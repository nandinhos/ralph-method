<?php

namespace App\Ralph;

use App\Models\FeatureProjection;
use Illuminate\Support\Facades\Process;
use RuntimeException;

final class RalphLauncher
{
    public function __construct(private readonly RalphRuntime $runtime) {}

    /**
     * @return array{ready: bool, reason: string, next_feature: ?string, next_title: ?string, running: bool, pauseable: bool, cursor_state: ?string, can_recover: bool, can_debug: bool, can_resume: bool}
     */
    public function decision(?string $workflowId): array
    {
        if ($workflowId === null || $workflowId === '') {
            return $this->blocked('cockpit.run.no_workflow');
        }

        if (preg_match('/^wf_[A-Za-z0-9_-]+$/', $workflowId) !== 1) {
            return $this->blocked('cockpit.run.no_workflow');
        }

        try {
            $root = $this->runtime->projectRoot();
        } catch (RuntimeException) {
            return $this->blocked('cockpit.run.no_root');
        }

        if ($this->runtime->controlBin() === null) {
            return $this->blocked('cockpit.run.no_control');
        }

        if (! is_file($this->runtime->workflowPath())) {
            return $this->blocked('cockpit.run.no_manifest');
        }

        $manifestId = $this->manifestWorkflowId();
        if ($manifestId === null || $manifestId !== $workflowId) {
            return $this->blocked('cockpit.run.workflow_mismatch');
        }

        if (! is_writable($root) || (is_dir($this->runtime->controlDir()) && ! is_writable($this->runtime->controlDir()))) {
            return $this->blocked('cockpit.run.root_readonly');
        }

        if ($this->supervisorBusy()) {
            return $this->blocked(
                'cockpit.run.already_running',
                $this->nextFeature($workflowId),
                running: true,
                pauseable: $this->ownsSupervisor($workflowId),
            );
        }

        $inside = Process::path($root)->run(['git', 'rev-parse', '--is-inside-work-tree']);
        if (! $inside->successful() || trim($inside->output()) !== 'true') {
            return $this->blocked('cockpit.run.git_unavailable');
        }

        $dirty = Process::path($root)->run(['git', 'status', '--porcelain']);
        if (! $dirty->successful()) {
            return $this->blocked('cockpit.run.git_unavailable');
        }
        if (trim($dirty->output()) !== '') {
            return $this->blocked('cockpit.run.dirty_tree');
        }

        $next = $this->nextFeature($workflowId);
        if ($next['key'] === null) {
            return $this->blocked('cockpit.run.queue_empty');
        }

        $cursorState = $this->controlCursorState($workflowId);
        $effective = $cursorState ?? $next['status'];
        if ($effective === 'debugging_required') {
            return $this->blocked('cockpit.run.debug_required', $next, cursorState: $effective);
        }
        if (in_array($effective, ['recovery_required', 'blocked'], true)) {
            return $this->blocked('cockpit.run.recovery_required', $next, cursorState: $effective);
        }

        if ($this->declaredInputMissing($next['key'])) {
            return $this->blocked('cockpit.run.plan_missing', $next, cursorState: $effective);
        }

        return [
            'ready' => true,
            'reason' => 'cockpit.run.ready',
            'next_feature' => $next['key'],
            'next_title' => $next['title'],
            'running' => false,
            'pauseable' => false,
            'cursor_state' => $cursorState,
            'can_recover' => false,
            'can_debug' => false,
            'can_resume' => false,
        ];
    }

