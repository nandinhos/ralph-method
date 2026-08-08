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
import os
from pathlib import Path
proof = {
    'schema_version': '1.0.0',
    'status': 'verified',
    'agent': 'ralph-review',
    'target_root': str(Path(os.environ['TARGET']).resolve()),
    'policy_hash': os.environ['HASH'],
    'tree_hash_before': 'a' * 64,
    'tree_hash_after': 'a' * 64,
    'canary_absent': True,
    'tool_events_seen': 1,
    'forbidden_tools_seen': [],
    'denied_tools_seen': [],
    'session_id': 'ses_fixture_policy',
    'terminal_event': 'step_finish',
    'final_marker': 'READONLY_DENIED',
}
Path(os.environ['PROOF']).write_text(json.dumps(proof))
PY

php "$ROOT/adapters/opencode/policy.php" check \
  --repo-root "$TMP/project" --agent ralph-review --proof-file "$PROOF" >/dev/null

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
