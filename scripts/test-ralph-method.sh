#!/usr/bin/env bash

# Os blocos PHP recebem dados por variáveis de ambiente; não há expansão shell
# intencional dentro das expressões delimitadas por aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-test.XXXXXX")"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

search_file() {
  if command -v rg >/dev/null 2>&1; then
    rg -q "$1" "$2"
  else
    grep -Eq "$1" "$2"
  fi
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [ "$expected" = "$actual" ] || fail "$label (esperado=$expected recebido=$actual)"
}

control() {
  php "$ROOT/bin/ralph-control" "$@"
}

json_field() {
  local json="$1"
  local field="$2"
  JSON_PAYLOAD="$json" JSON_FIELD="$field" php -r '
    $payload = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    $value = $payload[getenv("JSON_FIELD")] ?? null;
    if (! is_scalar($value)) {
        exit(1);
    }
    echo $value;
  '
}

mkdir -p "$TMP/bin"
git -C "$TMP" init -q
git -C "$TMP" config user.email ralph-method@example.invalid
git -C "$TMP" config user.name 'Ralph Method Test'
printf '%s\n' '# Fixture' > "$TMP/README.md"
printf '%s\n' '# Plano' > "$TMP/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_test","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Primeira feature","position":1},{"feature_key":"FEATURE-002","title":"Segunda feature","position":2}]}' > "$TMP/workflow.json"
git -C "$TMP" add README.md plan.md workflow.json
git -C "$TMP" commit -qm base

init_output="$(cd "$TMP" && control init --workflow wf_test --manifest workflow.json)"
assert_eq 'wf_test' "$(json_field "$init_output" workflow_id)" 'workflow inicializado'

claim_output="$(cd "$TMP" && control claim --workflow wf_test --feature FEATURE-001 --actor test)"
lease="$(json_field "$claim_output" lease_token)"

(cd "$TMP" && control trace --workflow wf_test --feature FEATURE-001 --lease "$lease" \
  --event started --execution-id exec_parent --runner codex --role implementation \
  --identity-status unavailable --identity-source runtime_not_exposed) >/dev/null
(cd "$TMP" && control trace --workflow wf_test --feature FEATURE-001 --lease "$lease" \
  --event completed --execution-id exec_child --parent-execution-id exec_parent \
  --runner hermes --runner-version 0.20.0 --provider minimax --model MiniMax-M3 \
  --session-id sess_test --role technical_review --identity-status exact \
  --identity-source usage_file) >/dev/null
(cd "$TMP" && control trace --workflow wf_test --feature FEATURE-001 --lease "$lease" \
  --event completed --execution-id exec_child --parent-execution-id exec_parent \
  --runner hermes --runner-version 0.20.0 --provider minimax --model MiniMax-M3 \
  --session-id sess_test --role technical_review --identity-status exact \
  --identity-source usage_file) >/dev/null

status_output="$(cd "$TMP" && control status)"
STATUS_JSON="$status_output" php -r '
  $status = json_decode(getenv("STATUS_JSON"), true, 512, JSON_THROW_ON_ERROR);
  $feature = $status["projection"]["features"][0];
  if (($feature["state"] ?? null) !== "running" || count($feature["delegations"] ?? []) !== 2) {
      exit(1);
  }
'

EVENTS_FILE="$TMP/.git/ralph-control/events.jsonl" php -r '
  $count = 0;
  foreach (file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      $count += ($event["type"] ?? null) === "delegation.completed" ? 1 : 0;
  }
  exit($count === 1 ? 0 : 1);
'

report_file="$TMP/.git/ralph-control/reports/trace/TRC.json"
report_output="$(cd "$TMP" && "$ROOT/bin/ralph-trace" report --workflow wf_test --format json --output "$report_file")"
REPORT_JSON="$report_output" REPORT_FILE="$report_file" php -r '
  $report = json_decode(getenv("REPORT_JSON"), true, 512, JSON_THROW_ON_ERROR);
  if (! preg_match("/^TRC-[0-9]{4}-[0-9]{4}$/", $report["document_id"] ?? "")) {
      exit(1);
  }
  if (($report["delegation_count"] ?? null) !== 2 || ! is_file(getenv("REPORT_FILE"))) {
      exit(1);
  }
'

