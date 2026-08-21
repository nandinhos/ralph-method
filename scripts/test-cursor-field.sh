#!/usr/bin/env bash

# Prova de campo opt-in do adapter Cursor (FEATURE-100A / BL-0004).
# Exige CLI autenticada (`agent login`) e consentimento explícito.
# Não faz parte de scripts/ci-portable.sh — espelha scripts/test-agy-field.sh.
#
# Uso:
#   RALPH_CURSOR_FIELD=1 bash scripts/test-cursor-field.sh
#
# Variáveis:
#   RALPH_CURSOR_FIELD=1          obrigatório (opt-in)
#   RALPH_CURSOR_MODEL            modelo explícito (ou .ralph/cursor.env)
#   RALPH_CURSOR_CLI              binário agent/cursor-agent
#   RALPH_CURSOR_TIMEOUT          timeout por sessão (default 300)
#   RALPH_TEST_KEEP_TMP=1         preserva $TMP para debug
#
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-cursor-field.XXXXXX")"
CANARY="CURSOR_FIELD_CANARY_20260817"
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

[ "${RALPH_CURSOR_FIELD:-0}" = 1 ] \
  || fail 'campo Cursor opt-in: exporte RALPH_CURSOR_FIELD=1 antes de executar'

if [ -f "$ROOT/.ralph/cursor.env" ]; then
  # shellcheck disable=SC1091
  set -a
  # shellcheck source=/dev/null
  source "$ROOT/.ralph/cursor.env"
  set +a
fi

for command in php git; do
  command -v "$command" >/dev/null 2>&1 || fail "$command não encontrado"
done

