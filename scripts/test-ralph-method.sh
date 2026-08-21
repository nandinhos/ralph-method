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
  RALPH_DEBUG_COMMAND='' \
  RALPH_SUPERVISE_ARGS_FILE="$TMP/supervisor-args.log" \
  RALPH_OPENCODE_VERIFY_POLICY_PROOF="$TMP/supervisor-proof.json" \
  RALPH_OPENCODE_VERIFY_AGENT=ralph-review \
  control supervise --workflow wf_supervise --engine opencode --interval 1 \
    --test-cmd fixture-quality-gate \
    --stale-after 5 --activity-stale-after 5 --max-retries 0 --heartbeat-interval 1 2>&1)"
supervise_exit=$?
set -e
assert_eq '0' "$supervise_exit" 'supervisor terminou com recovery explícito'
printf '%s' "$supervise_output" | grep -q '"status": "debugging_required"' || fail 'supervisor não encaminhou a falha para systematic debugging'
grep -q -- '--engine opencode' "$TMP/supervisor-args.log" || fail 'supervisor não propagou engine opencode ao Ralph configurado'
grep -q -- '--test-cmd fixture-quality-gate' "$TMP/supervisor-args.log" || fail 'supervisor não propagou o gate de qualidade ao Ralph configurado'
grep -q -- '--no-verify' "$TMP/supervisor-args.log" || fail 'execução OpenCode supervisionada não separou implementação da revisão'

stale_supervise_tmp="$TMP/supervise-stale-fixture"
mkdir -p "$stale_supervise_tmp/.ralph"
git -C "$stale_supervise_tmp" init -q
git -C "$stale_supervise_tmp" config user.email ralph-method@example.invalid
git -C "$stale_supervise_tmp" config user.name 'Ralph Method Supervisor Stale Test'
printf '%s\n' '# Supervisor stale' > "$stale_supervise_tmp/README.md"
printf '%s\n' '# Plano' > "$stale_supervise_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_supervise_stale","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Retry com novo fencing","position":1}]}' > "$stale_supervise_tmp/workflow.json"
cat > "$stale_supervise_tmp/fake-ralph.sh" <<'SH'
#!/usr/bin/env bash
set -u
if [ "${RALPH_EXECUTION_ATTEMPT:-0}" -ge 2 ]; then
  exit 0
fi
sleep 30
SH
chmod +x "$stale_supervise_tmp/fake-ralph.sh"
printf '%s\n' "RALPH_BIN=$stale_supervise_tmp/fake-ralph.sh" > "$stale_supervise_tmp/.ralph/codex.env"
git -C "$stale_supervise_tmp" add .
git -C "$stale_supervise_tmp" commit -qm base
(cd "$stale_supervise_tmp" && control init --workflow wf_supervise_stale --manifest workflow.json >/dev/null)
set +e
(cd "$stale_supervise_tmp" && \
  control supervise --workflow wf_supervise_stale --engine codex --interval 1 \
    --test-cmd true --quality-command true --runtime-evidence-command true \
    --technical-review-command true --curation-command true \
    --stale-after 2 --activity-stale-after 2 --max-retries 1 --heartbeat-interval 1 \
    > "$TMP/stale-supervise.log" 2>&1) &
stale_supervisor_pid=$!
set -e
stale_events="$stale_supervise_tmp/.git/ralph-control/events.jsonl"
for _ in $(seq 1 80); do
  if search_file '"type":"command.started"' "$stale_events" 2>/dev/null; then
    break
  fi
  sleep 0.1
done
search_file '"type":"command.started"' "$stale_events" || fail 'supervisor stale não iniciou comando controlado'
stale_run_pid="$(ps -eo pid=,args= | awk '$0 ~ /bin\/ralph-control run --workflow wf_supervise_stale/ {print $1; exit}')"
[ -n "$stale_run_pid" ] || fail 'não foi possível localizar o processo run do supervisor stale'
stale_command_pid="$(EVENTS_FILE="$stale_events" php -r '
  foreach (file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"] ?? null) === "command.started") {
          echo $event["facts"]["pid"] ?? "";
          exit;
      }
  }
')"
[ -n "$stale_command_pid" ] || fail 'não foi possível localizar o processo controlado stale'
stale_pgid="$(ps -o pgid= -p "$stale_command_pid" | tr -d ' ')"
kill -KILL "$stale_run_pid" 2>/dev/null || true
if [ -n "$stale_pgid" ] && [ "$stale_pgid" != "0" ] && [ "$stale_pgid" != "$$" ]; then
  kill -KILL -- "-$stale_pgid" 2>/dev/null || true
fi
set +e
wait "$stale_supervisor_pid"
stale_supervisor_exit=$?
set -e
assert_eq '0' "$stale_supervisor_exit" 'supervisor stale concluiu a recuperação automática'
stale_supervise_output="$(<"$TMP/stale-supervise.log")"
printf '%s' "$stale_supervise_output" | grep -q '"status": "complete"' || fail 'supervisor stale não concluiu após novo fencing'
EVENTS_FILE="$stale_events" php -r '
  $attempts = [];
  $leases = [];
  foreach (file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"] ?? null) === "feature.claimed") {
          $attempts[] = $event["attempt"] ?? null;
          $leases[] = $event["lease_token_hash"] ?? null;
      }
  }
  if ($attempts !== [1, 2] || count(array_unique($leases)) !== 2) {
      fwrite(STDERR, "fencing inválido: ".json_encode([$attempts, $leases])."\n");
      exit(1);
  }
'

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
(cd "$utf_tmp" && control run --workflow wf_utf8 --feature FEATURE-UTF8 --lease "$utf_lease" --command "printf '\\377\\342'" >/dev/null)
(cd "$utf_tmp" && control verify) >/dev/null

printf 'OK: Ralph Method smoke passou.\n'

# ---------------------------------------------------------------------------
# Reconfirmação de exit code: exit 1 capturado + stdout "tudo verde" ->
# exit ratificado para 0 (camada de robustez contra delay do wrapper).
# ---------------------------------------------------------------------------
reconfirm_tmp="$TMP/reconfirm-fixture"
mkdir -p "$reconfirm_tmp"
git -C "$reconfirm_tmp" init -q
git -C "$reconfirm_tmp" config user.email ralph-method@example.invalid
git -C "$reconfirm_tmp" config user.name 'Ralph Method Reconfirm Test'
printf '%s\n' '# Reconfirm' > "$reconfirm_tmp/README.md"
printf '%s\n' '# Plano' > "$reconfirm_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_reconfirm","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Reconfirm","position":1}]}' > "$reconfirm_tmp/workflow.json"
git -C "$reconfirm_tmp" add .
git -C "$reconfirm_tmp" commit -qm base
(cd "$reconfirm_tmp" && control init --workflow wf_reconfirm --manifest workflow.json >/dev/null)
reconfirm_claim="$(cd "$reconfirm_tmp" && control claim --workflow wf_reconfirm --feature FEATURE-001 --actor reconfirm)"
reconfirm_lease="$(json_field "$reconfirm_claim" lease_token)"
reconfirm_output="$(cd "$reconfirm_tmp" && control run --workflow wf_reconfirm --feature FEATURE-001 --lease "$reconfirm_lease" --command 'printf "tudo verde · completadas 1 · falharam 0 · duracao 1m\n"; exit 1')"
printf '%s' "$reconfirm_output" | grep -q '"status": "awaiting_gates"' || fail 'reconfirmação não ratificou exit 1 com stdout de sucesso'
grep -q '"exit_reconfirmed"' "$reconfirm_tmp/.git/ralph-control/events.jsonl" || fail 'block.finished sem fato exit_reconfirmed'
printf 'ok   reconfirmação de exit: exit 1 com "tudo verde" ratificado para 0 (awaiting_gates)\n'

