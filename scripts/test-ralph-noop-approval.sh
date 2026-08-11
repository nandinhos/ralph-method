#!/usr/bin/env bash

# Os blocos PHP usam expressões literais dentro de aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-noop-approval.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control() {
  php "$ROOT/bin/ralph-control" "$@"
}

project="$TMP/project"
mkdir -p "$project"
git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method No-op Approval Test'
printf '%s\n' '# Feature já presente' > "$project/README.md"
printf '%s\n' '# Plano' > "$project/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_noop_approval","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-NOOP-001","title":"Aprovação sem commit vazio","position":1}]}' > "$project/workflow.json"
git -C "$project" add README.md plan.md workflow.json
git -C "$project" commit -qm base

(cd "$project" && control init --workflow wf_noop_approval --manifest workflow.json >/dev/null)
claim="$(cd "$project" && control claim --workflow wf_noop_approval --feature FEATURE-NOOP-001 --actor ralph)"
lease="$(printf '%s' "$claim" | php -r '$v=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
[ -n "$lease" ] || fail 'lease não foi emitido'

# A fase não altera o checkout porque o requisito já está presente no HEAD.
(cd "$project" && control finish --workflow wf_noop_approval --feature FEATURE-NOOP-001 --lease "$lease" --exit-code 0 >/dev/null)

for gate in validation quality runtime_evidence technical_review curation; do
  producer="producer-$gate"
  (cd "$project" && control gate --workflow wf_noop_approval --feature FEATURE-NOOP-001 --lease "$lease" \
    --gate "$gate" --status passed --producer "$producer" --actor "$producer" --exit-code 0 >/dev/null)
done

(cd "$project" && control approve --workflow wf_noop_approval --feature FEATURE-NOOP-001 --lease "$lease" >/dev/null) \
  || fail 'feature já implementada não foi aprovada sem commit vazio'

status="$(cd "$project" && control status)"
STATUS_JSON="$status" php -r '
    $status = json_decode(getenv("STATUS_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $feature = $status["projection"]["features"][0] ?? [];
    if (($feature["state"] ?? null) !== "approved") {
        fwrite(STDERR, "estado inesperado\n");
        exit(1);
    }
'

EVENTS_FILE="$project/.git/ralph-control/events.jsonl" php -r '
    $events = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    $approved = null;
    foreach ($events as $line) {
        $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        if (($event["type"] ?? null) === "feature.approved") {
            $approved = $event;
        }
    }
    if (($approved["facts"]["implementation_mode"] ?? null) !== "already_present"
        || ($approved["facts"]["no_op"] ?? null) !== true) {
        fwrite(STDERR, "modo de implementação no-op não foi auditado\n");
        exit(1);
    }
'

commit_count="$(git -C "$project" rev-list --count HEAD)"
[ "$commit_count" = '1' ] || fail 'aprovação no-op criou commit inesperado'

(cd "$project" && control handoff --workflow wf_noop_approval --feature FEATURE-NOOP-001 --output .ralph/handoffs/FEATURE-NOOP-001 >/dev/null)
(cd "$project" && control handoff-commit --workflow wf_noop_approval --feature FEATURE-NOOP-001 --lease "$lease" >/dev/null)
(cd "$project" && control release --workflow wf_noop_approval --feature FEATURE-NOOP-001 --lease "$lease" >/dev/null)
(cd "$project" && control advance --workflow wf_noop_approval --feature FEATURE-NOOP-001 --lease "$lease" >/dev/null)
(cd "$project" && control verify >/dev/null)

printf 'OK: feature já implementada foi aprovada, auditada e liberada sem commit vazio.\n'
