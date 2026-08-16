# Adapter Cursor — contrato da seam

Runner: `cursor` (CLI headless `agent`/`cursor-agent`).
Resultado: `runner-result` `schema_version=1.2.0`, terminal de sucesso `result`.

## Comandos

```
adapters/cursor/runner.sh version
adapters/cursor/runner.sh preflight [--mode impl|verify] [--repo-root DIR]
adapters/cursor/runner.sh run --repo-root DIR --prompt-file FILE --events-file FILE \
  --result-file FILE --mode impl|verify --execution-id exec_... \
  --workflow-id wf_... --feature-key ... --attempt N
```

## Variáveis de ambiente

- `RALPH_CURSOR_MODEL` — modelo explícito (obrigatório; sem default).
- `RALPH_CURSOR_TIMEOUT` — timeout do comando (default 1800s).
- `RALPH_CURSOR_MAX_PROMPT_BYTES` — limite do prompt (default 262144).
- `RALPH_CURSOR_MAX_EVENT_BYTES` — limite do stream (default 5242880).
- `RALPH_CURSOR_MAX_EVENTS` — limite de eventos (default 10000).
- `RALPH_CURSOR_VERIFY_MODE` — `ask` (v1; não configura policy proof).
- `RALPH_CURSOR_CLI` — binário (`agent` ou `cursor-agent`); default: auto-detect.

Nenhuma `CURSOR_API_KEY`: a autenticação é a sessão local da conta Cursor.

## Cursor é uma IDE com LLM embutido (sem API key)

Autenticação = sessão local da conta Cursor (login do operador). O probe de
readiness não procura chave; `agent status --format json` + `agent models` são
a autoridade. O modelo é o LLM selecionado na sessão/workspace; o perfil pode
fixar `RALPH_CURSOR_MODEL`.

## Impl

```
agent -p --force --trust --output-format stream-json \
  --workspace "$REPO_ROOT" --model "$RALPH_CURSOR_MODEL" < "$PROMPT_FILE"
```

## Verify v1 (declared — nunca verified)

```
agent -p --mode ask --trust --output-format stream-json \
  --workspace "$REPO_ROOT" --model "$RALPH_CURSOR_MODEL" < "$PROMPT_FILE"
```

- `permission_policy_status` = `declared`
- `permission_policy_hash` = `null`
- `verification_agent` = `ask`
- `--mode ask` é convenção de modo, não fingerprint de política; o parser
  reprova ferramenta de escrita observada mesmo em `ask`.

## Proibido no contrato inicial

- `--continue`, `--resume`, `--fork`;
- stdin de prompt (usa arquivo);
- sessão reutilizada;
- ferramenta de escrita observada em verify (reprova o resultado);
- runner PowerShell (Windows exige WSL/Git Bash).

## Parser fail-closed

- JSONL inválido → `failed`;
- zero eventos → `failed`;
- múltiplos `result` terminais → `failed`;
- modelo efetivo divergente do solicitado, quando observável → `failed`;
- escrita observada em verify → `failed`;
- canário: se o verify criar/alterar arquivo → reprovar.