# ---------------------------------------------------------------------------
# FEATURE-101 (Phase 1): Contrato de telemetria (schema + eventos)
# - RALPH_SCHEMA_VERSION 1.3.0 e aceitação de 1.0.0-1.3.0; rejeição de 1.4.0
# - Verificação de novos tipos de evento e registro de event.rejected para tipo desconhecido
# - telemetry.activity sanitiza segredos e UTF-8 inválido sem rejeitar o bloco
# - command.heartbeat preserva campos legados e adiciona position, eta_seconds, gate_age
# - monitor e status continuam compatíveis
# ---------------------------------------------------------------------------
telemetry_tmp="$TMP/telemetry-fixture"
mkdir -p "$telemetry_tmp"
git -C "$telemetry_tmp" init -q
git -C "$telemetry_tmp" config user.email ralph-method@example.invalid
git -C "$telemetry_tmp" config user.name 'Ralph Method Telemetry Test'
printf '%s\n' '# Telemetry' > "$telemetry_tmp/README.md"
printf '%s\n' '# Plano' > "$telemetry_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_telemetry","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Telemetry","position":1}]}' > "$telemetry_tmp/workflow.json"
git -C "$telemetry_tmp" add .
git -C "$telemetry_tmp" commit -qm base
(cd "$telemetry_tmp" && control init --workflow wf_telemetry --manifest workflow.json >/dev/null)
telemetry_claim="$(cd "$telemetry_tmp" && control claim --workflow wf_telemetry --feature FEATURE-001 --actor telemetry)"
telemetry_lease="$(json_field "$telemetry_claim" lease_token)"

# O bloco emite no stdout um canário de segredo e UTF-8 inválido; o
# telemetry.activity capturado no ledger não pode conter o segredo em claro.
telemetry_canary='sk-canary-SECRETVALUE1234567890'
(cd "$telemetry_tmp" && control run --workflow wf_telemetry --feature FEATURE-001 --lease "$telemetry_lease" \
  --heartbeat-interval 1 \
  --command "printf 'progredindo com $telemetry_canary e caracteres inválidos \\x00\\xff\\xfe\\n'; sleep 3; exit 0" \
  >/dev/null 2>&1)

if grep -q "$telemetry_canary" "$telemetry_tmp/.git/ralph-control/events.jsonl"; then
  fail 'telemetry.activity vazou o canário de segredo no ledger'
fi

grep -q '"type":"telemetry.activity"' "$telemetry_tmp/.git/ralph-control/events.jsonl" \
  || fail 'telemetry.activity não foi emitido durante o bloco'
grep -q '"type":"command.heartbeat"' "$telemetry_tmp/.git/ralph-control/events.jsonl" \
  || fail 'command.heartbeat não foi emitido'

# Validação detalhada dos campos de telemetry.activity e command.heartbeat
EVENTS_FILE="$telemetry_tmp/.git/ralph-control/events.jsonl" php -r '
  $events = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $activityFound = false;
  $heartbeatFound = false;
  foreach ($events as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      $type = $event["type"] ?? "";
      if ($type === "telemetry.activity") {
          $activityFound = true;
          $facts = $event["facts"] ?? [];
          if (! array_key_exists("activity_preview", $facts) || ! array_key_exists("elapsed", $facts)
              || ! array_key_exists("idle_seconds", $facts) || ! array_key_exists("phase", $facts)) {
              fwrite(STDERR, "telemetry.activity campos ausentes: ".json_encode($facts)."\n");
              exit(1);
          }
      } elseif ($type === "command.heartbeat") {
          $heartbeatFound = true;
          $facts = $event["facts"] ?? [];
          // Campos legados
          foreach (["pid", "process_tree", "heartbeat_sequence", "stdout_bytes", "stderr_bytes", "idle_seconds", "child_running"] as $legacyKey) {
              if (! array_key_exists($legacyKey, $facts)) {
                  fwrite(STDERR, "command.heartbeat campo legado ausente: {$legacyKey}\n");
                  exit(1);
              }
          }
          // Campos novos
          foreach (["position", "eta_seconds", "gate_age"] as $newKey) {
              if (! array_key_exists($newKey, $facts)) {
                  fwrite(STDERR, "command.heartbeat campo novo ausente: {$newKey}\n");
                  exit(1);
              }
          }
      }
  }
  if (! $activityFound || ! $heartbeatFound) {
      fwrite(STDERR, "eventos de telemetria não encontrados no ledger\n");
      exit(1);
  }
'

# Monitor e status continuam lendo os eventos normalmente
(cd "$telemetry_tmp" && control status >/dev/null)
(cd "$telemetry_tmp" && php "$ROOT/bin/ralph-monitor" --workflow wf_telemetry --once --json >/dev/null)
(cd "$telemetry_tmp" && control verify >/dev/null)
printf 'ok   telemetry.activity sanitiza canário de segredo e heartbeat preserva campos (FEATURE-101 Phase 1)\n'

# ---------------------------------------------------------------------------
# Teste de schema 1.3.0, fail-closed de 1.4.0 e tipos novos no verify
# ---------------------------------------------------------------------------
schema_tmp="$TMP/schema-fixture"
mkdir -p "$schema_tmp"
git -C "$schema_tmp" init -q
git -C "$schema_tmp" config user.email ralph-method@example.invalid
git -C "$schema_tmp" config user.name 'Ralph Method Schema Test'
printf '%s\n' '# Schema Test' > "$schema_tmp/README.md"
printf '%s\n' '# Plano' > "$schema_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_schema","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Schema Test","position":1}]}' > "$schema_tmp/workflow.json"
git -C "$schema_tmp" add .
git -C "$schema_tmp" commit -qm base
(cd "$schema_tmp" && control init --workflow wf_schema --manifest workflow.json >/dev/null)
(cd "$schema_tmp" && control verify >/dev/null)

