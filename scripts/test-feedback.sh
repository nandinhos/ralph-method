#!/usr/bin/env bash

# O bloco PHP recebe o caminho por variável de ambiente; não há expansão shell
# intencional dentro da expressão delimitada por aspas simples.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-feedback.XXXXXX")"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

mkdir -p "$TMP/project/.spec/init" "$TMP/bin"
git -C "$TMP/project" init -q
git -C "$TMP/project" config user.email ralph-method@example.invalid
git -C "$TMP/project" config user.name 'Ralph Method Test'
cat > "$TMP/project/.spec/init/project-phases.md" <<'EOF'
# Fases

## Phase 1: Feedback operacional token=nao-deve-vazar

- [ ] Criar o artefato da fase.
EOF
cat > "$TMP/project/workflow.json" <<'EOF'
{"schema_version":"1.0.0","workflow_id":"wf_feedback","plan_file":".spec/init/project-phases.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Feedback operacional","position":1}]}
EOF
git -C "$TMP/project" add .
git -C "$TMP/project" commit -qm base

(cd "$TMP/project" && php "$ROOT/bin/ralph-control" init --workflow wf_feedback --manifest workflow.json >/dev/null)

cat > "$TMP/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
prompt="$(cat)"
if grep -q 'RALPH_VERIFY' <<< "$prompt"; then
  printf 'TASK 1: DONE\n'
else
  printf '%s\n' 'artefato criado pela sessão fake' > feedback-artifact.txt
fi
EOF
chmod +x "$TMP/bin/codex"

cat > "$TMP/bin/feedback-consumer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${RALPH_FEEDBACK_CONSUMER_FAIL:-0}" = "1" ]; then
  exit 19
fi
cat > "$RALPH_FEEDBACK_CONSUMER_LOG"
EOF
chmod +x "$TMP/bin/feedback-consumer"

feedback_file="$TMP/project/.git/ralph-control/feedback/events.jsonl"
consumer_log="$TMP/consumer.jsonl"
output_file="$TMP/output.txt"
set +e
(
  cd "$TMP/project"
  PATH="$TMP/bin:$PATH" \
  RALPH_FEEDBACK_FILE="$feedback_file" \
  RALPH_FEEDBACK_STDOUT=1 \
  RALPH_FEEDBACK_CMD="$TMP/bin/feedback-consumer" \
  RALPH_FEEDBACK_CONSUMER_LOG="$consumer_log" \
  RALPH_VERIFY=always \
  RALPH_CODEX_PROFILE=test \
  RALPH_CODEX_MODEL=test-model \
  "$ROOT/scripts/ralph.sh" --test-cmd true
) >"$output_file" 2>&1
run_exit=$?
set -e
[ "$run_exit" -eq 0 ] || { sed -n '1,160p' "$output_file" >&2; fail "loop de feedback não terminou verde"; }

grep -q '^RALPH_FEEDBACK ' "$output_file" || fail 'feedback não apareceu na saída do loop'
[ -s "$feedback_file" ] || fail 'arquivo JSONL de feedback não foi criado'
[ -s "$consumer_log" ] || fail 'consumidor externo não recebeu feedback'

FEEDBACK_FILE="$feedback_file" php -r '
    $events = file(getenv("FEEDBACK_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    if (count($events) < 4) {
        exit(1);
    }
    $names = [];
    foreach ($events as $line) {
        $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        if (($event["schema_version"] ?? null) !== "1.0.0"
            || ($event["source"] ?? null) !== "ralph"
            || ! isset($event["run_id"], $event["timestamp"], $event["progress"]["percent"])) {
            exit(1);
        }
        if (str_contains($line, "nao-deve-vazar")) {
            exit(1);
        }
        $names[] = $event["event"] ?? null;
    }
    foreach (["run_start", "phase_start", "phase_done", "run_end"] as $required) {
        if (! in_array($required, $names, true)) {
            exit(1);
        }
    }
    $last = json_decode(end($events), true, 512, JSON_THROW_ON_ERROR);
    exit(($last["state"] ?? null) === "completed" && ($last["progress"]["percent"] ?? null) === 100 ? 0 : 1);
'

monitor_output="$(php "$ROOT/bin/ralph-monitor" --root "$TMP/project" --controller "$ROOT/bin/ralph-control" --workflow wf_feedback --once --json)"
MONITOR_JSON="$monitor_output" php -r '
    $snapshot = json_decode(getenv("MONITOR_JSON"), true, 512, JSON_THROW_ON_ERROR);
    $feedback = $snapshot["loop_feedback"] ?? null;
    exit(is_array($feedback) && ($feedback["event"] ?? null) === "run_end" ? 0 : 1);
'

failure_output="$(
  cd "$TMP/project"
  PATH="$TMP/bin:$PATH" \
  RALPH_FEEDBACK_FILE="$feedback_file" \
  RALPH_FEEDBACK_CMD="$TMP/bin/feedback-consumer" \
  RALPH_FEEDBACK_CONSUMER_LOG="$consumer_log" \
  RALPH_FEEDBACK_CONSUMER_FAIL=1 \
  RALPH_VERIFY=always \
  "$ROOT/scripts/ralph.sh" --test-cmd true 2>&1
)"
printf '%s\n' "$failure_output" | grep -q "consumidor falhou" || fail 'falha do callback não foi reportada'

printf 'OK: feedback JSONL, stdout, progresso e encerramento foram comprovados.\n'
