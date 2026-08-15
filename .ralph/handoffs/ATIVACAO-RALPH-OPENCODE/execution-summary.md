# HND-2026-0005 — Handoff de ativação do Ralph Method 0.9.0 via OpenCode no `refactor-radar`

- Documento: HND-2026-0005
- Origem: repositório `ralph-method` (main `7c79e0a`, versão publicada `0.9.0`)
- Destino: projeto-alvo `refactor-radar` (branch `main`, HEAD `4341421`, 20 commits à frente de origin)
- Harness de destino: OpenCode
- Estado: pronto para atualização e ativação
- Política de conhecimento: non_blocking

## Contexto

O `refactor-radar` é o projeto-alvo original do Ralph Method. Ele já possui
uma instalação do método **0.8.0** (`.ralph/install-manifest.json`), mas a
versão publicada atual é **0.9.0**. O OpenCode é o harness de destino e o
`ralph-init 0.9.0` já o trata como elegível (timeout de 30s no health probe).

Este handoff ativa o "Ralph evolutivo": atualiza o método para 0.9.0
**preservando o drift local**, configura o OpenCode e inicia a fila de
features com uma feature por bloco e gates no controlador.

## Estado atual do projeto-alvo (verificado)

- Branch `main`, HEAD `4341421`, árvore com 20 commits à frente de `origin/main`;
- método instalado: `0.8.0`, orquestração `native_codex`, `fallback_policy=none`;
- providers no manifest: `codex=functional/adapter=true`, `opencode=degraded`,
  `claude=unauthenticated`, `hermes=functional/adapter=false`, `agy=unsupported`;
- `ralph-doctor` reporta `drift_detected`:
  - `bin/ralph-bloco` — **modificado localmente** (hash local `c70321ea9cbe`,
    instalado `6bf163af44ff`, método `e27cf6036a37`);
  - `.ralph/opencode.env` — **modificado localmente** (modelo
    `opencode-go/gpt-5.6-luna` e proof `/tmp/ralph-readonly-policy-proof.json` já
    apontados);
- comando de qualidade real: `bin/check`.

## Objetivo

1. Atualizar o método para 0.9.0 preservando as customizações locais.
2. Tornar o OpenCode elegível (`functional`/`adapter_enabled=true`).
3. Inicializar o workflow com features ordenadas e executar em modo
   supervisionado com `--engine opencode`.

## Passos de ativação (pelo agente do projeto-alvo)

### 1. Auditar antes de tocar em qualquer arquivo

```bash
git -C "$PROJECT_ROOT" status --short --branch
"$METHOD_ROOT/bin/ralph-init" plan --project "$PROJECT_ROOT" --provider opencode --verify-providers
```

Confira no JSON:
- `ralph_installation.method.managed=true` (instalação existente);
- `ralph_installation.external.status=not_found` e `apply_allowed=true`;
- `opencode.auth_status=authenticated`, `health_status=healthy`,
  `status=functional`, `adapter_enabled=true`;
- arquivos com `action=update` vs `conflict`. **Conflito = parar e decidir com
  o usuário; nunca sobrescrever o drift local silenciosamente.**

### 2. Preservar o drift local antes da atualização

As duas alterações locais são intencionais e devem sobreviver ao update:

```bash
cp bin/ralph-bloco /tmp/refactor-radar-ralph-bloco.custom
cp .ralph/opencode.env /tmp/refactor-radar-opencode.env.custom
```

Documente no handoff do projeto o propósito de cada alteração local (ex: o
`ralph-bloco` customizado pode conter ajustes de parada/engine deste repo).

### 3. Aplicar a atualização para 0.9.0

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" apply \
  --project "$PROJECT_ROOT" \
  --provider opencode \
  --verify-providers
```

> Se o `apply` recusar por `conflict` em `bin/ralph-bloco` ou
> `.ralph/opencode.env`, não force: restaure os arquivos locais e rode
> `plan` de novo para confirmar que a divergência agora é `update` e não
> `conflict`. O instalador atualiza por ownership e hash; a customização deve
> ser preservada ou reconciliada explicitamente.

Depois, reaplique as customizações locais se o instalador tiver sobrescrito:

```bash
cp /tmp/refactor-radar-ralph-bloco.custom bin/ralph-bloco
cp /tmp/refactor-radar-opencode.env.custom .ralph/opencode.env
```

Rode o doctor e confirme o estado desejado:

```bash
"$PROJECT_ROOT/bin/ralph-doctor" --project "$PROJECT_ROOT"
```

Resultado aceitável: `method_version=0.9.0`; `drift` pode permanecer somente
para os arquivos customizados (bloco e opencode.env), o que é o estado
intencional deste projeto.

### 4. Configurar o OpenCode

Confirme `.ralph/opencode.env` com:

```bash
RALPH_OPENCODE_MODEL=opencode-go/gpt-5.6-luna
RALPH_OPENCODE_AGENT=ralph-review
RALPH_OPENCODE_VERIFY_AGENT=ralph-review
RALPH_OPENCODE_VERIFY_POLICY_PROOF=/tmp/ralph-readonly-policy-proof.json
```

Valide a proof read-only (gerar somente se ausente; sempre FORA da raiz mutável):

```bash
"$PROJECT_ROOT/scripts/opencode-readonly-proof.sh" \
  --repo-root "$PROJECT_ROOT" \
  --agent ralph-review \
  --model "$RALPH_OPENCODE_MODEL" \
  --proof-file /tmp/ralph-readonly-policy-proof.json
