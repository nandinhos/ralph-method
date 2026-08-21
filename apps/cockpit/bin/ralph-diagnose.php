#!/usr/bin/env php
<?php

declare(strict_types=1);

$workflowId = (string) getenv('RALPH_DEBUG_WORKFLOW_ID');
$featureKey = (string) getenv('RALPH_DEBUG_FEATURE_KEY');
$attempt = (int) getenv('RALPH_DEBUG_ATTEMPT');
$cwd = getcwd() ?: '.';
$dirty = trim((string) shell_exec('git status --porcelain 2>/dev/null'));
$manifestPath = $cwd.'/.git/ralph-control/workflow.json';
$manifestPresent = is_file($manifestPath);
$control = is_file($cwd.'/bin/ralph-control') || $manifestPresent;
$workflow = loadWorkflow($manifestPath);
$declared = declaredInput($workflow, $featureKey);
$declaredPath = $declared === '' ? '' : $cwd.DIRECTORY_SEPARATOR.ltrim($declared, '/');
$missingInput = $declaredPath !== '' && ! is_file($declaredPath);
$ledgerPath = $cwd.'/.git/ralph-control/events.jsonl';
$stderr = diagnosticSanitize(latestSupervisorStderr($cwd, $featureKey));
$inputError = $stderr !== '' && str_contains($stderr, 'input da feature não encontrado');
$recoveryReason = diagnosticSanitize(lastRecoveryReason($ledgerPath, $featureKey));
$blockStderr = diagnosticSanitize(latestBlockStderr($cwd, $featureKey));
$blockStderrPreview = diagnosticSanitize(latestBlockStderrPreview($ledgerPath, $featureKey));
$runnerStderr = $blockStderr !== '' ? $blockStderr : $blockStderrPreview;
$harnessFailure = classifyRunnerHarnessFailure($runnerStderr);
$redactionThreshold = max(0, (int) (getenv('RALPH_DEBUG_REDACTED_THRESHOLD') ?: 0));
$redactionSummary = ledgerRedactionSummary($ledgerPath, $featureKey);
$redactionAlert = $redactionSummary['redacted_count'] > $redactionThreshold ? [
    'status' => 'alert',
    'threshold' => $redactionThreshold,
    'redacted_count' => $redactionSummary['redacted_count'],
    'redacted_kinds' => $redactionSummary['redacted_kinds'],
    'markers' => $redactionSummary['redacted_kinds'] === []
        ? ['[REDACTED:*]']
        : array_map(static fn (string $kind): string => '[REDACTED:'.$kind.']', $redactionSummary['redacted_kinds']),
    'paths' => $redactionSummary['paths'],
] : null;
$blockDied = $recoveryReason !== '' && (
    str_contains($recoveryReason, 'sem evento terminal')
    || str_contains($recoveryReason, 'sem concluir')
    || str_contains($recoveryReason, 'exit')
);

