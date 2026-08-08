#!/usr/bin/env bash

# Os blocos PHP e os fixtures recebem literais por aspas simples de propósito.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-provider.XXXXXX")"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

assert_json() {
  local json="$1"
  local expression="$2"
  JSON="$json" php -r "$expression" || fail "assertiva JSON falhou"
}

fake_bin="$TMP/bin"
project="$TMP/projeto"
mkdir -p "$fake_bin" "$project"
git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method Provider Test'
printf '%s\n' '# Provider fixture' > "$project/README.md"
git -C "$project" add README.md
git -C "$project" commit -qm base

printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in' '  --version) printf "%s\\n" "fixture token=supersecret" ;;' '  "login status") [ "${FAKE_CODEX_AUTH:-1}" = 1 ] && printf "%s\\n" "Logged in token=supersecret" || { printf "%s\\n" "Not logged in"; exit 1; } ;;' '  "doctor --json") [ "${FAKE_HEALTH:-1}" = 1 ] && printf "%s\\n" "{\\"healthy\\":true}" || exit 1 ;;' '  *--print*|*exec*|*run*) exit 91 ;;' '  *) exit 2 ;;' 'esac' > "$fake_bin/codex"
chmod +x "$fake_bin/codex"

printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in' '  --version) printf "%s\\n" "fixture" ;;' '  "auth status --json") [ "${FAKE_HANG:-0}" = 1 ] && sleep 20; [ "${FAKE_AUTH:-1}" = 1 ] && printf "%s\\n" "Logged in token=supersecret" || { printf "%s\\n" "Not logged in"; exit 1; } ;;' '  *--print*|*exec*|*run*) exit 91 ;;' '  *) exit 2 ;;' 'esac' > "$fake_bin/claude"
chmod +x "$fake_bin/claude"

printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in' '  --version) printf "%s\\n" "fixture" ;;' '  "auth list") [ "${FAKE_OPENCODE_AUTH:-1}" = 1 ] && printf "\\033[0m\\n┌  Credentials  ┐\\n●  OpenRouter api\\n●  Anthropic oauth\\n" || { printf "%s\\n" "●  OpenRouter api"; exit 7; } ;;' '  models) printf "%s\\n" "openrouter/model-a" "anthropic/model-b" ;;' '  *--print*|*exec*|*run*) exit 91 ;;' '  *) exit 2 ;;' 'esac' > "$fake_bin/opencode"
chmod +x "$fake_bin/opencode"

printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in' '  --version) printf "%s\\n" "fixture" ;;' '  "status") printf "%s\\n" "Provider: MiniMax" "Model: MiniMax-M3" "MiniMax          ✓ configured" "Other Provider   ✗ not logged in" ;;' '  "auth status MiniMax") printf "%s\\n" "minimax: logged in" ;;' '  *--print*|*exec*|*run*) exit 91 ;;' '  *) exit 2 ;;' 'esac' > "$fake_bin/hermes"
chmod +x "$fake_bin/hermes"

printf '%s\n' '#!/usr/bin/env bash' 'case "$1" in' '  --version) printf "%s\\n" "fixture" ;;' '  *--print*|*exec*|*run*) exit 91 ;;' '  *) exit 2 ;;' 'esac' > "$fake_bin/agy"
chmod +x "$fake_bin/agy"

common_env=(PATH="$fake_bin:/usr/bin:/bin" RALPH_METHOD_SOURCE="$ROOT" RALPH_HERMES_PROVIDER=)

without_verification="$(env "${common_env[@]}" "$ROOT/bin/ralph-init" plan --project "$project" --provider claude)"
assert_json "$without_verification" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    $provider = $plan["detection"]["providers"]["claude"] ?? [];
    exit(($provider["auth_status"] ?? null) === "not_checked" && ($provider["adapter_enabled"] ?? true) === false && ($plan["orchestration"]["mode"] ?? null) === "needs_review" ? 0 : 1);
'

verified="$(env "${common_env[@]}" "$ROOT/bin/ralph-init" plan --project "$project" --provider claude --verify-providers)"
printf '%s\n' "$verified" | grep -qv 'supersecret' || fail 'saída do probe vazou segredo'
assert_json "$verified" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    $provider = $plan["detection"]["providers"]["claude"] ?? [];
    exit(($provider["auth_status"] ?? null) === "authenticated" && ($provider["health_status"] ?? null) === "healthy" && ($provider["status"] ?? null) === "functional" && ($provider["adapter_enabled"] ?? false) === true && ($plan["orchestration"]["mode"] ?? null) === "single_provider" ? 0 : 1);
'

env "${common_env[@]}" "$ROOT/bin/ralph-init" apply --project "$project" --provider claude --verify-providers >/dev/null
assert_json "$(cat "$project/.ralph/providers.json")" '
    $providers = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($providers["providers"]["claude"]["status"] ?? null) === "functional" && ($providers["providers"]["claude"]["adapter_enabled"] ?? false) === true ? 0 : 1);
'

