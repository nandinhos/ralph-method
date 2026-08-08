#!/usr/bin/env bash

# Os blocos Python/PHP são literais; não há expansão shell dentro deles.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-opencode-field.XXXXXX")"
FIXTURE="$TMP/fixture"
REFERENCE="$TMP/reference"
OUTPUT="$TMP/controller-output.log"
MODEL="${RALPH_OPENCODE_MODEL:-opencode/deepseek-v4-flash-free}"
NONCE="nonce-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"

cleanup() {
  if [ "${RALPH_KEEP_FIELD_FIXTURE:-0}" != 1 ]; then
    rm -rf "$TMP"
  else
    echo "fixture preservada em: $TMP" >&2
  fi
}
trap cleanup EXIT

fail() {
  echo "FALHA: $1" >&2
  [ -f "$OUTPUT" ] && tail -n 80 "$OUTPUT" >&2
  exit 1
}

mkdir -p "$FIXTURE/.spec" "$REFERENCE"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" config user.email ralph-method@example.invalid
git -C "$FIXTURE" config user.name 'Ralph Method OpenCode Field'

printf '%s\n' '# Fixture de capacidade OpenCode' 'Este arquivo é protegido pelo oráculo externo.' > "$FIXTURE/README.md"
printf '%s\n' '{"id":"T-001","title":"Fundação","status":"done","priority":"critical","estimate_hours":3,"tags":["backend","core"],"dependencies":[]}' '{"id":"T-002","title":"API","status":"in_progress","priority":"high","estimate_hours":5,"tags":["backend","api"],"dependencies":["T-001"]}' '{"id":"T-003","title":"Interface","status":"todo","priority":"medium","estimate_hours":4,"tags":["frontend","ux"],"dependencies":["T-001"]}' '{"id":"T-004","title":"Testes","status":"in_progress","priority":"high","estimate_hours":6,"tags":["quality","backend"],"dependencies":["T-002"]}' '{"id":"T-005","title":"Documentação","status":"todo","priority":"low","estimate_hours":2,"tags":["docs"],"dependencies":["T-001"]}' '{"id":"T-006","title":"Deploy","status":"blocked","priority":"critical","estimate_hours":3,"tags":["ops","release"],"dependencies":["T-004","T-005"]}' '{"id":"T-007","title":"Analytics","status":"done","priority":"medium","estimate_hours":2.5,"tags":["data","backend"],"dependencies":["T-002"]}' '{"id":"T-008","title":"Acabamento","status":"todo","priority":"low","estimate_hours":1.5,"tags":["frontend","ux"],"dependencies":["T-003","T-007"]}' | python3 -c 'import json,sys; print(json.dumps([json.loads(line) for line in sys.stdin], separators=(",",":")))' > "$FIXTURE/tasks.json"
printf '%s\n' '{"id":"T-001","title":"Duplicado A","status":"todo","priority":"low","estimate_hours":1,"tags":[],"dependencies":[]}' '{"id":"T-001","title":"Duplicado B","status":"todo","priority":"low","estimate_hours":1,"tags":[],"dependencies":[]}' | python3 -c 'import json,sys; print(json.dumps([json.loads(line) for line in sys.stdin], separators=(",",":")))' > "$FIXTURE/duplicate.json"
printf '%s\n' '{"id":"T-001","title":"Dependência ausente","status":"todo","priority":"low","estimate_hours":1,"tags":[],"dependencies":["T-999"]}' > "$FIXTURE/unknown-dependency.json"
printf '%s\n' '{"id":"T-001","title":"Ciclo A","status":"todo","priority":"low","estimate_hours":1,"tags":[],"dependencies":["T-002"]}' '{"id":"T-002","title":"Ciclo B","status":"todo","priority":"low","estimate_hours":1,"tags":[],"dependencies":["T-001"]}' | python3 -c 'import json,sys; print(json.dumps([json.loads(line) for line in sys.stdin], separators=(",",":")))' > "$FIXTURE/cycle.json"
printf '%s\n' '{"id":"T-001","title":"Status inválido","status":"paused","priority":"low","estimate_hours":1,"tags":[],"dependencies":[]}' > "$FIXTURE/invalid-status.json"

for input in tasks.json duplicate.json unknown-dependency.json cycle.json invalid-status.json; do
  sha256sum "$FIXTURE/$input" | awk '{print $1}' > "$REFERENCE/$input.sha256"
done
sha256sum "$FIXTURE/README.md" | awk '{print $1}' > "$REFERENCE/README.sha256"

printf '%s\n' \
  '{"schema_version":"1.0.0","workflow_id":"wf_opencode_complex","plan_file":".spec/project-phases.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-OPENCODE-COMPLEX","title":"Relatório determinístico de tarefas","position":1}]}' \
  > "$FIXTURE/workflow.json"