# Teste fail-closed: evento com schema_version 1.4.0 deve ser rejeitado por verify
schema_invalid_tmp="$TMP/schema-invalid-fixture"
cp -a "$schema_tmp" "$schema_invalid_tmp"
EVENTS_FILE="$schema_invalid_tmp/.git/ralph-control/events.jsonl" php -r '
  $lines = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $first = json_decode($lines[0], true, 512, JSON_THROW_ON_ERROR);
  $first["schema_version"] = "1.4.0";
  unset($first["event_hash"]);
  // Canonical hash
  $canon = $first;
  ksort($canon);
  // Just rewrite with invalid schema version
  $first["event_hash"] = "sha256:".hash("sha256", json_encode($canon, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n");
  file_put_contents(getenv("EVENTS_FILE"), json_encode($first, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n");
'
set +e
(cd "$schema_invalid_tmp" && control verify >/dev/null 2>&1)
schema_14_exit=$?
set -e
[ "$schema_14_exit" -ne 0 ] || fail 'schema_version 1.4.0 não foi rejeitado (fail-closed)'

# Teste de tipo desconhecido: tentativa de evento inválido gera event.rejected no ledger
reject_tmp="$TMP/reject-fixture"
mkdir -p "$reject_tmp"
git -C "$reject_tmp" init -q
git -C "$reject_tmp" config user.email ralph-method@example.invalid
git -C "$reject_tmp" config user.name 'Ralph Method Reject Test'
printf '%s\n' '# Reject Test' > "$reject_tmp/README.md"
printf '%s\n' '# Plano' > "$reject_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_reject","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Reject Test","position":1}]}' > "$reject_tmp/workflow.json"
git -C "$reject_tmp" add .
git -C "$reject_tmp" commit -qm base
(cd "$reject_tmp" && control init --workflow wf_reject --manifest workflow.json >/dev/null)
(cd "$reject_tmp" && control claim --workflow wf_reject --feature FEATURE-001 --actor reject-test >/dev/null)

# Testar via subshell que appendEvent de tipo desconhecido falha e grava event.rejected
set +e
(cd "$reject_tmp" && ROOT_DIR="$ROOT" php -r '
  $root = realpath(getenv("ROOT_DIR"));
  $code = file_get_contents($root."/bin/ralph-control");
  $code = preg_replace("/^#\!.*?\n/", "", $code);
  $code = preg_replace("/^<\?php\s*/", "", $code);
  $code = preg_replace("/\\\$arguments\s*=\s*args\\(\\\$argv\\);.*$/s", "", $code);
  eval($code);
  $workflow = loadWorkflowForId("wf_reject");
  $projection = project($workflow, readEvents());
  $feature = featureFrom($projection, "FEATURE-001");
  appendEvent(eventContext(["workflow" => "wf_reject"], $feature, "tipo.completamente.invalido", "Teste de rejeição"));
') >/dev/null 2>&1
reject_sub_exit=$?
set -e
[ "$reject_sub_exit" -ne 0 ] || fail 'tipo desconhecido não retornou erro'
grep -q '"type":"event.rejected"' "$reject_tmp/.git/ralph-control/events.jsonl" \
  || fail 'event.rejected não foi gravado no ledger para tipo desconhecido'
(cd "$reject_tmp" && control verify >/dev/null) || fail 'ledger com event.rejected não passou no verify'
printf 'ok   schema 1.3.0 promovido, 1.4.0 rejeitado fail-closed, event.rejected e novos tipos no verify (FEATURE-101 Phase 1)\n'

# ---------------------------------------------------------------------------
# FEATURE-101 (Phase 2): Watchdog de gates (gate.started, gate.stalled, gate_ages)
# - gate.started (gate, attempt, started_at) emitido ao entrar em awaiting_gates
# - Replay de awaiting_gates não duplica gate.started (idempotência)
# - Relógio injetável (RALPH_TEST_CLOCK_EPOCH) determinístico
# - Acima de RALPH_GATE_STALL_AFTER (600s) -> gate.stalled com gate, age_seconds, threshold
# - Acima de RALPH_GATE_MAX_AGE (3600s) -> recovery_required explícito sem espera real
# - ralph-monitor --once --json expõe gate_ages de forma read-only
# ---------------------------------------------------------------------------
watchdog_tmp="$TMP/watchdog-fixture"
mkdir -p "$watchdog_tmp/bin" "$watchdog_tmp/scripts"
git -C "$watchdog_tmp" init -q
git -C "$watchdog_tmp" config user.email ralph-method@example.invalid
git -C "$watchdog_tmp" config user.name 'Ralph Method Watchdog Test'
printf '%s\n' '# Watchdog Test' > "$watchdog_tmp/README.md"
printf '%s\n' '# Plano' > "$watchdog_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_watchdog","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Watchdog Test","position":1}]}' > "$watchdog_tmp/workflow.json"
printf '%s\n' '#!/usr/bin/env bash' 'echo "check ok"' > "$watchdog_tmp/bin/check"
chmod +x "$watchdog_tmp/bin/check"
cp "$ROOT/scripts/ralph-run-quality.sh" "$watchdog_tmp/scripts/"
cp "$ROOT/scripts/ralph-run-runtime-evidence.sh" "$watchdog_tmp/scripts/"
cp "$ROOT/scripts/ralph-run-independent-gate.sh" "$watchdog_tmp/scripts/"
cp "$ROOT/scripts/ralph-run-curator.sh" "$watchdog_tmp/scripts/"
chmod +x "$watchdog_tmp/scripts"/ralph-run-*.sh

git -C "$watchdog_tmp" add .
git -C "$watchdog_tmp" commit -qm base

(cd "$watchdog_tmp" && control init --workflow wf_watchdog --manifest workflow.json >/dev/null)
watchdog_claim="$(cd "$watchdog_tmp" && control claim --workflow wf_watchdog --feature FEATURE-001 --actor watchdog-test)"
watchdog_lease="$(json_field "$watchdog_claim" lease_token)"

# Bloco termina com exit 0 -> feature entra em awaiting_gates
printf '%s\n' 'src code' > "$watchdog_tmp/src.txt"
git -C "$watchdog_tmp" add src.txt
git -C "$watchdog_tmp" commit -qm "feat: implementa"
(cd "$watchdog_tmp" && control run --workflow wf_watchdog --feature FEATURE-001 --lease "$watchdog_lease" --command 'true' >/dev/null 2>&1)

# Pipeline de gates via supervisor com gates configurados
watchdog_log="$TMP/watchdog-supervise.log"
(cd "$watchdog_tmp" && env -u RALPH_QUALITY_COMMAND -u RALPH_RUNTIME_EVIDENCE_CMD -u RALPH_TECHNICAL_REVIEW_COMMAND -u RALPH_CURATION_COMMAND -u RALPH_TEST_CMD \
  RALPH_QUALITY_COMMAND='echo quality-ok' \
  RALPH_RUNTIME_EVIDENCE_CMD='echo runtime-ok' \
  RALPH_TECHNICAL_REVIEW_COMMAND='echo review-ok' \
  RALPH_CURATION_COMMAND='echo curation-ok' \
  php "$ROOT/bin/ralph-control" supervise --workflow wf_watchdog --engine codex --interval 1 --max-retries 0 > "$watchdog_log" 2>&1)

# Verificar que gate.started foi emitido para os gates com campos esperados
grep -q '"type":"gate.started"' "$watchdog_tmp/.git/ralph-control/events.jsonl" \
  || fail 'gate.started não foi emitido durante o pipeline de gates'

EVENTS_FILE="$watchdog_tmp/.git/ralph-control/events.jsonl" php -r '
  $events = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $startedGates = [];
  foreach ($events as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"] ?? "") === "gate.started") {
          $facts = $event["facts"] ?? [];
          if (! isset($facts["gate"], $facts["attempt"], $facts["started_at"])) {
              fwrite(STDERR, "gate.started com fatos incompletos: ".json_encode($facts)."\n");
              exit(1);
          }
          $startedGates[] = $facts["gate"];
      }
  }
  if (! in_array("validation", $startedGates, true)) {
      fwrite(STDERR, "gate.started para validation não encontrado\n");
      exit(1);
  }
'

# Teste de idempotência / replay de awaiting_gates:
# Iniciar outra fixture travada em awaiting_gates para testar replay
replay_tmp="$TMP/replay-fixture"
mkdir -p "$replay_tmp/bin" "$replay_tmp/scripts"
git -C "$replay_tmp" init -q
git -C "$replay_tmp" config user.email ralph-method@example.invalid
git -C "$replay_tmp" config user.name 'Ralph Method Replay Test'
printf '%s\n' '# Replay' > "$replay_tmp/README.md"
printf '%s\n' '# Plano' > "$replay_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_replay","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Replay","position":1}]}' > "$replay_tmp/workflow.json"
git -C "$replay_tmp" add .
git -C "$replay_tmp" commit -qm base
(cd "$replay_tmp" && control init --workflow wf_replay --manifest workflow.json >/dev/null)
replay_claim="$(cd "$replay_tmp" && control claim --workflow wf_replay --feature FEATURE-001 --actor replay-test)"
replay_lease="$(json_field "$replay_claim" lease_token)"
printf '%s\n' 'code' > "$replay_tmp/code.txt"
git -C "$replay_tmp" add code.txt
git -C "$replay_tmp" commit -qm "feat: replay"
(cd "$replay_tmp" && control run --workflow wf_replay --feature FEATURE-001 --lease "$replay_lease" --command 'true' >/dev/null 2>&1)

