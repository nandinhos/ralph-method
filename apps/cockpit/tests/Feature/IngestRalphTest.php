<?php

use App\Models\DelegationNode;
use App\Models\FeatureProjection;
use App\Models\GateProjection;
use App\Models\KnowledgeItem;
use App\Models\TimelineEvent;
use App\Models\WorkflowProjection;
use App\Ralph\RalphIngestor;
use Illuminate\Support\Facades\File;

function cockpitFixtureRoot(): string
{
    $root = storage_path('framework/testing/ralph-project');
    File::deleteDirectory($root);
    File::ensureDirectoryExists($root.'/.git/ralph-control/feedback');
    File::ensureDirectoryExists($root.'/.ralph/knowledge-candidates');

    File::put($root.'/.git/ralph-control/workflow.json', json_encode([
        'schema_version' => '1.0.0',
        'workflow_id' => 'wf_cockpit_demo',
        'features' => [
            ['feature_key' => 'FEATURE-091', 'title' => 'Detectar legado', 'position' => 1, 'status' => 'pending'],
            ['feature_key' => 'FEATURE-092', 'title' => 'Evoluir hashes', 'position' => 2, 'status' => 'pending'],
        ],
    ], JSON_THROW_ON_ERROR));

    File::put($root.'/.git/ralph-control/events.jsonl', implode("\n", [
        '{"schema_version":"1.1.0","event_id":"evt-001","workflow_id":"wf_cockpit_demo","feature_key":"FEATURE-091","attempt":1,"type":"feature.claimed","timestamp":"2026-08-16T12:00:00Z","engine":"cursor","summary":"lease adquirido"}',
        '{"schema_version":"1.1.0","event_id":"evt-002","workflow_id":"wf_cockpit_demo","feature_key":"FEATURE-091","attempt":1,"type":"gate.passed","timestamp":"2026-08-16T12:01:00Z","facts":{"gate":"quality"},"summary":"163 asserts"}',
        '{"schema_version":"1.1.0","event_id":"evt-003","workflow_id":"wf_cockpit_demo","feature_key":"FEATURE-091","attempt":1,"type":"feature.released","timestamp":"2026-08-16T12:02:00Z","engine":"cursor"}',
        '{"schema_version":"1.1.0","event_id":"evt-004","workflow_id":"wf_cockpit_demo","feature_key":"FEATURE-092","attempt":1,"type":"feature.claimed","timestamp":"2026-08-16T12:03:00Z","engine":"cursor"}',
    ])."\n");

    File::put($root.'/.git/ralph-control/feedback/events.jsonl', '{"schema_version":"1.0.0","run_id":"run-1","workflow_id":"wf_cockpit_demo","feature_key":"FEATURE-092","attempt":1,"timestamp":"2026-08-16T12:03:10Z","event":"phase_start","state":"running","health":"ok","engine":"cursor","phase":{"number":1,"total":3,"title":"Implementar","attempt":1},"progress":{"percent":42},"detail":"fase em curso","source":"ralph"}'."\n");

    File::put($root.'/.ralph/knowledge-candidates/CUR-2026-0099.json', json_encode([
        'schema_version' => '1.0.0',
        'curation_id' => 'CUR-2026-0099',
        'workflow_id' => 'wf_cockpit_demo',
        'feature_key' => 'FEATURE-091',
        'attempt' => 1,
        'status' => 'pending',
        'retention' => 'ask',
        'source' => [
            'release_event_id' => 'evt_demo_release',
            'handoff_path' => '.ralph/handoffs/FEATURE-091-DEMO',
        ],
        'created_at' => '2026-08-16T11:59:00Z',
    ], JSON_THROW_ON_ERROR));

    return $root;
}

it('projeta workflow, features, gates e timeline a partir dos JSONL', function () {
    $root = cockpitFixtureRoot();
    config(['ralph.project_root' => $root, 'ralph.monitor_bin' => null]);

    $changed = app(RalphIngestor::class)->rebuild();

    expect($changed)->toContain('wf_cockpit_demo')
        ->and(WorkflowProjection::query()->where('workflow_id', 'wf_cockpit_demo')->value('engine'))->toBe('cursor')
        ->and(WorkflowProjection::query()->where('workflow_id', 'wf_cockpit_demo')->value('progress_percent'))->toBe(42)
        ->and(FeatureProjection::query()->where('feature_key', 'FEATURE-091')->value('status'))->toBe('released')
        ->and(FeatureProjection::query()->where('feature_key', 'FEATURE-092')->value('status'))->toBe('running')
        ->and(GateProjection::query()->where('feature_key', 'FEATURE-091')->where('gate_key', 'quality')->value('status'))->toBe('passed')
        ->and(TimelineEvent::query()->where('name', 'feature.claimed')->count())->toBe(2)
        ->and(KnowledgeItem::query()->where('item_key', 'CUR-2026-0099')->value('title'))->toBe('FEATURE-091')
        ->and(DelegationNode::query()->where('role', 'runner')->where('label', 'cursor')->value('state'))->toBe('running')
        ->and(DelegationNode::query()->where('role', 'root')->where('label', 'ralph-control')->exists())->toBeTrue();
});

