#!/usr/bin/env php
<?php

declare(strict_types=1);

function parserFail(string $message): never
{
    fwrite(STDERR, "agy parser: {$message}\n");
    exit(2);
}

/** @return array<string, string> */
function parserOptions(array $arguments): array
{
    $options = [];
    for ($index = 0; $index < count($arguments); $index++) {
        $argument = $arguments[$index];
        if (! str_starts_with($argument, '--')) {
            parserFail("argumento inesperado: {$argument}");
        }
        $name = substr($argument, 2);
        $value = $arguments[++$index] ?? null;
        if ($value === null || str_starts_with($value, '--')) {
            parserFail("--{$name} exige valor");
        }
        $options[$name] = $value;
    }

    return $options;
}

function parserRequired(array $options, string $name): string
{
    $value = trim((string) ($options[$name] ?? ''));
    if ($value === '') {
        parserFail("--{$name} obrigatório");
    }

    return $value;
}

function writePrivate(string $path, string $content): void
{
    $directory = dirname($path);
    if (! is_dir($directory) && ! mkdir($directory, 0700, true) && ! is_dir($directory)) {
        parserFail("não foi possível criar {$directory}");
    }
    $temporary = $path.'.tmp.'.bin2hex(random_bytes(4));
    if (file_put_contents($temporary, $content, LOCK_EX) === false || ! rename($temporary, $path)) {
        @unlink($temporary);
        parserFail("não foi possível publicar {$path}");
    }
    @chmod($path, 0600);
}

function pathInsideRoot(string $candidate, string $root): bool
{
    if (! str_starts_with($candidate, '/')) {
        $candidate = $root.'/'.$candidate;
    }
    $segments = [];
    foreach (explode('/', $candidate) as $segment) {
        if ($segment === '' || $segment === '.') {
            continue;
        }
        if ($segment === '..') {
            array_pop($segments);
            continue;
        }
        $segments[] = $segment;
    }
    $normalized = '/'.implode('/', $segments);

    return $normalized === $root || str_starts_with($normalized, $root.'/');
}

function verifyToolParameters(string $tool, mixed $parameters, string $root): bool
{
    if (! is_array($parameters) || array_is_list($parameters)) {
        return false;
    }
    $contracts = [
        'view_file' => ['required' => ['AbsolutePath'], 'allowed' => ['AbsolutePath', 'StartLine', 'EndLine'], 'paths' => ['AbsolutePath']],
        'list_dir' => ['required' => ['DirectoryPath'], 'allowed' => ['DirectoryPath'], 'paths' => ['DirectoryPath']],
        'grep_search' => ['required' => ['Query', 'SearchPath'], 'allowed' => ['Query', 'SearchPath'], 'paths' => ['SearchPath']],
        'find_by_name' => ['required' => ['Pattern', 'SearchDirectory'], 'allowed' => ['Pattern', 'SearchDirectory'], 'paths' => ['SearchDirectory']],
    ];
    $contract = $contracts[$tool] ?? null;
    if (! is_array($contract)
        || array_diff(array_keys($parameters), $contract['allowed']) !== []
        || array_diff($contract['required'], array_keys($parameters)) !== []) {
        return false;
    }
    foreach ($contract['paths'] as $pathKey) {
        $path = $parameters[$pathKey] ?? null;
        if (! is_string($path) || $path === '' || ! pathInsideRoot($path, $root)) {
            return false;
        }
    }
    foreach (['Query', 'Pattern'] as $textKey) {
        if (array_key_exists($textKey, $parameters)
            && (! is_string($parameters[$textKey]) || $parameters[$textKey] === '')) {
            return false;
        }
    }
    foreach (['StartLine', 'EndLine'] as $lineKey) {
        if (array_key_exists($lineKey, $parameters)
            && (! is_int($parameters[$lineKey]) || $parameters[$lineKey] < 1)) {
            return false;
        }
    }

    return true;
}

function verifyToolPath(string $tool, mixed $parameters): ?string
{
    if (! is_array($parameters)) {
        return null;
    }
    $pathKeys = [
        'view_file' => 'AbsolutePath',
        'list_dir' => 'DirectoryPath',
        'grep_search' => 'SearchPath',
        'find_by_name' => 'SearchDirectory',
    ];
    $pathKey = $pathKeys[$tool] ?? null;
    $path = is_string($pathKey) ? ($parameters[$pathKey] ?? null) : null;

    return is_string($path) && $path !== '' ? $path : null;
}

