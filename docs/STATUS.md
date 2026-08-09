# Status do Ralph Method

## Estado atual

A versão `0.4.0` foi promovida para `main` e está sincronizada com
`origin/main` no commit `6dd9b29`. A certificação completa está em
[`docs/reports/0007-certificacao-e-promocao-v0-4-0.md`](reports/0007-certificacao-e-promocao-v0-4-0.md).

A branch `feat/ralph-hardening` iniciou a evolução de segurança da v0.5.0. A
primeira entrega adiciona exclusividade por feature durante o bloco controlado,
protege o ledger com `workflow.lock` e comprova a rejeição de duas execuções
simultâneas no teste de método. A promoção desta evolução ainda não ocorreu.
O incidente e a correção estão documentados em
[`docs/incidents/0008-concorrencia-no-bloco-controlado.md`](incidents/0008-concorrencia-no-bloco-controlado.md).
Na revisão adversarial, o checkpoint encontrou e corrigiu o bypass por
`workflow_id` alternativo, o `finish` concorrente e o replay de uma tentativa
sem evento terminal após crash. O contrato executável dessa evolução está em
[`docs/architecture/control-plane-hardening-plan.md`](architecture/control-plane-hardening-plan.md).

O repositório é uma extração independente do núcleo Ralph validado no
`refactor-radar`: essa é a origem histórica, não uma dependência de runtime.
Não há importação de código, banco, credencial ou módulo do produto-alvo. A
versão `0.4.0` mantém a instalação local reversível, doctor, ownership por hash
e canal de feedback para o orquestrador externo, e adiciona o guia operacional
versionado para agentes de IA.

O escopo operacional está fechado em três harnesses: Codex e Claude CLI pelos
runners nativos do loop, e OpenCode pelo adapter executável certificado em
campo. Hermes e agy permanecem somente na detecção passiva compatível e estão
registrados em [`docs/backlog.md`](backlog.md) com prioridade nenhuma.

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
| Runners Codex/Claude | `scripts/ralph.sh` | integração nativa de execução e revisão do loop |
| Resultado de runner | `schemas/runner-result.schema.json` | contrato sanitizado de sessão, modelo, terminal e fallback |
| Política read-only OpenCode | `adapters/opencode/policy.php`, `scripts/opencode-readonly-proof.sh` | fingerprint, prova externa e bloqueio fail-closed da revisão |
| Guia de agentes | `docs/AGENT_GUIDE.md` | operação, comunicação e ciclo de vida |

A matriz completa de componentes, responsabilidades e limites está em
[`docs/architecture/README.md`](architecture/README.md). Ela é a referência
para abstrair o Ralph Method para outro projeto ou harness sem misturar
autoridade do controlador, execução do runner, observabilidade e documentação.

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

## Providers e harnesses

O loop herdado do `bc-harness` possui execução Codex e Claude. Nesta versão,
provider pode ser certificado como `functional` quando `auth_status` é
`authenticated` e `health_status` é `healthy`. `adapter_enabled` exige também
`runner_supported=true`. OpenCode é certificado com `auth list` + `models`,
JSONL, política read-only e teste de campo. Hermes e agy podem ser detectados
de modo seguro, mas não possuem adapter de execução nesta linha e não entram
na seleção como fallback. Nenhum probe inicia geração. Quando nenhum runner
está disponível, `auto` mantém o plano em `needs_review` sem materializar
`codex` ou outro executor fictício.

## Validação

Os checks portáteis verdes são `scripts/check-shell.sh`,
`scripts/test-installation.sh`, `scripts/test-feedback.sh`,
`scripts/test-provider-readiness.sh`, `scripts/test-multiprovider.sh`,
`scripts/test-ralph-method.sh`, `scripts/test-ralph-knowledge.sh` e
`scripts/test-ralph.sh`, além de `scripts/test-opencode-policy.sh`,
`scripts/test-opencode-adapter.sh`, `scripts/test-opencode-adversarial.sh` e da prova real
`scripts/test-opencode-field.sh`. Eles cobrem ownership, conflito, idempotência,
remoção segura, eventos, prontidão de providers, progresso e a regressão do
loop, capability adversarial, parsing JSONL, política read-only e execução
complexa por OpenCode com implementação e revisão preservadas no trace.

