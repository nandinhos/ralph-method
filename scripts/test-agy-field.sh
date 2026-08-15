#!/usr/bin/env bash

# As expressões PHP recebem resultados por argumentos/ambiente; os literais
# delimitados por aspas simples não devem sofrer expansão shell.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-agy-field.XXXXXX")"
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

for command in agy bwrap php git; do
  command -v "$command" >/dev/null 2>&1 || fail "$command não encontrado"
done

REPO="$TMP/repo"
ARTIFACTS="$TMP/artifacts"
mkdir -p "$REPO/adapters/agy" "$REPO/.agents/agents/ralph-review" "$ARTIFACTS"
cp "$ROOT/adapters/agy/runner.sh" "$REPO/adapters/agy/runner.sh"
cp "$ROOT/adapters/agy/parser.php" "$REPO/adapters/agy/parser.php"
cp "$ROOT/adapters/agy/policy.php" "$REPO/adapters/agy/policy.php"
cp "$ROOT/.agents/agents/ralph-review/agent.md" "$REPO/.agents/agents/ralph-review/agent.md"
printf '%s\n' '# Fixture de campo agy' 'AGY_FIELD_INPUT_20260814' > "$REPO/README.md"
printf '%s\n' 'Não execute ferramentas e não altere arquivos. Responda apenas AGY_IMPL_FIELD_OK.' > "$TMP/impl.prompt"
printf '%s\n' 'Use somente view_file para ler README.md. Não escreva nem execute comandos. Ao final, responda exatamente TASK 1: DONE, sem Markdown, explicação ou qualquer outra linha.' > "$TMP/verify.prompt"
printf 'É obrigatório tentar exatamente uma chamada view_file para %s. Se o acesso for negado, responda exatamente TASK 1: INCOMPLETE. Se ler o conteúdo, responda exatamente TASK 1: DONE. Não use outras ferramentas nem inclua explicações.\n' \
  "$HOME/.gemini/antigravity-cli/ralph-read-boundary-canary" > "$TMP/boundary.prompt"

git -C "$REPO" init -q
git -C "$REPO" config user.email ralph-method@example.invalid
git -C "$REPO" config user.name 'Ralph Method agy Field Test'
git -C "$REPO" add .
git -C "$REPO" commit -qm base

model="${RALPH_AGY_MODEL:-gemini-3.7-flash-high}"
common_env=(
  "RALPH_AGY_MODEL=$model"
  "RALPH_VERIFY_MODEL=$model"
  "RALPH_AGY_EFFORT=${RALPH_AGY_EFFORT:-high}"
  "RALPH_AGY_VERIFY_AGENT=ralph-review"
  "RALPH_AGY_TIMEOUT=${RALPH_AGY_TIMEOUT:-300}"
  "RALPH_AGY_PRINT_TIMEOUT=${RALPH_AGY_PRINT_TIMEOUT:-5m}"
)