function verificationVerdicts(string $response): ?string
{
    $sourceLines = preg_split('/\R/', $response) ?: [];
    $lines = [];
    $seen = [];
    foreach ($sourceLines as $sourceLine) {
        $sourceLine = trim($sourceLine);
        if ($sourceLine === '') {
            continue;
        }
        if (preg_match('/^TASK ([1-9][0-9]*): (DONE|INCOMPLETE)$/', $sourceLine, $match) !== 1
            || isset($seen[$match[1]])) {
            return null;
        }
        $seen[$match[1]] = true;
        $lines[] = 'TASK '.$match[1].': '.$match[2];
    }

    return $lines === [] ? null : implode("\n", $lines)."\n";
}

$options = parserOptions(array_slice($argv, 1));
$eventsPath = parserRequired($options, 'events');
$sanitizedPath = parserRequired($options, 'sanitized-events');
$resultPath = parserRequired($options, 'result');
$repoRoot = realpath(parserRequired($options, 'repo-root'));
if ($repoRoot === false) {
    parserFail('repo-root inválido');
}
$runnerVersion = parserRequired($options, 'runner-version');
$requestedModel = parserRequired($options, 'requested-model');
$executionId = parserRequired($options, 'execution-id');
$executionMode = parserRequired($options, 'execution-mode');
$workflowId = parserRequired($options, 'workflow-id');
$featureKey = parserRequired($options, 'feature-key');
$attempt = parserRequired($options, 'attempt');
$promptSha256 = parserRequired($options, 'prompt-sha256');
$promptTransport = parserRequired($options, 'prompt-transport');
$permissionPolicyStatus = parserRequired($options, 'permission-policy-status');
$permissionPolicyHash = trim((string) ($options['permission-policy-hash'] ?? ''));
$permissionPolicyHash = in_array($permissionPolicyHash, ['', 'none'], true) ? null : $permissionPolicyHash;
$verificationAgent = trim((string) ($options['verification-agent'] ?? ''));
$verificationAgent = in_array($verificationAgent, ['', 'none'], true) ? null : $verificationAgent;
$textOutput = trim((string) ($options['text-output'] ?? '')) ?: null;
$exitCode = filter_var(parserRequired($options, 'exit-code'), FILTER_VALIDATE_INT);
$maxBytes = filter_var((string) ($options['max-event-bytes'] ?? '5242880'), FILTER_VALIDATE_INT);
$maxEvents = filter_var((string) ($options['max-events'] ?? '10000'), FILTER_VALIDATE_INT);

if ($exitCode === false || $maxBytes === false || $maxBytes < 1 || $maxEvents === false || $maxEvents < 1) {
    parserFail('limites ou exit-code inválidos');
}
if (! in_array($executionMode, ['impl', 'verify'], true)
    || preg_match('/^exec_[A-Za-z0-9_-]+$/', $executionId) !== 1
    || preg_match('/^wf_[A-Za-z0-9_-]+$/', $workflowId) !== 1
    || preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/', $featureKey) !== 1
    || preg_match('/^[0-9]+$/', $attempt) !== 1
    || preg_match('/^[a-f0-9]{64}$/', $promptSha256) !== 1) {
    parserFail('contexto de execução inválido');
}

$eventBytes = is_file($eventsPath) ? filesize($eventsPath) : false;
$malformed = null;
if ($eventBytes === false) {
    $eventBytes = 0;
    $malformed = 'stream JSONL ausente';
} elseif ($eventBytes > $maxBytes) {
    $malformed = 'stream JSONL excedeu o limite de bytes';
}
$content = $eventBytes <= $maxBytes && is_file($eventsPath) ? (string) file_get_contents($eventsPath) : '';
$lines = preg_split('/\R/', $content) ?: [];
$lines = array_values(array_filter($lines, static fn (string $line): bool => trim($line) !== ''));
if (count($lines) > $maxEvents) {
    $malformed ??= 'stream JSONL excedeu o limite de eventos';
}

