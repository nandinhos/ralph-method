#!/usr/bin/env bash

# Teste determinístico do terminal dashboard (bin/ralph-watch) do Ralph Method 2.0
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-watch-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

# 1. Lint do bin/ralph-watch
php -l "$ROOT/bin/ralph-watch" >/dev/null || fail 'bin/ralph-watch com erro de sintaxe'

# 2. Ajuda (--help e -h)
php "$ROOT/bin/ralph-watch" --help | grep -q "Ralph Method 2.0 — Terminal Dashboard" || fail '--help não exibiu ajuda esperada'
php "$ROOT/bin/ralph-watch" -h | grep -q "Uso:" || fail '-h não exibiu ajuda esperada'

# 3. Validação de argumentos obrigatórios
set +e
php "$ROOT/bin/ralph-watch" >/dev/null 2>&1
no_wf_exit=$?
php "$ROOT/bin/ralph-watch" --workflow wf_test --interval 0 >/dev/null 2>&1
invalid_interval_exit=$?
set -e

[ "$no_wf_exit" -eq 2 ] || fail 'execução sem --workflow deveria retornar exit 2'
[ "$invalid_interval_exit" -eq 2 ] || fail 'execução com --interval 0 deveria retornar exit 2'

# 4. Ledger ausente / inexistente
missing_events="$TMP/nonexistent/events.jsonl"
missing_json="$(php "$ROOT/bin/ralph-watch" --workflow wf_missing --events-file "$missing_events" --once --json)"

MISSING_JSON="$missing_json" php -r '
    $snap = json_decode(getenv("MISSING_JSON"), true, 512, JSON_THROW_ON_ERROR);
    if (($snap["health"] ?? null) !== "waiting"
        || ($snap["state"] ?? null) !== "idle"
        || ($snap["workflow_id"] ?? null) !== "wf_missing"
        || ($snap["total_features"] ?? null) !== 0
        || ($snap["event_count"] ?? null) !== 0
        || ! str_contains((string) ($snap["message"] ?? ""), "ledger ausente")) {
        exit(1);
    }
' || fail 'ledger ausente não gerou snapshot com estado explícito esperado'

# Renderização texto com ledger ausente
missing_text="$(php "$ROOT/bin/ralph-watch" --workflow wf_missing --events-file "$missing_events" --once)"
printf '%s\n' "$missing_text" | grep -q "AGUARDANDO" || fail 'texto com ledger ausente não contém AGUARDANDO'
printf '%s\n' "$missing_text" | grep -q "nenhuma feature carregada" || fail 'texto com ledger ausente não exibe aviso de fila'

