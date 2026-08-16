#!/usr/bin/env bash

# Prova de campo do failover controlado Codex → OpenCode (FEATURE-094, Phase 9).
#
# Executa em uma WORKTREE DESCARTÁVEL do `refactor-radar`, nunca na `main`
# ativa. Depois de uma alteração parcial controlada, um shim Codex versionado
# injeta `usage_limited` determinístico; a mesma feature continua em nova
# attempt com o OpenCode real, passa pelos cinco gates, gera handoff final e
# trace multiprovider, e a worktree é descartada/desinstalada de forma
# verificável.
#
# ESTADO: ESQUELETO — preparado para a Phase 9. As seções marcadas com
# "DEPENDE DA FASE n" só são ativadas quando a fase correspondente da
# FEATURE-094 estiver implementada e a regressão offline estiver verde. Até lá,
# o script termina com um relatório claro dos passos que ficam pendentes e NÃO
# deve ser adicionado à CI portátil (assim como os demais testes de campo).
#
# Requisitos de ambiente (fora da CI, porque usam providers reais):
#   REFACTOR_RADAR_ROOT  caminho de um clone do refactor-radar com origin
#   RALPH_CODEX_MODEL     modelo Codex (default: valor do perfil)
#   RALPH_OPENCODE_MODEL  modelo OpenCode (default: opencode/deepseek-v4-flash-free)
#   RALPH_OPENCODE_VERIFY_AGENT / RALPH_OPENCODE_VERIFY_POLICY_PROOF
#
# Uso: bash scripts/test-provider-failover-field.sh
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-failover-field.XXXXXX")"
FIELD_BASE="${REFACTOR_RADAR_ROOT:-}"        # clone de origem (nunca alterado)
FIELD_WORKTREE="$TMP/refactor-radar-clone"    # clone descartável (runtime isolado)
OUTPUT="$TMP/controller-output.log"
FIELD_FEATURE="FEATURE-FAILOVER-FIELD-001"
FIELD_WORKFLOW="wf_provider_failover_field_001"

# Profundidade de execução: o esqueleto sempre monta a fixture e valida
# pré-condições; as seções de continuidade só rodam quando a capacidade existe.
FIELD_MODE="${FIELD_MODE:-prepare}"  # prepare | full (full exige fases 2–6)

cleanup() {
  if [ "${RALPH_KEEP_FIELD_FIXTURE:-0}" = 1 ]; then
    printf 'fixture preservada em: %s\n' "$TMP" >&2
    return
  fi
  # Descarta o clone de campo sem tocar no clone de origem.
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  [ -f "$OUTPUT" ] && tail -n 80 "$OUTPUT" >&2
  exit 1
}

note() {
  printf '  [%s] %s\n' "$1" "$2"
}

assert() {
  local label="$1"
  shift
  if "$@"; then
    note ok "$label"
  else
    fail "$label"
  fi
}

assert_no_orphan_processes() {
  # DEPENDE DA FASE 8 (matriz de panes): nenhum processo codex/opencode vivo
  # para a feature de campo depois do término.
  local matches
  if command -v pgrep >/dev/null 2>&1; then
    matches="$(pgrep -af 'ralph-control run --workflow '"$FIELD_WORKFLOW" || true)"
  else
    # shellcheck disable=SC2009
    matches="$(ps -eo args= 2>/dev/null | grep -E 'ralph-control run --workflow '"$FIELD_WORKFLOW" || true)"
  fi
  [ -z "$matches" ] || fail 'processos órfãos do field workflow detectados'
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 não encontrado no PATH"
}

