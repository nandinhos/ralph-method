# Relatório 0006 — reteste adversarial baseado em documentação oficial

## Resultado executivo

As causas levantadas na rodada anterior foram confrontadas com documentação
primária e com uma nova abordagem: um probe executado pelo próprio OpenCode,
em vez do canal de subagentes que expirou.

| Critério | Resultado |
|---|---|
| Documentação oficial confrontada | OpenCode, Claude Code e Codex CLI |
| Probe real | OpenCode `1.18.15`, modelo `opencode/big-pickle` |
| Verdict estruturado | `ADVERSARIAL_VERDICT: PASS` |
| Sessão | 1 |
| Eventos `step_finish` | 4, todos na mesma sessão |
| Ferramentas de leitura | 10: glob, read e grep |
| Ferramentas proibidas | 0 executadas |
| Política | `policy.php check` exit 0 |
| Superfície | hash antes/depois idêntico |
| Duração | 38s |

## Findings e correções

1. O probe inicial falhou por exigir cardinalidade `step_finish == 1`. A
   execução real mostrou uma sequência multi-step; o contrato passou a exigir
   `step_finish >= 1` e sessão única.
2. O parser aceitava a primeira sessão e ignorava uma segunda. Agora rejeita
   JSONL com `sessionID` divergente.
3. O runner podia anexar dois `--agent` quando argumento e ambiente divergiam.
   Agora resolve um agente único e reprova a divergência antes da chamada à
   CLI.

## Contrato após o reteste

```text
OpenCode run
→ --format json
→ sessão nova sem --continue/--session
→ agente explícito
→ política deny efetiva
→ JSONL com uma sessão
→ pelo menos um step_finish
→ verdict estruturado
→ hash e árvore preservados
```

## Status

O adversarial específico do adapter OpenCode está comprovado e foi marcado como
concluído na roadmap. A promoção para `main` ainda não ocorreu: falta apenas a
revisão adversarial da branch completa e a regressão final de release.
