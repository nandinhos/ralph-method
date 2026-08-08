#!/usr/bin/env bash

# O PHP inline usa expressões literais dentro de aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-opencode-policy.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$TMP/project/.opencode/agents"
cp "$ROOT/.opencode/agents/ralph-review.md" "$TMP/project/.opencode/agents/ralph-review.md"
printf '%s\n' '{}' > "$TMP/project/opencode.json"

fingerprint="$(php "$ROOT/adapters/opencode/policy.php" hash --repo-root "$TMP/project" --agent ralph-review)"
hash_value="$(FINGERPRINT="$fingerprint" php -r '$v=json_decode(getenv("FINGERPRINT"), true, 512, JSON_THROW_ON_ERROR); echo $v["policy_hash"];')"
PROOF="$TMP/proof.json"

PROOF="$PROOF" TARGET="$TMP/project" HASH="$hash_value" python3 - <<'PY'
import json
import hashlib
import os
from pathlib import Path
proof = {
    'schema_version': '1.0.0',
    'status': 'verified',
    'agent': 'ralph-review',
    'target_root': str(Path(os.environ['TARGET']).resolve()),
    'policy_hash': os.environ['HASH'],
    'tree_hash_before': None,
    'tree_hash_after': None,
    'canary_absent': True,
    'tool_events_seen': 0,
    'forbidden_tools_seen': [],
    'denied_tools_seen': [],
    'policy_denied_tools': ['edit', 'bash'],
    'denial_evidence': {'edit': ['policy'], 'bash': ['policy']},
    'session_id': 'ses_fixture_policy',
    'terminal_event': 'step_finish',
    'final_marker': 'READONLY_DENIED',
    'attempts': 1,
}
event_file = Path(os.environ['PROOF'] + '.events.jsonl')
event_file.write_text('{"sessionID":"ses_fixture_policy","type":"start"}\n{"sessionID":"ses_fixture_policy","type":"text","text":"READONLY_DENIED"}\n{"sessionID":"ses_fixture_policy","type":"step_finish"}\n')
proof['event_log_sha256'] = hashlib.sha256(event_file.read_bytes()).hexdigest()

digest = hashlib.sha256()
root = Path(os.environ['TARGET'])
relative_paths = [f'.opencode/agents/ralph-review.md']
relative_paths.extend(name for name in ('opencode.json', 'opencode.jsonc', 'opencode.yaml', 'opencode.yml', 'opencode.toml') if (root / name).is_file())
for relative in sorted(relative_paths):
    item = root / relative
    digest.update(relative.encode())
    digest.update(b'\0')
    digest.update(hashlib.sha256(item.read_bytes()).digest())
proof['tree_hash_before'] = digest.hexdigest()
proof['tree_hash_after'] = digest.hexdigest()
Path(os.environ['PROOF']).write_text(json.dumps(proof))
PY

php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$PROOF" >/dev/null

cp "$PROOF" "$TMP/unknown-field.json"
cp "$PROOF.events.jsonl" "$TMP/unknown-field.json.events.jsonl"
PROOF="$TMP/unknown-field.json" python3 - <<'PY'
import json
import os
from pathlib import Path
path = Path(os.environ['PROOF'])
value = json.loads(path.read_text())
value['unexpected'] = True
path.write_text(json.dumps(value))
PY
unknown_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$TMP/unknown-field.json" >/dev/null 2>&1 || unknown_exit=$?
[ "$unknown_exit" -eq 1 ] || fail 'campo extra na prova foi aceito'

cp "$PROOF" "$TMP/missing-session.json"
cp "$PROOF.events.jsonl" "$TMP/missing-session.json.events.jsonl"
PROOF="$TMP/missing-session.json" python3 - <<'PY'
import json
import os
from pathlib import Path
path = Path(os.environ['PROOF'])
value = json.loads(path.read_text())
del value['session_id']
path.write_text(json.dumps(value))
PY
missing_session_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$TMP/missing-session.json" >/dev/null 2>&1 || missing_session_exit=$?
[ "$missing_session_exit" -eq 1 ] || fail 'prova sem sessão foi aceita'

cp "$PROOF" "$TMP/missing-marker.json"
cp "$PROOF.events.jsonl" "$TMP/missing-marker.json.events.jsonl"
PROOF="$TMP/missing-marker.json" python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path
proof_path = Path(os.environ['PROOF'])
event_path = Path(str(proof_path) + '.events.jsonl')
events = [json.loads(line) for line in event_path.read_text().splitlines() if 'READONLY_DENIED' not in line]
event_path.write_text(''.join(json.dumps(event) + '\n' for event in events))
proof = json.loads(proof_path.read_text())
proof['event_log_sha256'] = hashlib.sha256(event_path.read_bytes()).hexdigest()
proof_path.write_text(json.dumps(proof))
PY
missing_marker_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$TMP/missing-marker.json" >/dev/null 2>&1 || missing_marker_exit=$?
[ "$missing_marker_exit" -eq 1 ] || fail 'marcador ausente no JSONL foi aceito'

cp "$PROOF" "$TMP/fictitious-tree.json"
cp "$PROOF.events.jsonl" "$TMP/fictitious-tree.json.events.jsonl"
PROOF="$TMP/fictitious-tree.json" python3 - <<'PY'
import json
import os
from pathlib import Path
path = Path(os.environ['PROOF'])
value = json.loads(path.read_text())
value['tree_hash_before'] = 'a' * 64
value['tree_hash_after'] = 'a' * 64
path.write_text(json.dumps(value))
PY
fictitious_tree_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$TMP/fictitious-tree.json" >/dev/null 2>&1 || fictitious_tree_exit=$?
[ "$fictitious_tree_exit" -eq 1 ] || fail 'hash fictício da superfície de política foi aceito'

cp "$PROOF" "$TMP/fictitious-tool.json"
cp "$PROOF.events.jsonl" "$TMP/fictitious-tool.json.events.jsonl"
PROOF="$TMP/fictitious-tool.json" python3 - <<'PY'
import json
import os
from pathlib import Path
path = Path(os.environ['PROOF'])
value = json.loads(path.read_text())
value['policy_denied_tools'].append('write')
path.write_text(json.dumps(value))
PY
fictitious_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$TMP/fictitious-tool.json" >/dev/null 2>&1 || fictitious_exit=$?
[ "$fictitious_exit" -eq 1 ] || fail 'ferramenta fictícia na política foi aceita'

cp "$PROOF" "$TMP/mismatched-events.json"
cp "$PROOF.events.jsonl" "$TMP/mismatched-events.json.events.jsonl"
printf '%s\n' '{"type":"text","sessionID":"ses_fixture_policy","text":"alteração não refletida no hash"}' >> "$TMP/mismatched-events.json.events.jsonl"
mismatch_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$TMP/mismatched-events.json" >/dev/null 2>&1 || mismatch_exit=$?
[ "$mismatch_exit" -eq 1 ] || fail 'JSONL com hash divergente foi aceito'

printf '%s\n' '# alteração da política' >> "$TMP/project/.opencode/agents/ralph-review.md"
changed_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$PROOF" >/dev/null 2>&1 || changed_exit=$?
[ "$changed_exit" -eq 1 ] || fail 'política stale não foi bloqueada'

bad_exit=0
php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$TMP/project/proof.json" >/dev/null 2>&1 || bad_exit=$?
[ "$bad_exit" -eq 1 ] || fail 'prova dentro da raiz mutável foi aceita'

echo 'OK: fingerprint, prova externa, política stale e caminho mutável foram validados.'
