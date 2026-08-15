#!/usr/bin/env bash

# As expressões PHP recebem caminhos pelo ambiente e não expandem shell.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-agy-loop.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$TMP/bin" "$TMP/repo/adapters/agy" "$TMP/repo/.agents/agents/ralph-review" "$TMP/repo/scripts"
cp "$ROOT/scripts/ralph.sh" "$TMP/repo/scripts/ralph.sh"
cp "$ROOT/adapters/agy/runner.sh" "$TMP/repo/adapters/agy/runner.sh"
cp "$ROOT/adapters/agy/parser.php" "$TMP/repo/adapters/agy/parser.php"
cp "$ROOT/adapters/agy/policy.php" "$TMP/repo/adapters/agy/policy.php"
cp "$ROOT/.agents/agents/ralph-review/agent.md" "$TMP/repo/.agents/agents/ralph-review/agent.md"
printf '%s\n' 'oauth-fixture' > "$TMP/oauth-token"
cat > "$TMP/bin/agy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = '--version' ]; then printf '%s\n' 'agy 1.1.13'; exit 0; fi
if [[ " $* " == *' --help '* ]]; then
  printf '%s\n' '--print --output-format --model --effort --print-timeout --mode --sandbox --agent --add-dir'
  exit 0
fi
if [ "${*: -1}" = agents ]; then printf '%s\n' 'ralph-review'; exit 0; fi
printf '%s\n' "$*" > "${RALPH_TEST_AGY_ARGS:?}"
model=''
repo_root=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--model' ]; then model="$2"; shift 2; continue; fi
  if [ "$1" = '--add-dir' ]; then repo_root="$2"; shift 2; continue; fi
  shift
done
[ "${RALPH_TEST_MUTATE_SURFACE:-0}" != 1 ] || printf '%s\n' '# adulterado pela implementação' >> "$repo_root/adapters/agy/policy.php"
printf '{"event":"init","conversation_id":"conv_loop","init":{"model":"%s","cwd":"fixture","tools":[],"permission_mode":"always-proceed"}}\n' "$model"
printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_loop","step_index":1,"state":"DONE","step_type":"agent_response","text_delta":"LOOP_OK"}}'
printf '%s\n' '{"event":"result","result":{"conversation_id":"conv_loop","status":"SUCCESS","response":"LOOP_OK"}}'
EOF
chmod +x "$TMP/bin/agy"

cat > "$TMP/bin/bwrap" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' /bin/true '* ]] || [ "${*: -1}" = /bin/true ]; then exit 0; fi
printf '%s\n' "$*" > "${RALPH_TEST_BWRAP_ARGS:?}"
model=''
while [ "$#" -gt 0 ]; do
  if [ "$1" = '--model' ]; then model="$2"; shift 2; continue; fi
  shift
done
printf '{"event":"init","conversation_id":"conv_loop_verify","init":{"model":"%s","cwd":"fixture","tools":[],"permission_mode":"request-review","expanded_commands":[{"name":"plan","type":"system"}]}}\n' "$model"
printf '%s\n' '{"event":"step_update","step_update":{"conversation_id":"conv_loop_verify","step_index":1,"state":"DONE","step_type":"agent_response","text_delta":"TASK 1: DONE"}}'
printf '%s\n' '{"event":"result","result":{"conversation_id":"conv_loop_verify","status":"SUCCESS","response":"TASK 1: DONE"}}'
EOF
chmod +x "$TMP/bin/bwrap"

cat > "$TMP/bin/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' called > "${RALPH_TEST_CLAUDE_CALLED:?}"
exit 99
EOF
chmod +x "$TMP/bin/claude"

printf '%s\n' '# Fixture' > "$TMP/repo/README.md"
cat > "$TMP/repo/PHASES.md" <<'EOF'
# Plano

## Phase 1: Confirmar caminho do adapter

- [ ] **Task:** reconhecer que a fixture já está pronta.
  - **Acceptance criteria:** comando externo true termina verde.
EOF

git -C "$TMP/repo" init -q
git -C "$TMP/repo" config user.email ralph-method@example.invalid
git -C "$TMP/repo" config user.name 'Ralph Method agy Loop Test'
git -C "$TMP/repo" add README.md PHASES.md adapters .agents scripts
git -C "$TMP/repo" commit -qm base
cp -a "$TMP/repo" "$TMP/tamper-repo"

loop_exit=0
(
  cd "$TMP/repo"
  PATH="$TMP/bin:/usr/bin:/bin" \
  RALPH_AGY_MODEL=gemini-3.7-flash-high \
  RALPH_AGY_EFFORT=high \
  RALPH_AGY_TOKEN_FILE="$TMP/oauth-token" \
  RALPH_TEST_AGY_ARGS="$TMP/agy-args" \
  RALPH_TEST_BWRAP_ARGS="$TMP/bwrap-args" \
  RALPH_TEST_CLAUDE_CALLED="$TMP/claude-called" \
  ./scripts/ralph.sh --engine agy --test-cmd true PHASES.md \
    > "$TMP/loop.log" 2>&1
) || loop_exit=$?
if [ "$loop_exit" -ne 0 ]; then
  tail -n 80 "$TMP/loop.log" >&2
  fail "loop agy terminou com código $loop_exit"
fi

[ ! -e "$TMP/claude-called" ] || fail 'engine agy caiu no branch Claude'
grep -q -- '--mode accept-edits' "$TMP/agy-args" || fail 'loop não chamou impl agy'
grep -q -- '--mode plan' "$TMP/bwrap-args" || fail 'loop não chamou verify agy isolado'
LOG_DIR="$TMP/repo/.phases/logs" php -r '
  $modes=[];
  foreach (glob(getenv("LOG_DIR")."/*.result.json") ?: [] as $path) {
      $v=json_decode(file_get_contents($path), true, 512, JSON_THROW_ON_ERROR);
      if (($v["runner"]??null)!=="agy" || ($v["status"]??null)!=="completed" || ($v["terminal_event"]??null)!=="result") exit(1);
      $modes[$v["execution_mode"]??""]=($modes[$v["execution_mode"]??""]??0)+1;
  }
  exit(($modes["impl"]??0)===1 && ($modes["verify"]??0)===1 ? 0 : 1);
' || fail 'loop não publicou resultados impl e verify válidos'

tamper_exit=0
(
  cd "$TMP/tamper-repo"
  PATH="$TMP/bin:/usr/bin:/bin" \
  RALPH_AGY_MODEL=gemini-3.7-flash-high \
  RALPH_AGY_EFFORT=high \
  RALPH_AGY_TOKEN_FILE="$TMP/oauth-token" \
  RALPH_TEST_AGY_ARGS="$TMP/tamper-agy-args" \
  RALPH_TEST_BWRAP_ARGS="$TMP/tamper-bwrap-args" \
  RALPH_TEST_CLAUDE_CALLED="$TMP/claude-called" \
  RALPH_TEST_MUTATE_SURFACE=1 \
  ./scripts/ralph.sh --engine agy --test-cmd true PHASES.md \
    > "$TMP/tamper-loop.log" 2>&1
) || tamper_exit=$?
[ "$tamper_exit" -ne 0 ] || fail 'loop aceitou adapter adulterado pela implementação'
grep -q 'superfície de verificação.*mudou' "$TMP/tamper-loop.log" || fail 'loop não explicou a adulteração da superfície'
[ ! -e "$TMP/tamper-bwrap-args" ] || fail 'verify iniciou depois da adulteração do adapter'

printf '%s\n' 'OK: loop despachou impl/verify agy, não caiu em Claude e bloqueou superfície adulterada.'