# Chama supervisor com comando que falha em runtime_evidence sem avançar
set +e
(cd "$replay_tmp" && env -u RALPH_QUALITY_COMMAND -u RALPH_RUNTIME_EVIDENCE_CMD -u RALPH_TECHNICAL_REVIEW_COMMAND -u RALPH_CURATION_COMMAND -u RALPH_TEST_CMD \
  RALPH_QUALITY_COMMAND='echo quality-ok' \
  RALPH_RUNTIME_EVIDENCE_CMD='exit 1' \
  php "$ROOT/bin/ralph-control" supervise --workflow wf_replay --engine codex --interval 1 --max-retries 0 >/dev/null 2>&1)
set -e
replay_started_1="$(grep -c '"type":"gate.started"' "$replay_tmp/.git/ralph-control/events.jsonl")"

# Re-executa supervise no mesmo estado de awaiting_gates
set +e
(cd "$replay_tmp" && env -u RALPH_QUALITY_COMMAND -u RALPH_RUNTIME_EVIDENCE_CMD -u RALPH_TECHNICAL_REVIEW_COMMAND -u RALPH_CURATION_COMMAND -u RALPH_TEST_CMD \
  RALPH_QUALITY_COMMAND='echo quality-ok' \
  RALPH_RUNTIME_EVIDENCE_CMD='exit 1' \
  php "$ROOT/bin/ralph-control" supervise --workflow wf_replay --engine codex --interval 1 --max-retries 0 >/dev/null 2>&1)
set -e
replay_started_2="$(grep -c '"type":"gate.started"' "$replay_tmp/.git/ralph-control/events.jsonl")"

[ "$replay_started_1" -eq "$replay_started_2" ] || fail "replay de awaiting_gates duplicou gate.started ($replay_started_1 vs $replay_started_2)"
printf 'ok   gate.started registrado e idempotente por replay (FEATURE-101 Phase 2)\n'

# ---------------------------------------------------------------------------
# Teste de Watchdog com relógio determinístico: gate.stalled e recovery_required
# ---------------------------------------------------------------------------
stall_tmp="$TMP/stall-fixture"
mkdir -p "$stall_tmp"
git -C "$stall_tmp" init -q
git -C "$stall_tmp" config user.email ralph-method@example.invalid
git -C "$stall_tmp" config user.name 'Ralph Method Stall Test'
printf '%s\n' '# Stall' > "$stall_tmp/README.md"
printf '%s\n' '# Plano' > "$stall_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_stall","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Stall","position":1}]}' > "$stall_tmp/workflow.json"
git -C "$stall_tmp" add .
git -C "$stall_tmp" commit -qm base
(cd "$stall_tmp" && control init --workflow wf_stall --manifest workflow.json >/dev/null)
stall_claim="$(cd "$stall_tmp" && control claim --workflow wf_stall --feature FEATURE-001 --actor stall-test)"
stall_lease="$(json_field "$stall_claim" lease_token)"
printf '%s\n' 'code' > "$stall_tmp/code.txt"
git -C "$stall_tmp" add code.txt
git -C "$stall_tmp" commit -qm "feat: stall"
(cd "$stall_tmp" && control run --workflow wf_stall --feature FEATURE-001 --lease "$stall_lease" --command 'true' >/dev/null 2>&1)

# Injetar evento gate.started no passado (T0 = 1000000)
T0=1000000
(cd "$stall_tmp" && ROOT_DIR="$ROOT" CLOCK_T0="$T0" LEASE="$stall_lease" php -r '
  $root = realpath(getenv("ROOT_DIR"));
  $code = file_get_contents($root."/bin/ralph-control");
  $code = preg_replace("/^#\!.*?\n/", "", $code);
  $code = preg_replace("/^<\?php\s*/", "", $code);
  $code = preg_replace("/\\\$arguments\s*=\s*args\\(\\\$argv\\);.*$/s", "", $code);
  putenv("RALPH_TEST_CLOCK_EPOCH=".getenv("CLOCK_T0"));
  eval($code);
  $workflow = loadWorkflowForId("wf_stall");
  $projection = project($workflow, readEvents());
  $feature = featureFrom($projection, "FEATURE-001");
  appendEvent(eventContext([
      "workflow" => "wf_stall",
      "lease" => getenv("LEASE"),
      "actor" => "supervisor",
      "actor-type" => "controller",
      "idempotency-key" => "idem_gate_started_wf_stall_FEATURE-001_1_quality",
  ], $feature, "gate.started", "Início do gate quality", [
      "gate" => "quality",
      "attempt" => 1,
      "started_at" => gmdate("Y-m-d\TH:i:s\Z", (int) getenv("CLOCK_T0")),
  ]));
')

# Teste gate_ages no ralph-monitor --once --json (com T = T0 + 120)
monitor_json="$(cd "$stall_tmp" && env RALPH_TEST_CLOCK_EPOCH=$((T0 + 120)) php "$ROOT/bin/ralph-monitor" --workflow wf_stall --once --json)"
MONITOR_PAYLOAD="$monitor_json" php -r '
  $snapshot = json_decode(getenv("MONITOR_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
  if (! isset($snapshot["gate_ages"]) || ! is_array($snapshot["gate_ages"])) {
      fwrite(STDERR, "gate_ages ausente no snapshot do monitor\n");
      exit(1);
  }
  $ages = $snapshot["gate_ages"];
  foreach (["validation", "quality", "runtime_evidence", "technical_review", "curation"] as $gate) {
      if (! array_key_exists($gate, $ages)) {
          fwrite(STDERR, "gate {$gate} ausente em gate_ages\n");
          exit(1);
      }
  }
  if ($ages["quality"] !== 120) {
      fwrite(STDERR, "idade de quality esperada 120, obtida: ".var_export($ages["quality"], true)."\n");
      exit(1);
  }
  if ($ages["runtime_evidence"] !== null) {
      fwrite(STDERR, "runtime_evidence deveria ser null antes de iniciar\n");
      exit(1);
  }
'
printf 'ok   gate_ages exposto no ralph-monitor --once --json (FEATURE-101 Phase 2)\n'

# Teste gate.stalled: relógio em T0 + 650 (acima de RALPH_GATE_STALL_AFTER=600)
stall_log="$TMP/stall-run.log"
set +e
(cd "$stall_tmp" && env -u RALPH_QUALITY_COMMAND -u RALPH_RUNTIME_EVIDENCE_CMD -u RALPH_TECHNICAL_REVIEW_COMMAND -u RALPH_CURATION_COMMAND -u RALPH_TEST_CMD \
  RALPH_TEST_CLOCK_EPOCH=$((T0 + 650)) \
  RALPH_GATE_STALL_AFTER=600 \
  RALPH_GATE_MAX_AGE=3600 \
  RALPH_QUALITY_COMMAND='echo quality-ok' \
  RALPH_RUNTIME_EVIDENCE_CMD='echo runtime-ok' \
  RALPH_TECHNICAL_REVIEW_COMMAND='echo review-ok' \
  RALPH_CURATION_COMMAND='echo curation-ok' \
  php "$ROOT/bin/ralph-control" supervise --workflow wf_stall --engine codex --interval 1 --max-retries 0 > "$stall_log" 2>&1)
set -e

grep -q '"type":"gate.stalled"' "$stall_tmp/.git/ralph-control/events.jsonl" \
  || fail 'gate.stalled não foi emitido no limiar RALPH_GATE_STALL_AFTER'

EVENTS_FILE="$stall_tmp/.git/ralph-control/events.jsonl" php -r '
  $events = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $stalledFound = false;
  foreach ($events as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"] ?? "") === "gate.stalled") {
          $stalledFound = true;
          $facts = $event["facts"] ?? [];
          if (($facts["gate"] ?? "") !== "quality" || ($facts["age_seconds"] ?? 0) < 600 || ($facts["threshold"] ?? 0) !== 600) {
              fwrite(STDERR, "gate.stalled fatos incorretos: ".json_encode($facts)."\n");
              exit(1);
          }
      }
  }
  if (! $stalledFound) {
      exit(1);
  }
'
printf 'ok   gate.stalled emitido no limiar e exibido no feedback (FEATURE-101 Phase 2)\n'

# Teste recovery_required: relógio em T0 + 3700 (acima de RALPH_GATE_MAX_AGE=3600)
horizon_tmp="$TMP/horizon-fixture"
mkdir -p "$horizon_tmp"
git -C "$horizon_tmp" init -q
git -C "$horizon_tmp" config user.email ralph-method@example.invalid
git -C "$horizon_tmp" config user.name 'Ralph Method Horizon Test'
printf '%s\n' '# Horizon' > "$horizon_tmp/README.md"
printf '%s\n' '# Plano' > "$horizon_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_horizon","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Horizon","position":1}]}' > "$horizon_tmp/workflow.json"
git -C "$horizon_tmp" add .
git -C "$horizon_tmp" commit -qm base
(cd "$horizon_tmp" && control init --workflow wf_horizon --manifest workflow.json >/dev/null)
horizon_claim="$(cd "$horizon_tmp" && control claim --workflow wf_horizon --feature FEATURE-001 --actor horizon-test)"
horizon_lease="$(json_field "$horizon_claim" lease_token)"
printf '%s\n' 'code' > "$horizon_tmp/code.txt"
git -C "$horizon_tmp" add code.txt
git -C "$horizon_tmp" commit -qm "feat: horizon"
(cd "$horizon_tmp" && control run --workflow wf_horizon --feature FEATURE-001 --lease "$horizon_lease" --command 'true' >/dev/null 2>&1)