parallel_trace_pids=()
for i in $(seq 1 24); do
  (cd "$TMP" && control trace --workflow wf_test --feature FEATURE-001 --lease "$lease" \
    --event started --execution-id "exec_parallel_$i" --runner codex --role implementation \
    --identity-status unavailable --identity-source runtime_not_exposed > "$TMP/trace-$i.log" 2>&1) &
  parallel_trace_pids+=("$!")
done
for pid in "${parallel_trace_pids[@]}"; do
  wait "$pid" || fail "trace concorrente falhou (pid=$pid)"
done
(cd "$TMP" && control verify) >/dev/null
EVENTS_FILE="$TMP/.git/ralph-control/events.jsonl" php -r '
  $count = 0;
  foreach (file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      $count += ($event["type"] ?? null) === "delegation.started" && str_starts_with((string) ($event["facts"]["execution_id"] ?? ""), "exec_parallel_") ? 1 : 0;
  }
  exit($count === 24 ? 0 : 1);
'

invalid_exit=0
invalid_output="$(cd "$TMP" && control trace --workflow wf_test --feature FEATURE-001 --lease "$lease" \
  --event completed --execution-id exec_invalid --runner agy --role review \
  --identity-status exact 2>&1 >/dev/null)" || invalid_exit=$?
assert_eq '2' "$invalid_exit" 'identidade exata sem modelo'
printf '%s' "$invalid_output" | grep -q 'effective-model' || fail 'mensagem da identidade exata'

workflow_exit=0
workflow_output="$(cd "$TMP" && control trace --workflow wf_other --feature FEATURE-001 --lease "$lease" \
  --event started --execution-id exec_wrong_workflow --runner codex --role implementation 2>&1 >/dev/null)" || workflow_exit=$?
assert_eq '2' "$workflow_exit" 'workflow divergente'
printf '%s' "$workflow_output" | grep -q 'workflow incompatível' || fail 'mensagem do workflow divergente'

(cd "$TMP" && control verify) >/dev/null

concurrency_tmp="$TMP/concurrency-fixture"
mkdir -p "$concurrency_tmp"
git -C "$concurrency_tmp" init -q
git -C "$concurrency_tmp" config user.email ralph-method@example.invalid
git -C "$concurrency_tmp" config user.name 'Ralph Method Concurrency Test'
printf '%s\n' '# Concorrência' > "$concurrency_tmp/README.md"
printf '%s\n' '# Plano' > "$concurrency_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_concurrency","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Execução exclusiva","position":1}]}' > "$concurrency_tmp/workflow.json"
git -C "$concurrency_tmp" add README.md plan.md workflow.json
git -C "$concurrency_tmp" commit -qm base
(cd "$concurrency_tmp" && control init --workflow wf_concurrency --manifest workflow.json >/dev/null)
concurrency_claim="$(cd "$concurrency_tmp" && control claim --workflow wf_concurrency --feature FEATURE-001 --actor concurrency-test)"
concurrency_lease="$(json_field "$concurrency_claim" lease_token)"

set +e
(cd "$concurrency_tmp" && control run --workflow wf_concurrency --feature FEATURE-001 --lease "$concurrency_lease" --command 'sleep 3' > "$TMP/concurrency-first.log" 2>&1) &
concurrency_first_pid=$!
for _ in $(seq 1 50); do
  if search_file '"type":"command.started"' "$concurrency_tmp/.git/ralph-control/events.jsonl" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
search_file '"type":"command.started"' "$concurrency_tmp/.git/ralph-control/events.jsonl" || fail 'primeira execução adquiriu lock e iniciou comando'

alias_exit=0
alias_output="$(cd "$concurrency_tmp" && control run --workflow wf_alias --feature FEATURE-001 --lease "$concurrency_lease" --command 'sleep 1' 2>&1)" || alias_exit=$?
assert_eq '2' "$alias_exit" 'workflow divergente não contorna exclusividade'
printf '%s' "$alias_output" | grep -q 'workflow incompatível' || fail 'mensagem do workflow divergente no run'