```

### 5. Preparar a fila (workflow + features)

Use (ou crie) um manifesto versionado com `workflow_id`, `plan_file`,
`test_command=bin/check` e features ordenadas por `position` — uma feature por
bloco lógico. Inicialize:

```bash
cd "$PROJECT_ROOT"
bin/ralph-control init --workflow <wf_id> --manifest workflow.json
```

### 6. Executar em modo supervisionado (OpenCode)

Exporte as variáveis do OpenCode no processo que lança o supervisor (o
controlador as remove do executor, mas o preflight do adapter as lê):

```bash
cd "$PROJECT_ROOT"
RALPH_OPENCODE_MODEL=opencode-go/gpt-5.6-luna \
RALPH_OPENCODE_AGENT=ralph-review \
RALPH_OPENCODE_VERIFY_AGENT=ralph-review \
RALPH_OPENCODE_VERIFY_POLICY_PROOF=/tmp/ralph-readonly-policy-proof.json \
  bin/ralph-control supervise \
    --workflow <wf_id> \
    --engine opencode \
    --test-cmd "bin/check" \
    --interval 30 \
    --max-retries 3
```

Acompanhe:

```bash
bin/ralph-monitor --workflow <wf_id> --interval 30
bin/ralph-control status --workflow <wf_id>
```

O supervisor seleciona a feature autorizada, adquire lease, executa um bloco,
roda os cinco gates (validation, quality, runtime_evidence, technical_review,
curation) e só avança com gates comprovados.

## Regras obrigatórias do processo Ralph evolutivo

- Uma feature por bloco e um commit por fase aprovada;
- `ralph-control` é a única autoridade de estado, ledger e avanço;
- nenhum gate é aprovado por texto, screenshot ou promessa;
- não edite ledger, plano aprovado ou lease;
- não troque provider silenciosamente; `fallback_policy=none` permanece;
- feedback do loop é observabilidade; decisões usam `ralph-control status`;
- não exponha tokens, prompts, respostas completas, leases ou proofs.

## Erros conhecidos e tratamentos (0.9.0)

| Sintoma | Causa | Tratamento |
|---|---|---|
| `opencode: degraded` no plan | instalação ainda 0.8.0 (timeout 8s) | aplicar o 0.9.0 (timeout 30s) e re-rodar `plan --verify-providers` |
| `preflight do adapter opencode falhou` no supervise | `RALPH_OPENCODE_*` ausente no ambiente do supervisor | exportar modelo/agente/proof no processo que lança o `supervise` |
| `apply` recusado por `conflict` em bloco/opencode.env | drift local vs fonte | não forçar; reconciliar explicitamente preservando a customização |
| Codex em rate limit `You have hit your usage limit` | limite da conta | o `ralph.sh 0.9.0` reconhece e espera o reset (não queima ciclo) |
| verify reprovado com tasks INCOMPLETE | implementação não completa | systematic debugging (`ralph-control debug`), depois `continue`/`supervise` |

## Evidência

- Método publicado: `ralph-method` main `7c79e0a`, tag `v0.9.0`;
- guia operacional: `docs/AGENT_GUIDE.md` (method_version 0.9.0);
- certificação do self-hosting com OpenCode: `docs/_meta/capture.log`
  (2026-08-15) e workflow `wf_provider_failover_20260813_001` em clone dedicado;
- handoffs anteriores do `refactor-radar` em `.ralph/handoffs/` (phase-20/21/22).

## Checklist de encerramento do agente de destino

- [ ] li AGENTS.md, CLAUDE.md e o AGENT_GUIDE do método;
- [ ] `ralph-init plan --provider opencode --verify-providers` mostrou
      `adapter_enabled=true` (método 0.9.0);
- [ ] customizações locais (`bin/ralph-bloco`, `.ralph/opencode.env`) preservadas;
- [ ] `ralph-doctor` com `method_version=0.9.0`;
- [ ] `.ralph/opencode.env` com modelo, agente e proof apontada;
- [ ] workflow inicializado com features ordenadas;
- [ ] `supervise` executou pelo menos um bloco com gates no controlador;
- [ ] não iniciei a próxima feature diretamente;
- [ ] nenhum segredo/prompt completo entrou em docs, trace ou relatório.
