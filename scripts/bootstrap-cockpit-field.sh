#!/usr/bin/env bash

# Bootstrap do checkout de campo do Trace Cockpit.
# Cria ou renova o worktree em /tmp/ralph-cockpit-field, inicializa o workflow
# executável (default: FEATURE-100 hero flow) e deixa o preflight pronto para
# Rodar Ralph no browser.
#
# Uso:
#   bash scripts/bootstrap-cockpit-field.sh
#   bash scripts/bootstrap-cockpit-field.sh --reset
#   bash scripts/bootstrap-cockpit-field.sh --fixture-099   # smoke de contrato (legado)
#
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIELD="${RALPH_COCKPIT_FIELD:-/tmp/ralph-cockpit-field}"
BRANCH="${RALPH_COCKPIT_BRANCH:-feat/trace-cockpit}"
FIXTURE="${RALPH_COCKPIT_FIXTURE:-100}"
RESET=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --reset) RESET=1; shift ;;
    --field) FIELD="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --fixture-099) FIXTURE=099; shift ;;
    --fixture-100) FIXTURE=100; shift ;;
    -h|--help)
      printf '%s\n' \
        'Uso: bash scripts/bootstrap-cockpit-field.sh [--reset] [--field PATH] [--branch NAME] [--fixture-099|--fixture-100]' \
        '' \
        'Fixtures:' \
        '  100 (default)  FEATURE-100 hero flow — campo Cursor + superfícies + browser' \
        '  099            smoke de contrato (manifesto/preflight/ingest mínimo)' \
        '' \
        'Variáveis:' \
        '  RALPH_COCKPIT_FIELD    destino do worktree (default: /tmp/ralph-cockpit-field)' \
        '  RALPH_COCKPIT_BRANCH   branch do worktree (default: feat/trace-cockpit)' \
        '  RALPH_COCKPIT_FIXTURE  100 ou 099 (default: 100)'
      exit 0
      ;;
    *) printf 'Argumento desconhecido: %s\n' "$1" >&2; exit 2 ;;
  esac
done

case "$FIXTURE" in
  100)
    WORKFLOW_ID="wf_trace_cockpit_hero"
    SPEC_DIR="100-trace-cockpit-hero"
    ;;
  099)
    WORKFLOW_ID="wf_cockpit_field"
    SPEC_DIR="099-cockpit-field"
    ;;
  *)
    printf 'FALHA: fixture inválida: %s (use 100 ou 099)\n' "$FIXTURE" >&2
    exit 2
    ;;
esac

MANIFEST=".spec/features/$SPEC_DIR/workflow.json"

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

