#!/usr/bin/env bash

# Os blocos PHP usam variáveis de ambiente para manter as expressões literais.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-knowledge-test.XXXXXX")"
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

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [ "$expected" = "$actual" ] || fail "$label (esperado=$expected recebido=$actual)"
}

mkdir -p "$TMP/project"
git -C "$TMP/project" init -q
git -C "$TMP/project" config user.email ralph-method@example.invalid
git -C "$TMP/project" config user.name 'Ralph Method Knowledge Test'
printf '%s\n' '# Conhecimento' > "$TMP/project/README.md"
printf '%s\n' '# Plano' > "$TMP/project/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_knowledge","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Handoff e memória","position":1}]}' > "$TMP/project/workflow.json"
git -C "$TMP/project" add README.md plan.md workflow.json
git -C "$TMP/project" commit -qm base

(cd "$TMP/project" && control init --workflow wf_knowledge --manifest workflow.json >/dev/null)
claim="$(cd "$TMP/project" && control claim --workflow wf_knowledge --feature FEATURE-001 --actor ralph)"
lease="$(json_field "$claim" lease_token)"

printf '%s\n' 'feature validada' > "$TMP/project/feature.txt"
git -C "$TMP/project" add feature.txt
git -C "$TMP/project" commit -qm '[feat] (feature): implementa feature de teste'
(cd "$TMP/project" && control finish --workflow wf_knowledge --feature FEATURE-001 --lease "$lease" --exit-code 0 >/dev/null)

for gate in validation quality runtime_evidence technical_review curation; do
  producer='quality-runner'
  actor='quality-runner'
  if [ "$gate" = 'validation' ]; then
    producer='validator'
    actor='validator'
  elif [ "$gate" = 'runtime_evidence' ]; then
    producer='runtime-proof'
    actor='runtime-proof'
  elif [ "$gate" = 'technical_review' ]; then
    producer='reviewer'
    actor='reviewer'
  elif [ "$gate" = 'curation' ]; then
    producer='curator'
    actor='curator'
  fi
  (cd "$TMP/project" && control gate --workflow wf_knowledge --feature FEATURE-001 --lease "$lease" \
    --gate "$gate" --status passed --producer "$producer" --actor "$actor" --exit-code 0 >/dev/null)
done

(cd "$TMP/project" && control approve --workflow wf_knowledge --feature FEATURE-001 --lease "$lease" >/dev/null)
(cd "$TMP/project" && control handoff --workflow wf_knowledge --feature FEATURE-001 --output .ralph/handoffs/FEATURE-001 >/dev/null)
(cd "$TMP/project" && control handoff-commit --workflow wf_knowledge --feature FEATURE-001 --lease "$lease" >/dev/null)
(cd "$TMP/project" && control release --workflow wf_knowledge --feature FEATURE-001 --lease "$lease" >/dev/null)

for file in bug-report.json bug-report.md evidence-manifest.json execution-summary.md; do
  [ -f "$TMP/project/.ralph/handoffs/FEATURE-001/$file" ] || fail "handoff sem $file"
done

candidates_before="$(cd "$TMP/project" && "$ROOT/bin/ralph-knowledge" candidates)"
printf '%s' "$candidates_before" | grep -q '"status": "pending"' || fail 'candidato pendente não foi materializado'
candidate_id="$(printf '%s' "$candidates_before" | php -r '$v=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR); echo $v["candidates"][0]["curation_id"] ?? "";')"
[ -f "$TMP/project/.ralph/knowledge-candidates/$candidate_id.json" ] || fail 'cache de candidato ausente'
if git -C "$TMP/project" status --porcelain | grep -q 'knowledge-candidates'; then
  fail 'cache de candidato contaminou a árvore de trabalho'
fi
grep -qxF '/.ralph/knowledge-candidates/' "$TMP/project/.git/info/exclude" || fail 'cache de candidato não foi isolado no exclude local'

