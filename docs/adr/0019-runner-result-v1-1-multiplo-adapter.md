# ADR 0019 — `runner-result` 1.1 para múltiplos adapters

- **Status:** accepted
- **Date:** `2026-08-14`
- **Owner:** Equipe do Ralph Method

## Context

O schema `runner-result` 1.0 é específico do OpenCode: runner constante e
terminal `step_finish`. O `agy` observa terminal `result`. Alterar a semântica
sob o mesmo número quebraria consumidores; usar `2.0.0` anteciparia o contrato
de outcome/failover reservado à FEATURE-094.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A — Reusar `1.0.0`** | nenhum novo número | muda contrato publicado silenciosamente |
| **B — Criar schema exclusivo `agy`** | isolamento máximo | duplica contrato comum e gate |
| **C — Adicionar `1.1.0` compatível** | preserva 1.0 e adia v2 | schema precisa de condicionais por versão/runner |
| **D — Publicar `2.0.0` agora** | unificação futura | incorpora versão sem os campos de failover planejados |

## Decision

Adotar a opção C. O arquivo canônico aceitará:

- OpenCode `schema_version=1.0.0`, `runner=opencode`, terminal `step_finish`;
- `agy` `schema_version=1.1.0`, `runner=agy`, terminal `result`;
- requisitos comuns de sessão, identidade, fallback e policy por modo.

O parser OpenCode não muda sua versão. O parser `agy` deve observar o modelo no
evento `init`; ausência/divergência falha closed e nunca vira identidade exata
por mera configuração.

`bin/ralph-control` continua autoridade de importação e passa a validar a matriz
versão/runner/terminal. A policy evidence é despachada ao checker do runner; o
resultado importado preserva o runner observado em vez de fixar `opencode`.

## Consequences

- consumidores existentes de 1.0 permanecem válidos;
- gate 0 pode tratar adapters por resultado comum sem interpretar JSONL bruto;
- `2.0.0` continua reservado ao outcome/failure domain/failover;
- fixtures devem provar ambas as versões e seus terminais incompatíveis.

## Trigger to revisit

Publicar `2.0.0` somente quando FEATURE-094 definir e implementar outcome,
failure domain, retry/failover e importação sob lease, ou quando uma mudança
incompatível adicional não couber em 1.x. Owner: Equipe do Ralph Method.
