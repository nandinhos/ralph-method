# HND-2026-0005 — Handoff de ativação do Ralph Method no projeto-alvo (OpenCode)

- Documento: HND-2026-0005
- Origem: repositório `ralph-method` (main `e2d1cf5`, versão publicada `0.9.0`)
- Destino: projeto-alvo `teste-events-opencode` (branch `fix/papeis-admin-financial`, HEAD `ae47b5a`)
- Harness de destino: OpenCode
- Estado: pronto para ativação
- Política de conhecimento: non_blocking

## Contexto

O Ralph Method `0.9.0` está publicado e o self-hosting foi certificado em
clone dedicado com o engine OpenCode: pipeline completo (claim/lease/fencing,
implementação via adapter, gates 1–3, revisão read-only independente,
systematic debugging e retry) exercitado no próprio repositório. Este handoff
ativa o Ralph Method no projeto-alvo `teste-events-opencode`, que usa OpenCode
como harness, e coloca em prática o processo evolutivo do Ralph (features
ordenadas, uma por bloco, com gates no controlador).

## Pré-condições verificadas

- Projeto-alvo é um checkout Git limpo (branch `fix/papeis-admin-financial`, HEAD `ae47b5a`);
- OpenCode presente e funcional; `opencode models` demora ~11s, mas o
  `ralph-init 0.9.0` usa timeout de 30s para o health deste provider
  (OpenCode aparece como `functional`/`adapter_enabled=true`);
- `.ralph/opencode.env` do instalador aponta para `scripts/ralph.sh` e exige
  modelo, agente e prova read-only antes do verify;
- o repositório `ralph-method` é a fonte do método; não é dependência de
  runtime do projeto-alvo.

## Passos de ativação (pelo agente do projeto-alvo)

### 1. Preparar o contexto

```bash
git -C "$PROJECT_ROOT" status --short --branch
```

Leia `AGENTS.md`, `CLAUDE.md`, `docs/STATUS.md` e o
`docs/AGENT_GUIDE.md` do repositório `ralph-method` antes de agir.

### 2. Dry-run (somente leitura)

```bash
METHOD_ROOT=/caminho/para/ralph-method
PROJECT_ROOT=/caminho/para/teste-events-opencode

"$METHOD_ROOT/bin/ralph-init" plan \
  --project "$PROJECT_ROOT" \
  --provider opencode \
  --verify-providers
```

Confirme no JSON:
- `opencode.auth_status=authenticated`, `health_status=healthy`,
  `status=functional`, `adapter_enabled=true`;
- `ralph_installation.external.status=not_found` e `apply_allowed=true`;
- `orchestration.mode=single_provider` (ou `needs_review` se o runner faltar).

### 3. Aplicar a instalação

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" apply \
  --project "$PROJECT_ROOT" \
  --provider opencode \
  --verify-providers

"$PROJECT_ROOT/bin/ralph-doctor" --project "$PROJECT_ROOT"
```

Confirme `status=healthy` e a presença de `.ralph/opencode.env`,
`.ralph/install-manifest.json` e `bin/ralph-*`.

### 4. Configurar o OpenCode no projeto-alvo

Preencha `.ralph/opencode.env`:

```bash
RALPH_OPENCODE_MODEL=<modelo explícito, ex: opencode/deepseek-v4-flash-free>
RALPH_OPENCODE_AGENT=ralph-review
RALPH_OPENCODE_VERIFY_AGENT=ralph-review
```

Gere a prova read-only FORA da raiz mutável:

```bash
"$PROJECT_ROOT/scripts/opencode-readonly-proof.sh" \
  --repo-root "$PROJECT_ROOT" \
  --agent ralph-review \
  --model "$RALPH_OPENCODE_MODEL" \
  --proof-file /tmp/ralph-readonly-policy-proof.json