finish_exit=0
finish_output="$(cd "$concurrency_tmp" && control finish --workflow wf_concurrency --feature FEATURE-001 --lease "$concurrency_lease" --exit-code 0 2>&1)" || finish_exit=$?
assert_eq '12' "$finish_exit" 'finish concorrente foi rejeitado durante run'
printf '%s' "$finish_output" | grep -q 'execução ativa' || fail 'mensagem do finish concorrente'
concurrency_second_output="$(cd "$concurrency_tmp" && control run --workflow wf_concurrency --feature FEATURE-001 --lease "$concurrency_lease" --command 'sleep 1' 2>&1)"
concurrency_second_exit=$?
wait "$concurrency_first_pid"
concurrency_first_exit=$?
set -e
assert_eq '0' "$concurrency_first_exit" 'primeira execução concorrente terminou'
assert_eq '12' "$concurrency_second_exit" 'segunda execução concorrente foi rejeitada'
printf '%s' "$concurrency_second_output" | grep -q 'execução ativa' || fail 'mensagem da execução concorrente'
(cd "$concurrency_tmp" && control verify) >/dev/null
EVENTS_FILE="$concurrency_tmp/.git/ralph-control/events.jsonl" php -r '
  $events = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $counts = [];
  foreach ($events as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      $counts[$event["type"] ?? ""] = ($counts[$event["type"] ?? ""] ?? 0) + 1;
  }
  exit(($counts["attempt.started"] ?? 0) === 1 && ($counts["command.started"] ?? 0) === 1 && ($counts["block.finished"] ?? 0) === 1 ? 0 : 1);
'

crash_tmp="$TMP/crash-fixture"
mkdir -p "$crash_tmp"
git -C "$crash_tmp" init -q
git -C "$crash_tmp" config user.email ralph-method@example.invalid
git -C "$crash_tmp" config user.name 'Ralph Method Crash Test'
printf '%s\n' '# Crash' > "$crash_tmp/README.md"
printf '%s\n' '# Plano' > "$crash_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_crash","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Recuperação explícita","position":1}]}' > "$crash_tmp/workflow.json"
git -C "$crash_tmp" add README.md plan.md workflow.json
git -C "$crash_tmp" commit -qm base
(cd "$crash_tmp" && control init --workflow wf_crash --manifest workflow.json >/dev/null)
crash_claim="$(cd "$crash_tmp" && control claim --workflow wf_crash --feature FEATURE-001 --actor crash-test)"
crash_lease="$(json_field "$crash_claim" lease_token)"
(cd "$crash_tmp" && exec php "$ROOT/bin/ralph-control" run --workflow wf_crash --feature FEATURE-001 --lease "$crash_lease" --command 'sleep 5' > "$TMP/crash-first.log" 2>&1) &
crash_pid=$!
for _ in $(seq 1 50); do
  if search_file '"type":"command.started"' "$crash_tmp/.git/ralph-control/events.jsonl" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
search_file '"type":"command.started"' "$crash_tmp/.git/ralph-control/events.jsonl" || fail 'crash fixture iniciou comando'
kill -KILL "$crash_pid" 2>/dev/null || true
set +e
wait "$crash_pid"
crash_exit=$?
set -e
[ "$crash_exit" -ne 0 ] || fail 'controlador crash terminou com exit zero'

crash_active_exit=0
crash_active_output="$(cd "$crash_tmp" && control run --workflow wf_crash --feature FEATURE-001 --lease "$crash_lease" --command 'true' 2>&1)" || crash_active_exit=$?
assert_eq '12' "$crash_active_exit" 'replay foi rejeitado enquanto filho do crash estava vivo'
printf '%s' "$crash_active_output" | grep -q 'execução ativa' || fail 'mensagem do replay durante crash'

stale_output=''
stale_status=''
for _ in $(seq 1 70); do
  stale_output="$(cd "$crash_tmp" && control continue --workflow wf_crash 2>&1)"
  stale_status="$(printf '%s' "$stale_output" | php -r '$value = json_decode(stream_get_contents(STDIN), true); echo $value["status"] ?? "";')"
  if [ "$stale_status" = 'recovery_required' ]; then
    break
  fi
  sleep 0.1
done
assert_eq 'recovery_required' "$stale_status" 'crash exige recovery explícito após o filho terminar'
printf '%s' "$stale_output" | grep -q 'FEATURE-001' || fail 'recovery informa a feature interrompida'

retry_output="$(cd "$crash_tmp" && control retry --workflow wf_crash --feature FEATURE-001 --reason 'reteste após crash' 2>&1)"
retry_lease="$(json_field "$retry_output" lease_token)"
(cd "$crash_tmp" && control run --workflow wf_crash --feature FEATURE-001 --lease "$retry_lease" --command 'true' >/dev/null)

