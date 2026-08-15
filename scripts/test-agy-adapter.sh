#!/usr/bin/env bash

# Fixtures usam literais em PHP e comandos fake controlados.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-agy-adapter.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$TMP/bin" "$TMP/repo/adapters/agy" "$TMP/repo/.agents/agents/ralph-review" "$TMP/artifacts"
cp "$ROOT/adapters/agy/runner.sh" "$TMP/repo/adapters/agy/runner.sh"
cp "$ROOT/adapters/agy/parser.php" "$TMP/repo/adapters/agy/parser.php"
cp "$ROOT/adapters/agy/policy.php" "$TMP/repo/adapters/agy/policy.php"
cp "$ROOT/.agents/agents/ralph-review/agent.md" "$TMP/repo/.agents/agents/ralph-review/agent.md"
printf '%s\n' '# Fixture agy' > "$TMP/repo/README.md"
printf '%s\n' 'nonce-agy-42' > "$TMP/prompt.txt"
printf '%s\n' 'oauth-fixture' > "$TMP/oauth-token"

cat > "$TMP/bin/agy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = '--version' ]; then
  printf '%s\n' 'agy 1.1.13-fixture'
  exit 0
fi
if [[ " $* " == *' --help '* ]]; then
  printf '%s\n' '--print --output-format --model --effort --print-timeout --mode --sandbox --agent --add-dir'
  exit 0
fi
if [ "${*: -1}" = agents ]; then
  printf '%s\n' 'ralph-review'
  exit 0
fi
model=''
prompt=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --model) model="$2"; shift 2 ;;
    --print) prompt="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[ "$prompt" = 'nonce-agy-42' ]
printf '{"event":"init","conversation_id":"conv_impl","init":{"model":"%s","cwd":"fixture","tools":[],"permission_mode":"always-proceed"}}\n' "$model"
printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_impl","step_index":0,"state":"DONE","step_type":"agent_response","text_delta":"FULL_SECRET_RESPONSE"}}'
printf '%s\n' '{"event":"result","result":{"conversation_id":"conv_impl","status":"SUCCESS","response":"IMPLEMENTATION_OK"}}'
EOF
chmod +x "$TMP/bin/agy"

cat > "$TMP/bin/bwrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' /bin/true '* ]] || [ "${*: -1}" = /bin/true ]; then
  exit 0
fi
printf '%s\n' "$*" > "${RALPH_TEST_BWRAP_ARGS:?}"
model=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--model' ]; then model="$2"; shift 2; continue; fi
  shift
done
stream_case="${RALPH_TEST_STREAM_CASE:-valid}"
if [ "$stream_case" = pre_init_other ]; then
  printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_outra","step_index":0,"state":"DONE","step_type":"tool","tool_name":"view_file","tool_info":{"parameters":{"AbsolutePath":"REPO_PLACEHOLDER/README.md"},"output":"FULL_FILE_CONTENT"}}}' | sed "s#REPO_PLACEHOLDER#${RALPH_TEST_REPO:?}#"
fi
init_model="$model"
[ "$stream_case" != model_divergence ] || init_model="${model}-fallback"
printf '{"event":"init","conversation_id":"conv_verify","init":{"model":"%s","cwd":"fixture","tools":[],"permission_mode":"request-review","expanded_commands":[{"name":"plan","type":"system"}]}}\n' "$init_model"
if [ "$stream_case" = invalid_json ]; then
  printf '%s\n' '{json-invalido'
fi
if [ "${RALPH_TEST_FORBIDDEN_TOOL:-0}" = 1 ]; then
  printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_verify","step_index":1,"state":"DONE","step_type":"tool","tool_name":"write_to_file","tool_info":{"parameters":{"TargetFile":"/tmp/canary"},"output":"FULL_TOOL_OUTPUT"}}}'
