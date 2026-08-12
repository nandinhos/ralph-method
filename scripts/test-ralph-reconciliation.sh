#!/usr/bin/env bash

# Os blocos PHP/Python usam expressões literais dentro de aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-reconciliation.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control() {
  php "$ROOT/bin/ralph-control" "$@"
}

json_field() {
  local json="$1"
  local field="$2"
  JSON_PAYLOAD="$json" JSON_FIELD="$field" php -r '
    $payload = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR);
    $value = $payload[getenv("JSON_FIELD")] ?? null;
    if (! is_scalar($value)) {
        exit(1);
    }
    echo $value;
  '
}

project="$TMP/project"
mkdir -p "$project/.ralph" "$project/.opencode/agents"
git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method Reconciliation Test'
printf '%s\n' '# Reconciliação' > "$project/README.md"
printf '%s\n' '# Plano' > "$project/plan.md"
printf '%s\n' '{}' > "$project/opencode.json"
cp "$ROOT/.opencode/agents/ralph-review.md" "$project/.opencode/agents/ralph-review.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_reconciliation","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-RECONCILIATION","title":"Retry do adapter","position":1}]}' > "$project/workflow.json"

cat > "$TMP/fake-ralph.sh" <<'SH'
#!/usr/bin/env bash

set -euo pipefail

write_result() {
  local mode="$1"
  local status="$2"
  local exit_code="$3"
  local path="$4"
  python3 - "$mode" "$status" "$exit_code" "$path" <<'PY'
import json
import os
import sys
from pathlib import Path

mode, status, exit_code, path = sys.argv[1:]
attempt = int(os.environ['RALPH_EXECUTION_ATTEMPT'])
execution_id = Path(path).stem.replace('.log', '').replace('.', '_')
result = {
    'schema_version': '1.0.0',
    'runner': 'opencode',
    'runner_version': '1.18.15-fixture',
    'provider': 'opencode',
    'requested_model': 'opencode/fixture-model',
    'effective_model': None,
    'identity_status': 'declared',
    'identity_source': 'requested_model',
    'execution_id': 'exec_reconciliation_' + execution_id,
    'execution_mode': mode,
    'workflow_id': os.environ['RALPH_EXECUTION_WORKFLOW_ID'],
    'feature_key': os.environ['RALPH_EXECUTION_FEATURE_KEY'],
    'attempt': attempt,
    'session_id': 'ses_reconciliation_' + execution_id,
    'status': status,
    'exit_code': int(exit_code),
    'fallback_used': None,
    'fallback_status': 'unknown',
    'events_seen': 1,
    'event_bytes': 10,
    'terminal_event': 'step_finish',
    'prompt_sha256': None,
    'prompt_transport': 'file',
    'permission_policy_hash': os.environ.get('RALPH_TEST_POLICY_HASH') if mode == 'verify' else None,
    'permission_policy_status': 'verified' if mode == 'verify' else 'not_required',
    'verification_agent': 'ralph-review' if mode == 'verify' else None,
    'error_summary': 'limite transitório do provider' if status == 'usage_limited' else None,
    'artifact_refs': ['fixture_' + execution_id],
}
Path(path).parent.mkdir(parents=True, exist_ok=True)
Path(path).write_text(json.dumps(result) + '\n')
PY
}

mkdir -p "$PWD/.phases/logs"
if printf '%s\n' "$*" | grep -q -- '--verify-only'; then
  sleep 2
  write_result verify completed 0 "$PWD/.phases/logs/phase-01.verify-1.log.result.json"
else
  write_result impl usage_limited 124 "$PWD/.phases/logs/phase-01.cycle-1.log.result.json"
  write_result impl completed 0 "$PWD/.phases/logs/phase-01.cycle-2.log.result.json"
fi
printf '%s\n' 'RALPH_FEEDBACK {"event":"fixture_done","source":"reconciliation"}'
SH
chmod +x "$TMP/fake-ralph.sh"
printf '%s\n' "RALPH_BIN=$TMP/fake-ralph.sh" > "$project/.ralph/opencode.env"
git -C "$project" add .
git -C "$project" add -f .ralph/opencode.env
git -C "$project" commit -qm base