mkdir -p "$TMP/.phases/logs"
cat > "$TMP/.phases/logs/historical-feature-002.result.json" <<'JSON'
{
  "schema_version": "1.0.0",
  "runner": "opencode",
  "runner_version": "1.18.15",
  "provider": "opencode",
  "requested_model": "opencode/fixture-model",
  "effective_model": null,
  "identity_status": "declared",
  "identity_source": "requested_model",
  "execution_id": "exec_historical_feature_002",
  "execution_mode": "impl",
  "workflow_id": "wf_test",
  "feature_key": "FEATURE-002",
  "attempt": 0,
  "session_id": "ses_historical_feature_002",
  "status": "completed",
  "exit_code": 0,
  "fallback_used": null,
  "fallback_status": "unknown",
  "events_seen": 1,
  "event_bytes": 10,
  "terminal_event": "step_finish",
  "prompt_sha256": "deadbeef",
  "prompt_transport": "file",
  "permission_policy_hash": null,
  "permission_policy_status": "not_required",
  "verification_agent": null,
  "error_summary": null,
  "artifact_refs": ["historical"]
}
JSON

adversarial_command="set +e; php '$ROOT/bin/ralph-control' observe --workflow wf_test --feature FEATURE-001 --event child_attempt; php '$ROOT/bin/ralph-control' gate --workflow wf_test --feature FEATURE-001 --gate validation --status passed; php '$ROOT/bin/ralph-control' approve --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' release --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' advance --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' retry --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' recover --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' trace --workflow wf_test --feature FEATURE-001 --event completed --execution-id exec_child_attempt --runner codex --role implementation; echo 'RALPH_FEEDBACK {\"event\":\"phase_done\",\"source\":\"adversarial\"}'"
run_feedback_output="$(cd "$TMP" && control run --workflow wf_test --feature FEATURE-001 --lease "$lease" --command "$adversarial_command")"
printf '%s' "$run_feedback_output" | grep -q '^RALPH_FEEDBACK ' || fail 'control não retransmitiu feedback do bloco'

STATUS_JSON="$(cd "$TMP" && control status)" php -r '
  $status = json_decode(getenv("STATUS_JSON"), true, 512, JSON_THROW_ON_ERROR);
  $delegations = $status["projection"]["features"][0]["delegations"] ?? [];
  foreach ($delegations as $delegation) {
      if (($delegation["execution_id"] ?? null) === "exec_historical_feature_002") {
          exit(1);
      }
  }
'

EVENTS_FILE="$TMP/.git/ralph-control/events.jsonl" php -r '
  $bypass = 0;
  $hook = 0;
  foreach (file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      $bypass += ($event["type"] ?? null) === "policy.bypass_detected" ? 1 : 0;
      $hook += ($event["summary"] ?? null) === "Hook observou evento do Ralph" ? 1 : 0;
  }
  exit($bypass === 0 && $hook === 0 ? 0 : 1);
'
supervise_tmp="$TMP/supervise-fixture"
mkdir -p "$supervise_tmp/.ralph"
git -C "$supervise_tmp" init -q
git -C "$supervise_tmp" config user.email ralph-method@example.invalid
git -C "$supervise_tmp" config user.name 'Ralph Method Supervisor Test'
printf '%s\n' '# Supervisor' > "$supervise_tmp/README.md"
printf '%s\n' '# Plano' > "$supervise_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_supervise","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Teste do supervisor","position":1}]}' > "$supervise_tmp/workflow.json"
cat > "$supervise_tmp/fake-ralph.sh" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" > "${RALPH_SUPERVISE_ARGS_FILE:?}"
printf '%s\n' 'RALPH_FEEDBACK {"event":"run_end","source":"fake-supervisor"}'
exit 1
SH
chmod +x "$supervise_tmp/fake-ralph.sh"
printf '%s\n' "RALPH_BIN=$supervise_tmp/fake-ralph.sh" > "$supervise_tmp/.ralph/opencode.env"
git -C "$supervise_tmp" add .
git -C "$supervise_tmp" commit -qm base
(cd "$supervise_tmp" && control init --workflow wf_supervise --manifest workflow.json >/dev/null)
touch "$TMP/supervisor-proof.json"
set +e
supervise_output="$(cd "$supervise_tmp" && \
  RALPH_SUPERVISE_ARGS_FILE="$TMP/supervisor-args.log" \
  RALPH_OPENCODE_VERIFY_POLICY_PROOF="$TMP/supervisor-proof.json" \
  RALPH_OPENCODE_VERIFY_AGENT=ralph-review \
  control supervise --workflow wf_supervise --engine opencode --interval 1 \
    --stale-after 5 --activity-stale-after 5 --max-retries 0 --heartbeat-interval 1 2>&1)"