# A entrega pode avançar antes da curadoria; conhecimento é non_blocking.
advance_output="$(cd "$TMP/project" && control advance --workflow wf_knowledge --feature FEATURE-001 --lease "$lease")"
assert_eq '' "$(json_field "$advance_output" next_feature)" 'workflow avançou para fila vazia sem curadoria'

candidate_before="$(cd "$TMP/project" && control status)"
STATUS_JSON="$candidate_before" php -r '
  $status = json_decode(getenv("STATUS_JSON"), true, 512, JSON_THROW_ON_ERROR);
  $feature = $status["projection"]["features"][0] ?? [];
  if (($feature["state"] ?? null) !== "released" || ($feature["knowledge_state"] ?? null) !== "knowledge_pending") {
      exit(1);
  }
'

curated="$(cd "$TMP/project" && control knowledge curated --workflow wf_knowledge --feature FEATURE-001 \
  --title 'Lock de execução precisa de workflow canônico' \
  --summary 'Validar o workflow carregado antes de derivar locks evita aliases de execução.' \
  --category architecture --root-cause workflow-identity-bypass \
  --topics concurrency,locks --stack php,bash --domain orchestration --fingerprints workflow-identity-bypass \
  --commit "$(git -C "$TMP/project" rev-parse HEAD~1)" \
  --test 'scripts/test-ralph-method.sh' 2>&1)"
lesson_id="$(json_field "$curated" lesson_id)"
printf '%s' "$lesson_id" | grep -Eq '^LES-[0-9]{4}-[0-9]{4}$' || fail 'lição curada recebeu ID padronizado'
[ -f "$TMP/project/docs/engineering/lessons/$lesson_id.yaml" ] || fail 'lição YAML ausente'
[ -f "$TMP/project/docs/engineering/lessons/$lesson_id.md" ] || fail 'lição Markdown ausente'
[ -f "$TMP/project/docs/engineering/INDEX.md" ] || fail 'índice de engenharia ausente'
[ -f "$TMP/project/docs/engineering/categories/architecture.md" ] || fail 'subíndice de categoria ausente'
[ -f "$TMP/project/docs/engineering/topics/concurrency.md" ] || fail 'subíndice de tema ausente'
grep -q 'topics:' "$TMP/project/docs/engineering/lessons/$lesson_id.yaml" || fail 'taxonomia não foi persistida'
grep -q 'workflow-identity-bypass' "$TMP/project/docs/engineering/lessons/$lesson_id.yaml" || fail 'fingerprint não foi persistido'

candidates_after="$(cd "$TMP/project" && "$ROOT/bin/ralph-knowledge" candidates)"
printf '%s' "$candidates_after" | grep -q '"status": "persisted"' || fail 'candidato não mudou para persisted'

curated_again="$(cd "$TMP/project" && control knowledge curated --workflow wf_knowledge --feature FEATURE-001 \
  --title 'Lock de execução precisa de workflow canônico' \
  --summary 'Validar o workflow carregado antes de derivar locks evita aliases de execução.' \
  --category architecture --root-cause workflow-identity-bypass \
  --commit "$(git -C "$TMP/project" rev-parse HEAD~1)" \
  --test 'scripts/test-ralph-method.sh' 2>&1)"
assert_eq "$lesson_id" "$(json_field "$curated_again" lesson_id)" 'curadoria repetida é idempotente'

conflict_exit=0
(cd "$TMP/project" && control knowledge rejected --workflow wf_knowledge --feature FEATURE-001 --reason 'decisão conflitante') >/dev/null 2>&1 || conflict_exit=$?
assert_eq '3' "$conflict_exit" 'decisão de retenção conflitante foi bloqueada'