A regressão multiprovider offline está verde no relatório
[`docs/reports/0009-regressao-multiprovider.md`](reports/0009-regressao-multiprovider.md).
Ela prova que a seleção `auto` escolhe somente providers funcionais com
`runner_supported=true`, mantém a ordem Codex → Claude CLI → OpenCode, não
faz fallback silencioso, bloqueia `apply` explícito não autenticado e mantém
`fallback_policy=none`. A mesma prova registra no `ralph-trace` identidade
exata, modelo e sessão dos três harnesses. Hermes e agy não participam da
seleção executável e continuam no backlog sem prioridade.

Os smoke tests reais dos CLIs também foram comprovados fora do loop: Codex
retornou exit `0`, JSONL válido, thread e marcador determinístico; Claude
retornou exit `0`, JSON válido, sessão e marcador após a correção do limite de
orçamento artificial da primeira tentativa. O teste de campo complexo OpenCode
foi repetido no commit candidato com `opencode/deepseek-v4-flash-free` e
terminou verde em 136s, com `FEATURE_CHECK_OK`, trace, processo contido e
revisão read-only.

O hardening adicionou uma prova específica de handoff e memória em
[`scripts/test-ralph-knowledge.sh`](../scripts/test-ralph-knowledge.sh): a
feature avança antes da curadoria, a lição é publicada com ID `LES-YYYY-NNNN`,
a segunda curadoria é idempotente e a recuperação consulta somente lições
validadas do projeto-alvo. Conhecimento permanece `non_blocking`.

A reprodução independente foi comprovada a partir de um `git archive` limpo:
o bundle foi instalado duas vezes em um projeto Git fixture fora do
`refactor-radar`, validado pelo doctor, desinstalado por ownership e deixou o
projeto original limpo. O comando reproduzível é
`bash scripts/test-reproducibility.sh`.
O relatório da auditoria está em
[`docs/reports/0008-auditoria-de-acoplamento-e-reproducibilidade.md`](reports/0008-auditoria-de-acoplamento-e-reproducibilidade.md).

O adversarial do adapter OpenCode foi maturado com um probe direto da CLI real:
`ralph-review` retornou `ADVERSARIAL_VERDICT: PASS` em 38s, com uma sessão,
quatro `step_finish`, dez operações somente de leitura, política revalidada e
hash da superfície idêntico antes/depois. O teste também reproduz e protege a
rejeição de múltiplas sessões e de agente divergente.

O teste de campo real do OpenCode foi concluído com a feature
`FEATURE-FIELD-OPENCODE-001` em checkout descartável: implementação, revisão
read-only, `bin/check`, evidência de runtime e curadoria passaram; o handoff
foi versionado e o controlador avançou para uma fila vazia. O relatório
sanitizado está em
[`docs/reports/0004-teste-campo-opencode-cinco-gates.md`](reports/0004-teste-campo-opencode-cinco-gates.md).
O reteste adversarial oficial está em
[`docs/reports/0006-reteste-adversarial-oficial-opencode.md`](reports/0006-reteste-adversarial-oficial-opencode.md).
O relatório final de certificação e promoção está em
[`docs/reports/0007-certificacao-e-promocao-v0-4-0.md`](reports/0007-certificacao-e-promocao-v0-4-0.md).
As falhas anteriores foram preservadas nos incidentes 0003 a 0007. A revisão
ampla exploratória que expirou não foi considerada aprovação; a decisão usou a
prova externa, a revisão bounded estruturada, a regressão e os testes reais.
