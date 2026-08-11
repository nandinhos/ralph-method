# ADR-0012 — Aprovação idempotente sem commit vazio

## Contexto

O loop do Ralph pode concluir que a fase já está implementada no `HEAD`. Nesse
caso `scripts/ralph.sh` termina com exit code `0`, working tree limpa e nenhum
commit novo. A promoção anterior do `ralph-control` exigia sempre um commit
filho imediato da base da tentativa, deixando uma feature validada presa em
`awaiting_gates`.

## Opções consideradas

1. Criar um commit vazio para satisfazer a regra de promoção.
2. Manter a rejeição e exigir que o executor altere novamente o código.
3. Aceitar explicitamente o resultado idempotente, preservando todas as
   verificações de checkout e mantendo a exigência de commit para mudanças
   reais.

## Decisão

Adotamos a opção 3.

O controlador aceita o caminho `already_present` somente quando o resultado
comprova simultaneamente que base, árvore e commit de implementação são o
checkout atual, que o resultado ainda corresponde ao `HEAD`, que a working tree
está limpa e que os cinco gates estão aprovados. O evento
`feature.approved` registra `implementation_mode=already_present` e
`no_op=true`.

O caminho normal não mudou: uma implementação que diverge da base precisa
produzir exatamente um commit-filho. Se o resultado ficar stale, o controlador
emite `recovery.required`; a aprovação não reinterpreta nem reutiliza gates de
outro checkout.

## Consequências

### Positivas

- fases já presentes podem seguir o fluxo sem commit artificial;
- a idempotência fica visível e auditável no ledger;
- commits reais continuam sujeitos à regra de um commit-filho;
- divergências de checkout deixam de produzir uma feature presa sem rota de
  recuperação.

### Negativas

- uma execução no-op não cria um commit próprio para marcar a passagem;
- a auditoria precisa consultar o resultado e o evento `feature.approved` para
  distinguir presença anterior de mudança recém-produzida;
- uma alteração do checkout entre o bloco e os gates reinicia a tentativa e
  exige nova validação.

## Dono

Equipe do Ralph Method.

## Data

2026-08-11.

## Gatilho para revisitar

Revisitar se o método passar a aceitar múltiplos commits de implementação por
feature, commits de documentação fora do handoff ou promoção entre worktrees;
esses casos exigirão um contrato de proveniência diferente do atual.
