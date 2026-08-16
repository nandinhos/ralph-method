#!/usr/bin/env php
<?php

declare(strict_types=1);

function parserFail(string $message): never
{
    fwrite(STDERR, "cursor parser: {$message}\n");
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

/** @param array<string, mixed> $parameters */
function sanitizeEvent(mixed $value): mixed
{
    if (is_array($value)) {
        $result = [];
        foreach ($value as $key => $item) {
            $safeKey = is_string($key) ? $key : (string) $key;
            $result[$safeKey] = sanitizeEvent($item);
        }

        return $result;
    }
    if (is_string($value)) {
        $value = preg_replace('/\s+/', ' ', trim($value)) ?? '';
        $value = preg_replace('/(?:token|api[_-]?key|secret|password|authorization|bearer)\s*[:=]\s*\S+/i', '[redacted]', $value) ?? $value;
        if (@preg_match('//u', $value) !== 1) {
            $converted = function_exists('iconv') ? @iconv('UTF-8', 'UTF-8//IGNORE', $value) : false;
            $value = is_string($converted) ? $converted : '';
        }
        $value = substr($value, 0, 500);

        return $value === '' ? null : $value;
    }

    return $value;
}

/** @param list<array<string, mixed>> $events */
function cursorTerminal(array $events): bool
{
    foreach ($events as $event) {
        $type = (string) ($event['type'] ?? '');
        if ($type === 'result') {
            return true;
        }
    }

    return false;
}

/** @param list<array<string, mixed>> $events */
function cursorResultCount(array $events): int
{
    $count = 0;
    foreach ($events as $event) {
        if ((string) ($event['type'] ?? '') === 'result') {
            $count++;
        }
    }

    return $count;
}

/** @param list<array<string, mixed>> $events */
function writeObserved(array $events): bool
{
    foreach ($events as $event) {
        $type = (string) ($event['type'] ?? '');
        if ($type === 'tool_call') {
            $tool = (string) ($event['tool'] ?? ($event['name'] ?? ''));
            if (in_array($tool, ['write_to_file', 'apply_diff', 'run_terminal_command', 'bash', 'edit'], true)) {
                return true;
            }
            if (preg_match('/write|edit|create|modify/i', $tool) === 1) {
                return true;
            }
        }
        if (preg_match('/write|apply_diff|run_terminal_command|edit/i', $type) === 1) {
            return true;
        }
    }

    return false;
}

/** @param list<array<string, mixed>> $events */
function observedModel(array $events): ?string
{
    foreach ($events as $event) {
        $type = (string) ($event['type'] ?? '');
        if ($type === 'system' || $type === 'init') {
            $model = $event['model'] ?? null;
            if (is_string($model) && $model !== '') {
                return $model;
            }
        }
    }

    return null;
}

$arguments = array_slice($argv, 1);
$options = parserOptions($arguments);
$eventsPath = parserRequired($options, 'events');
$sanitizedPath = parserRequired($options, 'sanitized-events');
$resultPath = parserRequired($options, 'result');
$repoRoot = parserRequired($options, 'repo-root');
$exitCode = (int) parserRequired($options, 'exit-code');
$runnerVersion = parserRequired($options, 'runner-version');
$requestedModel = parserRequired($options, 'requested-model');
$executionId = parserRequired($options, 'execution-id');
$executionMode = parserRequired($options, 'execution-mode');
$workflowId = parserRequired($options, 'workflow-id');
$featureKey = parserRequired($options, 'feature-key');
$attempt = parserRequired($options, 'attempt');
$promptSha256 = parserRequired($options, 'prompt-sha256');
$promptTransport = parserRequired($options, 'prompt-transport');
$permissionPolicyStatus = $options['permission-policy-status'] ?? 'not_required';
$permissionPolicyHash = $options['permission-policy-hash'] ?? 'none';
$verificationAgent = $options['verification-agent'] ?? 'none';
$textOutput = $options['text-output'] ?? null;
$maxEventBytes = (int) ($options['max-event-bytes'] ?? '5242880');
$maxEvents = (int) ($options['max-events'] ?? '10000');

if (! in_array($executionMode, ['impl', 'verify'], true)) {
    parserFail("execution-mode inválido: {$executionMode}");
}
if (preg_match('/^exec_[A-Za-z0-9_-]+$/', $executionId) !== 1
    || preg_match('/^wf_[A-Za-z0-9_-]+$/', $workflowId) !== 1
    || preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/', $featureKey) !== 1
    || ! ctype_digit($attempt)) {
    parserFail('identificadores inválidos');
}

$raw = is_file($eventsPath) ? (string) file_get_contents($eventsPath) : '';
$events = [];
$fatalError = null;
$eventBytes = strlen($raw);
foreach (preg_split('/\R/', $raw) ?: [] as $lineNumber => $line) {
    if (trim($line) === '') {
        continue;
    }
    if ($eventBytes > $maxEventBytes) {
        $fatalError = 'stream excede o limite de bytes';
        break;
    }
    if (count($events) >= $maxEvents) {
        $fatalError = 'stream excede o limite de eventos';
        break;
    }
    try {
        $decoded = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
    } catch (Throwable $exception) {
        $fatalError = 'JSONL inválido na linha '.($lineNumber + 1);
        break;
    }
    if (! is_array($decoded)) {
        $fatalError = 'evento inválido na linha '.($lineNumber + 1);
        break;
    }
    $events[] = $decoded;
}

$terminal = cursorTerminal($events);
$resultCount = cursorResultCount($events);
$writeInVerify = $executionMode === 'verify' && writeObserved($events);
$modelObserved = observedModel($events);
$identityStatus = 'declared';
$identitySource = 'requested_model';
$effectiveModel = null;
if ($modelObserved !== null) {
    $effectiveModel = $modelObserved;
    $identityStatus = 'observed';
    $identitySource = 'event_init_model';
}

$status = 'completed';
$errorSummary = $fatalError;
if ($errorSummary !== null) {
    $status = 'failed';
}
if ($errorSummary === null && $resultCount > 1) {
    $errorSummary = 'múltiplos eventos result no stream';
    $status = 'failed';
}
if ($errorSummary === null && $writeInVerify) {
    $errorSummary = 'ferramenta de escrita observada em modo verify';
    $status = 'failed';
}
if ($errorSummary === null && $exitCode !== 0) {
    $errorSummary = "Cursor terminou com exit code {$exitCode}";
    $status = 'failed';
}
if ($errorSummary === null && count($events) === 0) {
    $errorSummary = 'sem eventos observados';
    $status = 'failed';
}
if ($errorSummary === null && ! $terminal) {
    $errorSummary = 'sem evento terminal result';
    $status = 'failed';
}
if ($errorSummary === null && $modelObserved !== null && $modelObserved !== $requestedModel) {
    $errorSummary = 'modelo efetivo divergente do solicitado';
    $status = 'failed';
}

$result = [
    'schema_version' => '1.2.0',
    'runner' => 'cursor',
    'runner_version' => $runnerVersion,
    'provider' => 'cursor',
    'requested_model' => $requestedModel,
    'effective_model' => $effectiveModel,
    'identity_status' => $identityStatus,
    'identity_source' => $identitySource,
    'execution_id' => $executionId,
    'execution_mode' => $executionMode,
    'workflow_id' => $workflowId,
    'feature_key' => $featureKey,
    'attempt' => (int) $attempt,
    'session_id' => $executionId.'_session',
    'status' => $status,
    'exit_code' => $exitCode,
    'fallback_used' => null,
    'fallback_status' => 'unknown',
    'events_seen' => count($events),
    'event_bytes' => $eventBytes,
    'terminal_event' => $terminal ? 'result' : null,
    'prompt_sha256' => $promptSha256,
    'prompt_transport' => $promptTransport,
    'permission_policy_hash' => $permissionPolicyHash === 'none' || $permissionPolicyHash === '' ? null : $permissionPolicyHash,
    'permission_policy_status' => $permissionPolicyStatus,
    'verification_agent' => $verificationAgent === 'none' || $verificationAgent === '' ? null : $verificationAgent,
    'error_summary' => $errorSummary,
    'artifact_refs' => [basename($sanitizedPath)],
];

// Sanitiza os eventos para persistência (sem prompts/respostas completas).
$sanitized = [];
foreach ($events as $event) {
    $entry = sanitizeEvent($event);
    if (is_array($entry)) {
        unset($entry['content'], $entry['text'], $entry['response'], $entry['result']);
        $entry['type'] = (string) ($entry['type'] ?? 'unknown');
        $entry['cursor_parser'] = '1.2.0';
        $sanitized[] = $entry;
    }
}
writePrivate($sanitizedPath, implode("\n", array_map(
    static fn (array $entry): string => json_encode($entry, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR),
    $sanitized
))."\n");

if ($textOutput !== null) {
    $text = '';
    foreach ($events as $event) {
        if (in_array((string) ($event['type'] ?? ''), ['text', 'response'], true) && is_string($event['content'] ?? $event['text'] ?? null)) {
            $text .= ($event['content'] ?? $event['text'])."\n";
        }
    }
    writePrivate($textOutput, $text);
}

$json = json_encode($result, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)."\n";
writePrivate($resultPath, $json);

echo $json;
