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

adversarial_command="set +e; php '$ROOT/bin/ralph-control' observe --workflow wf_test --feature FEATURE-001 --event child_attempt; php '$ROOT/bin/ralph-control' gate --workflow wf_test --feature FEATURE-001 --gate validation --status passed; php '$ROOT/bin/ralph-control' approve --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' release --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' advance --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' retry --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' recover --workflow wf_test --feature FEATURE-001; php '$ROOT/bin/ralph-control' trace --workflow wf_test --feature FEATURE-001 --event completed --execution-id exec_child_attempt --runner codex --role implementation; echo 'RALPH_FEEDBACK {\"event\":\"phase_done\",\"source\":\"adversarial\"}'"
run_feedback_output="$(cd "$TMP" && control run --workflow wf_test --feature FEATURE-001 --lease "$lease" --command "$adversarial_command")"
printf '%s' "$run_feedback_output" | grep -q '^RALPH_FEEDBACK ' || fail 'control não retransmitiu feedback do bloco'

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
printf 'OK: Ralph Method smoke passou.\n'