    /**
     * @return array{started: bool, reason: string, pid: ?int}
     */
    public function start(string $workflowId): array
    {
        $decision = $this->decision($workflowId);
        if (! $decision['ready']) {
            return ['started' => false, 'reason' => $decision['reason'], 'pid' => null];
        }

        $bin = $this->runtime->controlBin();
        $root = $this->runtime->projectRoot();
        $log = storage_path('logs/ralph-supervise.log');

        $debug = $this->debugCommandLine();
        $debugArg = $debug !== null ? ' --debug-command '.escapeshellarg($debug) : '';
        $inner = sprintf(
            '%s %s supervise --workflow %s%s >> %s 2>&1 < /dev/null & echo $!',
            escapeshellarg(PHP_BINARY),
            escapeshellarg((string) $bin),
            escapeshellarg($workflowId),
            $debugArg,
            escapeshellarg($log),
        );

        $runner = is_executable('/usr/bin/setsid')
            ? ['setsid', 'sh', '-c', $inner]
            : ['sh', '-c', $inner];

        $process = Process::path($root)->timeout(3)->run($runner);
        $pid = (int) trim($process->output());
        if ($pid < 1) {
            return ['started' => false, 'reason' => 'cockpit.run.start_failed', 'pid' => null];
        }

        $this->writePidFile($pid, $workflowId);

        if (! Process::isRecording()) {
            usleep(1_500_000);
            if (! $this->pidAlive($pid)) {
                $this->clearPidFile();

                return ['started' => false, 'reason' => $this->exitReasonFromControllerAndStream($workflowId), 'pid' => null];
            }
        }

        return ['started' => true, 'reason' => 'cockpit.run.started', 'pid' => $pid];
    }

    /**
     * @return array{stopped: bool, reason: string}
     */
    public function pause(string $workflowId): array
    {
        $record = $this->pidRecord();
        if ($record === null) {
            if ($this->supervisorLockBusy()) {
                return ['stopped' => false, 'reason' => 'cockpit.run.pause_foreign'];
            }

            return ['stopped' => false, 'reason' => 'cockpit.run.not_running'];
        }

        $pid = $record['pid'];
        if ($record['workflow_id'] !== $workflowId) {
            return ['stopped' => false, 'reason' => 'cockpit.run.pause_failed'];
        }

        if (! $this->pidAlive($pid)) {
            $this->clearPidFile();

            return ['stopped' => false, 'reason' => 'cockpit.run.not_running'];
        }

        if (! $this->isSupervisePid($pid)) {
            return ['stopped' => false, 'reason' => 'cockpit.run.pause_failed'];
        }

        $stopped = $this->terminateSupervise($pid);
        $this->clearPidFile();

        return [
            'stopped' => $stopped,
            'reason' => $stopped ? 'cockpit.run.paused' : 'cockpit.run.pause_failed',
        ];
    }

    /**
     * @return array{debugged: bool, reason: string, report: array<string, mixed>}
     */
    public function debug(string $workflowId): array
    {
        $feature = $this->nextFeature($workflowId);
        $command = $this->debugCommandLine();
        if ($feature['key'] === null || $command === null) {
            return ['debugged' => false, 'reason' => 'cockpit.run.debug_missing', 'report' => $this->emptyReport()];
        }

        $bin = $this->runtime->controlBin();
        if ($bin === null) {
            return ['debugged' => false, 'reason' => 'cockpit.run.no_control', 'report' => $this->emptyReport()];
        }

        $result = Process::path($this->runtime->projectRoot())->timeout(60)->run([
            PHP_BINARY,
            $bin,
            'debug',
            '--workflow',
            $workflowId,
            '--feature',
            $feature['key'],
            '--command',
            $command,
        ]);
        $payload = json_decode($result->output(), true);
        $status = is_array($payload) ? (string) ($payload['status'] ?? '') : '';
        $report = $this->summarizeDebugPayload(is_array($payload) ? $payload : null, $workflowId);
        if ($status === 'debugging_verified') {
            FeatureProjection::query()
                ->where('workflow_id', $workflowId)
                ->where('feature_key', $feature['key'])
                ->update(['status' => 'pending']);

            return ['debugged' => true, 'reason' => 'cockpit.run.debugged', 'report' => $report];
        }

        return [
            'debugged' => false,
            'reason' => $status === 'debugging_required' ? 'cockpit.run.debug_required' : 'cockpit.run.debug_failed',
            'report' => $report,
        ];
    }

    /**
     * @return array{incident_id: string, symptom: string, root_cause: string, correction_plan: string, errors: list<string>}
     */
    public function latestDiagnosis(string $workflowId): array
    {
        $live = $this->runDiagnoseCommand($workflowId);
        if ($live['symptom'] !== '') {
            return $live;
        }

        $dir = $this->runtime->controlDir().DIRECTORY_SEPARATOR.'reports';
        $files = glob($dir.DIRECTORY_SEPARATOR.'DBG-*.json') ?: [];
        rsort($files);
        foreach ($files as $file) {
            $payload = json_decode((string) file_get_contents($file), true);
            if (! is_array($payload) || ($payload['workflow_id'] ?? null) !== $workflowId) {
                continue;
            }

            return $this->summarizeReportFile($payload, []);
        }

        return $this->emptyReport();
    }

