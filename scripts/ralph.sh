#!/usr/bin/env bash
#
# ralph.sh
#
# Orquestrador que le um documento de fases, quebra em fases, e alimenta cada
# uma ao Codex CLI ou Claude Code para implementacao automatica.
#
# Invariantes:
#   1. Cada fase E cada ciclo de correcao roda em sessao NOVA, com prompt
#      auto-contido. Nunca reutiliza sessao.
#   2. Zero perguntas. Do inicio ao fim sem interacao humana.
#   3. Fase so e "completa" quando passa por 4 gates mecanicos, nunca pelo
#      exit code do engine.
#   4. Limite de uso -> espera o reset e re-executa a MESMA fase, sem consumir
#      ciclo de correcao.
#   5. Um commit por fase concluida.
#
# Agnostico de stack: a fase e o CLAUDE.md/AGENTS.md do projeto definem
# linguagem, framework, comandos e convencoes.
#
# Uso:
#   ./ralph.sh [opcoes] [caminho-do-arquivo]
#
# Opcoes:
#   --engine codex|claude    engine de implementacao (default: codex)
#   --from N                 comeca na fase N (limpa do progresso as fases >= N)
#   --keep-going             continua apos uma fase falhar (default: para)
#   --max-cycles N           ciclos de correcao por fase (default: 3)
#   --no-verify              desliga o gate 3 (equivale a RALPH_VERIFY=off)
#   --test-cmd "<cmd>"       comando de teste do projeto (gate 2)
#
# Input (primeiro arquivo posicional). Sem argumento, resolve nesta ordem:
#   1. .spec/init/project-phases.md      (cadeia init)
#   2. .spec/project-phases.md           (repos pre-init, com aviso)
#
#   Um PHASES.md de feature tambem e input valido:
#     ./ralph.sh .spec/features/<slug>/PHASES.md
#
# Contrato de formato do input (validado no preflight):
#   - >= 1 heading `## Phase N: <titulo>`
#   - nenhum heading `## Phase ...` fora desse formato
#   - sub-fases em `### Phase N.M:` (nao viram sessao propria)
#   - qualquer outro `## ` encerra a captura da fase anterior
#
# Gates por fase (todos verdes -> commit; qualquer vermelho -> ciclo de correcao):
#   0. engine terminou de verdade (claude: is_error no JSON; codex: exit code)
#   1. a sessao escreveu codigo? SINAL, nao veredito — uma fase ja implementada
#      faz o engine (corretamente) nao escrever nada. Alimenta a causa do ciclo
#      de correcao quando um gate posterior reprova.
#   2. suite de testes do projeto, rodada PELO ralph (fora da sessao do agente)
#   3. sessao verificadora independente, read-only, task a task — o gate final,
#      roda em toda fase (RALPH_VERIFY=always, default). RALPH_VERIFY=auto
#      economiza: so roda quando o veredito do gate 2 nao basta — sessao que
#      nao escreveu nada (claim "ja implementada"), ciclo de correcao, ou
#      gate 2 desabilitado. --no-verify / RALPH_VERIFY=off desliga. No engine
#      claude o verificador usa Sonnet (RALPH_VERIFY_MODEL, default: sonnet)
#      com esforco high — e leitura + checklist.
#
# Gates verdes com a arvore limpa => a fase ja estava implementada em HEAD:
# marcada como feita, sem commit (nao ha o que commitar).
#
# Comando de teste (gate 2), primeira regra que resolver:
#   1. --test-cmd "<cmd>"
#   2. RALPH_TEST_CMD
#   3. deteccao por manifest:
#        Laravel Sail (artisan + vendor/bin/sail)  -> vendor/bin/sail test
#        composer.json com scripts.test            -> composer test
#        artisan                                   -> php artisan test
#        package.json com scripts.test             -> npm test
#        pytest.ini / pyproject [tool.pytest]      -> pytest
#        go.mod                                    -> go test ./...
#        Cargo.toml                                -> cargo test
#   4. nada resolvido -> aviso alto + gate 2 pulado (o gate 3 segura sozinho)
#
# Laravel Sail: a suite roda dentro do container, entao Sail tem precedencia
# sobre `composer test`. Containers parados -> abort no preflight (todo gate 2
# falharia, queimando ciclos de correcao).
#
# Variaveis de ambiente:
#   RALPH_TEST_CMD           comando de teste (gate 2); --test-cmd tem prioridade
#   RALPH_VERIFY             gate 3: always (default) | auto | off
#   RALPH_VERIFY_MODEL       modelo do verificador (sonnet no Claude; Luna no Codex)
#   RALPH_CLAUDE_VERIFY_EFFORT esforco do verificador Claude (default: high)
#   RALPH_CODEX_PROFILE      perfil do Codex (default: bc-harness)
#   RALPH_CODEX_MODEL        modelo Codex de implementacao (default: gpt-5.6-luna)
#   RALPH_CODEX_REASONING_EFFORT esforco Codex (default: high)
#   RALPH_MAX_CYCLES         ciclos de correcao por fase (default: 3)
#   RALPH_MAX_LIMIT_WAITS    esperas consecutivas por limite, por fase (default: 20)
#   RALPH_LIMIT_WAIT_DEFAULT fallback de espera em segundos (default: 1800)
#   RALPH_LIMIT_BUFFER       segundos extras apos o reset (default: 60)
#   RALPH_HOOK_TIMEOUT       segundos ate TERM no hook (default: 10)
#   RALPH_HOOK_KILL_AFTER    segundos adicionais ate KILL (default: 2)
#
# Exportadas para hooks (ex: notify-n8n.sh) durante cada sessao de engine:
#   RALPH_ENGINE             codex | claude
#   RALPH_PHASE_TITLE        titulo da fase corrente
#   RALPH_PHASE_NUM          numero da fase corrente
#   RALPH_PHASE_TOTAL        total de fases do run
#   RALPH_PHASE_ATTEMPT      ciclo corrente (1 = implementacao inicial)
#   RALPH_PHASE_MAX_ATTEMPTS igual a RALPH_MAX_CYCLES
#
# Hook de eventos:
#   RALPH_HOOK               executavel chamado a cada evento; se nao definido,
#                            usa ./scripts/ralph-hook.sh do repo-alvo se existir
#   Chamada: HOOK <evento> <detalhe>; eventos: run_start phase_start cycle_start
#   gate_fail phase_done phase_already_done phase_failed limit_wait run_end
#   Best-effort: hook ausente/lento/com erro nao derruba o run; TERM em 10s e
#   KILL 2s depois por default
#
# Feedback para o orquestrador externo:
#   RALPH_FEEDBACK_FILE    JSONL append-only; default: .git/ralph-control/feedback/events.jsonl
#   RALPH_FEEDBACK_STDOUT  1 publica `RALPH_FEEDBACK <json>` na tela
#   RALPH_FEEDBACK_CMD     executavel consumidor; recebe evento/detalhe e JSON em stdin
#   RALPH_RUN_ID            identificador externo opcional da execucao
#   O canal e somente observabilidade. Falha do consumidor nunca aprova gate,
#   altera estado ou interrompe o loop.
#
# Exit code: 0 = todas as fases verdes; 1 = alguma falhou ou abortou.
#
# Pre-requisitos:
#   - Codex: npm install -g @openai/codex + OPENAI_API_KEY
#   - Claude: npm install -g @anthropic-ai/claude-code + ANTHROPIC_API_KEY
#   - Raiz de um repo git, com a arvore de trabalho limpa

set -euo pipefail

ENGINE="codex"
INPUT_FILE=""
FROM_PHASE=0
KEEP_GOING=false
TEST_CMD_FLAG=""
MAX_CYCLES="${RALPH_MAX_CYCLES:-3}"
VERIFY_MODE="${RALPH_VERIFY:-always}"
VERIFY_MODEL=""
CODEX_PROFILE="${RALPH_CODEX_PROFILE:-bc-harness}"
CODEX_MODEL="${RALPH_CODEX_MODEL:-gpt-5.6-luna}"
CODEX_REASONING_EFFORT="${RALPH_CODEX_REASONING_EFFORT:-high}"
CLAUDE_VERIFY_EFFORT="${RALPH_CLAUDE_VERIFY_EFFORT:-high}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --engine)      ENGINE="$2"; shift 2 ;;
    --engine=*)    ENGINE="${1#*=}"; shift ;;
    --from)        FROM_PHASE="$2"; shift 2 ;;
    --from=*)      FROM_PHASE="${1#*=}"; shift ;;
    --max-cycles)  MAX_CYCLES="$2"; shift 2 ;;
    --max-cycles=*) MAX_CYCLES="${1#*=}"; shift ;;
    --test-cmd)    TEST_CMD_FLAG="$2"; shift 2 ;;
    --test-cmd=*)  TEST_CMD_FLAG="${1#*=}"; shift ;;
    --keep-going)  KEEP_GOING=true; shift ;;
    --no-verify)   VERIFY_MODE="off"; shift ;;
    -h|--help)     sed -n '2,70p' "$0"; exit 0 ;;
    *)             INPUT_FILE="$1"; shift ;;
  esac