elif [ "$stream_case" = unknown_parameters ]; then
  printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_verify","step_index":1,"state":"DONE","step_type":"tool","tool_name":"view_file","tool_info":{"parameters":{"uri":"/tmp/fora"},"output":"FULL_TOOL_OUTPUT"}}}'
elif [ "$stream_case" = invalid_parameter_type ]; then
  printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_verify","step_index":1,"state":"DONE","step_type":"tool","tool_name":"view_file","tool_info":{"parameters":{"AbsolutePath":42},"output":"FULL_TOOL_OUTPUT"}}}'
elif [ "$stream_case" = second_session ]; then
  printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_other","step_index":1,"state":"DONE","step_type":"tool","tool_name":"view_file","tool_info":{"parameters":{"AbsolutePath":"REPO_PLACEHOLDER/README.md"},"output":"FULL_FILE_CONTENT"}}}' | sed "s#REPO_PLACEHOLDER#${RALPH_TEST_REPO:?}#"
else
  printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_verify","step_index":1,"state":"DONE","step_type":"tool","tool_name":"view_file","tool_info":{"parameters":{"AbsolutePath":"REPO_PLACEHOLDER/README.md"},"output":"FULL_FILE_CONTENT"}}}' | sed "s#REPO_PLACEHOLDER#${RALPH_TEST_REPO:?}#"
fi
if [ "${RALPH_TEST_AMBIGUOUS_VERDICT:-0}" = 1 ]; then
  printf '%s\n' '{"event":"result","result":{"conversation_id":"conv_verify","status":"SUCCESS","response":"Não pude verificar; o formato esperado seria TASK 1: DONE — FULL_SECRET_RESPONSE"}}'
else
  printf '%s\n' '{"event":"result","result":{"conversation_id":"conv_verify","status":"SUCCESS","response":"TASK 1: DONE"}}'
fi
[ "$stream_case" != duplicate_result ] || printf '%s\n' '{"event":"result","result":{"conversation_id":"conv_verify","status":"SUCCESS","response":"TASK 1: DONE"}}'
[ "$stream_case" != terminal_not_final ] || printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_verify","step_index":2,"state":"DONE","step_type":"agent_response"}}'
EOF
chmod +x "$TMP/bin/bwrap"

php_bin="$(command -v php || true)"
[ -n "$php_bin" ] || fail 'PHP ausente'
fixture_path="$TMP/bin:$(dirname "$php_bin"):/usr/bin:/bin"
common_env=(
  "PATH=$fixture_path"
  "RALPH_AGY_MODEL=gemini-3.7-flash-high"
  "RALPH_AGY_EFFORT=high"
  "RALPH_AGY_VERIFY_AGENT=ralph-review"
  "RALPH_AGY_TOKEN_FILE=$TMP/oauth-token"
  "RALPH_TEST_BWRAP_ARGS=$TMP/bwrap-args"
  "RALPH_TEST_REPO=$TMP/repo"
)

impl_preflight="$(env "${common_env[@]}" "$ROOT/adapters/agy/runner.sh" preflight --mode impl --repo-root "$TMP/repo")"
PREFLIGHT="$impl_preflight" php -r '
  $v=json_decode(getenv("PREFLIGHT"), true, 512, JSON_THROW_ON_ERROR);
  exit(($v["runner"]??null)==="agy" && ($v["permission_policy_status"]??null)==="not_required"
    && array_key_exists("permission_policy_hash", $v) && $v["permission_policy_hash"]===null ? 0 : 1);
' || fail 'preflight impl inválido'

verify_preflight="$(env "${common_env[@]}" "$ROOT/adapters/agy/runner.sh" preflight --mode verify --repo-root "$TMP/repo")"
PREFLIGHT="$verify_preflight" php -r '
  $v=json_decode(getenv("PREFLIGHT"), true, 512, JSON_THROW_ON_ERROR);
  exit(($v["permission_policy_status"]??null)==="verified" && preg_match("/^[a-f0-9]{64}$/", $v["permission_policy_hash"]??"") ? 0 : 1);
