#!/usr/bin/env bash

# Regressão da FEATURE-097-GATE-RECUPERACAO: distingue defeito do comando de
# gate (gate_harness_error) de falha da feature (gate_rejected), e o retry de
# gate NÃO re-executa o bloco já commitado.
#
# Cobre o INC-2026-0007 (refactor-radar): technical_review rejeitado por
# defeito do comando; agora o erro de harness mantém a feature em
# awaiting_gates e re-roda só o gate — sem debugging da feature nem
# re-implementação.
#
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-gate-recovery.XXXXXX")"
if [ "${RALPH_TEST_KEEP_TMP:-0}" = 1 ]; then
  trap 'printf "KEEPING_TMP=%s\n" "$TMP" >&2' EXIT
else
  trap 'rm -rf "$TMP"' EXIT
fi

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control() { "$ROOT/bin/ralph-control" "$@"; }

# setup_repo <dir> <counter> <always_fail> -> inicializa workflow de uma feature
# e a deixa em awaiting_gates (bloco commitado com exit 0).
# Comandos de gate ficam em bin/ para o pipeline usar.
# always_fail=1 -> o comando de review sempre falha sem saída (harness_error).
# always_fail=0 -> o comando falha só na 1ª chamada e passa nas seguintes.
setup_repo() {
  local repo="$1" counter="$2" always_fail="$3"
  mkdir -p "$repo/bin" "$repo/scripts" "$repo/.ralph"
  cp "$ROOT/scripts/ralph-run-quality.sh" "$repo/scripts/"
  cp "$ROOT/scripts/ralph-run-runtime-evidence.sh" "$repo/scripts/"
  cp "$ROOT/scripts/ralph-run-independent-gate.sh" "$repo/scripts/"
  cp "$ROOT/scripts/ralph-run-curator.sh" "$repo/scripts/"
  chmod +x "$repo/scripts"/ralph-run-*.sh
  cp "$ROOT/bin/ralph-control" "$repo/bin/ralph-control"
  chmod +x "$repo/bin/ralph-control"

  printf '%s\n' '#!/usr/bin/env bash' 'echo "check OK"' > "$repo/bin/check"
  chmod +x "$repo/bin/check"

  if [ "$always_fail" = 1 ]; then
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' > "$repo/bin/faulty-gate.sh"
  else
    # Contador: falha SEM nenhuma saída (defeito de harness) na 1ª chamada,
    # passa nas seguintes (retry automático).
    printf '%s\n' '#!/usr/bin/env bash' "n=\$(cat \"$counter\" 2>/dev/null || echo 0)" "n=\$((n+1))" "echo \"\$n\" > \"$counter\"" 'if [ "$n" -le 1 ]; then exit 1; fi' 'echo "review-ok"' > "$repo/bin/faulty-gate.sh"
  fi
  chmod +x "$repo/bin/faulty-gate.sh"

  printf '%s\n' '# Fixture gate recovery' '' '## Phase 1: Provar recuperacao de gate' '' '- [ ] **Task:** feature de teste.' '  - **Acceptance criteria:** erro de harness nao re-executa o bloco.' > "$repo/plan.md"
  printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_gate_recovery","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-GATE-RECOVERY","title":"Recuperacao de gate","position":1}]}' > "$repo/workflow.json"
  printf '%s\n' 'AGENTS' > "$repo/AGENTS.md"

  git -C "$repo" init -q
  git -C "$repo" config user.email ralph-method@example.invalid
  git -C "$repo" config user.name 'Ralph Method Gate Recovery Test'
  git -C "$repo" add -A
  git -C "$repo" commit -qm base

  init_out="$(cd "$repo" && control init --workflow wf_gate_recovery --manifest workflow.json)"
  [ -n "$init_out" ] || fail 'init falhou'
  claim_out="$(cd "$repo" && control claim --workflow wf_gate_recovery --feature FEATURE-GATE-RECOVERY --actor recovery-test)"
  lease="$(printf '%s' "$claim_out" | php -r '$v=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
  [ -n "$lease" ] || fail 'claim não devolveu lease'

  # Bloco commitado com exit 0 -> block.finished(exit 0) -> awaiting_gates.
  printf '%s\n' 'implementado' > "$repo/src.txt"
  git -C "$repo" add src.txt bin/faulty-gate.sh
  git -C "$repo" commit -qm "feat: implementa a feature"
  run_out="$(cd "$repo" && control run --workflow wf_gate_recovery --feature FEATURE-GATE-RECOVERY --lease "$lease" --command 'true')"
  printf '%s' "$run_out" | grep -q '"status": "awaiting_gates"' || fail "run não chegou a awaiting_gates: $run_out"

  printf '%s' "$lease"
}

