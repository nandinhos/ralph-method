# ADR 0017 — Reabertura do `agy` e seam comum de adapters

- **Status:** accepted
- **Date:** `2026-08-14`
- **Owner:** Equipe do Ralph Method

## Context

O [PRD do adapter `agy`](../prd/prd-adapter-agy.md) satisfaz o gatilho do
ADR-0007: há demanda explícita, contrato headless estável e orçamento de
validação. Também dispara o gatilho do ADR-0005: `agy` é o segundo provider
novo que exigiria exceções de preflight, dispatch e gate no núcleo.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A — Manter `agy` passivo** | zero mudança no loop | não atende a demanda nem amplia capacidade |
| **B — Adicionar branches `agy` em cada ponto** | implementação local rápida | duplica conhecimento e viola o gatilho do ADR-0005 |
| **C — Extrair seam `preflight|run|version` para adapters** | OpenCode e `agy` ficam substituíveis sob um contrato | exige caracterizar e ajustar o caminho OpenCode |
| **D — Migrar também Codex/Claude** | uniformidade total imediata | ampliação especulativa e regressão desnecessária |

## Decision

Adotar a opção C. `scripts/ralph.sh` reconhecerá adapters por um dispatch único
e chamará `adapters/<runner>/runner.sh` com argumentos comuns de execução e um
`runner-result` normalizado. OpenCode e `agy` entram nessa seam; Codex e Claude
permanecem runners nativos caracterizados. `bin/ralph-control`, gates e
`fallback_policy=none` não mudam.

O contrato externo vigente é `preflight|run|version`. O `classify` proposto no
ADR-0005 passa a ser responsabilidade interna do parser chamado por `run`; os
metadados antes projetados por `metadata` são publicados no `runner-result` e
a versão isolada permanece acessível por `version`. Assim não há operação órfã
nem classificação específica no loop.

O provider `agy` somente será elegível quando seus probes não generativos e os
pré-requisitos de verify Linux forem funcionais. A identidade canônica em
configuração, schema, trace e paths é `agy`.

## Consequences

- ADR-0005 e ADR-0007 ficam superseded, com histórico preservado;
- o loop deixa de conhecer flags específicas de cada adapter;
- cada adapter continua dono de modelo, agente, política e parser;
- adicionar um próximo adapter compatível não exige novo branch no gate 0;
- instalação, fixture offline, prova real e promoção independente continuam
  obrigatórias;
- failover e escolha de destino permanecem fora do adapter e desta feature.

## Trigger to revisit

Revisitar quando um adapter não puder ser reduzido a uma sessão headless com
prompt, eventos e resultado final; ou quando três adapters precisarem de um
segundo transporte comum. Owner: Equipe do Ralph Method. Não migrar runners
nativos antes desse sinal observável.