retrieve="$(cd "$TMP/project" && "$ROOT/bin/ralph-knowledge" retrieve --query 'workflow lock aliases' --limit 1)"
assert_eq "$lesson_id" "$(json_field "$(printf '%s' "$retrieve" | php -r '$v=json_decode(stream_get_contents(STDIN), true); echo json_encode($v["lessons"][0] ?? []);')" lesson_id)" 'recuperação seletiva encontrou lição aplicável'
printf '%s' "$retrieve" | grep -q 'workflow-identity-bypass' || fail 'contexto recuperado contém causa raiz'

filtered="$(cd "$TMP/project" && "$ROOT/bin/ralph-knowledge" retrieve --query 'locks' --category architecture --topic concurrency --stack php --domain orchestration --fingerprint workflow-identity-bypass --limit 1)"
assert_eq "$lesson_id" "$(json_field "$(printf '%s' "$filtered" | php -r '$v=json_decode(stream_get_contents(STDIN), true); echo json_encode($v["lessons"][0] ?? []);')" lesson_id)" 'filtros de taxonomia encontraram lição aplicável'

irrelevant="$(cd "$TMP/project" && "$ROOT/bin/ralph-knowledge" retrieve --query 'database satellite astronomy' --limit 3)"
assert_eq '0' "$(printf '%s' "$irrelevant" | php -r '$v=json_decode(stream_get_contents(STDIN), true); echo count($v["lessons"] ?? []);')" 'conhecimento irrelevante não foi carregado'