    /**
     * @return array{recovered: bool, reason: string}
     */
    public function recover(string $workflowId): array
    {
        $feature = $this->nextFeature($workflowId);
        $state = $this->controlCursorState($workflowId) ?? $feature['status'];
        if ($feature['key'] === null || ! in_array($state, ['recovery_required', 'blocked'], true)) {
            return ['recovered' => false, 'reason' => 'cockpit.run.recover_unavailable'];
        }

        $bin = $this->runtime->controlBin();
        if ($bin === null) {
            return ['recovered' => false, 'reason' => 'cockpit.run.no_control'];
        }

        $result = Process::path($this->runtime->projectRoot())->timeout(20)->run([
            PHP_BINARY,
            $bin,
            'recover',
            '--workflow',
            $workflowId,
            '--feature',
            $feature['key'],
            '--reason',
            'cockpit: retomada do orquestrador',
        ]);
        $payload = json_decode($result->output(), true);
        if ($result->successful() && is_array($payload) && ($payload['status'] ?? null) === 'pending') {
            FeatureProjection::query()
                ->where('workflow_id', $workflowId)
                ->where('feature_key', $feature['key'])
                ->update(['status' => 'pending']);

            return ['recovered' => true, 'reason' => 'cockpit.run.recovered'];
        }

        return ['recovered' => false, 'reason' => 'cockpit.run.recover_failed'];
    }

    /**
     * @return array{started: bool, reason: string, pid: ?int}
     */
    public function resume(string $workflowId): array
    {
        $state = $this->controlCursorState($workflowId) ?? $this->nextFeature($workflowId)['status'];
        if ($state === 'debugging_required') {
            $debug = $this->debug($workflowId);
            $state = $this->controlCursorState($workflowId) ?? $state;
            if ($state === 'debugging_required' && ! $debug['debugged']) {
                return ['started' => false, 'reason' => $debug['reason'], 'pid' => null];
            }
        }

        if (in_array($state, ['recovery_required', 'blocked'], true)) {
            $recovered = $this->recover($workflowId);
            if (! $recovered['recovered']) {
                return ['started' => false, 'reason' => $recovered['reason'], 'pid' => null];
            }
        }

        return $this->start($workflowId);
    }

    public function debugCommandLine(): ?string
    {
        $configured = config('ralph.debug_command');
        $path = is_string($configured) && $configured !== ''
            ? $configured
            : base_path('bin/ralph-diagnose.php');
        if (! is_file($path)) {
            return null;
        }

        return PHP_BINARY.' '.$path;
    }

    /**
     * @return array{key: ?string, title: ?string, status: ?string}
     */
    public function nextFeature(string $workflowId): array
    {
        $feature = FeatureProjection::query()
            ->where('workflow_id', $workflowId)
            ->whereNotIn('status', ['released', 'approved'])
            ->orderBy('position')
            ->first();

        return [
            'key' => $feature?->feature_key,
            'title' => $feature?->title,
            'status' => $feature?->status,
        ];
    }

    public function supervisorBusy(): bool
    {
        $record = $this->pidRecord();
        if ($record !== null && $this->pidAlive($record['pid'])) {
            return true;
        }

        return $this->supervisorLockBusy();
    }

    public function ownsSupervisor(string $workflowId): bool
    {
        $record = $this->pidRecord();
        if ($record === null || $record['workflow_id'] !== $workflowId) {
            return false;
        }

        return $this->pidAlive($record['pid']) && $this->isSupervisePid($record['pid']);
    }

    private function supervisorLockBusy(): bool
    {
        $lockPath = $this->runtime->controlDir().DIRECTORY_SEPARATOR.'supervisor.lock';
        if (! is_file($lockPath)) {
            return false;
        }

        $handle = fopen($lockPath, 'c+');
        if ($handle === false) {
            return false;
        }

        $busy = ! flock($handle, LOCK_EX | LOCK_NB);
        if (! $busy) {
            flock($handle, LOCK_UN);
        }
        fclose($handle);

        return $busy;
    }

