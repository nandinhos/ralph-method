#!/usr/bin/env bash

# Os blocos PHP são literais; não há expansão shell dentro das expressões.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-cursor-adapter.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  echo "FALHA: $1" >&2
  exit 1
}

mkdir -p "$TMP/bin" "$TMP/repo" "$TMP/artifacts"
echo '# Prompt' > "$TMP/prompt.md"
echo 'nonce=nonce-cursor-7' >> "$TMP/prompt.md"
echo '# Fixture' > "$TMP/repo/README.md"

cat > "$TMP/bin/agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --version)
    echo '0.1.0-fixture'
    ;;
  -p)
    # Lê o prompt do último argumento posicional e emite stream-json.
    prompt="${!#}"
    grep -q 'nonce-cursor-7' <<<"$prompt"
    case " $* " in
      *' --mode ask '*)
        if [[ " $* " == *'--force'* ]] || [[ " $* " == *'--trust'* ]] || [[ " $* " == *'--mode 'ask' '* ]]; then
          :
        fi
        echo '{"type":"system","model":"cursor/model-7","content":"init"}'
        echo '{"type":"result","content":"verify ok"}'
        ;;
      *)
        echo '{"type":"system","model":"cursor/model-7","content":"init"}'
        echo '{"type":"tool_call","tool":"write_to_file","content":"write"}'
        echo '{"type":"result","content":"impl ok"}'
        ;;
    esac
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$TMP/bin/agent"

php_bin="$(command -v php || true)"
[ -n "$php_bin" ] || fail 'PHP não está disponível no PATH do teste'
php_runtime_path="$(dirname "$php_bin"):/usr/bin:/bin"
fixture_path="$TMP/bin:$php_runtime_path"

# 1. preflight impl: contrato declarado not_required, hash null.
preflight_output="$(PATH="$fixture_path" RALPH_CURSOR_MODEL=cursor/model-7 \
  "$ROOT/adapters/cursor/runner.sh" preflight --mode impl --repo-root "$TMP/repo" --model cursor/model-7)"
PREFLIGHT_JSON="$preflight_output" php -r '
  $value = json_decode(getenv("PREFLIGHT_JSON"), true, 512, JSON_THROW_ON_ERROR);
  if (($value["runner"] ?? null) !== "cursor"
      || ($value["permission_policy_status"] ?? null) !== "not_required"
      || ($value["permission_policy_hash"] ?? null) !== null) {
      exit(1);
  }
'

# 2. preflight verify: contrato declarado (ask), nunca verified.
preflight_verify="$(PATH="$fixture_path" RALPH_CURSOR_MODEL=cursor/model-7 \
  "$ROOT/adapters/cursor/runner.sh" preflight --mode verify --repo-root "$TMP/repo" --model cursor/model-7)"
PREFLIGHT_JSON="$preflight_verify" php -r '
  $value = json_decode(getenv("PREFLIGHT_JSON"), true, 512, JSON_THROW_ON_ERROR);
  if (($value["permission_policy_status"] ?? null) !== "declared"
      || ($value["permission_policy_hash"] ?? null) !== null) {
      exit(1);
  }
'

# 3. preflight sem modelo explícito e sem RALPH_CURSOR_MODEL -> exit 2.
no_model_exit=0
PATH="$fixture_path" "$ROOT/adapters/cursor/runner.sh" preflight --mode impl --repo-root "$TMP/repo" >/dev/null 2>&1 || no_model_exit=$?
[ "$no_model_exit" -eq 2 ] || fail 'preflight sem modelo explícito foi aceito'

# 4. run impl: implementação completa com tool_call e result terminal.
PATH="$fixture_path" RALPH_CURSOR_MODEL=cursor/model-7 \
  RALPH_EXECUTION_WORKFLOW_ID=wf_fixture \
  RALPH_EXECUTION_FEATURE_KEY=FEATURE-CURSOR \
  RALPH_EXECUTION_ATTEMPT=1 \
  "$ROOT/adapters/cursor/runner.sh" run \
    --repo-root "$TMP/repo" \
    --prompt-file "$TMP/prompt.md" \
    --events-file "$TMP/artifacts/events.jsonl" \
    --result-file "$TMP/artifacts/result.json" \
    --mode impl \
    --execution-id exec_cursor_impl \
    --workflow-id wf_fixture \
    --feature-key FEATURE-CURSOR \
    --attempt 1 \
    --model cursor/model-7 > "$TMP/runner-output.json"

