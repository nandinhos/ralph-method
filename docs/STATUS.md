# Status do Ralph Method

## Estado atual

O repositório é uma extração independente do núcleo Ralph validado no
`refactor-radar`. A versão `0.2.1` mantém a instalação local reversível,
doctor, ownership por hash e canal de feedback para o orquestrador externo, e
adiciona o guia operacional versionado para agentes de IA.

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
| Guia de agentes | `docs/AGENT_GUIDE.md` | operação, comunicação e ciclo de vida |

## Entrega concluída nesta fase

`ralph-init plan/apply/uninstall`, `ralph-doctor`, manifesto de instalação,
capabilities dos providers e feedback do loop foram implementados com testes
portáteis. O uninstall preserva runtime, workflow e evidências; arquivos
alterados pelo usuário ficam intactos. O apply usa staging e rollback para não
deixar instalação parcial em falha; os perfis gerados apontam para o loop local.
Quando o bloco é lançado pelo controlador, o feedback também é retransmitido
ao terminal em tempo real. O guia de agentes acompanha a versão do método e é
verificado por `scripts/check-doc-sync.sh`.

## Providers

O loop herdado do `bc-harness` possui execução Codex e Claude. OpenCode ainda é
uma capability detectável, mas não está habilitado como engine até existir um
adaptador validado. Hermes e agy permanecem candidatos a executores delegados.

## Validação

Os checks portáteis verdes são `scripts/check-shell.sh`,
`scripts/test-installation.sh`, `scripts/test-feedback.sh`,
`scripts/test-ralph-method.sh` e `scripts/test-ralph.sh`. Eles cobrem
ownership, conflito, idempotência, remoção segura, eventos, progresso e a
regressão do loop.
