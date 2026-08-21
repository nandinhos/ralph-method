#!/usr/bin/env bash
#
# ralph-selfhost-technical-review-codex.sh — gate technical_review do
# self-hosting usando o Codex como engine de revisão (read-only).
#
# Motivo (ANOM-2026-010): o ralph.sh --verify-only exige engine com adapter
# (opencode/agy/cursor); o Codex é runner nativo e não tem esse modo. Este
# script reutiliza o MESMO mecanismo do gate 3 do bloco — `codex exec
# --sandbox read-only` com o prompt verify da fase — para que o gate
# technical_review rode com o Codex de ponta a ponta, sem trocar de provider.
#
# O operador define o provider do fluxo inteiro (RALPH_ENGINE=codex); este
# script não escolhe engine: apenas executa a revisão com o codex.
#
# Contrato do supervisor (env):
#   RALPH_WORKFLOW_ID  RALPH_FEATURE_KEY  RALPH_ATTEMPT  RALPH_GATE
#   RALPH_REPORT_PATH  RALPH_LEASE
#
# Uso (invocado pelo supervisor):
#   RALPH_TECHNICAL_REVIEW_COMMAND=bash scripts/ralph-selfhost-technical-review-codex.sh

# Expressões PHP literais dentro de aspas simples: sem expansão shell.
# shellcheck disable=SC2016

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW="${RALPH_WORKFLOW_ID:-}"
FEATURE="${RALPH_FEATURE_KEY:-}"
ATTEMPT="${RALPH_ATTEMPT:-}"
CODEX_HOME="${CODEX_HOME:-$REPO/../.onda2-home/.codex}"
CODEX_MODEL="${CODEX_MODEL:-gpt-5.6-luna}"
CODEX_REASONING_EFFORT="${CODEX_REASONING_EFFORT:-high}"
CODEX_PROFILE="${CODEX_PROFILE:-bc-harness}"

if [ -z "$WORKFLOW" ] || [ -z "$FEATURE" ]; then
  echo "contexto ausente: RALPH_WORKFLOW_ID e RALPH_FEATURE_KEY são obrigatórios" >&2
  exit 2
fi

export CODEX_HOME

# 1) Input da fase: manifest cortado por phase já gerado pelo controlador
#    (mesma lógica do ralph-selfhost-technical-review.sh). Contém somente a
#    fase da feature atual, nunca o PHASES.md inteiro (evita falso negativo
#    por phases futuras da fila).
INPUT=""
MANIFEST_DIR="$REPO/.git/ralph-control/manifests"
if [ -d "$MANIFEST_DIR" ]; then
  if [ -n "$ATTEMPT" ]; then
    CANDIDATE="$MANIFEST_DIR/$(printf '%s' "$FEATURE" | sed 's/[^A-Za-z0-9._-]/_/g')-attempt-${ATTEMPT}.md"
    [ -f "$CANDIDATE" ] && INPUT="$CANDIDATE"
  fi
  if [ -z "$INPUT" ]; then
    FEATURE_SAFE="$(printf '%s' "$FEATURE" | sed 's/[^A-Za-z0-9._-]/_/g')"
    INPUT="$(find "$MANIFEST_DIR" -maxdepth 1 -name "${FEATURE_SAFE}-attempt-*.md" -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- || true)"
  fi
fi

if [ -z "$INPUT" ] || [ ! -f "$INPUT" ]; then
  echo "input da feature não encontrado para revisão técnica" >&2
  exit 1
fi