$conversationId = null;
$observedModel = null;
$initCount = 0;
$resultCount = 0;
$resultStatus = null;
$response = '';
$terminalIndex = null;
$planExpanded = false;
$permissionMode = null;
$sanitized = [];
$allowedVerifyTools = ['view_file', 'list_dir', 'grep_search', 'find_by_name'];

foreach ($lines as $index => $line) {
    try {
        $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
    } catch (JsonException) {
        $malformed ??= 'stream contém linha JSON inválida';
        continue;
    }
    if (! is_array($event) || ! is_string($event['event'] ?? null)) {
        $malformed ??= 'evento sem tipo válido';
        continue;
    }
    $type = $event['event'];
    if ($type === 'init') {
        $initCount++;
        $id = $event['conversation_id'] ?? null;
        $init = $event['init'] ?? null;
        if (! is_string($id) || $id === '' || ! is_array($init) || ! is_string($init['model'] ?? null)) {
            $malformed ??= 'evento init incompleto';
            continue;
        }
        if ($conversationId !== null && $conversationId !== $id) {
            $malformed ??= 'stream contém múltiplas conversas';
        }
        $conversationId = $id;
        $observedModel = $init['model'];
        $permissionMode = $init['permission_mode'] ?? null;
        foreach (($init['expanded_commands'] ?? []) as $expanded) {
            if (is_array($expanded) && ($expanded['name'] ?? null) === 'plan') {
                $planExpanded = true;
            }
        }
        $sanitized[] = ['event' => 'init'];
        continue;
    }
    if ($type === 'step_update') {
        $step = $event['step_update'] ?? null;
        if (! is_array($step)) {
            $malformed ??= 'step_update incompleto';
            continue;
        }
        $id = $step['conversation_id'] ?? null;
        if (is_string($id) && $conversationId !== null && $id !== $conversationId) {
            $malformed ??= 'stream contém múltiplas conversas';
        }
        $projected = [
            'event' => 'step_update',
            'state' => is_string($step['state'] ?? null) ? $step['state'] : null,
            'step_type' => is_string($step['step_type'] ?? null) ? $step['step_type'] : null,
        ];
        if (($step['step_type'] ?? null) === 'tool') {
            $tool = $step['tool_name'] ?? null;
            $projected['tool_name'] = is_string($tool) ? $tool : null;
            $toolParameters = $step['tool_info']['parameters'] ?? null;
            $toolPath = is_string($tool) ? verifyToolPath($tool, $toolParameters) : null;
            if (is_string($toolPath) && ! pathInsideRoot($toolPath, $repoRoot)) {
                $projected['access_scope'] = 'outside_workspace';
                if (($step['state'] ?? null) === 'ERROR') {
                    $projected['access_outcome'] = 'denied';
                }
            }
            $toolOutput = $step['tool_info']['output'] ?? null;
            if (! isset($projected['access_outcome']) && is_string($toolOutput) && $toolOutput !== '') {
                $projected['access_outcome'] = preg_match('/permission|denied|not allowed|outside.{0,40}workspace|blocked|rejected|approval/iu', $toolOutput) === 1
                    ? 'denied'
                    : 'not_proven';
            }
            if ($executionMode === 'verify') {
                if (! is_string($tool) || ! in_array($tool, $allowedVerifyTools, true)) {
                    $malformed ??= 'verify tentou ferramenta fora da allowlist read-only';
                }
                if (! is_string($tool)
                    || ! verifyToolParameters($tool, $toolParameters, $repoRoot)) {
                    $malformed ??= 'verify publicou parâmetros desconhecidos ou path fora de repo-root';
                }
            }
        }
        $sanitized[] = array_filter($projected, static fn (mixed $value): bool => $value !== null);
        continue;
    }
    if ($type === 'result') {
        $resultCount++;
        $terminalIndex = $index;
        $result = $event['result'] ?? null;
        $id = is_array($result) ? ($result['conversation_id'] ?? null) : null;
        if (! is_array($result) || ! is_string($id) || $id === '') {
            $malformed ??= 'evento result incompleto';
            continue;
        }
        if ($conversationId !== null && $conversationId !== $id) {
            $malformed ??= 'result pertence a outra conversa';
        }
        $conversationId ??= $id;
        $resultStatus = $result['status'] ?? null;
        $response = is_string($result['response'] ?? null) ? $result['response'] : '';
        $sanitized[] = ['event' => 'result', 'status' => is_string($resultStatus) ? $resultStatus : null];
        continue;
    }
    $malformed ??= "tipo de evento desconhecido: {$type}";
}

