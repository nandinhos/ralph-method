#!/usr/bin/env bash

# Hero flow de campo isolado para o Cursor (FEATURE-102B). A prova executa o
# controlador sem --command: ele gera o ralph.sh, que chama o runner Cursor e
# a CLI fake. hero=true só é registrado depois de init, claim, run e da prova
# real do runner; os cinco gates então fecham o fluxo de produção promovido.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-cursor-hero.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

project="$TMP/checkout-de-campo"
mkdir -p "$project/.ralph" "$TMP/bin"
git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method Cursor Hero Test'
printf '%s\n' '# Cursor hero fixture' > "$project/README.md"
printf '%s\n' '## Phase 1: Cursor hero flow' '- [ ] implementação será executada pela CLI Cursor' > "$project/plan.md"
printf '%s\n' \
  'RALPH_BIN='"$ROOT/scripts/ralph.sh" \
  'RALPH_CURSOR_CLI='"$TMP/bin/agent" \
  'RALPH_CURSOR_MODEL=cursor/model-hero' \
  'RALPH_VERIFY=always' \
  > "$project/.ralph/cursor.env"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_cursor_hero","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-CURSOR-HERO","title":"Cursor hero flow","position":1}]}' > "$project/workflow.json"

cat > "$TMP/bin/agent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  --version)
    printf '%s\n' '0.1.0-cursor-hero-fixture'
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
    if [ "$verify" -eq 0 ]; then
      printf '%s\n' 'cursor-cli-hero-invoked' > "$workspace/cursor-hero-proof.txt"
    fi
    printf '%s\n' '{"type":"system","model":"cursor/model-hero","content":"init"}'
    if [ "$verify" -eq 1 ]; then
      printf '%s\n' '{"type":"text","content":"TASK 1: DONE"}'
      printf '%s\n' '{"type":"result","content":"verification complete"}'
    else
      printf '%s\n' '{"type":"result","content":"hero implementation complete"}'
    fi
    exit 0
    ;;
  *)
    exit 2
    ;;
esac
EOF
chmod +x "$TMP/bin/agent"
git -C "$project" add .
git -C "$project" commit -qm base

control() {
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

control init --workflow wf_cursor_hero --manifest workflow.json >/dev/null
initial_status="$(control provider-status --workflow wf_cursor_hero --format json)"
INITIAL_STATUS="$initial_status" php -r '
$value = json_decode(getenv("INITIAL_STATUS"), true, 512, JSON_THROW_ON_ERROR);
$state = $value["adapters"]["cursor"] ?? [];
  if (($state["optin"] ?? false) !== true
      || ($state["adversarial"] ?? true) !== false
      || ($state["hero"] ?? true) !== false
      || ($state["promoted"] ?? true) !== false
      || ($state["promotion_blockers"] ?? []) !== ["adversarial", "hero"]) {
      exit(1);
}
foreach (["opencode", "agy"] as $engine) {
    $legacy = $value["adapters"][$engine] ?? [];
    foreach (["optin", "adversarial", "hero", "promoted"] as $field) {
        if (($legacy[$field] ?? false) !== true) { exit(1); }
    }
    if (($legacy["promotion_blockers"] ?? ["unexpected"]) !== []) { exit(1); }
    if (($value[$engine] ?? null) !== $legacy) { exit(1); }
}
'

for adapter in opencode agy cursor; do
  [ -f "$project/.ralph/adapter-promotion/$adapter.json" ] \
    || fail "estado persistido ausente para o adapter $adapter"
done

# A prova adversarial é pré-requisito; hero continua falso enquanto o fluxo
# end-to-end executa sob a autorização explícita de prova, fora de produção.
control provider-status --workflow wf_cursor_hero --format json \
  --promote cursor --adversarial >/dev/null
claim="$(control claim --workflow wf_cursor_hero --feature FEATURE-CURSOR-HERO --actor cursor-hero-implementer)"
lease="$(json_field "$claim" lease_token)"
control run --workflow wf_cursor_hero --feature FEATURE-CURSOR-HERO --lease "$lease" \
  --engine cursor --promotion-proof hero --test-cmd true >/dev/null
[ -f "$project/cursor-hero-proof.txt" ] || fail 'o hero flow não atravessou a CLI Cursor'

before_hero="$(control provider-status --workflow wf_cursor_hero --format json)"
BEFORE_HERO="$before_hero" php -r '
  $value = json_decode(getenv("BEFORE_HERO"), true, 512, JSON_THROW_ON_ERROR);
  $state = $value["adapters"]["cursor"] ?? [];
  if (($state["adversarial"] ?? false) !== true
      || ($state["hero"] ?? true) !== false
      || ($state["promoted"] ?? true) !== false) {
      exit(1);
  }
'

# Só agora a evidência de hero é persistida e pode habilitar produção.
status="$(control provider-status --workflow wf_cursor_hero --format json --promote cursor --hero)"
STATUS="$status" php -r '
  $value = json_decode(getenv("STATUS"), true, 512, JSON_THROW_ON_ERROR);
  $state = $value["adapters"]["cursor"] ?? [];
  exit(($state["promoted"] ?? false) === true && ($state["promotion_blockers"] ?? ["blocked"]) === [] ? 0 : 1);
'

for gate in validation quality runtime_evidence technical_review curation; do
  producer="cursor-hero-${gate}"
  control gate --workflow wf_cursor_hero --feature FEATURE-CURSOR-HERO --lease "$lease" \
    --gate "$gate" --status passed --exit-code 0 --producer "$producer" >/dev/null
done

control approve --workflow wf_cursor_hero --feature FEATURE-CURSOR-HERO --lease "$lease" >/dev/null
status_final="$(control status)"
STATUS="$status_final" php -r '
  $value = json_decode(getenv("STATUS"), true, 512, JSON_THROW_ON_ERROR);
  $feature = $value["projection"]["features"][0] ?? [];
  exit(($feature["state"] ?? null) === "approved" ? 0 : 1);
'
(cd "$project" && php "$ROOT/bin/ralph-control" verify >/dev/null)

document_id="$(control document-id --workflow wf_cursor_hero \
  --feature FEATURE-CURSOR-HERO --kind RPT --scope promotion-blockers --plain)"
INDEX_FILE="$project/.git/ralph-control/document-index.json" DOCUMENT_ID="$document_id" php -r '
$index = json_decode(file_get_contents(getenv("INDEX_FILE")), true, 512, JSON_THROW_ON_ERROR);
foreach ($index["documents"] ?? [] as $document) {
    if (($document["id"] ?? null) === getenv("DOCUMENT_ID")) {
        exit(($document["metric"] ?? null) === "promotion_blockers" ? 0 : 1);
    }
}
exit(1);
' || fail 'document-id registry não registrou a métrica promotion_blockers'

printf 'ok   Cursor hero flow executou init, claim, runner/CLI, cinco gates e promoção somente após a prova\n'
