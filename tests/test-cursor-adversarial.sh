#!/usr/bin/env bash

# Prova adversarial offline do gate de promoção do Cursor (FEATURE-102B).
# Cada cenário é tentado com o adapter rebaixado e repetido depois da prova;
# os dois caminhos pós-promoção atravessam scripts/ralph.sh, o adapter e uma
# CLI Cursor fake determinística. O caso de claim divergente continua sendo
# rejeitado mesmo após a promoção e só passa quando o lease correto é usado.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-cursor-adversarial.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control() {
  local project="$1"
  shift
  (cd "$project" && php "$ROOT/bin/ralph-control" "$@")
}

json_field() {
  local payload="$1"
  local field="$2"
  JSON_PAYLOAD="$payload" JSON_FIELD="$field" php -r '
    $value = json_decode(getenv("JSON_PAYLOAD"), true, 512, JSON_THROW_ON_ERROR)[getenv("JSON_FIELD")] ?? null;
    if (! is_scalar($value)) { exit(1); }
    echo $value;
  '
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf '%s\n' '0.1.0-cursor-promotion-fixture'
    exit 0
    ;;
  -p)
    workspace=''
    previous=''
    verify=0
    for argument in "$@"; do
      if [ "$previous" = '--workspace' ]; then
        workspace="$argument"
      fi
      if [ "$previous" = '--mode' ] && [ "$argument" = 'ask' ]; then
        verify=1
      fi
      previous="$argument"
    done
    [ -n "$workspace" ] || exit 2
    # Registra o prompt recebido para que cada cenário hostil possa ser
    # comprovado novamente no caminho promovido, e não apenas por uma
    # execução genérica do runner.
    printf '%s\n' "${!#}" >> "$workspace/cursor-prompt.txt"
    if [ "$verify" -eq 0 ]; then
      printf '%s\n' 'cursor-cli-invoked' > "$workspace/cursor-cli-proof.txt"
    fi
    printf '%s\n' '{"type":"system","model":"cursor/model-adversarial","content":"init"}'
    if [ "$verify" -eq 1 ]; then
      printf '%s\n' '{"type":"text","content":"TASK 1: DONE"}'
      printf '%s\n' '{"type":"result","content":"verification complete"}'
    else
      printf '%s\n' '{"type":"result","content":"adversarial fixture handled"}'
    fi
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$TMP/bin/agent"

new_project() {
  local project="$1"
  local scenario="$2"
  mkdir -p "$project/.ralph"
  git -C "$project" init -q
  git -C "$project" config user.email ralph-method@example.invalid
  git -C "$project" config user.name 'Ralph Method Cursor Adversarial Test'
  case "$scenario" in
    malicious)
      printf '%s\n' '## Phase 1: input hostile' '- [ ] token=ghp_adversarial_secret' > "$project/plan.md"
      ;;
    allowlist)
      printf '%s\n' '## Phase 1: comando hostil' '- [ ] run_command --allow-all rm -f README.md' > "$project/plan.md"
      ;;
    claim)
      printf '%s\n' '## Phase 1: claim hostil' '- [ ] claim deve ser conferido pelo controlador' > "$project/plan.md"
      ;;
    *)
      fail "cenário desconhecido: $scenario"
      ;;
  esac
  printf '%s\n' '# Cursor adversarial fixture' > "$project/README.md"
  printf '%s\n' \
    'RALPH_BIN='"$ROOT/scripts/ralph.sh" \
    'RALPH_CURSOR_CLI='"$TMP/bin/agent" \
    'RALPH_CURSOR_MODEL=cursor/model-adversarial' \
    'RALPH_VERIFY=always' \
    > "$project/.ralph/cursor.env"
  printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_cursor_adversarial","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-CURSOR-ADVERSARIAL","title":"Cursor adversarial fixture","position":1}]}' > "$project/workflow.json"
  git -C "$project" add .
  git -C "$project" commit -qm base
  control "$project" init --workflow wf_cursor_adversarial --manifest workflow.json >/dev/null
}

