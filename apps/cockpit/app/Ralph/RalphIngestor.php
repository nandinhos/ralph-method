<?php

namespace App\Ralph;

use App\Events\CockpitUpdated;
use App\Models\DelegationNode;
use App\Models\FeatureProjection;
use App\Models\GateProjection;
use App\Models\IngestCursor;
use App\Models\KnowledgeItem;
use App\Models\TimelineEvent;
use App\Models\WorkflowProjection;
use Carbon\CarbonImmutable;
use Illuminate\Support\Facades\Process;

final class RalphIngestor
{
    public function __construct(private readonly RalphRuntime $runtime) {}

    /**
     * @return list<string>
     */
    public function rebuild(): array
    {
        DelegationNode::query()->delete();
        KnowledgeItem::query()->delete();
        TimelineEvent::query()->delete();
        GateProjection::query()->delete();
        FeatureProjection::query()->delete();
        WorkflowProjection::query()->delete();
        IngestCursor::query()->delete();

        return $this->tick();
    }

    /**
     * @return list<string>
     */
    public function tick(): array
    {
        $changed = [];

        $this->ingestWorkflowManifest($changed);
        $this->ingestJsonl('ledger', $this->runtime->ledgerPath(), $changed);
        $this->ingestJsonl('feedback', $this->runtime->feedbackPath(), $changed);
        $this->ingestKnowledge($changed);
        $this->ingestMonitor($changed);
        $this->ensureRootDelegations($changed);

        return array_values(array_unique($changed));
    }

    public function broadcast(array $workflowIds): void
    {
        foreach ($workflowIds as $workflowId) {
            CockpitUpdated::dispatch($workflowId);
        }
    }

    /**
     * @param  list<string>  $changed
     */
    private function ingestWorkflowManifest(array &$changed): void
    {
        $path = $this->runtime->workflowPath();
        if (! is_file($path)) {
            return;
        }

        $payload = json_decode((string) file_get_contents($path), true);
        if (! is_array($payload)) {
            return;
        }

        $workflowId = is_string($payload['workflow_id'] ?? null) ? $payload['workflow_id'] : null;
        if ($workflowId === null || $workflowId === '') {
            return;
        }

        $this->touchWorkflow($workflowId);
        $features = is_array($payload['features'] ?? null) ? $payload['features'] : [];
        foreach ($features as $index => $feature) {
            if (! is_array($feature)) {
                continue;
            }
            $key = is_string($feature['feature_key'] ?? null) ? $feature['feature_key'] : null;
            if ($key === null) {
                continue;
            }
            $attributes = [
                'title' => is_string($feature['title'] ?? null) ? $feature['title'] : $key,
                'position' => is_numeric($feature['position'] ?? null) ? (int) $feature['position'] : ($index + 1),
            ];
            $exists = FeatureProjection::query()
                ->where('workflow_id', $workflowId)
                ->where('feature_key', $key)
                ->exists();
            if (! $exists) {
                $attributes['status'] = is_string($feature['status'] ?? null) ? $feature['status'] : 'pending';
            }
            $this->upsertFeature($workflowId, $key, $attributes);
            $this->seedGates($workflowId, $key);
        }
        $changed[] = $workflowId;
    }