if ($initCount !== 1) {
    $malformed ??= 'stream deve conter exatamente um init';
}
if ($resultCount !== 1 || $terminalIndex !== count($lines) - 1) {
    $malformed ??= 'stream deve terminar com exatamente um result';
}
if ($observedModel !== $requestedModel) {
    $malformed ??= 'modelo efetivo diverge do modelo solicitado';
}
if ($executionMode === 'verify' && (! $planExpanded || $permissionMode !== 'request-review')) {
    $malformed ??= 'verify não comprovou mode plan e permission_mode seguro';
}
if ($executionMode === 'verify'
    && ($permissionPolicyStatus !== 'verified'
        || ! is_string($permissionPolicyHash)
        || preg_match('/^[a-f0-9]{64}$/', $permissionPolicyHash) !== 1
        || $verificationAgent !== 'ralph-review')) {
    $malformed ??= 'verify sem política ou agente comprovado';
}
if ($executionMode === 'impl' && ($permissionPolicyStatus !== 'not_required' || $permissionPolicyHash !== null)) {
    $malformed ??= 'impl carrega política read-only indevida';
}
if ($resultStatus !== 'SUCCESS') {
    $malformed ??= 'agy não publicou status SUCCESS';
}
$verdictOutput = '';
if ($executionMode === 'verify') {
    $projectedVerdicts = verificationVerdicts($response);
    if ($projectedVerdicts === null) {
        $malformed ??= 'verify não publicou somente vereditos TASK canônicos e únicos';
    } else {
        $verdictOutput = $projectedVerdicts;
    }
}

$status = 'completed';
$errorSummary = $malformed;
if ($exitCode !== 0 || $errorSummary !== null || $conversationId === null) {
    $status = in_array($exitCode, [124, 137], true) ? 'usage_limited' : 'failed';
    $errorSummary ??= $exitCode !== 0 ? "agy terminou com exit code {$exitCode}" : 'saída sem conversa terminal';
}

$sanitizedLines = '';
foreach ($sanitized as $event) {
    $sanitizedLines .= json_encode($event, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)."\n";
}
writePrivate($sanitizedPath, $sanitizedLines);
if ($textOutput !== null) {
    writePrivate($textOutput, $verdictOutput);
}

$result = [
    'schema_version' => '1.1.0',
    'runner' => 'agy',
    'runner_version' => $runnerVersion,
    'provider' => 'agy',
    'requested_model' => $requestedModel,
    'effective_model' => $observedModel,
    'identity_status' => $observedModel === null ? 'unavailable' : 'observed',
    'identity_source' => $observedModel === null ? 'not_exposed' : 'event_init_model',
    'execution_id' => $executionId,
    'execution_mode' => $executionMode,
    'workflow_id' => $workflowId,
    'feature_key' => $featureKey,
    'attempt' => (int) $attempt,
    'session_id' => $conversationId,
    'status' => $status,
    'exit_code' => $exitCode,
    'fallback_used' => $observedModel === null ? null : $observedModel !== $requestedModel,
    'fallback_status' => $observedModel === null ? 'unknown' : ($observedModel === $requestedModel ? 'not_detected' : 'detected'),
    'events_seen' => count($lines),
    'event_bytes' => (int) $eventBytes,
    'terminal_event' => $resultCount === 1 ? 'result' : null,
    'prompt_sha256' => $promptSha256,
    'prompt_transport' => $promptTransport,
    'permission_policy_hash' => $permissionPolicyHash,
    'permission_policy_status' => $permissionPolicyStatus,
    'verification_agent' => $verificationAgent,
    'error_summary' => $errorSummary,
    'artifact_refs' => [basename($sanitizedPath)],
];

writePrivate($resultPath, json_encode($result, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR)."\n");