```

Aponte `RALPH_OPENCODE_VERIFY_POLICY_PROOF=/tmp/ralph-readonly-policy-proof.json`
no perfil. A ausência da prova ou do agente bloqueia a revisão.

### 5. Preparar a fila (workflow + features)

Crie (ou use) um manifesto versionado com `workflow_id`, `plan_file`,
`test_command` (o comando de qualidade real do projeto, ex: `bin/check`,
`composer test` ou `vendor/bin/sail test`) e features ordenadas por
`position`, uma feature por bloco lógico. Inicialize o controlador:

```bash
cd "$PROJECT_ROOT"
bin/ralph-control init \
  --workflow <wf_id> \
  --manifest workflow.json
```

### 6. Executar em modo supervisionado (OpenCode)

Exporte as variáveis do OpenCode no processo que lança o supervisor (o
controlador as remove do executor, mas o preflight do adapter as lê):

```bash
cd "$PROJECT_ROOT"
RALPH_OPENCODE_MODEL=<modelo> \
RALPH_OPENCODE_AGENT=ralph-review \
RALPH_OPENCODE_VERIFY_AGENT=ralph-review \
RALPH_OPENCODE_VERIFY_POLICY_PROOF=/tmp/ralph-readonly-policy-proof.json \
  bin/ralph-control supervise \
    --workflow <wf_id> \
    --engine opencode \
    --test-cmd "<comando de qualidade real>" \
    --interval 30 \
    --max-retries 3
```

Acompanhe em outro terminal:

```bash
bin/ralph-monitor --workflow <wf_id> --interval 30
bin/ralph-control status --workflow <wf_id>
```

O supervisor seleciona a feature autorizada, adquire lease, executa um bloco,
roda os cinco gates (validation, quality, runtime_evidence, technical_review,
curation) e só avança com gates comprovados. Não escolha a próxima feature por
conta própria; o `ralph-control` decide.

## Regras obrigatórias do processo Ralph evolutivo

- Uma feature por bloco e um commit por fase aprovada;
- o `ralph-control` é a única autoridade de estado, ledger e avanço;
- nenhum gate é aprovado por texto, screenshot ou promessa — somente pela
  projeção do controlador;
- não edite ledger, plano aprovado ou lease;
- não troque provider silenciosamente; `fallback_policy=none` permanece;
- feedback do loop é observabilidade; decisões usam `ralph-control status`;
- não exponha tokens, prompts, respostas completas, leases ou proofs.

## Erros conhecidos e tratamentos (0.9.0)

| Sintoma | Causa | Tratamento |
|---|---|---|
| OpenCode `degraded`/`adapter_enabled=false` no plan | health `opencode models` lento | usar `ralph-init 0.9.0` (timeout 30s); confirmar `auth list` e `models` |
| `preflight do adapter opencode falhou` no supervise | `RALPH_OPENCODE_*` ausente no ambiente do supervisor | exportar modelo/agente/proof no processo que lança o `supervise` |
| Codex em rate limit `You have hit your usage limit` | limite da conta | o `ralph.sh 0.9.0` reconhece e espera o reset (não queima ciclo) |
| verify reprovado com tasks INCOMPLETE | implementação não completa | rodar systematic debugging (`ralph-control debug`), depois `continue`/`supervise` |

## Evidência

- Método publicado: `ralph-method` main `e2d1cf5`, tag `v0.9.0`;
- certificação do self-hosting: `docs/_meta/capture.log` (2026-08-15) e
  workflow `wf_provider_failover_20260813_001` em clone dedicado;
- guia operacional completo: `docs/AGENT_GUIDE.md` (guide_version 1.7.0,
  method_version 0.9.0).

## Checklist de encerramento do agente de destino

- [ ] li AGENTS.md, CLAUDE.md e o AGENT_GUIDE do método;
- [ ] `ralph-init plan --provider opencode --verify-providers` mostrou
      `adapter_enabled=true`;
- [ ] apply terminou com `doctor` healthy;
- [ ] `.ralph/opencode.env` tem modelo, agente e proof apontada;
- [ ] workflow inicializado com features ordenadas;
- [ ] `supervise` executou pelo menos um bloco com gates no controlador;
- [ ] não iniciei a próxima feature diretamente;
- [ ] nenhum segredo/prompt completo entrou em docs, trace ou relatório.
