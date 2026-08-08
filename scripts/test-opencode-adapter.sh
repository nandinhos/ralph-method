#!/usr/bin/env bash

# Os blocos PHP são literais; não há expansão shell dentro das expressões.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-opencode-adapter.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FALHA: $1" >&2
  exit 1
}

mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/artifacts"
echo '# Prompt' > "$TMP/prompt.md"
echo 'nonce=nonce-adapter-42' >> "$TMP/prompt.md"
echo '# Fixture' > "$TMP/repo/README.md"

cat > "$TMP/bin/opencode" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    echo '1.18.15-fixture'
    ;;
  run)
    if [[ " $* " == *' --help '* ]]; then
      echo '--format default|json'
      echo '--file file(s) to attach to message'
      exit 0
    fi
    file=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = '--file' ]; then file="$2"; shift 2; continue; fi
      shift
    done
    grep -q 'nonce-adapter-42' "$file"
    echo '{"type":"step_start","sessionID":"ses_fixture_42"}'
    echo '{"type":"text","sessionID":"ses_fixture_42","providerID":"fixture","modelID":"model-42"}'
    echo '{"type":"step_finish","sessionID":"ses_fixture_42"}'
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$TMP/bin/opencode"

PATH="$TMP/bin:/usr/bin:/bin" RALPH_OPENCODE_MODEL=fixture/model \
  "$ROOT/adapters/opencode/runner.sh" preflight --model fixture/model >/dev/null

PATH="$TMP/bin:/usr/bin:/bin" RALPH_OPENCODE_MODEL=fixture/model \
  "$ROOT/adapters/opencode/runner.sh" run \
    --repo-root "$TMP/repo" \
    --prompt-file "$TMP/prompt.md" \
    --events-file "$TMP/artifacts/events.jsonl" \
    --result-file "$TMP/artifacts/result.json" \
    --mode impl \
    --execution-id exec_fixture_adapter \
    --model fixture/model \
    --auto 1 \
    --pure 1 > "$TMP/runner-output.json"

RESULT_FILE="$TMP/artifacts/result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  if (($result["status"] ?? null) !== "completed"
      || ($result["session_id"] ?? null) !== "ses_fixture_42"
      || ($result["terminal_event"] ?? null) !== "step_finish"
      || ($result["identity_status"] ?? null) !== "observed"
      || ! array_key_exists("fallback_used", $result)
      || $result["fallback_used"] !== null
      || ($result["fallback_status"] ?? null) !== "unknown"
      || ($result["prompt_transport"] ?? null) !== "file") {
      exit(1);
  }
'

verify_exit=0
PATH="$TMP/bin:/usr/bin:/bin" RALPH_OPENCODE_MODEL=fixture/model \
  "$ROOT/adapters/opencode/runner.sh" run \
    --repo-root "$TMP/repo" \
    --prompt-file "$TMP/prompt.md" \
    --events-file "$TMP/artifacts/verify-events.jsonl" \
    --result-file "$TMP/artifacts/verify-result.json" \
    --mode verify \
    --execution-id exec_fixture_verify \
    --model fixture/model >/dev/null 2>&1 || verify_exit=$?
[ "$verify_exit" -eq 2 ] || fail 'modo verify sem agente read-only foi aceito'

echo '{"type":"step_start","sessionID":"ses_bad"}' > "$TMP/artifacts/malformed.jsonl"
echo 'not-json' >> "$TMP/artifacts/malformed.jsonl"
php "$ROOT/adapters/opencode/parser.php" \
  --events "$TMP/artifacts/malformed.jsonl" \
  --result "$TMP/artifacts/malformed-result.json" \
  --exit-code 0 \
  --runner-version 1.18.15 \
  --provider fixture \
  --requested-model fixture/model \
  --execution-id exec_fixture_malformed \
  --prompt-sha256 deadbeef \
  --prompt-transport file >/dev/null

RESULT_FILE="$TMP/artifacts/malformed-result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  exit(($result["status"] ?? null) === "failed" && str_contains((string) ($result["error_summary"] ?? ""), "JSONL") ? 0 : 1);
'

echo '{"type":"step_start","sessionID":"ses_big"}' > "$TMP/artifacts/too-many.jsonl"
echo '{"type":"step_finish","sessionID":"ses_big"}' >> "$TMP/artifacts/too-many.jsonl"
php "$ROOT/adapters/opencode/parser.php" \
  --events "$TMP/artifacts/too-many.jsonl" \
  --result "$TMP/artifacts/too-many-result.json" \
  --exit-code 0 \
  --runner-version 1.18.15 \
  --provider fixture \
  --requested-model fixture/model \
  --execution-id exec_fixture_limit \
  --prompt-sha256 deadbeef \
  --prompt-transport file \
  --max-events 1 >/dev/null

RESULT_FILE="$TMP/artifacts/too-many-result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  exit(($result["status"] ?? null) === "failed" && str_contains((string) ($result["error_summary"] ?? ""), "limite") ? 0 : 1);
'

echo 'OK: adapter OpenCode, transporte por arquivo, parser, sessão, evento terminal, tri-state e limites passaram.'