assert_rejected_while_demoted() {
  local project="$1"
  local lease="$2"
  local command="$3"
  local label="$4"
  local output exit_code
  set +e
  output="$(control "$project" run --workflow wf_cursor_adversarial \
    --feature FEATURE-CURSOR-ADVERSARIAL --lease "$lease" --engine cursor \
    --command "$command" 2>&1)"
  exit_code=$?
  set -e
  [ "$exit_code" -ne 0 ] || fail "$label atravessou o Cursor rebaixado"
  printf '%s' "$output" | grep -Fq 'cursor rebaixado; rode tests/test-cursor-adversarial.sh e test-cursor-hero.sh' \
    || fail "$label não exibiu o bloqueio canônico"
}

run_through_cursor_runner() {
  local project="$1"
  local lease="$2"
  local scenario="$3"
  control "$project" run --workflow wf_cursor_adversarial \
    --feature FEATURE-CURSOR-ADVERSARIAL --lease "$lease" --engine cursor \
    --test-cmd true >/dev/null
  [ -f "$project/cursor-cli-proof.txt" ] || fail 'a CLI Cursor não foi executada após a promoção'
  case "$scenario" in
    malicious)
      grep -Fq 'token=ghp_adversarial_secret' "$project/cursor-prompt.txt" \
        || fail 'input malicioso não foi reexecutado pelo Cursor após a promoção'
      ;;
    allowlist)
      grep -Fq 'run_command --allow-all rm -f README.md' "$project/cursor-prompt.txt" \
        || fail 'comando fora da allowlist não foi reexecutado pelo Cursor após a promoção'
      ;;
    claim)
      grep -Fq 'claim deve ser conferido pelo controlador' "$project/cursor-prompt.txt" \
        || fail 'cenário de claim não foi reexecutado pelo Cursor após a promoção'
      ;;
    *)
      fail "cenário promovido desconhecido: $scenario"
      ;;
  esac
}

run_case() {
  local scenario="$1"
  local project="$TMP/$scenario"
  local claim lease promoted_claim output exit_code
  new_project "$project" "$scenario"
  claim="$(control "$project" claim --workflow wf_cursor_adversarial \
    --feature FEATURE-CURSOR-ADVERSARIAL --actor adversarial-test)"
  lease="$(json_field "$claim" lease_token)"

  case "$scenario" in
    malicious)
      assert_rejected_while_demoted "$project" "$lease" \
        'printf "token=ghp_adversarial_secret" > escaped.txt' 'input malicioso'
      ;;
    allowlist)
      assert_rejected_while_demoted "$project" "$lease" \
        'run_command --allow-all rm -f README.md' 'comando fora da allowlist'
      ;;
    claim)
      assert_rejected_while_demoted "$project" "${lease}divergent" \
        'true' 'claim divergente'
      ;;
  esac

  promoted_claim="$(control "$project" provider-status --workflow wf_cursor_adversarial \
    --format json --promote cursor --adversarial --hero)"
  PROMOTED_STATUS="$promoted_claim" php -r '
    $value = json_decode(getenv("PROMOTED_STATUS"), true, 512, JSON_THROW_ON_ERROR);
    $state = $value["adapters"]["cursor"] ?? [];
    foreach (["optin", "adversarial", "hero", "promoted"] as $field) {
        if (($state[$field] ?? false) !== true) { exit(1); }
    }
    if (($state["promotion_blockers"] ?? ["unexpected"]) !== []) { exit(1); }
  '

  if [ "$scenario" = claim ]; then
    set +e
    output="$(control "$project" run --workflow wf_cursor_adversarial \
      --feature FEATURE-CURSOR-ADVERSARIAL --lease "${lease}divergent" \
      --engine cursor --test-cmd true 2>&1)"
    exit_code=$?
    set -e
    [ "$exit_code" -ne 0 ] || fail 'claim divergente foi aceita após a promoção'
    printf '%s' "$output" | grep -Eiq 'lease|token|diverg' \
      || fail 'claim divergente não foi reportada como divergência de lease'
  fi

  # Reexecução pós-promoção: sem --command, o controlador gera o comando
  # normativo e scripts/ralph.sh atravessa adapters/cursor/runner.sh e agent.
  # O prompt é conferido para garantir que o cenário hostil específico foi
  # reexecutado após a promoção, e não substituído por um smoke genérico.
  run_through_cursor_runner "$project" "$lease" "$scenario"
}

run_case malicious
run_case allowlist
run_case claim

printf 'ok   Cursor rebaixado rejeita três cenários hostis e a reexecução promovida usa runner/CLI; lease divergente continua bloqueado\n'
