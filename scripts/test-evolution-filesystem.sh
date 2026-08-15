#!/usr/bin/env bash

# Regressão de resiliência a falha de filesystem na evolução assistida
# (roadmap 0.8.0): SIGKILL real durante o rename de publicação e espaço
# insuficiente / rename falhando no destino.
#
# Cobre: evolve -> quarentena -> installing (rename via commitStagedFiles) ->
# rollback restaurando a árvore legada, mesmo com interrupção por SIGKILL no
# meio da publicação ou falha de escrita no destino.
#
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-evolution-fs.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

new_project() {
  local project="$1"
  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" config user.email ralph-method@example.invalid
  git -C "$project" config user.name 'Ralph Method Evolution FS Test'
  printf '%s\n' '# Projeto fixture' > "$project/README.md"
  git -C "$project" add README.md
  git -C "$project" commit -qm base
}

# Monta um projeto com a assinatura bc-harness legada (harness/ralph), como os
# demais testes de evolução. <dir> recebe o caminho; <legacy_mode> controla a
# permissão de escrita no destino (0 = normal, 1 = destino read-only).
setup_legacy() {
  local project="$1" legacy_mode="$2"
  new_project "$project"
  mkdir -p "$project/harness" "$project/shared"
  cp -R "$ROOT/tests/fixtures/bc-harness-legacy/harness/ralph" "$project/harness/"
  mkdir -p "$project/harness/ralph/nested"
  printf '%s\n' 'conteúdo aninhado' > "$project/harness/ralph/nested/member.txt"
  printf '%s\n' 'alvo interno' > "$project/shared/target.txt"
  ln -s ../../shared/target.txt "$project/harness/ralph/internal-link"
  chmod 0750 "$project/harness/ralph"
  chmod 0710 "$project/harness/ralph/nested"
  chmod 0701 "$project/harness/ralph/nested/member.txt"
  git -C "$project" add -A
  git -C "$project" commit -qm "fixture legada"
  if [ "$legacy_mode" = 1 ]; then
    # Falha de filesystem no destino: bin/ fica read-only ANTES do evolve, de
    # modo que o rename de publicação (staging -> bin/ralph-control) falhe.
    mkdir -p "$project/bin"
    chmod 0555 "$project/bin"
  fi
}

# ── Cenário 1: SIGKILL durante o rename de publicação (installing). ──────────
proj_kill="$TMP/proj-kill"
setup_legacy "$proj_kill" 0

kill_out="$TMP/kill.log"
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$proj_kill" --apply --provider auto >"$kill_out" 2>&1 &
kill_pid=$!
kill_state=""
kill_done=0
for _ in $(seq 1 2000); do
  if ! kill -STOP "$kill_pid" 2>/dev/null; then
    break
  fi
  # Detecta a fase installing (publicação via rename de staging -> destino).
  kill_state="$(find "$proj_kill/.ralph/evolutions" -name evolution.json -print -quit 2>/dev/null || true)"
  if [ -n "$kill_state" ] && KILL_STATE="$kill_state" php -r '
      $state = json_decode(file_get_contents(getenv("KILL_STATE")), true, 512, JSON_THROW_ON_ERROR);
      if (($state["status"] ?? null) === "installing") { exit(0); }
      exit(1);
  ' 2>/dev/null; then
    if kill -0 "$kill_pid" 2>/dev/null; then
      kill -KILL "$kill_pid" 2>/dev/null || true
      wait "$kill_pid" 2>/dev/null || true
      kill_done=1
      break
    fi
  fi
  kill -CONT "$kill_pid" 2>/dev/null || true
  sleep 0.001
  if ! kill -0 "$kill_pid" 2>/dev/null; then
    break
  fi
done
if [ "$kill_done" -ne 1 ]; then
  kill -KILL "$kill_pid" 2>/dev/null || true
  wait "$kill_pid" 2>/dev/null || true
  fail 'não foi possível interromper o processo durante a publicação (installing)'