# Injetar gate.started em T0
(cd "$horizon_tmp" && ROOT_DIR="$ROOT" CLOCK_T0="$T0" LEASE="$horizon_lease" php -r '
  $root = realpath(getenv("ROOT_DIR"));
  $code = file_get_contents($root."/bin/ralph-control");
  $code = preg_replace("/^#\!.*?\n/", "", $code);
  $code = preg_replace("/^<\?php\s*/", "", $code);
  $code = preg_replace("/\\\$arguments\s*=\s*args\\(\\\$argv\\);.*$/s", "", $code);
  putenv("RALPH_TEST_CLOCK_EPOCH=".getenv("CLOCK_T0"));
  eval($code);
  $workflow = loadWorkflowForId("wf_horizon");
  $projection = project($workflow, readEvents());
  $feature = featureFrom($projection, "FEATURE-001");
  appendEvent(eventContext([
      "workflow" => "wf_horizon",
      "lease" => getenv("LEASE"),
      "actor" => "supervisor",
      "actor-type" => "controller",
      "idempotency-key" => "idem_gate_started_wf_horizon_FEATURE-001_1_quality",
  ], $feature, "gate.started", "Início do gate quality", [
      "gate" => "quality",
      "attempt" => 1,
      "started_at" => gmdate("Y-m-d\TH:i:s\Z", (int) getenv("CLOCK_T0")),
  ]));
')

set +e
horizon_out="$(cd "$horizon_tmp" && env -u RALPH_QUALITY_COMMAND -u RALPH_RUNTIME_EVIDENCE_CMD -u RALPH_TECHNICAL_REVIEW_COMMAND -u RALPH_CURATION_COMMAND -u RALPH_TEST_CMD \
  RALPH_TEST_CLOCK_EPOCH=$((T0 + 3700)) \
  RALPH_GATE_STALL_AFTER=600 \
  RALPH_GATE_MAX_AGE=3600 \
  php "$ROOT/bin/ralph-control" supervise --workflow wf_horizon --engine codex --interval 1 --max-retries 0 2>/dev/null)"
set -e

printf '%s' "$horizon_out" | grep -q '"status": *"recovery_required"' \
  || fail "supervisor não retornou recovery_required no horizonte max_age: $horizon_out"
grep -q '"type":"recovery.required"' "$horizon_tmp/.git/ralph-control/events.jsonl" \
  || fail 'recovery.required não foi gravado no ledger quando gate excedeu max_age'
printf 'ok   recovery_required emitido no horizonte máximo sem espera real (FEATURE-101 Phase 2)\n'

# ---------------------------------------------------------------------------
# FEATURE-101 (Phase 4): Systematic debugging ao vivo
# - Emissão de debug.progress durante runSystematicDebug (início e hipóteses avaliadas)
# - Conteúdo 100% sanitizado (canários de segredo redigidos, sem vazamento de trecho sensível)
# - cause_kind do contrato atual (feature_bug / harness_defect)
# - Hipóteses confirmadas/rejeitadas e referências Context7/official no stream
# - Relatório final DBG-* segue o contrato oficial
# - ralph-monitor --once --json expõe debug com debug.progress mais recente (read-only)
# - ralph-watch exibe o debug ao vivo na TUI e no snapshot JSON
# ---------------------------------------------------------------------------
live_dbg_tmp="$TMP/live-debug-fixture"
mkdir -p "$live_dbg_tmp"
git -C "$live_dbg_tmp" init -q
git -C "$live_dbg_tmp" config user.email ralph-method@example.invalid
git -C "$live_dbg_tmp" config user.name 'Ralph Method Live Debug Test'
printf '%s\n' '# Live Debug' > "$live_dbg_tmp/README.md"
printf '%s\n' '# Plano' > "$live_dbg_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_live_debug","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-DBG","title":"Live Debug Test","position":1}]}' > "$live_dbg_tmp/workflow.json"
git -C "$live_dbg_tmp" add .
git -C "$live_dbg_tmp" commit -qm base

(cd "$live_dbg_tmp" && control init --workflow wf_live_debug --manifest workflow.json >/dev/null)
dbg_claim="$(cd "$live_dbg_tmp" && control claim --workflow wf_live_debug --feature FEATURE-DBG --actor live-dbg-test)"
dbg_lease="$(json_field "$dbg_claim" lease_token)"

# Faz o bloco falhar para transicionar a feature para debugging_required
set +e
(cd "$live_dbg_tmp" && control run --workflow wf_live_debug --feature FEATURE-DBG --lease "$dbg_lease" --command 'exit 1' >/dev/null 2>&1)
set -e

# Cria comando fake de systematic debug válido com referências Context7/official
fake_debug_script="$TMP/fake-debug-command.sh"
cat > "$fake_debug_script" <<'SH'
#!/usr/bin/env bash
cat <<JSON
{
  "schema_version": "1.3.0",
  "workflow_id": "$RALPH_DEBUG_WORKFLOW_ID",
  "feature_key": "$RALPH_DEBUG_FEATURE_KEY",
  "attempt": $RALPH_DEBUG_ATTEMPT,
  "incident_id": "INC-2026-0088",
  "severity": "medium",
  "cause_kind": "feature_bug",
  "symptom": "Incompatibilidade no tipo de retorno do handler",
  "root_cause": "Erro de conversao de tipos estritos no processamento",
  "correction_plan": "Ajustar tipagem do handler",
  "hypotheses": [
    {
      "id": "H1",
      "statement": "Incompatibilidade de tipos no schema",
      "status": "confirmed"
    },
    {
      "id": "H2",
      "statement": "Falha de rede externa",
      "status": "rejected"
    }
  ],
  "official_references": [
    {
      "provider": "Context7",
      "source": "https://docs.context7.invalid/types",
      "section": "Type Safety"
    },
    {
      "provider": "official",
      "source": "https://official.example.invalid/specs",
      "section": "Overview"
    }
  ],
  "validation": {
    "status": "passed",
    "exit_code": 0,
    "evidence_refs": ["README.md"]
  },
  "knowledge_candidate": {
    "title": "Validação de tipos em handlers",
    "summary": "Sempre tipar explicitamente para evitar coerção implícita",
    "applicability": ["core", "handlers"],
    "limitations": ["apenas PHP 8.2+"]
  },
  "status": "verified"
}
JSON
SH
chmod +x "$fake_debug_script"

