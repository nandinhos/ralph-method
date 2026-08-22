#!/usr/bin/env bash
#
# ralph-cockpit-ingest-loop.sh — re-roda o ralph:ingest a cada N segundos
# para o cockpit projetar os eventos do ledger em (quase) tempo real.
#
# O Reverb já empurra CockpitUpdated para o navegador; este loop garante que
# o ingest (fonte das projeções) capture os eventos novos do ledger.
#
# Uso (2º plano):
#   nohup bash scripts/ralph-cockpit-ingest-loop.sh > logs/ingest-loop.out 2>&1 &

set -u

COCKPIT="${RALPH_COCKPIT_APP:-$(cd "$(dirname "$0")/../apps/cockpit" && pwd)}"
TICK="${RALPH_INGEST_TICK:-5}"

while true; do
  php "$COCKPIT/artisan" ralph:ingest >/dev/null 2>&1
  sleep "$TICK"
done