    private function terminateSupervise(int $pid): bool
    {
        if ($pid < 2 || $pid === getmypid()) {
            return false;
        }

        $pgid = function_exists('posix_getpgid') ? posix_getpgid($pid) : false;
        if (is_int($pgid) && $pgid > 1 && $pgid === $pid) {
            @posix_kill(-$pgid, 15);
        } else {
            @posix_kill($pid, 15);
        }

        $deadline = microtime(true) + 2.0;
        while (microtime(true) < $deadline) {
            if (! $this->pidAlive($pid)) {
                return true;
            }
            usleep(100_000);
        }

        @posix_kill($pid, 15);
        usleep(200_000);

        return ! $this->pidAlive($pid);
    }

    private function isSupervisePid(int $pid): bool
    {
        $cmdline = $this->pidCmdline($pid);

        return str_contains($cmdline, 'ralph-control') && str_contains($cmdline, 'supervise');
    }

    private function pidCmdline(int $pid): string
    {
        $path = '/proc/'.$pid.'/cmdline';
        if (! is_readable($path)) {
            return '';
        }

        $raw = file_get_contents($path);

        return $raw === false ? '' : str_replace("\0", ' ', $raw);
    }

    /**
     * @return array{pid: int, workflow_id: string}|null
     */
    private function pidRecord(): ?array
    {
        $path = $this->pidFile();
        if (! is_file($path)) {
            return null;
        }

        $raw = file_get_contents($path);
        if ($raw === false) {
            return null;
        }

        $decoded = json_decode($raw, true);
        if (is_array($decoded) && isset($decoded['pid'], $decoded['workflow_id'])) {
            $pid = (int) $decoded['pid'];
            $workflowId = (string) $decoded['workflow_id'];
            if ($pid > 1 && $workflowId !== '') {
                return ['pid' => $pid, 'workflow_id' => $workflowId];
            }

            return null;
        }

        $pid = (int) trim($raw);
        if ($pid < 2) {
            return null;
        }

        return ['pid' => $pid, 'workflow_id' => ''];
    }

    private function writePidFile(int $pid, string $workflowId): void
    {
        file_put_contents($this->pidFile(), json_encode([
            'pid' => $pid,
            'workflow_id' => $workflowId,
        ], JSON_THROW_ON_ERROR));
    }

    private function clearPidFile(): void
    {
        $path = $this->pidFile();
        if (is_file($path)) {
            unlink($path);
        }
    }

    private function controlCursorState(string $workflowId): ?string
    {
        $bin = $this->runtime->controlBin();
        if ($bin === null) {
            return null;
        }

        try {
            $root = $this->runtime->projectRoot();
        } catch (RuntimeException) {
            return null;
        }

        $result = Process::path($root)->timeout(8)->run([PHP_BINARY, $bin, 'status', '--workflow', $workflowId]);
        if (! $result->successful()) {
            return null;
        }

        $payload = json_decode($result->output(), true);
        if (! is_array($payload)) {
            return null;
        }

        $cursor = is_string(data_get($payload, 'projection.cursor')) ? data_get($payload, 'projection.cursor') : null;
        $features = data_get($payload, 'projection.features');
        if (! is_array($features)) {
            return null;
        }

        foreach ($features as $feature) {
            if (is_array($feature) && ($feature['feature_key'] ?? null) === $cursor) {
                return is_string($feature['state'] ?? null) ? $feature['state'] : null;
            }
        }

        return null;
    }

    private function exitReasonFromControllerAndStream(string $workflowId): string
    {
        $cursorState = $this->controlCursorState($workflowId);
        if ($cursorState === 'debugging_required') {
            return 'cockpit.run.debug_required';
        }

        if ($cursorState === 'recovery_required' || $cursorState === 'blocked') {
            $lastReason = $this->lastLedgerRecoveryReason($workflowId);
            if (str_contains($lastReason, 'exit_code') || str_contains($lastReason, 'retry_limit') || str_contains($lastReason, 'exit')) {
                return 'cockpit.run.block_failed';
            }

            return 'cockpit.run.recovery_required';
        }

        $lastEvent = $this->lastLedgerEvent($workflowId);
        if ($lastEvent !== null) {
            $type = (string) ($lastEvent['type'] ?? '');
            if ($type === 'debugging.required' || $type === 'debugging.rejected') {
                return 'cockpit.run.debug_required';
            }

            if ($type === 'recovery.required') {
                $reason = (string) data_get($lastEvent, 'facts.reason', '');
                $exitCode = data_get($lastEvent, 'facts.exit_code');
                if ($exitCode !== null || str_contains($reason, 'exit') || str_contains($reason, 'retry_limit')) {
                    return 'cockpit.run.block_failed';
                }

                return 'cockpit.run.recovery_required';
            }

            if ($type === 'workflow.completed') {
                return 'cockpit.run.queue_empty';
            }
        }

        $next = $this->nextFeature($workflowId);
        if ($next['key'] === null) {
            return 'cockpit.run.queue_empty';
        }

        return 'cockpit.run.start_failed';
    }