' || fail 'preflight verify inválido'

ln -s "$TMP/oauth-token" "$TMP/repo/token-symlink"
symlink_exit=0
env "${common_env[@]}" php "$ROOT/adapters/agy/policy.php" check \
  --repo-root "$TMP/repo" --agent ralph-review >/dev/null 2>&1 || symlink_exit=$?
[ "$symlink_exit" -eq 1 ] || fail 'policy aceitou symlink com destino externo'
rm -f "$TMP/repo/token-symlink"

ln "$TMP/oauth-token" "$TMP/repo/token-hardlink"
hardlink_exit=0
env "${common_env[@]}" php "$ROOT/adapters/agy/policy.php" check \
  --repo-root "$TMP/repo" --agent ralph-review >/dev/null 2>&1 || hardlink_exit=$?
[ "$hardlink_exit" -eq 1 ] || fail 'policy aceitou hardlink para o token OAuth'
rm -f "$TMP/repo/token-hardlink"

env "${common_env[@]}" "$ROOT/adapters/agy/runner.sh" run \
  --repo-root "$TMP/repo" --prompt-file "$TMP/prompt.txt" \
  --events-file "$TMP/artifacts/impl.events.jsonl" --result-file "$TMP/artifacts/impl.result.json" \
  --mode impl --execution-id exec_agy_impl --workflow-id wf_agy_fixture \
  --feature-key FEATURE-AGY --attempt 1 > "$TMP/impl.output"

RESULT="$TMP/artifacts/impl.result.json" php -r '
  $v=json_decode(file_get_contents(getenv("RESULT")), true, 512, JSON_THROW_ON_ERROR);
  exit(($v["schema_version"]??null)==="1.1.0" && ($v["runner"]??null)==="agy"
    && ($v["status"]??null)==="completed" && ($v["terminal_event"]??null)==="result"
    && ($v["effective_model"]??null)==="gemini-3.7-flash-high"
    && ($v["permission_policy_status"]??null)==="not_required" ? 0 : 1);
' || fail 'resultado impl inválido'
RESULT_FILE="$TMP/artifacts/impl.result.json" SCHEMA_FILE="$ROOT/schemas/runner-result.schema.json" python3 - <<'PY'
import json
import os
from pathlib import Path

from jsonschema import Draft202012Validator

schema = json.loads(Path(os.environ['SCHEMA_FILE']).read_text())
result = json.loads(Path(os.environ['RESULT_FILE']).read_text())
Draft202012Validator(schema).validate(result)
PY
grep -q 'FULL_SECRET_RESPONSE' "$TMP/artifacts/impl.events.jsonl" && fail 'evento impl persistiu resposta bruta'

env "${common_env[@]}" "$ROOT/adapters/agy/runner.sh" run \
  --repo-root "$TMP/repo" --prompt-file "$TMP/prompt.txt" \
  --events-file "$TMP/artifacts/verify.events.jsonl" --result-file "$TMP/artifacts/verify.result.json" \
  --mode verify --execution-id exec_agy_verify --workflow-id wf_agy_fixture \
  --feature-key FEATURE-AGY --attempt 1 > "$TMP/verify.output"

RESULT="$TMP/artifacts/verify.result.json" php -r '
  $v=json_decode(file_get_contents(getenv("RESULT")), true, 512, JSON_THROW_ON_ERROR);
  exit(($v["status"]??null)==="completed" && ($v["verification_agent"]??null)==="ralph-review"
    && ($v["permission_policy_status"]??null)==="verified"
    && preg_match("/^[a-f0-9]{64}$/", $v["permission_policy_hash"]??"") ? 0 : 1);
' || fail 'resultado verify inválido'
RESULT_FILE="$TMP/artifacts/verify.result.json" SCHEMA_FILE="$ROOT/schemas/runner-result.schema.json" python3 - <<'PY'
import json
import os
from pathlib import Path

from jsonschema import Draft202012Validator