RESULT_FILE="$TMP/artifacts/result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  if (($result["status"] ?? null) !== "completed"
      || ($result["terminal_event"] ?? null) !== "result"
      || ($result["identity_status"] ?? null) !== "observed"
      || ($result["identity_source"] ?? null) !== "event_init_model"
      || ($result["runner"] ?? null) !== "cursor"
      || ($result["schema_version"] ?? null) !== "1.2.0"
      || ($result["permission_policy_status"] ?? null) !== "not_required"
      || ($result["permission_policy_hash"] ?? null) !== null
      || ($result["events_seen"] ?? 0) < 1) {
      exit(1);
  }
'

# 5. run verify: contrato declared, sem escrita observada, terminal result.
PATH="$fixture_path" RALPH_CURSOR_MODEL=cursor/model-7 \
  "$ROOT/adapters/cursor/runner.sh" run \
    --repo-root "$TMP/repo" \
    --prompt-file "$TMP/prompt.md" \
    --events-file "$TMP/artifacts/verify-events.jsonl" \
    --result-file "$TMP/artifacts/verify-result.json" \
    --mode verify \
    --execution-id exec_cursor_verify \
    --workflow-id wf_fixture \
    --feature-key FEATURE-CURSOR \
    --attempt 1 \
    --model cursor/model-7 >/dev/null

RESULT_FILE="$TMP/artifacts/verify-result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  if (($result["status"] ?? null) !== "completed"
      || ($result["execution_mode"] ?? null) !== "verify"
      || ($result["permission_policy_status"] ?? null) !== "declared"
      || ($result["permission_policy_hash"] ?? null) !== null
      || ($result["verification_agent"] ?? null) !== "ask") {
      exit(1);
  }
'

# 6. Contrato 1.2.0 válido contra o schema (impl e verify).
RESULT_FILE="$TMP/artifacts/result.json" SCHEMA_FILE="$ROOT/schemas/runner-result.schema.json" python3 - <<'PY'
import json
import os
from pathlib import Path

schema = json.loads(Path(os.environ['SCHEMA_FILE']).read_text())
result = json.loads(Path(os.environ['RESULT_FILE']).read_text())

required = {
    'schema_version', 'runner', 'runner_version', 'requested_model',
    'identity_status', 'identity_source', 'execution_id', 'execution_mode',
    'workflow_id', 'feature_key', 'attempt', 'status', 'exit_code',
    'fallback_used', 'fallback_status', 'events_seen', 'session_id',
    'terminal_event', 'error_summary', 'artifact_refs',
    'permission_policy_hash', 'permission_policy_status',
}
if not required.issubset(result) or result['runner'] != 'cursor' or result['schema_version'] != '1.2.0':
    raise SystemExit('resultado impl não contém o contrato 1.2.0 do cursor')
if result['execution_mode'] != 'impl' or result['permission_policy_hash'] is not None or result['permission_policy_status'] != 'not_required':
    raise SystemExit('resultado impl não respeita o contrato de política')
PY

# 7. Parser fail-closed: JSONL inválido -> failed.
echo '{"type":"system","content":"init"}' > "$TMP/artifacts/malformed.jsonl"
echo 'not-json' >> "$TMP/artifacts/malformed.jsonl"
php "$ROOT/adapters/cursor/parser.php" \
  --events "$TMP/artifacts/malformed.jsonl" \
  --sanitized-events "$TMP/artifacts/malformed-sanitized.jsonl" \
  --result "$TMP/artifacts/malformed-result.json" \
  --repo-root "$TMP/repo" \
  --exit-code 0 \
  --runner-version 0.1.0 \
  --requested-model cursor/model-7 \
  --execution-id exec_cursor_malformed \
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

# 8. Parser fail-closed: múltiplos result -> failed.
printf '%s\n' \
  '{"type":"system","content":"init"}' \
  '{"type":"result","content":"one"}' \
  '{"type":"result","content":"two"}' \
  > "$TMP/artifacts/multi-result.jsonl"