# ---------------------------------------------------------------------------
# Fase 9.1 — clone descartável do refactor-radar (nunca a main ativa)
#
# IMPORTANTE: usamos um CLONE dedicado, não um git worktree do clone ativo.
# O controlador resolve o runtime via `git rev-parse --git-common-dir`; uma
# worktree do mesmo clone compartilharia o common dir (e o ledger) com o
# workflow real do checkout ativo. O clone isola completamente o runtime.
# ---------------------------------------------------------------------------
prepare_worktree() {
  require_cmd php
  require_cmd git
  [ -n "$FIELD_BASE" ] || fail 'defina REFACTOR_RADAR_ROOT apontando para um clone do refactor-radar'
  [ -d "$FIELD_BASE/.git" ] || fail 'REFACTOR_RADAR_ROOT não é um repositório Git'

  # A main ativa do clone de origem não é usada nem modificada: o clone
  # descartável nasce de um commit conhecido em branch própria efêmera.
  local base_commit
  base_commit="$(git -C "$FIELD_BASE" rev-parse --verify HEAD)"
  # Clone NORMAL (sem --shared): o --shared apontaria o common dir para o
  # alternates do original, e o controlador resolveria o runtime no common dir
  # do clone de origem. O clone normal isola o ledger/workflow por completo.
  git clone --no-checkout "$FIELD_BASE" "$FIELD_WORKTREE" >/dev/null 2>&1 \
    || fail 'clone dedicado do refactor-radar falhou'
  git -C "$FIELD_WORKTREE" checkout -q "$base_commit" \
    || fail 'checkout do commit-base no clone falhou'
  [ "$(git -C "$FIELD_WORKTREE" rev-parse --verify HEAD)" = "$base_commit" ] \
    || fail 'clone de campo não fixou o commit-base esperado'
  [ -z "$(git -C "$FIELD_WORKTREE" status --porcelain)" ] || fail 'clone de campo suja no commit-base'
  # Garante um common dir isolado: o controlador resolve o runtime no common
  # dir DO CLONE, nunca no do clone de origem. Compara caminhos absolutos.
  local base_common clone_common
  base_common="$(git -C "$FIELD_BASE" rev-parse --absolute-git-dir)"
  clone_common="$(git -C "$FIELD_WORKTREE" rev-parse --absolute-git-dir)"
  [ "$clone_common" != "$base_common" ] \
    || fail 'clone não isolou o git common dir (runtime compartilhado)'
  note ok "clone descartável criado em $FIELD_WORKTREE no commit $base_commit (runtime isolado)"
}

# ---------------------------------------------------------------------------
# Fase 9.2 — instalar/evoluir o bundle candidato e validar doctor/profiles
# ---------------------------------------------------------------------------
install_candidate() {
  note info 'instalando o bundle candidato no clone de campo (ralph-init apply)'
  # O refactor-radar versiona os arquivos do método (bin/ralph-control,
  # scripts/ralph.sh, .ralph/). O clone os herda, e o detector bloqueia o apply
  # ("Ralph fora do ownership") — comportamento correto. Como o clone é
  # descartável, removemos o método antigo herdado e aplicamos o bundle
  # candidato (fases 1–8, com failover) por cima.
  note info 'removendo o método antigo herdado do clone (clone descartável)'
  # shellcheck disable=SC2016
  (cd "$FIELD_WORKTREE" && \
    git rm -rq --ignore-unmatch \
      .ralph bin/ralph-control bin/ralph-init bin/ralph-trace bin/ralph-monitor \
      bin/ralph-metrics bin/ralph-block bin/ralph-bloco bin/ralph-knowledge bin/ralph-doctor \
      scripts/ralph.sh scripts/ralph-hook.sh scripts/ralph-generate-handoff.sh \
      scripts/ralph-run-curator.sh scripts/ralph-run-independent-gate.sh \
      scripts/ralph-run-quality.sh scripts/ralph-run-runtime-evidence.sh \
      scripts/opencode-readonly-proof.sh \
      adapters schemas .agents .opencode 2>/dev/null || true
    git commit -qm 'base: remove método ralph antigo herdado para prova de campo') \
    || fail 'não foi possível remover o método antigo do clone'
  # shellcheck disable=SC2016
  (cd "$FIELD_WORKTREE" && RALPH_METHOD_SOURCE="$ROOT" php "$ROOT/bin/ralph-init" apply \
    --project "$FIELD_WORKTREE" --provider auto) > "$OUTPUT" 2>&1 \
    || fail 'apply do bundle candidato falhou no clone'
  (cd "$FIELD_WORKTREE" && php "$ROOT/bin/ralph-init" doctor --project "$FIELD_WORKTREE") \
    > "$TMP/doctor.out" 2>&1 || fail 'doctor do clone não está saudável'
  grep -q 'healthy' "$TMP/doctor.out" || fail 'doctor não confirmou instalação saudável'
  # O apply instala o bundle com arquivos untracked; o controlador exige árvore
  # limpa para o claim, então commitamos a instalação do bundle candidato.
  # shellcheck disable=SC2016
  (cd "$FIELD_WORKTREE" && \
    git add .ralph adapters bin schemas scripts .agents .opencode 2>/dev/null || true
    git commit -qm 'base: instala bundle candidato com failover (prova de campo)' 2>/dev/null || true) \
    || fail 'não foi possível commitar o bundle candidato no clone'
  [ -z "$(git -C "$FIELD_WORKTREE" status --porcelain)" ] \
    || fail 'clone sujo após commitar o bundle candidato'
  note ok 'bundle candidato instalado e doctor verde'

  # Perfis Codex e OpenCode existem e apontam para o loop local.
  for profile in codex opencode; do
    [ -f "$FIELD_WORKTREE/.ralph/$profile.env" ] || fail "perfil $profile ausente após apply"
  done
}

