#!/usr/bin/env bash
#
# ralph-live-tail.sh — acompanhamento ao vivo do Ralph Method em 2º plano.
#
# Funde em um único stream, em tempo real:
#   1. o log do supervisor (saúde, gates, retomadas);
#   2. os eventos do ledger (telemetry.activity, heartbeat, gate.*, debug.*);
#   3. o snapshot do monitor (feature atual, estado, progresso) a cada tick.
#
# Somente leitura: não aprova gates, não toca no ledger, não altera o clone.
# Interface web fica para o ralph-watch (FEATURE-101C); este script é o olho
# de terminal imediato.
#
# Uso:
#   bash scripts/ralph-live-tail.sh [--no-follow] [--lines N] [--tick S]
#
# Variáveis de ambiente:
#   RALPH_FIELD=/tmp/ralph-method-2.0-field   (checkout de execução)
#   RALPH_WORKFLOW=wf_ralph_method_2_0_onda1
#   RALPH_SUPERVISOR_LOG=/tmp/ralph-supervise-onda1.log
#
# Para rodar em 2º plano e olhar depois:
#   nohup bash scripts/ralph-live-tail.sh > /tmp/ralph-live-tail.out 2>&1 &
#   tail -f /tmp/ralph-live-tail.out
#
# Expressões PHP literais dentro de aspas simples: sem expansão shell.
# shellcheck disable=SC2016

set -u



FIELD="${RALPH_FIELD:-/tmp/ralph-method-2.0-field}"
WORKFLOW="${RALPH_WORKFLOW:-wf_ralph_method_2_0_onda1}"
SUPERVISOR_LOG="${RALPH_SUPERVISOR_LOG:-/tmp/ralph-supervise-onda1.log}"
LINES="${RALPH_LIVE_LINES:-20}"
TICK="${RALPH_LIVE_TICK:-10}"
FOLLOW=1

# parse de argumentos: aceita --no-follow, --lines N, --lines=N, --tick N, --tick=N
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-follow) FOLLOW=0 ;;
    --lines) LINES="${2:-$LINES}"; shift ;;
    --lines=*) LINES="${1#--lines=}" ;;
    --tick) TICK="${2:-$TICK}"; shift ;;
    --tick=*) TICK="${1#--tick=}" ;;
  esac
  shift
done

LEDGER="$FIELD/.git/ralph-control/events.jsonl"
MONITOR="$FIELD/bin/ralph-monitor"
CONTROL="$FIELD/bin/ralph-control"


GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'
MAGENTA=$'\033[35m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'

stamp() { date '+%H:%M:%S'; }

# Cores por tipo de evento (prefixo de tipo).
color_event() {
  case "$1" in
    gate.passed|feature.approved|feature.released|block.finished) echo "$GREEN" ;;
    gate.rejected|debugging.rejected|feature.failed) echo "$RED" ;;
    gate.stalled|recovery.*|debugging.*|gate.retry_started) echo "$YELLOW" ;;
    feature.claimed|feature.advanced) echo "$MAGENTA" ;;
    command.heartbeat|telemetry.activity) echo "$DIM" ;;
    *) echo "$CYAN" ;;
  esac
}

echo "${BOLD}═══ Ralph Method — acompanhamento ao vivo ═══${RESET}"
echo "workflow: $WORKFLOW"
echo "field:    $FIELD"
echo "ledger:   $LEDGER"
echo "supervisor log: $SUPERVISOR_LOG"
echo "────────────────────────────────────────────"

if [ ! -f "$LEDGER" ]; then
  echo "${RED}ledger não encontrado: $LEDGER${RESET}" >&2
  exit 1
fi

# Contadores para posições iniciais.
ledger_pos=$(wc -l < "$LEDGER" 2>/dev/null || echo 0)
log_pos=$(wc -l < "$SUPERVISOR_LOG" 2>/dev/null || echo 0)

# Mostra as últimas N linhas do log do supervisor (estado recente).
if [ "$LINES" -gt 0 ] && [ -f "$SUPERVISOR_LOG" ]; then
  echo "${BOLD}── últimas $LINES linhas do supervisor ──${RESET}"
  tail -n "$LINES" "$SUPERVISOR_LOG" | sed "s/^/$(stamp) /"
  echo
fi