fingerprint="$(php "$ROOT/adapters/opencode/policy.php" hash --repo-root "$project" --agent ralph-review)"
policy_hash="$(FINGERPRINT="$fingerprint" php -r '$v=json_decode(getenv("FINGERPRINT"), true, 512, JSON_THROW_ON_ERROR); echo $v["policy_hash"];')"
proof="$TMP/policy-proof.json"
PROOF="$proof" TARGET="$project" HASH="$policy_hash" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

proof_path = Path(os.environ['PROOF'])
root = Path(os.environ['TARGET'])
event_path = Path(str(proof_path) + '.events.jsonl')
event_path.write_text('{"sessionID":"ses_fixture_policy","type":"start"}\n{"sessionID":"ses_fixture_policy","type":"text","text":"READONLY_DENIED"}\n{"sessionID":"ses_fixture_policy","type":"step_finish"}\n')

digest = hashlib.sha256()
relative_paths = ['.opencode/agents/ralph-review.md']
relative_paths.extend(name for name in ('opencode.json', 'opencode.jsonc', 'opencode.yaml', 'opencode.yml', 'opencode.toml') if (root / name).is_file())
for relative in sorted(relative_paths):
    item = root / relative
    digest.update(relative.encode())
    digest.update(b'\0')
    digest.update(hashlib.sha256(item.read_bytes()).digest())
tree_hash = digest.hexdigest()
proof = {
    'schema_version': '1.0.0',
    'status': 'verified',
    'agent': 'ralph-review',
    'target_root': str(root.resolve()),
    'policy_hash': os.environ['HASH'],
    'tree_hash_before': tree_hash,
    'tree_hash_after': tree_hash,
    'canary_absent': True,
    'tool_events_seen': 0,
    'forbidden_tools_seen': [],
    'denied_tools_seen': [],
    'policy_denied_tools': ['edit', 'bash'],
    'denial_evidence': {'edit': ['policy'], 'bash': ['policy']},
    'session_id': 'ses_fixture_policy',
    'terminal_event': 'step_finish',
    'event_log_sha256': hashlib.sha256(event_path.read_bytes()).hexdigest(),
    'final_marker': 'READONLY_DENIED',
    'attempts': 1,
}
proof_path.write_text(json.dumps(proof) + '\n')
PY

(cd "$project" && control init --workflow wf_reconciliation --manifest workflow.json >/dev/null)
claim="$(cd "$project" && control claim --workflow wf_reconciliation --feature FEATURE-RECONCILIATION --actor test)"
lease="$(json_field "$claim" lease_token)"
run_output="$(cd "$project" && \
  RALPH_OPENCODE_VERIFY_POLICY_PROOF="$proof" \
  RALPH_OPENCODE_VERIFY_AGENT=ralph-review \
  RALPH_TEST_POLICY_HASH="$policy_hash" \
  control run --workflow wf_reconciliation --feature FEATURE-RECONCILIATION \
    --lease "$lease" --engine opencode --test-cmd true --heartbeat-interval 1)"

printf '%s' "$run_output" | grep -q '"exit_code": 0' || fail 'retry OpenCode não terminou verde'

EVENTS_FILE="$project/.git/ralph-control/events.jsonl" php -r '
    $events = file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    $counts = ["delegation.failed" => 0, "delegation.completed" => 0, "recovery.required" => 0, "block.finished" => 0, "verification_heartbeat" => 0];
    $modes = [];
    foreach ($events as $line) {
        $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        $type = $event["type"] ?? "";
        if (array_key_exists($type, $counts)) {
            $counts[$type]++;
        }
        if ($type === "command.heartbeat" && (($event["facts"]["phase"] ?? null) === "verification")) {
            $counts["verification_heartbeat"]++;
        }
        if (in_array($type, ["delegation.failed", "delegation.completed"], true)) {
            $facts = $event["facts"] ?? [];
            $modes[] = $facts["execution_mode"] ?? "";
        }
    }
    sort($modes);
    if ($counts["delegation.failed"] !== 1 || $counts["delegation.completed"] !== 2 || $counts["recovery.required"] !== 0 || $counts["block.finished"] !== 1 || $counts["verification_heartbeat"] < 1
        || $modes !== ["impl", "impl", "verify"]) {
        fwrite(STDERR, json_encode(["counts" => $counts, "modes" => $modes])."\n");
        exit(1);
    }
' || fail 'ledger não separou retry histórico da execução normativa'

(cd "$project" && control verify >/dev/null)
printf 'OK: reconciliação OpenCode preservou retry e aprovou somente impl/verify finais.\n'