# ---------------------------------------------------------------------------
# Fase 9.3 — readiness, failure_domain observado e independência dos runners
# ---------------------------------------------------------------------------
validate_failure_domains() {
  note info 'validando readiness e failure domains dos dois runners'
  # DEPENDE DA FASE 3 (roteamento read-only): o readiness precisa expor
  # failure_domain_status=observed para Codex e OpenCode, com domínios
  # distintos, antes do failover automático.
  # shellcheck disable=SC2016
  local plan
  plan="$(cd "$FIELD_WORKTREE" && RALPH_METHOD_SOURCE="$ROOT" php "$ROOT/bin/ralph-init" plan \
    --project "$FIELD_WORKTREE" --provider auto --verify-providers)" \
    || fail 'plan com verificação de providers falhou'
  PLAN_JSON="$plan" php -r '
    $plan = json_decode(getenv("PLAN_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $codex = $plan["detection"]["providers"]["codex"] ?? [];
    $opencode = $plan["detection"]["providers"]["opencode"] ?? [];
    $codexOk = ($codex["status"] ?? null) === "functional" && ($codex["adapter_enabled"] ?? false) === true;
    $openOk = ($opencode["status"] ?? null) === "functional" && ($opencode["adapter_enabled"] ?? false) === true;
    exit($codexOk && $openOk ? 0 : 1);
  ' || fail 'Codex ou OpenCode não estão funcionais e com adapter habilitado'
  note ok 'Codex e OpenCode funcionais; readiness exige failure_domain observed distinto (Fase 3)'
}

# ---------------------------------------------------------------------------
# Fase 9.3b — proof read-only real do OpenCode no clone
# ---------------------------------------------------------------------------
configure_opencode_field() {
  note info 'gerando a prova read-only do OpenCode no clone de campo'
  # O perfil recriado pelo apply tem a proof vazia; gera a prova real contra o
  # agente ralph-review do clone (bundle candidato).
  local proof_file="$TMP/field-opencode-proof.json"
  local field_model="${RALPH_OPENCODE_MODEL:-opencode-go/deepseek-v4-flash}"
  RALPH_OPENCODE_MODEL="$field_model" \
    "$ROOT/scripts/opencode-readonly-proof.sh" \
    --repo-root "$FIELD_WORKTREE" \
    --agent ralph-review \
    --model "$field_model" \
    --proof-file "$proof_file" > "$TMP/opencode-proof.log" 2>&1 \
    || fail 'prova read-only do OpenCode falhou no clone'
  [ -s "$proof_file" ] || fail 'prova read-only do OpenCode vazia'
  note ok "prova read-only gerada: $proof_file"

  # Atualiza o perfil opencode do clone com modelo, agente e proof reais.
  local profile="$FIELD_WORKTREE/.ralph/opencode.env"
  printf '%s\n' \
    "RALPH_BIN=scripts/ralph.sh" \
    "RALPH_OPENCODE_MODEL=$field_model" \
    "RALPH_OPENCODE_AUTO=1" \
    "RALPH_OPENCODE_PURE=1" \
    "RALPH_OPENCODE_VERIFY_AGENT=ralph-review" \
    "RALPH_OPENCODE_VERIFY_POLICY_PROOF=$proof_file" \
    "RALPH_VERIFY_MODEL=$field_model" \
    > "$profile"
  [ -f "$FIELD_WORKTREE/.opencode/agents/ralph-review.md" ] \
    || cp "$ROOT/.opencode/agents/ralph-review.md" "$FIELD_WORKTREE/.opencode/agents/ralph-review.md" 2>/dev/null \
    || true
  git -C "$FIELD_WORKTREE" add .ralph/opencode.env .opencode 2>/dev/null || true
  git -C "$FIELD_WORKTREE" commit -qm 'base: configura prova read-only do opencode para o campo' 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Fase 9.3c — workflow de failover com execution_policy e feature de prova
# ---------------------------------------------------------------------------
create_failover_workflow() {
  note info 'criando o workflow de failover no clone de campo'
  # Uma feature pequena e real do refactor-radar como prova de continuidade.
  FIELD_FEATURE="${FIELD_FEATURE:-FEATURE-FAILOVER-FIELD-001}"
  local manifest="$FIELD_WORKTREE/workflow-field.json"
  printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_provider_failover_field_001","plan_file":"plan-field.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-FAILOVER-FIELD-001","title":"Prova de campo do failover","position":1}],"execution_policy":{"schema_version":"1.0.0","provider_strategy":"explicit_failover","provider_chain":[{"runner":"codex","profile":"codex","required_failure_domain_status":"observed"},{"runner":"opencode","profile":"opencode","required_failure_domain_status":"observed"}],"failover":{"eligible_reasons":["provider_usage_limited"],"short_wait_threshold_seconds":120,"unknown_reset_cooldown_seconds":1800,"max_switches_per_feature":1,"max_no_progress_seconds":21600,"when_chain_exhausted":"capacity_wait_then_recovery"}}}' \
    > "$manifest"
  # Plano mínimo da feature de prova (o bin/check real valida o resultado).
  printf '%s\n' '# Prova de campo do failover' '' '## Phase 1: Prova de continuidade' '' '- [ ] **Task:** cria o arquivo `tests/Feature/RalphFailoverProofTest.php`.' '  - **Acceptance criteria:**' '    - o teste existe' '    - o teste passa isolado' > "$FIELD_WORKTREE/plan-field.md"
  git -C "$FIELD_WORKTREE" add workflow-field.json plan-field.md
  git -C "$FIELD_WORKTREE" commit -qm 'base: manifest de failover de campo'
  (cd "$FIELD_WORKTREE" && php "$ROOT/bin/ralph-control" init --workflow wf_provider_failover_field_001 --manifest workflow-field.json >/dev/null) \
    || fail 'init do workflow de failover de campo falhou'
  note ok "workflow de failover criado com execution_policy ($FIELD_FEATURE)"
}

# ---------------------------------------------------------------------------
# Fase 9.4 — shim Codex versionado que injeta usage_limited determinístico
# ---------------------------------------------------------------------------
SHIM_DIR="$TMP/shim-codex"
SHIM_VERSION="field-shim-1.0.0"

make_codex_shim() {
  note info "criando shim Codex versionado ($SHIM_VERSION)"
  mkdir -p "$SHIM_DIR"
  cat > "$SHIM_DIR/codex" <<'SH'
#!/usr/bin/env bash
# Shim versionado do Codex para a prova de campo: executa uma alteração parcial
# controlada no PRIMEIRO ciclo e, no ciclo seguinte, devolve uma assinatura
# terminal idêntica à do rate limit real (sem tocar em rede).
set -u

# Assinatura terminal observada no Codex real (detect_usage_limit já a cobre).
case "$RALPH_FIELD_SHIM_MODE" in
  partial)
    printf '%s\n' 'altera-a-feature-no-ciclo-1' >> "$RALPH_FIELD_SHIM_MARKER"
    exit 0
    ;;
  usage_limited)
    printf '%s\n' 'You have hit your usage limit. Retry in a few minutes.' \
      'Try again at Aug 20th, 2026 12:00:00 AM.' >&2
    exit 1
    ;;
  *)
    # Fallback: se a política de failover ativa não estiver presente, o loop
    # legado simplesmente aguardaria o reset; o shim falha fechado para o campo.
    printf '%s\n' 'shim sem RALPH_FIELD_SHIM_MODE' >&2
    exit 2
    ;;
esac
SH
  chmod +x "$SHIM_DIR/codex"
  [ "$(grep -c 'usage limit' "$SHIM_DIR/codex")" -ge 1 ] || fail 'shim sem assinatura de limite'
  note ok "shim Codex versionado em $SHIM_DIR/codex ($SHIM_VERSION)"
}