done

PHASES_DIR=".phases"
LOG_DIR=".phases/logs"
PROMPT_DIR=".phases/prompts"
MANIFEST="$PHASES_DIR/manifest.txt"
PROGRESS_FILE="$PHASES_DIR/.progress"

MAX_LIMIT_WAITS="${RALPH_MAX_LIMIT_WAITS:-20}"
LIMIT_WAIT_DEFAULT="${RALPH_LIMIT_WAIT_DEFAULT:-1800}"
LIMIT_BUFFER="${RALPH_LIMIT_BUFFER:-60}"
HOOK_TIMEOUT="${RALPH_HOOK_TIMEOUT:-10}"
HOOK_KILL_AFTER="${RALPH_HOOK_KILL_AFTER:-2}"
FEEDBACK_FILE="${RALPH_FEEDBACK_FILE:-.git/ralph-control/feedback/events.jsonl}"
FEEDBACK_STDOUT="${RALPH_FEEDBACK_STDOUT:-0}"
FEEDBACK_CMD="${RALPH_FEEDBACK_CMD:-}"
FEEDBACK_TIMEOUT="${RALPH_FEEDBACK_TIMEOUT:-5}"
RUN_ID="${RALPH_RUN_ID:-run_$(date -u '+%Y%m%dT%H%M%SZ')_$$}"

TEST_CMD=""
SAIL_BIN=""
LIMIT_WAITS=0
HOOK_BIN=""
APPROVED_HEAD=""
APPROVED_PLAN_SIGNATURE=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()     { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $1"; }
success() { echo -e "${GREEN}[$(date '+%H:%M:%S')] $1${NC}"; }
warn()    { echo -e "${YELLOW}[$(date '+%H:%M:%S')] $1${NC}"; }
fail()    { echo -e "${RED}[$(date '+%H:%M:%S')] $1${NC}"; }

format_duration() {
  local total_seconds=$1
  local hours=$((total_seconds / 3600))
  local minutes=$(((total_seconds % 3600) / 60))
  local seconds=$((total_seconds % 60))

  if [ "$hours" -gt 0 ]; then
    printf "%dh %dm %ds" "$hours" "$minutes" "$seconds"
  elif [ "$minutes" -gt 0 ]; then
    printf "%dm %ds" "$minutes" "$seconds"
  else
    printf "%ds" "$seconds"
  fi
}

# ---------------------------------------------------------------------------
# Hook de eventos (opcional)
# ---------------------------------------------------------------------------

resolve_hook() {
  if [ -n "${RALPH_HOOK:-}" ]; then
    if [ -x "$RALPH_HOOK" ]; then
      HOOK_BIN="$RALPH_HOOK"
    else
      warn "RALPH_HOOK definido mas nao executavel: $RALPH_HOOK (ignorado)"
      return 0
    fi
  elif [ -x "./scripts/ralph-hook.sh" ]; then
    HOOK_BIN="$(pwd)/scripts/ralph-hook.sh"
  else
    return 0
  fi

  log "Hook de eventos: $HOOK_BIN"
}

feedback_escape() {
  local value="${1:-}"
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s' "$value"
}

feedback_redact() {
  local value="${1:-}" sanitized
  sanitized=$(printf '%s' "$value" | sed -E \
    -e 's/((token|secret|password|passwd|api[_-]?key)[[:space:]]*[=:][[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's/(sk-[A-Za-z0-9_-]{12,}|gh[pousr]_[A-Za-z0-9_]{20,})/[REDACTED]/g') || sanitized="$value"
  printf '%s' "$sanitized"
}

feedback_int_or_null() {
  if [[ "${1:-}" =~ ^[0-9]+$ ]]; then
    printf '%s' "$1"
  else
    printf 'null'
  fi
}

feedback_string_or_null() {
  if [ -n "${1:-}" ]; then
    printf '"%s"' "$(feedback_escape "$1")"
  else
    printf 'null'
  fi
}

feedback_state() {
  case "$1" in
    run_start|phase_start|cycle_start|gate_fail) printf 'running' ;;
    limit_wait) printf 'waiting' ;;
    phase_done|phase_already_done) printf 'completed' ;;
    phase_failed) printf 'blocked' ;;
    run_end)
      case "${2:-}" in
        FALHOU*|ABORTADO*) printf 'failed' ;;
        *) printf 'completed' ;;
      esac
      ;;
    *) printf 'running' ;;
  esac
}

feedback_health() {
  case "$1" in
    gate_fail|cycle_start|limit_wait) printf 'warning' ;;
    phase_failed|run_end)
      case "${2:-}" in
        FALHOU*|ABORTADO*|*falhou*) printf 'error' ;;
        *) printf 'ok' ;;
      esac
      ;;
    *) printf 'ok' ;;
  esac
}

feedback_percent() {
  local event="$1" phase_num="${RALPH_PHASE_NUM:-}" total="${RALPH_PHASE_TOTAL:-}" state="$2"
  if ! [[ "$phase_num" =~ ^[0-9]+$ && "$total" =~ ^[0-9]+$ && "$total" -gt 0 ]]; then
    [ "$state" = "completed" ] && printf '100' || printf '0'
    return 0
  fi

  local completed="$phase_num"
  if [ "$event" = "phase_start" ]; then
    completed=$((phase_num - 1))
  elif [ "$event" = "run_start" ]; then
    completed=0
  elif [ "$event" = "run_end" ] && [ "$state" = "completed" ]; then
    completed="$total"
  fi
  [ "$completed" -lt 0 ] && completed=0
  [ "$completed" -gt "$total" ] && completed="$total"
  printf '%s' "$((completed * 100 / total))"
}

feedback_payload() {
  local event="$1" detail="${2:-}"
  local state health percent
  state=$(feedback_state "$event" "$detail")
  health=$(feedback_health "$event" "$detail")
  percent=$(feedback_percent "$event" "$state")

  printf '{"schema_version":"1.0.0","run_id":"%s","workflow_id":%s,"feature_key":%s,"attempt":%s,"timestamp":"%s","event":"%s","state":"%s","health":"%s","engine":"%s","phase":{"number":%s,"total":%s,"title":"%s","attempt":%s},"progress":{"percent":%s},"detail":"%s","source":"ralph"}' \
    "$(feedback_escape "$(feedback_redact "$RUN_ID")")" \
    "$(feedback_string_or_null "${RALPH_WORKFLOW_ID:-}")" \
    "$(feedback_string_or_null "${RALPH_FEATURE_KEY:-}")" \
    "$(feedback_int_or_null "${RALPH_PHASE_ATTEMPT:-}")" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "$(feedback_escape "$event")" \
    "$(feedback_escape "$state")" \
    "$(feedback_escape "$health")" \
    "$(feedback_escape "$ENGINE")" \
    "$(feedback_int_or_null "${RALPH_PHASE_NUM:-}")" \
    "$(feedback_int_or_null "${RALPH_PHASE_TOTAL:-}")" \
    "$(feedback_escape "$(feedback_redact "${RALPH_PHASE_TITLE:-}")")" \
    "$(feedback_int_or_null "${RALPH_PHASE_ATTEMPT:-}")" \
    "$percent" \
    "$(feedback_escape "$(feedback_redact "$detail")")"
}

feedback_emit() {
  local event="$1" detail="${2:-}" payload callback_rc=0
  payload=$(feedback_payload "$event" "$detail")

  if [ -n "$FEEDBACK_FILE" ]; then
    local feedback_dir
    feedback_dir=$(dirname "$FEEDBACK_FILE")
    if mkdir -p "$feedback_dir" 2>/dev/null; then
      if command -v flock >/dev/null 2>&1; then
        (flock -x 9; printf '%s\n' "$payload" >&9) 9>>"$FEEDBACK_FILE" || true
      else
        printf '%s\n' "$payload" >>"$FEEDBACK_FILE" 2>/dev/null || true
      fi
    fi
  fi

  if [ "$FEEDBACK_STDOUT" = "1" ]; then
    printf 'RALPH_FEEDBACK %s\n' "$payload"
  fi

  if [ -n "$FEEDBACK_CMD" ]; then
    if [ -x "$FEEDBACK_CMD" ]; then
      if command -v timeout >/dev/null 2>&1; then
        printf '%s\n' "$payload" | timeout --kill-after=1s "${FEEDBACK_TIMEOUT}s" \
          "$FEEDBACK_CMD" "$event" "$detail" >/dev/null 2>&1 || callback_rc=$?
      else
        printf '%s\n' "$payload" | "$FEEDBACK_CMD" "$event" "$detail" >/dev/null 2>&1 || callback_rc=$?
      fi
      [ "$callback_rc" -eq 0 ] || warn "feedback: consumidor falhou no evento '$event' (ignorado)"
    else
      warn "RALPH_FEEDBACK_CMD definido mas nao executavel: $FEEDBACK_CMD (ignorado)"
    fi
  fi
}

