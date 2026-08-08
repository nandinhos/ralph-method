<?php

declare(strict_types=1);

function argument(array $arguments, string $name, bool $required = true): ?string
{
    $needle = '--'.$name;
    $index = array_search($needle, $arguments, true);
    if ($index !== false && isset($arguments[$index + 1])) {
        return (string) $arguments[$index + 1];
    }
    foreach ($arguments as $value) {
        if (str_starts_with($value, $needle.'=')) {
            return substr($value, strlen($needle) + 1);
        }
    }
    if ($required) {
        fwrite(STDERR, "opencode policy: --{$name} obrigatório\n");
        exit(2);
    }

    return null;
}

function stop(string $message): never
{
    fwrite(STDERR, "opencode policy: {$message}\n");
    exit(1);
}

function rootPath(string $path): string
{
    $root = realpath($path);
    if ($root === false || ! is_dir($root)) {
        stop("raiz do projeto ausente: {$path}");
    }

    return $root;
}

function agentName(string $agent): string
{
    if (preg_match('/^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$/', $agent) !== 1) {
        stop('nome de agente inválido');
    }

    return $agent;
}

/** @return array<string, string> */
function policyFiles(string $root, string $agent): array
{
    $files = [];
    $agentRelative = '.opencode/agents/'.$agent.'.md';
    $agentPath = $root.'/'.$agentRelative;
    if (! is_file($agentPath)) {
        stop("agente read-only ausente: {$agentRelative}");
    }
    $files[$agentRelative] = $agentPath;

    foreach (['opencode.json', 'opencode.jsonc', 'opencode.yaml', 'opencode.yml', 'opencode.toml'] as $relative) {
        if (is_file($root.'/'.$relative)) {
            $files[$relative] = $root.'/'.$relative;
        }
    }

    return $files;
}

/** @return array{hash: string, files: array<string, string>, agent_path: string, denied_tools: list<string>} */
function policyFingerprint(string $root, string $agent): array
{
    $files = policyFiles($root, $agent);
    $material = '';
    foreach ($files as $relative => $path) {
        $content = file_get_contents($path);
        if ($content === false) {
            stop("não foi possível ler a política: {$relative}");
        }
        $files[$relative] = hash('sha256', $content);
        $material .= $relative."\0".$files[$relative]."\n";
    }

    $agentContent = file_get_contents($root.'/.opencode/agents/'.$agent.'.md');
    if ($agentContent === false || ! str_contains($agentContent, 'permission:')) {
        stop('agente sem bloco de permissões explícito');
    }
    $deniedTools = [];
    foreach (['edit', 'bash'] as $tool) {
        $pattern = '/^\s*["\']?'.preg_quote($tool, '/').'["\']?\s*:\s*deny\s*$/m';
        if (preg_match($pattern, $agentContent) !== 1) {
            stop("política sem regra obrigatória: {$tool}: deny");
        }
        $deniedTools[] = $tool;
    }
    if (preg_match('/^\s*["\']?external_directory["\']?\s*:\s*deny\s*$/m', $agentContent) !== 1) {
        stop('política sem regra obrigatória: external_directory: deny');
    }
    if (preg_match('/^\s*["\']?\*["\']?\s*:\s*deny\s*$/m', $agentContent) !== 1) {
        stop('política sem deny global explícito');
    }

    return [
        'hash' => hash('sha256', $material),
        'files' => $files,
        'agent_path' => $root.'/.opencode/agents/'.$agent.'.md',
        'denied_tools' => $deniedTools,
    ];
}

function proofPathOutsideRoot(string $root, string $proofPath): string
{
    $proof = realpath($proofPath);
    if ($proof === false || ! is_file($proof)) {
        stop("prova read-only ausente: {$proofPath}");
    }
    $prefix = rtrim($root, '/').'/';
    if ($proof === $root || str_starts_with($proof, $prefix)) {
        stop('prova read-only deve ficar fora da raiz mutável');
    }

    return $proof;
}

function policyTreeHash(string $root, string $agent): string
{
    $paths = policyFiles($root, $agent);
    ksort($paths, SORT_STRING);
    $context = hash_init('sha256');
    foreach ($paths as $relative => $path) {
        $contentHash = hash_file('sha256', $path, true);
        if (! is_string($contentHash)) {
            stop("não foi possível calcular o hash da superfície de política: {$relative}");
        }
        hash_update($context, $relative."\0");
        hash_update($context, $contentHash);
    }

    return hash_final($context);
}

