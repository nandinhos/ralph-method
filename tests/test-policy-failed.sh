#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-policy.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control() {
  local project="$1"
  shift
  (cd "$project" && php "$ROOT/bin/ralph-control" "$@")
}

json_field() {
  local payload="$1"
  local field="$2"
  JSON_PAYLOAD="$payload" JSON_FIELD="$field" php -r '
    $value = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR)[getenv("JSON_FIELD")] ?? null;
    if (! is_scalar($value)) { exit(1); }
    echo $value;
  '
}

project="$TMP/policy"
mkdir -p "$project"
git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method Policy Test'
printf '%s\n' '# Policy fixture' > "$project/README.md"
printf '%s\n' '# Policy plan' > "$project/plan.md"
cat > "$project/workflow.json" <<'JSON'
{
  "schema_version": "1.3.0",
  "workflow_id": "wf_policy_failed",
  "plan_file": "plan.md",
  "knowledge_policy": {"mode": "non_blocking"},
  "execution_policy": {
    "schema_version": "1.0.0",
    "provider_strategy": "explicit_failover",
    "provider_chain": [
      {"runner": "codex", "profile": "codex-default", "required_failure_domain_status": "observed"},
      {"runner": "opencode", "profile": "opencode-default", "required_failure_domain_status": "observed"}
    ],
    "failover": {
      "eligible_reasons": ["provider_usage_limited"],
      "short_wait_threshold_seconds": 10,
      "unknown_reset_cooldown_seconds": 20,
      "max_switches_per_feature": 2,
      "max_no_progress_seconds": 120,
      "when_chain_exhausted": "recovery_required"
    }
  },
  "features": [{"feature_key": "FEATURE-POLICY", "title": "Policy divergence", "position": 1}]
}
JSON
git -C "$project" add .
git -C "$project" commit -qm base
control "$project" init --workflow wf_policy_failed --manifest workflow.json >/dev/null

claim="$(control "$project" claim --workflow wf_policy_failed --feature FEATURE-POLICY --actor policy-test)"
lease="$(json_field "$claim" lease_token)"
control "$project" finish --workflow wf_policy_failed --feature FEATURE-POLICY --lease "$lease" --exit-code 0 >/dev/null
for gate in validation quality runtime_evidence technical_review curation; do
  control "$project" gate --workflow wf_policy_failed --feature FEATURE-POLICY --lease "$lease" \
    --gate "$gate" --status passed --producer "policy-test-$gate" --exit-code 0 >/dev/null
done

# Diverge somente o conteúdo da policy; o hash congelado continua sendo a
# autoridade da tentativa.
PROJECT="$project" php -r '
  $path = getenv("PROJECT")."/.git/ralph-control/workflow.json";
  $workflow = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
  $workflow["execution_policy"]["failover"]["max_switches_per_feature"] = 3;
  file_put_contents($path, json_encode($workflow, JSON_UNESCAPED_SLASHES|JSON_UNESCAPED_UNICODE|JSON_PRETTY_PRINT)."\n");
'

set +e
approve_output="$(control "$project" approve --workflow wf_policy_failed --feature FEATURE-POLICY --lease "$lease" 2>&1)"
approve_exit=$?
set -e
[ "$approve_exit" -ne 0 ] || fail 'approve aceitou resultado com policy divergente'
printf '%s' "$approve_output" | grep -Eiq 'execution_policy divergiu|policy_violation|recovery explícito' || fail 'approve não informou policy_violation e recovery explícito'

EVENTS_FILE="$project/.git/ralph-control/events.jsonl" php -r '
  $events = array_map(static fn(string $line): array => json_decode($line, true, 512, JSON_THROW_ON_ERROR), file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES));
  $recovery = array_values(array_filter($events, static fn(array $event): bool => ($event["type"] ?? null) === "recovery.required" && ($event["facts"]["reason"] ?? null) === "policy_violation"));
  if ($recovery === []) { fwrite(STDERR, "recovery.required/policy_violation ausente\n"); exit(1); }
  foreach ($recovery as $event) {
    if (($event["facts"]["cause_kind"] ?? null) !== "harness_defect") { exit(2); }
  }
  foreach ($events as $event) {
    if (($event["facts"]["reason"] ?? null) === "policy_violation" && ($event["facts"]["cause_kind"] ?? null) === "feature_bug") { exit(3); }
  }
'
[ -f "$project/.git/ralph-control/policy.lock" ] || fail 'policy.lock não foi criado'

status="$(control "$project" status)"
STATUS="$status" php -r '
  $status = json_decode(getenv("STATUS"), true, 512, JSON_THROW_ON_ERROR);
  $feature = $status["projection"]["features"][0] ?? [];
  exit(($feature["state"] ?? null) === "failed"
    && ($feature["result"]["status"] ?? null) === "failed"
    && ($feature["result"]["reason"] ?? null) === "policy_violation" ? 0 : 1);
'

set +e
supervise_output="$(control "$project" supervise --workflow wf_policy_failed --interval 1 --max-retries 2 2>&1)"
supervise_exit=$?
set -e
[ "$supervise_exit" -eq 0 ] || fail "supervise abortou em vez de registrar recovery: $supervise_output"
printf '%s' "$supervise_output" | grep -q '"status": "recovery_required"' || fail 'supervise não retornou recovery_required'

EVENTS_FILE="$project/.git/ralph-control/events.jsonl" php -r '
  $events = array_map(static fn(string $line): array => json_decode($line, true, 512, JSON_THROW_ON_ERROR), file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES));
  foreach ($events as $event) {
    if (($event["type"] ?? null) === "recovery.retry_started") { exit(1); }
  }
'

control "$project" reconcile --workflow wf_policy_failed --feature FEATURE-POLICY --policy >/dev/null
[ ! -f "$project/.git/ralph-control/policy.lock" ] || fail 'policy.lock sobreviveu à reconciliação'
reclaimed="$(control "$project" claim --workflow wf_policy_failed --feature FEATURE-POLICY --actor policy-reconciled)"
[ "$(json_field "$reclaimed" attempt)" = '2' ] || fail 'claim não foi liberada após reconcile --policy'

(cd "$project" && php "$ROOT/bin/ralph-control" verify >/dev/null)
printf 'ok   policy_violation vira failed/harness_defect, bloqueia retry/claim e exige reconcile explícito\n'
