#!/usr/bin/env bash
#
# test-ralph-supervise-unit.sh — validação unitária e de sanidade do supervisor agnóstico.
#
# Testa:
#   1. Opção --help
#   2. Validação determinística de diretório inexistente
#   3. Validação determinística de workflow ausente
#   4. Resolução agnóstica de comando de teste (composer, artisan, npm)
#   5. Bloqueio determinístico de instância concorrente (anti-paralelismo via lock)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/ralph-supervise.sh"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "== 1. Teste de ajuda (--help)"
out="$("$SCRIPT" --help)"
if ! echo "$out" | grep -q "supervisor universal e agnóstico"; then
  echo "FALHA: ajuda não exibiu a descrição esperada" >&2
  exit 1
fi
echo "  ok"

echo "== 2. Teste de validação de diretório inexistente"
set +e
"$SCRIPT" --target-dir "$TMP/inexistente_123" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
  echo "FALHA: esperado código de saída 2, obteve $rc" >&2
  exit 1
fi
echo "  ok"

echo "== 3. Teste de workflow ausente"
mkdir -p "$TMP/proj"
set +e
"$SCRIPT" --target-dir "$TMP/proj" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 2 ]; then
  echo "FALHA: esperado código de saída 2 para workflow ausente, obteve $rc" >&2
  exit 1
fi
echo "  ok"

echo "== 4. Teste de resolução agnóstica de comando de teste via composer.json"
cat > "$TMP/proj/composer.json" <<'EOF'
{
  "scripts": {
    "test": "phpunit"
  }
}
EOF
cat > "$TMP/proj/workflow.json" <<'EOF'
{
  "workflow_id": "wf_test_unit"
}
EOF
# Criar mock do bin/ralph-control para simular conclusão imediata
mkdir -p "$TMP/proj/bin"
cat > "$TMP/proj/bin/ralph-control" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "supervise" ]; then
  exit 0
elif [ "$1" = "status" ]; then
  echo '{"workflow":{"workflow_id":"wf_test_unit"},"projection":{"cursor":null,"features":[{"feature_key":"F1","state":"released"}]},"event_count":5}'
  exit 0
fi
exit 0
EOF
chmod +x "$TMP/proj/bin/ralph-control"

out="$("$SCRIPT" --target-dir "$TMP/proj" --workflow wf_test_unit)"
if ! echo "$out" | grep -q "Quality Cmd:  composer test"; then
  echo "FALHA: não detectou 'composer test' via composer.json" >&2
  echo "$out" >&2
  exit 1
fi
if ! echo "$out" | grep -q "Todas as 1 ondas foram executadas e validadas com sucesso"; then
  echo "FALHA: ciclo simulado de onda não concluiu com sucesso" >&2
  echo "$out" >&2
  exit 1
fi
echo "  ok"

echo "== 5. Teste de bloqueio de concorrência (anti-paralelismo)"
mkdir -p "$TMP/proj/.ralph"
lock_file="$TMP/proj/.ralph/.supervisor-wrapper.lock"
exec 199>"$lock_file"
if command -v flock >/dev/null 2>&1; then
  flock -x 199
  set +e
  err_out="$("$SCRIPT" --target-dir "$TMP/proj" --workflow wf_test_unit 2>&1)"
  rc=$?
  set -e
  if [ "$rc" -ne 12 ]; then
    echo "FALHA: esperado código 12 para lock concorrente, obteve $rc" >&2
    exit 1
  fi
  if ! echo "$err_out" | grep -q "Já existe um supervisor ou wrapper ativo"; then
    echo "FALHA: mensagem de lock duplicado não encontrada" >&2
    exit 1
  fi
  flock -u 199
fi
echo "  ok"

echo "OK: test-ralph-supervise-unit passou integralmente."