EVENTS_FILE="$TMP/project/.git/ralph-control/events.jsonl" LESSON_ID="$lesson_id" php -r '
  $counts = [];
  $telemetryEvents = [];
  foreach (file(getenv("EVENTS_FILE"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [] as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      $type = $event["type"] ?? "";
      $counts[$type] = ($counts[$type] ?? 0) + 1;
      if ($type === "knowledge.telemetry") {
          $telemetryEvents[] = $event;
      }
  }
  if (($counts["feature.released"] ?? 0) !== 1 || ($counts["knowledge.candidate_created"] ?? 0) !== 1 || ($counts["knowledge.curated"] ?? 0) !== 1) {
      fwrite(STDERR, "contagem de eventos incorreta: ".json_encode($counts)."\n");
      exit(1);
  }
  if (count($telemetryEvents) < 2) {
      fwrite(STDERR, "esperava ao menos 2 eventos knowledge.telemetry (criação e curadoria), obtido: ".count($telemetryEvents)."\n");
      exit(2);
  }
  $firstTel = $telemetryEvents[0]["facts"] ?? [];
  if (($firstTel["action"] ?? "") !== "candidate_created" || ($firstTel["status"] ?? "") !== "pending" || ($firstTel["policy"] ?? "") !== "non_blocking") {
      fwrite(STDERR, "primeiro knowledge.telemetry inválido: ".json_encode($firstTel)."\n");
      exit(3);
  }
  $secondTel = $telemetryEvents[1]["facts"] ?? [];
  if (($secondTel["action"] ?? "") !== "curated" || ($secondTel["status"] ?? "") !== "persisted" || ($secondTel["lesson_id"] ?? "") !== getenv("LESSON_ID")) {
      fwrite(STDERR, "segundo knowledge.telemetry inválido: ".json_encode($secondTel)."\n");
      exit(4);
  }
  if (($secondTel["category"] ?? "") !== "architecture" || ! in_array("concurrency", $secondTel["topics"] ?? [], true)) {
      fwrite(STDERR, "taxonomia do knowledge.telemetry ausente: ".json_encode($secondTel)."\n");
      exit(5);
  }
' || fail 'verificação de eventos knowledge.telemetry falhou'

# Verificação de leitura read-only de knowledge_summary pelo ralph-monitor e ralph-watch
project_events_hash_before="$(sha256sum "$TMP/project/.git/ralph-control/events.jsonl")"

monitor_snap="$(cd "$TMP/project" && php "$ROOT/bin/ralph-monitor" --workflow wf_knowledge --once --json)"
MONITOR_SNAP="$monitor_snap" LESSON_ID="$lesson_id" php -r '
  $snap = json_decode(getenv("MONITOR_SNAP"), true, 512, JSON_THROW_ON_ERROR);
  $ks = $snap["knowledge_summary"] ?? null;
  if (! is_array($ks)) {
      fwrite(STDERR, "knowledge_summary ausente no snapshot do ralph-monitor\n");
      exit(1);
  }
  if (($ks["total"] ?? 0) !== 1 || ($ks["curated"] ?? 0) !== 1 || ($ks["pending"] ?? 0) !== 0) {
      fwrite(STDERR, "contagens de knowledge_summary no monitor incorretas: ".json_encode($ks)."\n");
      exit(2);
  }
  $cands = $ks["candidates"] ?? [];
  if (count($cands) !== 1 || ($cands[0]["status"] ?? "") !== "persisted" || ($cands[0]["lesson_id"] ?? "") !== getenv("LESSON_ID")) {
      fwrite(STDERR, "candidatos no monitor incorretos: ".json_encode($cands)."\n");
      exit(3);
  }
' || fail 'ralph-monitor não expôs knowledge_summary corretamente'

watch_snap="$(cd "$TMP/project" && php "$ROOT/bin/ralph-watch" --workflow wf_knowledge --once --json)"
WATCH_SNAP="$watch_snap" LESSON_ID="$lesson_id" php -r '
  $snap = json_decode(getenv("WATCH_SNAP"), true, 512, JSON_THROW_ON_ERROR);
  $ks = $snap["knowledge_summary"] ?? null;
  if (! is_array($ks)) {
      fwrite(STDERR, "knowledge_summary ausente no snapshot do ralph-watch\n");
      exit(1);
  }
  if (($ks["total"] ?? 0) !== 1 || ($ks["curated"] ?? 0) !== 1 || ($ks["pending"] ?? 0) !== 0) {
      fwrite(STDERR, "contagens de knowledge_summary no watch incorretas: ".json_encode($ks)."\n");
      exit(2);
  }
' || fail 'ralph-watch não expôs knowledge_summary corretamente'

# Validação da renderização TUI do ralph-watch com candidatos curados
watch_tui="$(cd "$TMP/project" && php "$ROOT/bin/ralph-watch" --workflow wf_knowledge --once)"
printf '%s\n' "$watch_tui" | grep -q "FILA DE CONHECIMENTO & LIÇÕES" || fail 'TUI do ralph-watch não exibiu seção de conhecimento'
printf '%s\n' "$watch_tui" | grep -q "$lesson_id" || fail "TUI do ralph-watch não listou lição $lesson_id"
printf '%s\n' "$watch_tui" | grep -q "CURATED" || fail 'TUI do ralph-watch não exibiu badge CURATED'

project_events_hash_after="$(sha256sum "$TMP/project/.git/ralph-control/events.jsonl")"
assert_eq "$project_events_hash_before" "$project_events_hash_after" 'monitor e watch não mutaram o ledger de eventos'

(cd "$TMP/project" && control verify) >/dev/null

# Um segundo projeto comprova que rejeitar/descartar o candidato não publica lição e sanitiza segredo-canário.
mkdir -p "$TMP/discard"
git -C "$TMP/discard" init -q
git -C "$TMP/discard" config user.email ralph-method@example.invalid
git -C "$TMP/discard" config user.name 'Ralph Method Knowledge Discard Test'
printf '%s\n' '# Descarte' > "$TMP/discard/README.md"
printf '%s\n' '# Plano' > "$TMP/discard/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_discard","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Candidato descartável api_key=sk-live-canary1234567890","position":1}]}' > "$TMP/discard/workflow.json"
git -C "$TMP/discard" add README.md plan.md workflow.json
git -C "$TMP/discard" commit -qm base
(cd "$TMP/discard" && control init --workflow wf_discard --manifest workflow.json >/dev/null)
discard_claim="$(cd "$TMP/discard" && control claim --workflow wf_discard --feature FEATURE-001 --actor ralph)"
discard_lease="$(json_field "$discard_claim" lease_token)"
printf '%s\n' 'candidato sem retenção' > "$TMP/discard/feature.txt"
git -C "$TMP/discard" add feature.txt
git -C "$TMP/discard" commit -qm '[feat] (feature): candidato descartável'
(cd "$TMP/discard" && control finish --workflow wf_discard --feature FEATURE-001 --lease "$discard_lease" --exit-code 0 >/dev/null)
for gate in validation quality runtime_evidence technical_review curation; do
  (cd "$TMP/discard" && control gate --workflow wf_discard --feature FEATURE-001 --lease "$discard_lease" \
    --gate "$gate" --status passed --producer test --actor test --exit-code 0 >/dev/null)