# Loop de acompanhamento.
while :; do
  # 1) snapshot do monitor (feature atual, estado, gates, progresso)
  if [ -x "$MONITOR" ]; then
    snap="$("$MONITOR" --root "$FIELD" --controller "$CONTROL" --workflow "$WORKFLOW" --once --json 2>/dev/null)"
    if [ -n "$snap" ]; then
      feat=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);echo ($d["cursor"]??"");' 2>/dev/null)
      title=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);echo ($d["title"]??"");' 2>/dev/null)
      st=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);echo ($d["state"]??$d["status"]??"");' 2>/dev/null)
      prog=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);echo round((float)($d["progress"]["feature_percent"]??0),1);' 2>/dev/null)
      gates=$(printf '%s' "$snap" | php -r '$d=json_decode(stream_get_contents(STDIN),true);$p=$d["progress"]??[];echo ($p["passed_gates"]??0)."/".($p["total_gates"]??0);' 2>/dev/null)
      echo "${CYAN}${BOLD}[$(stamp)]${RESET} snapshot → feature=${MAGENTA}${feat:-—}${RESET} (${title:-—}) estado=${YELLOW}${st:-—}${RESET} progresso=${prog:-—}% gates=${gates:-—}"

      # Workflow completo: sem cursor e estado complete = todas as features
      # liberadas. Para de monitorar e avisa — não fica repetindo o snapshot.
      if [ "$st" = "complete" ] && [ -z "$feat" ]; then
        echo ""
        echo "${GREEN}${BOLD}══════════════════════════════════════════════════════════${RESET}"
        echo "${GREEN}${BOLD}  ✅ WORKFLOW COMPLETO — ${WORKFLOW}${RESET}"
        echo "${GREEN}${BOLD}  Todas as features foram liberadas com os 5 gates verdes.${RESET}"
        echo "${CYAN}  Ledger:  ${LEDGER}${RESET}"
        echo "${CYAN}  Relatório de tempo:${RESET}"
        echo "${CYAN}    php bin/ralph-time-report.php --ledger ${LEDGER} --workflow ${WORKFLOW} --format md${RESET}"
        echo "${GREEN}${BOLD}══════════════════════════════════════════════════════════${RESET}"
        echo ""
        echo "encerrado em $(date '+%Y-%m-%d %H:%M:%S')"
        exit 0
      fi
    fi
  fi

  # 2) eventos novos do ledger (depois da posição conhecida)
  if [ -f "$LEDGER" ]; then
    new_pos=$(wc -l < "$LEDGER")
    if [ "$new_pos" -gt "$ledger_pos" ]; then
      tail -n +$((ledger_pos + 1)) "$LEDGER" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        out=$(printf '%s' "$line" | php -r '
          $e = json_decode(stream_get_contents(STDIN), true);
          if (! is_array($e)) { exit; }
          $ts = substr((string)($e["timestamp"] ?? ""), 11, 8);
          $type = (string)($e["type"] ?? "");
          $feat = (string)($e["feature_key"] ?? "");
          $sum = (string)($e["summary"] ?? ($e["detail"] ?? ""));
          $attempt = (int)($e["attempt"] ?? 0);
          printf("%s|%s|%s|attempt %d|%s", $ts, $type, $feat, $attempt, $sum);
        ' 2>/dev/null)
        if [ -n "$out" ]; then
          ts="${out%%|*}"; rest="${out#*|}"
          type="${rest%%|*}"; rest="${rest#*|}"
          feat="${rest%%|*}"; rest="${rest#*|}"
          sum="${rest#*|}"
          color="$(color_event "$type")"
          printf "%s %s%-28s%s %s%-26s%s %s\n" \
            "${CYAN}${BOLD}${ts}${RESET}" "$color" "$type" "$RESET" \
            "$MAGENTA" "$feat" "$RESET" "$sum"
        fi
      done
      ledger_pos=$new_pos
    fi
  fi

  # 3) linhas novas do log do supervisor
  if [ -f "$SUPERVISOR_LOG" ]; then
    new_log_pos=$(wc -l < "$SUPERVISOR_LOG")
    if [ "$new_log_pos" -gt "$log_pos" ]; then
      tail -n +$((log_pos + 1)) "$SUPERVISOR_LOG" | while IFS= read -r line; do
        [ -z "$line" ] && continue
        # coloriza por palavra-chave
        if printf '%s' "$line" | grep -qiE 'rejeitad|FALHA|erro|verm'; then
          c="$RED"
        elif printf '%s' "$line" | grep -qiE 'aprovad|verde|ok|avan'; then
          c="$GREEN"
        elif printf '%s' "$line" | grep -qiE 'stale|aguard|retry|paus'; then
          c="$YELLOW"
        else
          c="$DIM"
        fi
        printf "%s ${c}%s${RESET}\n" "${CYAN}${BOLD}[$(stamp)]${RESET}" "$line"
      done
      log_pos=$new_log_pos
    fi
  fi

  if [ "$FOLLOW" -eq 0 ]; then
    break
  fi
  sleep "$TICK"
done