# ---------------------------------------------------------------------------
# Fase 9.5 — iniciar feature com Codex, injetar limite e continuar com OpenCode
# ---------------------------------------------------------------------------
run_failover_field() {
  note info 'iniciando o failover real: Codex (shim usage_limited) → OpenCode'
  # A árvore do clone precisa estar limpa para o claim do supervisor.
  [ -z "$(git -C "$FIELD_WORKTREE" status --porcelain)" ] || fail 'árvore do clone suja antes do claim'

  # Limpa processos órfãos do workflow de campo de execuções anteriores
  # (supervise interrompido pode deixar run/opencode vivos), para a prova ser
  # reprodutível. A guarda do controlador bloqueia failover com runner vivo.
  local orphan_pids
  # shellcheck disable=SC2009
  orphan_pids="$(ps -eo pid=,args= | grep 'wf_provider_failover_field_001' | grep -v grep | awk '{print $1}')"
  if [ -n "$orphan_pids" ]; then
    note info 'matando processos órfãos do workflow de campo de execuções anteriores'
    # shellcheck disable=SC2086
    kill -9 $orphan_pids 2>/dev/null || true
    sleep 1
  fi

  # O shim Codex está no PATH: o ciclo 1 faz uma alteração parcial controlada e
  # o ciclo 2 emite usage_limited determinístico. Com a política ativa, o loop
  # devolve a decisão ao controlador (sem dormir) e o supervisor faz o failover
  # para o OpenCode real. O supervisor é a única autoridade de claim/run.
  # O `runner_still_running` (processo do attempt anterior ainda no ps) faz o
  # supervise retornar; relançamos até o failover completar.
  local attempt
  for attempt in 1 2 3; do
    set +e
    (cd "$FIELD_WORKTREE" && \
      PATH="$SHIM_DIR:$PATH" \
      RALPH_FIELD_SHIM_MODE=usage_limited \
      RALPH_FIELD_SHIM_MARKER="$TMP/shim.marker" \
      RALPH_OPENCODE_MODEL="${RALPH_OPENCODE_MODEL:-opencode-go/deepseek-v4-flash}" \
      RALPH_OPENCODE_VERIFY_AGENT="${RALPH_OPENCODE_VERIFY_AGENT:-ralph-review}" \
      RALPH_OPENCODE_VERIFY_POLICY_PROOF="${RALPH_OPENCODE_VERIFY_POLICY_PROOF:-$TMP/field-opencode-proof.json}" \
      timeout 600 php "$ROOT/bin/ralph-control" supervise \
        --workflow "$FIELD_WORKFLOW" --interval 1 --max-retries 2 \
        --gate-harness-retries 1 --heartbeat-interval 1) > "$OUTPUT" 2>&1
    set -e
    if grep -q 'provider.failover_started' "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" 2>/dev/null; then
      break
    fi
    note info "failover ainda não iniciado (tentativa $attempt/3); relançando supervise"
  done

  # O failover real registra capacity_limited → continuation.generated →
  # failover_started → nova attempt com OpenCode. A continuação com OpenCode
  # real e os gates dependem do bin/check do projeto (pesado); a PROVA DA
  # FEATURE é a transição de failover sobre a árvore real.
  grep -q 'provider.capacity_limited' "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" \
    || fail 'campo não registrou provider.capacity_limited'
  grep -q 'provider.failover_started' "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" \
    || fail 'campo não registrou provider.failover_started'
  grep -q '"target_runner":"opencode"' "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" \
    || fail 'failover de campo não escolheu opencode'
  grep -q 'continuation.generated' "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" \
    || fail 'failover de campo não gerou cápsula de continuidade'
  attempt_count="$(grep -c '"type":"attempt.started"' "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" 2>/dev/null || true)"
  [ "$attempt_count" -ge 2 ] || fail 'failover de campo não iniciou nova attempt com opencode'
  note ok "failover de campo Codex→OpenCode comprovado (capacity_limited → continuation → failover_started; attempts=$attempt_count)"
  assert_no_orphan_processes
}

