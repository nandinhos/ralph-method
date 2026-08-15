#!/usr/bin/env php
<?php

declare(strict_types=1);

function failPolicy(string $message): never
{
    fwrite(STDERR, "agy policy: {$message}\n");
    exit(1);
}

/** @return array<string, string> */
function parsePolicyOptions(array $arguments): array
{
    $options = [];
    for ($index = 0; $index < count($arguments); $index++) {
        $argument = $arguments[$index];
        if (! str_starts_with($argument, '--')) {
            failPolicy("argumento inesperado: {$argument}");
        }
        $name = substr($argument, 2);
        $value = $arguments[++$index] ?? null;
        if ($value === null || str_starts_with($value, '--')) {
            failPolicy("--{$name} exige valor");
        }
        $options[$name] = $value;
    }

    return $options;
}

function requiredPolicyOption(array $options, string $name): string
{
    $value = trim((string) ($options[$name] ?? ''));
    if ($value === '') {
        failPolicy("--{$name} obrigatório");
    }

    return $value;
}

function executablePath(string $command): string
{
    $output = [];
    $exit = 0;
    exec('command -v '.escapeshellarg($command).' 2>/dev/null', $output, $exit);
    if ($exit !== 0 || trim((string) ($output[0] ?? '')) === '') {
        failPolicy("{$command} não encontrado");
    }

    return trim($output[0]);
}

function assertSafeProjectTree(string $root, string $token): void
{
    $tokenStat = stat($token);
    if (! is_array($tokenStat)) {
        failPolicy('não foi possível inspecionar inode do token OAuth');
    }
    try {
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($root, FilesystemIterator::SKIP_DOTS),
            RecursiveIteratorIterator::SELF_FIRST,
        );
        foreach ($iterator as $entry) {
            $path = $entry->getPathname();
            if ($entry->isLink()) {
                $resolved = realpath($path);
                if ($resolved === false || ($resolved !== $root && ! str_starts_with($resolved, $root.'/'))) {
                    failPolicy('repo-root contém symlink quebrado ou com destino externo');
                }
                continue;
            }
            if (! $entry->isFile()) {
                continue;
            }
            $entryStat = stat($path);
            if (is_array($entryStat)
                && $entryStat['dev'] === $tokenStat['dev']
                && $entryStat['ino'] === $tokenStat['ino']) {
                failPolicy('repo-root contém hardlink para o token OAuth');
            }
        }
    } catch (UnexpectedValueException) {
        failPolicy('não foi possível inspecionar toda a árvore do projeto');
    }
}

/** @return array{status: string, policy_hash: string, agent: string, isolation: string} */
function inspectPolicy(array $options): array
{
    if (PHP_OS_FAMILY !== 'Linux') {
        failPolicy('verify agy v1 exige Linux');
    }

    $root = realpath(requiredPolicyOption($options, 'repo-root'));
    if ($root === false || ! is_dir($root)) {
        failPolicy('repo-root inválido');
    }
    $agent = requiredPolicyOption($options, 'agent');
    if ($agent !== 'ralph-review') {
        failPolicy('agente de verificação deve ser ralph-review');
    }

    $home = rtrim((string) getenv('HOME'), '/');
    $tokenCandidate = trim((string) ($options['token-file'] ?? getenv('RALPH_AGY_TOKEN_FILE')));
    $tokenCandidate = $tokenCandidate !== '' ? $tokenCandidate : $home.'/.gemini/antigravity-cli/antigravity-oauth-token';
    $token = realpath($tokenCandidate);
    if ($token === false || ! is_file($token) || ! is_readable($token)) {
        failPolicy('token OAuth do agy ausente ou ilegível');
    }
    if ($token === $root || str_starts_with($token, $root.'/')) {
        failPolicy('token OAuth não pode ficar dentro do projeto');
    }
    assertSafeProjectTree($root, $token);

    $surfaces = [
        '.agents/agents/'.$agent.'/agent.md',
        'adapters/agy/runner.sh',
        'adapters/agy/parser.php',
        'adapters/agy/policy.php',
    ];
    $digest = hash_init('sha256');
    hash_update($digest, "antigravity_readonly_policy/v2\0");
    hash_update($digest, "mounts=/usr,etc-network-minimal,agy,repo-ro,app-tmpfs,tmp,oauth-ro,settings-ro,canary-ro\0");
    hash_update($digest, "env=HOME,USER,PATH,LANG\0");
    hash_update($digest, "file_access=allowNonWorkspaceAccess:false\0");
    hash_update($digest, "command_policy=strict;permissions.allow=[]\0");
    hash_update($digest, "tools=view_file,list_dir,grep_search,find_by_name\0");
    foreach ($surfaces as $relative) {
        $path = $root.'/'.$relative;
        if (! is_file($path) || ! is_readable($path)) {
            failPolicy("superfície de política ausente: {$relative}");
        }
        hash_update($digest, $relative."\0".(hash_file('sha256', $path) ?: '')."\0");
    }

    $bwrap = executablePath('bwrap');
    $smoke = escapeshellarg($bwrap).' --ro-bind / / --proc /proc --dev /dev'
        .' --unshare-pid --die-with-parent /bin/true 2>/dev/null';
    $output = [];
    $exit = 0;
    exec($smoke, $output, $exit);
    if ($exit !== 0) {
        failPolicy('bwrap não conseguiu criar namespace isolado');
    }

    return [
        'status' => 'verified',
        'policy_hash' => hash_final($digest),
        'agent' => $agent,
        'isolation' => 'bwrap_allowlisted_v1',
    ];
}

$command = $argv[1] ?? '';
if (! in_array($command, ['hash', 'check'], true)) {
    failPolicy('uso: policy.php hash|check --repo-root DIR --agent ralph-review [--token-file FILE]');
}
$result = inspectPolicy(parsePolicyOptions(array_slice($argv, 2)));
fwrite(STDOUT, json_encode($result, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)."\n");
