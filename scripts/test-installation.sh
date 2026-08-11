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
    if (($plan["ralph_installation"]["external"]["status"] ?? null) !== "not_found"
        || ($plan["ralph_installation"]["external"]["apply_allowed"] ?? false) !== true) {
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
assert_file "$project/schemas/ralph-installation-detection.schema.json"
assert_file "$project/schemas/ralph-evolution.schema.json"
assert_file "$project/.ralph/opencode.env"
assert_file "$project/schemas/provider-readiness.schema.json"

dry_output="$(cd "$project" && RALPH_DRY_RUN=1 bin/ralph-bloco 1 1 codex)"
printf '%s\n' "$dry_output" | grep -q 'ralph.*scripts/ralph.sh' || fail 'perfil instalado não aponta para o loop local'

doctor_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" doctor --project "$project")"
DOCTOR_JSON="$doctor_output" php -r '
    $doctor = json_decode(getenv("DOCTOR_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($doctor["status"] ?? null) === "healthy"
        && ($doctor["ralph_installation"]["method"]["status"] ?? null) === "managed"
        && ($doctor["ralph_installation"]["external"]["status"] ?? null) === "not_found" ? 0 : 1);
'

# O manifesto válido não transforma um marcador externo posterior em arquivo
# pertencente ao método: a coexistência também exige revisão.
printf '%s\n' '# Ralph de outra origem' > "$project/ralph.sh"
managed_external_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$project")"
MANAGED_EXTERNAL_JSON="$managed_external_plan" php -r '
    $plan = json_decode(getenv("MANAGED_EXTERNAL_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["ralph_installation"]["method"]["status"] ?? null) === "managed"
        && ($plan["ralph_installation"]["external"]["status"] ?? null) === "detected"
        && ($plan["ralph_installation"]["external"]["apply_allowed"] ?? true) === false ? 0 : 1);
'
managed_external_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$project" --provider auto >/dev/null 2>&1 || managed_external_exit=$?
[ "$managed_external_exit" -eq 3 ] || fail "marcador externo posterior não bloqueou apply"
rm "$project/ralph.sh"

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

# Uma instalação Ralph externa é inventariada sem ler ou copiar conteúdo e
# bloqueia o apply comum para exigir uma evolução explícita.
external_project="$TMP/ralph-externo"
new_project "$external_project"
printf '%s\n' '#!/usr/bin/env bash' 'echo legacy-ralph' > "$external_project/ralph.sh"
printf '%s\n' '# Ralph legado' > "$external_project/Ralphfile"
chmod +x "$external_project/ralph.sh"
external_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$external_project")"
EXTERNAL_JSON="$external_plan" php -r '
    $plan = json_decode(getenv("EXTERNAL_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $installation = $plan["ralph_installation"] ?? [];
    $external = $installation["external"] ?? [];
    if (($installation["method"]["status"] ?? null) !== "not_installed"
        || ($external["status"] ?? null) !== "detected"
        || ($external["classification"] ?? null) !== "external_ralph"
        || ($external["confidence"] ?? null) !== "high"
        || ($external["apply_allowed"] ?? true) !== false
        || ($external["migration_supported"] ?? true) !== false) {
        exit(1);
    }
    foreach ($external["signals"] ?? [] as $signal) {
        if (str_starts_with((string) ($signal["path"] ?? ""), "/")
            || isset($signal["content"])
            || ! preg_match("/^[a-f0-9]{64}$/", (string) ($signal["sha256"] ?? ""))) {
            exit(1);
        }
    }
'

external_apply_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$external_project" --provider auto >/dev/null 2>&1 || external_apply_exit=$?
[ "$external_apply_exit" -eq 3 ] || fail "Ralph externo não bloqueou apply com exit 3"
assert_file "$external_project/ralph.sh"
assert_file "$external_project/Ralphfile"
assert_not_file "$external_project/.ralph/install-manifest.json"
external_doctor="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" doctor --project "$external_project")"
EXTERNAL_DOCTOR_JSON="$external_doctor" php -r '
    $doctor = json_decode(getenv("EXTERNAL_DOCTOR_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($doctor["status"] ?? null) === "external_ralph_detected"
        && ($doctor["ralph_installation"]["external"]["status"] ?? null) === "detected" ? 0 : 1);
'

# Manifesto presente, mas inválido ou de outra origem, também bloqueia e fica
# visível como instalação inválida em vez de falhar sem diagnóstico.
invalid_project="$TMP/ralph-manifesto-invalido"
new_project "$invalid_project"
mkdir -p "$invalid_project/.ralph"
printf '%s\n' '{"origem":"ralph-legado"}' > "$invalid_project/.ralph/install-manifest.json"
invalid_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$invalid_project")"
INVALID_JSON="$invalid_plan" php -r '
    $plan = json_decode(getenv("INVALID_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["ralph_installation"]["method"]["status"] ?? null) === "invalid"
        && ($plan["ralph_installation"]["external"]["status"] ?? null) === "detected"
        && ($plan["ralph_installation"]["external"]["apply_allowed"] ?? true) === false ? 0 : 1);
'
invalid_apply_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$invalid_project" --provider auto >/dev/null 2>&1 || invalid_apply_exit=$?
[ "$invalid_apply_exit" -eq 3 ] || fail "manifesto inválido não bloqueou apply com exit 3"
invalid_doctor="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" doctor --project "$invalid_project")"
INVALID_DOCTOR_JSON="$invalid_doctor" php -r '
    $doctor = json_decode(getenv("INVALID_DOCTOR_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($doctor["status"] ?? null) === "invalid_installation"
        && ($doctor["ralph_installation"]["method"]["status"] ?? null) === "invalid" ? 0 : 1);
'

# Uma pasta .ralph sem marcador conhecido não é tratada como instalação Ralph.
neutral_project="$TMP/ralph-neutro"
new_project "$neutral_project"
mkdir -p "$neutral_project/.ralph"
printf '%s\n' 'configuração do projeto' > "$neutral_project/.ralph/project-notes.txt"
neutral_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$neutral_project")"
NEUTRAL_JSON="$neutral_plan" php -r '
    $plan = json_decode(getenv("NEUTRAL_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["ralph_installation"]["external"]["status"] ?? null) === "not_found"
        && ($plan["ralph_installation"]["external"]["apply_allowed"] ?? false) === true ? 0 : 1);
'

# A instalação legada real é reconhecida somente na raiz aprovada e expõe
# metadados sanitizados da árvore, sem importar conteúdo dos arquivos.
legacy_project="$TMP/ralph-legado-bc-harness"
new_project "$legacy_project"
mkdir -p "$legacy_project/harness/ralph"
printf '%s\n' '#!/usr/bin/env bash' 'echo install' > "$legacy_project/harness/ralph/install.sh"
printf '%s\n' '--- a/ralph.sh' '+++ b/ralph.sh' > "$legacy_project/harness/ralph/ralph.patch"
printf '%s\n' '#!/usr/bin/env bash' 'echo upstream' > "$legacy_project/harness/ralph/ralph.sh.upstream"
printf '%s\n' '# documentação legada' > "$legacy_project/harness/ralph/README.md"
legacy_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$legacy_project")"
legacy_plan_repeat="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$legacy_project")"
LEGACY_JSON="$legacy_plan" LEGACY_REPEAT_JSON="$legacy_plan_repeat" php -r '
    $plan = json_decode(getenv("LEGACY_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $repeat = json_decode(getenv("LEGACY_REPEAT_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $external = $plan["ralph_installation"]["external"] ?? [];
    $repeatExternal = $repeat["ralph_installation"]["external"] ?? [];
    if (($external["status"] ?? null) !== "detected"
        || ($external["classification"] ?? null) !== "external_ralph_legacy"
        || ($external["family"] ?? null) !== "bc-harness"
        || ! preg_match("/^bc_harness_[a-z0-9_]+$/", (string) ($external["signature_id"] ?? ""))
        || ($external["legacy_root"] ?? null) !== "harness/ralph"
        || ($external["legacy_type"] ?? null) !== "legacy_directory"
        || ($external["recommended_action"] ?? null) !== "evolve"
        || ($external["apply_allowed"] ?? true) !== false
        || ($external["migration_supported"] ?? true) !== false
        || ! preg_match("/^[a-f0-9]{64}$/", (string) ($external["tree_fingerprint"] ?? ""))
        || ($external["tree_fingerprint"] ?? null) !== ($repeatExternal["tree_fingerprint"] ?? null)
        || count($external["members"] ?? []) !== 4) {
        exit(1);
    }
    foreach ($external["members"] as $member) {
        if (! preg_match("/^[a-f0-9]{64}$/", (string) ($member["sha256"] ?? ""))
            || ! preg_match("/^(?!\\/)(?!.*\\.\\.)[^\\n]+$/", (string) ($member["path"] ?? ""))
            || ! preg_match("/^(?!\\/)(?!.*\\.\\.)[^\\n]+$/", (string) ($member["relative_path"] ?? ""))
            || ($member["type"] ?? null) !== "file"
            || isset($member["content"])) {
            exit(1);
        }
    }
    exit(0);
'
legacy_apply_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$legacy_project" --provider auto >/dev/null 2>&1 || legacy_apply_exit=$?
[ "$legacy_apply_exit" -eq 3 ] || fail 'instalação bc-harness legada não bloqueou apply'

# Caminhos parecidos dentro de dependências não fazem parte do escopo aprovado.
false_positive_project="$TMP/ralph-falso-positivo"
new_project "$false_positive_project"
for dependency_root in \
  "$false_positive_project/vendor/fake-package/harness/ralph" \
  "$false_positive_project/node_modules/fake-package/harness/ralph"; do
  mkdir -p "$dependency_root"
  printf '%s\n' 'install' > "$dependency_root/install.sh"
  printf '%s\n' 'patch' > "$dependency_root/ralph.patch"
  printf '%s\n' 'upstream' > "$dependency_root/ralph.sh.upstream"
done
false_positive_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$false_positive_project")"
FALSE_POSITIVE_JSON="$false_positive_plan" php -r '
    $plan = json_decode(getenv("FALSE_POSITIVE_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $external = $plan["ralph_installation"]["external"] ?? [];
    if (($external["status"] ?? null) !== "not_found"
        || ($external["classification"] ?? null) !== "none"
        || ($external["apply_allowed"] ?? false) !== true
        || ($external["legacy_candidates"] ?? []) !== []) {
        exit(1);
    }
    exit(0);
'

# Uma raiz aprovada incompleta aparece como candidata, mas não vira instalação.
candidate_project="$TMP/ralph-candidato-incompleto"
new_project "$candidate_project"
mkdir -p "$candidate_project/harness/ralph"
printf '%s\n' 'install' > "$candidate_project/harness/ralph/install.sh"
candidate_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$candidate_project")"
CANDIDATE_JSON="$candidate_plan" php -r '
    $plan = json_decode(getenv("CANDIDATE_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $external = $plan["ralph_installation"]["external"] ?? [];
    $candidate = $external["legacy_candidates"][0] ?? [];
    exit(($external["status"] ?? null) === "not_found"
        && ($external["classification"] ?? null) === "none"
        && ($external["apply_allowed"] ?? false) === true
        && ($candidate["path"] ?? null) === "harness/ralph"
        && ($candidate["status"] ?? null) === "candidate" ? 0 : 1);
'

# Uma raiz aprovada apontando para fora do projeto é rejeitada sem ser seguida.
symlink_project="$TMP/ralph-symlink-externo"
new_project "$symlink_project"
mkdir -p "$TMP/ralph-alvo-externo"
printf '%s\n' 'install' > "$TMP/ralph-alvo-externo/install.sh"
printf '%s\n' 'patch' > "$TMP/ralph-alvo-externo/ralph.patch"
printf '%s\n' 'upstream' > "$TMP/ralph-alvo-externo/ralph.sh.upstream"
mkdir -p "$symlink_project/harness"
ln -s "$TMP/ralph-alvo-externo" "$symlink_project/harness/ralph"
symlink_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$symlink_project")"
SYMLINK_JSON="$symlink_plan" php -r '
    $plan = json_decode(getenv("SYMLINK_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $external = $plan["ralph_installation"]["external"] ?? [];
    $candidate = $external["legacy_candidates"][0] ?? [];
    exit(($external["status"] ?? null) === "not_found"
        && ($external["apply_allowed"] ?? false) === true
        && ($candidate["status"] ?? null) === "rejected" ? 0 : 1);
'

# Um marcador genérico isolado é ambíguo, mas ainda bloqueia por segurança.
ambiguous_project="$TMP/ralph-ambiguo"
new_project "$ambiguous_project"
printf '%s\n' 'workflow: legado' > "$ambiguous_project/ralph.yml"
ambiguous_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" plan --project "$ambiguous_project")"
AMBIGUOUS_JSON="$ambiguous_plan" php -r '
    $plan = json_decode(getenv("AMBIGUOUS_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["ralph_installation"]["external"]["status"] ?? null) === "ambiguous"
        && ($plan["ralph_installation"]["external"]["classification"] ?? null) === "unknown_ralph_like"
        && ($plan["ralph_installation"]["external"]["apply_allowed"] ?? true) === false ? 0 : 1);
'
ambiguous_apply_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" apply --project "$ambiguous_project" --provider auto >/dev/null 2>&1 || ambiguous_apply_exit=$?
[ "$ambiguous_apply_exit" -eq 3 ] || fail "origem ambígua não bloqueou apply com exit 3"

# A evolução explícita isola os sinais externos, instala uma versão nova sem
# importar estado legado e deixa um manifesto persistente para rollback.
evolution_project="$TMP/ralph-evolucao"
new_project "$evolution_project"
printf '%s\n' '#!/usr/bin/env bash' 'echo ralph-legado' > "$evolution_project/ralph.sh"
printf '%s\n' '# Ralphfile legado' > "$evolution_project/Ralphfile"
chmod +x "$evolution_project/ralph.sh"
evolution_plan_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$evolution_project")"
EVOLUTION_PLAN_JSON="$evolution_plan_output" php -r '
    $plan = json_decode(getenv("EVOLUTION_PLAN_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["status"] ?? null) === "ready"
        && ($plan["migration"]["mode"] ?? null) === "quarantine_only"
        && ($plan["migration"]["state_imported"] ?? true) === false
        && count($plan["backup"]["signals_to_quarantine"] ?? []) === 2
        && ($plan["approval_required"] ?? false) === true ? 0 : 1);
'
evolution_apply_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$evolution_project" --apply --provider auto)"
EVOLUTION_APPLY_JSON="$evolution_apply_output" php -r '
    $result = json_decode(getenv("EVOLUTION_APPLY_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($result["status"] ?? null) === "awaiting_acceptance"
        && preg_match("/^EVL-[0-9]{8}-[0-9]{4}$/", (string) ($result["evolution_id"] ?? "")) === 1
        && ($result["migration"]["state_imported"] ?? true) === false ? 0 : 1);
'
evolution_id="$(EVOLUTION_APPLY_JSON="$evolution_apply_output" php -r '$result = json_decode(getenv("EVOLUTION_APPLY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $result["evolution_id"];')"
assert_not_file "$evolution_project/ralph.sh"
assert_not_file "$evolution_project/Ralphfile"
assert_file "$evolution_project/.ralph/install-manifest.json"
assert_file "$evolution_project/.ralph/evolutions/$evolution_id/backup/ralph.sh"
repeat_evolution_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$evolution_project" --apply --provider auto)"
REPEAT_EVOLUTION_JSON="$repeat_evolution_output" php -r '
    $result = json_decode(getenv("REPEAT_EVOLUTION_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($result["status"] ?? null) === "already_pending" ? 0 : 1);
'
rollback_plan_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$evolution_project" --evolution "$evolution_id")"
ROLLBACK_PLAN_JSON="$rollback_plan_output" php -r '
    $plan = json_decode(getenv("ROLLBACK_PLAN_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["status"] ?? null) === "ready" && ($plan["rollback_allowed"] ?? false) === true ? 0 : 1);
'
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$evolution_project" --evolution "$evolution_id" --apply >/dev/null
assert_file "$evolution_project/ralph.sh"
assert_file "$evolution_project/Ralphfile"
assert_not_file "$evolution_project/.ralph/install-manifest.json"
ROLLBACK_STATE_JSON="$(cat "$evolution_project/.ralph/evolutions/$evolution_id/evolution.json")" php -r '
    $state = json_decode(getenv("ROLLBACK_STATE_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($state["status"] ?? null) === "rolled_back"
        && (($state["backup"]["files"][0]["status"] ?? null) === "restored") ? 0 : 1);
'

# O aceite é explícito e não elimina o backup; uma alteração na instalação
# nova bloqueia rollback em vez de sobrescrever trabalho do usuário.
accept_project="$TMP/ralph-evolucao-aceite"
new_project "$accept_project"
printf '%s\n' '# Ralph externo para aceite' > "$accept_project/ralph.sh"
accept_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$accept_project" --apply --provider auto)"
accept_id="$(EVOLUTION_APPLY_JSON="$accept_output" php -r '$result = json_decode(getenv("EVOLUTION_APPLY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $result["evolution_id"];')"
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$accept_project" --evolution "$accept_id" --accept --apply >/dev/null
ACCEPT_STATE_JSON="$(cat "$accept_project/.ralph/evolutions/$accept_id/evolution.json")" php -r '
    $state = json_decode(getenv("ACCEPT_STATE_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($state["status"] ?? null) === "accepted" ? 0 : 1);
'
printf '%s\n' '# alteração após aceite' >> "$accept_project/bin/ralph-control"
drift_rollback_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$accept_project" --evolution "$accept_id" --apply >/dev/null 2>&1 || drift_rollback_exit=$?
[ "$drift_rollback_exit" -eq 3 ] || fail 'rollback não bloqueou drift após aceite'

# A evolução não pode seguir a raiz antiga se o checkout for movido.
moved_project="$TMP/ralph-evolucao-movido"
new_project "$moved_project"
printf '%s\n' '# Ralph externo movido' > "$moved_project/ralph.sh"
moved_apply_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$moved_project" --apply --provider auto)"
moved_id="$(EVOLUTION_APPLY_JSON="$moved_apply_output" php -r '$result = json_decode(getenv("EVOLUTION_APPLY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $result["evolution_id"];')"
moved_destination="$TMP/ralph-evolucao-movido-destino"
mv "$moved_project" "$moved_destination"
moved_rollback_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$moved_destination" --evolution "$moved_id")"
MOVED_ROLLBACK_JSON="$moved_rollback_plan" php -r '
    $plan = json_decode(getenv("MOVED_ROLLBACK_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["status"] ?? null) === "blocked"
        && ($plan["rollback_allowed"] ?? true) === false
        && isset($plan["root_mismatch"]) ? 0 : 1);
'
moved_rollback_exit=0
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$moved_destination" --evolution "$moved_id" --apply >/dev/null 2>&1 || moved_rollback_exit=$?
[ "$moved_rollback_exit" -eq 3 ] || fail 'rollback seguiu caminho antigo depois de mover o projeto'
assert_file "$moved_destination/.ralph/install-manifest.json"

# Ledger e workflow externos são preservados durante a evolução; não são
# importados nem movidos para o backup legado.
runtime_evolution_project="$TMP/ralph-evolucao-runtime"
new_project "$runtime_evolution_project"
printf '%s\n' '# Ralph externo' > "$runtime_evolution_project/ralph.sh"
mkdir -p "$runtime_evolution_project/.git/ralph-control"
printf '%s\n' '{"legacy":true}' > "$runtime_evolution_project/.git/ralph-control/events.jsonl"
printf '%s\n' '{"legacy":true}' > "$runtime_evolution_project/.git/ralph-control/workflow.json"
runtime_events_hash="$(php -r 'echo hash_file("sha256", $argv[1]);' "$runtime_evolution_project/.git/ralph-control/events.jsonl")"
runtime_evolution_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$runtime_evolution_project" --apply --provider auto)"
runtime_evolution_id="$(EVOLUTION_APPLY_JSON="$runtime_evolution_output" php -r '$result = json_decode(getenv("EVOLUTION_APPLY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $result["evolution_id"];')"
assert_file "$runtime_evolution_project/.git/ralph-control/events.jsonl"
assert_file "$runtime_evolution_project/.git/ralph-control/workflow.json"
runtime_events_after_hash="$(php -r 'echo hash_file("sha256", $argv[1]);' "$runtime_evolution_project/.git/ralph-control/events.jsonl")"
[ "$runtime_events_after_hash" = "$runtime_events_hash" ] || fail 'evolução alterou o ledger legado'
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$runtime_evolution_project" --evolution "$runtime_evolution_id" --apply >/dev/null
assert_file "$runtime_evolution_project/ralph.sh"
assert_file "$runtime_evolution_project/.git/ralph-control/events.jsonl"

# Simula crash depois da instalação nova, antes de persistir a lista de
# arquivos gerenciados. O rollback deve reconstruir essa lista pelo manifesto
# compatível e restaurar o legado sem assumir ownership indevido.
interrupted_project="$TMP/ralph-evolucao-interrompida"
new_project "$interrupted_project"
printf '%s\n' '# Ralph externo interrompido' > "$interrupted_project/ralph.sh"
interrupted_output="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" evolve --project "$interrupted_project" --apply --provider auto)"
interrupted_id="$(EVOLUTION_APPLY_JSON="$interrupted_output" php -r '$result = json_decode(getenv("EVOLUTION_APPLY_JSON"), true, 512, JSON_THROW_ON_ERROR); echo $result["evolution_id"];')"
interrupted_state="$interrupted_project/.ralph/evolutions/$interrupted_id/evolution.json"
EVOLUTION_STATE_PATH="$interrupted_state" php -r '
    $path = getenv("EVOLUTION_STATE_PATH");
    $state = json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
    $state["status"] = "installing";
    $state["installation"]["managed_files"] = [];
    file_put_contents($path, json_encode($state, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT)."\n");
'
interrupted_rollback_plan="$(RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$interrupted_project" --evolution "$interrupted_id")"
INTERRUPTED_ROLLBACK_JSON="$interrupted_rollback_plan" php -r '
    $plan = json_decode(getenv("INTERRUPTED_ROLLBACK_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit(($plan["status"] ?? null) === "ready"
        && count($plan["managed_files"] ?? []) > 1
        && ($plan["rollback_allowed"] ?? false) === true ? 0 : 1);
'
RALPH_METHOD_SOURCE="$ROOT" "$ROOT/bin/ralph-init" rollback --project "$interrupted_project" --evolution "$interrupted_id" --apply >/dev/null
assert_file "$interrupted_project/ralph.sh"
assert_not_file "$interrupted_project/.ralph/install-manifest.json"

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