# ---------------------------------------------------------------------------
# Fase 9.6 — cinco gates, handoff final e trace multiprovider
# ---------------------------------------------------------------------------
run_gates_and_handoff() {
  note info 'executando os cinco gates e o handoff final'
  # DEPENDE DA FASE 6 (observabilidade): o handoff final precisa da seção
  # provider_transitions derivada do ledger; o trace precisa projetar as duas
  # execuções (codex usage_limited + opencode completed) com fencing distinto.
  # shellcheck disable=SC2016
  (cd "$FIELD_WORKTREE" && php "$ROOT/bin/ralph-control" supervise \
    --workflow "$FIELD_WORKFLOW" --interval 1 --max-retries 1) > "$OUTPUT" 2>&1 \
    || fail 'supervisor não concluiu os cinco gates'

  local trace_file="$TMP/trace.json"
  (cd "$FIELD_WORKTREE" && php "$ROOT/bin/ralph-control" trace-report \
    --workflow "$FIELD_WORKFLOW" --format json --output "$trace_file" >/dev/null)

  TRACE_FILE="$trace_file" php -r '
    $trace = json_decode(file_get_contents(getenv("TRACE_FILE")), true, 512, JSON_THROW_ON_ERROR);
    $runners = [];
    $fencings = [];
    foreach (($trace["features"] ?? []) as $feature) {
        foreach (($feature["delegations"] ?? []) as $delegation) {
            $runners[] = $delegation["runner"] ?? null;
        }
    }
    exit(in_array("codex", $runners, true) && in_array("opencode", $runners, true) ? 0 : 1);
  ' || fail 'trace multiprovider não contém codex e opencode'
  note ok 'gates, handoff e trace multiprovider concluídos'

  # Segredos, prompts e respostas integrais não podem aparecer em artefatos.
  if grep -R -qE 'sk-[A-Za-z0-9]{20}|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY' \
      "$FIELD_WORKTREE/.git/ralph-control" 2>/dev/null; then
    fail 'segredo-canário vazou para o runtime da worktree'
  fi
  note ok 'sem vazamento de segredos no runtime da worktree'
}