emit() {
  local event="$1" detail="${2:-}"
  feedback_emit "$event" "$detail"

  [ -n "$HOOK_BIN" ] || return 0

  RALPH_EVENT="$event" \
  RALPH_EVENT_DETAIL="$detail" \
  RALPH_ENGINE="$ENGINE" \
  RALPH_PHASE_TITLE="${RALPH_PHASE_TITLE:-}" \
  RALPH_PHASE_NUM="${RALPH_PHASE_NUM:-}" \
  RALPH_PHASE_TOTAL="${RALPH_PHASE_TOTAL:-}" \
  RALPH_PHASE_ATTEMPT="${RALPH_PHASE_ATTEMPT:-}" \
  RALPH_PHASE_MAX_ATTEMPTS="$MAX_CYCLES" \
  RALPH_LOG_DIR="$LOG_DIR" \
  RALPH_INPUT_FILE="$INPUT_FILE" \
    timeout --kill-after="${HOOK_KILL_AFTER}s" "${HOOK_TIMEOUT}s" \
      "$HOOK_BIN" "$event" "$detail" >/dev/null 2>&1 \
    || warn "hook: evento '$event' falhou ou expirou (ignorado)"

  return 0
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------

resolve_input_file() {
  if [ -n "$INPUT_FILE" ]; then
    return 0
  fi

  if [ -f ".spec/init/project-phases.md" ]; then
    INPUT_FILE=".spec/init/project-phases.md"
  elif [ -f ".spec/project-phases.md" ]; then
    INPUT_FILE=".spec/project-phases.md"
    warn "Usando .spec/project-phases.md (layout pre-init). O padrao atual e .spec/init/project-phases.md."
  else
    fail "Nenhum documento de fases encontrado."
    fail "Esperado .spec/init/project-phases.md (rode /init:project-phases) ou passe o caminho como argumento."
    exit 1
  fi
}

validate_input_format() {
  local top_level
  top_level=$(grep -cE '^## Phase [0-9]+: ' "$INPUT_FILE" || true)

  if [ "$top_level" -lt 1 ]; then
    fail "Contrato de formato violado: nenhum heading '## Phase N: <titulo>' em $INPUT_FILE"
    fail "ralph quebra o documento por esse heading. Corrija o documento antes de rodar."
    exit 1
  fi

  local malformed
  malformed=$(grep -E '^## Phase' "$INPUT_FILE" | grep -vE '^## Phase [0-9]+: ' || true)
  if [ -n "$malformed" ]; then
    fail "Contrato de formato violado: headings '## Phase' fora do formato '## Phase N: <titulo>':"
    printf '    %s\n' "${malformed//$'\n'/$'\n    '}"
    fail "Uma fase com heading torto some silenciosamente do run. Corrija antes de gastar tokens."
    exit 1
  fi

  if [ "$VERIFY_MODE" != "off" ]; then
    local phases_without_tasks
    phases_without_tasks=$(awk '
      /^## Phase [0-9]+: / {
        if (phase != "" && tasks == 0) print phase
        phase = $0
        tasks = 0
        next
      }
      /^## / {
        if (phase != "" && tasks == 0) print phase
        phase = ""
        tasks = 0
        next
      }
      phase != "" && /^[[:space:]]*- \[[ xX]\]/ { tasks++ }
      END { if (phase != "" && tasks == 0) print phase }
    ' "$INPUT_FILE")

    if [ -n "$phases_without_tasks" ]; then
      fail "Contrato de verificacao violado: toda fase precisa de ao menos uma task checkbox:"
      printf '    %s\n' "${phases_without_tasks//$'\n'/$'\n    '}"
      fail "Use '- [ ]' em PHASES.md ou desative conscientemente o gate 3 com --no-verify."
      exit 1
    fi
  fi

  log "Formato do input OK ($top_level fases declaradas)"
}

exclude_phases_dir() {
  local exclude_file
  exclude_file="$(git rev-parse --git-dir)/info/exclude"
  mkdir -p "$(dirname "$exclude_file")"
  if ! grep -qxF '/.phases/' "$exclude_file" 2>/dev/null; then
    echo '/.phases/' >> "$exclude_file"
    log "Registrado /.phases/ em .git/info/exclude (nao mexe no .gitignore do projeto)"
  fi
}

# Laravel Sail: a suite roda DENTRO do container. Rodar `composer test` /
# `php artisan test` no host falha (sem PHP, sem banco, sem rede do compose).
# Ecoa o caminho do binario sail quando o projeto usa Sail.
detect_sail() {
  [ -f artisan ] || return 1
  if [ -x vendor/bin/sail ]; then
    echo "vendor/bin/sail"
    return 0
  fi
  # Sail declarado no composer.json mas vendor/ ainda nao instalado.
  if [ -f composer.json ] && grep -qF 'laravel/sail' composer.json; then
    echo "vendor/bin/sail"
    return 0
  fi
  return 1
}

# Containers de pe? O wrapper do sail imprime "Sail is not running." e sai != 0.
sail_running() {
  local out rc=0
  out=$("$SAIL_BIN" ps 2>&1) || rc=$?
  grep -qiF 'is not running' <<< "$out" && return 1
  [ "$rc" -ne 0 ] && return 1
  grep -qiE '(^|[[:space:]])(Up|running)([[:space:]]|$)' <<< "$out"
}

# O comando de teste invoca o sail? Olha o executavel (1o token), nao a string
# inteira: um caminho como /tmp/sail-fixture/test.sh nao usa sail.
test_cmd_uses_sail() {
  local first="${TEST_CMD%% *}"
  [ "$(basename -- "$first")" = "sail" ]
}

# Gate 2 so tem valor se rodar de verdade. Sail com containers parados falha
# toda fase e queima ciclos de correcao inuteis — aborta antes da 1a sessao.
check_sail_running() {
  [ -n "$SAIL_BIN" ] || return 0
  test_cmd_uses_sail || return 0

  if [ ! -x "$SAIL_BIN" ]; then
    fail "Laravel Sail detectado, mas $SAIL_BIN nao existe."
    fail "Rode a instalacao de dependencias do projeto (ex: composer install) antes."
    exit 1
  fi

  if ! sail_running; then
    fail "Laravel Sail detectado, mas os containers nao estao de pe."
    fail "A suite de testes (gate 2) roda dentro do container e falharia em toda fase."
    fail "Suba o ambiente antes de rodar o ralph:"
    fail "    $SAIL_BIN up -d"
    exit 1
  fi

  log "Sail: containers de pe"
}

resolve_test_cmd() {
  SAIL_BIN="$(detect_sail || true)"

  if [ -n "$TEST_CMD_FLAG" ]; then
    TEST_CMD="$TEST_CMD_FLAG"
    log "Gate 2 — comando de teste (--test-cmd): $TEST_CMD"
    check_sail_running
    return 0
  fi

  if [ -n "${RALPH_TEST_CMD:-}" ]; then
    TEST_CMD="$RALPH_TEST_CMD"
    log "Gate 2 — comando de teste (RALPH_TEST_CMD): $TEST_CMD"
    check_sail_running
    return 0
  fi

  # Sail vem ANTES de composer/npm: num projeto Laravel dockerizado o host nao
  # tem PHP nem acesso ao banco, e `composer test` mentiria como gate.
  if [ -n "$SAIL_BIN" ]; then
    TEST_CMD="$SAIL_BIN test"
  elif [ -f composer.json ] && grep -qE '"test"[[:space:]]*:' composer.json; then
    TEST_CMD="composer test"
  elif [ -f artisan ]; then
    TEST_CMD="php artisan test"
  elif [ -f package.json ] && grep -qE '"test"[[:space:]]*:' package.json; then
    TEST_CMD="npm test"
  elif [ -f pytest.ini ] || { [ -f pyproject.toml ] && grep -qF '[tool.pytest' pyproject.toml; }; then
    TEST_CMD="pytest"
  elif [ -f go.mod ]; then
    TEST_CMD="go test ./..."
  elif [ -f Cargo.toml ]; then
    TEST_CMD="cargo test"
  fi

  if [ -n "$TEST_CMD" ]; then
    log "Gate 2 — comando de teste (detectado): $TEST_CMD"
    check_sail_running
  else
    warn "Gate 2 DESABILITADO: nenhum comando de teste resolvido."
    if [ "$VERIFY_MODE" = "off" ]; then
      warn "--no-verify tambem desligou o gate 3: NENHUMA validacao mecanica ativa."
    else
      warn "Passe --test-cmd '<cmd>' ou defina RALPH_TEST_CMD. O gate 3 (verificador) roda em toda fase."
    fi
  fi
}

