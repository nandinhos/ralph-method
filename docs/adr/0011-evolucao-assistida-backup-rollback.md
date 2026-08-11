# ADR-0011 — Evolução assistida com backup e rollback condicional

## Contexto

O detector da v0.7.0 bloqueava o `apply` quando encontrava um Ralph fora do
manifesto do Ralph Method. Isso evitava sobrescrita, mas deixava o usuário sem
um caminho operacional reproduzível para testar a versão nova mantendo a
possibilidade de retorno.

O método não conhece a semântica de um Ralph externo. Ledger, workflow,
prompts, credenciais e eventos podem possuir contratos incompatíveis e não
podem ser importados por inferência.

## Opções consideradas

1. Liberar o `apply` comum após um aviso.
2. Copiar todo o projeto para um backup genérico e tentar migrar o estado.
3. Criar uma operação explícita, numerada e protegida por lock que isola apenas
   os sinais detectados, preserva runtime, instala o método novo e oferece
   rollback condicionado a hashes.
4. Criar adapters específicos antes de permitir qualquer teste de evolução.

## Decisão

Adotamos a opção 3, no modo `quarantine_only`.

Os comandos são:

```text
evolve --plan
→ inventário somente leitura
→ evolve --apply
→ EVL-YYYYMMDD-NNNN
→ backup com SHA-256
→ isolamento dos sinais não-runtime
→ instalação transacional do Ralph Method
→ awaiting_acceptance
→ accept ou rollback --apply
```

O estado fica em `.ralph/evolutions/<id>/evolution.json`, o backup fica em
`.ralph/evolutions/<id>/backup/` e a operação usa o mesmo
`.ralph/install.lock` do instalador. Sinais de
`.git/ralph-control/events.jsonl` e `.git/ralph-control/workflow.json`
permanecem no lugar e são apenas registrados como preservados.

Quando a origem é `legacy_directory`, a quarentena move a raiz inteira para o
backup, mantendo subdiretórios, arquivos, permissões e symlinks internos sem
seguir nenhum symlink durante o inventário. Cada membro recebe tipo, modo,
SHA-256 e, quando aplicável, o alvo do symlink; a árvore também recebe um
fingerprint composto e o estado mantém um journal com o evento `before` e
`after` de cada movimento. O backup e o staging permanecem disponíveis para
recuperação explícita após uma falha intermediária.

O rollback só é autorizado quando:

- o manifesto novo existe e seus arquivos possuem os hashes instalados;
- nenhum arquivo gerenciado está ausente ou modificado;
- todo backup necessário existe;
- o inventário efetivo da árvore legada tem exatamente os membros registrados
  (sem ausências nem entradas extras), mantendo tipo, permissões, hash e
  fingerprint compatíveis antes da restauração;
- nenhum destino legado não gerenciado está ocupado;
- a evolução está em `awaiting_acceptance`, `accepted` ou
  `recovery_required`.

O aceite é explícito e mantém o backup. O rollback não apaga o histórico do
projeto e não sobrescreve alteração do usuário. Falhas intermediárias deixam o
estado `recovery_required` para ação explícita.

## Consequências

### Positivas

- o usuário pode testar uma versão nova em projeto com Ralph legado;
- o caminho é idempotente e auditável por um ID numerado;
- a barreira normal de `apply` permanece fail-closed;
- o rollback é impedido por drift em vez de destruir trabalho;
- não há falsa promessa de migração sem adapter de origem.

### Negativas

- o estado legado não é traduzido para o Ralph Method;
- o backup fica local no projeto e exige gestão de espaço;
- falhas de filesystem podem exigir recuperação manual;
- o journal e o staging podem permanecer até que o rollback seja concluído;
- adapters de origem continuam sendo uma evolução posterior.

## Dono

Equipe do Ralph Method.

## Data

2026-08-10.

## Gatilho para revisitar

Adicionar um adapter somente quando existir uma origem identificável, contrato
documentado para ledger/workflow e fixtures reais de importação, falha parcial,
rollback e compatibilidade. O modo `quarantine_only` deve continuar sendo o
fallback quando a origem não for comprovada.