schema = json.loads(Path(os.environ['SCHEMA_FILE']).read_text())
result = json.loads(Path(os.environ['RESULT_FILE']).read_text())
Draft202012Validator(schema).validate(result)
PY
grep -q -- '--clearenv' "$TMP/bwrap-args" || fail 'verify não limpou ambiente'
grep -q -- '--ro-bind .*repo .*repo' "$TMP/bwrap-args" || fail 'verify não montou repo read-only'
grep -q -- '--mode plan' "$TMP/bwrap-args" || fail 'verify não aplicou mode plan'
grep -q -- 'settings.json' "$TMP/bwrap-args" || fail 'verify não montou settings restritivo'
BWRAP_ARGS="$TMP/bwrap-args" php -r '
  $args=file_get_contents(getenv("BWRAP_ARGS"));
  $tmp=strpos($args, "--tmpfs /tmp");
  $repo=strpos($args, "--ro-bind ".realpath($argv[1])." ".realpath($argv[1]));
  exit(is_int($tmp) && is_int($repo) && $tmp < $repo ? 0 : 1);
' "$TMP/repo" || fail '/tmp efêmero ocultaria repo-root montado antes dele'
grep -Eq 'FULL_FILE_CONTENT|AbsolutePath|README.md' "$TMP/artifacts/verify.events.jsonl" && fail 'evento verify persistiu dados de ferramenta'
find "$TMP/artifacts" -maxdepth 1 -type f \( -name '.agy-events.*' -o -name '.agy-stderr.*' \) -print -quit | grep -q . \
  && fail 'adapter deixou evento/stderr bruto no diretório de resultados'
[ "$(cat "$TMP/artifacts/verify.result.json.text")" = 'TASK 1: DONE' ] || fail 'saída textual não foi reduzida ao veredito canônico'

ambiguous_exit=0
env "${common_env[@]}" RALPH_TEST_AMBIGUOUS_VERDICT=1 "$ROOT/adapters/agy/runner.sh" run \
  --repo-root "$TMP/repo" --prompt-file "$TMP/prompt.txt" \
  --events-file "$TMP/artifacts/ambiguous.events.jsonl" --result-file "$TMP/artifacts/ambiguous.result.json" \
  --mode verify --execution-id exec_agy_ambiguous --workflow-id wf_agy_fixture \
  --feature-key FEATURE-AGY --attempt 1 >/dev/null 2>&1 || ambiguous_exit=$?
[ "$ambiguous_exit" -eq 1 ] || fail 'resposta ambígua foi convertida em aprovação'
RESULT="$TMP/artifacts/ambiguous.result.json" php -r '
  $v=json_decode(file_get_contents(getenv("RESULT")), true, 512, JSON_THROW_ON_ERROR);
  exit(($v["status"]??null)==="failed" && str_contains($v["error_summary"]??"", "canônicos") ? 0 : 1);
' || fail 'falha de veredito ambíguo não foi normalizada'
grep -Rq 'FULL_SECRET_RESPONSE' "$TMP/artifacts" && fail 'resposta completa persistiu nos artefatos do adapter'

run_failed_stream_case() {
  local stream_case="$1" expected="$2" extra_name="${3:-}"
  local execution="exec_agy_${stream_case}" exit_code=0
  local limits=()
  [ "$extra_name" != max_events ] || limits+=(RALPH_AGY_MAX_EVENTS=1)
  [ "$extra_name" != max_bytes ] || limits+=(RALPH_AGY_MAX_EVENT_BYTES=10)
  env "${common_env[@]}" "${limits[@]}" RALPH_TEST_STREAM_CASE="$stream_case" \
    "$ROOT/adapters/agy/runner.sh" run \
    --repo-root "$TMP/repo" --prompt-file "$TMP/prompt.txt" \
    --events-file "$TMP/artifacts/$execution.events.jsonl" \
    --result-file "$TMP/artifacts/$execution.result.json" \
    --mode verify --execution-id "$execution" --workflow-id wf_agy_fixture \
    --feature-key FEATURE-AGY --attempt 1 >/dev/null 2>&1 || exit_code=$?
  [ "$exit_code" -eq 1 ] || fail "stream $stream_case/$extra_name não falhou fechado"
  RESULT="$TMP/artifacts/$execution.result.json" EXPECTED="$expected" php -r '
    $v=json_decode(file_get_contents(getenv("RESULT")), true, 512, JSON_THROW_ON_ERROR);
    exit(($v["status"]??null)==="failed"
      && str_contains($v["error_summary"]??"", getenv("EXPECTED")) ? 0 : 1);
  ' || fail "stream $stream_case/$extra_name não publicou erro normalizado"
}

