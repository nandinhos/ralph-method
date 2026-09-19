#!/usr/bin/env bash
#
# ralph-supervise.sh — supervisor universal e agnóstico de workflows/ondas (SPP).
#
# Control plane agnóstico para execução de ondas sequenciais (anti-paralelismo),
# monitoramento em tempo real com sidecar do Trace Cockpit e recuperação
# determinística guiada por evidências.
#
# Uso:
#   bash scripts/ralph-supervise.sh [opções]
#
# Opções:
#   --target-dir <dir>       Diretório do projeto-alvo (default: pwd)
#   --workflow <id>          Workflow único para supervisionar
#   --workflows <id1,id2>    Fila ordenada de workflows para execução em multi-ondas
#   --engine <engine>        Runner do ciclo (default: codex ou do method.json)
#   --test-cmd <cmd>         Comando de teste (Gate 2 / Quality). Auto-detectado se omitido
#   --debug-cmd <cmd>        Comando de diagnóstico/debug sistemático
#   --interval <segundos>    Intervalo de amostragem do supervisor (default: 20)
#   --max-retries <n>        Limite de retries por feature antes de escalada (default: 3)
#   --relaunch-sleep <seg>   Espera antes de retomar ciclo transitório (default: 8)
#   --with-cockpit           Inicia sidecar de ingest do Cockpit para visualização em tempo real
#   --cockpit-path <dir>     Caminho da aplicação Cockpit (default: $ROOT/apps/cockpit)
#   -h, --help               Exibe esta mensagem de ajuda

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET_DIR="$(pwd)"
WORKFLOW_FLAG=""
WORKFLOWS_FLAG=""
ENGINE="${RALPH_ENGINE:-codex}"
TEST_CMD_FLAG=""
DEBUG_CMD_FLAG=""
INTERVAL="${RALPH_INTERVAL:-20}"
MAX_RETRIES="${RALPH_MAX_RETRIES:-3}"
RELAUNCH_SLEEP="${RALPH_RELAUNCH_SLEEP:-8}"
WITH_COCKPIT="${RALPH_WITH_COCKPIT:-0}"
COCKPIT_PATH="${RALPH_COCKPIT_APP:-$ROOT/apps/cockpit}"

usage() {
  sed -n '3,22p' "$0" | sed 's/^#//; s/^ //'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target-dir)
      TARGET_DIR="$2"
      shift 2
      ;;
    --target-dir=*)
      TARGET_DIR="${1#*=}"
      shift
      ;;
    --workflow)
      WORKFLOW_FLAG="$2"
      shift 2
      ;;
    --workflow=*)
      WORKFLOW_FLAG="${1#*=}"
      shift
      ;;
    --workflows)
      WORKFLOWS_FLAG="$2"
      shift 2
      ;;
    --workflows=*)
      WORKFLOWS_FLAG="${1#*=}"
      shift
      ;;
    --engine)
      ENGINE="$2"
      shift 2
      ;;
    --engine=*)
      ENGINE="${1#*=}"
      shift
      ;;
    --test-cmd)
      TEST_CMD_FLAG="$2"
      shift 2
      ;;
    --test-cmd=*)
      TEST_CMD_FLAG="${1#*=}"
      shift
      ;;
    --debug-cmd)
      DEBUG_CMD_FLAG="$2"
      shift 2
      ;;
    --debug-cmd=*)
      DEBUG_CMD_FLAG="${1#*=}"
      shift
      ;;
    --interval)
      INTERVAL="$2"
      shift 2
      ;;
    --interval=*)
      INTERVAL="${1#*=}"
      shift
      ;;
    --max-retries)
      MAX_RETRIES="$2"
      shift 2
      ;;
    --max-retries=*)
      MAX_RETRIES="${1#*=}"
      shift
      ;;
    --relaunch-sleep)
      RELAUNCH_SLEEP="$2"
      shift 2
      ;;
    --relaunch-sleep=*)
      RELAUNCH_SLEEP="${1#*=}"
      shift
      ;;
    --with-cockpit)
      WITH_COCKPIT=1
      shift
      ;;
    --cockpit-path)
      COCKPIT_PATH="$2"
      shift 2
      ;;
    --cockpit-path=*)
      COCKPIT_PATH="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Opção desconhecida: $1" >&2
      usage
      ;;
  esac
done

TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd || echo "$TARGET_DIR")"
if [ ! -d "$TARGET_DIR" ]; then
  echo "ERRO: Diretório alvo inexistente: $TARGET_DIR" >&2
  exit 2
fi

cd "$TARGET_DIR" || exit 2