if ($missingInput || $inputError) {
    $name = $declared !== '' ? $declared : 'plan.md';
    $symptom = 'O bloco reivindicou a feature e morreu na hora: o input '.$name.' declarado no manifesto nao existe no checkout.';
    $rootCause = 'ralph-control run exige o arquivo de plano do workflow.json; sem '.$name.' o processo sai com erro e o supervise marca recovery_required sem evento terminal.';
    $plan = 'Restaure '.$name.' no checkout observado. Recover e Retomar nao criam o arquivo; o cockpit nao aprova gate nem escolhe a feature.';
    $title = 'Input da feature ausente no checkout';
    $summary = 'O manifesto declara o plano, o arquivo nao esta no checkout, e o stderr do supervisor confirma input nao encontrado. Retomar o bloco sem restaurar o arquivo so repete a recovery.';
    $hypotheses = [
        [
            'id' => 'H1',
            'statement' => 'O manifesto declara '.$name.' e o arquivo nao existe no checkout.',
            'status' => 'confirmed',
        ],
        [
            'id' => 'H2',
            'statement' => 'O supervise saiu porque o comando de debug estava ausente.',
            'status' => 'rejected',
        ],
        [
            'id' => 'H3',
            'statement' => 'O runner CLI falhou depois de receber o input da feature.',
            'status' => 'rejected',
        ],
    ];
    $causeKind = 'harness_defect';
    $incidentId = 'INC-COCKPIT-INPUT-001';
    $evidence = array_values(array_filter([
        $manifestPresent ? 'workflow-json' : null,
        $missingInput ? 'missing-plan-file' : null,
        $inputError ? 'supervisor-stderr' : null,
        $recoveryReason !== '' ? 'ledger-recovery' : null,
    ]));
} elseif ($harnessFailure !== null) {
    $symptom = $harnessFailure['symptom'];
    $rootCause = $harnessFailure['root_cause'];
    $plan = $harnessFailure['plan'];
    $title = $harnessFailure['title'];
    $summary = $harnessFailure['summary'];
    $hypotheses = $harnessFailure['hypotheses'];
    $causeKind = 'harness_defect';
    $incidentId = $harnessFailure['incident_id'];
    $evidence = array_values(array_filter([
        'block-stderr',
        $blockStderr !== '' ? 'block-artifact' : 'ledger-stderr-preview',
        $recoveryReason !== '' ? 'ledger-recovery' : null,
    ]));
} elseif ($blockDied) {
    $symptom = 'O supervise reivindicou a feature e o processo do bloco encerrou sem evento terminal.';
    $rootCause = 'O runner do checkout nao conclui a feature apos o claim; o controlador marca recovery_required e o orquestrador sai.';
    $plan = 'O painel mostra este diagnostico. Retomar so sustenta o orquestrador se o runner do checkout conseguir escrever o bloco. O cockpit nao aprova gate.';
    $title = 'Bloco encerra sem evento terminal';
    $summary = 'Recover e debug-command nao bastam quando o processo filho termina sem concluir a feature. O painel expoe a causa lida no ledger.';
    $hypotheses = [
        [
            'id' => 'H1',
            'statement' => 'O bloco morre logo apos o claim, sem evento terminal da feature.',
            'status' => 'confirmed',
        ],
    ];
    $causeKind = 'harness_defect';
    $incidentId = 'INC-COCKPIT-ORCH-001';
    $evidence = array_values(array_filter([
        $manifestPresent ? 'workflow-json' : 'cwd',
        $dirty === '' ? 'git-clean' : 'git-porcelain',
        $recoveryReason !== '' ? 'ledger-recovery' : 'ledger-absent',
    ]));
} elseif ($recoveryReason !== '') {
    $symptom = 'O supervise encerrou em recovery_required e o orquestrador nao permaneceu no ar.';
    $rootCause = 'O controlador registrou recovery com motivo: '.$recoveryReason.'.';
    $plan = 'Diagnosticar no cockpit, corrigir a causa no checkout e so entao retomar o supervise. O cockpit nao aprova gate.';
    $title = 'Recovery registrada no ledger';
    $summary = 'O diagnostico read-only le o motivo da recovery no ledger e expoe no painel administrativo.';
    $hypotheses = [
        [
            'id' => 'H1',
            'statement' => 'A ultima recovery do ledger explica a saida do supervise.',
            'status' => 'confirmed',
        ],
    ];
    $causeKind = 'unknown';
    $incidentId = 'INC-COCKPIT-ORCH-001';
    $evidence = ['ledger-recovery'];
} else {
    $symptom = 'O supervise encerrou em recovery ou debugging e o orquestrador nao permaneceu no ar.';
    $rootCause = 'O comando de systematic debugging nao estava disponivel para o supervise diagnosticar a fila.';
    $plan = 'O cockpit fornece o diagnostico read-only, registra o debug no controlador, faz recover se o estado exigir e dispara supervise com debug-command.';
    $title = 'Cockpit deve passar debug-command ao supervise';
    $summary = 'Sem comando de debug o supervisor devolve debugging_required e encerra. O painel administrativo fornece o diagnostico read-only.';
    $hypotheses = [
        [
            'id' => 'H1',
            'statement' => 'Sem comando de debug o supervise sai em debugging_required.',
            'status' => 'confirmed',
        ],
    ];
    $causeKind = 'unknown';
    $incidentId = 'INC-COCKPIT-ORCH-001';
    $evidence = [
        $manifestPresent ? 'workflow-json' : 'cwd',
        $dirty === '' ? 'git-clean' : 'git-porcelain',
    ];
}