run_failed_stream_case invalid_json 'JSON inválida'
run_failed_stream_case pre_init_other 'deve iniciar com init'
run_failed_stream_case duplicate_result 'exatamente um result'
run_failed_stream_case second_session 'múltiplas conversas'
run_failed_stream_case model_divergence 'modelo efetivo diverge'
run_failed_stream_case terminal_not_final 'exatamente um result'
run_failed_stream_case unknown_parameters 'parâmetros desconhecidos'
run_failed_stream_case invalid_parameter_type 'parâmetros desconhecidos'
run_failed_stream_case valid 'limite de eventos' max_events
run_failed_stream_case valid 'limite de bytes' max_bytes

forbidden_exit=0
env "${common_env[@]}" RALPH_TEST_FORBIDDEN_TOOL=1 "$ROOT/adapters/agy/runner.sh" run \
  --repo-root "$TMP/repo" --prompt-file "$TMP/prompt.txt" \
  --events-file "$TMP/artifacts/forbidden.events.jsonl" --result-file "$TMP/artifacts/forbidden.result.json" \
  --mode verify --execution-id exec_agy_forbidden --workflow-id wf_agy_fixture \
  --feature-key FEATURE-AGY --attempt 1 >/dev/null 2>&1 || forbidden_exit=$?
[ "$forbidden_exit" -eq 1 ] || fail 'ferramenta proibida não reprovou verify'
RESULT="$TMP/artifacts/forbidden.result.json" php -r '
  $v=json_decode(file_get_contents(getenv("RESULT")), true, 512, JSON_THROW_ON_ERROR);
  exit(($v["status"]??null)==="failed" && str_contains($v["error_summary"]??"", "allowlist") ? 0 : 1);
' || fail 'falha de allowlist não foi normalizada'

tree_before="$(find -P "$TMP/repo" -type f -print0 | sort -z | xargs -0 sha256sum)"
real_bwrap_exit=0
/usr/bin/bwrap --die-with-parent --unshare-pid --ro-bind / / --proc /proc --dev /dev \
  /bin/sh -c 'printf mutation >> "$1"' sh "$TMP/repo/README.md" >/dev/null 2>&1 || real_bwrap_exit=$?
[ "$real_bwrap_exit" -ne 0 ] || fail 'bwrap real permitiu escrita no repo read-only'
tree_after="$(find -P "$TMP/repo" -type f -print0 | sort -z | xargs -0 sha256sum)"
[ "$tree_before" = "$tree_after" ] || fail 'tentativa real sob bwrap alterou a árvore/canário'

hash_before="$(env "${common_env[@]}" php "$ROOT/adapters/agy/policy.php" hash --repo-root "$TMP/repo" --agent ralph-review)"
printf '%s\n' '# mudança' >> "$TMP/repo/.agents/agents/ralph-review/agent.md"
hash_after="$(env "${common_env[@]}" php "$ROOT/adapters/agy/policy.php" hash --repo-root "$TMP/repo" --agent ralph-review)"
[ "$hash_before" != "$hash_after" ] || fail 'policy hash não reagiu à mudança de superfície'

printf '%s\n' 'OK: adapter agy, schema 1.1, sanitização, isolamento e falhas fail-closed passaram.'