# Executa o systematic debug via controlador
debug_run_output="$(cd "$live_dbg_tmp" && control debug --workflow wf_live_debug --feature FEATURE-DBG --command "bash $fake_debug_script")"

printf '%s\n' "$debug_run_output" | grep -q '"status": *"debugging_verified"' \
  || fail "systematic debug não retornou debugging_verified: $debug_run_output"

# 1. Verifica emissão de debug.progress no ledger
events_content="$(cat "$live_dbg_tmp/.git/ralph-control/events.jsonl")"

printf '%s\n' "$events_content" | grep -q '"type":"debug.progress"' \
  || fail 'evento debug.progress não foi emitido no ledger durante runSystematicDebug'

# Teste de sanitização estrita: em fixture separada, comando que tenta vazar segredos é rejeitado e redigido
leak_dbg_tmp="$TMP/leak-debug-fixture"
mkdir -p "$leak_dbg_tmp"
git -C "$leak_dbg_tmp" init -q
git -C "$leak_dbg_tmp" config user.email ralph-method@example.invalid
git -C "$leak_dbg_tmp" config user.name 'Ralph Method Leak Test'
printf '%s\n' '# Leak Test' > "$leak_dbg_tmp/README.md"
printf '%s\n' '# Plano' > "$leak_dbg_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_leak","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-LEAK","title":"Leak Test","position":1}]}' > "$leak_dbg_tmp/workflow.json"
git -C "$leak_dbg_tmp" add .
git -C "$leak_dbg_tmp" commit -qm base
(cd "$leak_dbg_tmp" && control init --workflow wf_leak --manifest workflow.json >/dev/null)
leak_claim="$(cd "$leak_dbg_tmp" && control claim --workflow wf_leak --feature FEATURE-LEAK --actor leak-test)"
leak_lease="$(json_field "$leak_claim" lease_token)"
set +e
(cd "$leak_dbg_tmp" && control run --workflow wf_leak --feature FEATURE-LEAK --lease "$leak_lease" --command 'exit 1' >/dev/null 2>&1)
set -e

leak_debug_script="$TMP/leak-debug-command.sh"
cat > "$leak_debug_script" <<'SH'
#!/usr/bin/env bash
cat <<JSON
{
  "schema_version": "1.3.0",
  "workflow_id": "$RALPH_DEBUG_WORKFLOW_ID",
  "feature_key": "$RALPH_DEBUG_FEATURE_KEY",
  "attempt": $RALPH_DEBUG_ATTEMPT,
  "incident_id": "INC-2026-0089",
  "severity": "high",
  "cause_kind": "feature_bug",
  "symptom": "Vazamento com api_key=secret-canary-live-debug-12345",
  "root_cause": "sk-proj-1234567890123456 e user@secretdomain.invalid",
  "correction_plan": "Redigir segredo",
  "hypotheses": [{"id": "H1", "statement": "Segredo vazado", "status": "confirmed"}],
  "official_references": [{"provider": "official", "source": "https://official.example.invalid", "section": "Sec"}],
  "validation": {"status": "passed", "exit_code": 0, "evidence_refs": ["README.md"]},
  "knowledge_candidate": {"title": "T", "summary": "S", "applicability": [], "limitations": []},
  "status": "verified"
}
JSON
SH
chmod +x "$leak_debug_script"

set +e
(cd "$leak_dbg_tmp" && control debug --workflow wf_leak --feature FEATURE-LEAK --command "bash $leak_debug_script" >/dev/null 2>&1)
set -e
events_after_leak="$(cat "$leak_dbg_tmp/.git/ralph-control/events.jsonl")"
if printf '%s\n' "$events_after_leak" | grep -q 'secret-canary-live-debug-12345\|sk-proj-1234567890123456'; then
    fail 'segredo canário vazou no ledger durante systematic debugging'
fi

EVENTS_FILE="$live_dbg_tmp/.git/ralph-control/events.jsonl" php -r '
    $lines = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    $debugEvents = [];
    foreach ($lines as $line) {
        $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        if (($event["type"] ?? "") === "debug.progress") {
            $debugEvents[] = $event;
        }
    }
    if (count($debugEvents) < 2) {
        fwrite(STDERR, "esperava ao menos 2 eventos debug.progress (início e hipóteses), obtido: ".count($debugEvents)."\n");
        exit(1);
    }
    $first = $debugEvents[0]["facts"] ?? [];
    if (($first["phase"] ?? "") !== "started" || ($first["status"] ?? "") !== "investigating") {
        fwrite(STDERR, "primeiro debug.progress deve ser phase=started e status=investigating: ".json_encode($first)."\n");
        exit(2);
    }
    $second = $debugEvents[1]["facts"] ?? [];
    if (($second["phase"] ?? "") !== "hypotheses_evaluated"
        || ($second["cause_kind"] ?? "") !== "feature_bug"
        || ($second["confirmed_hypotheses"] ?? 0) !== 1
        || ($second["rejected_hypotheses"] ?? 0) !== 1) {
        fwrite(STDERR, "segundo debug.progress deve conter hipóteses e cause_kind=feature_bug: ".json_encode($second)."\n");
        exit(3);
    }
    $refs = $second["official_references"] ?? [];
    if (count($refs) !== 2 || ($refs[0]["provider"] ?? "") !== "Context7") {
        fwrite(STDERR, "referências oficiais devem conter Context7: ".json_encode($refs)."\n");
        exit(4);
    }
' || fail 'estrutura e fatos dos eventos debug.progress inválidos'

# 2. Relatório DBG-* segue o contrato oficial
report_files=( "$live_dbg_tmp/.git/ralph-control/reports"/DBG-*.json )
[ -f "${report_files[0]}" ] || fail 'relatório DBG-*.json não foi criado em reports/'
grep -q '"status": *"verified"' "${report_files[0]}" || fail 'relatório DBG-* com status diferente de verified'
grep -q 'Context7' "${report_files[0]}" || fail 'relatório DBG-* não contém Context7'

# 3. ralph-monitor --once --json expõe debug.progress mais recente (read-only)
events_hash_before="$(sha256sum "$live_dbg_tmp/.git/ralph-control/events.jsonl")"
monitor_dbg_json="$(cd "$live_dbg_tmp" && php "$ROOT/bin/ralph-monitor" --workflow wf_live_debug --once --json)"
events_hash_after="$(sha256sum "$live_dbg_tmp/.git/ralph-control/events.jsonl")"
[ "$events_hash_before" = "$events_hash_after" ] || fail 'ralph-monitor mutou o ledger'

