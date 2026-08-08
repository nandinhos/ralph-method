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

/** @return array{hash: string, files: array<string, string>, agent_path: string} */
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
    foreach (['edit: deny', 'bash: deny', 'external_directory: deny'] as $required) {
        if (! str_contains($agentContent, $required)) {
            stop("política sem regra obrigatória: {$required}");
        }
    }
    if (preg_match('/^\s*["\']?\*["\']?\s*:\s*deny\s*$/m', $agentContent) !== 1) {
        stop('política sem deny global explícito');
    }

    return [
        'hash' => hash('sha256', $material),
        'files' => $files,
        'agent_path' => $root.'/.opencode/agents/'.$agent.'.md',
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

function check(string $root, string $agent, string $proofPath): void
{
    $fingerprint = policyFingerprint($root, $agent);
    $proofFile = proofPathOutsideRoot($root, $proofPath);
    $proof = json_decode((string) file_get_contents($proofFile), true);
    if (! is_array($proof)) {
        stop('prova read-only não é JSON válido');
    }
    if (($proof['status'] ?? null) !== 'verified'
        || ($proof['final_marker'] ?? null) !== 'READONLY_DENIED'
        || ($proof['agent'] ?? null) !== $agent
        || ($proof['target_root'] ?? null) !== $root
        || ($proof['policy_hash'] ?? null) !== $fingerprint['hash']) {
        stop('prova read-only não corresponde à política atual');
    }
    if (($proof['tree_hash_before'] ?? null) === null
        || ($proof['tree_hash_before'] ?? null) !== ($proof['tree_hash_after'] ?? null)
        || ($proof['canary_absent'] ?? false) !== true
        || ! is_int($proof['tool_events_seen'] ?? null)
        || ($proof['tool_events_seen'] ?? 0) < 1
        || ! is_array($proof['forbidden_tools_seen'] ?? null)
        || $proof['forbidden_tools_seen'] !== []) {
        stop('prova read-only não comprovou árvore preservada e ferramentas restritas');
    }

    echo json_encode([
        'status' => 'verified',
        'agent' => $agent,
        'policy_hash' => $fingerprint['hash'],
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
