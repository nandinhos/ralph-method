#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAGNOSE="$ROOT/apps/cockpit/bin/ralph-diagnose.php"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/.git/ralph-control/artifacts"
printf '%s\n' \
  'ralph-cursor: não foi possível obter a versão do Cursor' \
  > "$TMP/.git/ralph-control/artifacts/FEATURE-099A-COCKPIT-MANIFEST-attempt-1.stderr.log"

report_file="$TMP/report.json"
(
  cd "$TMP" && \
  RALPH_DEBUG_WORKFLOW_ID=wf_cockpit_field \
  RALPH_DEBUG_FEATURE_KEY=FEATURE-099A-COCKPIT-MANIFEST \
  RALPH_DEBUG_ATTEMPT=1 \
  php "$DIAGNOSE"
) > "$report_file"

# shellcheck disable=SC2016
incident="$(php -r 'echo json_decode(file_get_contents($argv[1]), true)["incident_id"] ?? "";' "$report_file")"
# shellcheck disable=SC2016
cause="$(php -r 'echo json_decode(file_get_contents($argv[1]), true)["cause_kind"] ?? "";' "$report_file")"

[ "$incident" = 'INC-COCKPIT-CURSOR-001' ] || {
  printf 'esperado INC-COCKPIT-CURSOR-001, obteve %s\n' "$incident" >&2
  cat "$report_file" >&2
  exit 1
}
[ "$cause" = 'harness_defect' ] || {
  printf 'esperado cause_kind harness_defect, obteve %s\n' "$cause" >&2
  exit 1
}

printf 'test-cockpit-diagnose: OK (cursor PATH/CLI)\n'
