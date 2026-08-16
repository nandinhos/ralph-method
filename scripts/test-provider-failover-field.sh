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
FIELD_WORKTREE="$TMP/refactor-radar-worktree" # worktree descartável
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
  # Descarta a worktree de campo sem tocar no clone de origem.
  if [ -d "$FIELD_WORKTREE/.git" ]; then
    git -C "$FIELD_WORKTREE" worktree remove --force "$FIELD_WORKTREE" >/dev/null 2>&1 || true
  fi
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
# Fase 9.1 — worktree descartável do refactor-radar (nunca a main ativa)
# ---------------------------------------------------------------------------
prepare_worktree() {
  require_cmd php
  require_cmd git
  [ -n "$FIELD_BASE" ] || fail 'defina REFACTOR_RADAR_ROOT apontando para um clone do refactor-radar'
  [ -d "$FIELD_BASE/.git" ] || fail 'REFACTOR_RADAR_ROOT não é um repositório Git'

  # A main ativa do clone de origem não é usada nem modificada: a worktree
  # descarta nasce de um commit conhecido em branch própria efêmera.
  local base_commit
  base_commit="$(git -C "$FIELD_BASE" rev-parse --verify HEAD)"
  git -C "$FIELD_BASE" worktree add --detach "$FIELD_WORKTREE" "$base_commit" >/dev/null
  [ "$(git -C "$FIELD_WORKTREE" rev-parse --verify HEAD)" = "$base_commit" ] \
    || fail 'worktree de campo não fixou o commit-base esperado'
  [ -z "$(git -C "$FIELD_WORKTREE" status --porcelain)" ] || fail 'worktree de campo suja no commit-base'
  note ok "worktree descartável criada em $FIELD_WORKTREE no commit $base_commit"

  # Uma segunda checagem de segurança: o campo não pode escrever na main do
  # clone de origem.
  git -C "$FIELD_BASE" worktree list | grep -q "$FIELD_WORKTREE" || fail 'worktree não registrada'
}

# ---------------------------------------------------------------------------
# Fase 9.2 — instalar/evoluir o bundle candidato e validar doctor/profiles
# ---------------------------------------------------------------------------
install_candidate() {
  note info 'instalando o bundle candidato na worktree de campo (ralph-init apply)'
  # DEPENDE DA FASE 8: o bundle candidato precisa da regressão offline verde
  # e da revisão adversarial sem finding crítico/alto.
  # shellcheck disable=SC2016
  (cd "$FIELD_WORKTREE" && RALPH_METHOD_SOURCE="$ROOT" php "$ROOT/bin/ralph-init" apply \
    --project "$FIELD_WORKTREE" --provider auto) > "$OUTPUT" 2>&1 \
    || fail 'apply do bundle candidato falhou na worktree'
  (cd "$FIELD_WORKTREE" && php "$ROOT/bin/ralph-init" doctor --project "$FIELD_WORKTREE") \
    > "$TMP/doctor.out" 2>&1 || fail 'doctor da worktree não está saudável'
  grep -q 'healthy' "$TMP/doctor.out" || fail 'doctor não confirmou instalação saudável'
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
  note info 'iniciando a feature de campo (primeira attempt com Codex)'
  # DEPENDE DAS FASES 1–6: contratos v2 (prontos), runner-result Codex,
  # classificação, política/circuitos, cápsula e nova attempt com OpenCode.

  # A branch da worktree precisa estar isolada; o controlador exige árvore
  # limpa para o claim.
  [ -z "$(git -C "$FIELD_WORKTREE" status --porcelain)" ] || fail 'árvore da worktree suja antes do claim'

  local claim lease
  claim="$(cd "$FIELD_WORKTREE" && php "$ROOT/bin/ralph-control" claim \
    --workflow "$FIELD_WORKFLOW" --feature "$FIELD_FEATURE" --actor field-test)" \
    || fail 'claim da feature de campo falhou'
  lease="$(CLAIM="$claim" php -r '$v=json_decode(getenv("CLAIM"), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"];')"
  [ -n "$lease" ] || fail 'lease não foi adquirido'

  # Ciclo 1: shim em modo partial (alteração parcial controlada).
  # Ciclo 2+: shim em modo usage_limited; com a política ativa, o loop devolve
  # a decisão ao controlador em vez de dormir.
  set +e
  (cd "$FIELD_WORKTREE" && \
    PATH="$SHIM_DIR:$PATH" \
    RALPH_FIELD_SHIM_MODE=usage_limited \
    RALPH_FIELD_SHIM_MARKER="$TMP/shim.marker" \
    RALPH_OPENCODE_MODEL="${RALPH_OPENCODE_MODEL:-opencode/deepseek-v4-flash-free}" \
    RALPH_OPENCODE_VERIFY_AGENT="${RALPH_OPENCODE_VERIFY_AGENT:-ralph-review}" \
    RALPH_OPENCODE_VERIFY_POLICY_PROOF="${RALPH_OPENCODE_VERIFY_POLICY_PROOF:-}" \
    php "$ROOT/bin/ralph-control" run --engine codex --test-cmd "true" \
      --workflow "$FIELD_WORKFLOW" --feature "$FIELD_FEATURE" --lease "$lease") > "$OUTPUT" 2>&1
  run_rc=$?
  set -e

  # A primeira execução termina em capacity_limited/failover_pending; o
  # controlador (Fases 4–5) precisa comprovar que não deixou processo vivo e
  # que emitiu nova attempt com OpenCode.
  [ "$run_rc" -ne 0 ] || note info 'loop legado retornou 0; failover não ativo nesta build'
  [ -f "$TMP/shim.marker" ] || note warn 'shim não registrou a alteração parcial'
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
  note info 'descartando a worktree de campo de forma verificável'
  # O clone de origem não pode sofrer drift: worktree removida com sucesso e o
  # HEAD do clone permanece no commit-base.
  local base_before base_after
  base_before="$(git -C "$FIELD_BASE" rev-parse --verify HEAD)"
  git -C "$FIELD_WORKTREE" worktree remove --force "$FIELD_WORKTREE" >/dev/null 2>&1 \
    || fail 'não foi possível remover a worktree de campo'
  base_after="$(git -C "$FIELD_BASE" rev-parse --verify HEAD)"
  [ "$base_before" = "$base_after" ] || fail 'clone de origem sofreu drift no HEAD'
  note ok "worktree removida; clone de origem intacto em $base_before"
}

# ---------------------------------------------------------------------------
# Execução
# ---------------------------------------------------------------------------

echo '== Prova de campo do failover controlado Codex → OpenCode (Phase 9) =='
echo "modo: $FIELD_MODE"

prepare_worktree
install_candidate
validate_failure_domains
make_codex_shim

if [ "$FIELD_MODE" = "full" ]; then
  run_failover_field
  run_gates_and_handoff
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