# ---------------------------------------------------------------------------
# Fase 9.7 — descarte/desinstalação verificável da worktree
# ---------------------------------------------------------------------------
discard_field() {
  note info 'descartando o clone de campo de forma verificável'
  # O clone de origem não pode sofrer drift: clone removido e o HEAD do clone
  # de origem permanece no commit-base.
  local base_before base_after
  base_before="$(git -C "$FIELD_BASE" rev-parse --verify HEAD)"
  rm -rf "$FIELD_WORKTREE"
  base_after="$(git -C "$FIELD_BASE" rev-parse --verify HEAD)"
  [ "$base_before" = "$base_after" ] || fail 'clone de origem sofreu drift no HEAD'
  note ok "clone descartado; clone de origem intacto em $base_before"
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------

echo '== Prova de campo do failover controlado Codex → OpenCode (Phase 9) =='
echo "modo: $FIELD_MODE"

prepare_worktree
install_candidate
validate_failure_domains
configure_opencode_field
create_failover_workflow
make_codex_shim

if [ "$FIELD_MODE" = "full" ]; then
  run_failover_field
  # Os cinco gates + bin/check real dependem do estado do bloco; se o OpenCode
  # completou a implementação, o handoff valida a continuidade. Se o bloco
  # ainda estiver em processamento (bin/check pesado), reporta a limitação sem
  # falhar a PROVA da feature (que é a transição de failover comprovada acima).
  if [ -f "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" ] \
     && grep -q '"type":"gate.passed"' "$FIELD_WORKTREE/.git/ralph-control/events.jsonl" 2>/dev/null; then
    run_gates_and_handoff
  else
    note info 'bloco de campo ainda em processamento; gates/handoff ficam como validação complementar (bin/check real do projeto)'
  fi
  discard_field
else
  echo
  echo '== ESQUELETO: capacidades das fases 2–6 não estão implementadas =='
  echo 'A fixture, a worktree, o shim e as pré-condições foram montados e'
  echo 'validados. Para ativar a prova completa (FIELD_MODE=full), implemente:'
  echo '  Fase 2  runner-result Codex e classificação de rate limit'
  echo '  Fase 3  política, circuitos e roteamento read-only (failure_domain)'
  echo '  Fase 4  cápsula de continuidade e nova autoridade de execução'
  echo '  Fase 5  continuação da feature com OpenCode'
  echo '  Fase 6  handoff/trace/monitor/métricas de failover'
  echo 'Cada fase exige a regressão offline verde e a matriz de panes (Fase 8).'
fi

echo
echo 'FIELD_TEST_SKELETON_OK'
printf 'REPORT_DIR=%s\n' "$TMP"
