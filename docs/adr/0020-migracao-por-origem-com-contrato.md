# ADR-0020 — Migração por origem com contrato específico (adapter `bc-harness`)

- **Status:** accepted
- **Date:** `2026-08-16`
- **Owner:** Equipe do Ralph Method

## Contexto

A evolução assistida (ADR-0010/0011) entrega detecção, backup, isolamento e
rollback no modo `quarantine_only`: nenhum ledger, workflow, prompt, credencial
ou evento externo é importado. O detector reconhece a assinatura `bc-harness`
em `harness/ralph` e classifica a origem como `external_ralph_legacy`, mas
`migration_supported` permanece `false` (ADR-0010: "Até existir um adapter de
migração por origem, o método não importa `.git/ralph-control`, prompts,
credenciais, workflow ou eventos externos").

Há agora demanda real de reutilizar o conhecimento de um projeto com Ralph
legado `bc-harness` (ex.: o `refactor-radar`) ao adotar o Ralph Method. Essa
reutilização é uma **migração semântica por origem**, não uma cópia genérica:
cada família legada tem ownership, runtime e semântica próprios, e importar
estado sem contrato específico é inferência arriscada.

## Opções consideradas

| Opção | Vantagens | Desvantagens |
|---|---|---|
| **A — Manter `quarantine_only` para sempre** | Superfície mínima e nenhum risco | Não reaproveita conhecimento legado; usuário re-faz handoff/memória à mão |
| **B — Importar tudo de qualquer origem** | Parece completo | Inferência por heurística, corrompe ownership, importa o que o usuário não entendeu |
| **C — Adapter de migração por origem, contrato fechado** | Conhecimento reutilizável com ownership e hashes; fail-closed para origens desconhecidas | Exige contrato, schema, fixtures e prova por origem |

## Decisão

Adotar a opção C, restrita à primeira origem com contrato: `bc-harness` em
`harness/ralph`.

Um adapter de migração por origem é um componente que declara, **para uma
família e raiz aprovadas**:

- os caminhos de ownership que podem ser traduzidos (ex.: conhecimento em
  `docs/`, handoffs, índice de memória);
- o que **nunca** é importado (ledger, workflow, prompts, credenciais, eventos
  brutos);
- a função de tradução determinística (mapeamento de campos → estrutura canônica
  do Ralph Method), com validação por schema e hashes antes/depois;
- o modo `quarantine_only` continua sendo a fronteira preventiva: a migração só
  roda após `evolve --apply` com backup íntegro e aceite explícito.

O contrato é declarado em `schemas/migration-adapter.schema.json`. A
classificação `migration_supported` do detector passa a vir do adapter
registrado, e não de heurística.

### Escopo inicial da origem `bc-harness`

Somente o que tem equivalência direta e sanitizada:

- handoffs textuais do `bc-harness` (documentos de fase/condução) → candidatos
  de memória do Ralph Method (`knowledge_candidates`);
- índice de conhecimento existente → candidatos de memória, **sem conteúdo
  bruto** de ledger/prompt/credencial;
- caminhos de runtime já preservados pela evolução (`.git/ralph-control`) são
  ignorados como hoje.

Não é importado: ledger, workflow, prompts, respostas, credenciais, eventos
brutos, leases ou proofs.

## Consequências

### Positivas

- conhecimento legado reaproveitável sem re-escrever handoff à mão;
- importação auditável e reversível (candidatos são rejeitáveis/descartáveis);
- `migration_supported` passa a ser decisão de contrato, não de heurística;
- origens sem contrato permanecem `quarantine_only` (fail-closed).

### Negativas

- cada origem exige contrato, schema, fixtures e prova;
- a tradução é determinística e limitada ao que tem equivalência canônica;
- nenhuma promessa de "converter tudo" para famílias desconhecidas.

### Obrigações

- nenhuma importação sem schema validado e hashes antes/depois;
- nenhuma importação de ledger/workflow/prompts/credenciais/eventos;
- `quarantine_only` continua default; `migration_supported` só com adapter;
- prova por fixture offline, regressão e campo antes de habilitar nova origem.

## Gatilho para revisitar

Revisitar quando uma segunda origem (ex.: OpenCode), ou a necessidade de
importar mais que conhecimento do `bc-harness`, tiver contrato e prova. Owner:
Equipe do Ralph Method.