preflight_checks() {
  if [[ "$ENGINE" != "codex" && "$ENGINE" != "claude" ]]; then
    fail "Engine invalida: $ENGINE. Use 'codex' ou 'claude'."
    exit 1
  fi

  if ! [[ "$FROM_PHASE" =~ ^[0-9]+$ ]]; then
    fail "Valor invalido para --from: '$FROM_PHASE'. Use um numero inteiro (ex: --from 5)."
    exit 1
  fi

  if ! [[ "$MAX_CYCLES" =~ ^[0-9]+$ ]] || [ "$MAX_CYCLES" -lt 1 ]; then
    fail "Valor invalido para --max-cycles: '$MAX_CYCLES'. Use um inteiro >= 1."
    exit 1
  fi

  case "$VERIFY_MODE" in
    auto|always|off) ;;
    *)
      fail "Valor invalido para RALPH_VERIFY: '$VERIFY_MODE'. Use auto, always ou off."
      exit 1
      ;;
  esac

  if ! [[ "$HOOK_TIMEOUT" =~ ^[1-9][0-9]*$ ]] || ! [[ "$HOOK_KILL_AFTER" =~ ^[1-9][0-9]*$ ]]; then
    fail "RALPH_HOOK_TIMEOUT e RALPH_HOOK_KILL_AFTER devem ser inteiros >= 1."
    exit 1
  fi

  if [[ "$ENGINE" == "codex" ]]; then
    case "$CODEX_REASONING_EFFORT" in
      minimal|low|medium|high|xhigh) ;;
      *)
        fail "RALPH_CODEX_REASONING_EFFORT invalido: '$CODEX_REASONING_EFFORT'."
        fail "Use minimal, low, medium, high ou xhigh."
        exit 1
        ;;
    esac
  else
    case "$CLAUDE_VERIFY_EFFORT" in
      low|medium|high|xhigh|max) ;;
      *)
        fail "RALPH_CLAUDE_VERIFY_EFFORT invalido: '$CLAUDE_VERIFY_EFFORT'."
        fail "Use low, medium, high, xhigh ou max."
        exit 1
        ;;
    esac
  fi

  # O modelo de verificacao e explicito por engine, com override opcional.
  if [ -n "${RALPH_VERIFY_MODEL:-}" ]; then
    VERIFY_MODEL="$RALPH_VERIFY_MODEL"
  elif [[ "$ENGINE" == "claude" ]]; then
    VERIFY_MODEL="sonnet"
  else
    VERIFY_MODEL="$CODEX_MODEL"
  fi

  if ! command -v "$ENGINE" &> /dev/null; then
    if [[ "$ENGINE" == "codex" ]]; then
      fail "codex CLI nao encontrado. Instale com: npm install -g @openai/codex"
    else
      fail "Claude Code CLI nao encontrado. Instale com: npm install -g @anthropic-ai/claude-code"
    fi
    exit 1
  fi

  if ! git rev-parse --is-inside-work-tree &> /dev/null 2>&1; then
    fail "Requer um repositorio git."
    exit 1
  fi

  resolve_input_file

  if [ ! -f "$INPUT_FILE" ]; then
    fail "Arquivo nao encontrado: $INPUT_FILE"
    exit 1
  fi

  validate_input_format
  exclude_phases_dir

  # Arvore limpa: 'git add -A' da primeira fase engoliria trabalho nao commitado.
  if [ -n "$(git status --porcelain)" ]; then
    fail "Arvore de trabalho suja. ralph commita por fase e engoliria suas mudancas."
    fail "Commite ou stashe antes de rodar:"
    git status --short | sed 's/^/    /'
    exit 1
  fi

  resolve_test_cmd
  resolve_hook

  success "Pre-checks OK (engine: $ENGINE, input: $INPUT_FILE)"
}

# ---------------------------------------------------------------------------
# Split + progresso
# ---------------------------------------------------------------------------

manifest_entries() { grep -v '^#' "$MANIFEST" || true; }

