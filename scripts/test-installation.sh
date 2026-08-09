#!/usr/bin/env bash

# Os blocos PHP recebem JSON por variáveis de ambiente; não há expansão shell
# intencional dentro das expressões delimitadas por aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-install.XXXXXX")"
EXPECTED_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

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

assert_not_file() {
  [ ! -e "$1" ] || fail "arquivo deveria ter sido removido: $1"
}

new_project() {
  local project="$1"
  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" config user.email ralph-method@example.invalid
  git -C "$project" config user.name 'Ralph Method Test'
  printf '%s\n' '# Projeto fixture' > "$project/README.md"
  git -C "$project" add README.md
  git -C "$project" commit -qm base
}

init_output=""
project="$TMP/projeto"
new_project "$project"

init_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$project")"
INIT_JSON="$init_output" EXPECTED_VERSION="$EXPECTED_VERSION" php -r '
    $plan = json_decode(getenv("INIT_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $actions = array_column($plan["files"] ?? [], "action");
    if (($plan["method_version"] ?? null) !== getenv("EXPECTED_VERSION") || ! in_array("create", $actions, true)) {
        exit(1);
    }
'

RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$project" --provider auto >/dev/null
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$project" --provider auto >/dev/null
assert_file "$project/.ralph/install-manifest.json"
assert_file "$project/.ralph/method.json"
assert_file "$project/bin/ralph-control"
assert_file "$project/bin/ralph-init"
assert_file "$project/bin/ralph-metrics"
assert_file "$project/.ralph/codex.env"
assert_file "$project/.ralph/claude.env"
assert_file "$project/adapters/README.md"
assert_file "$project/adapters/opencode/runner.sh"
assert_file "$project/adapters/opencode/parser.php"
assert_file "$project/adapters/opencode/policy.php"
assert_file "$project/scripts/opencode-readonly-proof.sh"
assert_file "$project/.opencode/agents/ralph-review.md"
assert_file "$project/schemas/runner-result.schema.json"
assert_file "$project/schemas/readonly-policy-proof.schema.json"
assert_file "$project/schemas/knowledge-candidate.schema.json"
assert_file "$project/.ralph/opencode.env"
assert_file "$project/schemas/provider-readiness.schema.json"

dry_output="$(cd "$project" && RALPH_DRY_RUN=1 bin/ralph-bloco 1 1 codex)"
printf '%s\n' "$dry_output" | grep -q 'ralph.*scripts/ralph.sh' || fail 'perfil instalado não aponta para o loop local'

doctor_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" doctor --project "$project")"
DOCTOR_JSON="$doctor_output" php -r '
    $doctor = json_decode(getenv("DOCTOR_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($doctor["status"] ?? null) === "healthy" ? 0 : 1);
'

# Runtime, histórico e handoff são do projeto e sobrevivem à remoção do método.
mkdir -p "$project/.git/ralph-control" "$project/.ralph/handoffs" "$project/.ralph/reports"
printf '%s\n' '{"runtime":true}' > "$project/.git/ralph-control/events.jsonl"
printf '%s\n' '{"workflow":true}' > "$project/.git/ralph-control/workflow.json"

printf '%s\n' '# alteração do usuário' >> "$project/bin/ralph-trace"
printf '%s\n' '# política local do usuário' >> "$project/.ralph/codex.env"
uninstall_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" uninstall --project "$project")"
UNINSTALL_JSON="$uninstall_plan" php -r '
    $plan = json_decode(getenv("UNINSTALL_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $modified = array_values(array_filter($plan["files"] ?? [], static fn (array $file): bool => ($file["path"] ?? null) === "bin/ralph-trace"));
    exit(($modified[0]["action"] ?? null) === "preserve_modified" ? 0 : 1);
'

RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" uninstall --project "$project" --apply >/dev/null
assert_file "$project/bin/ralph-trace"
assert_not_file "$project/bin/ralph-control"
assert_not_file "$project/bin/ralph-init"
assert_file "$project/.ralph/codex.env"
assert_not_file "$project/.ralph/claude.env"
assert_not_file "$project/.opencode/agents/ralph-review.md"
assert_not_file "$project/.ralph/install-manifest.json"
assert_file "$project/.ralph/uninstall-report.json"
assert_file "$project/.git/ralph-control/events.jsonl"
assert_file "$project/.git/ralph-control/workflow.json"

# Um arquivo preexistente, ainda sem ownership no manifesto, nunca é sobrescrito.
conflict_project="$TMP/conflito"
new_project "$conflict_project"
mkdir -p "$conflict_project/bin"
printf '%s\n' '# arquivo do usuário' > "$conflict_project/bin/ralph-control"
mkdir -p "$conflict_project/.ralph"
printf '%s\n' '{"pertence":"ao usuário"}' > "$conflict_project/.ralph/method.json"
conflict_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$conflict_project")"
CONFLICT_JSON="$conflict_plan" php -r '
    $plan = json_decode(getenv("CONFLICT_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $foundGeneratedConflict = false;
    foreach ($plan["files"] ?? [] as $file) {
        if (($file["path"] ?? null) === "bin/ralph-control") {
            if (($file["action"] ?? null) !== "conflict") {
                exit(1);
            }
        }
        if (($file["path"] ?? null) === ".ralph/method.json") {
            $foundGeneratedConflict = ($file["action"] ?? null) === "conflict";
        }
    }
    exit($foundGeneratedConflict ? 0 : 1);
'

conflict_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$conflict_project" --provider auto >/dev/null 2>&1 || conflict_exit=$?
[ "$conflict_exit" -eq 3 ] || fail "conflito não interrompeu a instalação com exit 3"

# Falha durante o staging não publica arquivos parcialmente.
broken_source="$TMP/source-incompleto"
while IFS= read -r relative; do
  [ -n "$relative" ] || continue
  mkdir -p "$broken_source/$(dirname "$relative")"
  cp "$ROOT/$relative" "$broken_source/$relative"
done <<'EOF'
bin/ralph-control
bin/ralph-trace
bin/ralph-monitor
bin/ralph-block
bin/ralph-bloco
bin/ralph-knowledge
bin/ralph-metrics
bin/ralph-init
bin/ralph-doctor
scripts/ralph.sh
scripts/ralph-hook.sh
scripts/ralph-generate-handoff.sh
scripts/ralph-run-curator.sh
scripts/ralph-run-independent-gate.sh
scripts/ralph-run-quality.sh
scripts/ralph-run-runtime-evidence.sh
schemas/feedback-event.schema.json
schemas/provider-readiness.schema.json
schemas/knowledge-candidate.schema.json
adapters/README.md
EOF
rm "$broken_source/scripts/ralph-hook.sh"
broken_project="$TMP/staging-falho"
new_project "$broken_project"
broken_exit=0
RALPH_METHOD_SOURCE="$broken_source" "$ROOT/bin/ralph-init" apply --project "$broken_project" --provider auto >/dev/null 2>&1 || broken_exit=$?
[ "$broken_exit" -eq 4 ] || fail "falha de staging não retornou exit 4"
assert_not_file "$broken_project/bin/ralph-control"
assert_not_file "$broken_project/.ralph/install-manifest.json"
if find "$broken_project/.ralph" -maxdepth 1 -type d -name '.install-stage-*' -print -quit 2>/dev/null | grep -q .; then
  fail 'staging temporário ficou abandonado após rollback'
fi

printf 'OK: instalação, idempotência, ownership, desinstalação e preservação passaram.\n'
