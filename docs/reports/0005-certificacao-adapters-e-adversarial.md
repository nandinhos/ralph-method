# Relatório 0005 — comprovação dos engines e maturação adversarial

## Objetivo

Comprovar os CLIs reais disponíveis, repetir o caminho de campo do OpenCode e
submeter o contrato do adapter a revisões independentes bounded. Este relatório
separa o que foi executado do que continua pendente.

## Engines e CLIs reais

| Engine/provider | Execução | Evidência observada | Resultado |
|---|---|---|---|
| Codex | smoke não generativo, sem ferramentas, timeout de 90s | exit `0`, JSONL válido, `thread.started` e marcador determinístico | comprovado |
| Claude | primeira tentativa com orçamento artificial de US$ 0,05 | `error_max_budget_usd`; não foi classificada como falha do provider | diagnóstico concluído |
| Claude | retry sem alteração de projeto, orçamento artificial de US$ 0,50 | exit `0`, JSON válido, sessão, `subtype=success` e marcador determinístico | comprovado |
| OpenCode | `scripts/test-opencode-field.sh` com `opencode/big-pickle` | exit `0`, `FIELD_TEST_OK`, `FEATURE_CHECK_OK`, trace de implementação/revisão e prova read-only | comprovado em campo complexo; 137s |

Versões observadas no ambiente: Codex CLI `0.146.0`, Claude Code `2.1.225` e
OpenCode `1.18.15`. Os smoke tests Codex/Claude comprovam o CLI autenticado e
seu retorno; não comprovam um adapter independente que ainda não existe para
esses dois engines. O Ralph continua usando Codex e Claude como engines nativos
em `scripts/ralph.sh`.

## Contrato canônico OpenCode

O contrato agora fica explícito:

1. `impl` não recebe a prova read-only no ambiente do implementador;
2. `verify` exige agente read-only e prova externa antes da CLI;
3. a prova chega por `--policy-proof` ou por
   `RALPH_OPENCODE_VERIFY_POLICY_PROOF`;
4. a política valida hash, sessão, evento terminal, marcador, canário, árvore
   estável e superfície de ferramentas;
5. o parser normaliza JSONL e falha fechado em JSON inválido, evento terminal
   ausente, limite excedido ou exit code não zero;
6. `ralph-control` exige exatamente uma delegação `impl` e uma `verify`, sob
   contexto de workflow, feature e tentativa, antes dos gates.

As provas locais `test-opencode-adapter.sh` e `test-opencode-policy.sh` ficaram
verdes. A revalidação direta de `policy.php check` contra a prova do campo
também terminou com exit `0`.

## Revisão adversarial e systematic debugging

| Tentativa | Escopo | Resultado | Interpretação |
|---|---|---|---|
| 1 | revisão ampla do campo, ledger, trace, status e diff | timeout sem parecer | não aprova nem reprova o adapter |
| 2 | `bc-reviewer`, contrato em cinco alegações | timeout sem parecer | escopo/retorno não bounded o suficiente |
| 3 | `bc-reviewer`, evidência de campo em cinco alegações | timeout sem parecer | mesma falha de canal; agente encerrado como `inconclusive` |
| 4 | explorer, uma alegação estreita sobre `--policy-proof` | `FAIL` | falso finding: ignorou a fonte equivalente por variável de ambiente |
| 5 | explorer, linhas 91 e 111–132, alegação canônica | `PASS` | prova que ambas as fontes são aceitas e ausência bloqueia antes da CLI |

O systematic debugging isolou duas causas: a redação inicial do teste
adversarial era estreita demais e as revisões amplas não tinham deadline/output
estruturado suficientemente bounded. Não há evidência de que o runner tenha
aceitado uma prova inválida; os testes negativos e a prova de campo permanecem
verdes.

## Status e decisão

| Item | Status |
|---|---|
| smoke real Codex | verde |
| smoke real Claude | verde após corrigir o limite artificial do teste |
| adapter OpenCode em fixture e campo | verde |
| cinco gates do campo real | verdes no relatório 0004 |
| revisão read-only OpenCode | verde em campo e nas fixtures |
| adversarial bounded repetível do adapter | pendente |
| promoção para `main` | não autorizada |

A promoção continua bloqueada por decisão de processo, não por falha dos cinco
gates: falta concluir a maturação adversarial com protocolo bounded, timeout
observável e parecer estruturado. A pendência está registrada na roadmap e no
incidente 0005.
