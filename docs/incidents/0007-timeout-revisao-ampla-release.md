# Incidente 0007 — timeout da revisão ampla da release

**Data:** 2026-08-08
**Componente:** revisão independente OpenCode
**Release candidata:** `v0.4.0` / `c6a7f74995bc5f93aefe51212b3ba1e949788baf`
**Severidade:** operacional, sem mutação do código
**Status:** resolvido por mitigação bounded

## Contexto

Antes da promoção local para `main`, foi criado um snapshot descartável da
branch completa e submetido ao agente `ralph-review` com política read-only
comprovada externamente. A política passou: o canário de mutação foi recusado,
a superfície da política permaneceu com o mesmo hash e a prova foi aceita pelo
checker.

## Sintoma

A revisão ampla recebeu um escopo recursivo de todos os componentes e
documentos. O OpenCode permaneceu explorando o snapshot até o timeout de 240s.
O JSONL permaneceu válido e tinha uma sessão, mas não apresentou os marcadores
obrigatórios `FINAL_REVIEW_*`. Foram observados 84 eventos `read`, sete
`glob`, cinco `grep` e nenhum veredicto estruturado. A execução não foi tratada
como aprovação.

Na repetição do probe adversarial com `opencode/big-pickle`, a sessão também
atingiu o timeout de 180s sem emitir `ADVERSARIAL_VERDICT: PASS`.

## Análise da causa raiz

O bloqueio não reproduziu uma violação do contrato do adapter. O padrão foi
continuidade excessiva de uma revisão aberta, sem limite de arquivos nem de
chamadas de leitura. A hipótese de defeito funcional foi confrontada contra:

- a prova externa de política read-only;
- a suíte determinística do adapter, schema e policy;
- uma revisão bounded independente;
- um novo probe adversarial com outro modelo OpenCode.

## Correção e mitigação

Foi aplicado um protocolo bounded para a decisão final: lista explícita de oito
arquivos, no máximo oito chamadas `read`, proibição de ferramentas de busca e
execução, veredicto obrigatório e timeout. Com
`opencode/deepseek-v4-flash-free`, o probe terminou com exit `0`, uma sessão,
dois `step_finish`, oito leituras e:

```text
FINAL_REVIEW_VERDICT: PASS
FINAL_REVIEW_FINDINGS: none
```

O probe adversarial real subsequente também passou em 61s, sem alteração de
código. A proteção de timeout permanece obrigatória; timeout continua sendo
falha operacional e nunca autorização implícita.

## Risco residual

Modelos e providers podem variar em continuidade e tempo de resposta. Novas
versões do OpenCode, da política ou do agente devem repetir o protocolo
bounded, a prova externa e o teste de campo. Uma revisão ampla exploratória
continua útil para diagnóstico, mas não é usada como gate sem saída estruturada.