# 2) Prompt verify: contrato idêntico ao gate 3 do bloco (read-only, TASK por
#    task da fase). No sandbox read-only do Codex 0.149 as ferramentas de
#    leitura são expostas via exec (rg/sed/find/pwd/git diff), não
#    Read/Glob/Grep — redação validada pelo próprio codex no ralph.sh
#    (ANOM-2026-006/010).
PROMPT_FILE="$REPO/.git/ralph-control/technical-review-${FEATURE}-${ATTEMPT}.txt"
{
  cat <<'REVIEW'
RALPH_VERIFY

Voce e um verificador independente. NAO escreva, edite ou crie nenhum arquivo.
Seu unico trabalho e ler o codigo real e dizer o que esta feito e o que nao esta.
Use somente a ferramenta exec, com os comandos rg, sed, find, pwd e git diff
--no-ext-diff (somente leitura); nunca use apply_patch, redirecionamentos,
comandos que escrevam, testes, PHP, providers ou qualquer acao que mude estado.
No Codex, exec e permitido exclusivamente para leitura dos arquivos e deve
receber apenas os comandos explicitamente listados acima.

Para CADA task marcada com `- [ ]` ou `- [x]` na fase abaixo, na ordem em que
aparecem, confira os acceptance criteria contra o codigo real (arquivos, classes,
testes, rotas, migrations — o que a task exigir) e emita EXATAMENTE UMA linha:

TASK <n>: DONE
TASK <n>: INCOMPLETE — <o que falta>

Regras:
- <n> e o indice da task na fase, comecando em 1.
- Uma linha TASK para cada task, sem excecao, sem agrupar.
- Nao emita nenhum outro texto alem das linhas TASK.
- Codigo ausente, TODO, placeholder ou teste faltando => INCOMPLETE.
- Na duvida, INCOMPLETE.

## Fase a verificar
REVIEW
  cat "$INPUT"
} > "$PROMPT_FILE"

# 3) Executa a revisão com o Codex em sandbox read-only (o mesmo caminho do
#    gate 3 do bloco). Sem provider alternativo: codex é o provider do fluxo.
OUTPUT_FILE="$REPO/.git/ralph-control/technical-review-${FEATURE}-${ATTEMPT}.out"
set +e
(cd "$REPO" && codex --profile "$CODEX_PROFILE" exec --ephemeral \
  --model "$CODEX_MODEL" \
  -c "model_reasoning_effort=\"$CODEX_REASONING_EFFORT\"" \
  --dangerously-bypass-hook-trust \
  --sandbox read-only - < "$PROMPT_FILE") > "$OUTPUT_FILE" 2>&1
RC=$?
set -e

[ "$RC" -ne 0 ] && { cat "$OUTPUT_FILE"; exit "$RC"; }

# 4) Validação: cada task da fase precisa de exatamente uma linha
#    TASK <n>: DONE (sem conflito, sem ausência). A saída do codex é a
#    evidência do gate (o supervisor registra pelo stdout + exit code).
EXPECTED=$(grep -cE '^[[:space:]]*- \[[ xX]\]' "$INPUT" || true)
if [ "$EXPECTED" -eq 0 ]; then
  cat "$OUTPUT_FILE"
  echo "fase sem task checkbox; revisão técnica sem contrato task a task" >&2
  exit 1
fi

TASK_LINES=$(sed -E \
  -e 's/\r$//' \
  -e 's/^[[:space:]]*(#{1,6}[[:space:]]+|[-*+][[:space:]]+)?//' \
  -e 's/\*\*//g' \
  -e 's/`//g' \
  "$OUTPUT_FILE" \
  | sed -nE 's/^[[:space:]]*(TASK [0-9]+: (DONE|INCOMPLETE)([[:space:]]*[—-].*)?)[[:space:]]*$/\1/p' \
  || true)

PARSED=$(printf '%s\n' "$TASK_LINES" | grep -c . || true)
if [ "$PARSED" -eq 0 ]; then
  cat "$OUTPUT_FILE"
  echo "o verificador não emitiu linhas TASK; revisão não confirmada" >&2
  exit 1
fi

ERRORS=""
for TASK_NUM in $(seq 1 "$EXPECTED"); do
  LINES=$(printf '%s\n' "$TASK_LINES" | grep -E "^TASK ${TASK_NUM}: " || true)
  if [ -z "$LINES" ]; then
    ERRORS+="TASK $TASK_NUM ausente"$'\n'
    continue
  fi
  STATUSES=$(printf '%s\n' "$LINES" | sed -nE 's/^TASK [0-9]+: (DONE|INCOMPLETE).*/\1/p' | sort -u)
  STATUS_COUNT=$(printf '%s\n' "$STATUSES" | grep -c . || true)
  if [ "$STATUS_COUNT" -ne 1 ]; then
    ERRORS+="TASK $TASK_NUM recebeu vereditos conflitantes"$'\n'
    continue
  fi
  if printf '%s\n' "$STATUSES" | grep -q '^INCOMPLETE$'; then
    ERRORS+="TASK $TASK_NUM INCOMPLETE"$'\n'
  fi
done

cat "$OUTPUT_FILE"
if [ -n "$ERRORS" ]; then
  echo "revisão técnica reprovada:" >&2
  printf '%s' "$ERRORS" >&2
  exit 1
fi

exit 0