done
(cd "$TMP/discard" && control approve --workflow wf_discard --feature FEATURE-001 --lease "$discard_lease" >/dev/null)
(cd "$TMP/discard" && control handoff --workflow wf_discard --feature FEATURE-001 --output .ralph/handoffs/FEATURE-001 >/dev/null)
(cd "$TMP/discard" && control handoff-commit --workflow wf_discard --feature FEATURE-001 --lease "$discard_lease" >/dev/null)
(cd "$TMP/discard" && control release --workflow wf_discard --feature FEATURE-001 --lease "$discard_lease" >/dev/null)
(cd "$TMP/discard" && control knowledge rejected --workflow wf_discard --feature FEATURE-001 --reason 'token=ghp_secretCanary123456789012345 sem aprendizado reutilizável' >/dev/null)
[ ! -d "$TMP/discard/docs/engineering/lessons" ] || [ -z "$(find "$TMP/discard/docs/engineering/lessons" -type f -print -quit)" ] || fail 'candidato rejeitado publicou lição'

DISCARD_EVENTS="$TMP/discard/.git/ralph-control/events.jsonl" php -r '
  $lines = file(getenv("DISCARD_EVENTS"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $rejectedTel = null;
  $createdTel = null;
  foreach ($lines as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"] ?? "") === "knowledge.telemetry") {
          if (($event["facts"]["action"] ?? "") === "rejected") {
              $rejectedTel = $event;
          } elseif (($event["facts"]["action"] ?? "") === "candidate_created") {
              $createdTel = $event;
          }
      }
  }
  if ($createdTel === null || $rejectedTel === null) {
      fwrite(STDERR, "eventos knowledge.telemetry não encontrados\n");
      exit(1);
  }
  $cFacts = $createdTel["facts"] ?? [];
  if (str_contains($cFacts["title"] ?? "", "sk-live-canary1234567890")) {
      fwrite(STDERR, "canário de segredo vazou no título do candidate_created: ".json_encode($cFacts)."\n");
      exit(2);
  }
  if (! str_contains($cFacts["title"] ?? "", "[REDACTED]")) {
      fwrite(STDERR, "título do candidate_created não foi redigido: ".json_encode($cFacts)."\n");
      exit(3);
  }
  $rFacts = $rejectedTel["facts"] ?? [];
  if (($rFacts["status"] ?? "") !== "rejected" || ($rFacts["policy"] ?? "") !== "non_blocking") {
      fwrite(STDERR, "fatos do knowledge.telemetry de rejeição inválidos: ".json_encode($rFacts)."\n");
      exit(4);
  }
  if (str_contains($rFacts["reason"] ?? "", "ghp_secretCanary123456789012345")) {
      fwrite(STDERR, "canário de segredo vazou na razão da rejeição: ".json_encode($rFacts)."\n");
      exit(5);
  }
  if (! str_contains($rFacts["reason"] ?? "", "[REDACTED]")) {
      fwrite(STDERR, "razão da rejeição não foi redigida: ".json_encode($rFacts)."\n");
      exit(6);
  }
' || fail 'verificação de knowledge.telemetry de rejeição e sanitização falhou'

discard_monitor_snap="$(cd "$TMP/discard" && php "$ROOT/bin/ralph-monitor" --workflow wf_discard --once --json)"
DISCARD_SNAP="$discard_monitor_snap" php -r '
  $snap = json_decode(getenv("DISCARD_SNAP"), true, 512, JSON_THROW_ON_ERROR);
  $ks = $snap["knowledge_summary"] ?? null;
  if (! is_array($ks) || ($ks["rejected"] ?? 0) !== 1 || ($ks["curated"] ?? 0) !== 0 || ($ks["pending"] ?? 0) !== 0) {
      fwrite(STDERR, "knowledge_summary de rejeição inválido: ".json_encode($ks)."\n");
      exit(1);
  }
' || fail 'ralph-monitor não exibiu contagem de rejeição corretamente'

(cd "$TMP/discard" && control verify) >/dev/null

# Um terceiro projeto comprova skipped e review-required
mkdir -p "$TMP/decisions"
git -C "$TMP/decisions" init -q
git -C "$TMP/decisions" config user.email ralph-method@example.invalid
git -C "$TMP/decisions" config user.name 'Ralph Method Knowledge Decisions Test'
printf '%s\n' '# Decisões' > "$TMP/decisions/README.md"
printf '%s\n' '# Plano' > "$TMP/decisions/plan.md"
printf '%s\n' '{"schema_version":"1.0.0","workflow_id":"wf_decisions","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Candidato skipped","position":1},{"feature_key":"FEATURE-002","title":"Candidato review required","position":2}]}' > "$TMP/decisions/workflow.json"
git -C "$TMP/decisions" add README.md plan.md workflow.json
git -C "$TMP/decisions" commit -qm base
(cd "$TMP/decisions" && control init --workflow wf_decisions --manifest workflow.json >/dev/null)

# FEATURE-001: skipped
f1_claim="$(cd "$TMP/decisions" && control claim --workflow wf_decisions --feature FEATURE-001 --actor ralph)"
f1_lease="$(json_field "$f1_claim" lease_token)"
printf '%s\n' 'f1' > "$TMP/decisions/f1.txt"
git -C "$TMP/decisions" add f1.txt
git -C "$TMP/decisions" commit -qm '[feat] f1'
(cd "$TMP/decisions" && control finish --workflow wf_decisions --feature FEATURE-001 --lease "$f1_lease" --exit-code 0 >/dev/null)
for gate in validation quality runtime_evidence technical_review curation; do
  (cd "$TMP/decisions" && control gate --workflow wf_decisions --feature FEATURE-001 --lease "$f1_lease" \
    --gate "$gate" --status passed --producer test --actor test --exit-code 0 >/dev/null)
done
(cd "$TMP/decisions" && control approve --workflow wf_decisions --feature FEATURE-001 --lease "$f1_lease" >/dev/null)
(cd "$TMP/decisions" && control handoff --workflow wf_decisions --feature FEATURE-001 --output .ralph/handoffs/FEATURE-001 >/dev/null)
(cd "$TMP/decisions" && control handoff-commit --workflow wf_decisions --feature FEATURE-001 --lease "$f1_lease" >/dev/null)
(cd "$TMP/decisions" && control release --workflow wf_decisions --feature FEATURE-001 --lease "$f1_lease" >/dev/null)
(cd "$TMP/decisions" && control knowledge skipped --workflow wf_decisions --feature FEATURE-001 >/dev/null)

# FEATURE-002: review-required
(cd "$TMP/decisions" && control advance --workflow wf_decisions --feature FEATURE-001 --lease "$f1_lease" >/dev/null)
f2_claim="$(cd "$TMP/decisions" && control claim --workflow wf_decisions --feature FEATURE-002 --actor ralph)"
f2_lease="$(json_field "$f2_claim" lease_token)"
printf '%s\n' 'f2' > "$TMP/decisions/f2.txt"
git -C "$TMP/decisions" add f2.txt
git -C "$TMP/decisions" commit -qm '[feat] f2'
(cd "$TMP/decisions" && control finish --workflow wf_decisions --feature FEATURE-002 --lease "$f2_lease" --exit-code 0 >/dev/null)
for gate in validation quality runtime_evidence technical_review curation; do
  (cd "$TMP/decisions" && control gate --workflow wf_decisions --feature FEATURE-002 --lease "$f2_lease" \
    --gate "$gate" --status passed --producer test --actor test --exit-code 0 >/dev/null)
done
(cd "$TMP/decisions" && control approve --workflow wf_decisions --feature FEATURE-002 --lease "$f2_lease" >/dev/null)
(cd "$TMP/decisions" && control handoff --workflow wf_decisions --feature FEATURE-002 --output .ralph/handoffs/FEATURE-002 >/dev/null)
(cd "$TMP/decisions" && control handoff-commit --workflow wf_decisions --feature FEATURE-002 --lease "$f2_lease" >/dev/null)
(cd "$TMP/decisions" && control release --workflow wf_decisions --feature FEATURE-002 --lease "$f2_lease" >/dev/null)
(cd "$TMP/decisions" && control knowledge review-required --workflow wf_decisions --feature FEATURE-002 --reason 'necessita parecer de arquitetura' >/dev/null)

DECISIONS_EVENTS="$TMP/decisions/.git/ralph-control/events.jsonl" php -r '
  $lines = file(getenv("DECISIONS_EVENTS"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
  $skippedTel = null;
  $reviewTel = null;
  foreach ($lines as $line) {
      $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
      if (($event["type"] ?? "") === "knowledge.telemetry") {
          $action = $event["facts"]["action"] ?? "";
          if ($action === "skipped") {
              $skippedTel = $event;
          } elseif ($action === "review_required") {
              $reviewTel = $event;
          }
      }
  }
  if ($skippedTel === null || $reviewTel === null) {
      fwrite(STDERR, "eventos skipped e review_required não encontrados\n");
      exit(1);
  }
  if (($skippedTel["facts"]["status"] ?? "") !== "skipped" || ($skippedTel["facts"]["policy"] ?? "") !== "non_blocking") {
      fwrite(STDERR, "fatos do skipped inválidos: ".json_encode($skippedTel)."\n");
      exit(2);
  }
  if (($reviewTel["facts"]["status"] ?? "") !== "review_required" || ($reviewTel["facts"]["policy"] ?? "") !== "non_blocking") {
      fwrite(STDERR, "fatos do review_required inválidos: ".json_encode($reviewTel)."\n");
      exit(3);
  }
' || fail 'verificação de telemetria skipped e review-required falhou'

decisions_monitor_snap="$(cd "$TMP/decisions" && php "$ROOT/bin/ralph-monitor" --workflow wf_decisions --once --json)"
DECISIONS_SNAP="$decisions_monitor_snap" php -r '
  $snap = json_decode(getenv("DECISIONS_SNAP"), true, 512, JSON_THROW_ON_ERROR);
  $ks = $snap["knowledge_summary"] ?? null;
  if (! is_array($ks) || ($ks["total"] ?? 0) !== 2 || ($ks["skipped"] ?? 0) !== 1 || ($ks["review_required"] ?? 0) !== 1) {
      fwrite(STDERR, "knowledge_summary de decisões inválido: ".json_encode($ks)."\n");
      exit(1);
  }
' || fail 'ralph-monitor não exibiu contagens de skipped e review_required corretamente'

(cd "$TMP/decisions" && control verify) >/dev/null

printf 'OK: handoff, taxonomia, índices, retenção seletiva, descarte, skipped, review-required, sanitização, monitor e watch passaram (%s).\n' "$lesson_id"