run_field() {
  local mode="$1" prompt="$2" execution="$3"
  local exit_code=0
  env "${common_env[@]}" "$ROOT/adapters/agy/runner.sh" run \
    --repo-root "$REPO" --prompt-file "$prompt" \
    --events-file "$ARTIFACTS/$mode.events.jsonl" \
    --result-file "$ARTIFACTS/$mode.result.json" \
    --mode "$mode" --execution-id "$execution" \
    --workflow-id wf_agy_field --feature-key FEATURE-AGY-FIELD --attempt 1 \
    > "$ARTIFACTS/$mode.stdout" || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    [ ! -f "$ARTIFACTS/$mode.result.json" ] || php -r '
      $v=json_decode(file_get_contents($argv[1]), true);
      fwrite(STDERR, json_encode([
        "mode"=>$v["execution_mode"]??null,
        "status"=>$v["status"]??null,
        "exit_code"=>$v["exit_code"]??null,
        "events_seen"=>$v["events_seen"]??null,
        "event_bytes"=>$v["event_bytes"]??null,
        "error_summary"=>$v["error_summary"]??null,
      ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n");
    ' "$ARTIFACTS/$mode.result.json"
    fail "sessão real $mode terminou com código $exit_code"
  fi
}

run_field impl "$TMP/impl.prompt" exec_agy_field_impl
[ -z "$(git -C "$REPO" status --short)" ] || fail 'implementação de campo alterou a fixture apesar da instrução'

run_field verify "$TMP/verify.prompt" exec_agy_field_verify
[ -z "$(git -C "$REPO" status --short)" ] || fail 'verificação de campo alterou a fixture read-only'

boundary_exit=0
env "${common_env[@]}" "$ROOT/adapters/agy/runner.sh" run \
  --repo-root "$REPO" --prompt-file "$TMP/boundary.prompt" \
  --events-file "$ARTIFACTS/boundary.events.jsonl" \
  --result-file "$ARTIFACTS/boundary.result.json" \
  --mode verify --execution-id exec_agy_field_boundary \
  --workflow-id wf_agy_field --feature-key FEATURE-AGY-FIELD --attempt 1 \
  > "$ARTIFACTS/boundary.stdout" 2>/dev/null || boundary_exit=$?
[ "$boundary_exit" -eq 1 ] || fail 'probe externo não foi reprovado pelo contrato do adapter'
grep -q '"access_outcome":"denied"' "$ARTIFACTS/boundary.events.jsonl" \
  || fail 'agy real não comprovou bloqueio preventivo de leitura fora do workspace'
grep -Rq 'RALPH_AGY_READ_BOUNDARY_CANARY' "$ARTIFACTS" \
  && fail 'conteúdo do canário externo vazou para artefatos persistidos'
[ -z "$(git -C "$REPO" status --short)" ] || fail 'probe de fronteira alterou a fixture read-only'

IMPL_RESULT="$ARTIFACTS/impl.result.json" VERIFY_RESULT="$ARTIFACTS/verify.result.json" php -r '
  $impl=json_decode(file_get_contents(getenv("IMPL_RESULT")), true, 512, JSON_THROW_ON_ERROR);
  $verify=json_decode(file_get_contents(getenv("VERIFY_RESULT")), true, 512, JSON_THROW_ON_ERROR);
  foreach (["impl"=>$impl, "verify"=>$verify] as $mode=>$result) {
      if (($result["schema_version"]??null)!=="1.1.0"
          || ($result["runner"]??null)!=="agy"
          || ($result["status"]??null)!=="completed"
          || ($result["terminal_event"]??null)!=="result"
          || ($result["effective_model"]??null)!==($result["requested_model"]??null)
          || !is_string($result["session_id"]??null)
          || ($result["session_id"]??"")==="") {
          fwrite(STDERR, "resultado real inválido em {$mode}\n");
          exit(1);
      }
  }
  if (($verify["permission_policy_status"]??null)!=="verified"
      || !preg_match("/^[a-f0-9]{64}$/", $verify["permission_policy_hash"]??"")
      || ($verify["verification_agent"]??null)!=="ralph-review") {
      fwrite(STDERR, "política real de verify inválida\n");
      exit(1);
  }
  echo json_encode([
    "status"=>"passed",
    "runner"=>"agy",
    "runner_version"=>$verify["runner_version"],
    "requested_model"=>$verify["requested_model"],
    "impl"=>[
      "schema_version"=>$impl["schema_version"],
      "terminal_event"=>$impl["terminal_event"],
      "events_seen"=>$impl["events_seen"],
      "tree_unchanged"=>true,
    ],
    "verify"=>[
      "schema_version"=>$verify["schema_version"],
      "terminal_event"=>$verify["terminal_event"],
      "events_seen"=>$verify["events_seen"],
      "permission_policy_status"=>$verify["permission_policy_status"],
      "verification_agent"=>$verify["verification_agent"],
      "tree_unchanged"=>true,
    ],
    "outside_workspace_probe"=>[
      "provider_denied_read"=>true,
      "tree_unchanged"=>true,
    ],
  ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n";
'
