# HND-2026-0011 — Feedback da ativação da FEATURE-097 no refactor-radar

- Documento: HND-2026-0011
- Origem: `refactor-radar` (projeto-alvo)
- Destino: `ralph-method` (implementação nativa)
- Harness: OpenCode
- Estado: feedback de ativação (resposta ao HND-2026-0010)
- Política de conhecimento: non_blocking

## 1. Versão aplicada e doctor

- Método atualizado de `0.9.0` para `0.9.1` (FEATURE-097, `ralph-init apply` com
  preservação do drift local: `bin/ralph-bloco` e `.ralph/opencode.env`).
- `ralph-doctor`: `status=drift_detected` (drift somente nos arquivos
  customizados — estado intencional), `method_version=0.9.1`,
  `provider=opencode`; `ralph-init plan --verify-providers`: opencode
  `functional`/`adapter_enabled=true`.

## 2. Saída de `ralph-control gate-test`

| Gate | Command resolvido | classification | Obs. |
|---|---|---|---|
| `quality` | `scripts/ralph-run-quality.sh` → `bin/check` | `gate_harness_error` | exit 124 (timeout no default de 60s do gate-test; `bin/check` leva ~4–5 min; no supervise real o gate-timeout é 900s) |
| `runtime_evidence` | `php artisan about` | `passed` | evidência 574 bytes |
| `technical_review` | `scripts/ralph-review-feature.sh` (LLM) | `gate_harness_error` | exit 124 no gate-test com 60s e 300s (review LLM leva >300s e o script só emite evidência no fim); **no gate real (900s) passou** |
| `curation` | default nativo | `gate_rejected` | **bug do default**: `ralph-knowledge --workflow ... --feature ...` sem ação obrigatória → exit 2 |
| `curation` (workaround) | `scripts/ralph-curate-gate.sh` | `passed` | evidência 356 bytes |

## 3. Avanço da phase-25

- `technical_review`: **APROVADO** (veredito da última linha estruturada) — 4ª
  tentativa de gate; o parser de substring falhava com prosa mista.
- `curation`: default nativo quebrado (ver item 2); workaround
  `scripts/ralph-curate-gate.sh` (política non_blocking, curadoria só pós-release)
  validado no gate-test.
- A feature **ainda não avançou para released**: o retry pós-debugging
  re-executa o bloco inteiro a cada tentativa (7 `attempt.started`), e no
  attempt 7 o bloco retornou `exit 1` apesar da saída do ralph.sh indicar
  sucesso ("Gate 2 suite verde", "JA IMPLEMENTADA", `phase_already_done`) →
  `debugging_required` sem rodar os gates.

## 4. Contagem

- `attempt.started` para `phase-25`: **7** — 7 re-execuções completas do bloco
  (implementação opencode + bin/check) para uma feature cujo commit
  (`3729c4e`) nunca mudou. Cada re-execução custa ~8–10 min + sessão de modelo.

## 5. Findings novos para o ralph-method

1. **`gate-test` com default de timeout 60s é curto demais** para `bin/check`
   (qualidade) e para gates LLM (`technical_review`): ambos dão
   `gate_harness_error` por timeout, mesmo estando corretos no supervise real
   (gate-timeout 900s). O `gate-test` deveria herdar/aceitar o gate-timeout
   configurado ou detectar a duração esperada.
2. **Default do gate curation quebrado (FEATURE-096/097)**: o comando canônico
   `ralph-knowledge --workflow ... --feature ...` não passa a ação obrigatória
   (`candidate|curated|rejected|review-required|skipped`). Além disso, a
   curadoria de conhecimento só é válida após `feature.released` — a semântica
   do gate curation pré-release com política `non_blocking` precisa ser
   definida (evidência + pass, sem inventar decisão).
3. **Retry de gate ainda re-executa o bloco commitado**: apesar da FEATURE-097
   classificar `gate_harness_error` vs `gate_rejected`, o caminho
   `debugging.verified → retry` inicia nova tentativa do bloco inteiro. Para um
   defeito de comando de gate, a correção vale só para o gate; a re-implementação
   é desperdício. Sugestão: se a feature está commitada e os gates anteriores
   passaram, a retomada deve re-rodar somente o gate pendente.
4. **Exit code do bloco inconsistente no caminho "já implementada"**: no attempt
   7, o ralph.sh reportou sucesso (`phase_already_done`) mas o controlador
   registrou `block.finished exit_code=1` → `debugging_required` espúrio. O
   exit code do caminho "nada a commitar / já implementada" precisa ser estável
   (0) sob `--no-verify` e no executor controlado.
5. **Gates LLM não emitem evidência durante a execução**: o comando de review
   só escreve o veredito no final; em timeout o gate-test vê 0 bytes de
   evidência, indistinguível de um script travado. Considerar streaming de
   progresso ou um contrato de "evidência mínima" para gates de longa duração.

6. **Executor controlado instável no caminho "já implementada" — BLOQUEIA o
   fechamento** (finding principal): após todos os 5 gates estarem corrigidos e
   aprovados, a phase-25 não fecha porque o bloco re-executado a cada tentativa
   falha no executor controlado: no attempt 7 `block.finished exit_code=1`
   apesar de o ralph.sh reportar sucesso ("Gate 2 suite verde", "JA
   IMPLEMENTADA", `phase_already_done`); no attempt 8 `recovery.required`
   ("processo terminou sem evento terminal"); o loop seguiu até 9+ attempts,
   re-executando o bloco commitado (~10–16 min por tentativa + sessão de
   modelo). O caminho `--no-verify` + "nada a commitar" precisa encerrar o
   processo controlado com exit 0 e evento terminal estável, e o retry pós-
   recuperação de um bloco já commitado deve re-rodar só os gates.

## Status final (após as correções)

- `technical_review`: **APROVADO** (veredito da última linha estruturada).
- `curation`: workaround `scripts/ralph-curate-gate.sh` validado no gate-test.
- `runtime_evidence`: **passed** (`php artisan about`).
- **phase-25 NÃO fechou**: o laço de retry do executor controlado (finding 6)
  re-executa o bloco commitado e falha com exit espúrio / perda de evento
  terminal. `attempt.started` chegou a **9+**.
- O supervise foi interrompido para parar o sangramento de re-execuções.

## Evidência

- `INC-2026-0007` (pane original), `DBG-2026-0008/0009/0010/0011` (debugs da
  fase 25), commits de correção no refactor-radar
  (`scripts/ralph-review-feature.sh`, `scripts/ralph-curate-gate.sh`,
  `scripts/ralph-debug-report.php`).
- `RPT-2026-0068/0069/0070` (rejeições do technical_review),
  `RPT-2026-0072` (curation default quebrado).

## Checklist

- [ ] método 0.9.1 aplicado e doctor ok;
- [ ] gate-test executado para quality/runtime_evidence/technical_review/curation;
- [ ] technical_review aprovado (última linha) e curation workaround validado;
- [ ] phase-25 ainda não released — retry re-executa bloco e attempt 7 teve exit
      espúrio;
- [ ] findings acima entregues ao ralph-method;
- [ ] nenhum segredo/prompt completo entrou em docs, trace ou relatório.
