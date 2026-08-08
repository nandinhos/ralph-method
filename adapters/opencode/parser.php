<?php

declare(strict_types=1);

function option(array $arguments, string $name, bool $required = true): ?string
{
    $index = array_search('--'.$name, $arguments, true);
    if ($index !== false && isset($arguments[$index + 1])) {
        return (string) $arguments[$index + 1];
    }
    foreach ($arguments as $argument) {
        if (str_starts_with($argument, '--'.$name.'=')) {
            return substr($argument, strlen('--'.$name.'='));
        }
    }
    if ($required) {
        fwrite(STDERR, "opencode parser: --{$name} obrigatório\n");
        exit(2);
    }

    return null;
}

function clean(?string $value): ?string
{
    if ($value === null) {
        return null;
    }
    $value = preg_replace('/\s+/', ' ', trim($value)) ?? '';
    $value = preg_replace('/(?:token|api[_-]?key|secret|password|authorization|bearer)\s*[:=]\s*\S+/i', '[redacted]', $value) ?? $value;

    return $value === '' ? null : substr($value, 0, 240);
}

$arguments = array_slice($argv, 1);
$eventsPath = option($arguments, 'events');
$resultPath = option($arguments, 'result');
$exitCode = (int) option($arguments, 'exit-code');
$runnerVersion = option($arguments, 'runner-version');
$provider = option($arguments, 'provider');
$requestedModel = option($arguments, 'requested-model');
$executionId = option($arguments, 'execution-id');
$promptSha256 = option($arguments, 'prompt-sha256');
$promptTransport = option($arguments, 'prompt-transport');
$permissionPolicyHash = option($arguments, 'permission-policy-hash', false);
$permissionPolicyHash = $permissionPolicyHash === '' ? null : $permissionPolicyHash;
$permissionPolicyStatus = option($arguments, 'permission-policy-status', false) ?? 'not_required';
$verificationAgent = option($arguments, 'verification-agent', false);
$textOutput = option($arguments, 'text-output', false);
$fallbackStatus = option($arguments, 'fallback-status', false) ?? 'unknown';
$maxEventBytes = (int) (option($arguments, 'max-event-bytes', false) ?? '5242880');
$maxEvents = (int) (option($arguments, 'max-events', false) ?? '10000');

if (! in_array($fallbackStatus, ['unknown', 'detected', 'not_detected'], true)) {
    fwrite(STDERR, "opencode parser: fallback-status inválido\n");
    exit(2);
}
if (! in_array($permissionPolicyStatus, ['verified', 'not_required', 'failed'], true)) {
    fwrite(STDERR, "opencode parser: permission-policy-status inválido\n");
    exit(2);
}

$events = [];
$sessionId = null;
$terminalEvent = null;
$fatalError = null;
$observedProvider = null;
$observedModel = null;
$malformed = null;
$textParts = [];
$eventBytes = is_file($eventsPath) ? (int) filesize($eventsPath) : 0;

if ($eventBytes > $maxEventBytes || ! is_file($eventsPath)) {
    $malformed = 'saída JSONL ausente ou excedeu o limite de bytes';
} else {
    $handle = fopen($eventsPath, 'rb');
    if ($handle === false) {
        $malformed = 'não foi possível abrir a saída JSONL';
    } else {
        while (($line = fgets($handle)) !== false) {
            if (count($events) >= $maxEvents) {
                $malformed = 'saída JSONL excedeu o limite de eventos';
                break;
            }
            $decoded = json_decode(trim($line), true);
            if (! is_array($decoded)) {
                $malformed = 'saída JSONL contém linha inválida';
                break;
            }
            $events[] = $decoded;
            $sessionId ??= isset($decoded['sessionID']) && is_string($decoded['sessionID']) ? $decoded['sessionID'] : null;
            $sessionId ??= isset($decoded['session_id']) && is_string($decoded['session_id']) ? $decoded['session_id'] : null;
            $type = isset($decoded['type']) && is_string($decoded['type']) ? $decoded['type'] : null;
            if ($type === 'step_finish') {
                $terminalEvent = $type;
            }
            if ($type === 'error') {
                $fatalError = clean(is_string($decoded['message'] ?? null) ? $decoded['message'] : (is_string($decoded['error'] ?? null) ? $decoded['error'] : 'evento de erro do OpenCode'));
            }
            if ($type === 'text') {
                $text = $decoded['text'] ?? ($decoded['part']['text'] ?? null);
                if (is_string($text) && $text !== '') {
                    $textParts[] = $text;
                }
            }
            foreach (['providerID', 'provider_id', 'provider'] as $field) {
                if ($observedProvider === null && is_string($decoded[$field] ?? null) && trim($decoded[$field]) !== '') {
                    $observedProvider = trim($decoded[$field]);
                }
            }
            foreach (['modelID', 'model_id', 'model'] as $field) {
                if ($observedModel === null && is_string($decoded[$field] ?? null) && trim($decoded[$field]) !== '') {
                    $observedModel = trim($decoded[$field]);
                }
            }
        }
        fclose($handle);
    }
}

