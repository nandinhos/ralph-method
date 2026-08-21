#!/usr/bin/env bash
#
# ralph-anomaly-observer.sh — observer de anomalias do Ralph Method.
#
# Detecta problemas SILENCIOSOS que não têm feedback visível:
#   - supervisor morto (crash, OOM) com feature em running/awaiting_gates
#   - rate limits (429, usage limit) que ficam no log da execução sem evento
#   - gates travados (gate.stalled, retry pendente sem progresso)
#   - heartbeats ausentes (health != ok no monitor)
#   - retries/recoveries em loop (mesma feature sem avanço)
#   - crescimento do ledger (possível OOM do controlador)
#
# Somente leitura: não aprova gates, não altera o ledger, não toca no clone.
# Reporta em /tmp/ralph-anomalies.jsonl (linha por anomalia) e ecoa no stdout.
#
# Uso:
#   nohup bash scripts/ralph-anomaly-observer.sh --tick 30 \
#     > /tmp/ralph-anomaly-observer.out 2>&1 &
#
# Variáveis:
#   RALPH_FIELD, RALPH_WORKFLOW, RALPH_SUPERVISOR_LOG, RALPH_TICK
#   RALPH_ANOMALY_OUT=/tmp/ralph-anomalies.jsonl
#
# Expressões PHP literais dentro de aspas simples: sem expansão shell.
# shellcheck disable=SC2016

set -u



FIELD="${RALPH_FIELD:-/tmp/ralph-method-2.0-field}"
WORKFLOW="${RALPH_WORKFLOW:-wf_ralph_method_2_0_onda1}"
SUPERVISOR_LOG="${RALPH_SUPERVISOR_LOG:-/tmp/ralph-supervise-onda1.log}"
TICK="${RALPH_TICK:-30}"
OUT="${RALPH_ANOMALY_OUT:-/tmp/ralph-anomalies.jsonl}"
MAX_LEDGER_MB="${RALPH_MAX_LEDGER_MB:-25}"
RETRY_LOOP_LIMIT="${RALPH_RETRY_LOOP_LIMIT:-8}"
CONTROL="$FIELD/bin/ralph-control"
MONITOR="$FIELD/bin/ralph-monitor"
LEDGER="$FIELD/.git/ralph-control/events.jsonl"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tick) TICK="${2:-$TICK}"; shift ;;
    --tick=*) TICK="${1#--tick=}" ;;
    --out) OUT="${2:-$OUT}"; shift ;;
    --out=*) OUT="${1#--out=}" ;;
  esac
  shift
done


RED=$'\033[31m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; BOLD=$'\033[1m'; RESET=$'\033[0m'

stamp() { date '+%Y-%m-%dT%H:%M:%S%z'; }

report() { # report <severity> <kind> <message>
  local severity="$1" kind="$2" message="$3" ts
  ts="$(stamp)"
  printf '{"timestamp":"%s","severity":"%s","kind":"%s","message":"%s"}\n' \
    "$ts" "$severity" "$kind" "$(printf '%s' "$message" | sed 's/"/\\"/g')" >> "$OUT"
  case "$severity" in
    critical) printf "%s ${RED}${BOLD}[CRÍTICO]${RESET} %s\n" "$ts" "$message" ;;
    warning)  printf "%s ${YELLOW}[AVISO]${RESET} %s\n" "$ts" "$message" ;;
    info)     printf "%s ${CYAN}[INFO]${RESET} %s\n" "$ts" "$message" ;;
  esac
}

# memo de deduplicação: não repete o mesmo alerta no mesmo tick
declare -A SEEN_THIS_TICK=()
seen() { [ -n "${SEEN_THIS_TICK[$1]:-}" ]; }
mark() { SEEN_THIS_TICK[$1]=1; }

echo "${BOLD}═══ Ralph Method — observer de anomalias ═══${RESET}"
echo "workflow: $WORKFLOW | tick: ${TICK}s | out: $OUT"
echo "────────────────────────────────────────────"

prev_log_pos=0
prev_ledger_pos=0

