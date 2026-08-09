#!/usr/bin/env bash

# Regressão offline da seleção multiprovider. Os CLIs abaixo são fixtures
# determinísticos: nenhum comando de geração é permitido durante o probe.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "/tmp/ralph-method-multiprovider.XXXXXX")"

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

assert_json() {
  local json="$1"
  local expression="$2"
  JSON_PAYLOAD="$json" php -r "$expression" || fail 'assertiva JSON falhou'
}

assert_selection() {
  local json="$1"
  local expected_selected="$2"
  local expected_functional="$3"
  local expected_runners="$4"
  local expected_mode="$5"
  local expected_primary="$6"

  JSON_PAYLOAD="$json" \
  EXPECTED_SELECTED="$expected_selected" \
  EXPECTED_FUNCTIONAL="$expected_functional" \
  EXPECTED_RUNNERS="$expected_runners" \
  EXPECTED_MODE="$expected_mode" \
  EXPECTED_PRIMARY="$expected_primary" \
  php -r '
    $plan = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    $functional = json_decode(getenv("EXPECTED_FUNCTIONAL"), true, 512, JSON_THROW_ON_ERROR);
    $runners = json_decode(getenv("EXPECTED_RUNNERS"), true, 512, JSON_THROW_ON_ERROR);
    $primary = getenv("EXPECTED_PRIMARY");
    $primary = $primary === "null" ? null : $primary;
    $checks = [
        ($plan["selection"]["selected_provider"] ?? null) === (getenv("EXPECTED_SELECTED") === "null" ? null : getenv("EXPECTED_SELECTED")),
        ($plan["selection"]["functional_providers"] ?? []) === $functional,
        ($plan["selection"]["available_runners"] ?? []) === $runners,
        ($plan["orchestration"]["mode"] ?? null) === getenv("EXPECTED_MODE"),
        ($plan["orchestration"]["primary_runner"] ?? null) === $primary,
        ($plan["orchestration"]["fallback_policy"] ?? null) === "none",
    ];
    exit(in_array(false, $checks, true) ? 1 : 0);
  ' || fail 'seleção multiprovider não corresponde ao contrato esperado'
}

summary() {
  local json="$1"
  JSON_PAYLOAD="$json" php -r '
    $plan = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    echo json_encode([
        "selected_provider" => $plan["selection"]["selected_provider"] ?? null,
        "selected_status" => $plan["selection"]["selected_status"] ?? null,
        "functional_providers" => $plan["selection"]["functional_providers"] ?? [],
        "available_runners" => $plan["selection"]["available_runners"] ?? [],
        "mode" => $plan["orchestration"]["mode"] ?? null,
        "primary_runner" => $plan["orchestration"]["primary_runner"] ?? null,
        "fallback_policy" => $plan["orchestration"]["fallback_policy"] ?? null,
    ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
  '
}

fake_bin="$TMP/bin"
project="$TMP/projeto"
generation_log="$TMP/generation.log"
mkdir -p "$fake_bin" "$project/.codex" "$project/.claude" "$project/.opencode"

git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method Multiprovider Test'
printf '%s\n' '# Fixture multiprovider' > "$project/README.md"
git -C "$project" add README.md .codex .claude .opencode
git -C "$project" commit -qm base

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "$*" in' \
  '  --version) printf "%s\\n" "codex-fixture 1.0.0" ;;' \
  '  "login status") [ "$FAKE_CODEX_AUTH" = 1 ] && printf "%s\\n" "Logged in" || { printf "%s\\n" "Not logged in"; exit 1; } ;;' \
  '  "doctor --json") printf "%s\\n" "{\\"healthy\\":true}" ;;' \
  '  *--print*|*exec*|*run*) printf "%s\\n" "$*" >> "$FAKE_GENERATION_LOG"; exit 91 ;;' \
  '  *) exit 2 ;;' \
  'esac' > "$fake_bin/codex"
