# Incidente 0005 — timeout da revisão adversarial do OpenCode

## Sintoma

As duas revisões `bc-reviewer` independentes, embora read-only e com escopos
reduzidos, não produziram parecer dentro das janelas de espera do orquestrador.
Os agentes foram encerrados com status `running`; portanto não houve aprovação
adversarial implícita.

Uma terceira revisão, reduzida a uma única alegação, respondeu com `FAIL` ao
afirmar que `--policy-proof` seria a única forma aceita. A leitura do código
mostrou que a alegação estava estreita: o runner aceita também a variável
externa `RALPH_OPENCODE_VERIFY_POLICY_PROOF`.

## Investigação sistemática

| Hipótese | Verificação | Resultado |
|---|---|---|
| O contrato não exige prova no modo `verify` | `runner.sh:126-132` e ausência de prova em `scripts/test-opencode-adapter.sh` | rejeitada; sem agente/prova o runner encerra antes da CLI |
| A prova só pode chegar por argumento | `runner.sh:91` e `runner.sh:111` | rejeitada; argumento e variável de ambiente são fontes equivalentes |
| O adapter está aceitando prova inválida | `scripts/test-opencode-policy.sh` e `policy.php check` no artefato de campo | rejeitada; hash, sessão, terminal, marcador, árvore e superfície são revalidados |
| A revisão adversarial ampla tem retorno determinístico dentro do timeout atual | duas sessões `bc-reviewer` sem parecer | não comprovada; o canal de revisão continua sujeito a timeout |

## Causa raiz

Há duas causas separadas:

1. o contrato documental não explicitava as duas fontes equivalentes da prova,
   permitindo um falso finding sobre `--policy-proof`;
2. a orquestração adversarial ainda não impõe um protocolo bounded com saída
   estruturada e deadline observável para cada lente.

Isso não indica falha funcional do adapter OpenCode. Indica que a maturação da
camada adversarial ainda não está concluída.

## Correção e prevenção

- documentar a prova como obrigatória, aceitando `--policy-proof` ou
  `RALPH_OPENCODE_VERIFY_POLICY_PROOF`;
- manter os testes fail-closed para ausência, campo extra, sessão ausente,
  marcador ausente, hash divergente, política stale e prova dentro da raiz;
- dividir a revisão adversarial em lentes pequenas, com timeout explícito,
  resposta estruturada e estado `inconclusive` em caso de expiração;
- não promover a branch enquanto uma revisão adversarial bounded não retornar
  parecer verificável sem timeout.

## Estado

`open` — o adapter e o campo real estão verdes, mas a certificação adversarial
repetível permanece na to-do antes da promoção para `main`.