resolve_cursor_cli() {
  if [ -n "${RALPH_CURSOR_CLI:-}" ]; then
    printf '%s' "$RALPH_CURSOR_CLI"
    return 0
  fi
  if command -v agent >/dev/null 2>&1; then
    command -v agent
    return 0
  fi
  if command -v cursor-agent >/dev/null 2>&1; then
    command -v cursor-agent
    return 0
  fi
  for candidate in "$HOME/.local/bin/agent" "$HOME/.local/bin/cursor-agent"; do
    if [ -x "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

CURSOR_CLI="$(resolve_cursor_cli 2>/dev/null || true)"
[ -n "$CURSOR_CLI" ] || fail 'CLI Cursor não encontrada (agent/cursor-agent ou RALPH_CURSOR_CLI)'

if [[ "$CURSOR_CLI" == */* ]]; then
  [ -x "$CURSOR_CLI" ] || fail "RALPH_CURSOR_CLI não executável: $CURSOR_CLI"
else
  command -v "$CURSOR_CLI" >/dev/null 2>&1 || fail "comando não encontrado: $CURSOR_CLI"
fi

model="${RALPH_CURSOR_MODEL:-}"
[ -n "$model" ] || fail 'RALPH_CURSOR_MODEL obrigatório (defina no ambiente ou em .ralph/cursor.env)'

auth_json="$("$CURSOR_CLI" status --format json 2>/dev/null)" \
  || fail 'agent status --format json falhou — rode: agent login'
AUTH_JSON="$auth_json" php -r '
  $value = json_decode(getenv("AUTH_JSON"), true);
  if (! is_array($value) || ($value["isAuthenticated"] ?? false) !== true) {
      fwrite(STDERR, "sessão Cursor não autenticada\n");
      exit(1);
  }
' || fail 'sessão Cursor não autenticada — rode: agent login'

REPO="$TMP/repo"
ARTIFACTS="$TMP/artifacts"
mkdir -p "$REPO" "$ARTIFACTS"
printf '%s\n' '# Fixture de campo Cursor' "$CANARY" > "$REPO/README.md"
printf '%s\n' \
  'Não use ferramentas. Não altere arquivos.' \
  'Responda apenas com a linha exata: CURSOR_IMPL_FIELD_OK' > "$TMP/impl.prompt"
printf '%s\n' \
  'Modo verificação read-only. Não use ferramentas de escrita nem terminal.' \
  'Se precisar, leia README.md somente por inspeção interna.' \
  'Responda apenas com a linha exata: TASK 1: DONE' > "$TMP/verify.prompt"

git -C "$REPO" init -q
git -C "$REPO" config user.email ralph-method@example.invalid
git -C "$REPO" config user.name 'Ralph Method Cursor Field Test'
git -C "$REPO" add .
git -C "$REPO" commit -qm base

timeout_seconds="${RALPH_CURSOR_TIMEOUT:-300}"
common_env=(
  "RALPH_CURSOR_MODEL=$model"
  "RALPH_CURSOR_CLI=$CURSOR_CLI"
  "RALPH_CURSOR_TIMEOUT=$timeout_seconds"
  "RALPH_CURSOR_VERIFY_MODE=ask"
)

run_field() {
  local mode="$1" prompt="$2" execution="$3"
  local exit_code=0
  env "${common_env[@]}" "$ROOT/adapters/cursor/runner.sh" run \
    --repo-root "$REPO" --prompt-file "$prompt" \
    --events-file "$ARTIFACTS/$mode.events.jsonl" \
    --result-file "$ARTIFACTS/$mode.result.json" \
    --mode "$mode" --execution-id "$execution" \
    --workflow-id wf_cursor_field --feature-key FEATURE-CURSOR-FIELD --attempt 1 \
    > "$ARTIFACTS/$mode.stdout" || exit_code=$?
  if [ "$exit_code" -ne 0 ]; then
    if [ -f "$ARTIFACTS/$mode.result.json" ]; then
      RESULT_JSON="$ARTIFACTS/$mode.result.json" php -r '
        $v = json_decode(file_get_contents(getenv("RESULT_JSON")), true);
        fwrite(STDERR, json_encode([
          "mode" => $v["execution_mode"] ?? null,
          "status" => $v["status"] ?? null,
          "exit_code" => $v["exit_code"] ?? null,
          "events_seen" => $v["events_seen"] ?? null,
          "event_bytes" => $v["event_bytes"] ?? null,
          "error_summary" => $v["error_summary"] ?? null,
        ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n");
      '
    fi
    fail "sessão real $mode terminou com código $exit_code"
  fi
}

run_field impl "$TMP/impl.prompt" exec_cursor_field_impl
[ -z "$(git -C "$REPO" status --short)" ] \
  || fail 'implementação de campo alterou a fixture apesar da instrução'

run_field verify "$TMP/verify.prompt" exec_cursor_field_verify
[ -z "$(git -C "$REPO" status --short)" ] \
  || fail 'verificação de campo alterou a fixture read-only'

# Canário: conteúdo exclusivo do README não deve vazar para stdout/resultado.
if grep -Rq "$CANARY" "$ARTIFACTS"/*.stdout "$ARTIFACTS"/*.result.json 2>/dev/null; then
  fail 'conteúdo do canário vazou para stdout ou resultado persistido'
fi

IMPL_RESULT="$ARTIFACTS/impl.result.json" VERIFY_RESULT="$ARTIFACTS/verify.result.json" php -r '
  $impl = json_decode(file_get_contents(getenv("IMPL_RESULT")), true, 512, JSON_THROW_ON_ERROR);
  $verify = json_decode(file_get_contents(getenv("VERIFY_RESULT")), true, 512, JSON_THROW_ON_ERROR);
  foreach (["impl" => $impl, "verify" => $verify] as $mode => $result) {
      if (($result["schema_version"] ?? null) !== "1.2.0"
          || ($result["runner"] ?? null) !== "cursor"
          || ($result["status"] ?? null) !== "completed"
          || ($result["terminal_event"] ?? null) !== "result"
          || ! is_string($result["session_id"] ?? null)
          || ($result["session_id"] ?? "") === "") {
          fwrite(STDERR, "resultado real inválido em {$mode}\n");
          exit(1);
      }
      $requested = $result["requested_model"] ?? null;
      $effective = $result["effective_model"] ?? null;
      if ($effective !== null && $requested !== null) {
          $normalize = static function (?string $value): string {
              $value = strtolower(trim((string) $value));
              $value = preg_replace("/[_-]+/", " ", $value) ?? $value;
              return preg_replace("/\\s+/", " ", $value) ?? $value;
          };
          if ($normalize($effective) !== $normalize($requested)) {
              fwrite(STDERR, "modelo divergente em {$mode}\n");
              exit(1);
          }
      }
  }
  if (($verify["permission_policy_status"] ?? null) !== "declared"
      || ($verify["permission_policy_hash"] ?? null) !== null
      || ($verify["verification_agent"] ?? null) !== "ask") {
      fwrite(STDERR, "política declarada de verify inválida\n");
      exit(1);
  }
  if (($impl["permission_policy_status"] ?? null) !== "not_required") {
      fwrite(STDERR, "política de impl inválida\n");
      exit(1);
  }
  echo json_encode([
      "status" => "passed",
      "runner" => "cursor",
      "runner_version" => $verify["runner_version"] ?? null,
      "requested_model" => $verify["requested_model"] ?? null,
      "effective_model" => $verify["effective_model"] ?? null,
      "impl" => [
          "schema_version" => $impl["schema_version"],
          "terminal_event" => $impl["terminal_event"],
          "events_seen" => $impl["events_seen"],
          "tree_unchanged" => true,
      ],
      "verify" => [
          "schema_version" => $verify["schema_version"],
          "terminal_event" => $verify["terminal_event"],
          "events_seen" => $verify["events_seen"],
          "permission_policy_status" => $verify["permission_policy_status"],
          "verification_agent" => $verify["verification_agent"],
          "tree_unchanged" => true,
      ],
  ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE)."\n";
'
