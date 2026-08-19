#!/usr/bin/env bash

# Regressão do contrato de snapshot (schemas/monitor-snapshot.schema.json) e do
# painel somente leitura servido por `ralph-monitor serve`.
#
# A fixture é offline: git local, controlador e processos falsos. Nunca usa
# provider real, credencial ou rede externa — o servidor só escuta em loopback.
#
# shellcheck disable=SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/ralph-method-monitor-ui.XXXXXX")"
SERVER_PID=""
FAKE_RUNNER_PID=""
OBSERVER_PID=""

cleanup() {
  for pid in "$SERVER_PID" "$FAKE_RUNNER_PID" "$OBSERVER_PID"; do
    if [ -n "$pid" ]; then
      kill -KILL "$pid" 2>/dev/null || true
    fi
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

fail() {
  printf 'FALHA: %s\n' "$1" >&2
  exit 1
}

ok() {
  printf '  ok    %s\n' "$1"
}

project="$TMP/project"
mkdir -p "$project/.spec/init"
git -C "$project" init -q
git -C "$project" config user.email ralph-method@example.invalid
git -C "$project" config user.name 'Ralph Method Monitor UI Test'
cat > "$project/.spec/init/project-phases.md" <<'EOF'
# Fases

## Phase 1: painel

- [ ] Criar o artefato da fase.
EOF
cat > "$project/workflow.json" <<'EOF'
{"schema_version":"1.0.0","workflow_id":"wf_painel","plan_file":".spec/init/project-phases.md","knowledge_policy":{"mode":"non_blocking"},"features":[{"feature_key":"FEATURE-001","title":"Publicar snapshot","position":1},{"feature_key":"FEATURE-002","title":"Renderizar painel","position":2}]}
EOF
git -C "$project" add .
git -C "$project" commit -qm base
(cd "$project" && php "$ROOT/bin/ralph-control" init --workflow wf_painel --manifest workflow.json >/dev/null)

snapshot() {
  php "$ROOT/bin/ralph-monitor" --root "$project" --controller "$ROOT/bin/ralph-control" \
    --feedback-file "$TMP/latest.json" --once --json
}

printf '\n== Contrato: snapshot valida contra o schema publicado ==\n'
# Sem --workflow: o checkout já declara qual é, e a UI não pode depender de o
# operador saber o identificador de cor.
discovered="$(snapshot)"
SNAPSHOT="$discovered" SCHEMA="$ROOT/schemas/monitor-snapshot.schema.json" python3 - <<'PY' || fail 'snapshot não valida contra monitor-snapshot.schema.json'
import json
import os

from jsonschema import Draft202012Validator

with open(os.environ['SCHEMA'], encoding='utf-8') as handle:
    schema = json.load(handle)
errors = list(Draft202012Validator(schema).iter_errors(json.loads(os.environ['SNAPSHOT'])))
if errors:
    raise SystemExit('schema rejeitou o snapshot: %r' % ([list(error.path) for error in errors],))
PY
ok 'snapshot publicado valida contra o contrato versionado'

SNAPSHOT="$discovered" php -r '
    $snapshot = json_decode(getenv("SNAPSHOT"), true, 512, JSON_THROW_ON_ERROR);
    if (($snapshot["schema_version"] ?? null) !== "1.0.0") { exit(1); }
    if (($snapshot["workflow_id"] ?? null) !== "wf_painel") { exit(2); }
    if (($snapshot["project"]["name"] ?? null) !== "project") { exit(3); }
    if (count($snapshot["features"] ?? []) !== 2) { exit(4); }
    $gates = array_column($snapshot["gates"] ?? [], "status", "gate");
    if (array_keys($gates) !== ["validation", "quality", "runtime_evidence", "technical_review", "curation"]) { exit(5); }
    if (array_unique(array_values($gates)) !== ["pending"]) { exit(6); }
    if (($snapshot["timeline"][0]["type"] ?? null) !== "workflow.initialized") { exit(7); }
    if (! array_key_exists("runner", $snapshot) || ! array_key_exists("name", $snapshot["runner"])) { exit(8); }
' || fail 'snapshot sem descoberta de workflow, features, gates nomeados, timeline ou runner'
ok 'workflow descoberto e projeção completa publicada (features, gates, timeline, runner)'

TIMELINE="$discovered" php -r '
    $snapshot = json_decode(getenv("TIMELINE"), true, 512, JSON_THROW_ON_ERROR);
    foreach ($snapshot["timeline"] as $event) {
        // A timeline é um recorte declarado: facts nunca sai do checkout.
        if (array_key_exists("facts", $event) || array_key_exists("lease_token_hash", $event)) { exit(1); }
    }
' || fail 'timeline vazou facts ou lease para o consumidor'
ok 'timeline expõe apenas campos declarados (sem facts nem lease)'

printf '\n== Saúde: estados de provider deixam de ser publicados como ok ==\n'
php -r '
    define("RALPH_MONITOR_LIBRARY", true);
    require $argv[1];
    $cases = [
        ["capacity_wait", [], "capacity_wait"],
        ["provider_failover_pending", [], "provider_failover"],
        ["running", [], "process_missing"],
        ["running", [["pid" => 1, "age" => 1, "command" => "ralph.sh"]], "ok"],
        ["awaiting_gates", [], "ok"],
    ];
    foreach ($cases as [$state, $processes, $expected]) {
        $health = monitorHealth($state, $processes, null, null, null, null, 180, 900);
        if ($health !== $expected) {
            fwrite(STDERR, "estado {$state} classificado como {$health}, esperado {$expected}\n");
            exit(1);
        }
    }
' "$ROOT/bin/ralph-monitor" || fail 'classificação de saúde não cobre capacity_wait e failover'
ok 'capacity_wait e provider_failover têm saúde própria'

printf '\n== Processos: observador read-only não conta como runner vivo ==\n'
php -r '
    define("RALPH_MONITOR_LIBRARY", true);
    require $argv[1];
    $observers = [
        "php /opt/bin/ralph-monitor --workflow wf_painel --interval 30",
        "php /opt/bin/ralph-control status --workflow wf_painel",
        "php /opt/bin/ralph-metrics --workflow wf_painel",
        "php /opt/bin/ralph-control failover-plan --workflow wf_painel",
    ];
    foreach ($observers as $command) {
        if (monitorIsRunnerProcess($command)) {
            fwrite(STDERR, "observador contado como runner: {$command}\n");
            exit(1);
        }
    }
    $runners = [
        "bash /opt/scripts/ralph.sh --workflow wf_painel",
        "php /opt/bin/ralph-control supervise --workflow wf_painel",
        "php /opt/bin/ralph-control run --workflow wf_painel --feature FEATURE-001",
    ];
    foreach ($runners as $command) {
        if (! monitorIsRunnerProcess($command)) {
            fwrite(STDERR, "runner não reconhecido: {$command}\n");
            exit(2);
        }
    }
' "$ROOT/bin/ralph-monitor" || fail 'classificação de processo confunde observador com runner'
ok 'observador e runner são distinguidos pela linha de comando'

# Prova de campo: com um monitor de verdade vivo (linha de comando contendo o
# workflow), a feature em execução sem runner ainda precisa acusar ausência.
claim="$(cd "$project" && php "$ROOT/bin/ralph-control" claim --workflow wf_painel --feature FEATURE-001 --actor monitor-ui-test)"
lease="$(CLAIM="$claim" php -r '$v = json_decode(getenv("CLAIM"), true, 512, JSON_THROW_ON_ERROR); echo $v["lease_token"] ?? "";')"
[ -n "$lease" ] || fail 'claim não retornou lease'

(exec php "$ROOT/bin/ralph-monitor" --root "$project" --controller "$ROOT/bin/ralph-control" \
  --workflow wf_painel --interval 3600 --feedback-file "$TMP/observer.json" > "$TMP/observer.log" 2>&1) &
OBSERVER_PID=$!
disown %% 2>/dev/null || true
sleep 1
observed="$(snapshot)"
OBSERVED="$observed" php -r '
    $snapshot = json_decode(getenv("OBSERVED"), true, 512, JSON_THROW_ON_ERROR);
    exit(($snapshot["health"] ?? null) === "process_missing" && ($snapshot["processes"] ?? null) === [] ? 0 : 1);
' || fail 'monitor vivo foi contado como runner e escondeu process_missing'
ok 'feature em execução sem runner acusa process_missing mesmo com monitor vivo'

(exec -a 'bash /opt/scripts/ralph.sh --workflow wf_painel' sleep 60) &
FAKE_RUNNER_PID=$!
disown %% 2>/dev/null || true
sleep 1
with_runner="$(snapshot)"
WITH_RUNNER="$with_runner" php -r '
    $snapshot = json_decode(getenv("WITH_RUNNER"), true, 512, JSON_THROW_ON_ERROR);
    exit(($snapshot["health"] ?? null) === "ok" && count($snapshot["processes"] ?? []) === 1 ? 0 : 1);
' || fail 'runner vivo não foi reconhecido'
ok 'runner vivo é reconhecido e a saúde volta a ok'
kill -KILL "$FAKE_RUNNER_PID" 2>/dev/null || true
FAKE_RUNNER_PID=""
kill -KILL "$OBSERVER_PID" 2>/dev/null || true
OBSERVER_PID=""

printf '\n== Painel: servidor local somente leitura ==\n'
port="$(php -r '
    $server = stream_socket_server("tcp://127.0.0.1:0", $code, $message);
    $name = stream_socket_get_name($server, false);
    fclose($server);
    echo substr($name, strrpos($name, ":") + 1);
')"
ledger="$project/.git/ralph-control/events.jsonl"
before_hash="$(php -r 'echo hash_file("sha256", $argv[1]);' "$ledger")"

# O segundo projeto não é checkout: um caminho inválido precisa virar cartão de
# erro, nunca derrubar o painel inteiro.
mkdir -p "$TMP/nao-e-projeto"
(exec php "$ROOT/bin/ralph-monitor" serve --project "$project" --project "$TMP/nao-e-projeto" \
  --host 127.0.0.1 --port "$port" \
  --controller "$ROOT/bin/ralph-control" > "$TMP/serve.log" 2>&1) &
SERVER_PID=$!
disown %% 2>/dev/null || true
for _ in $(seq 1 50); do
  if php -r 'exit(@fsockopen("127.0.0.1", (int) $argv[1], $c, $m, 0.2) ? 0 : 1);' "$port"; then
    break
  fi
  sleep 0.1
done

PORT="$port" php -r '
    $base = "http://127.0.0.1:".getenv("PORT");
    $document = file_get_contents($base."/");
    if ($document === false || ! str_contains($document, "RALPH")) { exit(1); }
    if (! str_contains($document, "/api/projects")) { exit(2); }

    $payload = json_decode((string) file_get_contents($base."/api/projects"), true, 512, JSON_THROW_ON_ERROR);
    if (($payload["schema_version"] ?? null) !== "1.0.0") { exit(3); }
    if (count($payload["projects"] ?? []) !== 2) { exit(4); }
    $snapshot = $payload["projects"][0];
    if (($snapshot["workflow_id"] ?? null) !== "wf_painel") { exit(5); }
    if (count($snapshot["features"] ?? []) !== 2) { exit(6); }
    $broken = $payload["projects"][1];
    if (($broken["health"] ?? null) !== "error" || ! is_string($broken["message"] ?? null)) { exit(7); }
' || fail 'painel não serviu documento e snapshot por projeto'
ok 'painel serve o documento e um snapshot por projeto, isolando o inválido'

PORT="$port" php -r '
    $context = stream_context_create(["http" => [
        "method" => "POST",
        "header" => "Content-Type: application/json\r\n",
        "content" => "{}",
        "ignore_errors" => true,
    ]]);
    file_get_contents("http://127.0.0.1:".getenv("PORT")."/api/projects", false, $context);
    $status = $http_response_header[0] ?? "";
    if (! str_contains($status, "405")) { exit(1); }

    $context = stream_context_create(["http" => ["ignore_errors" => true]]);
    file_get_contents("http://127.0.0.1:".getenv("PORT")."/api/aprovar-gate", false, $context);
    $status = $http_response_header[0] ?? "";
    if (! str_contains($status, "404")) { exit(2); }
' || fail 'painel aceitou método de escrita ou rota desconhecida'
ok 'painel recusa escrita (405) e rota inexistente (404)'

after_hash="$(php -r 'echo hash_file("sha256", $argv[1]);' "$ledger")"
[ "$before_hash" = "$after_hash" ] || fail 'painel alterou o ledger'
(cd "$project" && php "$ROOT/bin/ralph-control" verify >/dev/null) || fail 'ledger perdeu integridade após o painel'
ok 'ledger permanece íntegro e inalterado após o painel'

printf '\nOK: contrato de snapshot, classificação de saúde e painel somente leitura comprovados.\n'
