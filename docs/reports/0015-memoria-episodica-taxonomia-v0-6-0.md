# Relatório 0015 — memória episódica, retenção e taxonomia da v0.6.0

**Versão:** `0.6.0` candidata  
**Branch:** `feat/ralph-hardening`  
**Commit da implementação:** `36b02f2`  
**Data:** 2026-08-09  
**Status:** checks locais verdes; promoção, tag e push não realizados

## Objetivo

Adicionar memória episódica de implementação sem transformar conhecimento em
gate bloqueante, permitindo ao usuário revisar cada candidato e decidir entre
persistir, rejeitar, enviar para revisão ou descartar.

## Entrega

| Componente | Resultado comprovado |
|---|---|
| Candidato episódico | `feature.released` cria `.ralph/knowledge-candidates/CUR-...json` com origem sanitizada, status `pending` e retenção `ask` |
| Persistência | `knowledge curated` publica `LES-YYYY-NNNN` em YAML e Markdown |
| Descarte | `knowledge rejected` e `knowledge skipped` registram a decisão sem criar lição |
| Revisão | `knowledge review-required` mantém a decisão pendente sem interromper a fila |
| Idempotência | Repetição de `curated` reutiliza a decisão existente; não cria novo evento de curadoria |
| Integridade | Segunda decisão terminal conflitante é rejeitada com exit `3` |
| Taxonomia | Categoria, temas, stack, domínio e fingerprints são normalizados e persistidos |
| Índice macro | `docs/engineering/INDEX.md` agrega categorias, temas e documentos |
| Subíndices | `docs/engineering/categories/<categoria>.md` e `topics/<tema>.md` são regenerados pelo controlador |
| Recuperação | `retrieve` filtra por taxonomia e consulta somente `status: validated`, com limite de lições e contexto |
| Contrato | `schemas/knowledge-candidate.schema.json` documenta o manifesto local sanitizado |

## Fluxo comprovado

```text
feature.released
→ knowledge.candidate_created
→ .ralph/knowledge-candidates/CUR-...
→ curated | rejected | review-required | skipped
→ lesson persistida ou candidato encerrado
→ próxima feature continua sem depender da memória
```

O ledger continua sendo a fonte de fatos. O candidato é um cache local
descartável. A memória persistente só aparece após `curated`. Descartar não
apaga handoff, evidências nem eventos operacionais.

## Comandos executados

| Comando | Exit | Resultado |
|---|---:|---|
| `bash scripts/check-doc-sync.sh` | 0 | `VERSION` e `AGENT_GUIDE` sincronizados em `0.6.0` |
| `bash scripts/check-shell.sh` | 0 | `bash -n` e ShellCheck verdes em 25 scripts |
| `bash scripts/test-ralph-knowledge.sh` | 0 | handoff, candidato, taxonomia, índices, retenção, descarte, filtros e idempotência verdes |
| `bash scripts/test-installation.sh` | 0 | schema novo incluído na instalação, idempotência e uninstall preservados |
| `bash scripts/test-reproducibility.sh` | 0 | bundle Git commitado reproduzido em projeto independente |
| `bash scripts/test-ralph-method.sh` | 0 | control plane e 163 asserts do loop verdes; cenário `Killed` é fixture de crash esperado |
| `bash scripts/test-ralph-metrics.sh` | 0 | métricas read-only sem mutação |
| `php -l bin/ralph-control` | 0 | sintaxe PHP válida |
| `php -r` sobre `schemas/*.json` | 0 | todos os schemas JSON válidos |
| `bash scripts/ci-portable.sh` | 0 | CI portátil completa, sem credenciais ou geração real |

## Segurança e limites

- `ralph-control` permanece a única autoridade;
- candidato, lição e índices não alteram gates, leases ou fila;
- decisões de retenção conflitantes são rejeitadas;
- dados entram no YAML somente depois de sanitização;
- filtros estruturados reduzem o contexto antes da recuperação lexical;
- busca semântica, grafo e hub externo ainda não foram implementados;
- a revisão adversarial independente foi iniciada, mas excedeu o timeout e foi
  encerrada sem veredicto; isso não foi contado como aprovação;
- a prova atual é portátil e local; não houve nova geração real de provider,
  pois a alteração não tocou os adapters.

## Arquivos de contrato

- [`docs/adr/0009-memoria-episodica-e-taxonomia.md`](../adr/0009-memoria-episodica-e-taxonomia.md)
- [`docs/architecture/data-model.md`](../architecture/data-model.md)
- [`docs/architecture/interfaces.md`](../architecture/interfaces.md)
- [`docs/AGENT_GUIDE.md`](../AGENT_GUIDE.md)
- [`scripts/test-ralph-knowledge.sh`](../../scripts/test-ralph-knowledge.sh)

## Decisão de release

A implementação está validada no escopo da feature e o commit está pronto
para revisão humana. A branch continua candidata `v0.6.0`; não foi promovida
para `main`, não recebeu tag e não houve push remoto.