split_phases() {
  log "Quebrando $INPUT_FILE em fases..."

  local new_stamp old_stamp="" progress_backup=""
  new_stamp="$(basename "$INPUT_FILE")@sha256:$(sha256sum "$INPUT_FILE" | cut -c1-12)"

  if [ -f "$MANIFEST" ]; then
    old_stamp=$(sed -n '1s/^# stamp: //p' "$MANIFEST")
  fi
  if [ -f "$PROGRESS_FILE" ]; then
    progress_backup=$(cat "$PROGRESS_FILE")
  fi

  rm -rf "$PHASES_DIR"
  mkdir -p "$PHASES_DIR" "$LOG_DIR" "$PROMPT_DIR"

  # Progresso sobrevive entre execucoes, mas so vale para o MESMO input.
  if [ -n "$progress_backup" ]; then
    if [ -n "$old_stamp" ] && [ "$old_stamp" = "$new_stamp" ]; then
      printf '%s\n' "$progress_backup" > "$PROGRESS_FILE"
      log "Progresso anterior preservado (input inalterado)"
    else
      warn "O documento de fases mudou desde a ultima execucao — progresso zerado."
      warn "Fases marcadas como feitas pertenciam a outro plano."
    fi
  fi

  echo "# stamp: $new_stamp" > "$MANIFEST"

  local current_file=""
  local phase_count=0

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" =~ ^##[[:space:]]+Phase[[:space:]]+([0-9]+):[[:space:]]*(.*)$ ]]; then
      phase_count=$((phase_count + 1))

      local phase_num="${BASH_REMATCH[1]}"
      local phase_title="${BASH_REMATCH[2]}"
      phase_title="${phase_title%"${phase_title##*[![:space:]]}"}"

      local slug
      slug=$(printf 'phase-%02d' "$phase_num")

      current_file="$PHASES_DIR/${slug}.md"
      echo "$line" > "$current_file"
      echo "${slug}.md|${phase_num}|${phase_title}" >> "$MANIFEST"
      continue
    fi

    # Heading nivel 2 que nao e "## Phase N:" (ex: "## Open Questions"):
    # encerra a captura para nao vazar a secao para a ultima fase.
    if [[ "$line" =~ ^##[[:space:]] ]]; then
      current_file=""
      continue
    fi

    if [ -n "$current_file" ]; then
      echo "$line" >> "$current_file"
    fi
  done < "$INPUT_FILE"

  success "$phase_count fases extraidas"
}

is_phase_done() {
  local phase_file="$1"
  [ -f "$PROGRESS_FILE" ] && grep -qxF "$phase_file" "$PROGRESS_FILE"
}

mark_phase_done() {
  echo "$1" >> "$PROGRESS_FILE"
}

# --from N tambem limpa do progresso as fases >= N (re-rodar de proposito).
apply_from_override() {
  [ "$FROM_PHASE" -gt 1 ] || return 0
  [ -f "$PROGRESS_FILE" ] || return 0

  local kept="" file num _rest
  while IFS='|' read -r file num _rest; do
    if [ "$num" -lt "$FROM_PHASE" ] && grep -qxF "$file" "$PROGRESS_FILE"; then
      kept+="$file"$'\n'
    fi
  done < <(manifest_entries)

  printf '%s' "$kept" > "$PROGRESS_FILE"
  log "--from $FROM_PHASE: progresso das fases >= $FROM_PHASE limpo"
}

# ---------------------------------------------------------------------------
# Prompts (auto-contidos — cada sessao e nova)
# ---------------------------------------------------------------------------

context_preamble() {
  cat <<'PREAMBLE'
## Descubra a stack e as convencoes antes de escrever codigo
Este projeto pode ser de qualquer linguagem ou framework. NAO assuma nenhuma
stack. Antes de comecar, LEIA os que existirem, nesta ordem:
1. AGENTS.md ou CLAUDE.md — convencoes, comandos e regras do projeto
2. .spec/init/project-description.md — descricao geral do projeto
3. .spec/init/user-stories.md — user stories
4. .spec/init/database-schema.md — modelo de dados
5. os documentos citados no proprio texto da fase (ex: SPEC.md/PLAN.md da feature)
Use os comandos de build, teste e execucao definidos por esses documentos e pelo
tooling ja presente no repositorio. Se o projeto tiver uma ferramenta de memoria
ou contexto configurada, use-a para entender o historico.
PREAMBLE

  # O gate 2 roda ESTE comando. Se o agente rodar outro (ex: `php artisan test`
  # no host de um projeto Sail), ele ve verde e o gate ve vermelho.
  if [ -n "$TEST_CMD" ]; then
    echo
    echo "## Comando de teste deste projeto"
    echo "Rode a suite SEMPRE com:"
    echo
    echo "    $TEST_CMD"
    echo
    echo "Este e o comando exato usado para validar a fase. Nao use outro runner"
    echo "nem rode os testes por fora dele."
    if [ -n "$SAIL_BIN" ]; then
      echo "O projeto usa Laravel Sail: artisan, composer, php e testes rodam DENTRO"
      echo "do container, via '$SAIL_BIN <cmd>'. Nunca rode essas ferramentas no host."
    fi
  fi
}

build_impl_prompt() {
  local phase_file="$1" cycle="$2"
  local prompt_file="$PROMPT_DIR/${phase_file%.md}.cycle-${cycle}.txt"

  {
    echo "Voce e um desenvolvedor senior implementando uma fase deste projeto."
    echo
    context_preamble
    cat <<'TASK'

## Sua tarefa agora
Implemente COMPLETAMENTE a fase descrita abaixo.

Para cada item:
1. Implemente o codigo completo (nao deixe TODOs ou placeholders)
2. Crie os testes listados, seguindo o framework de testes do projeto
3. Rode os testes com o comando de teste do projeto
4. Se um teste falhar, corrija o codigo e rode novamente
5. So passe pro proximo item quando os testes passarem

## Regras obrigatorias
- Use SEMPRE os comandos, o runner de testes e as ferramentas ja adotados pelo
  projeto (nao introduza uma stack ou ferramenta nova por conta propria)
- Nao altere SPEC.md, PLAN.md, PHASES.md nem qualquer arquivo sob .spec/: esses
  artefatos aprovados autorizam a execucao e nao podem ser reescritos pelo executor
- Nao crie commits: o ralph.sh e o unico dono do commit por fase
- Testes e fixtures/factories devem criar todas as dependencias necessarias
- Nomes de classes, arquivos e metodos devem seguir EXATAMENTE o que esta descrito
- Nao pule nenhum item marcado com [ ]
- Ao final, valide que toda a suite de testes da fase passa

## Fase a implementar
TASK
    cat "$PHASES_DIR/$phase_file"
  } > "$prompt_file"

  echo "$prompt_file"
}

# Prompt de correcao: auto-contido. Carrega a fase inteira + a causa REAL
# da falha (nunca "os testes falharam" generico).
build_fix_prompt() {
  local phase_file="$1" cycle="$2" gate="$3" cause="$4"
  local prompt_file="$PROMPT_DIR/${phase_file%.md}.cycle-${cycle}.txt"

  {
    echo "Voce e um desenvolvedor senior corrigindo uma fase parcialmente implementada."
    echo
    context_preamble
    cat <<'INTRO'

## Situacao
Uma sessao anterior tentou implementar a fase abaixo e NAO passou na verificacao.
Voce esta numa sessao nova: nao tem memoria do que foi feito. Leia o codigo atual
antes de mudar qualquer coisa.

## Regras obrigatorias
- Corrija APENAS o que falta. Nao reimplemente o que ja esta correto e testado.
- Restaure qualquer mudanca acidental em SPEC.md, PLAN.md, PHASES.md ou .spec/;
  o executor nao pode alterar a autoridade de planejamento.
- Nao crie commits: o ralph.sh e o unico dono do commit por fase.
- Nao deixe TODOs, placeholders ou testes pulados.
- Rode a suite de testes do projeto ao final e garanta que ela passa.
INTRO
    echo
    echo "## Motivo da falha ($gate)"
    echo '```'
    echo "$cause"
    echo '```'
    echo
    echo "## Fase a completar"
    cat "$PHASES_DIR/$phase_file"
  } > "$prompt_file"

  echo "$prompt_file"
}

build_verify_prompt() {
  local phase_file="$1" cycle="$2"
  local prompt_file="$PROMPT_DIR/${phase_file%.md}.verify-${cycle}.txt"

  {
    cat <<'VERIFY'
RALPH_VERIFY

Voce e um verificador independente. NAO escreva, edite ou crie nenhum arquivo.
Seu unico trabalho e ler o codigo real e dizer o que esta feito e o que nao esta.

Para CADA task marcada com `- [ ]` ou `- [x]` na fase abaixo, na ordem em que
aparecem, confira os acceptance criteria contra o codigo real (arquivos, classes,
testes, rotas, migrations — o que a task exigir) e emita EXATAMENTE UMA linha:

TASK <n>: DONE
TASK <n>: INCOMPLETE — <o que falta>

Regras:
- <n> e o indice da task na fase, comecando em 1.
- Uma linha TASK para cada task, sem excecao, sem agrupar.
- Nao emita nenhum outro texto alem das linhas TASK.
- Codigo ausente, TODO, placeholder ou teste faltando => INCOMPLETE.
- Na duvida, INCOMPLETE.

## Fase a verificar
VERIFY
    cat "$PHASES_DIR/$phase_file"
  } > "$prompt_file"

  echo "$prompt_file"
}

# ---------------------------------------------------------------------------
# Limite de uso (item 5) — so olha o FIM do log, com padroes por engine
# ---------------------------------------------------------------------------

# Ecoa o epoch de reset se encontrado, "0" para limite sem horario.
# Retorna 0 quando detecta limite, 1 quando nao ha limite.
detect_usage_limit() {
  local log_file="$1"
  local tail_txt pattern epoch

  # A mensagem de limite sai no FIM da execucao. Olhar o log inteiro faz output
  # de teste do projeto ("429", "Too Many Requests") disparar espera de 30min.
  tail_txt=$(tail -n 20 "$log_file" 2>/dev/null || true)

  if [[ "$ENGINE" == "claude" ]]; then
    pattern='usage limit reached'
  else
    pattern='rate limit reached|quota exceeded|usage limit reached'
  fi

  grep -qiE "$pattern" <<< "$tail_txt" || return 1

  epoch=$(grep -oiE 'usage limit reached[^0-9]*[0-9]{10,13}' <<< "$tail_txt" \
    | grep -oE '[0-9]{10,13}' | tail -1 || true)

  if [ -z "$epoch" ]; then
    epoch=$(grep -oiE 'reset[a-z ]*[0-9]{10,13}' <<< "$tail_txt" \
      | grep -oE '[0-9]{10,13}' | tail -1 || true)
  fi

  echo "${epoch:-0}"
  return 0
}

wait_for_reset() {
  local epoch="$1"
  local now wait_secs
  now=$(date +%s)

  LIMIT_WAITS=$((LIMIT_WAITS + 1))
  if [ "$LIMIT_WAITS" -gt "$MAX_LIMIT_WAITS" ]; then
    fail "Limite de uso atingido $LIMIT_WAITS vezes seguidas nesta fase (cap: $MAX_LIMIT_WAITS)."
    fail "Abortando em vez de dormir indefinidamente."
    emit run_end "ABORTADO — limite de uso atingido $LIMIT_WAITS vezes na mesma fase"
    exit 1
  fi

  emit limit_wait "espera $LIMIT_WAITS/$MAX_LIMIT_WAITS por reset de limite em '${RALPH_PHASE_TITLE:-fase}'"

  if [[ "$epoch" =~ ^[0-9]+$ ]] && [ "$epoch" -gt 0 ]; then
    if [ "${#epoch}" -ge 13 ]; then
      epoch=$((epoch / 1000))
    fi
    wait_secs=$((epoch - now + LIMIT_BUFFER))
    if [ "$wait_secs" -lt "$LIMIT_BUFFER" ]; then
      wait_secs=$LIMIT_BUFFER
    fi
    warn "Limite de uso atingido. Reset previsto para $(date -d "@$epoch" '+%d/%m %H:%M:%S')."
  else
    wait_secs=$LIMIT_WAIT_DEFAULT
    warn "Limite de uso atingido. Sem horario de reset no output; aguardando fallback."
  fi

  warn "Espera $LIMIT_WAITS/$MAX_LIMIT_WAITS — aguardando $(format_duration "$wait_secs") ate retomar a MESMA fase..."

  local remaining=$wait_secs chunk
  while [ "$remaining" -gt 0 ]; do
    chunk=60
    [ "$remaining" -lt 60 ] && chunk=$remaining
    sleep "$chunk"
    remaining=$((remaining - chunk))
    [ "$remaining" -gt 0 ] && log "Retomando em $(format_duration "$remaining")..."
  done

  success "Reset provavelmente concluido. Retomando execucao."
}

# ---------------------------------------------------------------------------
# Engine
# ---------------------------------------------------------------------------

# run_engine <prompt_file> <log_file> <mode: impl|verify>
# Loop de resiliencia a limite de uso: nao consome ciclo de correcao.
run_engine() {
  local prompt_file="$1" log_file="$2" mode="$3"

  export RALPH_ENGINE="$ENGINE"
  export RALPH_PHASE_MAX_ATTEMPTS="$MAX_CYCLES"

  local model_args=()
  if [[ "$mode" == "verify" ]] && [ -n "$VERIFY_MODEL" ]; then
    model_args=(--model "$VERIFY_MODEL")
  fi

  while true; do
    local rc=0

    if [[ "$ENGINE" == "codex" ]]; then
      local session_model="$CODEX_MODEL"
      [[ "$mode" == "verify" ]] && session_model="$VERIFY_MODEL"

      if [[ "$mode" == "verify" ]]; then
        codex --profile "$CODEX_PROFILE" exec --ephemeral \
          --model "$session_model" \
          -c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"" \
          --dangerously-bypass-hook-trust \
          --sandbox read-only - < "$prompt_file" 2>&1 | tee "$log_file" || rc=$?
      else
        codex --profile "$CODEX_PROFILE" exec --ephemeral \
          --model "$session_model" \
          -c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"" \
          --dangerously-bypass-hook-trust \
          --dangerously-bypass-approvals-and-sandbox - \
          < "$prompt_file" 2>&1 | tee "$log_file" || rc=$?
      fi
    else
      # < /dev/null: claude -p le stdin quando nao e TTY. Sem o redirect ele
      # consome o stream de quem chamou (ex: o manifest do loop de fases).
      if [[ "$mode" == "verify" ]]; then
        env -u CLAUDECODE claude --dangerously-skip-permissions \
          "${model_args[@]}" \
          --effort "$CLAUDE_VERIFY_EFFORT" \
          -p "$(cat "$prompt_file")" \
          --allowedTools "Read,Glob,Grep" \
          --output-format text < /dev/null 2>&1 | tee "$log_file" || rc=$?
      else
        # JSON: o exit code do CLI e sinal fraco; o gate 0 le is_error.
        env -u CLAUDECODE claude --dangerously-skip-permissions \
          -p "$(cat "$prompt_file")" \
          --output-format json < /dev/null 2>&1 | tee "$log_file" || rc=$?
      fi
    fi

    local reset_epoch
    if reset_epoch=$(detect_usage_limit "$log_file"); then
      wait_for_reset "$reset_epoch"
      continue
    fi

    return "$rc"
  done
}

# ---------------------------------------------------------------------------
# Gates
# ---------------------------------------------------------------------------

# Gate 0 — o engine terminou de verdade?
# Preenche GATE_CAUSE quando vermelho.
GATE_CAUSE=""

gate0_engine_finished() {
  local log_file="$1" rc="$2"

  if [[ "$ENGINE" == "claude" ]]; then
    if ! grep -qF '"type":"result"' "$log_file" && ! grep -qF '"type": "result"' "$log_file"; then
      GATE_CAUSE="O engine terminou sem emitir um resultado. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
      return 1
    fi
    if grep -qE '"is_error"[[:space:]]*:[[:space:]]*true' "$log_file"; then
      GATE_CAUSE="O engine reportou is_error=true. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
      return 1
    fi
  fi

  if [ "$rc" -ne 0 ]; then
    GATE_CAUSE="O engine saiu com codigo $rc. Ultimas linhas do output:"$'\n'"$(tail -n 40 "$log_file")"
    return 1
  fi

  return 0
}

# Assinatura da arvore: rastreados (status + diff) e nao-rastreados (conteudo).
# Sem mutar o index.
tree_signature() {
  {
    git status --porcelain
    git diff HEAD
    git ls-files --others --exclude-standard -z | xargs -0 -r sha256sum 2> /dev/null
  } 2> /dev/null | sha256sum | cut -c1-16
}

# A fase executa um plano aprovado; nao pode reescrever a propria autoridade.
# Inclui o input mesmo quando ele vive fora de .spec/.
planning_signature() {
  {
    if [ -f "$INPUT_FILE" ]; then
      sha256sum "$INPUT_FILE"
    else
      printf 'MISSING %s\n' "$INPUT_FILE"
    fi
    if [ -d .spec ]; then
      find .spec -type f -print0 | sort -z | xargs -0 -r sha256sum
    fi
  } 2>/dev/null | sha256sum | cut -c1-16
}

refresh_approved_authority() {
  APPROVED_HEAD=$(git rev-parse HEAD)
  APPROVED_PLAN_SIGNATURE=$(planning_signature)
}

guard_execution_authority() {
  local stage="$1"
  local current_head
  current_head=$(git rev-parse HEAD)

  if [ "$current_head" != "$APPROVED_HEAD" ]; then
    LAST_GATE="guardrail — HEAD alterado fora do ralph"
    GATE_CAUSE="HEAD mudou durante $stage. O ralph precisa ser o unico dono dos commits da fase; esperado $APPROVED_HEAD, encontrado $current_head."
    return 1
  fi

  if [ "$(planning_signature)" != "$APPROVED_PLAN_SIGNATURE" ]; then
    LAST_GATE="guardrail — plano aprovado alterado"
    GATE_CAUSE="O input ou arquivos sob .spec/ mudaram durante $stage. Restaure integralmente os artefatos aprovados; execucao, testes, verificadores e hooks nao podem reautorizar o plano."
    return 1
  fi

  return 0
}

# Gate 1 — esta sessao escreveu codigo?
#
# SINAL, nao veredito. Uma fase pode ja estar implementada antes da sessao
# (tasks `[x]`, run anterior commitada, dev implementou a mao). Nesse caso o
# engine correto NAO escreve nada, e reprovar aqui seria um falso negativo:
# so os gates 2 e 3 sabem se o codigo esta completo.
#
# O retorno alimenta a causa do ciclo de correcao ("a sessao nao escreveu
# nada") quando algum gate posterior reprova.
gate1_session_wrote() {
  local sig_before="$1"
  [ "$(tree_signature)" != "$sig_before" ]
}

# Gate 2 — a suite do projeto passa, rodada PELO ralph (fora da sessao do agente)?
gate2_tests_pass() {
  local test_log="$1"

  if [ -z "$TEST_CMD" ]; then
    return 0
  fi

  log "Gate 2 — rodando a suite do projeto: $TEST_CMD"
  local rc=0
  # < /dev/null: sail test (docker compose exec) anexa stdin e consumiria o
  # stream de quem chamou, alem de poder travar esperando input.
  bash -c "$TEST_CMD" < /dev/null > "$test_log" 2>&1 || rc=$?

  if [ "$rc" -ne 0 ]; then
    GATE_CAUSE="O comando de teste do projeto ('$TEST_CMD') falhou com codigo $rc. Saida:"$'\n'"$(tail -n 200 "$test_log")"
    return 1
  fi

  success "Gate 2 — suite verde"
  return 0
}

# Gate 3 — sessao verificadora independente, read-only, task a task.
# O gate final: roda em toda fase por default (always). Modo auto economiza,
# rodando so quando o veredito do gate 2 nao basta:
#   - a sessao nao escreveu nada (claim "ja implementada" — so a verificacao
#     independente confirma isso sem confiar na palavra do engine)
#   - ciclo de correcao (a fase ja reprovou uma vez)
#   - gate 2 desabilitado (sem suite, o verificador e o unico gate)
# GATE3_RAN diz ao caminho "ja implementada" quais gates de fato validaram HEAD.
GATE3_RAN=0

gate3_independent_verify() {
  local phase_file="$1" cycle="$2" session_wrote="$3"
  local verify_log="$LOG_DIR/${phase_file%.md}.verify-${cycle}.log"

  GATE3_RAN=0

  case "$VERIFY_MODE" in
    off)
      log "Gate 3 pulado (--no-verify)"
      return 0
      ;;
    auto)
      if [ "$cycle" -eq 1 ] && [ "$session_wrote" -eq 1 ] && [ -n "$TEST_CMD" ]; then
        log "Gate 3 pulado: a sessao escreveu codigo e a suite passou (RALPH_VERIFY=always para rodar sempre)"
        return 0
      fi
      ;;
  esac

  local expected
  expected=$(grep -cE '^[[:space:]]*- \[[ xX]\]' "$PHASES_DIR/$phase_file" || true)

  if [ "$expected" -eq 0 ]; then
    GATE_CAUSE="A fase nao declara nenhuma task checkbox; o verificador nao tem contrato task a task."
    return 1
  fi

  GATE3_RAN=1
  log "Gate 3 — sessao verificadora independente ($expected tasks${VERIFY_MODEL:+, modelo: $VERIFY_MODEL})"

  local prompt_file verify_rc=0
  prompt_file=$(build_verify_prompt "$phase_file" "$cycle")
  run_engine "$prompt_file" "$verify_log" verify || verify_rc=$?

  if [ "$verify_rc" -ne 0 ]; then
    GATE_CAUSE="O processo verificador saiu com codigo $verify_rc; linhas TASK parciais nao sao confiaveis. Ultimas linhas:"$'\n'"$(tail -n 40 "$verify_log")"
    return 1
  fi

  local task_lines
  task_lines=$(sed -E \
    -e 's/\r$//' \
    -e 's/^[[:space:]]*(#{1,6}[[:space:]]+|[-*+][[:space:]]+)?//' \
    -e 's/\*\*//g' \
    -e 's/`//g' \
    "$verify_log" \
    | sed -nE 's/^[[:space:]]*(TASK [0-9]+: (DONE|INCOMPLETE)([[:space:]]*[—-].*)?)[[:space:]]*$/\1/p' \
    || true)

  local parsed
  parsed=$(printf '%s\n' "$task_lines" | grep -c . || true)

  if [ "$parsed" -eq 0 ]; then
    GATE_CAUSE="O verificador independente nao emitiu nenhuma linha 'TASK <n>: DONE|INCOMPLETE' — nao foi possivel confirmar que a fase esta completa. Ultimas linhas do verificador:"$'\n'"$(tail -n 40 "$verify_log")"
    return 1
  fi

  local canonical="" errors="" task_num lines statuses status_count status
  for task_num in $(seq 1 "$expected"); do
    lines=$(printf '%s\n' "$task_lines" | grep -E "^TASK ${task_num}: " || true)
    if [ -z "$lines" ]; then
      errors+="TASK $task_num ausente"$'\n'
      continue
    fi

    statuses=$(printf '%s\n' "$lines" | sed -nE 's/^TASK [0-9]+: (DONE|INCOMPLETE).*/\1/p' | sort -u)
    status_count=$(printf '%s\n' "$statuses" | grep -c . || true)
    if [ "$status_count" -ne 1 ]; then
      errors+="TASK $task_num recebeu vereditos conflitantes"$'\n'
      continue
    fi

    status=$(printf '%s\n' "$statuses" | head -n 1)
    canonical+="$(printf '%s\n' "$lines" | grep -m 1 -E "^TASK ${task_num}: ${status}")"$'\n'
  done

  local extra_ids
  extra_ids=$(printf '%s\n' "$task_lines" \
    | sed -nE 's/^TASK ([0-9]+):.*/\1/p' \
    | awk -v max="$expected" '$1 < 1 || $1 > max' \
    | sort -nu)
  if [ -n "$extra_ids" ]; then
    errors+="IDs fora do intervalo 1..$expected: $(tr '\n' ' ' <<< "$extra_ids")"$'\n'
  fi

  if [ -n "$errors" ]; then
    GATE_CAUSE="O verificador nao cobriu as $expected tasks de forma consistente:"$'\n'"$errors"$'\n'"Linhas normalizadas:"$'\n'"$task_lines"
    return 1
  fi

  local incomplete
  incomplete=$(printf '%s' "$canonical" | grep 'INCOMPLETE' || true)

  if [ -n "$incomplete" ]; then
    GATE_CAUSE="O verificador independente encontrou tasks incompletas:"$'\n'"$incomplete"
    return 1
  fi

  success "Gate 3 — $expected/$expected tasks confirmadas no codigo"
  return 0
}

# ---------------------------------------------------------------------------
# Execucao de fase
# ---------------------------------------------------------------------------

commit_phase() {
  local phase_num="$1" phase_title="$2"
  git add -A
  if git diff --cached --quiet; then
    fail "Nada para commitar apos os gates — estado inesperado."
    return 1
  fi
  git commit -q -m "feat(phase-${phase_num}): ${phase_title}"
  refresh_approved_authority
  log "Commit criado: feat(phase-${phase_num}): ${phase_title}"
}

commit_wip() {
  local phase_num="$1"
  if ! guard_execution_authority "preparacao do commit WIP"; then
    fail "Commit WIP recusado: $GATE_CAUSE"
    return 2
  fi
  [ -n "$(git status --porcelain)" ] || return 0
  git add -A
  git commit -q -m "wip(phase-${phase_num}): incomplete — see .phases/logs/"
  refresh_approved_authority
  warn "Commit wip criado para a fase $phase_num — a proxima fase parte de arvore limpa"
}

# run_phase <phase_file> <phase_num> <phase_title> <seq> <total>
run_phase() {
  local phase_file="$1" phase_num="$2" phase_title="$3" seq="$4" total="$5"
  local phase_start
  phase_start=$(date +%s)

  export RALPH_PHASE_TITLE="$phase_title"
  export RALPH_PHASE_NUM="$phase_num"
  export RALPH_PHASE_TOTAL="$total"

  LIMIT_WAITS=0
  GATE_CAUSE=""

  echo ""
  log "[$seq/$total] Phase $phase_num: $phase_title"
  emit phase_start "[$seq/$total] $phase_title"

  if ! guard_execution_authority "hook phase_start"; then
    fail "Guardrail vermelho — $GATE_CAUSE"
    emit phase_failed "$phase_title — autoridade de execucao violada no inicio"
    return 2
  fi

  local cycle=1
  while [ "$cycle" -le "$MAX_CYCLES" ]; do
    export RALPH_PHASE_ATTEMPT="$cycle"
    if [ "$cycle" -gt 1 ]; then
      warn "Ciclo de correcao $cycle/$MAX_CYCLES..."
      emit cycle_start "ciclo $cycle/$MAX_CYCLES em '$phase_title' — ultima causa: $LAST_GATE"
    fi

    local prompt_file log_file rc=0 sig_before
    log_file="$LOG_DIR/${phase_file%.md}.cycle-${cycle}.log"

    if [ "$cycle" -eq 1 ]; then
      prompt_file=$(build_impl_prompt "$phase_file" "$cycle")
    else
      prompt_file=$(build_fix_prompt "$phase_file" "$cycle" "$LAST_GATE" "$GATE_CAUSE")
    fi

    sig_before=$(tree_signature)
    run_engine "$prompt_file" "$log_file" impl || rc=$?

    GATE_CAUSE=""

    # Gate 1 e sinal, nao veredito: uma fase ja implementada faz o engine
    # (corretamente) nao escrever nada. Quem decide sao os gates 2 e 3.
    # O sinal tambem alimenta o modo auto do gate 3: sessao sem escrita e
    # exatamente o caso em que a verificacao independente e obrigatoria.
    local no_change_note="" session_wrote=1
    if ! gate1_session_wrote "$sig_before"; then
      session_wrote=0
      no_change_note="A sessao anterior terminou sem alterar nenhum arquivo. "
      warn "Gate 1 — a sessao nao escreveu nada; validando o codigo existente"
    fi

    if ! guard_execution_authority "sessao de implementacao"; then
      fail "Guardrail vermelho — $GATE_CAUSE"
      emit gate_fail "guardrail (autoridade de execucao) em '$phase_title'"
    elif ! gate0_engine_finished "$log_file" "$rc"; then
      LAST_GATE="gate 0 — engine nao concluiu"
      fail "Gate 0 vermelho"
      emit gate_fail "gate 0 (engine nao concluiu) em '$phase_title'"
    elif ! gate2_tests_pass "$LOG_DIR/${phase_file%.md}.test-${cycle}.log"; then
      LAST_GATE="gate 2 — suite de testes do projeto"
      GATE_CAUSE="${no_change_note}${GATE_CAUSE}"
      fail "Gate 2 vermelho — testes do projeto falharam"
      emit gate_fail "gate 2 (suite do projeto) em '$phase_title'"
    elif ! guard_execution_authority "gate 2"; then
      fail "Guardrail vermelho — $GATE_CAUSE"
      emit gate_fail "guardrail apos gate 2 em '$phase_title'"
    elif ! gate3_independent_verify "$phase_file" "$cycle" "$session_wrote"; then
      LAST_GATE="gate 3 — verificacao independente"
      GATE_CAUSE="${no_change_note}${GATE_CAUSE}"
      fail "Gate 3 vermelho — implementacao incompleta"
      emit gate_fail "gate 3 (verificacao independente) em '$phase_title'"
    elif ! guard_execution_authority "gate 3"; then
      fail "Guardrail vermelho — $GATE_CAUSE"
      emit gate_fail "guardrail apos gate 3 em '$phase_title'"
    else
      local phase_duration=$(($(date +%s) - phase_start))

      # Gates verdes e nada a commitar => a fase ja estava implementada em HEAD
      # (run anterior commitada, tasks [x], codigo escrito a mao).
      if [ -z "$(git status --porcelain)" ]; then
        success "Phase $phase_num: $phase_title — JA IMPLEMENTADA (nada a commitar)"
        if [ "$GATE3_RAN" -eq 1 ]; then
          log "Gates 2 e 3 verdes contra o codigo em HEAD; nenhum commit criado."
        else
          log "Gate 2 verde contra o codigo em HEAD; nenhum commit criado."
        fi
        emit phase_already_done "$phase_title — gates verdes contra HEAD, nada a commitar"
        if ! guard_execution_authority "hook phase_already_done"; then
          fail "Guardrail vermelho — $GATE_CAUSE"
          return 2
        fi
        mark_phase_done "$phase_file"
        return 0
      fi

      success "Phase $phase_num: $phase_title — COMPLETA ($(format_duration "$phase_duration"))"
      if ! commit_phase "$phase_num" "$phase_title"; then
        LAST_GATE="commit"
        emit phase_failed "$phase_title — falha no commit da fase"
        return 1
      fi
      emit phase_done "$phase_title — completa em $(format_duration "$phase_duration")"
      if ! guard_execution_authority "hook phase_done"; then
        fail "Guardrail vermelho — $GATE_CAUSE"
        return 2
      fi
      mark_phase_done "$phase_file"
      return 0
    fi

    cycle=$((cycle + 1))
  done

  local phase_duration=$(($(date +%s) - phase_start))
  fail "Phase $phase_num: $phase_title — FALHOU apos $MAX_CYCLES ciclos ($(format_duration "$phase_duration"))"
  emit phase_failed "$phase_title — falhou apos $MAX_CYCLES ciclos ($LAST_GATE)"
  fail "Ultima causa ($LAST_GATE):"
  printf '%s\n' "$GATE_CAUSE" | head -n 20 | sed 's/^/    /'
  fail "Logs em: $LOG_DIR/${phase_file%.md}.*"

  # O trabalho parcial fica na arvore; o preflight da proxima execucao exige
  # arvore limpa. Diga o que fazer em vez de deixar o dev descobrir no abort.
  if [ -n "$(git status --porcelain)" ]; then
    warn "O trabalho parcial desta fase ficou na arvore. Antes de re-rodar o ralph:"
    warn "    revise com 'git status --short' e 'git diff'; depois commite/stashe o que deseja preservar"
    warn "    ou restaure apenas paths conhecidos da fase. O ralph nao sugere limpeza global destrutiva."
  fi
  case "$LAST_GATE" in
    guardrail*) return 2 ;;
    *) return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

