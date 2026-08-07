# Status do Ralph Method

## Estado atual

O repositório é uma extração independente do núcleo Ralph validado no
`refactor-radar`. A versão `0.3.0` mantém a instalação local reversível,
doctor, ownership por hash e canal de feedback para o orquestrador externo, e
adiciona o guia operacional versionado para agentes de IA e a prontidão
condicional de providers.

## Componentes extraídos

| Componente | Path | Responsabilidade |
|---|---|---|
| Control plane | `bin/ralph-control` | estado, lease, fencing, gates e ledger |
| Trace | `bin/ralph-trace` | fatos de delegação e relatório `TRC` |
| Monitor | `bin/ralph-monitor` | snapshot operacional sem transição |
| Bloco | `bin/ralph-block`, `bin/ralph-bloco` | uma feature por execução |
| Loop | `scripts/ralph.sh` | sessões por fase e gates externos |
| Hook | `scripts/ralph-hook.sh` | observabilidade best-effort |
| Instalação | `bin/ralph-init` | plan/apply/uninstall com manifesto |
| Doctor | `bin/ralph-doctor` | drift e integridade da instalação |
| Feedback | `schemas/feedback-event.schema.json` | contrato JSONL/stdout/callback |
| Prontidão de provider | `schemas/provider-readiness.schema.json` | autenticação, diagnóstico seguro e elegibilidade do adapter |
| Guia de agentes | `docs/AGENT_GUIDE.md` | operação, comunicação e ciclo de vida |

## Entrega concluída nesta fase

`ralph-init plan/apply/uninstall`, `ralph-doctor`, manifesto de instalação,
capabilities dos providers, prontidão condicional e feedback do loop foram
implementados com testes portáteis. O uninstall preserva runtime, workflow e evidências; arquivos
alterados pelo usuário ficam intactos. O apply usa staging e rollback para não
deixar instalação parcial em falha; os perfis gerados apontam para o loop local.
Quando o bloco é lançado pelo controlador, o feedback também é retransmitido
ao terminal em tempo real. O guia de agentes acompanha a versão do método e é
verificado por `scripts/check-doc-sync.sh`. A verificação de providers é
passiva por padrão; `--verify-providers` executa somente probes seguros não
generativos.

## Providers

O loop herdado do `bc-harness` possui execução Codex e Claude. Nesta versão,
provider só pode ser habilitado como adapter quando `auth_status` é
`authenticated`, `health_status` é `healthy` e `status` é `functional`.
OpenCode pode ser certificado pelo probe seguro; Hermes exige
`RALPH_HERMES_PROVIDER`; agy permanece `unsupported` até existir diagnóstico
seguro validado. Nenhum probe inicia geração.

## Validação

Os checks portáteis verdes são `scripts/check-shell.sh`,
`scripts/test-installation.sh`, `scripts/test-feedback.sh`,
`scripts/test-provider-readiness.sh`, `scripts/test-ralph-method.sh` e
`scripts/test-ralph.sh`. Eles cobrem ownership, conflito, idempotência,
remoção segura, eventos, prontidão de providers, progresso e a regressão do
loop.
