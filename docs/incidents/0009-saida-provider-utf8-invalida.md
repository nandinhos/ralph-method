# Incidente 0009 — saída de provider com UTF-8 inválido

**Data:** 2026-08-09
**Componente:** `ralph-control` e parser OpenCode
**Severidade:** média
**Estado:** resolvido e validado em campo

## Sintoma

Uma execução real do teste de campo OpenCode concluiu a implementação e a
revisão read-only, mas o encerramento do `ralph-control` terminou com:
`Malformed UTF-8 characters, possibly incorrectly encoded`.

## Causa raiz

O preview capturado de stdout/stderr e algumas mensagens textuais do runner
eram encaminhados para `json_encode(... JSON_THROW_ON_ERROR)` sem uma garantia
explícita de UTF-8. Um byte binário isolado podia fazer a serialização falhar
depois de todos os gates do provider terem passado.

## Correção

- adicionado `sanitizeUtf8()` no control plane;
- bytes inválidos são removidos determinísticamente com `iconv` antes de
  padrões de segredo e serialização;
- chaves textuais de arrays também passam pela normalização;
- o parser OpenCode aplica a mesma proteção a `error_summary`;
- nenhum segredo, prompt ou resposta completa é preservado por essa correção.

## Evidência

O teste de método executa um bloco cujo comando emite deliberadamente `0xFF`;
o ledger permanece verificável e o teste termina com exit `0`. Depois disso:

- adversarial OpenCode: `OPENCODE_ADVERSARIAL_TEST_OK`, 97s;
- campo OpenCode: `FIELD_TEST_OK`, 118s;
- regressão portátil do control plane: verde.

## Risco residual

Remover bytes inválidos pode reduzir a fidelidade de uma mensagem textual,
mas é preferível a publicar JSON inválido ou abortar a transição de
encerramento. O artefato bruto continua separado e protegido pelos limites de
captura do runner; a memória e o ledger recebem somente representação
sanitizada.
