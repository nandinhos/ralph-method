# Incidente 0011 — Timeout da revisão adversarial por contexto de checkout

## Estado

Resolvido e reproduzido em `2026-08-09`.

## Sintoma

As duas primeiras revisões adversariais da detecção de Ralph externo
permaneceram em estado `running` e excederam o timeout do orquestrador. Não
houve veredito `pass` ou `fail` e nenhum arquivo foi alterado pelo subagente.

## Impacto

- a aprovação independente ficou indisponível naquela execução;
- a implementação não foi promovida com base nesse veredito;
- não houve alteração de produto, ledger ou instalação;
- os testes locais continuaram executáveis e verdes.

## Investigação

Foram executados probes bounded com o mesmo ecossistema:

| Probe | Escopo | Resultado |
|---|---|---|
| `default` sem ferramentas | responder `ACK` | concluído em menos de 30s |
| `bc-reviewer` sem ferramentas | responder `ACK` | concluído em menos de 30s |
| `bc-reviewer` com `pwd` | um comando | concluído; cwd não era o projeto esperado |
| `bc-reviewer` com `rg` relativo | três arquivos | falhou com paths inexistentes |
| `bc-reviewer` com `cd` explícito + `rg` | mesma verificação | `verdict: pass` em menos de 60s |

O agente conseguia iniciar e executar comandos. O problema era que a
delegação não estabelecia o diretório de trabalho do checkout. A instrução
fornecia o caminho no texto, mas usava paths relativos sem `cd` explícito. Ao
encontrar arquivos inexistentes, a revisão bounded não terminava com erro
imediato e podia ampliar a busca/contexto até atingir o timeout.

## Causa raiz

Dependência implícita entre a instrução textual da delegação e o diretório de
trabalho efetivo do subagente. O contrato de revisão também não exigia parada
fail-closed quando a primeira busca retornasse exit code diferente de zero.

## Correção aplicada

As delegações de revisão deste fluxo passam a exigir:

1. `cd` explícito para a raiz absoluta do checkout;
2. escopo de arquivos fechado;
3. quantidade limitada de comandos;
4. proibição de rede, geração e testes completos quando a tarefa é apenas
   revisão estrutural;
5. resposta estruturada e timeout bounded;
6. falha imediata se a busca inicial não encontrar os caminhos esperados.

O probe corrigido confirmou a presença de `detectExistingRalphInstallation`,
`apply_allowed` e `migration_supported`, além da restrição de
`migration_supported=false` no schema.

## Prevenção

- não considerar timeout como aprovação ou reprovação;
- registrar `running` → `timeout` como incidente de orquestração;
- executar um probe de saúde do papel antes de uma revisão ampla quando o
  ambiente tiver trocado de checkout;
- usar caminhos absolutos ou `cd` no primeiro comando de toda delegação;
- manter a revisão adversarial independente dos gates funcionais da feature.

## Evidência

- probe `bc-reviewer` sem contexto explícito: timeout;
- probe com `rg` relativo: exit `2`, paths inexistentes;
- probe com `cd /home/nandodev/projects/ralph-method` explícito: `verdict: pass`;
- `bash scripts/ci-portable.sh`: verde, `163 asserts` no loop;
- captura operacional em `docs/.scribe/capture.log`.
