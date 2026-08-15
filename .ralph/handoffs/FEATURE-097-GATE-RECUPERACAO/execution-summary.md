# HND-2026-0009 — Resposta: FEATURE-097 implementada (recuperação de gate)

- Documento: HND-2026-0009
- Origem: `ralph-method` (implementação nativa)
- Destino: `refactor-radar` (projeto-alvo; INC-2026-0007)
- Estado: implementado e testado; aguardando ativação no projeto-alvo
- Política de conhecimento: non_blocking

## O que foi implementado (resposta ao HND-2026-0008)

1. **Classificação do comando de gate** — `ralph-control` agora distingue:
   - `gate.rejected`: evidência (stdout/stderr não vazios) mostra falha da
     feature → `debugging_required` (corrige a feature);
   - `gate.harness_error`: comando sem evidência (stdout e stderr vazios) ou
     timeout → a feature permanece `awaiting_gates` e o gate é re-rodado.
2. **Retry de gate sem re-execução do bloco** — um `gate_harness_error` não
   re-executa o bloco já commitado; o comando é re-rodado até
   `--gate-harness-retries` (default 2) e só então `recovery_required` com
   `reason=gate_harness_error_limit`. O systematic debugging de erro de
   harness mira o comando, não a feature.
3. **Evidência mínima obrigatória** — comando de gate com `exit 0` e stdout
   vazio é tratado como defeito de harness.
4. **Self-test** — `ralph-control gate-test --gate <gate>` valida o comando
   configurado em modo fixture (contexto por env, evidência, exit code) sem
   tocar no workflow/ledger.

## Próximo passo no refactor-radar

Atualizar o método para a branch/versão que contém a FEATURE-097 (após o
merge) e re-rodar o `supervise`. A feature que parou no `technical_review`
(INC-2026-0007) será retomada sem re-execução do bloco: se o comando de
revisão falhar sem evidência, será classificado como `gate_harness_error` e
re-rodado; se o comando estiver corrigido, o gate passa.

Recomendado antes do `supervise`: validar o comando de review com
`bin/ralph-control gate-test --gate technical_review` (teria pego os defeitos
do script em segundos, não em horas).

## Evidência

- Implementação: `bin/ralph-control` (classificação, retry, `gate-test`),
  `docs/AGENT_GUIDE.md` (seção 6.2), `CHANGELOG.md`,
  `scripts/test-ralph-gate-recovery.sh`;
- origem do pedido: HND-2026-0008 e INC-2026-0007 (refactor-radar);
- regressão verde na CI portátil.