chmod +x "$fake_bin/codex"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "$*" in' \
  '  --version) printf "%s\\n" "claude-fixture 1.0.0" ;;' \
  '  "auth status --json") [ "$FAKE_CLAUDE_AUTH" = 1 ] && printf "%s\\n" "{\\"authenticated\\":true}" || { printf "%s\\n" "credentials not configured"; exit 1; } ;;' \
  '  *--print*|*exec*|*run*) printf "%s\\n" "$*" >> "$FAKE_GENERATION_LOG"; exit 91 ;;' \
  '  *) exit 2 ;;' \
  'esac' > "$fake_bin/claude"
chmod +x "$fake_bin/claude"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "$*" in' \
  '  --version) printf "%s\\n" "opencode-fixture 1.0.0" ;;' \
  '  "auth list") [ "$FAKE_OPENCODE_AUTH" = 1 ] && printf "\\033[0m\\n●  OpenRouter api\\n" || { printf "%s\\n" "credentials not configured"; exit 7; } ;;' \
  '  models) printf "%s\\n" "openrouter/model-a" "anthropic/model-b" ;;' \
  '  *--print*|*exec*|*run*) printf "%s\\n" "$*" >> "$FAKE_GENERATION_LOG"; exit 91 ;;' \
  '  *) exit 2 ;;' \
  'esac' > "$fake_bin/opencode"
chmod +x "$fake_bin/opencode"

php_bin="$(command -v php || true)"
[ -n "$php_bin" ] || fail 'PHP não está disponível no PATH do teste'
php_runtime_path="$(dirname "$php_bin"):/usr/bin:/bin"

common_env=(
  "PATH=$fake_bin:$php_runtime_path"
  "RALPH_METHOD_SOURCE=$ROOT"
  "RALPH_HERMES_PROVIDER="
  "FAKE_GENERATION_LOG=$generation_log"
)

all_functional="$(env "${common_env[@]}" FAKE_CODEX_AUTH=1 FAKE_CLAUDE_AUTH=1 FAKE_OPENCODE_AUTH=1 \
  "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_selection "$all_functional" codex '["codex","claude","opencode"]' '["codex","claude","opencode"]' native_codex codex

repeat_functional="$(env "${common_env[@]}" FAKE_CODEX_AUTH=1 FAKE_CLAUDE_AUTH=1 FAKE_OPENCODE_AUTH=1 \
  "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_eq "$(summary "$all_functional")" "$(summary "$repeat_functional")" 'seleção repetida não foi determinística'

codex_unavailable="$(env "${common_env[@]}" FAKE_CODEX_AUTH=0 FAKE_CLAUDE_AUTH=1 FAKE_OPENCODE_AUTH=1 \
  "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_selection "$codex_unavailable" claude '["claude","opencode"]' '["claude","opencode"]' single_provider claude
assert_json "$codex_unavailable" '
    $plan = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    $codex = $plan["detection"]["providers"]["codex"] ?? [];
    exit(($codex["status"] ?? null) === "unauthenticated" && ($codex["adapter_enabled"] ?? true) === false ? 0 : 1);
'

only_opencode="$(env "${common_env[@]}" FAKE_CODEX_AUTH=0 FAKE_CLAUDE_AUTH=0 FAKE_OPENCODE_AUTH=1 \
  "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_selection "$only_opencode" opencode '["opencode"]' '["opencode"]' single_provider opencode

none_functional="$(env "${common_env[@]}" FAKE_CODEX_AUTH=0 FAKE_CLAUDE_AUTH=0 FAKE_OPENCODE_AUTH=0 \
  "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_selection "$none_functional" null '[]' '[]' needs_review null
assert_json "$none_functional" '
    $plan = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["detection"]["verification"]["live_generation_probe"] ?? true) === false ? 0 : 1);
'