opencode_verified="$(env "${common_env[@]}" "$ROOT/bin/ralph-init" plan --project "$project" --provider opencode --verify-providers)"
printf '%s\n' "$opencode_verified" | grep -qv 'supersecret' || fail 'saída do probe OpenCode vazou segredo'
assert_json "$opencode_verified" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    $provider = $plan["detection"]["providers"]["opencode"] ?? [];
    exit(($provider["auth_status"] ?? null) === "authenticated" && ($provider["health_status"] ?? null) === "healthy" && ($provider["status"] ?? null) === "functional" && ($provider["runner_supported"] ?? true) === false && ($provider["adapter_enabled"] ?? true) === false && ($plan["orchestration"]["mode"] ?? null) === "needs_review" ? 0 : 1);
'

hermes_verified="$(env "${common_env[@]}" "$ROOT/bin/ralph-init" plan --project "$project" --provider hermes --verify-providers)"
assert_json "$hermes_verified" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    $provider = $plan["detection"]["providers"]["hermes"] ?? [];
    exit(($provider["auth_status"] ?? null) === "authenticated" && ($provider["health_status"] ?? null) === "healthy" && ($provider["status"] ?? null) === "functional" && ($provider["verification"]["provider_target"] ?? null) === "MiniMax" && ($provider["adapter_enabled"] ?? true) === false ? 0 : 1);
'

hermes_override="$(env "${common_env[@]}" RALPH_HERMES_PROVIDER=MiniMax "$ROOT/bin/ralph-init" plan --project "$project" --provider hermes --verify-providers)"
assert_json "$hermes_override" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["detection"]["providers"]["hermes"]["verification"]["provider_target"] ?? null) === "MiniMax" ? 0 : 1);
'

opencode_auth_failed="$(env "${common_env[@]}" FAKE_OPENCODE_AUTH=0 "$ROOT/bin/ralph-init" plan --project "$project" --provider opencode --verify-providers)"
assert_json "$opencode_auth_failed" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    $provider = $plan["detection"]["providers"]["opencode"] ?? [];
    exit(($provider["auth_status"] ?? null) === "unknown" && ($provider["status"] ?? null) === "authentication_unknown" && ($provider["adapter_enabled"] ?? true) === false ? 0 : 1);
'

auto_with_claude="$(env "${common_env[@]}" FAKE_CODEX_AUTH=0 "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_json "$auto_with_claude" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["selection"]["selected_provider"] ?? null) === "claude" && ($plan["orchestration"]["mode"] ?? null) === "single_provider" && in_array("claude", $plan["selection"]["functional_providers"] ?? [], true) ? 0 : 1);
'

unauthenticated="$(env "${common_env[@]}" FAKE_AUTH=0 "$ROOT/bin/ralph-init" plan --project "$project" --provider claude --verify-providers)"
assert_json "$unauthenticated" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    $provider = $plan["detection"]["providers"]["claude"] ?? [];
    exit(($provider["auth_status"] ?? null) === "unauthenticated" && ($provider["status"] ?? null) === "unauthenticated" && ($provider["adapter_enabled"] ?? true) === false ? 0 : 1);
'

apply_exit=0
env "${common_env[@]}" FAKE_AUTH=0 "$ROOT/bin/ralph-init" apply --project "$project" --provider claude --verify-providers >/dev/null 2>&1 || apply_exit=$?
[ "$apply_exit" -eq 3 ] || fail "provider não autenticado não bloqueou apply explícito"

auto_blocked="$(env "${common_env[@]}" FAKE_CODEX_AUTH=0 FAKE_AUTH=0 "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_json "$auto_blocked" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["orchestration"]["mode"] ?? null) === "needs_review" && ($plan["orchestration"]["primary_runner"] ?? null) === null && ($plan["selection"]["selected_provider"] ?? null) === null && ($plan["selection"]["adapter_enabled"] ?? true) === false ? 0 : 1);
'

no_runner="$(env PATH=/usr/bin:/bin RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$project" --provider auto --verify-providers)"
assert_json "$no_runner" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["orchestration"]["mode"] ?? null) === "needs_review" && ($plan["orchestration"]["primary_runner"] ?? null) === null && ($plan["selection"]["available_runners"] ?? ["unexpected"]) === [] ? 0 : 1);
'

started_at="$(date +%s)"
timed="$(env "${common_env[@]}" FAKE_HANG=1 "$ROOT/bin/ralph-init" plan --project "$project" --provider claude --verify-providers)"
elapsed=$(( $(date +%s) - started_at ))
[ "$elapsed" -lt 12 ] || fail "probe bloqueado não respeitou timeout"
assert_json "$timed" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["detection"]["providers"]["claude"]["status"] ?? null) === "authentication_unknown" ? 0 : 1);
'

unsupported="$(env "${common_env[@]}" "$ROOT/bin/ralph-init" plan --project "$project" --provider agy --verify-providers)"
assert_json "$unsupported" '
    $plan = json_decode(getenv("JSON"), true, 512, JSON_THROW_ON_ERROR);
    $provider = $plan["detection"]["providers"]["agy"] ?? [];
    exit(($provider["status"] ?? null) === "unsupported" && ($provider["adapter_enabled"] ?? true) === false ? 0 : 1);
'

printf 'OK: prontidão de provider, probe seguro, sanitização e bloqueio condicional passaram.\n'
