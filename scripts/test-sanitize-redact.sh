#!/usr/bin/env bash
# Os blocos PHP abaixo usam aspas simples para evitar expansão shell acidental.
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-redaction-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

control="$(realpath "$ROOT/bin/ralph-control")"
canary="$(cat "$ROOT/tests/fixtures/redaction/canary-text.txt")"

sanitized="$(CANARY_INPUT="$canary" CONTROL_PATH="$control" php -r '
    $code = file_get_contents(getenv("CONTROL_PATH"));
    $code = preg_replace("/^#!.*?\\n/", "", $code);
    $code = preg_replace("/^<\\?php\\s*/", "", $code);
    $code = preg_replace("/".chr(92).chr(36)."arguments\\s*=\\s*args\\(".chr(92).chr(36)."argv\\);.*$/s", "", $code);
    eval($code);
    echo sanitize(getenv("CANARY_INPUT"));
')"

grep -q '\[REDACTED:token\]' <<<"$sanitized" || fail 'token não foi redigido'
grep -q '\[REDACTED:aws_secret\]' <<<"$sanitized" || fail 'aws_secret não foi redigido'
grep -q '\[REDACTED:private_key\]' <<<"$sanitized" || fail 'private_key não foi redigido'
grep -q '\[REDACTED:db_url\]' <<<"$sanitized" || fail 'db_url não foi redigido'
if grep -q 'ghp_abc123exampleREPLACEme\|verysecret\|postgres://user:pwd@host/db' <<<"$sanitized"; then
  fail 'valor sensível vazou no retorno de sanitize'
fi

typed="$(TYPED_INPUT='bearer=eyJhbGciOiJIUzI1NiJ9.secret cookie=session-id=private-cookie-value "cookie":"json-private-cookie-value" Cookie: session=header-cookie-value; tracking=header-cookie-value-2' CONTROL_PATH="$control" php -r '
    $code = file_get_contents(getenv("CONTROL_PATH"));
    $code = preg_replace("/^#!.*?\\n/", "", $code);
    $code = preg_replace("/^<\\?php\\s*/", "", $code);
    $code = preg_replace("/".chr(92).chr(36)."arguments\\s*=\\s*args\\(".chr(92).chr(36)."argv\\);.*$/s", "", $code);
    eval($code);
    echo sanitize(getenv("TYPED_INPUT"));
')"
grep -q '\[REDACTED:bearer\]' <<<"$typed" || fail 'bearer não foi redigido'
grep -q '\[REDACTED:cookie\]' <<<"$typed" || fail 'cookie não foi redigido'
if grep -q 'eyJhbGciOiJIUzI1NiJ9.secret\|private-cookie-value\|header-cookie-value' <<<"$typed"; then
  fail 'bearer/cookie vazou no retorno de sanitize'
fi
grep -q '\[REDACTED:cookie\]' <<<"$typed" || fail 'cookie estruturado não foi redigido'
if grep -q 'json-private-cookie-value' <<<"$typed"; then
  fail 'cookie estruturado vazou no retorno de sanitize'
fi

structured="$(CONTROL_PATH="$control" php -r '
    $code = file_get_contents(getenv("CONTROL_PATH"));
    $code = preg_replace("/^#!.*?\\n/", "", $code);
    $code = preg_replace("/^<\\?php\\s*/", "", $code);
    $code = preg_replace("/".chr(92).chr(36)."arguments\\s*=\\s*args\\(".chr(92).chr(36)."argv\\);.*$/s", "", $code);
    eval($code);
    echo json_encode(sanitize([
        "token" => "short-structured-token",
        "aws_secret" => "short-structured-aws-secret",
        "private_key" => "short-structured-private-key",
        "db_url" => "short-structured-db-url",
        "bearer" => "short-structured-bearer",
        "cookie" => "short-structured-cookie",
    ]), JSON_UNESCAPED_SLASHES);
')"
for kind in token aws_secret private_key db_url bearer cookie; do
  grep -q "\[REDACTED:$kind\]" <<<"$structured" || fail "chave estruturada $kind não foi redigida"
