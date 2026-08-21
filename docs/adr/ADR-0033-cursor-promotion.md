# ADR-0033 — Promoção do adapter Cursor por prova completa

- **Status:** accepted
- **Date:** `2026-08-21`
- **Owner:** Equipe do Ralph Method

## Contexto

A FEATURE-100A registrou o opt-in do Cursor e o relatório
[`0031-cursor-field-20260817.md`](../reports/0031-cursor-field-20260817.md)
comprovou uma execução de campo do adapter. Essa evidência cobre autenticação,
identidade observada, execução impl, verify declarado e árvore inalterada, mas
declara explicitamente que a revisão adversarial independente e o hero flow
continuavam pendentes.

Opt-in é intenção operacional, não evidência de que as fronteiras de entrada,
allowlist, claims e gates sobreviveram a uso hostil. Promover Cursor somente
com esse sinal permitiria que uma promessa de compatibilidade entrasse na
cadeia de produção.

## Decisão

Manter o Cursor disponível como adapter — ele não é banido —, mas exigir quatro
sinais explícitos no estado persistido em
`.ralph/adapter-promotion/cursor.json`:

```json
{
  "optin": true,
  "adversarial": true,
  "hero": true,
  "promoted": true
}
```

`promoted` é derivado e só pode ser verdadeiro quando `optin`, `adversarial` e
`hero` forem verdadeiros. O comando somente leitura
`ralph-control provider-status --format json` expõe esses campos e a lista
`promotion_blockers`; a mutação exige `--promote` depois das provas.

Enquanto houver qualquer bloqueio, `--engine cursor` falha com a mensagem
canônica de rebaixamento. O supervisor pode rebaixar explicitamente a execução
para `opencode`, registrando o aviso operacional; não há troca silenciosa em
uma chamada direta do controlador ou do loop.

O registry de `document-id` reconhece o escopo `promotion-blockers` (ou
`promotion_blockers`) e registra a métrica `promotion_blockers` no índice
local. Assim, o número e os nomes dos bloqueios podem ser correlacionados com
os relatórios sem copiar prompts, respostas ou credenciais.

## Consequências

### Positivas

- Opt-in declarado não habilita execução de produção por si só.
- Adversarial e hero tornam-se provas reproduzíveis e independentes do estado
  derivado `promoted`.
- O estado por adapter é local, atômico, ignorado pelo Git e legível pelo
  operador; adapters já certificados permanecem retrocompatíveis no status.
- Falhas do Cursor são classificadas antes de iniciar um bloco, evitando
  claims ou leases órfãos.

### Negativas

- O Cursor pode ficar temporariamente indisponível mesmo com sessão autenticada
  até os dois scripts de prova passarem.
- `verify` do Cursor continua declarado (`ask`), não uma prova mecânica de
  isolamento; esta decisão não eleva esse contrato.
- O supervisor precisa de um `opencode` funcional para executar o rebaixamento
  automático; se ele não existir, a execução permanece bloqueada.

## Evidência exigida para revisitar

Executar, no checkout de campo, `tests/test-cursor-adversarial.sh` e
`tests/test-cursor-hero.sh`, validar `promotion_blockers: []`, e somente então
usar `ralph-control provider-status --promote cursor`. Qualquer mudança de
contrato do adapter deve reabrir esta decisão e preservar a regra fail-closed.