LAST_GATE=""

main() {
  preflight_checks
  split_phases
  apply_from_override
  refresh_approved_authority

  local total_phases
  total_phases=$(manifest_entries | wc -l)

  if [ "$total_phases" -eq 0 ]; then
    fail "Nenhuma fase extraida de $INPUT_FILE."
    exit 1
  fi

  if [ "$FROM_PHASE" -gt "$total_phases" ]; then
    fail "--from $FROM_PHASE excede o total de fases ($total_phases)."
    exit 1
  fi

  echo ""
  log "$total_phases fases para implementar (engine: $ENGINE, max-cycles: $MAX_CYCLES)"
  if [ "$ENGINE" = "codex" ]; then
    log "Codex: perfil $CODEX_PROFILE · modelo $CODEX_MODEL · esforco $CODEX_REASONING_EFFORT"
  fi
  [ "$FROM_PHASE" -gt 1 ] && log "Iniciando a partir da fase $FROM_PHASE"
  echo ""

  local file num title
  while IFS='|' read -r file num title; do
    if [ "$num" -lt "$FROM_PHASE" ]; then
      echo -e "  ${BLUE}[$num] $title (pulada por --from)${NC}"
    elif is_phase_done "$file"; then
      echo -e "  ${GREEN}[$num] $title (ja completada)${NC}"
    else
      echo -e "  ${YELLOW}[$num] $title${NC}"
    fi
  done < <(manifest_entries)

  local start_time
  start_time=$(date +%s)
  echo ""
  log "Inicio: $(date '+%d/%m/%Y %H:%M:%S')"
  emit run_start "$total_phases fases · engine $ENGINE · input $INPUT_FILE"

  if ! guard_execution_authority "hook run_start"; then
    fail "Guardrail vermelho — $GATE_CAUSE"
    emit run_end "FALHOU — hook run_start violou a autoridade de execucao"
    exit 1
  fi

  local seq=0 phase_rc=0
  local failed_phases=() skipped_phases=() completed_phases=()

  # fd 3, nunca stdin: comandos do corpo (claude -p, sail test / docker compose
  # exec) leem stdin quando nao e TTY e engoliriam o resto do manifest — o run
  # pararia apos a primeira fase.
  while IFS='|' read -r -u 3 file num title; do
    seq=$((seq + 1))

    if [ "$num" -lt "$FROM_PHASE" ]; then
      log "Pulando Phase $num: $title (antes de --from $FROM_PHASE)"
      skipped_phases+=("$title")
      continue
    fi

    if is_phase_done "$file"; then
      log "Pulando Phase $num: $title (ja completada)"
      skipped_phases+=("$title")
      continue
    fi

    if run_phase "$file" "$num" "$title" "$seq" "$total_phases"; then
      completed_phases+=("$title")
    else
      phase_rc=$?
      failed_phases+=("$title")
      if [ "$phase_rc" -eq 2 ]; then
        warn "Autoridade de execucao violada: --keep-going nao pode continuar nem criar WIP."
        break
      elif $KEEP_GOING; then
        warn "--keep-going: seguindo para a proxima fase"
        if ! commit_wip "$num"; then
          warn "Commit WIP recusado; interrompendo o run."
          break
        fi
      else
        warn "Parando na primeira fase que falhou (use --keep-going para continuar)"
        break
      fi
    fi
  done 3< <(manifest_entries)

  local end_time total_duration
  end_time=$(date +%s)
  total_duration=$((end_time - start_time))

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  log "RELATORIO FINAL (engine: $ENGINE)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local phase
  if [ ${#completed_phases[@]} -gt 0 ]; then
    echo ""
    success "Completadas (${#completed_phases[@]}):"
    for phase in "${completed_phases[@]}"; do printf '    %b%s%b\n' "$GREEN" "$phase" "$NC"; done
  fi

  if [ ${#skipped_phases[@]} -gt 0 ]; then
    echo ""
    log "Puladas (${#skipped_phases[@]}):"
    for phase in "${skipped_phases[@]}"; do printf '    %s\n' "$phase"; done
  fi

  if [ ${#failed_phases[@]} -gt 0 ]; then
    echo ""
    fail "Falharam (${#failed_phases[@]}):"
    for phase in "${failed_phases[@]}"; do printf '    %b%s%b\n' "$RED" "$phase" "$NC"; done
    echo ""
    fail "Verifique os logs em $LOG_DIR/"
  fi

  echo ""
  log "Inicio: $(date -d "@$start_time" '+%d/%m/%Y %H:%M:%S')"
  log "Fim:    $(date -d "@$end_time" '+%d/%m/%Y %H:%M:%S')"
  log "Duracao total: $(format_duration "$total_duration")"
  echo ""

  local verdict="tudo verde"
  [ ${#failed_phases[@]} -eq 0 ] || verdict="FALHOU"
  emit run_end "$verdict · completadas ${#completed_phases[@]} · falharam ${#failed_phases[@]} · puladas ${#skipped_phases[@]} · duracao $(format_duration "$total_duration")"

  if ! guard_execution_authority "hook run_end"; then
    fail "Guardrail vermelho — $GATE_CAUSE"
    exit 1
  fi

  [ ${#failed_phases[@]} -eq 0 ] || exit 1
}

main
