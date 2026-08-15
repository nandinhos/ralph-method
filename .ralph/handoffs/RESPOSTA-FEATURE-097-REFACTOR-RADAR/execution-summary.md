# HND-2026-0012 — Resposta ao feedback da FEATURE-097 (retry de gate sem re-execução)

- Documento: HND-2026-0012
- Origem: `ralph-method` (implementação nativa)
- Destino: `refactor-radar` (projeto-alvo; INC-2026-0007, HND-2026-0011)
- Estado: implementado e testado; aguardando reativação no projeto-alvo
- Política de conhecimento: non_blocking

## O que foi corrigido (resposta ao HND-2026-0011)

O feedback identificou 6 findings. Este handoff entrega a correção dos que
bloqueiam o fechamento da phase-25 e dos que eram bugs de método:

1. **Retry pós-debugging de feature commitada NÃO re-executa o bloco**
   (findings 3 e 6 — bloqueador): após `debugging_verified` com bloco
   commitado e falha de gate, o supervisor agora usa `beginGateRetry`
   (`gate.retry_started` → `awaiting_gates`) e re-roda **só o gate pendente**,
   sem nova tentativa de implementação. Antes: 7–9 re-execuções do bloco
   (~10–16 min cada). Regressão no cenário D de `test-ralph-gate-recovery.sh`
   confirma `attempts.started` estável.
2. **Default do gate curation corrigido** (finding 2): pré-release o default é
   read-only (`ralph-knowledge candidates --workflow ... --feature ...`), sem
   exigir ação de retenção que saía com exit 2 antes de `feature.released`. O
   workaround `ralph-curate-gate.sh` do projeto deixa de ser necessário.
3. **gate-test com timeout do gate real** (finding 1): o self-test usa o
   `gate-timeout` do supervise real (default 900s; `--gate-timeout` para
   override), eliminando o falso `gate_harness_error` em `bin/check` e em
   gates LLM.
4. **Evidência mínima e classificação** (findings 4 e 5): comando com exit 0 e
   stdout vazio é `gate_harness_error`; gates de longa duração são cobertos
   pelo `gate-test` com timeout adequado.

## Próximo passo no refactor-radar

Atualizar o método para a versão que contém esta correção (após o merge) e
re-rodar o `supervise` em `wf_ralph_20260805_001` (phase-25). Como o
`technical_review` e o `curation` já estavam aprovados e o comando de review
está corrigido, o fechamento deve ocorrer **sem nova sessão de implementação**:
o retry re-roda apenas os gates pendentes.

Antes do `supervise`, validar:

```bash
bin/ralph-control gate-test --gate technical_review
bin/ralph-control gate-test --gate curation
bin/ralph-control gate-test --gate quality
```

## Evidência

- Implementação: `bin/ralph-control` (`beginGateRetry`, `gate.retry_started`,
  `gate-test` com `--gate-timeout`), `scripts/ralph-run-independent-gate.sh`
  (default de curation), `scripts/test-ralph-gate-recovery.sh` (cenário D);
- origem: HND-2026-0011 e INC-2026-0007 (refactor-radar);
- regressão verde na CI portátil.

## Checklist de encerramento do agente de destino

- [ ] método atualizado para a versão com esta correção e `doctor` ok;
- [ ] `gate-test` validou os gates sem falso harness_error;
- [ ] `supervise` retomado em `wf_ralph_20260805_001` (phase-25);
- [ ] phase-25 fechou sem re-execução do bloco (`attempt.started` estável);
- [ ] nenhum segredo/prompt completo entrou em docs, trace ou relatório.