# ── Cenário A: comando sempre quebrado → harness_error, sem re-execução,
#    recovery_required no limite. ─────────────────────────────────────────────
repo_a="$TMP/repo-a"
counter_a="$TMP/counter-a"
printf '0\n' > "$counter_a"
setup_repo "$repo_a" "$counter_a" 1

supervise_a="$TMP/supervise-a.log"
set +e
timeout 25 env \
  RALPH_TECHNICAL_REVIEW_COMMAND='bash bin/faulty-gate.sh' \
  RALPH_CURATION_COMMAND='echo curation-ok' \
  bash -c 'cd "$1" && "$2" supervise --workflow wf_gate_recovery --engine codex --interval 1 --max-retries 0 --gate-harness-retries 1' _ "$repo_a" "$ROOT/bin/ralph-control" > "$supervise_a" 2>&1
set -e

echo "--- cenário A: supervise ---"
grep -E "gate technical_review|harness|recovery_required" "$supervise_a" | head -8
echo "--- fim ---"

grep -q "gate.harness_error" "$repo_a/.git/ralph-control/events.jsonl" \
  || fail 'A: não registrou gate.harness_error para comando sem evidência'
grep -q '"status": "rejected"' "$repo_a/.git/ralph-control/events.jsonl" \
  && fail 'A: comando sem evidência foi classificado como gate_rejected'
grep -q "gate_harness_error_limit\|falhou sem evidência após limite" "$repo_a/.git/ralph-control/events.jsonl" \
  || fail 'A: não registrou recovery_required por limite de harness error'

attempts_a="$(grep -c '"type": "attempt.started"' "$repo_a/.git/ralph-control/events.jsonl" 2>/dev/null || true)"
printf '%s\n' "A: attempts.started=$attempts_a (esperado 1 — sem re-execução do bloco)"
[ "$attempts_a" -le 1 ] || fail 'A: erro de harness re-executou o bloco de implementação'

# ── Cenário B: comando falha 1x e passa → retry automático do gate aprova,
#    sem recovery e sem re-execução. ─────────────────────────────────────────
repo_b="$TMP/repo-b"
counter_b="$TMP/counter-b"
printf '0\n' > "$counter_b"
setup_repo "$repo_b" "$counter_b" 0

supervise_b="$TMP/supervise-b.log"
set +e
timeout 30 env \
  RALPH_TECHNICAL_REVIEW_COMMAND='bash bin/faulty-gate.sh' \
  RALPH_CURATION_COMMAND='echo curation-ok' \
  bash -c 'cd "$1" && "$2" supervise --workflow wf_gate_recovery --engine codex --interval 1 --max-retries 0 --gate-harness-retries 3' _ "$repo_b" "$ROOT/bin/ralph-control" > "$supervise_b" 2>&1
set -e

echo "--- cenário B: supervise (1ª) ---"
grep -E "gate technical_review|harness|nova tentativa" "$supervise_b" | head -6
echo "--- fim ---"

grep -q "gate.harness_error" "$repo_b/.git/ralph-control/events.jsonl" \
  || fail 'B: não houve gate.harness_error na primeira tentativa do comando'

# O retry de gate NÃO re-executa o bloco (sem novo attempt.started).
attempts_b="$(grep -c '"type": "attempt.started"' "$repo_b/.git/ralph-control/events.jsonl" 2>/dev/null || true)"
printf '%s\n' "B: attempts.started=$attempts_b (esperado 1 — retry de gate não re-executa o bloco)"
[ "$attempts_b" -le 1 ] || fail 'B: retry de gate re-executou o bloco de implementação'

# O retry automático já aprovou o technical_review e avançou o workflow.
grep -q 'technical_review": *"passed"\|Gate technical_review: passed' "$repo_b/.git/ralph-control/events.jsonl" \
  || fail 'B: após o retry automático, technical_review não passou no ledger'
grep -q "gate_harness_error_limit\|falhou sem evidência após limite" "$repo_b/.git/ralph-control/events.jsonl" \
  && fail 'B: retry automático esgotou o limite (não deveria)'

# ── Cenário C: gate-test valida o comando sem tocar no workflow. ─────────────
selftest_ok="$(RALPH_TECHNICAL_REVIEW_COMMAND='echo review-ok' "$ROOT/bin/ralph-control" gate-test --gate technical_review 2>&1)"
printf '%s' "$selftest_ok" | grep -q '"classification": "passed"' \
  || fail 'C: gate-test não classificou comando saudável como passed'

selftest_bad="$(RALPH_TECHNICAL_REVIEW_COMMAND="bash -c 'exit 1'" "$ROOT/bin/ralph-control" gate-test --gate technical_review 2>&1)"
printf '%s' "$selftest_bad" | grep -q '"classification": "gate_harness_error"' \
  || fail 'C: gate-test não classificou comando sem evidência como gate_harness_error'

printf '%s\n' 'OK: recuperação de gate — erro de harness não re-executa o bloco, retry do comando aprova o gate e gate-test valida o comando.'