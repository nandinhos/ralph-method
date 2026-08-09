# Status do Ralph Method

## Estado atual

O repositório é uma extração independente do núcleo Ralph validado no
`refactor-radar`. A versão `0.4.0` mantém a instalação local reversível,
doctor, ownership por hash e canal de feedback para o orquestrador externo, e
adiciona o guia operacional versionado para agentes de IA e a prontidão
condicional de providers e certifica sessões reais de OpenCode e Hermes sem
confundir prontidão da CLI com disponibilidade do runner do Ralph.

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
| Adapter OpenCode | `adapters/opencode/` | preflight, execução JSONL, parser fail-closed e resultado normalizado |
| Resultado de runner | `schemas/runner-result.schema.json` | contrato sanitizado de sessão, modelo, terminal e fallback |
| Política read-only OpenCode | `adapters/opencode/policy.php`, `scripts/opencode-readonly-proof.sh` | fingerprint, prova externa e bloqueio fail-closed da revisão |
| Guia de agentes | `docs/AGENT_GUIDE.md` | operação, comunicação e ciclo de vida |

## Entrega concluída nesta fase

`ralph-init plan/apply/uninstall`, `ralph-doctor`, manifesto de instalação,
capabilities dos providers, prontidão condicional, seleção determinística e
feedback do loop foram
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
provider pode ser certificado como `functional` quando `auth_status` é
`authenticated` e `health_status` é `healthy`. `adapter_enabled` exige também
`runner_supported=true`. OpenCode é certificado com `auth list` + `models`;
Hermes identifica e verifica o provider selecionado; agy permanece
`unsupported` até existir diagnóstico seguro validado. Nenhum probe inicia
geração. Quando nenhum runner está disponível, `auto` mantém o plano em
`needs_review` sem materializar `codex` ou outro executor fictício.

## Validação

Os checks portáteis verdes são `scripts/check-shell.sh`,
`scripts/test-installation.sh`, `scripts/test-feedback.sh`,
`scripts/test-provider-readiness.sh`, `scripts/test-ralph-method.sh` e
`scripts/test-ralph.sh`, além de `scripts/test-opencode-policy.sh`,
`scripts/test-opencode-adapter.sh` e da prova real
`scripts/test-opencode-field.sh`. Eles cobrem ownership, conflito, idempotência,
remoção segura, eventos, prontidão de providers, progresso e a regressão do
loop, capability adversarial, parsing JSONL, política read-only e execução
complexa por OpenCode com implementação e revisão preservadas no trace.

O teste de campo real do OpenCode foi concluído com a feature
`FEATURE-FIELD-OPENCODE-001` em checkout descartável: implementação, revisão
read-only, `bin/check`, evidência de runtime e curadoria passaram; o handoff
foi versionado e o controlador avançou para uma fila vazia. O relatório
sanitizado está em
[`docs/reports/0004-teste-campo-opencode-cinco-gates.md`](reports/0004-teste-campo-opencode-cinco-gates.md).
As duas falhas anteriores foram preservadas nos incidentes 0003 e 0004. A
branch `feat/opencode-engine` ainda requer revisão adversarial final e regressão
antes de qualquer promoção para `main`.