    private function lastLedgerRecoveryReason(string $workflowId): string
    {
        $ledgerPath = $this->runtime->ledgerPath();
        if (! is_file($ledgerPath)) {
            return '';
        }

        $reason = '';
        $handle = fopen($ledgerPath, 'r');
        if ($handle === false) {
            return '';
        }

        while (($line = fgets($handle)) !== false) {
            $event = json_decode($line, true);
            if (! is_array($event) || ($event['workflow_id'] ?? null) !== $workflowId || ($event['type'] ?? null) !== 'recovery.required') {
                continue;
            }
            $candidate = $event['facts']['reason'] ?? '';
            if (is_string($candidate) && $candidate !== '') {
                $reason = $candidate;
            }
        }
        fclose($handle);

        return $reason;
    }

    /**
     * @return array<string, mixed>|null
     */
    private function lastLedgerEvent(string $workflowId): ?array
    {
        $ledgerPath = $this->runtime->ledgerPath();
        if (! is_file($ledgerPath)) {
            return null;
        }

        $last = null;
        $handle = fopen($ledgerPath, 'r');
        if ($handle === false) {
            return null;
        }

        while (($line = fgets($handle)) !== false) {
            $event = json_decode($line, true);
            if (is_array($event) && ($event['workflow_id'] ?? null) === $workflowId) {
                $last = $event;
            }
        }
        fclose($handle);

        return $last;
    }

    /**
     * @return array{incident_id: string, symptom: string, root_cause: string, correction_plan: string, errors: list<string>}
     */
    private function runDiagnoseCommand(string $workflowId): array
    {
        $line = $this->debugCommandLine();
        if ($line === null) {
            return $this->emptyReport();
        }

        try {
            $root = $this->runtime->projectRoot();
        } catch (RuntimeException) {
            return $this->emptyReport();
        }

        $feature = $this->nextFeature($workflowId);
        $result = Process::path($root)
            ->timeout(8)
            ->env([
                'RALPH_DEBUG_WORKFLOW_ID' => $workflowId,
                'RALPH_DEBUG_FEATURE_KEY' => (string) ($feature['key'] ?? ''),
                'RALPH_DEBUG_ATTEMPT' => '0',
            ])
            ->run(['sh', '-c', $line]);
        $payload = json_decode($result->output(), true);
        if (! is_array($payload) || ($payload['status'] ?? null) !== 'verified') {
            return $this->emptyReport();
        }

        return $this->summarizeReportFile($payload, []);
    }

    /**
     * @param  array<string, mixed>|null  $payload
     * @return array{incident_id: string, symptom: string, root_cause: string, correction_plan: string, errors: list<string>}
     */
    private function summarizeDebugPayload(?array $payload, string $workflowId): array
    {
        $errors = [];
        foreach (is_array($payload['errors'] ?? null) ? $payload['errors'] : [] as $error) {
            if (is_string($error) && $this->safeDiagnosisText($error)) {
                $errors[] = $error;
            }
        }

        $fromDisk = $this->latestDiagnosis($workflowId);
        if ($fromDisk['symptom'] !== '') {
            $fromDisk['errors'] = $errors;

            return $fromDisk;
        }

        return $this->emptyReport($errors);
    }

