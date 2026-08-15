# HND-2026-0010 — Ativação da FEATURE-097 no refactor-radar (retomada do supervise)

- Documento: HND-2026-0010
- Origem: `ralph-method` (implementação nativa; main `5d4b580`)
- Destino: `refactor-radar` (projeto-alvo; método 0.9.0, phase-25)
- Harness de destino: OpenCode
- Estado: pronto para ativação
- Política de conhecimento: non_blocking

## Contexto

O `refactor-radar` está com o método **0.9.0** instalado e a `phase-25`
parada: o `technical_review` foi rejeitado (INC-2026-0007) por **defeito do
comando de gate**, e o retry antigo re-executava o bloco commitado. A
**FEATURE-097** (em `main`, candidata à v0.9.2) corrige isso: o controlador
classifica `gate_harness_error` (defeito do comando) vs `gate_rejected`
(falha da feature), e o retry de gate não re-executa o bloco. Este handoff
ativa a FEATURE-097 no projeto e retoma o `supervise`.

## Estado atual verificado

- `refactor-radar`: branch `main` (28 commits à frente de origin), método
  `0.9.0`, workflow `wf_ralph_20260805_001`, feature `phase-25`;
- último evento do ledger: `gate.rejected` + `debugging.required` para
  `technical_review` (a sessão de gates está retomada/`reclaimed`);
- o ralph-method `main` (`5d4b580`) contém a FEATURE-097; `VERSION=0.9.1` com
  a 097 candidata à 0.9.2.

## Passos de ativação (pelo agente do refactor-radar)

### 1. Atualizar o método para a versão com a FEATURE-097

```bash
METHOD_ROOT=/caminho/para/ralph-method   # checkout do ralph-method em main 5d4b580
PROJECT_ROOT=/caminho/para/refactor-radar

# Auditar antes (somente leitura)
"$METHOD_ROOT/bin/ralph-init" plan --project "$PROJECT_ROOT" --provider opencode --verify-providers

# Preservar customizações locais (drift) antes do update
cp bin/ralph-bloco /tmp/refactor-radar-ralph-bloco.custom
cp .ralph/opencode.env /tmp/refactor-radar-opencode.env.custom

# Aplicar o update (0.9.0 -> versão com FEATURE-097)
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" apply \
  --project "$PROJECT_ROOT" --provider opencode --verify-providers

# Reaplicar customizações locais se o instalador tiver sobrescrito
cp /tmp/refactor-radar-ralph-bloco.custom bin/ralph-bloco
cp /tmp/refactor-radar-opencode.env.custom .ralph/opencode.env

"$PROJECT_ROOT/bin/ralph-doctor" --project "$PROJECT_ROOT"
```

Confirme `method_version` atualizado e o OpenCode `functional`/`adapter_enabled=true`.

### 2. Validar o comando de gate antes do supervise (self-test da FEATURE-097)

```bash
cd "$PROJECT_ROOT"
bin/ralph-control gate-test --gate technical_review
bin/ralph-control gate-test --gate quality
bin/ralph-control gate-test --gate runtime_evidence
```

Cada saída deve reportar `classification: passed` (ou `gate_harness_error`
para um comando quebrado, o que sinaliza que o script precisa ser corrigido
**antes** de gastar uma sessão real).

### 3. Corrigir o comando de technical_review (se necessário)

Se `gate-test` apontar `gate_harness_error` ou `gate_rejected`, corrija o
script de revisão (ex.: `scripts/ralph-review-feature.sh`) e re-valide com
`gate-test` até `classification: passed`.

### 4. Retomar o supervise (com a FEATURE-097 ativa)

```bash
cd "$PROJECT_ROOT"
RALPH_OPENCODE_MODEL=<modelo> \
RALPH_OPENCODE_AGENT=ralph-review \
RALPH_OPENCODE_VERIFY_AGENT=ralph-review \
RALPH_OPENCODE_VERIFY_POLICY_PROOF=<caminho da proof> \
  bin/ralph-control supervise \
    --workflow wf_ralph_20260805_001 \
    --engine opencode \
    --test-cmd "bin/check" \
    --interval 30 \
    --max-retries 3
```

Comportamento esperado da FEATURE-097:
- se o comando de review falhar sem evidência (stdout/stderr vazios), o
  controlador registra `gate.harness_error`, **mantém a feature em
  awaiting_gates** e re-roda o comando até `--gate-harness-retries` (default
  2) — **sem re-executar o bloco**;
- com o comando corrigido, o `technical_review` passa e a fila avança.

### 5. Feedback esperado (retorno ao ralph-method)

Ao concluir (ou travar de novo), retorne ao agente do ralph-method:

1. versão do método após o update e resultado do `ralph-doctor`;
2. saída de `ralph-control gate-test` para cada gate;
3. se o `technical_review` passou e a phase-25 avançou;
4. número de `attempt.started` no ledger (esperado: sem re-execução do bloco
   por erro de harness);
5. qualquer finding novo (contrato, default, classificação).

## Regras obrigatórias

- `ralph-control` permanece a única autoridade de estado, ledger e avanço;
- nenhum gate é aprovado por texto ou screenshot; só a projeção do controlador;
- não editar ledger, plano aprovado ou lease; `fallback_policy=none` permanece;
- não expor tokens, prompts completos, leases ou proofs;
- preservar as customizações locais (`bin/ralph-bloco`, `.ralph/opencode.env`).

## Evidência

- FEATURE-097 implementada em `main` (`eb7facc`, CI verde `31903358428`);
- handoff de resposta anterior: HND-2026-0009;
- origem do pedido: INC-2026-0007 (refactor-radar, phase-25).

## Checklist de encerramento do agente de destino

- [ ] método atualizado para a versão com a FEATURE-097 e `doctor` ok;
- [ ] `gate-test` validou `quality`, `runtime_evidence` e `technical_review`;
- [ ] comando de review corrigido (se necessário) e `gate-test` passed;
- [ ] `supervise` retomado em `wf_ralph_20260805_001` (phase-25);
- [ ] `technical_review` aprovado sem re-execução do bloco (attempt.started
      não cresceu por erro de harness);
- [ ] feedback do passo 5 enviado ao agente do ralph-method;
- [ ] nenhum segredo/prompt completo entrou em docs, trace ou relatório.