fi
[ -n "$kill_state" ] || fail 'a interrupção não deixou estado de evolução persistido'
kill_id="$(basename "$(dirname "$kill_state")")"

# O rollback reconstrói a árvore legada mesmo com a publicação interrompida.
kill_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$proj_kill" --evolution "$kill_id")"
KILL_PLAN="$kill_plan" php -r '
    $plan = json_decode(getenv("KILL_PLAN"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["status"] ?? null) === "ready"
        && ($plan["rollback_allowed"] ?? false) === true ? 0 : 1);
' || fail 'rollback não autorizado após SIGKILL na publicação'
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$proj_kill" --evolution "$kill_id" --apply >/dev/null
assert_file() { [ -f "$1" ] || fail "arquivo ausente após rollback: $1"; }
assert_file "$proj_kill/harness/ralph/nested/member.txt"
assert_file "$proj_kill/harness/ralph/install.sh"
[ "$(readlink "$proj_kill/harness/ralph/internal-link")" = '../../shared/target.txt' ] \
  || fail 'SIGKILL na publicação quebrou o symlink interno restaurado'
assert_file "$proj_kill/shared/target.txt"
[ ! -e "$proj_kill/.ralph/install-manifest.json" ] || fail 'rollback pós-SIGKILL deixou instalação nova'

# ── Cenário 2: rename de publicação falhando (destino read-only = espaço
#    insuficiente / falha de filesystem). ────────────────────────────────────
proj_fs="$TMP/proj-fs"
setup_legacy "$proj_fs" 1

fs_out="$TMP/fs.log"
fs_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$proj_fs" --apply --provider auto >"$fs_out" 2>&1 || fs_exit=$?
[ "$fs_exit" -ne 0 ] || fail 'evolve não falhou com destino de publicação read-only'
FS_OUT="$fs_out" php -r '
    $text = file_get_contents(getenv("FS_OUT"));
    exit(str_contains($text, "evolução não concluída") ? 0 : 1);
' || fail 'evolve não reportou falha de filesystem ao publicar'

# O estado fica recovery_required; o rollback restaura a árvore legada.
fs_state="$(find "$proj_fs/.ralph/evolutions" -name evolution.json -print -quit 2>/dev/null || true)"
[ -n "$fs_state" ] || fail 'falha de filesystem não persistiu estado de evolução'
fs_id="$(basename "$(dirname "$fs_state")")"
FS_STATE="$fs_state" php -r '
    $state = json_decode(file_get_contents(getenv("FS_STATE")), true, 512, JSON_THROW_ON_ERROR);
    exit(in_array($state["status"] ?? null, ["recovery_required", "quarantine_in_progress"], true) ? 0 : 1);
' || fail 'estado pós-falha de filesystem não é recovery_required/quarantine'

# Restaura a permissão para o rollback conseguir repor o backup no destino.
chmod 0755 "$proj_fs/bin" 2>/dev/null || true
fs_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$proj_fs" --evolution "$fs_id")"
FS_PLAN="$fs_plan" php -r '
    $plan = json_decode(getenv("FS_PLAN"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["status"] ?? null) === "ready"
        && ($plan["rollback_allowed"] ?? false) === true ? 0 : 1);
' || fail 'rollback não autorizado após falha de filesystem'
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$proj_fs" --evolution "$fs_id" --apply >/dev/null
assert_file "$proj_fs/harness/ralph/nested/member.txt"
assert_file "$proj_fs/harness/ralph/install.sh"
assert_file "$proj_fs/shared/target.txt"
[ ! -e "$proj_fs/.ralph/install-manifest.json" ] || fail 'rollback pós-falha de filesystem deixou instalação nova'

printf '%s\n' 'OK: evolução resiste a SIGKILL durante o rename de publicação e a falha de filesystem no destino (rollback restaura).'