# Resolução do binário ralph-control
if [ -f "$TARGET_DIR/bin/ralph-control" ]; then
  RALPH_BIN="$TARGET_DIR/bin/ralph-control"
elif [ -f "$ROOT/bin/ralph-control" ]; then
  RALPH_BIN="$ROOT/bin/ralph-control"
else
  echo "ERRO: bin/ralph-control não encontrado em $TARGET_DIR nem em $ROOT" >&2
  exit 2
fi

# Resolução do binário de diagnóstico
if [ -n "$DEBUG_CMD_FLAG" ]; then
  DEBUG_CMD="$DEBUG_CMD_FLAG"
elif [ -f "$TARGET_DIR/bin/ralph-diagnose.php" ]; then
  DEBUG_CMD="php $TARGET_DIR/bin/ralph-diagnose.php"
elif [ -f "$ROOT/bin/ralph-diagnose.php" ]; then
  DEBUG_CMD="php $ROOT/bin/ralph-diagnose.php"
else
  DEBUG_CMD="php $RALPH_BIN status"
fi

# Resolução agnóstica do comando de teste (Gate 2)
resolve_test_cmd() {
  if [ -n "$TEST_CMD_FLAG" ]; then
    echo "$TEST_CMD_FLAG"
    return 0
  fi
  if [ -n "${RALPH_TEST_CMD:-}" ]; then
    echo "$RALPH_TEST_CMD"
    return 0
  fi
  if [ -f .ralph/method.json ]; then
    local from_json
    from_json=$(grep -oE '"test_cmd"[[:space:]]*:[[:space:]]*"[^"]+"' .ralph/method.json 2>/dev/null | cut -d'"' -f4 || true)
    if [ -n "$from_json" ]; then
      echo "$from_json"
      return 0
    fi
  fi
  if [ -x vendor/bin/sail ]; then
    echo "vendor/bin/sail test"
  elif [ -f composer.json ] && grep -qE '"test"[[:space:]]*:' composer.json; then
    echo "composer test"
  elif [ -f artisan ]; then
    echo "php artisan test"
  elif [ -f package.json ] && grep -qE '"test"[[:space:]]*:' package.json; then
    echo "npm test"
  elif [ -f pytest.ini ] || { [ -f pyproject.toml ] && grep -qF '[tool.pytest' pyproject.toml; }; then
    echo "pytest"
  elif [ -f go.mod ]; then
    echo "go test ./..."
  elif [ -f Cargo.toml ]; then
    echo "cargo test"
  else
    echo "true"
  fi
}

TEST_CMD="$(resolve_test_cmd)"

# Garantia de Anti-Paralelismo via Lock de Wrapper
mkdir -p "$TARGET_DIR/.ralph"
WRAPPER_LOCK_FILE="$TARGET_DIR/.ralph/.supervisor-wrapper.lock"
exec 200>"$WRAPPER_LOCK_FILE"
if command -v flock >/dev/null 2>&1; then
  if ! flock -n 200; then
    echo "ERRO: Já existe um supervisor ou wrapper ativo para este checkout ($TARGET_DIR)." >&2
    exit 12
  fi
fi

# Gestão de Ciclo de Vida do Sidecar do Cockpit
COCKPIT_PID=""