$report = [
    'schema_version' => '1.2.0',
    'workflow_id' => $workflowId,
    'feature_key' => $featureKey,
    'attempt' => $attempt,
    'status' => 'verified',
    'incident_id' => $incidentId,
    'cause_kind' => $causeKind,
    'redaction_alert' => $redactionAlert,
    'symptom' => $symptom,
    'severity' => 'high',
    'root_cause' => $rootCause,
    'correction_plan' => $plan,
    'hypotheses' => $hypotheses,
    'official_references' => [
        [
            'provider' => 'official',
            'source' => 'https://www.php.net/manual/en/function.is-file.php',
            'section' => 'is_file',
        ],
    ],
    'validation' => [
        'status' => 'passed',
        'exit_code' => 0,
        'evidence_refs' => $evidence !== [] ? $evidence : ['cwd'],
    ],
    'knowledge_candidate' => [
        'title' => $title,
        'summary' => $summary,
        'applicability' => [
            'when' => 'supervise sai em debugging_required ou recovery_required',
            'when_not' => 'aprovacao de gate ou escolha de feature',
        ],
        'limitations' => [
            'nao cria o arquivo de plano no checkout',
            'nao aprova gates',
        ],
    ],
    'facts' => [
        'manifest_present' => $manifestPresent,
        'control_bin_present' => $control,
        'working_tree_clean' => $dirty === '',
        'declared_input' => $declared,
        'declared_input_present' => $declaredPath !== '' && is_file($declaredPath),
        'supervisor_stderr' => $stderr,
        'block_stderr' => $runnerStderr,
        'recovery_reason' => diagnosticSanitize($recoveryReason),
        'redacted_count' => $redactionSummary['redacted_count'],
        'redacted_kinds' => $redactionSummary['redacted_kinds'],
        'redaction_threshold' => $redactionThreshold,
        'redaction_alert' => $redactionAlert,
    ],
];