/** @param mixed $evidence @param list<string> $tools */
function denialEvidenceIsValid(mixed $evidence, array $tools): bool
{
    if (! is_array($evidence)) {
        return false;
    }

    foreach ($tools as $tool) {
        $sources = $evidence[$tool] ?? null;
        if (! is_array($sources)
            || $sources === []
            || ! array_reduce($sources, static fn (bool $valid, mixed $source): bool => $valid && is_string($source), true)
            || count($sources) !== count(array_unique($sources))
            || array_diff($sources, ['policy', 'event', 'model_text']) !== []
            || ! in_array('policy', $sources, true)) {
            return false;
        }
    }

    return true;
}

function check(string $root, string $agent, string $proofPath): void
{
    $fingerprint = policyFingerprint($root, $agent);
    $proofFile = proofPathOutsideRoot($root, $proofPath);
    $proof = json_decode((string) file_get_contents($proofFile), true);
    if (! is_array($proof)) {
        stop('prova read-only não é JSON válido');
    }
    $requiredKeys = [
        'schema_version', 'status', 'agent', 'target_root', 'policy_hash',
        'tree_hash_before', 'tree_hash_after', 'canary_absent', 'tool_events_seen',
        'forbidden_tools_seen', 'denied_tools_seen', 'policy_denied_tools',
        'denial_evidence', 'session_id', 'terminal_event', 'event_log_sha256',
        'final_marker', 'attempts',
    ];
    $allowedKeys = $requiredKeys;
    $unknownKeys = array_values(array_diff(array_keys($proof), $allowedKeys));
    $missingKeys = array_values(array_diff($requiredKeys, array_keys($proof)));
    if ($unknownKeys !== [] || $missingKeys !== []) {
        stop('prova read-only diverge do schema: '.json_encode(['unknown' => $unknownKeys, 'missing' => $missingKeys], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }
    if (($proof['status'] ?? null) !== 'verified'
        || ($proof['schema_version'] ?? null) !== '1.0.0'
        || ($proof['final_marker'] ?? null) !== 'READONLY_DENIED'
        || ($proof['agent'] ?? null) !== $agent
        || ($proof['target_root'] ?? null) !== $root
        || ($proof['policy_hash'] ?? null) !== $fingerprint['hash']) {
        stop('prova read-only não corresponde à política atual');
    }
    if (($proof['tree_hash_before'] ?? null) === null
        || ! is_string($proof['tree_hash_before'])
        || preg_match('/^[a-f0-9]{64}$/', $proof['tree_hash_before']) !== 1
        || ($proof['tree_hash_before'] ?? null) !== ($proof['tree_hash_after'] ?? null)
        || preg_match('/^[a-f0-9]{64}$/', (string) $proof['tree_hash_after']) !== 1
        || ($proof['canary_absent'] ?? false) !== true
        || ! is_int($proof['tool_events_seen'] ?? null)
        || ($proof['tool_events_seen'] ?? 0) < 0
        || ! is_array($proof['denied_tools_seen'] ?? null)
        || ! is_array($proof['policy_denied_tools'] ?? null)
        || ! array_reduce($proof['policy_denied_tools'], static fn (bool $valid, mixed $tool): bool => $valid && is_string($tool), true)
        || ! array_reduce($proof['denied_tools_seen'], static fn (bool $valid, mixed $tool): bool => $valid && is_string($tool), true)
        || count($proof['policy_denied_tools']) !== count(array_unique($proof['policy_denied_tools']))
        || array_diff($proof['denied_tools_seen'], $fingerprint['denied_tools']) !== []
        || count($proof['denied_tools_seen']) !== count(array_unique($proof['denied_tools_seen']))
        || ! is_array($proof['denial_evidence'] ?? null)
        || array_values(array_diff(array_keys($proof['denial_evidence']), $fingerprint['denied_tools'])) !== []
        || array_values(array_diff($fingerprint['denied_tools'], array_keys($proof['denial_evidence']))) !== []
        || ! denialEvidenceIsValid($proof['denial_evidence'], $fingerprint['denied_tools'])
        || ! is_string($proof['session_id'] ?? null)
        || preg_match('/^ses_[A-Za-z0-9_-]+$/', (string) $proof['session_id']) !== 1
        || ($proof['terminal_event'] ?? null) !== 'step_finish'
        || ! is_string($proof['event_log_sha256'] ?? null)
        || preg_match('/^[a-f0-9]{64}$/', $proof['event_log_sha256']) !== 1
        || ! is_int($proof['attempts'] ?? null)
        || ($proof['attempts'] ?? 0) < 1
        || ! is_array($proof['forbidden_tools_seen'] ?? null)
        || $proof['forbidden_tools_seen'] !== []) {
        stop('prova read-only não comprovou superfície de política preservada e ferramentas restritas');
    }
    $claimedPolicyDenied = $proof['policy_denied_tools'];
    $expectedPolicyDenied = $fingerprint['denied_tools'];
    sort($claimedPolicyDenied);
    sort($expectedPolicyDenied);
    if ($claimedPolicyDenied !== $expectedPolicyDenied) {
        stop('policy_denied_tools não corresponde à política fingerprintada');
    }

    $eventFile = proofPathOutsideRoot($root, $proofFile.'.events.jsonl');
    $eventHash = hash_file('sha256', $eventFile);
    if (! is_string($eventHash) || $eventHash !== $proof['event_log_sha256']) {
        stop('JSONL externo da prova não corresponde ao hash registrado');
    }
    $sessionId = null;
    $terminal = null;
    $markerSeen = false;
    $toolEvents = 0;
    $deniedObserved = [];
    $forbidden = ['bash', 'edit', 'write', 'apply_patch', 'exec_command', 'shell', 'terminal'];
    $eventLines = file($eventFile, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($eventLines === false || $eventLines === []) {
        stop('JSONL externo da prova está vazio ou ilegível');
    }
    foreach ($eventLines as $line) {
        $event = json_decode($line, true);
        if (! is_array($event)) {
            stop('JSONL externo da prova contém linha inválida');
        }
        $eventSessionId = is_string($event['sessionID'] ?? null) ? $event['sessionID'] : null;
        $eventSessionId ??= is_string($event['session_id'] ?? null) ? $event['session_id'] : null;
        if ($eventSessionId !== null && $sessionId !== null && $eventSessionId !== $sessionId) {
            stop('JSONL externo contém mais de uma sessão');
        }
        $sessionId ??= $eventSessionId;
        if (($event['type'] ?? null) === 'step_finish') {
            $terminal = 'step_finish';
        }
        $part = is_array($event['part'] ?? null) ? $event['part'] : [];
        $eventText = $event['text'] ?? ($part['text'] ?? null);
        if (is_string($eventText) && str_contains($eventText, 'READONLY_DENIED')) {
            $markerSeen = true;
        }
        if (($event['type'] ?? null) !== 'tool_use') {
            continue;
        }
        $toolEvents++;
        $tool = strtolower((string) ($event['tool'] ?? $part['tool'] ?? ''));
        if (! in_array($tool, $forbidden, true)) {
            continue;
        }
        $serialized = strtolower((string) json_encode($event, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
        $denied = str_contains($serialized, 'denied')
            || str_contains($serialized, 'permission')
            || str_contains($serialized, 'not available')
            || str_contains($serialized, 'unavailable tool')
            || str_contains($serialized, 'status":"error');
        if (! $denied) {
            stop('JSONL externo registrou ferramenta proibida sem recusa');
        }
        if (in_array($tool, $fingerprint['denied_tools'], true)) {
            $deniedObserved[] = $tool;
        }
    }
    if ($sessionId !== $proof['session_id'] || $terminal !== 'step_finish' || ! $markerSeen || $toolEvents !== $proof['tool_events_seen']) {
        stop('sessão, evento terminal ou contagem de ferramentas não correspondem ao JSONL');
    }
    if (policyTreeHash($root, $agent) !== $proof['tree_hash_after']) {
        stop('superfície atual da política não corresponde ao hash comprovado pela prova');
    }
    $claimedDenied = array_values(array_unique($proof['denied_tools_seen']));
    $observedDenied = array_values(array_unique($deniedObserved));
    sort($claimedDenied);
    sort($observedDenied);
    if ($claimedDenied !== $observedDenied) {
        stop('denied_tools_seen não corresponde às recusas observadas no JSONL');
    }

    echo json_encode([
        'status' => 'verified',
        'agent' => $agent,
        'policy_hash' => $fingerprint['hash'],
        'policy_denied_tools' => $fingerprint['denied_tools'],
        'proof_file' => basename($proofFile),
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)."\n";
}

$command = $argv[1] ?? '';
$arguments = array_slice($argv, 2);
$root = rootPath(argument($arguments, 'repo-root'));
$agent = agentName(argument($arguments, 'agent'));
$fingerprint = policyFingerprint($root, $agent);

if ($command === 'hash') {
    echo json_encode([
        'status' => 'ready',
        'agent' => $agent,
        'policy_hash' => $fingerprint['hash'],
        'denied_tools' => $fingerprint['denied_tools'],
        'files' => $fingerprint['files'],
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)."\n";
    exit(0);
}

if ($command === 'check') {
    check($root, $agent, argument($arguments, 'proof-file'));
    exit(0);
}

fwrite(STDERR, "uso: policy.php hash|check --repo-root DIR --agent NAME [--proof-file FILE]\n");
exit(2);