$status = 'completed';
$errorSummary = $malformed ?? $fatalError;
if ($permissionPolicyStatus === 'failed') {
    $errorSummary ??= 'política read-only não permaneceu válida ao final da execução';
}
if ($exitCode !== 0 || $errorSummary !== null || $sessionId === null || $terminalEvent === null) {
    $status = $exitCode === 124 || $exitCode === 137 ? 'usage_limited' : 'failed';
    $errorSummary ??= $exitCode !== 0 ? "OpenCode terminou com exit code {$exitCode}" : 'saída sem sessão ou evento terminal';
}

$identityStatus = 'declared';
$effectiveModel = null;
$identitySource = 'requested_model';
if ($observedModel !== null && $observedProvider !== null) {
    $effectiveModel = str_contains($observedModel, '/') ? $observedModel : $observedProvider.'/'.$observedModel;
    $identityStatus = 'observed';
    $identitySource = 'event_fields';
} elseif ($observedProvider !== null) {
    $identityStatus = 'partial';
    $identitySource = 'event_provider';
}

$result = [
    'schema_version' => '1.0.0',
    'runner' => 'opencode',
    'runner_version' => $runnerVersion,
    'provider' => $provider,
    'requested_model' => $requestedModel,
    'effective_model' => $effectiveModel,
    'identity_status' => $identityStatus,
    'identity_source' => $identitySource,
    'execution_id' => $executionId,
    'session_id' => $sessionId,
    'status' => $status,
    'exit_code' => $exitCode,
    'fallback_used' => $fallbackStatus === 'unknown' ? null : $fallbackStatus === 'detected',
    'fallback_status' => $fallbackStatus,
    'events_seen' => count($events),
    'event_bytes' => $eventBytes,
    'terminal_event' => $terminalEvent,
    'prompt_sha256' => $promptSha256,
    'prompt_transport' => $promptTransport,
    'permission_policy_hash' => $permissionPolicyHash,
    'permission_policy_status' => $permissionPolicyStatus,
    'verification_agent' => $verificationAgent,
    'error_summary' => $errorSummary,
    'artifact_refs' => [basename($eventsPath)],
];

if ($textOutput !== null) {
    $textTemporary = $textOutput.'.tmp.'.bin2hex(random_bytes(4));
    $text = $textParts === [] ? '' : implode("\n", $textParts)."\n";
    if (file_put_contents($textTemporary, $text, LOCK_EX) === false || ! rename($textTemporary, $textOutput)) {
        @unlink($textTemporary);
        fwrite(STDERR, "opencode parser: não foi possível publicar texto de verificação\n");
        exit(2);
    }
    @chmod($textOutput, 0600);
}

$json = json_encode($result, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT | JSON_THROW_ON_ERROR)."\n";
$temporary = $resultPath.'.tmp.'.bin2hex(random_bytes(4));
if (file_put_contents($temporary, $json, LOCK_EX) === false || ! rename($temporary, $resultPath)) {
    @unlink($temporary);
    fwrite(STDERR, "opencode parser: não foi possível publicar resultado\n");
    exit(2);
}
@chmod($resultPath, 0600);