# shellcheck disable=SC2317
cleanup() {
  local exit_code=$?
  if [ -n "$COCKPIT_PID" ] && kill -0 "$COCKPIT_PID" 2>/dev/null; then
    echo "[supervise] Encerrando sidecar do Trace Cockpit (PID $COCKPIT_PID)..."
    kill "$COCKPIT_PID" 2>/dev/null || true
    wait "$COCKPIT_PID" 2>/dev/null || true
  fi
  rm -f "$WRAPPER_LOCK_FILE" 2>/dev/null || true
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

if [ "$WITH_COCKPIT" -eq 1 ] && [ -f "$COCKPIT_PATH/artisan" ]; then
  echo "[supervise] Lançando sidecar do Trace Cockpit em segundo plano..."
  (
    export RALPH_PROJECT_ROOT="$TARGET_DIR"
    php "$COCKPIT_PATH/artisan" ralph:ingest --no-broadcast --follow >> "$TARGET_DIR/.ralph/cockpit-ingest.log" 2>&1
  ) &
  COCKPIT_PID=$!
  echo "[supervise] Sidecar do Cockpit ativo (PID $COCKPIT_PID, log: .ralph/cockpit-ingest.log)"
fi

# Resolução da Fila de Workflows (Multi-Ondas)
declare -a WORKFLOW_QUEUE=()

if [ -n "$WORKFLOWS_FLAG" ]; then
  IFS=',' read -r -a WORKFLOW_QUEUE <<< "$WORKFLOWS_FLAG"
elif [ -n "$WORKFLOW_FLAG" ]; then
  WORKFLOW_QUEUE=("$WORKFLOW_FLAG")
elif [ -n "${RALPH_WORKFLOW:-}" ]; then
  WORKFLOW_QUEUE=("$RALPH_WORKFLOW")
else
  # Auto-detecção do workflow ativo a partir do workflow.json
  WF_JSON=""
  if [ -f "$TARGET_DIR/.git/ralph-control/workflow.json" ]; then
    WF_JSON="$TARGET_DIR/.git/ralph-control/workflow.json"
  elif [ -f "$TARGET_DIR/.ralph/workflow.json" ]; then
    WF_JSON="$TARGET_DIR/.ralph/workflow.json"
  fi
  if [ -n "$WF_JSON" ]; then
    DETECTED_WF=$(grep -oE '"workflow_id"[[:space:]]*:[[:space:]]*"[^"]+"' "$WF_JSON" | head -n1 | cut -d'"' -f4 || true)
    if [ -n "$DETECTED_WF" ]; then
      WORKFLOW_QUEUE=("$DETECTED_WF")
    fi
  fi
fi

if [ ${#WORKFLOW_QUEUE[@]} -eq 0 ]; then
  echo "ERRO: Nenhum workflow especificado nem detectado em $TARGET_DIR." >&2
  echo "Passe --workflow <id> ou --workflows <id1,id2>." >&2
  exit 2
fi

echo "================================================================================"
echo " Ralph Method — Supervisor Universal Multi-Ondas (SPP Engine)"
echo "================================================================================"
echo " Projeto:      $TARGET_DIR"
echo " Fila Ondas:   ${WORKFLOW_QUEUE[*]}"
echo " Total Ondas:  ${#WORKFLOW_QUEUE[@]}"
echo " Engine:       $ENGINE"
echo " Quality Cmd:  $TEST_CMD"
echo " Debug Cmd:    $DEBUG_CMD"
echo " Intervalo:    ${INTERVAL}s | Max Retries: $MAX_RETRIES"
echo "================================================================================"

# Verificação determinística de conclusão do workflow
is_workflow_complete() {
  local status_json
  status_json="$(php "$RALPH_BIN" status 2>/dev/null)" || return 1
  # Um workflow está concluído quando todas as features foram liberadas (cursor nulo)
  # e nenhuma feature está travada em recovery_required ou failed.
  if echo "$status_json" | grep -q '"cursor":null'; then
    if ! echo "$status_json" | grep -qE '"state":"(recovery_required|failed|debugging_running)"'; then
      return 0
    fi
  fi
  return 1
}

W_INDEX=0
TOTAL_ONDA=${#WORKFLOW_QUEUE[@]}

for CURRENT_WF in "${WORKFLOW_QUEUE[@]}"; do
  # Limpar espaços ao redor
  CURRENT_WF="$(echo "$CURRENT_WF" | tr -d '[:space:]')"
  [ -z "$CURRENT_WF" ] && continue

  W_INDEX=$((W_INDEX + 1))
  echo
  echo "--------------------------------------------------------------------------------"
  echo " [Onda $W_INDEX/$TOTAL_ONDA] Iniciando execução do workflow: $CURRENT_WF"
  echo "--------------------------------------------------------------------------------"

  ATTEMPT=0
  while true; do
    ATTEMPT=$((ATTEMPT + 1))
    echo "[supervise][$CURRENT_WF] Ciclo $ATTEMPT em $(date '+%Y-%m-%d %H:%M:%S')"

    php "$RALPH_BIN" supervise \
      --workflow "$CURRENT_WF" \
      --engine "$ENGINE" \
      --test-cmd "$TEST_CMD" \
      --debug-command "$DEBUG_CMD" \
      --interval "$INTERVAL" \
      --max-retries "$MAX_RETRIES"
    RC=$?

    if is_workflow_complete; then
      echo "[supervise][$CURRENT_WF] SUCESSO: Onda concluída integralmente com todos os gates aprovados."
      break
    fi

    if [ "$RC" -ne 0 ]; then
      echo "[supervise][$CURRENT_WF] Supervisor retornou código $RC (aguardando resolução de stall/recovery)..."
    fi

    echo "[supervise][$CURRENT_WF] Aguardando ${RELAUNCH_SLEEP}s para próxima checagem/ciclo..."
    sleep "$RELAUNCH_SLEEP"
  done
done

echo
echo "================================================================================"
echo " Ralph Method: Todas as $TOTAL_ONDA ondas foram executadas e validadas com sucesso!"
echo "================================================================================"
exit 0