MONITOR_DBG_PAYLOAD="$monitor_dbg_json" php -r '
    $snap = json_decode(getenv("MONITOR_DBG_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    $dbg = $snap["debug"] ?? null;
    if (! is_array($dbg)) {
        fwrite(STDERR, "debug ausente no snapshot do monitor\n");
        exit(1);
    }
    if (($dbg["type"] ?? "") !== "debug.progress"
        || ($dbg["cause_kind"] ?? "") !== "feature_bug"
        || ($dbg["confirmed_hypotheses"] ?? 0) !== 1
        || ($dbg["rejected_hypotheses"] ?? 0) !== 1) {
        fwrite(STDERR, "campos do debug no snapshot do monitor inválidos: ".json_encode($dbg)."\n");
        exit(2);
    }
' || fail 'debug no snapshot do monitor inválido'

# 4. ralph-watch expõe debug no snapshot e exibe na TUI
watch_dbg_json="$(cd "$live_dbg_tmp" && php "$ROOT/bin/ralph-watch" --workflow wf_live_debug --once --json)"
WATCH_DBG_PAYLOAD="$watch_dbg_json" php -r '
    $snap = json_decode(getenv("WATCH_DBG_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    $dbg = $snap["debug"] ?? null;
    if (! is_array($dbg)) {
        fwrite(STDERR, "debug ausente no snapshot do ralph-watch\n");
        exit(1);
    }
    if (($dbg["cause_kind"] ?? "") !== "feature_bug"
        || ($dbg["confirmed_hypotheses"] ?? 0) !== 1) {
        fwrite(STDERR, "campos do debug no snapshot do ralph-watch inválidos: ".json_encode($dbg)."\n");
        exit(2);
    }
' || fail 'debug no snapshot do ralph-watch inválido'

watch_dbg_text="$(cd "$live_dbg_tmp" && php "$ROOT/bin/ralph-watch" --workflow wf_live_debug --once)"
printf '%s\n' "$watch_dbg_text" | grep -q "SYSTEMATIC DEBUGGING AO VIVO" || fail 'ralph-watch não renderizou seção SYSTEMATIC DEBUGGING AO VIVO'
printf '%s\n' "$watch_dbg_text" | grep -q "feature_bug" || fail 'ralph-watch não exibiu cause_kind feature_bug'
printf '%s\n' "$watch_dbg_text" | grep -q "Context7" || fail 'ralph-watch não exibiu Context7'
printf '%s\n' "$watch_dbg_text" | grep -q "1 confirmada(s)" || fail 'ralph-watch não exibiu contagem de hipóteses confirmadas'

# 5. Ledger íntegro com hash-chain válida
(cd "$live_dbg_tmp" && control verify >/dev/null) || fail 'verify falhou no ledger com eventos de systematic debug'

printf 'ok   systematic debugging ao vivo emite debug.progress sanitizado, DBG-* oficial, monitor e watch exibem progresso (FEATURE-101 Phase 4)\n'

# ---------------------------------------------------------------------------
# FEATURE-101 (Phase 5): Conhecimento em tempo real
# - Emissão de knowledge.telemetry ao criar candidato (após feature.released)
# - Emissão de knowledge.telemetry nas decisões (curated / rejected / skipped / review_required)
# - Conteúdo sanitizado (título, categoria, tópicos, sem conteúdo bruto)
# - knowledge_policy.mode: non_blocking preservado (liberação independente da curadoria)
# - ralph-monitor --once --json inclui knowledge_summary sem mutar ledger (read-only)
# - ralph-watch exibe fila de conhecimento e contagem por status na TUI e no JSON
# ---------------------------------------------------------------------------
live_k_tmp="$TMP/live-knowledge-fixture"
mkdir -p "$live_k_tmp"
git -C "$live_k_tmp" init -q
git -C "$live_k_tmp" config user.email ralph-method@example.invalid
git -C "$live_k_tmp" config user.name 'Ralph Method Live Knowledge Test'
printf '%s\n' '# Live Knowledge' > "$live_k_tmp/README.md"
printf '%s\n' '# Plano' > "$live_k_tmp/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_live_knowledge","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-K1","title":"Memória em tempo real 1","position":1},{"feature_key":"FEATURE-K2","title":"Memória em tempo real 2","position":2}]}' > "$live_k_tmp/workflow.json"
git -C "$live_k_tmp" add .
git -C "$live_k_tmp" commit -qm base

(cd "$live_k_tmp" && control init --workflow wf_live_knowledge --manifest workflow.json >/dev/null)

# Executa e libera FEATURE-K1
k1_claim="$(cd "$live_k_tmp" && control claim --workflow wf_live_knowledge --feature FEATURE-K1 --actor k-test)"
k1_lease="$(json_field "$k1_claim" lease_token)"
printf '%s\n' 'k1 implementado' > "$live_k_tmp/k1.txt"
git -C "$live_k_tmp" add k1.txt
git -C "$live_k_tmp" commit -qm '[feat] (k1): implementa k1'
(cd "$live_k_tmp" && control finish --workflow wf_live_knowledge --feature FEATURE-K1 --lease "$k1_lease" --exit-code 0 >/dev/null)

for g in validation quality runtime_evidence technical_review curation; do
  (cd "$live_k_tmp" && control gate --workflow wf_live_knowledge --feature FEATURE-K1 --lease "$k1_lease" \
    --gate "$g" --status passed --producer test --actor test --exit-code 0 >/dev/null)
done

(cd "$live_k_tmp" && control approve --workflow wf_live_knowledge --feature FEATURE-K1 --lease "$k1_lease" >/dev/null)
(cd "$live_k_tmp" && control handoff --workflow wf_live_knowledge --feature FEATURE-K1 --output .ralph/handoffs/FEATURE-K1 >/dev/null)
(cd "$live_k_tmp" && control handoff-commit --workflow wf_live_knowledge --feature FEATURE-K1 --lease "$k1_lease" >/dev/null)
(cd "$live_k_tmp" && control release --workflow wf_live_knowledge --feature FEATURE-K1 --lease "$k1_lease" >/dev/null)

# 1. Verifica emissão de knowledge.telemetry ao criar candidato pós-release
events_k1="$(cat "$live_k_tmp/.git/ralph-control/events.jsonl")"
printf '%s\n' "$events_k1" | grep -q '"type":"knowledge.telemetry"' \
  || fail 'evento knowledge.telemetry não foi emitido após feature.released'

# 2. advance avança para FEATURE-K2 mesmo antes da curadoria (non_blocking)
advance_k1="$(cd "$live_k_tmp" && control advance --workflow wf_live_knowledge --feature FEATURE-K1 --lease "$k1_lease")"
assert_eq 'FEATURE-K2' "$(json_field "$advance_k1" next_feature)" 'workflow avançou para próxima feature sem bloquear em curadoria'

# 3. Curadoria da FEATURE-K1 emite knowledge.curated e knowledge.telemetry
curated_k1="$(cd "$live_k_tmp" && control knowledge curated --workflow wf_live_knowledge --feature FEATURE-K1 \
  --title 'Telemetria Contínua de Memória' \
  --summary 'Stream sanitizado permite observabilidade de candidatos em tempo real.' \
  --category telemetry --root-cause telemetry-stream-visibility \
  --topics streaming,events,knowledge --stack php,bash --domain control-plane \
  --commit "$(git -C "$live_k_tmp" rev-parse HEAD~1)" \
  --test 'scripts/test-ralph-knowledge.sh' 2>&1)"
k1_lesson_id="$(json_field "$curated_k1" lesson_id)"
printf '%s' "$k1_lesson_id" | grep -Eq '^LES-[0-9]{4}-[0-9]{4}$' || fail 'lição curada recebeu ID padronizado'

git -C "$live_k_tmp" add docs/
git -C "$live_k_tmp" commit -qm '[docs] (k1): curadoria de conhecimento k1'

# Executa, libera e rejeita FEATURE-K2
k2_claim="$(cd "$live_k_tmp" && control claim --workflow wf_live_knowledge --feature FEATURE-K2 --actor k-test)"
k2_lease="$(json_field "$k2_claim" lease_token)"
printf '%s\n' 'k2 implementado' > "$live_k_tmp/k2.txt"
git -C "$live_k_tmp" add k2.txt
git -C "$live_k_tmp" commit -qm '[feat] (k2): implementa k2'
(cd "$live_k_tmp" && control finish --workflow wf_live_knowledge --feature FEATURE-K2 --lease "$k2_lease" --exit-code 0 >/dev/null)
for g in validation quality runtime_evidence technical_review curation; do
  (cd "$live_k_tmp" && control gate --workflow wf_live_knowledge --feature FEATURE-K2 --lease "$k2_lease" \
    --gate "$g" --status passed --producer test --actor test --exit-code 0 >/dev/null)
done
(cd "$live_k_tmp" && control approve --workflow wf_live_knowledge --feature FEATURE-K2 --lease "$k2_lease" >/dev/null)
(cd "$live_k_tmp" && control handoff --workflow wf_live_knowledge --feature FEATURE-K2 --output .ralph/handoffs/FEATURE-K2 >/dev/null)
(cd "$live_k_tmp" && control handoff-commit --workflow wf_live_knowledge --feature FEATURE-K2 --lease "$k2_lease" >/dev/null)
(cd "$live_k_tmp" && control release --workflow wf_live_knowledge --feature FEATURE-K2 --lease "$k2_lease" >/dev/null)
(cd "$live_k_tmp" && control knowledge rejected --workflow wf_live_knowledge --feature FEATURE-K2 --reason 'sem aprendizado duradouro' >/dev/null)

# 4. Validação estrita dos eventos knowledge.telemetry no ledger
EVENTS_FILE_K="$live_k_tmp/.git/ralph-control/events.jsonl" LESSON_ID_K="$k1_lesson_id" php -r '
  $lines = file(getenv("EVENTS_FILE_K"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $ktEvents = [];
  foreach ($lines as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"] ?? "") === "knowledge.telemetry") {
          $ktEvents[] = $event;
      }
  }
  if (count($ktEvents) < 4) {
      fwrite(STDERR, "esperava ao menos 4 eventos knowledge.telemetry (2 criados, 1 curado, 1 rejeitado), obtido: ".count($ktEvents)."\n");
      exit(1);
  }
  // Valida que todos contêm política non_blocking e nenhum conteúdo bruto/sensível
  foreach ($ktEvents as $e) {
      $facts = $e["facts"] ?? [];
      if (($facts["policy"] ?? "") !== "non_blocking") {
          fwrite(STDERR, "evento knowledge.telemetry sem policy=non_blocking: ".json_encode($facts)."\n");
          exit(2);
      }
      if (isset($facts["yaml"]) || isset($facts["markdown"]) || isset($facts["prompt"]) || isset($facts["raw"])) {
          fwrite(STDERR, "evento knowledge.telemetry contém campo bruto proibido: ".json_encode($facts)."\n");
          exit(3);
      }
  }
  $actions = array_map(static fn($e): string => (string)($e["facts"]["action"] ?? ""), $ktEvents);
  if (! in_array("candidate_created", $actions, true) || ! in_array("curated", $actions, true) || ! in_array("rejected", $actions, true)) {
      fwrite(STDERR, "ações de telemetria esperadas não encontradas: ".json_encode($actions)."\n");
      exit(4);
  }
' || fail 'validação de estrutura e sanitização de knowledge.telemetry falhou'

# 5. ralph-monitor --once --json expõe knowledge_summary (read-only, sem mutar ledger)
k_events_hash_before="$(sha256sum "$live_k_tmp/.git/ralph-control/events.jsonl")"
monitor_k_json="$(cd "$live_k_tmp" && php "$ROOT/bin/ralph-monitor" --workflow wf_live_knowledge --once --json)"
k_events_hash_after="$(sha256sum "$live_k_tmp/.git/ralph-control/events.jsonl")"
[ "$k_events_hash_before" = "$k_events_hash_after" ] || fail 'ralph-monitor mutou o ledger ao consultar knowledge_summary'

MONITOR_K_PAYLOAD="$monitor_k_json" LESSON_ID_K="$k1_lesson_id" php -r '
  $snap = json_decode(getenv("MONITOR_K_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
  $ks = $snap["knowledge_summary"] ?? null;
  if (! is_array($ks)) {
      fwrite(STDERR, "knowledge_summary ausente no snapshot do monitor\n");
      exit(1);
  }
  if (($ks["total"] ?? 0) !== 2 || ($ks["curated"] ?? 0) !== 1 || ($ks["rejected"] ?? 0) !== 1 || ($ks["pending"] ?? 0) !== 0) {
      fwrite(STDERR, "contagens de knowledge_summary no monitor incorretas: ".json_encode($ks)."\n");
      exit(2);
  }
  $cands = $ks["candidates"] ?? [];
  if (count($cands) !== 2) {
      fwrite(STDERR, "esperava 2 candidatos no knowledge_summary do monitor\n");
      exit(3);
  }
  $statuses = array_column($cands, "status");
  if (! in_array("persisted", $statuses, true) || ! in_array("rejected", $statuses, true)) {
      fwrite(STDERR, "status dos candidatos no monitor incorretos: ".json_encode($cands)."\n");
      exit(4);
  }
' || fail 'knowledge_summary no snapshot do ralph-monitor inválido'

# 6. ralph-watch expõe knowledge_summary no snapshot e exibe na TUI
watch_k_json="$(cd "$live_k_tmp" && php "$ROOT/bin/ralph-watch" --workflow wf_live_knowledge --once --json)"
WATCH_K_PAYLOAD="$watch_k_json" php -r '
  $snap = json_decode(getenv("WATCH_K_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
  $ks = $snap["knowledge_summary"] ?? null;
  if (! is_array($ks) || ($ks["total"] ?? 0) !== 2 || ($ks["curated"] ?? 0) !== 1 || ($ks["rejected"] ?? 0) !== 1) {
      fwrite(STDERR, "knowledge_summary no snapshot do ralph-watch incorreto: ".json_encode($ks)."\n");
      exit(1);
  }
' || fail 'knowledge_summary no snapshot do ralph-watch inválido'

watch_k_text="$(cd "$live_k_tmp" && php "$ROOT/bin/ralph-watch" --workflow wf_live_knowledge --once)"
printf '%s\n' "$watch_k_text" | grep -q "FILA DE CONHECIMENTO & LIÇÕES" || fail 'ralph-watch não exibiu FILA DE CONHECIMENTO & LIÇÕES'
printf '%s\n' "$watch_k_text" | grep -q "CURATED" || fail 'ralph-watch não exibiu badge CURATED'
printf '%s\n' "$watch_k_text" | grep -q "REJECTED" || fail 'ralph-watch não exibiu badge REJECTED'
printf '%s\n' "$watch_k_text" | grep -q "$k1_lesson_id" || fail "ralph-watch não exibiu lesson_id $k1_lesson_id"

# 7. Ledger íntegro com hash-chain válida
(cd "$live_k_tmp" && control verify >/dev/null) || fail 'verify falhou no ledger com eventos de conhecimento'

printf 'ok   conhecimento em tempo real emite knowledge.telemetry sanitizado, non_blocking, monitor e watch exibem resumo (FEATURE-101 Phase 5)\n'

# ---------------------------------------------------------------------------
# FEATURE-102A (Phase 1): Redação de conteúdo sensível
# - sanitize() redige os seis tipos v1 e prossegue sem rejeitar o evento
# - event.redacted registra somente metadados sanitizados
# - a hash chain permanece íntegra após 100 redações
# - o diagnóstico read-only alerta acima do limiar sem expor o valor original
# ---------------------------------------------------------------------------
bash "$ROOT/scripts/test-sanitize-redact.sh"

# ---------------------------------------------------------------------------
# FEATURE-102B (Phase 2): Cursor rebaixado até prova adversarial + hero
# ---------------------------------------------------------------------------
bash "$ROOT/tests/test-cursor-adversarial.sh"
bash "$ROOT/tests/test-cursor-hero.sh"