explicit_exit=0
env "${common_env[@]}" FAKE_CLAUDE_AUTH=0 FAKE_CODEX_AUTH=1 FAKE_OPENCODE_AUTH=1 \
  "$ROOT/bin/ralph-init" apply --project "$project" --provider claude --verify-providers \
  > "$TMP/explicit-apply.log" 2>&1 || explicit_exit=$?
assert_eq '3' "$explicit_exit" 'provider explícito não apto não bloqueou apply'
grep -q 'não está apto' "$TMP/explicit-apply.log" || fail 'apply bloqueado não explicou a causa'

[ ! -s "$generation_log" ] || fail 'probe executou comando generativo'

trace_project="$TMP/trace"
mkdir -p "$trace_project"
git -C "$trace_project" init -q
git -C "$trace_project" config user.email ralph-method@example.invalid
git -C "$trace_project" config user.name 'Ralph Method Trace Test'
printf '%s\n' '# Trace fixture' > "$trace_project/README.md"
printf '%s\n' '# Plano de trace' > "$trace_project/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_trace_matrix","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-TRACE","title":"Trace multiprovider","position":1}]}' > "$trace_project/workflow.json"
git -C "$trace_project" add README.md plan.md workflow.json
git -C "$trace_project" commit -qm base

control() {
  (cd "$trace_project" && php "$ROOT/bin/ralph-control" "$@")
}

control init --workflow wf_trace_matrix --manifest workflow.json >/dev/null

TRACE_LEASE=''

trace_feature() {
  local feature="$1"
  local execution="$2"
  local runner="$3"
  local provider="$4"
  local model="$5"
  local session="$6"
  local claim lease

  if [ -z "$TRACE_LEASE" ]; then
    claim="$(control claim --workflow wf_trace_matrix --feature "$feature" --actor multiprovider-test)"
    TRACE_LEASE="$(JSON_PAYLOAD="$claim" php -r '$payload = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR); echo $payload["lease_token"] ?? "";')"
  fi
  lease="$TRACE_LEASE"
  [ -n "$lease" ] || fail "claim não devolveu lease para $feature"
  control trace --workflow wf_trace_matrix --feature "$feature" --lease "$lease" \
    --event completed --execution-id "$execution" --runner "$runner" \
    --runner-version fixture-1.0.0 --provider "$provider" --model "$model" \
    --session-id "$session" --role implementation --identity-status exact \
    --identity-source usage_file --fallback-status not_detected >/dev/null
}

trace_feature FEATURE-TRACE exec_trace_codex codex openai gpt-5-codex sess_trace_codex
trace_feature FEATURE-TRACE exec_trace_claude claude anthropic claude-sonnet-4-20250514 sess_trace_claude
trace_feature FEATURE-TRACE exec_trace_opencode opencode opencode opencode/deepseek-v4-flash-free sess_trace_opencode

trace_report="$(control trace-report --workflow wf_trace_matrix --format json)"
assert_json "$trace_report" '
    $report = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    $expected = [
        "codex" => ["gpt-5-codex", "sess_trace_codex"],
        "claude" => ["claude-sonnet-4-20250514", "sess_trace_claude"],
        "opencode" => ["opencode/deepseek-v4-flash-free", "sess_trace_opencode"],
    ];
    $found = [];
    foreach ($report["features"] ?? [] as $feature) {
        foreach ($feature["delegations"] ?? [] as $delegation) {
            $runner = $delegation["runner"] ?? null;
            $found[$runner] = [$delegation["effective_model"] ?? null, $delegation["session_id"] ?? null];
            if (($delegation["identity_status"] ?? null) !== "exact" || ($delegation["fallback_status"] ?? null) !== "not_detected") {
                exit(1);
            }
        }
    }
    exit(($report["delegation_count"] ?? null) === 3 && $found === $expected ? 0 : 1);
'

printf 'OK: regressão multiprovider offline, seleção determinística, bloqueio sem fallback, probes não generativos e trace dos três harnesses passaram.\n'