done
if grep -q 'short-structured-' <<<"$structured"; then
  fail 'valor sensível em facts estruturado vazou no retorno de sanitize'
fi

mkdir -p "$TMP"
git -C "$TMP" init -q
git -C "$TMP" config user.email ralph-method@example.invalid
git -C "$TMP" config user.name 'Ralph Method Redaction Test'
printf '%s\n' '# Redaction' > "$TMP/README.md"
printf '%s\n' '# Plan' > "$TMP/plan.md"
printf '%s\n' '{"schema_version":"1.3.0","workflow_id":"wf_redaction","plan_file":"plan.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-102A-SANITIZE-REDACT","title":"Redaction","position":1}]}' > "$TMP/workflow.json"
git -C "$TMP" add .
git -C "$TMP" commit -qm base

(cd "$TMP" && php "$control" init --workflow wf_redaction --manifest workflow.json >/dev/null)
lease="$(cd "$TMP" && php "$control" claim --workflow wf_redaction --feature FEATURE-102A-SANITIZE-REDACT --actor test | php -r '$payload=json_decode(stream_get_contents(STDIN), true, 512, JSON_THROW_ON_ERROR); echo $payload["lease_token"];')"

(cd "$TMP" && CANARY_INPUT="$canary" CONTROL_PATH="$control" php -r '
    $code = file_get_contents(getenv("CONTROL_PATH"));
    $code = preg_replace("/^#!.*?\\n/", "", $code);
    $code = preg_replace("/^<\\?php\\s*/", "", $code);
    $code = preg_replace("/".chr(92).chr(36)."arguments\\s*=\\s*args\\(".chr(92).chr(36)."argv\\);.*$/s", "", $code);
    eval($code);
    $base = [
        "workflow_id" => "wf_redaction",
        "feature_key" => "FEATURE-102A-SANITIZE-REDACT",
        "attempt" => 1,
        "type" => "telemetry.activity",
        "summary" => "redaction fixture",
        "facts" => ["path" => "tests/fixtures/redaction/canary-text.txt", "content" => getenv("CANARY_INPUT")],
        "actor" => ["type" => "test", "name" => "redaction"],
    ];
    appendEvent(array_merge($base, ["idempotency_key" => "idem_phase102a_canary"]));
    for ($i = 0; $i < 100; $i++) {
        appendEvent(array_merge($base, [
            "idempotency_key" => "idem_phase102a_".$i,
            "facts" => ["path" => "tests/fixtures/redaction/canary-text.txt", "content" => "token=secret-".$i],
        ]));
    }
')

LEDGER="$TMP/.git/ralph-control/events.jsonl" php -r '
    $events = file(getenv("LEDGER"), FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    $allEvents = [];
    $redacted = [];
    foreach ($events as $line) {
        $event = json_decode($line, true, 512, JSON_THROW_ON_ERROR);
        $allEvents[] = $event;
        if (($event["type"] ?? "") === "event.redacted") {
            $redacted[] = $event;
            $encoded = json_encode($event, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
            foreach (["ghp_abc123exampleREPLACEme", "verysecret", "postgres://user:pwd@host/db"] as $leak) {
                if (str_contains($encoded, $leak) || str_contains($encoded, "secret-")) {
                    fwrite(STDERR, "segredo vazou no event.redacted\n");
                    exit(1);
                }
            }
        }
    }
    if (count($redacted) !== 101) {
        fwrite(STDERR, "esperava 101 eventos event.redacted, obtido ".count($redacted)."\n");
        exit(2);
    }
    $canaryEvents = array_values(array_filter($redacted, static fn (array $event): bool => (($event["facts"]["redacted_count"] ?? 0) === 4)));
    $facts = $canaryEvents[0]["facts"] ?? [];
    if (($facts["redacted_count"] ?? 0) !== 4 || ($facts["redacted_kinds"] ?? []) !== ["token", "aws_secret", "private_key", "db_url"] || ($facts["path"] ?? "") !== "tests/fixtures/redaction/canary-text.txt") {
        fwrite(STDERR, "facts de redação inválidos: ".json_encode($facts)."\n");
        exit(3);
    }
    $expectedKeys = ["feature_key", "path", "redacted_count", "redacted_kinds"];
    $actualKeys = array_keys($facts);
    sort($expectedKeys);
    sort($actualKeys);
    if ($actualKeys !== $expectedKeys) {
        fwrite(STDERR, "event.redacted carregou conteúdo além dos metadados: ".json_encode($facts)."\n");
        exit(4);
    }

    $sourceEvents = array_values(array_filter($allEvents, static fn (array $event): bool => ($event["type"] ?? "") === "telemetry.activity"));
    $sourceFacts = $sourceEvents[0]["facts"] ?? [];
    if (($sourceFacts["redacted"] ?? false) !== true || ($sourceFacts["redacted_count"] ?? 0) !== 4) {
        fwrite(STDERR, "evento de origem não marcou facts.redacted/redacted_count: ".json_encode($sourceFacts)."\n");
        exit(5);
    }
'

(cd "$TMP" && php "$control" verify >/dev/null) || fail 'hash chain não permaneceu íntegra após 100 redações'

mkdir -p "$TMP/.git/ralph-control/artifacts"
printf '%s\n' 'Cookie: session=raw-cookie-value; tracking=second-raw-cookie-value' > "$TMP/.git/ralph-control/artifacts/FEATURE-102A-SANITIZE-REDACT-attempt-1.stderr.log"

diagnose_report="$(cd "$TMP" && RALPH_DEBUG_WORKFLOW_ID=wf_redaction RALPH_DEBUG_FEATURE_KEY=FEATURE-102A-SANITIZE-REDACT RALPH_DEBUG_ATTEMPT=1 RALPH_DEBUG_REDACTED_THRESHOLD=0 php "$ROOT/bin/ralph-diagnose.php")"
DIAGNOSE_REPORT="$diagnose_report" php -r '
    $report = json_decode(getenv("DIAGNOSE_REPORT"), true, 512, JSON_THROW_ON_ERROR);
    $facts = $report["facts"] ?? [];
    if (($facts["redaction_alert"]["status"] ?? "") !== "alert" || ($facts["redacted_count"] ?? 0) !== 104) {
        fwrite(STDERR, "diagnóstico não emitiu alerta de redação\n");
        exit(1);
    }
    $encoded = json_encode($report, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    foreach (["ghp_abc123exampleREPLACEme", "verysecret", "secret-0", "raw-cookie-value", "second-raw-cookie-value"] as $leak) {
        if (str_contains($encoded, $leak)) {
            fwrite(STDERR, "diagnóstico vazou um valor redigido\n");
            exit(2);
        }
    }
'

set +e
(cd "$TMP" && php "$control" run --workflow wf_redaction --feature FEATURE-102A-SANITIZE-REDACT --lease "$lease" --command 'exit 1' >/dev/null 2>&1)
set -e
debug_output="$(cd "$TMP" && php "$control" debug --workflow wf_redaction --feature FEATURE-102A-SANITIZE-REDACT --command "env RALPH_DEBUG_REDACTED_THRESHOLD=0 php $ROOT/bin/ralph-diagnose.php")" || {
  printf '%s\n' "$debug_output" >&2
  for artifact in "$TMP/.git/ralph-control/artifacts"/*; do
    [ -f "$artifact" ] || continue
    printf '%s: ' "$(basename "$artifact")" >&2
    tail -5 "$artifact" >&2
  done
  exit 1
}
report_md=("$TMP/.git/ralph-control/reports"/DBG-*.md)
[ -f "${report_md[0]}" ] || fail 'relatório DBG-*.md não foi criado'
grep -q '\[REDACTED:' "${report_md[0]}" || fail 'DBG-*.md não exibiu marcador de redação'
grep -q 'tests/fixtures/redaction/canary-text.txt' "${report_md[0]}" || fail 'DBG-*.md não exibiu o path sanitizado'
if grep -q 'ghp_abc123exampleREPLACEme\|verysecret\|secret-0\|raw-cookie-value\|second-raw-cookie-value' "${report_md[0]}"; then
  fail 'DBG-*.md contém valor redigido'
fi

printf 'OK: sanitize redige os seis tipos, audita facts sem vazamento e preserva a hash chain.\n'