it('projeta gate rejeitado com classe visual de falha', function () {
    $root = cockpitFixtureRoot();
    File::append($root.'/.git/ralph-control/events.jsonl', "\n".json_encode([
        'schema_version' => '1.1.0',
        'event_id' => 'evt-fail',
        'workflow_id' => 'wf_cockpit_demo',
        'feature_key' => 'FEATURE-092',
        'attempt' => 1,
        'type' => 'gate.rejected',
        'timestamp' => '2026-08-16T12:04:00Z',
        'facts' => ['gate' => 'validation'],
        'summary' => 'contrato violado',
    ], JSON_THROW_ON_ERROR));
    config(['ralph.project_root' => $root, 'ralph.monitor_bin' => null]);

    app(RalphIngestor::class)->rebuild();

    expect(GateProjection::query()
        ->where('feature_key', 'FEATURE-092')
        ->where('gate_key', 'validation')
        ->value('status'))->toBe('failed')
        ->and(\App\Ralph\GateCatalog::visualClass('failed'))->toBe('is-fail');
});

it('é idempotente no segundo tick', function () {
    $root = cockpitFixtureRoot();
    config(['ralph.project_root' => $root, 'ralph.monitor_bin' => null]);

    $ingestor = app(RalphIngestor::class);
    $ingestor->rebuild();
    $ingestor->tick();

    expect(TimelineEvent::query()->count())->toBe(5)
        ->and(FeatureProjection::query()->count())->toBe(2);
});

it('não expõe rotas de mutação do control plane', function () {
    $uris = collect(app('router')->getRoutes())->map(fn ($route) => implode('|', $route->methods()).' '.$route->uri());

    expect($uris->implode("\n"))
        ->not->toContain('approve')
        ->not->toContain('retry')
        ->not->toContain('recover')
        ->not->toContain('advance')
        ->not->toContain('ralph-control');
});

it('ignora heartbeats na timeline operacional', function () {
    $root = cockpitFixtureRoot();
    File::append($root.'/.git/ralph-control/events.jsonl', "\n".implode("\n", [
        json_encode([
            'schema_version' => '1.1.0',
            'event_id' => 'evt-hb-1',
            'workflow_id' => 'wf_cockpit_demo',
            'type' => 'command.heartbeat',
            'timestamp' => '2026-08-16T12:05:00Z',
            'summary' => 'Heartbeat do processo controlado',
        ], JSON_THROW_ON_ERROR),
        json_encode([
            'schema_version' => '1.1.0',
            'event_id' => 'evt-hb-2',
            'workflow_id' => 'wf_cockpit_demo',
            'type' => 'command.heartbeat',
            'timestamp' => '2026-08-16T12:05:15Z',
            'summary' => 'Heartbeat do processo controlado',
        ], JSON_THROW_ON_ERROR),
    ]));
    config(['ralph.project_root' => $root, 'ralph.monitor_bin' => null]);

    app(RalphIngestor::class)->rebuild();

    expect(TimelineEvent::query()->where('name', 'command.heartbeat')->count())->toBe(0)
        ->and(TimelineEvent::query()->count())->toBe(5);
});

it('formata timestamps da timeline no fuso da aplicação', function () {
    $root = cockpitFixtureRoot();
    File::append($root.'/.git/ralph-control/events.jsonl', "\n".json_encode([
        'schema_version' => '1.1.0',
        'event_id' => 'evt-tz',
        'workflow_id' => 'wf_cockpit_demo',
        'feature_key' => 'FEATURE-091',
        'attempt' => 1,
        'type' => 'attempt.started',
        'timestamp' => '2026-08-16T07:29:45Z',
        'summary' => 'tentativa iniciada',
    ], JSON_THROW_ON_ERROR));
    config(['app.timezone' => 'America/Sao_Paulo', 'ralph.project_root' => $root, 'ralph.monitor_bin' => null]);

    app(RalphIngestor::class)->rebuild();

    expect(TimelineEvent::query()->where('name', 'attempt.started')->value('occurred_at')?->format('H:i:s'))
        ->toBe('04:29:45');
});