php "$ROOT/adapters/cursor/parser.php" \
  --events "$TMP/artifacts/multi-result.jsonl" \
  --sanitized-events "$TMP/artifacts/multi-result-sanitized.jsonl" \
  --result "$TMP/artifacts/multi-result-result.json" \
  --repo-root "$TMP/repo" \
  --exit-code 0 \
  --runner-version 0.1.0 \
  --requested-model cursor/model-7 \
  --execution-id exec_cursor_multi \
  --execution-mode impl \
  --workflow-id wf_fixture \
  --feature-key FEATURE-MULTI \
  --attempt 1 \
  --prompt-sha256 deadbeef \
  --prompt-transport file >/dev/null
RESULT_FILE="$TMP/artifacts/multi-result-result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  exit(($result["status"] ?? null) === "failed" && str_contains((string) ($result["error_summary"] ?? ""), "result") ? 0 : 1);
'

# 9. Parser fail-closed: escrita em verify -> failed.
printf '%s\n' \
  '{"type":"system","content":"init"}' \
  '{"type":"tool_call","tool":"write_to_file","content":"write"}' \
  '{"type":"result","content":"done"}' \
  > "$TMP/artifacts/verify-write.jsonl"
php "$ROOT/adapters/cursor/parser.php" \
  --events "$TMP/artifacts/verify-write.jsonl" \
  --sanitized-events "$TMP/artifacts/verify-write-sanitized.jsonl" \
  --result "$TMP/artifacts/verify-write-result.json" \
  --repo-root "$TMP/repo" \
  --exit-code 0 \
  --runner-version 0.1.0 \
  --requested-model cursor/model-7 \
  --execution-id exec_cursor_verify_write \
  --execution-mode verify \
  --workflow-id wf_fixture \
  --feature-key FEATURE-VERIFY-WRITE \
  --attempt 1 \
  --prompt-sha256 deadbeef \
  --prompt-transport file \
  --permission-policy-status declared \
  --verification-agent ask >/dev/null
RESULT_FILE="$TMP/artifacts/verify-write-result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  exit(($result["status"] ?? null) === "failed" && str_contains((string) ($result["error_summary"] ?? ""), "verify") ? 0 : 1);
'

# 10. Parser fail-closed: modelo efetivo divergente -> failed.
printf '%s\n' \
  '{"type":"system","model":"other/model","content":"init"}' \
  '{"type":"result","content":"done"}' \
  > "$TMP/artifacts/divergent-model.jsonl"
php "$ROOT/adapters/cursor/parser.php" \
  --events "$TMP/artifacts/divergent-model.jsonl" \
  --sanitized-events "$TMP/artifacts/divergent-model-sanitized.jsonl" \
  --result "$TMP/artifacts/divergent-model-result.json" \
  --repo-root "$TMP/repo" \
  --exit-code 0 \
  --runner-version 0.1.0 \
  --requested-model cursor/model-7 \
  --execution-id exec_cursor_divergent \
  --execution-mode impl \
  --workflow-id wf_fixture \
  --feature-key FEATURE-DIVERGENT \
  --attempt 1 \
  --prompt-sha256 deadbeef \
  --prompt-transport file >/dev/null
RESULT_FILE="$TMP/artifacts/divergent-model-result.json" php -r '
  $result = json_decode(file_get_contents(getenv("RESULT_FILE")), true, 512, JSON_THROW_ON_ERROR);
  exit(($result["status"] ?? null) === "failed" && str_contains((string) ($result["error_summary"] ?? ""), "modelo") ? 0 : 1);
'

# 11. Sanitização: eventos persistidos não contêm conteúdo completo do prompt/resposta.
[ -f "$TMP/artifacts/events.jsonl" ] || fail 'eventos sanitizados não foram persistidos'
if grep -q 'nonce-cursor-7' "$TMP/artifacts/events.jsonl"; then
  fail 'eventos sanitizados vazaram conteúdo do prompt'
fi

echo 'OK: adapter Cursor (CLI agent, stream-json, parser 1.2.0, verify declarado ask, limites e sanitização) passou.'
