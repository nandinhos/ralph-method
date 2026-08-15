# ADR 0007 — escopo fechado em três harnesses

**Status:** superseded — substituído pelo [ADR-0017](0017-reabertura-agy-e-seam-comum-de-adapters.md) em 2026-08-14
**Data:** 2026-08-09
**Decisores:** Ralph Method

## Contexto

O Ralph Method precisa manter uma superfície pequena, reproduzível e útil para
projetos diferentes. O ecossistema local possui Codex, Claude CLI, OpenCode,
Hermes e agy, mas cada ferramenta tem uma função e um nível de maturidade
distintos.

## Decisão

Esta linha de desenvolvimento fecha o escopo operacional em três harnesses:

1. **Codex**, pelo runner nativo integrado ao loop;
2. **Claude CLI**, pelo runner nativo integrado ao loop;
3. **OpenCode**, pelo adapter executável, normalizador e comprovado em campo.

Hermes e agy permanecem reconhecidos apenas pela camada passiva de readiness
quando aplicável. Não terão adapter de execução, promoção ou investimento de
maturação nesta linha. Os dois itens ficam no backlog com prioridade nenhuma.

O termo “três adapters” será usado apenas de maneira informal. Tecnicamente,
Codex e Claude usam integrações/runners nativos do loop, enquanto OpenCode tem
um adapter explícito em `adapters/opencode/`. A distinção evita documentar
arquivos ou contratos que ainda não existem.

## Consequências

- O contrato, o trace e o fluxo de gates devem permanecer estáveis para os três
  harnesses fechados.
- Hermes e agy continuam permitidos no schema de detecção para compatibilidade,
  mas `adapter_enabled` não deve ser inferido apenas da presença da CLI.
- Novos adapters exigem nova decisão, fixture offline, smoke real, prova
  adversarial, teste de campo e promoção independente.
- A instalação continua local por projeto; nenhum harness torna o Ralph
  dependente do domínio ou do runtime do `refactor-radar`.

## Gatilho para revisar

Reabrir este ADR somente quando houver uma necessidade de produto explícita,
um contrato de execução estável e orçamento de validação para Hermes ou agy.
