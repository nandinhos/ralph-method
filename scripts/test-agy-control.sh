#!/usr/bin/env bash

# A fixture produz o runner-result com PHP para preservar tipos JSON exatos.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-agy-control.XXXXXX")"
cleanup() {
  if [ "${RALPH_TEST_KEEP_TMP:-0}" = 1 ]; then
    printf 'DEBUG_TMP=%s\n' "$TMP" >&2
  else
    rm -rf "$TMP"
  fi
}
trap cleanup EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control() {
  php "$ROOT/bin/ralph-control" "$@"
}

mkdir -p "$TMP/repo"
git -C "$TMP/repo" init -q
git -C "$TMP/repo" config user.email ralph-method@example.invalid
git -C "$TMP/repo" config user.name 'Ralph Method agy Control Test'
printf '%s\n' '# Fixture agy control' > "$TMP/repo/README.md"
printf '%s\n' '# Plano' > "$TMP/repo/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_agy_control","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-AGY","title":"Importar resultado agy","position":1}]}' > "$TMP/repo/workflow.json"

cat > "$TMP/repo/fake-agy-result.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .phases/logs
php -r '
  $invalid = getenv("RALPH_TEST_INVALID_AGY") === "1";
  $result = [
    "schema_version" => "1.1.0",
    "runner" => "agy",
    "runner_version" => "1.1.13",
    "provider" => $invalid ? "outro" : "agy",
    "requested_model" => "gemini-3.7-flash-high",
    "effective_model" => $invalid ? "modelo-divergente" : "gemini-3.7-flash-high",
    "identity_status" => "observed",
    "identity_source" => "event_init_model",
    "execution_id" => "exec_agy_control_impl",
    "execution_mode" => "impl",
    "workflow_id" => getenv("RALPH_EXECUTION_WORKFLOW_ID"),
    "feature_key" => getenv("RALPH_EXECUTION_FEATURE_KEY"),
    "attempt" => (int) getenv("RALPH_EXECUTION_ATTEMPT"),
    "session_id" => "conv_agy_control",
    "status" => "completed",
    "exit_code" => 0,
    "fallback_used" => $invalid,
    "fallback_status" => $invalid ? "detected" : "not_detected",
    "events_seen" => 2,
    "event_bytes" => 128,
    "terminal_event" => "result",
    "prompt_sha256" => str_repeat("a", 64),
    "prompt_transport" => "file_to_argument",
    "permission_policy_hash" => null,
    "permission_policy_status" => "not_required",
    "verification_agent" => null,
    "error_summary" => null,
    "artifact_refs" => [],
  ];
  file_put_contents(".phases/logs/agy-control.result.json", json_encode($result, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR)."\n");
'
SH
chmod +x "$TMP/repo/fake-agy-result.sh"
git -C "$TMP/repo" add .
git -C "$TMP/repo" commit -qm base
cp -a "$TMP/repo" "$TMP/invalid-repo"

(cd "$TMP/repo" && control init --workflow wf_agy_control --manifest workflow.json >/dev/null)
claim="$(cd "$TMP/repo" && control claim --workflow wf_agy_control --feature FEATURE-AGY --actor agy-control-test)"
lease="$(CLAIM="$claim" php -r '$v=json_decode(getenv("CLAIM"), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
[ -n "$lease" ] || fail 'claim não retornou lease'

(cd "$TMP/repo" && control run --workflow wf_agy_control --feature FEATURE-AGY --lease "$lease" --command './fake-agy-result.sh' >/dev/null)

EVENTS="$TMP/repo/.git/ralph-control/events.jsonl" php -r '
  $found=0;
  foreach (file(getenv("EVENTS"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event=json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"]??null)==="delegation.completed"
          && ($event["facts"]["runner"]??null)==="agy"
          && ($event["facts"]["execution_mode"]??null)==="impl"
          && ($event["facts"]["terminal_event"]??null)==="result") {
          $found++;
      }
  }
  exit($found===1 ? 0 : 1);
' || fail 'controlador não importou exatamente uma delegação agy 1.1.0'

(cd "$TMP/repo" && control verify >/dev/null)

(cd "$TMP/invalid-repo" && control init --workflow wf_agy_control --manifest workflow.json >/dev/null)
invalid_claim="$(cd "$TMP/invalid-repo" && control claim --workflow wf_agy_control --feature FEATURE-AGY --actor agy-control-invalid)"
invalid_lease="$(CLAIM="$invalid_claim" php -r '$v=json_decode(getenv("CLAIM"), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
invalid_exit=0
invalid_output="$(cd "$TMP/invalid-repo" && RALPH_TEST_INVALID_AGY=1 control run \
  --workflow wf_agy_control --feature FEATURE-AGY --lease "$invalid_lease" \
  --command './fake-agy-result.sh' 2>&1)" || invalid_exit=$?
[ "$invalid_exit" -ne 0 ] || fail 'controlador aceitou identidade/fallback agy incompatível'
printf '%s' "$invalid_output" | grep -q 'identidade, provider ou fallback incompatível' \
  || fail 'controlador não explicou resultado agy incompatível'

NORM="$TMP/normative-repo"
mkdir -p "$NORM/adapters/agy" "$NORM/.agents/agents/ralph-review" "$NORM/.ralph" "$TMP/bin"
cp "$ROOT/adapters/agy/runner.sh" "$NORM/adapters/agy/runner.sh"
cp "$ROOT/adapters/agy/parser.php" "$NORM/adapters/agy/parser.php"
cp "$ROOT/adapters/agy/policy.php" "$NORM/adapters/agy/policy.php"
cp "$ROOT/adapters/agy/contract.md" "$NORM/adapters/agy/contract.md"
cp "$ROOT/.agents/agents/ralph-review/agent.md" "$NORM/.agents/agents/ralph-review/agent.md"
printf '%s\n' '# Fixture normativa agy' > "$NORM/README.md"
printf '%s\n' '# Plano' > "$NORM/plan.md"
printf '%s\n' '# Fases' '' '## Phase 1: Provar adapter' '' '- [ ] **Task:** publicar impl e verify.' '  - **Acceptance criteria:** ambos os resultados são válidos.' > "$NORM/PHASES.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_agy_normative","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-AGY-NORM","title":"Executar adapter normativo","position":1}]}' > "$NORM/workflow.json"
printf '%s\n' 'oauth-fixture' > "$TMP/oauth-token"

