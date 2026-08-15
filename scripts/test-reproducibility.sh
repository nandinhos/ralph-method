#!/usr/bin/env bash

# Os blocos PHP recebem JSON por variáveis de ambiente; não há expansão shell
# intencional dentro das expressões delimitadas por aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-reproducibility.XXXXXX")"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "arquivo ausente: $1"
}

assert_not_exists() {
  [ ! -e "$1" ] || fail "caminho deveria estar ausente: $1"
}

SOURCE="$TMP/method-source"
PROJECT="$TMP/projeto-independente"
mkdir -p "$SOURCE" "$PROJECT"

# A instalação deve funcionar a partir de um bundle Git sem metadados, sem o
# checkout de desenvolvimento e sem depender de outro projeto. A base vem de
# HEAD; o overlay inclui somente mudanças versionáveis do checkout para que o
# teste exercite a fonte atual antes do commit. Em árvore limpa, o overlay é
# vazio e o bundle equivale ao archive.
git -C "$ROOT" archive --format=tar HEAD | tar -x -C "$SOURCE"
while IFS= read -r -d '' deleted; do
  rm -f -- "$SOURCE/$deleted"
done < <(git -C "$ROOT" diff --name-only -z --diff-filter=D HEAD)
(
  cd "$ROOT"
  {
    git diff --name-only -z --diff-filter=ACMRTUXB HEAD
    git ls-files --others --exclude-standard -z
  } | tar --null -T - -cf -
) | tar -x -C "$SOURCE"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$SOURCE/VERSION")"

# Excluímos testes/checkers: eles podem citar o projeto de origem como parte
# da própria asserção histórica. A fronteira auditada é o runtime instalado.
runtime_files=()
while IFS= read -r -d '' file; do
  runtime_files+=("$file")
done < <(find "$SOURCE/bin" "$SOURCE/adapters" "$SOURCE/schemas" -type f -print0)
while IFS= read -r -d '' file; do
  runtime_files+=("$file")
done < <(find "$SOURCE/scripts" -type f -name '*.sh' ! -name 'test-*' ! -name 'check-*' -print0)

if grep -n -i 'refactor-radar' "${runtime_files[@]}" >/dev/null 2>&1; then
  fail 'runtime do bundle contém dependência textual do refactor-radar'
fi

git -C "$PROJECT" init -q
git -C "$PROJECT" config user.email ralph-method@example.invalid
git -C "$PROJECT" config user.name 'Ralph Method Reproducibility'
printf '%s\n' '# Projeto independente' > "$PROJECT/README.md"
git -C "$PROJECT" add README.md
git -C "$PROJECT" commit -qm base

plan="$(RALPH_METHOD_SOURCE="$SOURCE" "$SOURCE/bin/ralph-init" plan --project "$PROJECT" --provider auto)"
PLAN_JSON="$plan" EXPECTED_VERSION="$EXPECTED_VERSION" php -r '
    $plan = json_decode(getenv("PLAN_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["method_version"] ?? null) === getenv("EXPECTED_VERSION") && ($plan["project"]["root"] ?? null) !== null ? 0 : 1);
'

RALPH_METHOD_SOURCE="$SOURCE" "$SOURCE/bin/ralph-init" apply --project "$PROJECT" --provider auto >/dev/null
RALPH_METHOD_SOURCE="$SOURCE" "$SOURCE/bin/ralph-init" apply --project "$PROJECT" --provider auto >/dev/null
assert_file "$PROJECT/.ralph/install-manifest.json"
assert_file "$PROJECT/bin/ralph-control"
assert_file "$PROJECT/bin/ralph-init"
assert_file "$PROJECT/bin/ralph-metrics"
assert_file "$PROJECT/adapters/opencode/runner.sh"
assert_file "$PROJECT/adapters/agy/runner.sh"
assert_file "$PROJECT/.agents/agents/ralph-review/agent.md"
assert_file "$PROJECT/schemas/knowledge-candidate.schema.json"
assert_file "$PROJECT/scripts/ralph.sh"
assert_file "$PROJECT/.ralph/codex.env"
assert_file "$PROJECT/.ralph/claude.env"
assert_file "$PROJECT/.ralph/opencode.env"
assert_file "$PROJECT/.ralph/agy.env"

doctor="$(RALPH_METHOD_SOURCE="$SOURCE" "$SOURCE/bin/ralph-init" doctor --project "$PROJECT")"
DOCTOR_JSON="$doctor" php -r '
    $doctor = json_decode(getenv("DOCTOR_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($doctor["status"] ?? null) === "healthy" ? 0 : 1);
'

RALPH_METHOD_SOURCE="$SOURCE" "$SOURCE/bin/ralph-init" uninstall --project "$PROJECT" --apply >/dev/null
assert_not_exists "$PROJECT/.ralph/install-manifest.json"
assert_not_exists "$PROJECT/bin/ralph-control"
assert_not_exists "$PROJECT/adapters/opencode/runner.sh"
assert_not_exists "$PROJECT/adapters/agy/runner.sh"
assert_not_exists "$PROJECT/.agents/agents/ralph-review/agent.md"
assert_file "$PROJECT/README.md"

# O relatório de uninstall é uma evidência e o lock é um controle local
# deliberadamente preservados pelo contrato. Nenhum outro arquivo pode
# permanecer fora do controle do Git.
assert_file "$PROJECT/.ralph/uninstall-report.json"
assert_file "$PROJECT/.ralph/install.lock"
if [ "$(git -C "$PROJECT" status --porcelain)" != '?? .ralph/' ]; then
  fail 'projeto independente deixou alteração além do relatório de uninstall'
fi
if find "$PROJECT/.ralph" -mindepth 1 -maxdepth 1 ! -name uninstall-report.json ! -name install.lock -print -quit | grep -q .; then
  fail 'projeto independente deixou artefato inesperado no .ralph'
fi

printf 'OK: bundle Git reproduzido em projeto independente; plan/apply idempotente/doctor/uninstall e limpeza passaram.\n'
