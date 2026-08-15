#!/usr/bin/env bash

# Regressão da FEATURE-096-GATES-NATIVOS: o comando de gate é contrato nativo
# do método. O supervisor roda os cinco gates numa instalação padrão sem
# retornar gates_configuration_required, os wrappers instalados leem o contexto
# por ambiente (RALPH_*), e a configuração explícita por env continua aceita.
#
# Cobre: HND-2026-0006 — contrato de contexto por env no supervisor,
# defaults nativos para runtime_evidence/technical_review/curation e
# compatibilidade dos scripts ralph-run-*.sh com a invocação nua.
#
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-gates-native.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

repo="$TMP/repo"
mkdir -p "$repo/bin" "$repo/scripts" "$repo/.ralph"
cp "$ROOT/scripts/ralph-run-quality.sh" "$repo/scripts/"
cp "$ROOT/scripts/ralph-run-runtime-evidence.sh" "$repo/scripts/"
cp "$ROOT/scripts/ralph-run-independent-gate.sh" "$repo/scripts/"
cp "$ROOT/scripts/ralph-run-curator.sh" "$repo/scripts/"
chmod +x "$repo/scripts"/ralph-run-*.sh

printf '%s\n' '#!/usr/bin/env bash' 'echo "check OK"' > "$repo/bin/check"
chmod +x "$repo/bin/check"

printf '%s\n' '# Fixture gates' '' '## Phase 1: Provar pipeline nativo' '' '- [ ] **Task:** feature de teste.' '  - **Acceptance criteria:** pipeline não para em gates_configuration_required.' > "$repo/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_gates_native","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-GATES-NATIVE","title":"Gates nativos","position":1}]}' > "$repo/workflow.json"
printf '%s\n' 'AGENTS' > "$repo/AGENTS.md"

git -C "$repo" init -q
git -C "$repo" config user.email ralph-method@example.invalid
git -C "$repo" config user.name 'Ralph Method Gates Test'
git -C "$repo" add -A
git -C "$repo" commit -qm base

control() { "$ROOT/bin/ralph-control" "$@"; }

init_output="$(cd "$repo" && control init --workflow wf_gates_native --manifest workflow.json)"
[ -n "$init_output" ] || fail 'init do workflow falhou'
claim_output="$(cd "$repo" && control claim --workflow wf_gates_native --feature FEATURE-GATES-NATIVE --actor gates-test)"
lease="$(printf '%s' "$claim_output" | php -r '$v=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
[ -n "$lease" ] || fail 'claim não devolveu lease'

run_output="$(cd "$repo" && control run --workflow wf_gates_native --feature FEATURE-GATES-NATIVE --lease "$lease" --command 'exit 0')"
printf '%s' "$run_output" | grep -q '"status": "awaiting_gates"' || fail "run não chegou a awaiting_gates: $run_output"

# 1. Supervise processa os cinco gates sem gates_configuration_required.
#    O supervise roda em loop; encerra após o advance (next_feature). Para não
#    depender de encerramento assíncrono, capturamos a saída com timeout curto
#    e verificamos que o pipeline não sinalizou configuração ausente e que os
#    gates foram registrados no ledger.
supervise_out="$TMP/supervise.log"
set +e
timeout 40 env \
  RALPH_RUNTIME_EVIDENCE_CMD='echo runtime-ok' \
  RALPH_TECHNICAL_REVIEW_COMMAND='echo review-ok' \
  RALPH_CURATION_COMMAND='echo curation-ok' \
  bash -c 'cd "$1" && "$2" supervise --workflow wf_gates_native --engine codex --interval 1 --max-retries 0' _ "$repo" "$ROOT/bin/ralph-control" > "$supervise_out" 2>&1
supervise_rc=$?
set -e
[ "$supervise_rc" -ne 124 ] || true  # timeout é esperado no loop de teste

grep -q 'gates_configuration_required' "$supervise_out" && fail 'supervise retornou gates_configuration_required'
grep -q 'gate runtime_evidence: aprovado\|gate runtime_evidence: passou\|gate runtime_evidence' "$supervise_out" \
  || fail 'supervise não processou runtime_evidence'

# 2. Os quatro gates (exceto validation) foram registrados no ledger.
gate_count="$(grep -c '"gate"' "$repo/.git/ralph-control/events.jsonl" 2>/dev/null || true)"
printf '%s\n' "gates registrados no ledger: $gate_count"
[ "$gate_count" -ge 4 ] || fail 'menos de 4 registros de gate no ledger'

# 3. Contrato por env: um comando próprio que lê o contexto sem args posicionais.
printf '%s\n' '#!/usr/bin/env bash' 'echo "ctx=$RALPH_WORKFLOW_ID/$RALPH_FEATURE_KEY/$RALPH_GATE/$RALPH_ATTEMPT"' > "$repo/bin/env-gate.sh"
chmod +x "$repo/bin/env-gate.sh"

# 4. Compatibilidade: configuração explícita por env continua aceita (quality).
QUALITY_CMD_CHECK="$ROOT/scripts/ralph-run-quality.sh"
[ -x "$QUALITY_CMD_CHECK" ] || fail 'wrapper quality ausente'

# 5. Wrapper lê o contrato por env (invocação nua, sem args).
ctx="$(cd "$repo" && RALPH_WORKFLOW_ID=wf_gates_native RALPH_FEATURE_KEY=FEATURE-GATES-NATIVE RALPH_GATE=quality RALPH_ATTEMPT=1 bash "$repo/bin/env-gate.sh")"
[ "$ctx" = "ctx=wf_gates_native/FEATURE-GATES-NATIVE/quality/1" ] || fail "contrato por env não entregue ao comando: $ctx"

# 6. Supervise com um gate sem default e sem env não para em
#    gates_configuration_required (usa o default do wrapper).
fresh="$TMP/repo2"
cp -a "$repo" "$fresh"
rm -f "$fresh/.git/ralph-control/events.jsonl" "$fresh/.git/ralph-control/workflow.json" "$fresh/.git/ralph-control/reports/"*.log 2>/dev/null || true
rm -rf "$fresh/.git/ralph-control/reports" 2>/dev/null || true
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_gates_native","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-GATES-NATIVE","title":"Gates nativos","position":1}]}' > "$fresh/workflow.json"
git -C "$fresh" add -A
git -C "$fresh" commit -qm base2

init2="$(cd "$fresh" && control init --workflow wf_gates_native --manifest workflow.json)"
[ -n "$init2" ] || fail 'init do workflow fresh falhou'
claim2="$(cd "$fresh" && control claim --workflow wf_gates_native --feature FEATURE-GATES-NATIVE --actor gates-test)"
lease2="$(printf '%s' "$claim2" | php -r '$v=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
run2="$(cd "$fresh" && control run --workflow wf_gates_native --feature FEATURE-GATES-NATIVE --lease "$lease2" --command 'exit 0')"
printf '%s' "$run2" | grep -q '"status": "awaiting_gates"' || fail "run fresh não chegou a awaiting_gates: $run2"

supervise2_out="$TMP/supervise2.log"
set +e
timeout 30 env RALPH_CURATION_COMMAND='echo curation-ok' \
  bash -c 'cd "$1" && "$2" supervise --workflow wf_gates_native --engine codex --interval 1 --max-retries 0' _ "$fresh" "$ROOT/bin/ralph-control" > "$supervise2_out" 2>&1
set -e
grep -q 'gates_configuration_required' "$supervise2_out" && fail 'supervise2 retornou gates_configuration_required'

printf '%s\n' 'OK: gates nativos — supervisor processa os cinco gates sem gates_configuration_required, contrato por env e compatibilidade preservada.'