    /**
     * @param  array<string, mixed>  $payload
     * @param  list<string>  $errors
     * @return array{incident_id: string, symptom: string, root_cause: string, correction_plan: string, errors: list<string>}
     */
    private function summarizeReportFile(array $payload, array $errors): array
    {
        $fields = [];
        foreach (['incident_id', 'symptom', 'root_cause', 'correction_plan'] as $field) {
            $value = is_string($payload[$field] ?? null) ? trim((string) $payload[$field]) : '';
            $fields[$field] = $this->safeDiagnosisText($value) ? $value : '';
        }

        return [
            'incident_id' => $fields['incident_id'],
            'symptom' => $fields['symptom'],
            'root_cause' => $fields['root_cause'],
            'correction_plan' => $fields['correction_plan'],
            'errors' => $errors,
        ];
    }

    /**
     * @param  list<string>  $errors
     * @return array{incident_id: string, symptom: string, root_cause: string, correction_plan: string, errors: list<string>}
     */
    private function emptyReport(array $errors = []): array
    {
        return [
            'incident_id' => '',
            'symptom' => '',
            'root_cause' => '',
            'correction_plan' => '',
            'errors' => $errors,
        ];
    }

    private function safeDiagnosisText(string $value): bool
    {
        if ($value === '' || strlen($value) > 600) {
            return false;
        }

        return preg_match('/-----BEGIN [A-Z ]*PRIVATE KEY-----|\b(?:api[_-]?key|access[_-]?token|password|passwd|secret)\s*[:=]|\b(?:sk|ghp|github_pat|glpat)-[A-Za-z0-9_-]{12,}\b|\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b/i', $value) !== 1;
    }

    private function manifestWorkflowId(): ?string
    {
        $manifest = $this->manifest();
        if ($manifest === null || ! is_string($manifest['workflow_id'] ?? null)) {
            return null;
        }

        return $manifest['workflow_id'];
    }

    private function declaredInputMissing(?string $featureKey): bool
    {
        $source = $this->declaredInput($featureKey);
        if ($source === '') {
            return false;
        }

        try {
            $root = $this->runtime->projectRoot();
        } catch (RuntimeException) {
            return false;
        }

        return ! is_file($root.DIRECTORY_SEPARATOR.ltrim($source, DIRECTORY_SEPARATOR));
    }

    private function declaredInput(?string $featureKey): string
    {
        $manifest = $this->manifest();
        if ($manifest === null) {
            return '';
        }

        foreach ($manifest['features'] ?? [] as $feature) {
            if (! is_array($feature) || ($feature['feature_key'] ?? null) !== $featureKey) {
                continue;
            }
            $input = $feature['input_file'] ?? null;
            if (is_string($input) && $input !== '') {
                return $input;
            }
        }

        $plan = $manifest['plan_file'] ?? null;

        return is_string($plan) ? $plan : '';
    }

    /**
     * @return array<string, mixed>|null
     */
    private function manifest(): ?array
    {
        $raw = file_get_contents($this->runtime->workflowPath());
        if ($raw === false) {
            return null;
        }

        $manifest = json_decode($raw, true);

        return is_array($manifest) ? $manifest : null;
    }

    private function pidAlive(int $pid): bool
    {
        if (function_exists('posix_kill')) {
            return posix_kill($pid, 0);
        }

        return is_dir('/proc/'.$pid);
    }

    private function pidFile(): string
    {
        return storage_path('app/ralph-supervise.pid');
    }

    /**
     * @param  array{key: ?string, title: ?string, status?: ?string}|null  $next
     * @return array{ready: bool, reason: string, next_feature: ?string, next_title: ?string, running: bool, pauseable: bool, cursor_state: ?string, can_recover: bool, can_debug: bool, can_resume: bool}
     */
    private function blocked(string $reason, ?array $next = null, bool $running = false, bool $pauseable = false, ?string $cursorState = null): array
    {
        $state = $cursorState ?? $next['status'] ?? null;
        $stuck = in_array($state, ['recovery_required', 'debugging_required', 'blocked'], true);

        return [
            'ready' => false,
            'reason' => $reason,
            'next_feature' => $next['key'] ?? null,
            'next_title' => $next['title'] ?? null,
            'running' => $running,
            'pauseable' => $pauseable,
            'cursor_state' => is_string($state) ? $state : null,
            'can_recover' => ! $running && in_array($state, ['recovery_required', 'blocked'], true),
            'can_debug' => ! $running && $stuck && $this->debugCommandLine() !== null,
            'can_resume' => ! $running && $stuck,
        ];
    }
}
