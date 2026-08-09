#!/usr/bin/env bash

# Os blocos PHP recebem JSON por variáveis de ambiente; não há expansão shell
# intencional dentro das expressões delimitadas por aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-metrics.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

events="$TMP/events.jsonl"
cat > "$events" <<'JSONL'
{"schema_version":"1.1.0","event_id":"evt-001","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"workflow.initialized","timestamp":"2026-08-09T12:00:00Z"}
{"schema_version":"1.1.0","event_id":"evt-002","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"feature.claimed","timestamp":"2026-08-09T12:00:01Z"}
{"schema_version":"1.1.0","event_id":"evt-003","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"attempt.started","timestamp":"2026-08-09T12:00:02Z"}
{"schema_version":"1.1.0","event_id":"evt-004","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"command.started","timestamp":"2026-08-09T12:00:03Z"}
{"schema_version":"1.1.0","event_id":"evt-005","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"command.passed","timestamp":"2026-08-09T12:00:04Z"}
{"schema_version":"1.1.0","event_id":"evt-006","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"gate.passed","timestamp":"2026-08-09T12:00:05Z","facts":{"gate":"quality"}}
{"schema_version":"1.1.0","event_id":"evt-007","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"gate.rejected","timestamp":"2026-08-09T12:00:06Z","facts":{"gate":"runtime_evidence"}}
{"schema_version":"1.1.0","event_id":"evt-008","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":1,"type":"recovery.required","timestamp":"2026-08-09T12:00:07Z"}
{"schema_version":"1.1.0","event_id":"evt-009","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":2,"type":"recovery.resolved","timestamp":"2026-08-09T12:00:17Z"}
{"schema_version":"1.1.0","event_id":"evt-010","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":2,"type":"attempt.started","timestamp":"2026-08-09T12:00:18Z"}
{"schema_version":"1.1.0","event_id":"evt-011","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":2,"type":"block.finished","timestamp":"2026-08-09T12:00:28Z"}
{"schema_version":"1.1.0","event_id":"evt-012","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":2,"type":"feature.approved","timestamp":"2026-08-09T12:00:29Z"}
{"schema_version":"1.1.0","event_id":"evt-013","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":2,"type":"feature.released","timestamp":"2026-08-09T12:00:30Z"}
{"schema_version":"1.1.0","event_id":"evt-014","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":2,"type":"knowledge.candidate_created","timestamp":"2026-08-09T12:00:31Z"}
{"schema_version":"1.1.0","event_id":"evt-015","workflow_id":"wf_metrics","feature_key":"FEATURE-001","attempt":2,"type":"knowledge.curated","timestamp":"2026-08-09T12:00:32Z"}
{"schema_version":"1.1.0","event_id":"evt-016","workflow_id":"wf_metrics","feature_key":"FEATURE-002","attempt":1,"type":"feature.claimed","timestamp":"2026-08-09T12:01:00Z"}
{"schema_version":"1.1.0","event_id":"evt-017","workflow_id":"wf_metrics","feature_key":"FEATURE-002","attempt":1,"type":"attempt.started","timestamp":"2026-08-09T12:01:01Z"}
{"schema_version":"1.1.0","event_id":"evt-018","workflow_id":"wf_metrics","feature_key":"FEATURE-002","attempt":1,"type":"block.finished","timestamp":"2026-08-09T12:01:03Z"}
JSONL

before_hash="$(sha256sum "$events")"
metrics_json="$(php "$ROOT/bin/ralph-metrics" --events "$events")"
metrics_markdown="$(php "$ROOT/bin/ralph-metrics" --events "$events" --format markdown)"
after_hash="$(sha256sum "$events")"
[ "$before_hash" = "$after_hash" ] || fail 'ralph-metrics alterou o ledger'

METRICS_JSON="$metrics_json" php -r '
    $metrics = json_decode(getenv("METRICS_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $summary = $metrics["summary"] ?? [];
    if (($summary["events_total"] ?? null) !== 18
        || ($summary["features_total"] ?? null) !== 2
        || ($summary["attempts_total"] ?? null) !== 3
        || ($summary["completed_attempts"] ?? null) !== 2
        || ($summary["commands_total"] ?? null) !== 1
        || ($summary["commands_passed"] ?? null) !== 1
        || ($summary["gates_passed"] ?? null) !== 1
        || ($summary["gates_rejected"] ?? null) !== 1
        || ($summary["recoveries_required"] ?? null) !== 1
        || ($summary["recoveries_resolved"] ?? null) !== 1
        || ($summary["knowledge_candidates"] ?? null) !== 1
        || ($summary["knowledge_curated"] ?? null) !== 1) {
        exit(1);
    }
    if (($summary["attempt_duration_seconds"]["count"] ?? null) !== 2
        || ($summary["recovery_duration_seconds"]["count"] ?? null) !== 1) {
        exit(1);
    }
' || fail 'agregados JSON inesperados'

printf '%s\n' "$metrics_markdown" | grep -q 'Métricas do Ralph Method' || fail 'saída Markdown ausente'
printf '%s\n' "$metrics_markdown" | grep -q 'Duração média da tentativa' || fail 'métrica de duração ausente'

filtered="$(php "$ROOT/bin/ralph-metrics" --events "$events" --feature FEATURE-001)"
FILTERED_JSON="$filtered" php -r '
    $metrics = json_decode(getenv("FILTERED_JSON"), true, 512, JSON_THROW_ON_ERROR);
    exit (($metrics["summary"]["features_total"] ?? null) === 1 && ($metrics["summary"]["events_total"] ?? null) === 15 ? 0 : 1);
' || fail 'filtro por feature não foi aplicado'

printf '%s\n' '{"malformed":' > "$TMP/malformed.jsonl"
set +e
php "$ROOT/bin/ralph-metrics" --events "$TMP/malformed.jsonl" >/dev/null 2>&1
malformed_exit=$?
set -e
[ "$malformed_exit" -eq 3 ] || fail 'ledger corrompido não foi rejeitado'

printf 'OK: métricas read-only, agregação, duração, filtros, Markdown e ledger corrompido passaram.\n'
