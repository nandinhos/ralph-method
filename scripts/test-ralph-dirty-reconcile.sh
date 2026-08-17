#!/usr/bin/env bash

# Os blocos PHP/Python usam expressões literais dentro de aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-dirty-reconcile.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control() {
  php "$ROOT/bin/ralph-control" "$@"
}

project="$TMP/project"
mkdir -p "$project/.ralph" "$project/bin"
git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method Dirty Reconcile Test'
printf '%s\n' '# Reconciliação de árvore suja' > "$project/README.md"
printf '%s\n' '# Plano' > "$project/plan.md"
printf '%s\n' '## Phase 1: Criar arquivo A' '' '- [ ] **Task:** cria o arquivo A.' '  - **Acceptance criteria:**' '    - o arquivo existe' > "$project/phases.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_dirty_reconcile","plan_file":"phases.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-DIRTY","title":"Bloco interrompido","position":1}]}' > "$project/workflow.json"
printf '%s\n' '#!/usr/bin/env bash' 'echo check-ok' > "$project/bin/check"
chmod +x "$project/bin/check"
cp "$ROOT/bin/ralph-control" "$project/bin/ralph-control"
chmod +x "$project/bin/ralph-control"

# Fake ralph: escreve a implementação e DEIXA a árvore suja (bloco interrompido
# não commita), exit 1. Runner declarado opencode.
cat > "$TMP/fake-ralph.sh" <<'SH'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' 'feature do bloco interrompido' > "$PWD/feature-impl.txt"
mkdir -p "$PWD/.phases/logs"
python3 - "$PWD/.phases/logs/phase-01.cycle-1.log.result.json" <<'PY'
import json
import os
import sys
from pathlib import Path
result = {
    'schema_version': '1.0.0',
    'runner': 'opencode',
    'runner_version': '1.18.15-fixture',
    'provider': 'opencode',
    'requested_model': 'opencode/fixture-model',
    'effective_model': None,
    'identity_status': 'declared',
    'identity_source': 'requested_model',
    'execution_id': 'exec_dirty_impl',
    'execution_mode': 'impl',
    'workflow_id': os.environ['RALPH_EXECUTION_WORKFLOW_ID'],
    'feature_key': os.environ['RALPH_EXECUTION_FEATURE_KEY'],
    'attempt': int(os.environ['RALPH_EXECUTION_ATTEMPT']),
    'session_id': 'ses_dirty_impl',
    'status': 'failed',
    'exit_code': 1,
    'fallback_used': None,
    'fallback_status': 'unknown',
    'events_seen': 1,
    'event_bytes': 10,
    'terminal_event': 'step_finish',
    'prompt_sha256': None,
    'prompt_transport': 'file',
    'permission_policy_hash': None,
    'permission_policy_status': 'not_required',
    'verification_agent': None,
    'error_summary': 'bloco interrompido',
    'artifact_refs': ['fixture_dirty'],
}
path = sys.argv[1]
Path(path).parent.mkdir(parents=True, exist_ok=True)
Path(path).write_text(json.dumps(result) + '\n')
PY
printf '%s\n' 'RALPH_FEEDBACK {"event":"fixture_done","source":"dirty"}'
exit 1
SH
chmod +x "$TMP/fake-ralph.sh"
printf '%s\n' "RALPH_BIN=$TMP/fake-ralph.sh" > "$project/.ralph/codex.env"
git -C "$project" add .
git -C "$project" add -f .ralph/codex.env
git -C "$project" commit -qm base

# ---------------------------------------------------------------------------
# Camada A: preflight do ralph.sh NÃO aborta em árvore suja com o sinal do
# controlador, e aborta sem ele (fail-closed).
# ---------------------------------------------------------------------------
# Fake codex no PATH: o ralph.sh chama `codex` direto; o fake termina rápido.
mkdir -p "$TMP/bin"
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex fixture (nao real)"' 'exit 0' > "$TMP/bin/codex"
chmod +x "$TMP/bin/codex"
export PATH="$TMP/bin:$PATH"