# 5. Ledger populado com eventos da Onda 1 (Telemetria + Gates + Delta mtime)
events_file="$TMP/events.jsonl"
cat > "$events_file" <<'JSONL'
{"schema_version":"1.3.0","event_id":"evt-001","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"workflow.initialized","timestamp":"2026-08-21T12:00:00Z","facts":{"features":[{"key":"FEATURE-101","title":"Terminal dashboard ralph-watch"},{"key":"FEATURE-102","title":"Systematic debugging ao vivo"}]}}
{"schema_version":"1.3.0","event_id":"evt-002","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"feature.claimed","timestamp":"2026-08-21T12:00:05Z"}
{"schema_version":"1.3.0","event_id":"evt-003","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"attempt.started","timestamp":"2026-08-21T12:00:10Z"}
{"schema_version":"1.3.0","event_id":"evt-004","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"command.started","timestamp":"2026-08-21T12:00:15Z"}
{"schema_version":"1.3.0","event_id":"evt-005","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"telemetry.activity","timestamp":"2026-08-21T12:00:30Z","facts":{"activity_preview":"Executando checagem de sintaxe e testes de integração","elapsed":15,"idle_seconds":2,"phase":"running"}}
{"schema_version":"1.3.0","event_id":"evt-006","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"block.finished","timestamp":"2026-08-21T12:00:40Z"}
{"schema_version":"1.3.0","event_id":"evt-007","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"gate.started","timestamp":"2026-08-21T12:00:45Z","facts":{"gate":"validation"}}
{"schema_version":"1.3.0","event_id":"evt-008","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"gate.passed","timestamp":"2026-08-21T12:00:55Z","facts":{"gate":"validation"}}
{"schema_version":"1.3.0","event_id":"evt-009","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"gate.started","timestamp":"2026-08-21T12:00:56Z","facts":{"gate":"quality"}}
{"schema_version":"1.3.0","event_id":"evt-010","workflow_id":"wf_watch_demo","feature_key":"FEATURE-101","attempt":1,"type":"gate.stalled","timestamp":"2026-08-21T12:02:00Z","facts":{"gate":"quality","age_seconds":64,"threshold":60}}
JSONL

# Fixa o relógio determinístico em 2026-08-21T12:02:10Z (epoch 1787313730)
TEST_EPOCH="1787313730"

before_hash="$(sha256sum "$events_file")"
snapshot_json="$(RALPH_TEST_CLOCK_EPOCH="$TEST_EPOCH" php "$ROOT/bin/ralph-watch" --workflow wf_watch_demo --events-file "$events_file" --once --json)"
after_hash="$(sha256sum "$events_file")"
[ "$before_hash" = "$after_hash" ] || fail 'ralph-watch mutou o ledger de eventos'

# Valida snapshot JSON completo
SNAPSHOT_JSON="$snapshot_json" php -r '
    $snap = json_decode(getenv("SNAPSHOT_JSON"), true, 512, JSON_THROW_ON_ERROR);
    if (($snap["workflow_id"] ?? null) !== "wf_watch_demo") {
        exit(1);
    }
    if (($snap["cursor"] ?? null) !== "FEATURE-101") {
        exit(2);
    }
    if (($snap["health"] ?? null) !== "gate_stalled") {
        exit(3);
    }
    if (($snap["total_features"] ?? null) !== 2 || ($snap["completed_features"] ?? null) !== 0) {
        exit(4);
    }
    $gates = $snap["gates"] ?? [];
    if (($gates["validation"] ?? null) !== "passed" || ($gates["quality"] ?? null) !== "stalled" || ($gates["runtime_evidence"] ?? null) !== "pending") {
        exit(5);
    }
    $gateAges = $snap["gate_ages"] ?? [];
    if (($gateAges["validation"] ?? null) !== 10 || ($gateAges["quality"] ?? null) !== 74) {
        exit(6);
    }
    $telemetry = $snap["last_telemetry"] ?? [];
    if (! str_contains((string) ($telemetry["activity_preview"] ?? ""), "Executando checagem")
        || ($telemetry["elapsed"] ?? null) !== 15
        || ($telemetry["idle_seconds"] ?? null) !== 2) {
        exit(7);
    }
    $lastEvent = $snap["last_event"] ?? [];
    if (($lastEvent["type"] ?? null) !== "gate.stalled") {
        exit(8);
    }
    $queue = $snap["queue"] ?? [];
    if (count($queue) !== 2 || ($queue[0]["feature_key"] ?? null) !== "FEATURE-101" || ($queue[1]["feature_key"] ?? null) !== "FEATURE-102") {
        exit(9);
    }
' || fail 'campos do snapshot JSON não correspondem ao esperado'

# Pipe direto para jq exit 0
RALPH_TEST_CLOCK_EPOCH="$TEST_EPOCH" php "$ROOT/bin/ralph-watch" --workflow wf_watch_demo --events-file "$events_file" --once --json | jq . >/dev/null || fail 'pipe ralph-watch --once --json | jq . falhou'

# 6. Renderização ANSI em modo texto (com gate stalled inicial)
snapshot_text="$(RALPH_TEST_CLOCK_EPOCH="$TEST_EPOCH" php "$ROOT/bin/ralph-watch" --workflow wf_watch_demo --events-file "$events_file" --once)"
printf '%s\n' "$snapshot_text" | grep -q "TERMINAL DASHBOARD" || fail 'dashboard não renderizou cabeçalho'
printf '%s\n' "$snapshot_text" | grep -q "FEATURE-101" || fail 'dashboard não exibiu FEATURE-101'
printf '%s\n' "$snapshot_text" | grep -q "STALLED" || fail 'dashboard não exibiu badge STALLED'
printf '%s\n' "$snapshot_text" | grep -q "validation" || fail 'dashboard não listou gate validation'
printf '%s\n' "$snapshot_text" | grep -q "Executando checagem" || fail 'dashboard não exibiu preview de telemetria'

# 7. Comprovação de leitura delta por mtime
READER_TEST_SCRIPT="$TMP/test-reader-delta.php"
cat > "$READER_TEST_SCRIPT" <<'PHP'
<?php
declare(strict_types=1);

require_once $argv[1];

$root = $argv[2];
$workflowId = $argv[3];
$eventsFile = $argv[4];

$reader = new RalphWatchReader($root, $workflowId, $eventsFile);

// Leitura 1: arquivo inicial (não em cache)
$snap1 = $reader->collectSnapshot();
if ($snap1['delta']['cached'] !== false || $snap1['delta']['events_loaded'] !== 10) {
    fwrite(STDERR, "Erro snap1: esperado cached=false e events_loaded=10\n");
    exit(1);
}

// Leitura 2: mesmo arquivo sem alteração (deve usar cache de delta)
$snap2 = $reader->collectSnapshot();
if ($snap2['delta']['cached'] !== true || $snap2['delta']['events_loaded'] !== 10) {
    fwrite(STDERR, "Erro snap2: esperado cached=true e events_loaded=10\n");
    exit(2);
}

// Adiciona evento novo ao ledger
$newEvent = json_encode([
    'schema_version' => '1.3.0',
    'event_id' => 'evt-011',
    'workflow_id' => $workflowId,
    'feature_key' => 'FEATURE-101',
    'attempt' => 1,
    'type' => 'gate.passed',
    'timestamp' => '2026-08-21T12:02:20Z',
    'facts' => ['gate' => 'quality'],
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n";

file_put_contents($eventsFile, $newEvent, FILE_APPEND);
touch($eventsFile, time() + 5); // Garante novo mtime

// Leitura 3: arquivo modificado (cached deve ser false e carregar o evento novo)
$snap3 = $reader->collectSnapshot();
if ($snap3['delta']['cached'] !== false || $snap3['delta']['events_loaded'] !== 11) {
    fwrite(STDERR, "Erro snap3: esperado cached=false e events_loaded=11\n");
    exit(3);
}

// Verifica que o gate quality passou após o novo evento
if (($snap3['gates']['quality'] ?? null) !== 'passed') {
    fwrite(STDERR, "Erro snap3: esperado gate quality passed\n");
    exit(4);
}

exit(0);
PHP

php "$READER_TEST_SCRIPT" "$ROOT/bin/ralph-watch" "$TMP" "wf_watch_demo" "$events_file" || fail 'prova de delta por mtime falhou'

# 8. Renderização ANSI em modo texto pós-mutação (quality passou)
snapshot_text_after="$(RALPH_TEST_CLOCK_EPOCH="$TEST_EPOCH" php "$ROOT/bin/ralph-watch" --workflow wf_watch_demo --events-file "$events_file" --once)"
printf '%s\n' "$snapshot_text_after" | grep -q "PASSED" || fail 'dashboard não exibiu badge PASSED após atualização'

# 9. Systematic debugging ao vivo no ralph-watch (FEATURE-101 Phase 4)
debug_event=$(cat <<'JSON'
{"schema_version":"1.3.0","event_id":"evt-012","workflow_id":"wf_watch_demo","feature_key":"FEATURE-102","attempt":1,"type":"debug.progress","timestamp":"2026-08-21T12:02:25Z","facts":{"phase":"hypotheses_evaluated","status":"investigating","document_id":"DBG-2026-0042","attempt":1,"cause_kind":"feature_bug","confirmed_hypotheses":1,"rejected_hypotheses":1,"hypotheses":[{"id":"H1","status":"confirmed","statement":"Incompatibilidade no tipo retornado"},{"id":"H2","status":"rejected","statement":"Timeout de rede"}],"official_references":[{"provider":"Context7","source":"https://docs.example.invalid/guide","section":"Types"}]}}
JSON
)
printf '%s\n' "$debug_event" >> "$events_file"
touch "$events_file"

debug_snapshot_json="$(RALPH_TEST_CLOCK_EPOCH="$TEST_EPOCH" php "$ROOT/bin/ralph-watch" --workflow wf_watch_demo --events-file "$events_file" --once --json)"
DEBUG_SNAPSHOT="$debug_snapshot_json" php -r '
    $snap = json_decode(getenv("DEBUG_SNAPSHOT"), true, 512, JSON_THROW_ON_ERROR);
    $dbg = $snap["debug"] ?? null;
    if (! is_array($dbg)) {
        fwrite(STDERR, "debug ausente no snapshot do ralph-watch\n");
        exit(1);
    }
    if (($dbg["document_id"] ?? "") !== "DBG-2026-0042"
        || ($dbg["cause_kind"] ?? "") !== "feature_bug"
        || ($dbg["confirmed_hypotheses"] ?? 0) !== 1
        || ($dbg["rejected_hypotheses"] ?? 0) !== 1) {
        fwrite(STDERR, "campos de debug no snapshot inválidos: ".json_encode($dbg)."\n");
        exit(2);
    }
' || fail 'debug no snapshot JSON do ralph-watch inválido'

debug_snapshot_text="$(RALPH_TEST_CLOCK_EPOCH="$TEST_EPOCH" php "$ROOT/bin/ralph-watch" --workflow wf_watch_demo --events-file "$events_file" --once)"
printf '%s\n' "$debug_snapshot_text" | grep -q "SYSTEMATIC DEBUGGING AO VIVO" || fail 'dashboard não exibiu seção SYSTEMATIC DEBUGGING AO VIVO'
printf '%s\n' "$debug_snapshot_text" | grep -q "DBG-2026-0042" || fail 'dashboard não exibiu document_id do debug'
printf '%s\n' "$debug_snapshot_text" | grep -q "feature_bug" || fail 'dashboard não exibiu cause_kind do debug'
printf '%s\n' "$debug_snapshot_text" | grep -q "Context7" || fail 'dashboard não exibiu referência Context7 do debug'

printf 'OK: todos os testes de bin/ralph-watch (TUI, delta mtime, JSON, ledger ausente, gates e debug ao vivo) passaram.\n'

