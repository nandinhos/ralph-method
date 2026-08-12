# ADR-0010 — Detecção segura de Ralph externo antes da instalação

## Status

Aceita

## Contexto

O `ralph-init` reconhecia ownership somente quando encontrava
`.ralph/install-manifest.json` do Ralph Method. Um projeto que já possuísse um
Ralph de outra implementação podia, portanto, parecer apenas um conjunto de
conflitos de arquivos. Isso não distinguia uma instalação legada de um arquivo
com nome parecido e não oferecia ao agente informação suficiente para planejar
uma evolução.

A instalação de uma versão nova não pode mover, apagar ou interpretar
silenciosamente o runtime, prompts, workflow, credenciais ou ledger de uma
implementação desconhecida. O `ralph-control` do método também não pode herdar
estado externo sem uma tradução de contrato verificável.

## Opções consideradas

1. Sobrescrever os arquivos conflitantes e preservar somente os que falharem.
2. Procurar qualquer arquivo com `ralph` no nome e bloquear sempre.
3. Detectar um conjunto pequeno de sinais canônicos, exibir hashes e bloquear
   o `apply` comum quando a origem não pertence ao manifesto do método.
4. Fazer migração automática, incluindo ledger, workflow e prompts, para o
   novo runtime.

## Decisão

Adotamos a opção 3.

`bin/ralph-init plan` produz `ralph_installation`, conforme
`schemas/ralph-installation-detection.schema.json`, com:

- estado do manifesto do Ralph Method;
- classificação `not_found`, `detected` ou `ambiguous` da origem externa;
- confiança e sinais identificados por caminho relativo, tipo e SHA-256;
- decisão `apply_allowed` e recomendação operacional;
- indicação explícita de que a migração genérica ainda não é suportada.

O detector é somente leitura. Ele não abre, imprime ou copia o conteúdo dos
arquivos identificados. Um sinal canônico, ou dois sinais compatíveis, produz
`detected` com confiança alta. Um único marcador genérico produz
`ambiguous`; os dois casos bloqueiam o `apply` comum com exit code `3`. Uma
pasta `.ralph` sem marcador conhecido não bloqueia por si só.

### Reconhecimento limitado da instalação legada `bc-harness`

O detector também reconhece, somente na raiz aprovada `harness/ralph`, a
assinatura `bc-harness` formada pela composição `install.sh` + `ralph.patch` +
`ralph.sh.upstream`. Quando todos os membros estão presentes, o plano emite
`classification=external_ralph_legacy`, `family=bc-harness`,
`signature_id` determinístico, `members` com tipo/path/modo/SHA-256, `legacy_type
=legacy_directory`, `tree_fingerprint` composto e `recommended_action=evolve`,
sem armazenar conteúdo bruto. `apply_allowed=false` bloqueia o `apply` comum e
`migration_supported=false` mantém a migração fora do detector.

Raízes aprovadas incompletas aparecem em `legacy_candidates` como `candidate`
sem virar instalação; raízes inválidas (absoluta, traversal ou symlink externo)
são rejeitadas como `rejected` e não são seguidas. Caminhos parecidos dentro de
`vendor` e `node_modules` estão fora do escopo e nunca geram classificação.
Esta extensão foi validada na regressão `FEATURE-093-REGRESSION-RELEASE`
(relatório `0021`) e o ciclo completo de evolução de diretório legado está no
ADR-0011.

Arquivos pertencentes ao manifesto válido do Ralph Method e o runtime
operacional conhecido do próprio método são ignorados pelo detector. Um
marcador externo adicional continua sendo reportado, pois não possui
ownership conhecido.

Uma futura evolução assistida deverá ser uma operação explícita e separada,
com `plan`, confirmação, backup verificável, manifesto de rollback e restauração
condicional. O desenho previsto é:

```text
evolve --plan
→ inventário e escopo aprovados
→ evolve --apply
→ backup imutável + hashes
→ isolamento da instalação legada
→ apply transacional do Ralph Method
→ doctor + relatório
→ rollback --apply, se solicitado e se a instalação nova não tiver drift
```

Essa operação não faz parte do detector inicial. Até existir um adapter de
migração por origem, o método não importa `.git/ralph-control`, prompts,
credenciais, workflow ou eventos externos. A instalação legada permanece
intacta para revisão ou backup conduzido explicitamente pelo usuário.

## Consequências

### Positivas

- reduz o risco de sobrescrever um Ralph de outra origem;
- permite que o agente veja sinais objetivos antes de decidir uma evolução;
- mantém o `apply` idempotente e o ownership baseado no manifesto;
- preserva o histórico externo até que exista um contrato de migração;
- torna possível adicionar adapters de origem sem contaminar o instalador base.

### Negativas

- a primeira versão exige revisão manual quando encontra Ralph externo;
- a detecção por sinais não prova a semântica do runtime legado;
- a evolução com backup e rollback exige uma fase própria e testes de crash,
  drift, espaço em disco e restauração parcial.

## Dono

Equipe do Ralph Method.

## Data

2026-08-09. Estendido em 2026-08-12 com o reconhecimento da assinatura
`bc-harness` em `harness/ralph` e a classificação `external_ralph_legacy`
(validação na regressão `0021`). Revalidado em 2026-08-12 após o hardening do
supervisor (ADR-0013) e o fix de prontidão com SIGPIPE, na regressão `0023`.

## Gatilho para revisitar

Demanda real de instalar o método em projeto com Ralph legado, acompanhada de
uma origem identificável, caminhos de ownership conhecidos e contrato para
preservar ou traduzir seu estado. A reabertura exige fixture de backup,
rollback, falha intermediária e restauração sem sobrescrever alterações do
usuário.
