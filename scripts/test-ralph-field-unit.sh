#!/usr/bin/env bash
#
# test-ralph-field-unit.sh — validação unitária e de sanidade do gerenciador de campos.
#
# Testa:
#   1. Opção --help
#   2. Listagem em diretório vazio
#   3. Criação de clone isolado em sandbox temporário
#   4. Listagem reconhecendo o campo ativo
#   5. Destruição segura do campo

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/ralph-field.sh"
TMP="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP"
}
trap cleanup EXIT

echo "== 1. Teste de ajuda (--help)"
out="$("$SCRIPT" --help)"
if ! echo "$out" | grep -q "gerenciador canônico de campos de prova"; then
  echo "FALHA: ajuda não exibiu a descrição esperada" >&2
  exit 1
fi
echo "  ok"

echo "== 2. Teste de listagem sem campos"
out="$("$SCRIPT" list)"
if ! echo "$out" | grep -q "Nenhum campo de prova ativo encontrado"; then
  echo "FALHA: listagem esperava vazio" >&2
  exit 1
fi
echo "  ok"

echo "== 3. Teste de criação e destruição em repositório mock"
mkdir -p "$TMP/repo"
git -C "$TMP/repo" init -q -b main
git -C "$TMP/repo" config user.email "test@example.invalid"
git -C "$TMP/repo" config user.name "Test"
echo "hello" > "$TMP/repo/README.md"
git -C "$TMP/repo" add README.md
git -C "$TMP/repo" commit -q -m "initial commit"

mkdir -p "$TMP/repo/scripts"
cp "$SCRIPT" "$TMP/repo/scripts/ralph-field.sh"
chmod +x "$TMP/repo/scripts/ralph-field.sh"

(
  cd "$TMP/repo"
  bash scripts/ralph-field.sh create campo-teste --clone >/dev/null
  if [ ! -d ".ralph/fields/campo-teste" ]; then
    echo "FALHA: campo não foi criado em .ralph/fields/campo-teste" >&2
    exit 1
  fi

  list_out="$(bash scripts/ralph-field.sh list)"
  if ! echo "$list_out" | grep -q "Campo:  campo-teste"; then
    echo "FALHA: listagem não encontrou campo-teste" >&2
    exit 1
  fi

  bash scripts/ralph-field.sh destroy campo-teste >/dev/null
  if [ -d ".ralph/fields/campo-teste" ]; then
    echo "FALHA: campo-teste ainda existe após destroy" >&2
    exit 1
  fi
)
echo "  ok"

echo "OK: test-ralph-field-unit passou integralmente."