    /**
     * @param  list<string>  $changed
     */
    private function ingestJsonl(string $source, string $path, array &$changed): void
    {
        if (! is_file($path)) {
            return;
        }

        $cursor = IngestCursor::query()->firstOrCreate(
            ['source_key' => $source],
            ['byte_offset' => 0],
        );

        $handle = fopen($path, 'rb');
        if ($handle === false) {
            return;
        }

        $offset = (int) $cursor->byte_offset;
        if ($offset > 0) {
            fseek($handle, $offset);
        }

        while (($line = fgets($handle)) !== false) {
            $offset = ftell($handle) ?: $offset;
            $trimmed = trim($line);
            if ($trimmed === '') {
                continue;
            }
            try {
                $event = json_decode($trimmed, true, 512, JSON_THROW_ON_ERROR);
            } catch (\JsonException) {
                continue;
            }
            if (! is_array($event)) {
                continue;
            }
            $workflowId = $this->applyEvent($source, $event);
            if ($workflowId !== null) {
                $changed[] = $workflowId;
            }
        }

        $cursor->forceFill([
            'byte_offset' => $offset,
            'last_hash' => hash_file('sha256', $path) ?: null,
        ])->save();
        fclose($handle);
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function applyEvent(string $source, array $event): ?string
    {
        $workflowId = is_string($event['workflow_id'] ?? null) ? $event['workflow_id'] : null;
        if ($workflowId === null || $workflowId === '') {
            return null;
        }

        $this->touchWorkflow($workflowId, $event);
        $this->recordTimeline($source, $workflowId, $event);

        if ($source === 'feedback') {
            $this->applyFeedback($workflowId, $event);

            return $workflowId;
        }

        $type = is_string($event['type'] ?? null) ? $event['type'] : '';
        $featureKey = is_string($event['feature_key'] ?? null) ? $event['feature_key'] : null;

        if ($featureKey !== null && $featureKey !== 'workflow' && $type !== 'workflow.initialized') {
            $this->applyFeatureEvent($workflowId, $featureKey, $type, $event);
        }

        if (str_starts_with($type, 'gate.')) {
            $this->applyGateEvent($workflowId, $featureKey, $type, $event);
        }

        if ($type === 'recovery.required') {
            WorkflowProjection::query()->where('workflow_id', $workflowId)->increment('recovery_count');
        }

        if ($type === 'debugging.verified') {
            $this->ingestDebugKnowledge($workflowId, $featureKey, $event);
        }

        if ($type === 'knowledge.telemetry') {
            $this->applyKnowledgeTelemetry($workflowId, $featureKey, $event);
        }

        if (str_contains($type, 'delegation') || $type === 'attempt.started') {
            $this->applyDelegation($workflowId, $event);
        }

        return $workflowId;
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function applyFeedback(string $workflowId, array $event): void
    {
        $progress = is_array($event['progress'] ?? null) ? $event['progress'] : [];
        $percent = is_numeric($progress['percent'] ?? null) ? (int) $progress['percent'] : null;
        $engine = is_string($event['engine'] ?? null) ? $event['engine'] : null;
        $state = is_string($event['state'] ?? null) ? $event['state'] : null;
        $attempt = is_numeric($event['attempt'] ?? null) ? (int) $event['attempt'] : null;
        $featureKey = is_string($event['feature_key'] ?? null) ? $event['feature_key'] : null;

        $updates = array_filter([
            'engine' => $engine,
            'state' => $state,
            'attempt' => $attempt,
            'cursor_feature_key' => $featureKey,
            'progress_percent' => $percent,
        ], fn ($value) => $value !== null);

        if ($updates !== []) {
            WorkflowProjection::query()->where('workflow_id', $workflowId)->update($updates);
        }

        if ($featureKey !== null && $engine !== null) {
            $current = FeatureProjection::query()
                ->where('workflow_id', $workflowId)
                ->where('feature_key', $featureKey)
                ->value('status');
            $status = null;
            if ($state === 'completed') {
                $status = 'released';
            } elseif ($state === 'running' && ! in_array($current, ['released', 'approved'], true)) {
                $status = 'running';
            }

            FeatureProjection::query()
                ->where('workflow_id', $workflowId)
                ->where('feature_key', $featureKey)
                ->update(array_filter([
                    'engine' => $engine,
                    'attempt' => $attempt,
                    'status' => $status,
                ], fn ($value) => $value !== null));

            $this->applyDelegation($workflowId, array_merge($event, [
                'facts' => ['runner' => $engine],
            ]), $state === 'completed' ? 'ok' : 'running');
        }
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function applyFeatureEvent(string $workflowId, string $featureKey, string $type, array $event): void
    {
        $status = match ($type) {
            'block.finished' => 'running',
            'feature.claimed', 'attempt.started' => 'running',
            'feature.released' => 'released',
            'feature.approved' => 'approved',
            'recovery.required', 'debugging.required', 'debugging.rejected' => 'blocked',
            'debugging.verified' => 'pending',
            default => null,
        };

        $this->upsertFeature($workflowId, $featureKey, array_filter([
            'status' => $status,
            'engine' => is_string($event['engine'] ?? null) ? $event['engine'] : (is_string(data_get($event, 'facts.runner')) ? data_get($event, 'facts.runner') : null),
            'attempt' => is_numeric($event['attempt'] ?? null) ? (int) $event['attempt'] : null,
        ], fn ($value) => $value !== null));
        $this->seedGates($workflowId, $featureKey);

        $runner = is_string($event['engine'] ?? null)
            ? $event['engine']
            : (is_string(data_get($event, 'facts.runner')) ? (string) data_get($event, 'facts.runner') : null);
        if ($runner !== null && $runner !== '') {
            $delegationState = match ($type) {
                'feature.released', 'block.finished' => 'ok',
                default => 'running',
            };
            $this->applyDelegation($workflowId, array_merge($event, [
                'facts' => ['runner' => $runner],
            ]), $delegationState);
        }
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function ingestDebugKnowledge(string $workflowId, ?string $featureKey, array $event): void
    {
        $documentId = is_string(data_get($event, 'facts.document_id')) ? (string) data_get($event, 'facts.document_id') : '';
        $title = is_string(data_get($event, 'facts.knowledge_candidate.title'))
            ? (string) data_get($event, 'facts.knowledge_candidate.title')
            : (is_string(data_get($event, 'facts.incident_id')) ? (string) data_get($event, 'facts.incident_id') : '');
        $subtitle = is_string(data_get($event, 'facts.root_cause')) ? (string) data_get($event, 'facts.root_cause') : '';
        if ($documentId === '' || $title === '' || strlen($title) > 180 || strlen($subtitle) > 400) {
            return;
        }

        KnowledgeItem::query()->updateOrCreate(
            ['item_key' => $documentId],
            [
                'workflow_id' => $workflowId,
                'feature_key' => $featureKey,
                'title' => $title,
                'subtitle' => $subtitle !== '' ? $subtitle : 'verified',
                'status' => 'verified',
            ],
        );
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function applyGateEvent(string $workflowId, ?string $featureKey, string $type, array $event): void
    {
        if ($featureKey === null) {
            return;
        }

        $facts = is_array($event['facts'] ?? null) ? $event['facts'] : [];
        $gateKey = GateCatalog::normalize(is_string($facts['gate'] ?? null) ? $facts['gate'] : null);
        if ($gateKey === null) {
            return;
        }

        $status = match ($type) {
            'gate.passed' => 'passed',
            'gate.rejected', 'gate.failed' => 'failed',
            'gate.stalled' => 'stalled',
            'gate.started' => 'running',
            default => 'pending',
        };

        $detail = is_string($event['summary'] ?? null) ? $event['summary'] : null;
        if ($type === 'gate.stalled' && is_numeric($facts['age_seconds'] ?? null)) {
            $detail = $detail ?: sprintf('stalled (%ds)', (int) $facts['age_seconds']);
        }

        GateProjection::query()->updateOrCreate(
            [
                'workflow_id' => $workflowId,
                'feature_key' => $featureKey,
                'gate_key' => $gateKey,
            ],
            [
                'status' => $status,
                'detail' => $detail,
            ],
        );
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function applyKnowledgeTelemetry(string $workflowId, ?string $featureKey, array $event): void
    {
        $facts = is_array($event['facts'] ?? null) ? $event['facts'] : [];
        $curationId = is_string($facts['curation_id'] ?? null)
            ? $facts['curation_id']
            : (is_string($facts['candidate_id'] ?? null) ? $facts['candidate_id'] : null);
        if ($curationId === null || $curationId === '') {
            return;
        }

        $title = is_string($facts['title'] ?? null) && $facts['title'] !== ''
            ? $facts['title']
            : ($featureKey ?: $curationId);
        $status = is_string($facts['status'] ?? null)
            ? $facts['status']
            : (is_string($facts['decision'] ?? null) ? $facts['decision'] : 'pending');
        $subtitle = trim(sprintf(
            '%s · %s%s',
            $curationId,
            $featureKey ?: $workflowId,
            is_string($facts['category'] ?? null) && $facts['category'] !== '' ? ' · '.$facts['category'] : ''
        ));

        KnowledgeItem::query()->updateOrCreate(
            ['item_key' => $curationId],
            [
                'workflow_id' => $workflowId,
                'feature_key' => $featureKey,
                'title' => $title,
                'subtitle' => $subtitle,
                'status' => $status,
            ],
        );
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function applyDelegation(string $workflowId, array $event, string $state = 'running'): void
    {
        $runner = is_string(data_get($event, 'facts.runner'))
            ? (string) data_get($event, 'facts.runner')
            : (is_string($event['engine'] ?? null) ? (string) $event['engine'] : null);

        if ($runner === null || $runner === '') {
            return;
        }

        DelegationNode::query()->updateOrCreate(
            [
                'workflow_id' => $workflowId,
                'role' => 'runner',
                'label' => $runner,
            ],
            [
                'detail' => __('cockpit.delegation.implementation'),
                'state' => $state,
                'position' => 1,
            ],
        );
    }

    /**
     * @param  list<string>  $changed
     */
    private function ingestKnowledge(array &$changed): void
    {
        $dir = $this->runtime->knowledgeDir();
        if (! is_dir($dir)) {
            return;
        }

        foreach (glob($dir.DIRECTORY_SEPARATOR.'*.json') ?: [] as $file) {
            $payload = json_decode((string) file_get_contents($file), true);
            if (! is_array($payload)) {
                continue;
            }
            $workflowId = is_string($payload['workflow_id'] ?? null) ? $payload['workflow_id'] : null;
            $curationId = is_string($payload['curation_id'] ?? null) ? $payload['curation_id'] : basename($file, '.json');
            $featureKey = is_string($payload['feature_key'] ?? null) ? $payload['feature_key'] : null;
            if ($workflowId === null || $curationId === '') {
                continue;
            }

            $handoff = is_string(data_get($payload, 'source.handoff_path'))
                ? basename(str_replace('\\', '/', (string) data_get($payload, 'source.handoff_path')))
                : '';
            $retention = is_string($payload['retention'] ?? null) ? $payload['retention'] : 'ask';
            $status = is_string($payload['status'] ?? null) ? $payload['status'] : 'pending';
            $title = $featureKey ?: $curationId;
            $subtitle = trim(sprintf(
                '%s · %s · retention=%s',
                $curationId,
                $handoff !== '' ? $handoff : $workflowId,
                $retention,
            ));

            $item = KnowledgeItem::query()->updateOrCreate(
                ['item_key' => $curationId],
                [
                    'workflow_id' => $workflowId,
                    'feature_key' => $featureKey,
                    'title' => $title,
                    'subtitle' => $subtitle,
                    'status' => $status,
                ],
            );

            $createdAt = is_string($payload['created_at'] ?? null) ? $payload['created_at'] : null;
            if ($createdAt !== null) {
                try {
                    $item->forceFill(['created_at' => CarbonImmutable::parse($createdAt)])->save();
                } catch (\Throwable) {
                    //
                }
            }

            $changed[] = $workflowId;
        }
    }

    /**
     * @param  list<string>  $changed
     */
    private function ingestMonitor(array &$changed): void
    {
        $bin = $this->runtime->monitorBin();
        $controller = $this->runtime->controlBin();
        if ($bin === null) {
            return;
        }

        $workflowIds = WorkflowProjection::query()->pluck('workflow_id');
        foreach ($workflowIds as $workflowId) {
            $command = [
                PHP_BINARY,
                $bin,
                '--root',
                $this->runtime->projectRoot(),
                '--workflow',
                (string) $workflowId,
                '--once',
                '--json',
            ];
            if ($controller !== null) {
                $command[] = '--controller';
                $command[] = $controller;
            }

            $result = Process::timeout(8)->run($command);
            if (! $result->successful()) {
                continue;
            }
            try {
                $snapshot = json_decode($result->output(), true, 512, JSON_THROW_ON_ERROR);
            } catch (\JsonException) {
                continue;
            }
            if (! is_array($snapshot)) {
                continue;
            }

            $progress = is_array($snapshot['progress'] ?? null) ? $snapshot['progress'] : [];
            WorkflowProjection::query()->where('workflow_id', $workflowId)->update(array_filter([
                'health' => is_string($snapshot['health'] ?? null) ? $snapshot['health'] : null,
                'state' => is_string($snapshot['state'] ?? null) ? $snapshot['state'] : null,
                'cursor_feature_key' => is_string($snapshot['cursor'] ?? null) ? $snapshot['cursor'] : null,
                'progress_percent' => is_numeric($progress['estimated_percent'] ?? null) ? (int) $progress['estimated_percent'] : null,
                'attempt' => is_numeric($snapshot['attempt'] ?? null) ? (int) $snapshot['attempt'] : null,
                'monitor_payload' => $snapshot,
            ], fn ($value) => $value !== null));
            $changed[] = (string) $workflowId;
        }
    }

    /**
     * @param  list<string>  $changed
     */
    private function ensureRootDelegations(array &$changed): void
    {
        foreach (WorkflowProjection::query()->pluck('workflow_id') as $workflowId) {
            $node = DelegationNode::query()->firstOrCreate(
                [
                    'workflow_id' => $workflowId,
                    'role' => 'root',
                    'label' => 'ralph-control',
                ],
                [
                    'detail' => __('cockpit.delegation.root'),
                    'state' => 'root',
                    'position' => 0,
                ],
            );
            if ($node->wasRecentlyCreated) {
                $changed[] = (string) $workflowId;
            }
        }
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function touchWorkflow(string $workflowId, array $event = []): WorkflowProjection
    {
        $type = is_string($event['type'] ?? null)
            ? $event['type']
            : (is_string($event['event'] ?? null) ? $event['event'] : '');
        $occurred = $this->timestamp($event['timestamp'] ?? null);

        $workflow = WorkflowProjection::query()->firstOrCreate(
            ['workflow_id' => $workflowId],
        );

        if ($occurred !== null && ! $this->isTimelineNoise($type)) {
            $workflow->last_event_at = $occurred;
            if ($workflow->started_at === null) {
                $workflow->started_at = $occurred;
            }
        }

        if (is_string($event['engine'] ?? null)) {
            $workflow->engine = $event['engine'];
        }

        $workflow->save();

        return $workflow;
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    private function upsertFeature(string $workflowId, string $featureKey, array $attributes): void
    {
        FeatureProjection::query()->updateOrCreate(
            [
                'workflow_id' => $workflowId,
                'feature_key' => $featureKey,
            ],
            $attributes,
        );
    }

    private function seedGates(string $workflowId, string $featureKey): void
    {
        foreach (GateCatalog::KEYS as $gateKey) {
            GateProjection::query()->firstOrCreate(
                [
                    'workflow_id' => $workflowId,
                    'feature_key' => $featureKey,
                    'gate_key' => $gateKey,
                ],
                ['status' => 'pending'],
            );
        }
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function recordTimeline(string $source, string $workflowId, array $event): void
    {
        $name = is_string($event['type'] ?? null)
            ? $event['type']
            : (is_string($event['event'] ?? null) ? $event['event'] : 'event');

        if ($this->isTimelineNoise($name)) {
            return;
        }
        $eventId = is_string($event['event_id'] ?? null)
            ? $event['event_id']
            : (is_string($event['run_id'] ?? null) ? $event['run_id'].':'.$name.':'.($event['timestamp'] ?? '') : sha1(json_encode($event) ?: $name));
        $detail = is_string($event['summary'] ?? null) && $event['summary'] !== ''
            ? $event['summary']
            : (is_string($event['detail'] ?? null) && $event['detail'] !== ''
                ? $event['detail']
                : (is_string(data_get($event, 'facts.activity_preview'))
                    ? (string) data_get($event, 'facts.activity_preview')
                    : (is_string(data_get($event, 'facts.hypothesis'))
                        ? (string) data_get($event, 'facts.hypothesis')
                        : null)));

        TimelineEvent::query()->updateOrCreate(
            ['event_key' => $source.':'.$eventId],
            [
                'source' => $source,
                'workflow_id' => $workflowId,
                'feature_key' => is_string($event['feature_key'] ?? null) ? $event['feature_key'] : null,
                'kind' => str_starts_with($name, 'gate.') ? 'gates' : 'events',
                'name' => $name,
                'detail' => $detail,
                'engine' => is_string($event['engine'] ?? null) ? $event['engine'] : null,
                'occurred_at' => $this->timestamp($event['timestamp'] ?? null),
            ],
        );
    }

    private function timestamp(mixed $value): ?CarbonImmutable
    {
        if (! is_string($value) || $value === '') {
            return null;
        }

        try {
            return CarbonImmutable::parse($value)->timezone(config('app.timezone'));
        } catch (\Throwable) {
            return null;
        }
    }

    private function isTimelineNoise(string $name): bool
    {
        return $name === 'command.heartbeat';
    }
}