printf '%s\n' \
  '# Plano de teste de campo OpenCode' \
  '' \
  '## Phase 1: Relatório determinístico de tarefas' \
  '' \
  '- [ ] Implemente `task_report.py` usando somente a biblioteca padrão do Python.' \
  '- [ ] Leia `tasks.json` e produza `report.json` com schema_version 1.0.0, o nonce abaixo, resumo por status e prioridade, soma de estimativas, contagens de tags e ordem topológica determinística.' \
  '- [ ] A CLI deve aceitar `python task_report.py INPUT OUTPUT --nonce VALUE`.' \
  '- [ ] Rejeite IDs duplicados com código `duplicate_id`, dependência desconhecida com `unknown_dependency`, ciclos com `cycle_detected` e status inválido com `invalid_status`.' \
  '- [ ] Ordene chaves e resultados de forma estável e não altere README.md nem qualquer arquivo JSON de entrada.' \
  "- [ ] O nonce obrigatório desta execução é: $NONCE" \
  '' \
  'A validação final é externa ao checkout. Não crie nem altere scripts de validação, hashes ou referências fora da feature.' \
  > "$FIXTURE/.spec/project-phases.md"

git -C "$FIXTURE" add .
git -C "$FIXTURE" commit -qm 'base da fixture complexa OpenCode'

(cd "$FIXTURE" && php "$ROOT/bin/ralph-control" init --workflow wf_opencode_complex --manifest workflow.json >/dev/null)
claim="$(cd "$FIXTURE" && php "$ROOT/bin/ralph-control" claim --workflow wf_opencode_complex --feature FEATURE-OPENCODE-COMPLEX --actor field-test)"
lease="$(CLAIM="$claim" php -r '$v=json_decode(getenv("CLAIM"), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"];')"
[ -n "$lease" ] || fail 'lease não foi adquirido'

test_command="$ROOT/scripts/opencode-field-check.sh $FIXTURE $NONCE $REFERENCE"
printf -v controlled_command '%q ' "$ROOT/scripts/ralph.sh" --engine opencode --test-cmd "$test_command" --no-verify "$FIXTURE/.spec/project-phases.md"

started_at="$(date +%s)"
set +e
(cd "$FIXTURE" && \
  RALPH_OPENCODE_MODEL="$MODEL" \
  RALPH_OPENCODE_AUTO=1 \
  RALPH_OPENCODE_PURE=1 \
  RALPH_OPENCODE_TIMEOUT=1200 \
  RALPH_CAPTURE_MAX_BYTES=5242880 \
  RALPH_PROCESS_NAMESPACE=1 \
  RALPH_HOOK="$ROOT/scripts/ralph-hook.sh" \
  RALPH_FEEDBACK_STDOUT=1 \
  php "$ROOT/bin/ralph-control" run --workflow wf_opencode_complex --feature FEATURE-OPENCODE-COMPLEX --lease "$lease" --command "$controlled_command") > "$OUTPUT" 2>&1
run_rc=$?
set -e
finished_at="$(date +%s)"
[ "$run_rc" -eq 0 ] || fail "execução controlada terminou com exit $run_rc"
grep -R -q 'FEATURE_CHECK_OK' "$FIXTURE/.phases/logs" || fail 'oráculo externo não ficou verde'

(cd "$FIXTURE" && php "$ROOT/bin/ralph-control" status > "$TMP/status.json")
(cd "$FIXTURE" && php "$ROOT/bin/ralph-control" trace-report --workflow wf_opencode_complex --format json --output "$TMP/trace.json" > /dev/null)

STATUS_FILE="$TMP/status.json" TRACE_FILE="$TMP/trace.json" php -r '
  $status = json_decode(file_get_contents(getenv("STATUS_FILE")), true, 512, JSON_THROW_ON_ERROR);
  $trace = json_decode(file_get_contents(getenv("TRACE_FILE")), true, 512, JSON_THROW_ON_ERROR);
  $feature = $status["projection"]["features"][0] ?? [];
  $delegations = $feature["delegations"] ?? [];
  $found = false;
  foreach ($delegations as $delegation) {
      if (($delegation["runner"] ?? null) === "opencode" && ($delegation["status"] ?? null) === "completed" && ($delegation["session_id"] ?? null)) {
          $found = true;
      }
  }
  if (!$found || ($trace["delegation_count"] ?? 0) < 1 || ($feature["state"] ?? null) !== "awaiting_gates") {
      exit(1);
  }
'

printf '| Etapa | Resultado | Duração | Evidência |\n'
printf '|---|---|---:|---|\n'
printf '| Preflight + fixture | verde | — | input e oráculo externos preparados |\n'
printf '| Ralph + adapter OpenCode | verde | %ss | controller-output.log |\n' "$((finished_at - started_at))"
printf '| Feature complexa | verde | incluída no bloco | FEATURE_CHECK_OK |\n'
printf '| Trace | verde | — | sessão OpenCode importada pelo ralph-control |\n'
printf '| Capacidade | verde | — | limite de captura: 5242880 bytes |\n'
printf '| Processo | verde | — | contenção solicitada: pid_namespace |\n'
printf 'FIELD_TEST_OK\n'
printf 'REPORT_DIR=%s\n' "$TMP"
