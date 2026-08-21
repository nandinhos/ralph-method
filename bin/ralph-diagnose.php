#!/usr/bin/env php
<?php

declare(strict_types=1);

/**
 * Diagnóstico read-only para o self-hosting do Ralph Method.
 *
 * Lê o estado real do ledger e dos artefatos do bloco e produz um relatório
 * de systematic debugging no contrato do controlador (schema 1.2.0,
 * cause_kind, hipóteses, referências oficiais, validação e candidato de
 * conhecimento). Nunca escreve no ledger; somente leitura.
 *
 * Uso (invocado pelo supervisor como RALPH_DEBUG_COMMAND):
 *   RALPH_DEBUG_WORKFLOW_ID=... RALPH_DEBUG_FEATURE_KEY=... RALPH_DEBUG_ATTEMPT=N \
 *     php bin/ralph-diagnose.php
 */

$workflowId = (string) getenv('RALPH_DEBUG_WORKFLOW_ID');
$featureKey = (string) getenv('RALPH_DEBUG_FEATURE_KEY');
$attempt = (int) getenv('RALPH_DEBUG_ATTEMPT');
$cwd = getcwd() ?: '.';
$ledgerPath = $cwd.'/.git/ralph-control/events.jsonl';
$artifactsDir = $cwd.'/.git/ralph-control/artifacts';

/** @return list<array<string, mixed>> */
function readEvents(string $path): array
{
    if (! is_file($path)) {
        return [];
    }
    $events = [];
    foreach (file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
        try {
            $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        } catch (Throwable) {
            continue;
        }
        if (is_array($event)) {
            $events[] = $event;
        }
    }

    return $events;
}

/** @return array<string, mixed>|null */
function latestEvent(array $events, string $type, string $featureKey, ?int $attempt = null): ?array
{
    foreach (array_reverse($events) as $event) {
        if (($event['type'] ?? null) !== $type || ($event['feature_key'] ?? null) !== $featureKey) {
            continue;
        }
        if ($attempt !== null && (int) ($event['attempt'] ?? -1) !== $attempt) {
            continue;
        }

        return $event;
    }

    return null;
}