cat > "$TMP/bin/bwrap" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/bin/bwrap"

cat > "$NORM/fake-ralph.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .phases/logs
policy_json="$(php adapters/agy/policy.php check --repo-root "$PWD" --agent ralph-review)"
policy_hash="$(POLICY_JSON="$policy_json" php -r '$v=json_decode(getenv("POLICY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $v["policy_hash"] ?? "";')"
for mode in impl verify; do
  MODE="$mode" POLICY_HASH="$policy_hash" php -r '
    $mode=getenv("MODE");
    $verify=$mode==="verify";
    $result=[
      "schema_version"=>"1.1.0", "runner"=>"agy", "runner_version"=>"1.1.13",
      "provider"=>"agy", "requested_model"=>"gemini-3.7-flash-high",
      "effective_model"=>"gemini-3.7-flash-high", "identity_status"=>"observed",
      "identity_source"=>"event_init_model", "execution_id"=>"exec_agy_norm_".$mode,
      "execution_mode"=>$mode, "workflow_id"=>getenv("RALPH_EXECUTION_WORKFLOW_ID"),
      "feature_key"=>getenv("RALPH_EXECUTION_FEATURE_KEY"),
      "attempt"=>(int)getenv("RALPH_EXECUTION_ATTEMPT"), "session_id"=>"conv_norm_".$mode,
      "status"=>"completed", "exit_code"=>0, "fallback_used"=>false,
      "fallback_status"=>"not_detected", "events_seen"=>2, "event_bytes"=>128,
      "terminal_event"=>"result", "prompt_sha256"=>str_repeat("b",64),
      "prompt_transport"=>"file_to_argument",
      "permission_policy_hash"=>$verify ? getenv("POLICY_HASH") : null,
      "permission_policy_status"=>$verify ? "verified" : "not_required",
      "verification_agent"=>$verify ? "ralph-review" : null,
      "error_summary"=>null, "artifact_refs"=>[],
    ];
    $name=$verify ? "agy.verify-fixture.result.json" : "agy.result.json";
    file_put_contents(".phases/logs/".$name, json_encode($result, JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR)."\n");
  '
done
SH
chmod +x "$NORM/fake-ralph.sh"
printf '%s\n' 'RALPH_BIN=./fake-ralph.sh' > "$NORM/.ralph/agy.env"
git -C "$NORM" init -q
git -C "$NORM" config user.email ralph-method@example.invalid
git -C "$NORM" config user.name 'Ralph Method agy Normative Test'
git -C "$NORM" add .
git -C "$NORM" commit -qm base

(cd "$NORM" && control init --workflow wf_agy_normative --manifest workflow.json >/dev/null)
norm_claim="$(cd "$NORM" && control claim --workflow wf_agy_normative --feature FEATURE-AGY-NORM --actor agy-normative)"
norm_lease="$(CLAIM="$norm_claim" php -r '$v=json_decode(getenv("CLAIM"), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
(
  cd "$NORM"
  PATH="$TMP/bin:/usr/bin:/bin" RALPH_AGY_TOKEN_FILE="$TMP/oauth-token" \
    control run --workflow wf_agy_normative --feature FEATURE-AGY-NORM \
      --lease "$norm_lease" --engine agy --test-cmd true >/dev/null
)

EVENTS="$NORM/.git/ralph-control/events.jsonl" php -r '
  $modes=[];
  foreach (file(getenv("EVENTS"), FILE_IGNORE_NEW_LINES|FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event=json_decode($line,true,512,JSON_THROW_ON_ERROR);
      if (($event["type"]??null)==="delegation.completed" && ($event["facts"]["runner"]??null)==="agy") {
          $mode=$event["facts"]["execution_mode"]??"";
          $modes[$mode]=($modes[$mode]??0)+1;
      }
  }
  exit(($modes["impl"]??0)===1 && ($modes["verify"]??0)===1 ? 0 : 1);
' || fail 'caminho normativo não importou exatamente um impl e um verify agy'

(cd "$NORM" && control verify >/dev/null)
printf '%s\n' 'OK: controlador importou agy 1.1, rejeitou identidade/fallback e exigiu impl+verify normativos.'
