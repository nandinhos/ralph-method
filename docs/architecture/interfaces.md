# Interfaces do Ralph Method

## CLI mínima

```text
ralph-init plan --project <path>
ralph-init apply --project <path> --provider auto|codex|claude|opencode|hermes|agy [--verify-providers]
ralph-init plan --project <path> [--provider ...] [--verify-providers]
ralph-init uninstall --project <path> [--apply]
ralph-doctor --project <path> [--verify-providers]
bin/ralph-control <command> ...
bin/ralph-trace record|report|tree ...
bin/ralph-monitor --workflow <id> [--interval 30]
```

O procedimento operacional completo para agentes está em
[`../AGENT_GUIDE.md`](../AGENT_GUIDE.md). Ele é parte do contrato versionado e
deve ser atualizado junto com `VERSION`.

`plan` é somente leitura. `apply` instala apenas os arquivos listados no
manifesto, com cópia atômica. `uninstall` sem `--apply` apenas calcula o plano;
com `--apply`, remove somente arquivos ainda iguais ao hash instalado e
preserva arquivos modificados pelo usuário. Os perfis locais de Codex, Claude e OpenCode
também são gerados com `RALPH_BIN=scripts/ralph.sh` e entram no ownership. O
relatório fica em
`.ralph/uninstall-report.json`. O histórico operacional (`.git/ralph-control`),
workflow, handoffs e relatórios não pertencem ao uninstall e são preservados.

## Canal de feedback do loop

`scripts/ralph.sh` emite um evento sanitizado para cada início, tentativa,
falha, espera, conclusão e encerramento. O evento segue
`schemas/feedback-event.schema.json` e contém `run_id`, fase, tentativa,
`workflow_id`, `feature_key`, percentual estimado, estado e saúde. O canal é
unidirecional: quem recebe o evento não pode aprovar gates, adquirir leases ou
escolher a próxima feature.

Por padrão, o loop grava JSONL local em:

```text
.git/ralph-control/feedback/events.jsonl
```

Para exibir o fluxo na tela do orquestrador, use:

```bash
RALPH_FEEDBACK_STDOUT=1 scripts/ralph.sh
```

O consumidor deve ler linhas com o prefixo `RALPH_FEEDBACK `. Para integração
direta, `RALPH_FEEDBACK_CMD=/caminho/do/consumidor` executa um binário com
`<evento> <detalhe>` nos argumentos e o JSON completo no stdin. O callback tem
timeout e qualquer falha é apenas reportada; a execução não é aprovada nem
interrompida por ele.

Quando o bloco é iniciado pelo `ralph-control run` ou pelo supervisor, o
controlador ativa esse canal por padrão e retransmite as linhas
`RALPH_FEEDBACK` enquanto o processo está vivo. Assim o terminal do
orquestrador recebe progresso sem esperar o encerramento do bloco. O relay
continua sendo somente saída; gates, leases e transições permanecem no
controlador.

Os detalhes textuais são reduzidos e têm padrões óbvios de token, senha e API
key redigidos antes da publicação. O evento não carrega prompt, resposta,
credencial ou saída integral do comando.

`bin/ralph-monitor` continua sendo somente leitura. Além do snapshot do
workflow, ele mostra o último evento do JSONL do loop e permite detectar
processo ausente, heartbeat parado, gates sem atividade e workflow bloqueado.

## Prontidão de provider

`ralph-init` detecta providers sem tocar autenticação por padrão. A flag
`--verify-providers` solicita probes `safe` explícitos, com timeout e sem
geração. O resultado é persistido em `.ralph/providers.json` conforme
`schemas/provider-readiness.schema.json`.

O contrato mínimo de cada provider contém:

```text
installed, path, version,
auth_status, health_status, status,
capabilities, runner_supported, adapter_enabled, reason
```

Uma CLI é certificada quando `status=functional`. Um adapter somente é
elegível se `status=functional`, `runner_supported=true` e
`adapter_enabled=true`. `detected`, `authenticated`, `degraded`,
`unsupported` e `authentication_unknown` nunca habilitam execução alternativa.
O modo `auto` considera todos os providers certificados, mas escolhe somente
os runners disponíveis em ordem determinística. Ele não faz fallback silencioso;
quando não encontra runner apto, materializa `orchestration.mode=needs_review`.
Nesse caso, `selection.selected_provider` e `orchestration.primary_runner` são
`null`.

## Contrato de provider

Um adapter não grava arquivos de estado. Ele entrega ao controlador os campos:

```text
runner, runner_version, role, execution_id,
requested_model, effective_model, provider,
session_id ou conversation_id,
identity_status, identity_source,
status, reason, fallback_used e fallback_status
```

Quando o provider não expõe modelo efetivo, a identidade deve ser marcada como
`declared`, `observed`, `partial` ou `unavailable`.

O adapter OpenCode também exige `runner-result.schema.json`, sessão e evento
terminal `step_finish`; falta de evidência de fallback permanece como
`fallback_used=null` e `fallback_status=unknown`.

## Política de fallback

O padrão é `none`. Fallback precisa estar declarado no manifesto e sempre ser
registrado pelo `ralph-trace`; nenhuma falha pode trocar executor
silenciosamente.
