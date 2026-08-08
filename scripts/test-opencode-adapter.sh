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
    if [ -n "${RALPH_OPENCODE_VERIFY_POLICY_PROOF:-}" ] || [ -n "${RALPH_OPENCODE_VERIFY_AGENT:-}" ]; then
      printf 'proof=%s agent=%s\n' "${RALPH_OPENCODE_VERIFY_POLICY_PROOF:-}" "${RALPH_OPENCODE_VERIFY_AGENT:-}" > "${RALPH_TEST_ENV_LEAK_FILE:?}"
    fi
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

preflight_output="$(PATH="$TMP/bin:/usr/bin:/bin" RALPH_OPENCODE_MODEL=fixture/model \
  "$ROOT/adapters/opencode/runner.sh" preflight --model fixture/model)"
PREFLIGHT_JSON="$preflight_output" php -r '
  $value = json_decode(getenv("PREFLIGHT_JSON"), true, 512, JSON_THROW_ON_ERROR);
  if (($value["permission_policy_status"] ?? null) !== "not_required" || !array_key_exists("permission_policy_hash", $value) || $value["permission_policy_hash"] !== null) {
      exit(1);
  }
'

PATH="$TMP/bin:/usr/bin:/bin" RALPH_OPENCODE_MODEL=fixture/model \
  RALPH_OPENCODE_VERIFY_POLICY_PROOF=/tmp/proof-secret \
  RALPH_OPENCODE_VERIFY_AGENT=ralph-review \
  RALPH_TEST_ENV_LEAK_FILE="$TMP/env-leak" \
  RALPH_EXECUTION_WORKFLOW_ID=wf_fixture \
  RALPH_EXECUTION_FEATURE_KEY=FEATURE-ADAPTER \
  RALPH_EXECUTION_ATTEMPT=1 \
  "$ROOT/adapters/opencode/runner.sh" run \
    --repo-root "$TMP/repo" \
    --prompt-file "$TMP/prompt.md" \
    --events-file "$TMP/artifacts/events.jsonl" \
    --result-file "$TMP/artifacts/result.json" \
    --mode impl \
  --execution-id exec_fixture_adapter \
    --workflow-id wf_fixture \
    --feature-key FEATURE-ADAPTER \
    --attempt 1 \
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
      || ($result["prompt_transport"] ?? null) !== "file"
      || ($result["execution_mode"] ?? null) !== "impl") {
      exit(1);
  }
'

RESULT_FILE="$TMP/artifacts/result.json" SCHEMA_FILE="$ROOT/schemas/runner-result.schema.json" python3 - <<'PY'
import copy
import json
import os
from pathlib import Path

json.loads(Path(os.environ['SCHEMA_FILE']).read_text())
result = json.loads(Path(os.environ['RESULT_FILE']).read_text())

required = {
    'schema_version', 'runner', 'runner_version', 'requested_model',
    'identity_status', 'identity_source', 'execution_id', 'execution_mode',
    'workflow_id', 'feature_key', 'attempt', 'status', 'exit_code',
    'fallback_used', 'fallback_status', 'events_seen', 'session_id',
    'terminal_event', 'error_summary', 'artifact_refs',
    'permission_policy_hash', 'permission_policy_status',
}
if not required.issubset(result) or result['runner'] != 'opencode':
    raise SystemExit('resultado impl não contém o contrato mínimo publicado')
if result['execution_mode'] != 'impl' or result['permission_policy_hash'] is not None or result['permission_policy_status'] != 'not_required':
    raise SystemExit('resultado impl não respeita o contrato de política')
if result['status'] == 'completed' and (not result['session_id'] or result['terminal_event'] != 'step_finish' or result['events_seen'] < 1):
    raise SystemExit('resultado impl concluído sem sessão, terminal ou eventos')

verify = copy.deepcopy(result)
verify.update({
    'execution_id': 'exec_fixture_verify_schema',
    'execution_mode': 'verify',
    'permission_policy_hash': 'a' * 64,
    'permission_policy_status': 'verified',
    'verification_agent': 'ralph-review',
})
if verify['execution_mode'] != 'verify' or len(verify['permission_policy_hash']) != 64 or verify['permission_policy_status'] != 'verified' or not verify['verification_agent']:
    raise SystemExit('resultado verify não respeita o contrato de política')
PY

[ ! -e "$TMP/env-leak" ] || fail 'prova read-only vazou para a implementação'

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
  --execution-mode impl \
  --workflow-id wf_fixture \
  --feature-key FEATURE-MALFORMED \
  --attempt 1 \
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
  --execution-mode impl \
  --workflow-id wf_fixture \
  --feature-key FEATURE-LIMIT \
  --attempt 1 \
  --prompt-sha256 deadbeef \
  --prompt-transport file \
  --max-events 1 >/dev/null

RESULT_FILE="$TMP/artifacts/too-many-result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  exit(($result["status"] ?? null) === "failed" && str_contains((string) ($result["error_summary"] ?? ""), "limite") ? 0 : 1);
'

echo 'OK: adapter OpenCode, transporte por arquivo, parser, schema impl/verify, sessão, evento terminal, tri-state e limites passaram.'