while :; do
  SEEN_THIS_TICK=()

  # 1) supervisor vivo?
  sup_alive=$(pgrep -f "ralph-control supervise.*${WORKFLOW}" | head -1 || true)
  if [ -z "$sup_alive" ]; then
    if ! seen "supervisor_morto"; then
      mark "supervisor_morto"
      report "critical" "supervisor_down" "supervisor do workflow ${WORKFLOW} NÃO está rodando (PID ausente)"
    fi
  fi

  # 2) monitor: health e último evento
  if [ -x "$MONITOR" ]; then
    snap="$("$MONITOR" --root "$FIELD" --controller "$CONTROL" --workflow "$WORKFLOW" --once --json 2>/dev/null)"
    if [ -n "$snap" ]; then
      health=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);echo ($d["health"]??"");' 2>/dev/null)
      state=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);echo ($d["state"]??"");' 2>/dev/null)
      feat=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);echo ($d["cursor"]??"");' 2>/dev/null)
      if [ "$health" != "ok" ] && [ -n "$health" ]; then
        if ! seen "health_${health}"; then
          mark "health_${health}"
          report "warning" "health_${health}" "health=${health} | feature=${feat} estado=${state}"
        fi
      fi
      # recovery_required parado (sem supervisor para retomar)
      if [ "$state" = "recovery_required" ] && [ -z "$sup_alive" ]; then
        if ! seen "recovery_parado"; then
          mark "recovery_parado"
          report "critical" "recovery_stalled" "feature ${feat} em recovery_required e supervisor morto — o método está PARADO"
        fi
      fi
    fi
  fi

  # 3) log do supervisor: padrões silenciosos (rate limit, OOM, crash)
  if [ -f "$SUPERVISOR_LOG" ]; then
    log_pos=$(wc -l < "$SUPERVISOR_LOG")
    if [ "$log_pos" -gt "$prev_log_pos" ]; then
      tail -n +$((prev_log_pos + 1)) "$SUPERVISOR_LOG" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        if printf '%s' "$line" | grep -qiE 'Fatal error|memory exhausted|Allowed memory'; then
          report "critical" "control_oom" "$(printf '%s' "$line" | head -c 300)"
        elif printf '%s' "$line" | grep -qiE 'rate limit|usage limit|429|quota'; then
          report "warning" "rate_limit" "$(printf '%s' "$line" | head -c 300)"
        elif printf '%s' "$line" | grep -qiE 'saúde=blocked|health=blocked'; then
          report "warning" "supervisor_blocked" "$(printf '%s' "$line" | head -c 300)"
        fi
      done
      prev_log_pos=$log_pos
    fi
  fi

  # 4) rate limit nos logs da execução (.phases/logs) — o ponto cego clássico
  phase_logs=$(find "$FIELD/.phases/logs" -name "*.log" -newermt "-$((TICK * 2))s" 2>/dev/null | head -5)
  for pf in $phase_logs; do
    hits=$(grep -oiE 'rate limit reached|usage limit|quota exceeded|hit your usage limit|429' "$pf" 2>/dev/null | head -2)
    if [ -n "$hits" ]; then
      if ! seen "rl_$pf"; then
        mark "rl_$pf"
        report "warning" "rate_limit_phase" "rate limit detectado em $(basename "$pf"): $(echo "$hits" | tr '\n' ' ')"
      fi
    fi
  done

  # 5) ledger: crescimento (OOM iminente) e eventos de anomalia novos
  if [ -f "$LEDGER" ]; then
    ledger_mb=$(du -m "$LEDGER" | cut -f1)
    if [ "$ledger_mb" -gt "$MAX_LEDGER_MB" ] 2>/dev/null; then
      if ! seen "ledger_big"; then
        mark "ledger_big"
        report "warning" "ledger_growth" "ledger com ${ledger_mb}MB — risco de OOM do controlador (limite ${MAX_LEDGER_MB}MB)"
      fi
    fi
    ledger_pos=$(wc -l < "$LEDGER")
    if [ "$ledger_pos" -gt "$prev_ledger_pos" ]; then
      tail -n +$((prev_ledger_pos + 1)) "$LEDGER" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        kind=$(printf '%s' "$line" | php -r '$e=json_decode(stream_get_contents(STDIN),true);echo ($e["type"]??"");' 2>/dev/null)
        case "$kind" in
          recovery.required)
            msg=$(printf '%s' "$line" | php -r '$e=json_decode(stream_get_contents(STDIN),true);echo ($e["feature_key"]??"").": ".($e["summary"]??"");' 2>/dev/null)
            report "warning" "recovery_required" "$(printf '%s' "$msg" | head -c 200)" ;;
          gate.stalled)
            msg=$(printf '%s' "$line" | php -r '$e=json_decode(stream_get_contents(STDIN),true);echo ($e["feature_key"]??"").": ".($e["summary"]??"");' 2>/dev/null)
            report "warning" "gate_stalled" "$(printf '%s' "$msg" | head -c 200)" ;;
          debugging.required)
            msg=$(printf '%s' "$line" | php -r '$e=json_decode(stream_get_contents(STDIN),true);echo ($e["feature_key"]??"").": ".($e["summary"]??"");' 2>/dev/null)
            report "info" "debugging_required" "$(printf '%s' "$msg" | head -c 200)" ;;
        esac
      done
      prev_ledger_pos=$ledger_pos
    fi
  fi

  # 6) retries em loop: mesma feature com muitas recovery.retry_started
  if [ -f "$LEDGER" ]; then
    loop_count=$(grep -c '"type": *"recovery.retry_started"' "$LEDGER" 2>/dev/null || echo 0)
    if [ "$loop_count" -gt "$RETRY_LOOP_LIMIT" ] 2>/dev/null; then
      if ! seen "retry_loop"; then
        mark "retry_loop"
        report "warning" "retry_loop" "acumulou ${loop_count} retries — investigar loop de recovery (pode indicar defeito de harness ou provider)"
      fi
    fi
  fi

  sleep "$TICK"
done