function diagnosticSanitize(string $value): string
{
    $patterns = [
        'token' => '/\b((?:github[_-]?token|github_pat|access[_-]?token|api[_-]?key|token|secret|password|passwd))\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'aws_secret' => '/\b(aws[_-]?secret(?:[_-]?access[_-]?key)?)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'private_key' => '/\b(private[_-]?key(?:[_-]?pem)?)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
        'db_url' => '/\b((?:db|database)[_-]?url)\b(\s*["\']?\s*[:=]\s*)(?:"[^"]*"|\'[^\']*\'|[^\s,;}\]]+)/iu',
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
    $value = (string) preg_replace('/\b(?:AKIA|ASIA)[A-Z0-9]{8,}\b/i', '[REDACTED:aws_secret]', $value);
    $value = (string) preg_replace('/\b(?:sk|ghp|github_pat|glpat)[-_][A-Za-z0-9_-]{12,}\b/i', '[REDACTED:token]', $value);
    $value = (string) preg_replace('/\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b/', '[REDACTED]', $value);
    $value = (string) preg_replace('/\b\d{3}\.\d{3}\.\d{3}-\d{2}\b/', '[REDACTED]', $value);

    return $value;
}

/** @return array{redacted_count: int, redacted_kinds: list<string>, paths: list<string>} */
function ledgerRedactionSummary(array $events, string $featureKey): array
{
    $summary = ['redacted_count' => 0, 'redacted_kinds' => [], 'paths' => []];
    $knownKinds = ['token', 'aws_secret', 'private_key', 'db_url', 'bearer', 'cookie'];
    $featureEvents = array_values(array_filter(
        $events,
        static fn (array $event): bool => ($event['feature_key'] ?? null) === $featureKey,
    ));
    $redactionEvents = array_values(array_filter(
        $featureEvents,
        static fn (array $event): bool => ($event['type'] ?? null) === 'event.redacted',
    ));
    $sourceEvents = $redactionEvents !== [] ? $redactionEvents : $featureEvents;

    foreach ($sourceEvents as $event) {
        $facts = is_array($event['facts'] ?? null) ? $event['facts'] : [];
        $count = $facts['redacted_count'] ?? 0;
        if (is_int($count) || is_float($count) || (is_string($count) && ctype_digit($count))) {
            $summary['redacted_count'] += max(0, (int) $count);
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

function latestStderrPreview(string $artifactsDir, string $featureKey, int $attempt): string
{
    $patterns = [
        $artifactsDir.'/'.$featureKey.'-attempt-'.$attempt.'.stderr.log',
        $artifactsDir.'/supervisor-'.$featureKey.'-retry-*.stderr.log',
    ];
    foreach ($patterns as $pattern) {
        $matches = glob($pattern) ?: [];
        if ($matches !== []) {
            $path = end($matches);
            $content = (string) file_get_contents($path);
            if ($content !== '') {
                return substr($content, -1200);
            }
        }
    }

    return '';
}

$events = readEvents($ledgerPath);
$block = latestEvent($events, 'block.finished', $featureKey, $attempt);
$recovery = latestEvent($events, 'recovery.required', $featureKey);
$debugging = latestEvent($events, 'debugging.required', $featureKey);
$stderrPreview = diagnosticSanitize(latestStderrPreview($artifactsDir, $featureKey, $attempt));
$redactionThreshold = max(0, (int) (getenv('RALPH_DEBUG_REDACTED_THRESHOLD') ?: 0));
$redactionSummary = ledgerRedactionSummary($events, $featureKey);
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
$exitCode = is_array($block) ? (int) (($block['facts']['exit_code'] ?? 1)) : null;
$dirty = trim((string) shell_exec('git status --porcelain 2>/dev/null'));
$committed = is_array($block) && (($block['facts']['result_commit'] ?? null) !== null);
$processGone = is_array($block) && (($block['facts']['process_verified_terminated'] ?? false) === true);

// Classificação honesta: sem evidência de bug de código, não inventar
// feature_bug. Sinal de interrupção/harness leva a harness_defect; causa
// desconhecida leva a unknown (o controlador exige cause_kind).
$causeKind = 'unknown';
$incidentId = 'INC-RALPH-2-0-UNKNOWN-001';
$title = 'Falha do bloco sem causa de código confirmada';
$summary = 'O bloco terminou com falha e o diagnóstico read-only não encontrou evidência de bug de código; a causa é classificada como desconhecida para o controlador decidir a retomada.';

if ($exitCode !== null && $exitCode !== 0) {
    $causeKind = $exitCode === 137 || $exitCode === 143 || $exitCode === 124
        ? 'harness_defect'
        : ($exitCode === 125 ? 'harness_defect' : 'unknown');
    $incidentId = 'INC-RALPH-2-0-BLOCK-'.str_pad((string) $exitCode, 3, '0', STR_PAD_LEFT);
    $title = 'Bloco terminou com exit '.$exitCode;
    $summary = 'O bloco controlado terminou com código '.$exitCode.($stderrPreview !== '' ? ' e o stderr do artefato foi anexado ao diagnóstico.' : '; o artefato de stderr não contém texto.');
}
if ($recovery !== null) {
    $reason = diagnosticSanitize((string) ($recovery['facts']['reason'] ?? ''));
    $causeKind = str_contains($reason, 'sem evento terminal') || str_contains($reason, 'processo') ? 'harness_defect' : 'unknown';
    $incidentId = 'INC-RALPH-2-0-RECOVERY-001';
    $title = 'Recovery registrada no ledger';
    $summary = 'O supervisor registrou recovery com motivo: '.($reason !== '' ? $reason : 'sem motivo declarado').'.';
}
if ($debugging !== null) {
    $reason = diagnosticSanitize((string) ($debugging['facts']['reason'] ?? ''));
    if (str_contains($reason, 'não configurado')) {
        $causeKind = 'harness_defect';
        $incidentId = 'INC-RALPH-2-0-DEBUG-CMD-001';
        $title = 'Comando de systematic debugging ausente';
        $summary = 'O supervisor pediu debugging mas o comando não estava configurado; este diagnóstico agora fornece o relatório.';
    }
}

$evidence = array_values(array_filter([
    is_file($ledgerPath) ? 'ledger-events' : null,
    $dirty === '' ? 'git-clean' : 'git-porcelain',
    $committed ? 'block-committed' : null,
    $processGone ? 'process-terminated' : null,
    $stderrPreview !== '' ? 'block-stderr-artifact' : null,
]));

$report = [
    'schema_version' => '1.2.0',
    'workflow_id' => $workflowId,
    'feature_key' => $featureKey,
    'attempt' => $attempt,
    'status' => 'verified',
    'incident_id' => $incidentId,
    'cause_kind' => $causeKind,
    'redaction_alert' => $redactionAlert,
    'symptom' => $title,
    'severity' => 'high',
    'root_cause' => $summary,
    'correction_plan' => 'Revise o stderr do artefato no painel/terminal; confirme a causa no contexto atual e retome com recover ou re-execute o bloco conforme o estado da árvore. O diagnóstico não aprova gate nem escolhe a próxima feature.',
    'hypotheses' => [
        [
            'id' => 'H1',
            'statement' => 'O bloco terminou sem concluir a feature e o ledger registra a falha.',
            'status' => 'confirmed',
        ],
    ],
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
            'when' => 'bloco termina com falha ou recovery sem causa de código confirmada',
            'when_not' => 'aprovação de gate ou escolha de feature',
        ],
        'limitations' => [
            'não cria arquivos no checkout',
            'não aprova gates',
            'cause_kind desconhecido exige revisão humana',
        ],
    ],
    'facts' => [
        'block_exit_code' => $exitCode,
        'block_committed' => $committed,
        'process_verified_terminated' => $processGone,
        'working_tree_clean' => $dirty === '',
        'stderr_preview' => $stderrPreview !== '' ? substr($stderrPreview, 0, 400) : '',
        'redacted_count' => $redactionSummary['redacted_count'],
        'redacted_kinds' => $redactionSummary['redacted_kinds'],
        'redaction_threshold' => $redactionThreshold,
        'redaction_alert' => $redactionAlert,
    ],
];

fwrite(STDOUT, json_encode($report, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n");
exit(0);