resolve_cursor_cli() {
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

set_cursor_cli_in_profile() {
  local profile="$1"
  local cli="$2"
  [ -f "$profile" ] || return 0
  [ -n "$cli" ] || return 0
  if grep -q '^RALPH_CURSOR_CLI=' "$profile"; then
    sed -i "s|^RALPH_CURSOR_CLI=.*|RALPH_CURSOR_CLI=$cli|" "$profile"
  else
    printf '\nRALPH_CURSOR_CLI=%s\n' "$cli" >> "$profile"
  fi
}

control() {
  "$ROOT/bin/ralph-control" "$@"
}

if [ ! -f "$ROOT/$MANIFEST" ]; then
  fail "manifesto ausente: $ROOT/$MANIFEST"
fi

plan_file="$ROOT/.spec/features/$SPEC_DIR/plan.md"
if [ ! -f "$plan_file" ] && [ ! -f "$ROOT/.spec/features/$SPEC_DIR/PLAN.md" ]; then
  fail "plano ausente: .spec/features/$SPEC_DIR/plan.md ou PLAN.md"
fi

if git -C "$ROOT" rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  :
else
  fail "branch inexistente no repositório: $BRANCH"
fi

if [ -d "$FIELD/.git" ]; then
  printf 'Worktree existente em %s — atualizando checkout…\n' "$FIELD"
  git -C "$FIELD" checkout "$BRANCH" 2>/dev/null || git -C "$FIELD" checkout -B "$BRANCH"
  git -C "$FIELD" pull --ff-only origin "$BRANCH" 2>/dev/null || true
elif git -C "$ROOT" worktree list --porcelain | grep -q "^worktree $FIELD$"; then
  fail "diretório $FIELD existe mas não é worktree válido; remova ou use --field outro caminho"
else
  printf 'Criando worktree %s (branch %s)…\n' "$FIELD" "$BRANCH"
  git -C "$ROOT" worktree add "$FIELD" "$BRANCH"
fi

if [ "$RESET" -eq 1 ]; then
  printf 'Reset: descartando alterações locais e runtime do controlador…\n'
  git -C "$FIELD" reset --hard HEAD
  git -C "$FIELD" clean -fd
  rm -rf "$FIELD/.git/ralph-control"
fi

# Manifesto versionado (reaplica após reset).
spec_dest="$FIELD/.spec/features/$SPEC_DIR"
mkdir -p "$spec_dest"
for file in plan.md PHASES.md workflow.json PLAN.md; do
  if [ -f "$ROOT/.spec/features/$SPEC_DIR/$file" ]; then
    cp "$ROOT/.spec/features/$SPEC_DIR/$file" "$spec_dest/$file"
  fi
done

if [ -d "$ROOT/.ralph/knowledge-candidates" ]; then
  mkdir -p "$FIELD/.ralph/knowledge-candidates"
  cp -a "$ROOT/.ralph/knowledge-candidates/." "$FIELD/.ralph/knowledge-candidates/" 2>/dev/null || true
fi

if [ ! -d "$FIELD/.ralph" ]; then
  mkdir -p "$FIELD/.ralph"
fi

for profile in codex.env opencode.env cursor.env; do
  if [ -f "$ROOT/.ralph/$profile" ] && [ ! -f "$FIELD/.ralph/$profile" ]; then
    cp "$ROOT/.ralph/$profile" "$FIELD/.ralph/$profile"
  fi
done

# Perfil Cursor: sincroniza do método e aponta ralph.sh do repo (worktree pode estar atrás).
if [ -f "$ROOT/.ralph/cursor.env" ]; then
  cp "$ROOT/.ralph/cursor.env" "$FIELD/.ralph/cursor.env"
  if grep -q '^RALPH_BIN=' "$FIELD/.ralph/cursor.env"; then
    sed -i "s|^RALPH_BIN=.*|RALPH_BIN=$ROOT/scripts/ralph.sh|" "$FIELD/.ralph/cursor.env"
  else
    printf '\nRALPH_BIN=%s/scripts/ralph.sh\n' "$ROOT" >> "$FIELD/.ralph/cursor.env"
  fi
fi

cursor_cli="$(resolve_cursor_cli 2>/dev/null || true)"
if [ -n "$cursor_cli" ]; then
  set_cursor_cli_in_profile "$FIELD/.ralph/cursor.env" "$cursor_cli"
  set_cursor_cli_in_profile "$ROOT/.ralph/cursor.env" "$cursor_cli"
fi

# Sinal de harness Cursor (untracked no repo principal; necessário para --provider auto).
if [ -d "$ROOT/.cursor" ]; then
  mkdir -p "$FIELD/.cursor"
  rsync -a --delete \
    --exclude 'ralph-profile.local.json' \
    "$ROOT/.cursor/" "$FIELD/.cursor/"
fi

if ! git -C "$FIELD" diff --quiet || ! git -C "$FIELD" diff --cached --quiet; then
  untracked="$(git -C "$FIELD" status --porcelain \
    | grep -v "^?? .spec/features/$SPEC_DIR/" \
    | grep -v '^?? apps/' \
    | grep -v '^?? bin/check' \
    | grep -v '^?? scripts/bootstrap-cockpit-field.sh' \
    | grep -v '^?? scripts/test-cockpit-field-phase1.sh' \
    || true)"
  if [ -n "$untracked" ]; then
    fail "working tree suja em $FIELD — commit, descarte ou use --reset antes do bootstrap"
  fi
fi

init_output="$(cd "$FIELD" && control init --workflow "$WORKFLOW_ID" --manifest "$MANIFEST")"
[ -n "$init_output" ] || fail 'ralph-control init não devolveu saída'

# Instalação local: Cursor como primary_runner (self-hosting: worktree do próprio método).
method_json="$FIELD/.ralph/method.json"
method_version="$(tr -d '[:space:]' < "$ROOT/VERSION")"
installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
git_commit="$(git -C "$FIELD" rev-parse HEAD 2>/dev/null || echo '')"
git_branch="$(git -C "$FIELD" branch --show-current 2>/dev/null || echo '')"
FIELD="$FIELD" METHOD_VERSION="$method_version" INSTALLED_AT="$installed_at" \
GIT_COMMIT="$git_commit" GIT_BRANCH="$git_branch" php -r '
$field = getenv("FIELD");
$manifest = [
  "schema_version" => "1.0.0",
  "method_version" => getenv("METHOD_VERSION") ?: "0.0.0",
  "installed_at" => getenv("INSTALLED_AT") ?: gmdate("c"),
  "project" => [
    "root" => $field,
    "git" => [
      "commit" => getenv("GIT_COMMIT") ?: "",
      "branch" => getenv("GIT_BRANCH") ?: "",
    ],
  ],
  "orchestration" => [
    "mode" => "single_provider",
    "primary_runner" => "cursor",
    "fallback_policy" => "none",
  ],
  "components" => ["ralph-control", "ralph-monitor", "ralph-trace", "ralph-init"],
  "managed_files" => [],
];
$path = $field . "/.ralph/method.json";
file_put_contents($path, json_encode($manifest, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES) . "\n");
chmod($path, 0644);
'

# Preflight do cockpit exige git clean; artefatos de campo ficam fora do porcelain.
exclude_file="$FIELD/.git/info/exclude"
mkdir -p "$(dirname "$exclude_file")"
for pattern in \
  '.cursor/' \
  '.ralph/method.json' \
  '.ralph/cursor.env' \
  '.spec/features/099-cockpit-field/' \
  '.spec/features/100-trace-cockpit-hero/' \
  'apps/' \
  'bin/check' \
  'scripts/bootstrap-cockpit-field.sh' \
  'scripts/test-cockpit-field-phase1.sh' \
  ; do
  if ! grep -qxF "$pattern" "$exclude_file" 2>/dev/null; then
    printf '%s\n' "$pattern" >> "$exclude_file"
  fi
done

primary_runner='cursor'
if [ -f "$method_json" ]; then
  primary_runner="$(php -r 'echo json_decode(file_get_contents($argv[1]), true)["orchestration"]["primary_runner"] ?? "cursor";' "$method_json")"
fi

status_output="$(cd "$FIELD" && control status --workflow "$WORKFLOW_ID")"
cursor="$(printf '%s' "$status_output" | php -r '$j=json_decode(stream_get_contents(STDIN), true); echo $j["projection"]["cursor"] ?? "?";')"
state="$(printf '%s' "$status_output" | php -r '$j=json_decode(stream_get_contents(STDIN), true); $f=$j["projection"]["features"] ?? []; $c=$j["projection"]["cursor"] ?? null; foreach ($f as $row) { if (($row["feature_key"] ?? null)===$c) { echo $row["state"] ?? "?"; exit; } } echo "?";')"

printf '\nOK: checkout de campo pronto.\n'
printf '  worktree:  %s\n' "$FIELD"
printf '  workflow:  %s\n' "$WORKFLOW_ID"
printf '  cursor:    %s (%s)\n' "$cursor" "$state"
printf '  runner:    %s (primary_runner)\n' "$primary_runner"
printf '  failover:  cursor → opencode → codex (explicit_failover)\n'
printf '  fixture:   FEATURE-%s\n' "$FIXTURE"
printf '  manifesto: %s\n' "$MANIFEST"
printf '  plano:     .spec/features/%s/PLAN.md\n' "$SPEC_DIR"
printf '\nPróximos passos:\n'
printf '  1. apps/cockpit/.env → RALPH_PROJECT_ROOT=%s\n' "$FIELD"
printf '  2. cd apps/cockpit && php artisan ralph:ingest --rebuild && php artisan serve\n'
printf '  3. reverb:start + ralph:ingest --follow em terminais separados\n'
printf '  4. browser → Rodar Ralph (preflight verde) ou Diagnosticar se travado\n'
printf '  5. se agent status mostrar unauthenticated: agent login\n'