supervise_exit=$?
set -e
assert_eq '0' "$supervise_exit" 'supervisor terminou com recovery explícito'
printf '%s' "$supervise_output" | grep -q '"status": "debugging_required"' || fail 'supervisor não encaminhou a falha para systematic debugging'
grep -q -- '--engine opencode' "$TMP/supervisor-args.log" || fail 'supervisor não propagou engine opencode ao Ralph configurado'
grep -q -- '--no-verify' "$TMP/supervisor-args.log" || fail 'execução OpenCode supervisionada não separou implementação da revisão'

printf '%s' '{"evento":"incompleto"' >> "$TMP/.git/ralph-control/events.jsonl"
repair_output="$(cd "$TMP" && control repair-ledger --workflow wf_test)"
assert_eq 'recovery_required' "$(json_field "$repair_output" status)" 'repair-ledger recuperou corrupção terminal'
repair_report="$(json_field "$repair_output" report_id)"
printf '%s' "$repair_report" | grep -Eq '^RPT-[0-9]{4}-[0-9]{4}$' || fail 'repair-ledger gerou relatório numerado'
repair_backup="$(json_field "$repair_output" backup_path)"
[ -f "$repair_backup" ] || fail 'repair-ledger preservou backup do ledger'
(cd "$TMP" && control verify) >/dev/null

middle_tmp="${TMP}-middle"
cp -a "$TMP" "$middle_tmp"
middle_events="$middle_tmp/.git/ralph-control/events.jsonl"
awk 'NR == 3 { print "{\"evento\":\"corrupcao-intermediaria\"" } { print }' "$middle_events" > "$middle_events.tmp"
mv "$middle_events.tmp" "$middle_events"
middle_before="$(sha256sum "$middle_events")"
middle_output="$(cd "$middle_tmp" && control repair-ledger --workflow wf_test)"
assert_eq 'recovery_required' "$(json_field "$middle_output" status)" 'repair-ledger sinalizou corrupção intermediária'
middle_report="$(json_field "$middle_output" report_id)"
printf '%s' "$middle_report" | grep -Eq '^RPT-[0-9]{4}-[0-9]{4}$' || fail 'corrupção intermediária gerou relatório numerado'
middle_backup="$(json_field "$middle_output" backup_path)"
middle_prefix="$(json_field "$middle_output" prefix_path)"
middle_suffix="$(json_field "$middle_output" suffix_path)"
[ -f "$middle_backup" ] || fail 'corrupção intermediária preservou backup original'
[ -f "$middle_prefix" ] || fail 'corrupção intermediária preservou prefixo íntegro'
[ -f "$middle_suffix" ] || fail 'corrupção intermediária preservou sufixo forense'
middle_after="$(sha256sum "$middle_events")"
[ "$middle_before" = "$middle_after" ] || fail 'reparo intermediário alterou o ledger original'
set +e
(cd "$middle_tmp" && control verify) >/dev/null 2>&1
middle_verify_exit=$?
set -e
[ "$middle_verify_exit" -ne 0 ] || fail 'ledger intermediário corrompido foi tratado como íntegro'

utf_tmp="${TMP}-utf8"
mkdir -p "$utf_tmp"
git -C "$utf_tmp" init -q
git -C "$utf_tmp" config user.email ralph-method@example.invalid
git -C "$utf_tmp" config user.name 'Ralph Method UTF-8 Test'
printf '%s\n' '# UTF-8' > "$utf_tmp/README.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_utf8","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-UTF8","title":"Saída inválida","position":1}]}' > "$utf_tmp/workflow.json"
printf '%s\n' '# Plano' > "$utf_tmp/plan.md"
git -C "$utf_tmp" add .
git -C "$utf_tmp" commit -qm base
(cd "$utf_tmp" && control init --workflow wf_utf8 --manifest workflow.json >/dev/null)
utf_claim="$(cd "$utf_tmp" && control claim --workflow wf_utf8 --feature FEATURE-UTF8 --actor utf8-test)"
utf_lease="$(json_field "$utf_claim" lease_token)"
(cd "$utf_tmp" && control run --workflow wf_utf8 --feature FEATURE-UTF8 --lease "$utf_lease" --command "printf '\\377'" >/dev/null)
(cd "$utf_tmp" && control verify) >/dev/null

printf 'OK: Ralph Method smoke passou.\n'
