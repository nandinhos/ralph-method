# ADR 0009 — Memória episódica com retenção explícita e taxonomia derivada

## Status

Aceita para a candidata `v0.6.0`.

## Contexto

O Ralph já produzia um candidato de conhecimento depois de liberar uma
feature, mas o candidato existia somente como evento. Faltava uma forma clara
de o usuário revisar, persistir seletivamente ou descartar esse material. A
memória também era recuperada principalmente por texto, sem uma classificação
determinística por categoria e tema.

A memória de engenharia não deve bloquear a fila nem ser confundida com os
cinco gates de entrega. Ao mesmo tempo, o método precisa preservar a origem da
lição e impedir que eventos brutos ou conhecimento irrelevante sejam injetados
no contexto futuro.

## Opções consideradas

1. Persistir automaticamente todos os eventos como memória.
2. Não manter candidatos e depender de curadoria manual fora do Ralph.
3. Criar um cache local sanitizado, exigir decisão explícita de retenção e
   publicar somente lições curadas com taxonomia e índices derivados.

## Decisão

Adotamos a opção 3:

- `feature.released` cria um manifesto sanitizado em
  `.ralph/knowledge-candidates/` e emite `knowledge.candidate_created`;
- `knowledge curated` é a ação explícita que publica uma lição `LES-...`;
- `knowledge rejected`, `review-required` e `skipped` registram a decisão sem
  publicar memória validada;
- uma decisão terminal de retenção não pode ser substituída por outra decisão
  conflitante;
- as lições possuem `category`, `topics`, `stack`, `domain` e `fingerprints`;
- `docs/engineering/INDEX.md` é o índice macro e os arquivos em
  `categories/` e `topics/` são projeções regeneráveis;
- `retrieve` aplica filtros estruturados e só consulta documentos com
  `status: validated`;
- `knowledge_policy.mode` permanece `non_blocking`, separado da decisão de
  retenção;
- descartar uma memória não remove handoff, evidências ou eventos do ledger.

## Consequências

O usuário pode controlar o crescimento da memória sem interromper o
desenvolvimento. O agente recebe menos contexto e pode começar pela categoria e
tema corretos antes de uma futura busca semântica ou grafo de memória.

O cache de candidatos acrescenta arquivos locais transitórios e exige que o
uninstall preserve esse histórico como artefato do projeto. Os subíndices são
projeções e devem ser reconstruídos, nunca editados como fonte independente.

## Dono

Ralph Method.

## Data

2026-08-09.

## Gatilho para revisitar

Revisitar quando houver hub externo de memória, busca semântica ou volume que
torne a recuperação lexical e os índices locais insuficientes. A integração
deve preservar o contrato local e os identificadores de origem; não substituir
o `ralph-control` como autoridade.