# Sem o sinal: abort fail-closed.
printf '%s\n' 'sujeira externa' > "$project/untracked.txt"
dirty_abort_exit=0
(cd "$project" && RALPH_RECONCILE_DIRTY=0 "$ROOT/scripts/ralph.sh" --engine codex --test-cmd true "$project/phases.md" > "$TMP/abort.log" 2>&1) || dirty_abort_exit=$?
[ "$dirty_abort_exit" -ne 0 ] || fail 'A: preflight sem sinal não abortou (exit 0 inesperado)'
grep -q 'Arvore de trabalho suja' "$TMP/abort.log" || fail 'A: preflight sem sinal não abortou por árvore suja'
rm -f "$project/untracked.txt"

# Com o sinal: não aborta por árvore suja.
printf '%s\n' 'sujeira do bloco' > "$project/feature-impl.txt"
dirty_continue_exit=0
(cd "$project" && RALPH_RECONCILE_DIRTY=1 "$ROOT/scripts/ralph.sh" --engine codex --test-cmd true "$project/phases.md" > "$TMP/continue.log" 2>&1) || dirty_continue_exit=$?
grep -q 'Arvore de trabalho suja' "$TMP/continue.log" && fail 'A: preflight com sinal ainda abortou por árvore suja'
printf 'A: árvore suja com sinal de reconciliação não abortou no preflight (exit=%s)\n' "$dirty_continue_exit"
rm -f "$project/feature-impl.txt"

# ---------------------------------------------------------------------------
# Leva a feature a debugging_required: claim + run (bloco falha, exit 1).
# ---------------------------------------------------------------------------
(cd "$project" && control init --workflow wf_dirty_reconcile --manifest workflow.json >/dev/null)
claim="$(cd "$project" && control claim --workflow wf_dirty_reconcile --feature FEATURE-DIRTY --actor test)"
lease="$(printf '%s' "$claim" | php -r '$v=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
[ -n "$lease" ] || fail 'claim não devolveu lease'
run_exit=0
(cd "$project" && control run --workflow wf_dirty_reconcile --feature FEATURE-DIRTY --lease "$lease" --engine codex --test-cmd true --heartbeat-interval 1) > "$TMP/run.log" 2>&1 || run_exit=$?
grep -q '"type":"block.finished"' "$project/.git/ralph-control/events.jsonl" || fail 'run não registrou block.finished'
printf 'bloco executado (run exit=%s) e registrado como finalizado\n' "$run_exit"

# ---------------------------------------------------------------------------
# Camadas B/C via comando debug direto.
# ---------------------------------------------------------------------------
# 1. cause_kind ausente -> rejeitado (não vira verified).
cat > "$TMP/debug-missing-kind.sh" <<'SH'
#!/usr/bin/env bash
echo '{"schema_version":"1.1.0","workflow_id":"wf_dirty_reconcile","feature_key":"FEATURE-DIRTY","attempt":1,"status":"verified","incident_id":"INCD-DIRTY-0001","symptom":"bloco interrompido","severity":"high","root_cause":"sem causa","correction_plan":"nenhum","hypotheses":[{"id":"H1","statement":"sem causa","status":"confirmed"}],"official_references":[{"provider":"official","source":"https://docs.ralph.example/method","section":"recuperacao"}],"validation":{"status":"passed","exit_code":0,"evidence_refs":["README.md"]},"knowledge_candidate":{"title":"sem causa","summary":"sem causa","applicability":{"when":"x","when_not":"y"},"limitations":[]}}'
SH
chmod +x "$TMP/debug-missing-kind.sh"
set +e
debug_missing="$(cd "$project" && control debug --workflow wf_dirty_reconcile --feature FEATURE-DIRTY --command "bash $TMP/debug-missing-kind.sh" 2>&1)"
set -e
printf '%s' "$debug_missing" | grep -q 'cause_kind' || { printf '%s\n' "$debug_missing"; fail 'B: relatório sem cause_kind não foi rejeitado'; }
printf 'B: relatório sem cause_kind -> rejeitado (diagnóstico não fiel)\n'

