# Adapter OpenCode

Este adapter é um executor sem autoridade. Ele recebe um prompt, chama a CLI
OpenCode em uma sessão nova e publica um resultado normalizado. Não conhece
workflow, lease, gate, fila ou ledger.

## Execução

```text
runner.sh preflight --model provider/model
runner.sh run --repo-root DIR --prompt-file FILE --events-file FILE \
  --result-file FILE --mode impl|verify --execution-id exec_... \
  [--policy-proof EXTERNAL_FILE]
```

No modo `verify`, a prova read-only externa é obrigatória. Ela pode ser
fornecida por `--policy-proof EXTERNAL_FILE` ou por
`RALPH_OPENCODE_VERIFY_POLICY_PROOF`; as duas formas são equivalentes e a
ausência de ambas reprova antes da chamada à CLI. O agente read-only também
precisa estar explícito em `--agent` ou
`RALPH_OPENCODE_VERIFY_AGENT`.

O prompt é anexado por `--file`. A versão da CLI é consultada, o modelo é
obrigatório e `--format json` é obrigatório. `--continue`, `--session`,
`--fork`, `--attach` e `--port` não fazem parte do contrato inicial.

## Saída

O arquivo de eventos é local e descartável. Uma sessão pode emitir múltiplos
eventos `step_finish`; o parser exige pelo menos um e rejeita JSONL que misture
sessões. O arquivo de resultado segue
`schemas/runner-result.schema.json` e contém apenas fatos sanitizados:

- `session_id`, quando a CLI o expõe;
- `runner_version`, provider e modelo solicitado;
- modelo efetivo somente quando houver campo estruturado observável;
- status, exit code, evento terminal e limites de captura;
- `fallback_used=null` e `fallback_status=unknown` quando não houver prova.
- `permission_policy_hash` e `permission_policy_status` no modo `verify`;
- `verification_agent` quando a sessão independente for usada.

O controlador importa esse resultado sob lock e lease. O adapter não escreve
`.git/ralph-control` e nunca autoriza a próxima fase.

## Revisão read-only

O gate de revisão não confia em uma instrução textual. O preflight exige um
agente OpenCode com política explícita, uma prova externa e um fingerprint
estável:

```bash
scripts/opencode-readonly-proof.sh \
  --repo-root /caminho/do/projeto \
  --agent ralph-review \
  --model provider/model \
  --proof-file /tmp/ralph-readonly-policy-proof.json
```

O arquivo de prova deve ficar fora da raiz mutável. O controlador valida a
política novamente antes e depois da sessão. Uma mudança no agente ou na
configuração invalida o fingerprint; superfície de política divergente,
canário criado, marcador ou evento terminal ausente, ou saída incompleta
bloqueiam a revisão. A prova separa
`policy_denied_tools` (o que a política efetivamente nega) de
`denied_tools_seen` (recusas que a CLI chegou a emitir como evento); com `*:
deny`, a CLI pode simplesmente não expor a ferramenta, e isso continua válido
quando o fingerprint, o canário, o marcador JSONL e a superfície de política
preservada comprovam o isolamento.

O OpenCode pode criar arquivos bootstrap sob `.opencode/` na primeira chamada.
Eles são ignorados somente no hash da fixture descartável de prova; nenhum
arquivo do projeto é ignorado no resultado da feature.
