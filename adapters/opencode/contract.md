# Adapter OpenCode

Este adapter é um executor sem autoridade. Ele recebe um prompt, chama a CLI
OpenCode em uma sessão nova e publica um resultado normalizado. Não conhece
workflow, lease, gate, fila ou ledger.

## Execução

```text
runner.sh preflight --model provider/model
runner.sh run --repo-root DIR --prompt-file FILE --events-file FILE \
  --result-file FILE --mode impl|verify --execution-id exec_...
```

O prompt é anexado por `--file`. A versão da CLI é consultada, o modelo é
obrigatório e `--format json` é obrigatório. `--continue`, `--session`,
`--fork`, `--attach` e `--port` não fazem parte do contrato inicial.

## Saída

O arquivo de eventos é local e descartável. O arquivo de resultado segue
`schemas/runner-result.schema.json` e contém apenas fatos sanitizados:

- `session_id`, quando a CLI o expõe;
- `runner_version`, provider e modelo solicitado;
- modelo efetivo somente quando houver campo estruturado observável;
- status, exit code, evento terminal e limites de captura;
- `fallback_used=null` e `fallback_status=unknown` quando não houver prova.

O controlador importa esse resultado sob lock e lease. O adapter não escreve
`.git/ralph-control` e nunca autoriza a próxima fase.
