#!/usr/bin/env bash
# Observador ao vivo: controlador, monitor, projeção SQLite e preflight do cockpit.
# Uso: bash scripts/watch-cockpit-live.sh [segundos] [intervalo]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIELD="${RALPH_COCKPIT_FIELD:-/tmp/ralph-cockpit-field}"
WORKFLOW="${RALPH_COCKPIT_WORKFLOW:-wf_cockpit_field}"
COCKPIT="${RALPH_COCKPIT_APP:-$ROOT/apps/cockpit}"
DURATION="${1:-120}"
INTERVAL="${2:-5}"
OUT="${RALPH_COCKPIT_WATCH_LOG:-/tmp/cockpit-live-watch.jsonl}"

control="$ROOT/bin/ralph-control"
monitor="$ROOT/bin/ralph-monitor"

: > "$OUT"

tick=0
end=$((SECONDS + DURATION))

while [ "$SECONDS" -lt "$end" ]; do
  tick=$((tick + 1))
  ts="$(date -Iseconds)"
  status="$(cd "$FIELD" && "$control" status --workflow "$WORKFLOW" 2>/dev/null || echo '{}')"
  mon="$(cd "$FIELD" && "$monitor" --workflow "$WORKFLOW" --once --json 2>/dev/null || echo '{}')"
  sqlite="$(sqlite3 "$COCKPIT/database/database.sqlite" "SELECT workflow_id||'|'||health||'|'||COALESCE(progress_percent,0)||'|'||COALESCE(recovery_count,0)||'|'||COALESCE(engine,'') FROM workflow_projections WHERE workflow_id='$WORKFLOW';" 2>/dev/null || echo '')"
  features="$(sqlite3 "$COCKPIT/database/database.sqlite" "SELECT feature_key||':'||status||':'||COALESCE(attempt,0) FROM feature_projections WHERE workflow_id='$WORKFLOW' ORDER BY position;" 2>/dev/null | paste -sd ';' - || echo '')"
  timeline="$(sqlite3 "$COCKPIT/database/database.sqlite" "SELECT COUNT(*) FROM timeline_events WHERE workflow_id='$WORKFLOW';" 2>/dev/null || echo 0)"
  preflight="$(cd "$COCKPIT" && php -r "
require 'vendor/autoload.php';
\$app = require 'bootstrap/app.php';
\$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();
echo json_encode(app(App\Ralph\RalphLauncher::class)->decision('$WORKFLOW'), JSON_UNESCAPED_UNICODE);
" 2>/dev/null || echo '{}')"
  supervise="$(pgrep -af "ralph-control supervise.*${WORKFLOW}" 2>/dev/null | head -1 || true)"

  # shellcheck disable=SC2016
  php -r '
$ts = $argv[1]; $tick = (int)$argv[2];
$status = json_decode($argv[3], true) ?: [];
$mon = json_decode($argv[4], true) ?: [];
$preflight = json_decode($argv[5], true) ?: [];
$parts = explode("|", $argv[6]);
$wf = [
  "workflow_id" => $parts[0] ?? "",
  "health" => $parts[1] ?? "",
  "progress_percent" => (int)($parts[2] ?? 0),
  "recovery_count" => (int)($parts[3] ?? 0),
  "engine" => $parts[4] ?? "",
];
$cursor = $status["projection"]["cursor"] ?? null;
$state = null;
foreach ($status["projection"]["features"] ?? [] as $f) {
  if (($f["feature_key"] ?? null) === $cursor) { $state = $f["state"] ?? null; break; }
}
echo json_encode([
  "ts" => $ts,
  "tick" => $tick,
  "control" => ["cursor" => $cursor, "state" => $state, "events" => $status["event_count"] ?? null],
  "monitor" => ["health" => $mon["health"] ?? null, "processes" => count($mon["processes"] ?? []), "last_event" => $mon["last_event"]["type"] ?? null],
  "projection" => $wf,
  "features" => $argv[7],
  "timeline_events" => (int)$argv[8],
  "preflight" => ["ready" => $preflight["ready"] ?? false, "reason" => $preflight["reason"] ?? "", "running" => $preflight["running"] ?? false],
  "supervise" => $argv[9] !== "" ,
], JSON_UNESCAPED_UNICODE)."\n";
' "$ts" "$tick" "$status" "$mon" "$preflight" "$sqlite" "$features" "$timeline" "$supervise" >> "$OUT"

  sleep "$INTERVAL"
done

printf 'OK: %s linhas em %s\n' "$tick" "$OUT"