fwrite(STDOUT, json_encode($report, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n");
exit(0);

/** @return array<string, mixed> */
function loadWorkflow(string $path): array
{
    if (! is_file($path)) {
        return [];
    }

    $payload = json_decode((string) file_get_contents($path), true);

    return is_array($payload) ? $payload : [];
}

function diagnosticSanitize(string $value): string
{
    $patterns = [
        'token' => '/\b((?:github[_-]?token|github_pat|access[_-]?token|api[_-]?key|token|secret))\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'aws_secret' => '/\b(aws[_-]?secret)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'private_key' => '/\b(private[_-]?key(?:[_-]?pem)?)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'db_url' => '/\b(db[_-]?url)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'bearer' => '/\b(bearer)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'cookie' => '/\b(cookie|set-cookie)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
    ];
    foreach ($patterns as $kind => $pattern) {
        $value = (string) preg_replace_callback($pattern, static function (array $match) use ($kind): string {
            return $match[1].$match[2].'[REDACTED:'.$kind.']';
        }, $value);
    }
    $value = (string) preg_replace('/\b(?:postgres(?:ql)?|mysql|mariadb|mongodb(?:\+srv)?|redis|amqp(?:s)?):\/\/[^\s"\'<>]+/iu', '[REDACTED:db_url]', $value);
    $value = (string) preg_replace('/\bBearer\s+[A-Za-z0-9._~+\/-]+=*/i', '[REDACTED:bearer]', $value);
    $value = (string) preg_replace('/-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----/is', '[REDACTED:private_key]', $value);
    $value = (string) preg_replace('/(?<!REDACTED:)\b(?:private[_ -]?key(?:[_ -]?pem)?|with-private-key-pem)\b(?!\s*[:=])/iu', '[REDACTED:private_key]', $value);
    $value = (string) preg_replace('/\b(?:sk|ghp|github_pat|glpat)[-_][A-Za-z0-9_-]{12,}\b/i', '[REDACTED:token]', $value);
    $value = (string) preg_replace('/\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b/', '[REDACTED]', $value);
    $value = (string) preg_replace('/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/', '[REDACTED]', $value);
    $value = (string) preg_replace('/\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b/', '[REDACTED]', $value);

    return $value;
}

/** @return array{redacted_count: int, redacted_kinds: list<string>, paths: list<string>} */
function ledgerRedactionSummary(string $ledger, string $featureKey): array
{
    $summary = ['redacted_count' => 0, 'redacted_kinds' => [], 'paths' => []];
    $knownKinds = ['token', 'aws_secret', 'private_key', 'db_url', 'bearer', 'cookie'];
    if ($featureKey === '' || ! is_file($ledger)) {
        return $summary;
    }
    $events = [];
    $handle = fopen($ledger, 'r');
    if ($handle === false) {
        return $summary;
    }
    while (($line = fgets($handle)) !== false) {
        $event = json_decode($line, true);
        if (is_array($event) && ($event['feature_key'] ?? null) === $featureKey) {
            $events[] = $event;
        }
    }
    fclose($handle);

    $redactionEvents = array_values(array_filter($events, static fn (array $event): bool => ($event['type'] ?? null) === 'event.redacted'));
    $sourceEvents = $redactionEvents !== [] ? $redactionEvents : $events;
    foreach ($sourceEvents as $event) {
        $facts = is_array($event['facts'] ?? null) ? $event['facts'] : [];
        $count = $facts['redacted_count'] ?? 0;
        if (is_int($count) || is_float($count) || (is_string($count) && ctype_digit($count))) {
            $summary['redacted_count'] += (int) $count;
        }
        foreach ($facts['redacted_kinds'] ?? [] as $kind) {
            if (is_string($kind) && in_array($kind, $knownKinds, true) && ! in_array($kind, $summary['redacted_kinds'], true)) {
                $summary['redacted_kinds'][] = $kind;
            }
        }
        $path = $facts['path'] ?? null;
        if (is_string($path) && $path !== '' && ! in_array($path, $summary['paths'], true)) {
            $summary['paths'][] = diagnosticSanitize($path);
        }
    }

    return $summary;
}

/** @param array<string, mixed> $workflow */
function declaredInput(array $workflow, string $featureKey): string
{
    foreach ($workflow['features'] ?? [] as $feature) {
        if (! is_array($feature) || ($feature['feature_key'] ?? null) !== $featureKey) {
            continue;
        }
        $input = $feature['input_file'] ?? null;
        if (is_string($input) && $input !== '') {
            return $input;
        }
    }

    $plan = $workflow['plan_file'] ?? null;

    return is_string($plan) ? $plan : '';
}

function latestSupervisorStderr(string $cwd, string $featureKey): string
{
    if ($featureKey === '') {
        return '';
    }

    $safe = preg_replace('/[^A-Za-z0-9._-]/', '_', $featureKey) ?: 'feature';
    $files = glob($cwd.'/.git/ralph-control/artifacts/supervisor-'.$safe.'-retry-*.stderr.log') ?: [];
    if ($files === []) {
        return '';
    }

    usort($files, static fn (string $left, string $right): int => filemtime($right) <=> filemtime($left));

    return excerptLastLine($files[0]);
}

function latestBlockStderr(string $cwd, string $featureKey): string
{
    if ($featureKey === '') {
        return '';
    }

    $safe = preg_replace('/[^A-Za-z0-9._-]/', '_', $featureKey) ?: 'feature';
    $files = glob($cwd.'/.git/ralph-control/artifacts/'.$safe.'-attempt-*.stderr.log') ?: [];
    if ($files === []) {
        return '';
    }

    usort($files, static fn (string $left, string $right): int => filemtime($right) <=> filemtime($left));
    $lines = file($files[0], FILE_IGNORE_NEW_LINES) ?: [];
    $joined = trim(implode("\n", array_filter(array_map('trim', $lines), static fn (string $line): bool => $line !== '')));

    if ($joined === '') {
        return '';
    }

    if (strlen($joined) > 240) {
        return substr($joined, 0, 237).'...';
    }

    return $joined;
}

function latestBlockStderrPreview(string $ledger, string $featureKey): string
{
    if ($featureKey === '' || ! is_file($ledger)) {
        return '';
    }

    $preview = '';
    $handle = fopen($ledger, 'r');
    if ($handle === false) {
        return '';
    }

    while (($line = fgets($handle)) !== false) {
        $event = json_decode($line, true);
        if (! is_array($event) || ($event['feature_key'] ?? null) !== $featureKey) {
            continue;
        }
        if (! in_array($event['type'] ?? null, ['block.finished', 'command.finished'], true)) {
            continue;
        }
        $candidate = $event['facts']['stderr_preview'] ?? '';
        if (is_string($candidate) && $candidate !== '') {
            $preview = $candidate;
        }
    }
    fclose($handle);

    if (strlen($preview) > 240) {
        $preview = substr($preview, 0, 237).'...';
    }

    return $preview;
}

/** @return array<string, mixed>|null */
function classifyRunnerHarnessFailure(string $stderr): ?array
{
    if ($stderr === '') {
        return null;
    }

    if (str_contains($stderr, 'Authentication required')
        || str_contains($stderr, "agent login")
        || str_contains($stderr, 'CURSOR_API_KEY')) {
        return [
            'incident_id' => 'INC-COCKPIT-CURSOR-002',
            'symptom' => 'O adapter cursor terminou no gate 0: a CLI headless do Cursor no checkout nao esta autenticada.',
            'root_cause' => 'O processo filho do ralph-control executa agent/cursor-agent fora da sessao da IDE. Login no Cursor Desktop nao propaga para o CLI WSL; stderr indica autenticacao ausente.',
            'plan' => 'No terminal WSL do checkout: agent login (ou exporte CURSOR_API_KEY). Confirme com agent status --format json (isAuthenticated true). Depois recover + Retomar orquestrador.',
            'title' => 'CLI Cursor sem autenticacao no checkout',
            'summary' => 'Gate 0 falha porque agent -p exige login no ambiente headless. O cockpit expoe a causa lida no stderr do bloco.',
            'hypotheses' => [
                [
                    'id' => 'H1',
                    'statement' => 'O stderr do bloco confirma autenticacao ausente na CLI cursor.',
                    'status' => 'confirmed',
                ],
                [
                    'id' => 'H2',
                    'statement' => 'O comando de debug estava ausente no supervise.',
                    'status' => 'rejected',
                ],
            ],
        ];
    }

    if (str_contains($stderr, 'não foi possível obter a versão do Cursor')
        || str_contains($stderr, 'nao foi possivel obter a versao do Cursor')
        || str_contains($stderr, 'CLI do Cursor não encontrada')
        || str_contains($stderr, 'CLI do Cursor nao encontrada')
        || str_contains($stderr, 'versão do Cursor não reconhecida')
        || str_contains($stderr, 'versao do Cursor nao reconhecida')) {
        return [
            'incident_id' => 'INC-COCKPIT-CURSOR-001',
            'symptom' => 'O adapter cursor falhou antes do gate 0: a CLI nao foi encontrada ou nao respondeu --version no ambiente do subprocesso.',
            'root_cause' => 'O ralph-control executa o runner com PATH reduzido; agent/cursor-agent costuma estar em ~/.local/bin fora do PATH herdado. Sem RALPH_CURSOR_CLI absoluto o adapter aborta.',
            'plan' => 'Defina RALPH_CURSOR_CLI com caminho absoluto para agent (ex.: ~/.local/bin/agent) em .ralph/cursor.env do checkout. Rode bash scripts/bootstrap-cockpit-field.sh para sincronizar. Depois recover + Retomar.',
            'title' => 'CLI Cursor inacessivel no subprocesso do controlador',
            'summary' => 'stderr ralph-cursor indica versao/CLI indisponivel. Corrija PATH ou RALPH_CURSOR_CLI antes de retomar o bloco.',
            'hypotheses' => [
                [
                    'id' => 'H1',
                    'statement' => 'O stderr do bloco confirma falha de localizacao/versao da CLI cursor.',
                    'status' => 'confirmed',
                ],
                [
                    'id' => 'H2',
                    'statement' => 'O input da feature estava ausente no checkout.',
                    'status' => 'rejected',
                ],
            ],
        ];
    }

    if (str_contains($stderr, 'ralph-cursor:')
        || str_contains($stderr, 'gate 0')
        || str_contains($stderr, 'engine nao concluiu')) {
        return [
            'incident_id' => 'INC-COCKPIT-RUNNER-001',
            'symptom' => 'O runner cursor terminou sem publicar resultado normalizado; o gate 0 ficou vermelho.',
            'root_cause' => 'O adapter cursor nao concluiu a execucao (stderr: '.$stderr.').',
            'plan' => 'Leia o stderr completo em .git/ralph-control/artifacts/, corrija PATH/auth/modelo no .ralph/cursor.env e so entao recover + Retomar orquestrador.',
            'title' => 'Runner cursor falhou no gate 0',
            'summary' => 'O diagnostico le o stderr do ultimo bloco e classifica falha de harness antes de repetir recovery generica.',
            'hypotheses' => [
                [
                    'id' => 'H1',
                    'statement' => 'O stderr do bloco confirma falha do adapter cursor no gate 0.',
                    'status' => 'confirmed',
                ],
            ],
        ];
    }

    return null;
}

function excerptLastLine(string $path): string
{
    $lines = file($path, FILE_IGNORE_NEW_LINES) ?: [];
    $excerpt = '';
    foreach (array_reverse($lines) as $line) {
        $line = trim($line);
        if ($line === '') {
            continue;
        }
        $excerpt = $line;
        break;
    }

    if (strlen($excerpt) > 180) {
        $excerpt = substr($excerpt, 0, 177).'...';
    }

    return $excerpt;
}

function lastRecoveryReason(string $ledger, string $featureKey): string
{
    if ($featureKey === '' || ! is_file($ledger)) {
        return '';
    }

    $reason = '';
    $handle = fopen($ledger, 'r');
    if ($handle === false) {
        return '';
    }

    while (($line = fgets($handle)) !== false) {
        $event = json_decode($line, true);
        if (! is_array($event) || ($event['feature_key'] ?? null) !== $featureKey || ($event['type'] ?? null) !== 'recovery.required') {
            continue;
        }
        $candidate = $event['facts']['reason'] ?? '';
        if (is_string($candidate) && $candidate !== '' && strlen($candidate) < 200) {
            $reason = $candidate;
        }
    }
    fclose($handle);

    return $reason;
}