# 2. feature_bug com evidência inexistente -> rejeitado (Camada C).
cat > "$TMP/debug-fake-bug.sh" <<'SH'
#!/usr/bin/env bash
echo '{"schema_version":"1.1.0","workflow_id":"wf_dirty_reconcile","feature_key":"FEATURE-DIRTY","attempt":1,"status":"verified","incident_id":"INCD-DIRTY-0002","symptom":"bug real","severity":"high","cause_kind":"feature_bug","root_cause":"bug no codigo","correction_plan":"corrigir","hypotheses":[{"id":"H1","statement":"bug no codigo","status":"confirmed"}],"official_references":[{"provider":"official","source":"https://docs.ralph.example/method","section":"recuperacao"}],"validation":{"status":"passed","exit_code":0,"evidence_refs":["src/nao-existe.php"]},"knowledge_candidate":{"title":"bug","summary":"bug","applicability":{"when":"x","when_not":"y"},"limitations":[]}}'
SH
chmod +x "$TMP/debug-fake-bug.sh"
set +e
debug_fake="$(cd "$project" && control debug --workflow wf_dirty_reconcile --feature FEATURE-DIRTY --command "bash $TMP/debug-fake-bug.sh" 2>&1)"
set -e
printf '%s' "$debug_fake" | grep -q 'evidência inexistente' || { printf '%s\n' "$debug_fake"; fail 'C: feature_bug com evidência inexistente não foi rejeitado'; }
printf 'C: feature_bug com evidência inexistente -> rejeitado (evidência falsa)\n'

# 3. feature_bug com evidência existente -> verified + cause_kind persistido.
mkdir -p "$project/src"
printf '%s\n' '<?php' > "$project/src/existe.php"
cat > "$TMP/debug-real-bug.sh" <<'SH'
#!/usr/bin/env bash
echo '{"schema_version":"1.1.0","workflow_id":"wf_dirty_reconcile","feature_key":"FEATURE-DIRTY","attempt":1,"status":"verified","incident_id":"INCD-DIRTY-0003","symptom":"bug real","severity":"high","cause_kind":"feature_bug","root_cause":"bug no codigo","correction_plan":"corrigir","hypotheses":[{"id":"H1","statement":"bug no codigo","status":"confirmed"}],"official_references":[{"provider":"official","source":"https://docs.ralph.example/method","section":"recuperacao"}],"validation":{"status":"passed","exit_code":0,"evidence_refs":["src/existe.php"]},"knowledge_candidate":{"title":"bug","summary":"bug","applicability":{"when":"x","when_not":"y"},"limitations":[]}}'
SH
chmod +x "$TMP/debug-real-bug.sh"
set +e
debug_real="$(cd "$project" && control debug --workflow wf_dirty_reconcile --feature FEATURE-DIRTY --command "bash $TMP/debug-real-bug.sh" 2>&1)"
set -e
printf '%s' "$debug_real" | grep -q 'debugging_verified' || { printf '%s\n' "$debug_real"; fail 'B/C: feature_bug com evidência existente deveria verificar'; }
grep -q '"cause_kind":"feature_bug"\|"cause_kind": *"feature_bug"' "$project/.git/ralph-control/events.jsonl" || fail 'B: cause_kind não persistido no debugging.verified'
printf 'B/C: feature_bug com evidência existente -> debugging.verified com cause_kind persistido\n'

# ---------------------------------------------------------------------------
# Ledger final: rejeições e verificação coerentes.
# ---------------------------------------------------------------------------
EVENTS_FILE="$project/.git/ralph-control/events.jsonl" python3 - <<'PY'
import json
import os

events = [json.loads(line) for line in open(os.environ['EVENTS_FILE']) if line.strip()]
types = [e.get('type') for e in events]
assert 'debugging.verified' in types, 'esperava debugging.verified'
assert types.count('debugging.rejected') >= 2, 'esperava ao menos 2 debugging.rejected'
print('ledger: 2 rejeições (cause_kind ausente + evidência falsa) e 1 verificação (feature_bug real)')
PY

printf 'OK: incidente 0018 — árvore suja reconciliável sob sinal do controlador, causa classificada no debug e evidência de feature_bug validada.\n'
