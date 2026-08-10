# Handoff — Melhorias no detector de instalação (`bin/ralph-init` · detecção externa)

- **Data**: 2026-08-10
- **Framework**: Ralph Method `0.8.0` (tag `v0.8.0`) — detecção externa + `evolve`/`rollback` recém-adicionados
- **Projeto-alvo investigado**: `teste-events-opencode` (branch `fix/papeis-admin-financial`, HEAD `ae47b5a`, árvore limpa)
- **Origem da investigação**: a essência do Ralph Method nasceu do ralph do **harness Beer and Code** (`bc-harness`), que já está instalado no ambiente. Verificamos se a dinâmica nova (backup → instalar novo → rollback) cobre o caso de **instalações Ralph antigas não desacopladas** — e encontramos limitações concretas.

---

## 1. Resumo executivo

O detector de instalação externa da 0.8.0 (contrato `schemas/ralph-installation-detection.schema.json`,
17 sinais canônicos com SHA-256) é **correto para o contrato que define**, mas **não enxerga a instalação
Ralph que deu origem ao método** quando ela vive fora dos paths canônicos. No projeto real:

```
ralph-init plan → ralph_installation.external.status = "not_found"
                  classification = "none" · apply_allowed = true · 35 arquivos create
```

…**apesar de o projeto versionar uma instalação Ralph legada completa** em `harness/ralph/`
(28/07/2026: `ralph.sh` 45.709 B com patch, `ralph.sh.upstream` 43.187 B, `ralph.patch`, `install.sh`, `README.md`).

Consequência: `apply` prossegue, cria o `scripts/ralph.sh` novo **ao lado** do legado, sem
oferecer backup da instalação antiga, sem evolução assistida e sem rollback — o mecanismo
`evolve`/`rollback` da 0.8.0 **nunca dispara** nesse cenário porque a detecção é por paths
fixos relativos à raiz e não por conteúdo/assinatura.

---

## 2. Como o detector funciona hoje (0.8.0, verificado em campo)

### 2.1 Sinais varridos — 17 definições, todas **is_file** em paths fixos relativos à raiz

| id | path | kind |
|---|---|---|
| `root_ralph_script` | `ralph.sh` | canonical_script |
| `hidden_ralph_script` | `.ralph/ralph.sh` | canonical_script |
| `ralphfile` | `Ralphfile` | canonical_manifest |
| `root_ralph_yaml` | `ralph.yml` | configuration |
| `root_ralph_yaml_long` | `ralph.yaml` | configuration |
| `root_ralph_json` | `ralph.json` | configuration |
| `root_ralph_toml` | `ralph.toml` | configuration |
| `hidden_ralph_yaml` | `.ralph.yml` | configuration |
| `hidden_ralph_yaml_long` | `.ralph.yaml` | configuration |
| `hidden_ralph_json` | `.ralph.json` | configuration |
| `hidden_ralph_toml` | `.ralph.toml` | configuration |
| `ralph_control_binary` | `bin/ralph-control` | canonical_binary |
| `ralph_block_binary` | `bin/ralph-block` | canonical_binary |
| `ralph_loop_script` | `scripts/ralph.sh` | canonical_script |
| `ralph_install_manifest` | `.ralph/install-manifest.json` | installation_manifest |
| `ralph_ledger_events` | `.git/ralph-control/events.jsonl` | runtime_ledger |
| `ralph_workflow_state` | `.git/ralph-control/workflow.json` | runtime_state |

Sinais fortes (7): `root_ralph_script`, `hidden_ralph_script`, `ralphfile`,
`ralph_control_binary`, `ralph_block_binary`, `ralph_loop_script`, `ralph_install_manifest`.

### 2.2 Classificação

- **nenhum sinal** → `not_found` / `none` / `proceed` / `apply_allowed=true`
- **≥1 sinal forte OU ≥2 sinais** → `detected` / `external_ralph` / `high` / `review_before_apply`
- **1 sinal fraco** → `ambiguous` / `unknown_ralph_like` / `medium` / `review_before_apply`
- `migration_supported` é **`const: false`** no schema (evolução é `quarantine_only`: nada de
  ledger/prompt/workflow/credencial é importado; aceite explícito; rollback condicional).

### 2.3 Fluxo de bloqueio/evolução

- `apply` bloqueia quando detectado/ambiguo, exceto se `externalSignalsApproved()` aprovar
  (função aceita `$allowedExternalPaths` — **porém o usage da CLI não expõe a flag**, ver L3).
- `evolve --plan/--apply` cria estado numerado `EVL-YYYYMMDD-NNNN` com backup e hashes;
  `rollback --evolution EVL-... --apply` bloqueia com drift/backup ausente/destino ocupado.

---

## 3. Inventário do ecossistema Ralph no ambiente (mapeado 2026-08-10)

| # | Path | Linhagem / papel | Detectado hoje? |
|---|---|---|---|
| 1 | **`harness/ralph/`** (dentro do projeto, versionado) | Instalação legada bc-harness: `install.sh` + `ralph.patch` + `ralph.sh` (patched) + `ralph.sh.upstream` + `README.md` | ❌ `not_found` |
| 2 | `~/.claude-profiles/bc/plugins/marketplaces/beer-and-code/scripts/ralph.sh` (1.230 linhas) | **Fonte da essência** — ralph do marketplace Beer and Code | ❌ fora do projeto |
| 3 | `~/projects/opencode-profiles/bc-harness/scripts/ralph.sh` (1.171 linhas) + `ralph-opencode.sh` + `model-matrix.json` | Harness bc-harness edição OpenCode | ❌ fora do projeto |
| 4 | `~/.local/bin/ralph` (wrapper shell) | Delega para #2; engine default `codex` | ❌ fora do projeto |
| 5 | `~/projects/ralph-bc` (`backups/`, `current/`, `releases/`, CLI própria) | Cofre de versões do ralph | ❌ fora do projeto |
| 6 | `~/projects/ralph-method` (clone local, `0.8.0`) | O próprio framework (não é instalação no projeto-alvo) | N/A |
| 7 | `~/.config/opencode/{commands/plan.md, agent/ralph-build.md, ralph-verify.md, …}` | Manifestos do **harness ativo** (headers `Generated by bc-harness install.sh 2026-08-06`) | ❌ (não é instalação de ralph, é contexto de harness) |

---

## 4. Limitações identificadas

- **L1 — Escopo só raiz e paths fixos**: nenhum glob, nenhuma varredura de diretórios não
  canônicos; `is_file` em 17 paths literais.
- **L2 — O caso real é invisível**: `harness/ralph/` (padrão antigo bc/harness) não gera
  sinal nenhum → `apply_allowed=true` → instalação nova criada **ao lado** do legado, sem
  backup/evolução/rollback. O `evolve`/`rollback` da 0.8.0 não tem como disparar.
- **L3 — `allowedExternalPaths` sem CLI**: `externalSignalsApproved()` e o parâmetro
  existem em `installMethod()`, mas o `usage` (linha 77) não expõe nenhuma flag
  (`--allow-external-path`/`--scan-*`) — o mecanismo de aprovação manual não é acessível.
- **L4 — Sem assinatura de conteúdo**: todas as linhagens compartilham o header dos
  invariantes (`# ralph.sh` + “Orquestrador que le um documento de fases…” + os 5
  invariantes). Um arquivo com esse DNA em path não canônico não é sinal.
- **L5 — Sem fingerprint de linhagem**: não há proveniência (beer-and-code vs bc-harness
  vs method vs fork); só “arquivo existe no path X com hash Y”.
- **L6 — Classificação binária frágil**: 1 sinal fraco = `ambiguous`; mas **N** arquivos
  ralph-like fora da lista canônica = **0** sinais.
- **L7 — Sem contexto global informativo**: wrapper em PATH, profiles, vault, manifestos
  de harness ativo não entram no plano nem como bloco informativo.
- **L8 — Fingerprint do padrão legado não reconhecido**: o padrão de instalação antigo é
  identificável (par `install.sh` + `ralph.patch` + `ralph.sh.upstream`, como em
  `harness/ralph/`) e não é detectado.
- **L9 — `migration_supported` fixo em `false`**: corretamente conservador hoje, mas sem
  trilha para liberar migração quando a linhagem for conhecida (ex.: essência beer-and-code).

---

## 5. Melhorias propostas (priorizadas)

| # | Prioridade | Proposta |
|---|---|---|
| **M1** | Alta | **Sinal por assinatura de conteúdo**: glob `**/ralph*.sh` + match do header dos invariantes (fragmento comum às linhagens) → novo sinal `ralph_like_script` com `confidence=medium`, ação `review_before_apply`. Resolve L2/L4/L6. |
| **M2** | Alta | **Reconhecer diretórios de instalação legada**: fingerprint do padrão bc (`install.sh` + `ralph.patch` + `ralph.sh.upstream` num mesmo diretório, ex. `harness/ralph/`) → classificação `external_ralph_legacy`; `evolve` deve fazer **backup do diretório inteiro** (não só do arquivo único). Resolve L8. |
| **M3** | Alta | **Expor aprovação na CLI**: flag `--allow-external-path <path>` (ligada ao `$allowedExternalPaths` já existente) e/ou `--scan-global` informativo. Resolve L3. |
| **M4** | Média | **Proveniência de linhagem**: catalogar fragmentos por linhagem (beer-and-code 1.230 ln, bc-harness 1.171 ln, method 1.702 ln — headers diferem) → campo `family` no sinal; prepara trilha para `migration_supported=true` quando a família for conhecida. Resolve L5/L9. |
| **M5** | Média | **Bloco `environment_context`** (informativo, não bloqueante, sem conteúdo): wrapper PATH, profiles, vault `ralph-bc`, manifestos bc-harness ativos. Resolve L7. |
| **M6** | Baixa | **`legacy_candidates` no plano**: sempre listar arquivos ralph-like fora da lista canônica mesmo com `status=not_found` — auditoria humana sem surpresa. Resolve a assimetria de L1. |
| **M7** | Baixa | **Fixture de regressão**: adicionar ao `scripts/test-reproducibility.sh` (e ao report 0018/0019) um caso com o padrão `harness/ralph/` copiado, esperando `detected` (após M1/M2) ou `not_found`+`legacy_candidates` (antes). |

---

## 6. Referências no código (0.8.0, `bin/ralph-init`)

- `detectExistingRalphInstallation()` — ~linha 583 (manifesto, 17 definições, classificação)
- `$definitions` — ~linhas 600–617 · sinais fortes — ~linha 638 · classificação — ~644–675
- `externalSignalsApproved()` — ~linha 950 · `installMethod()` (bloqueio) — ~linha 978
- `evolveApply()` — ~linha 1327 · `rollbackPlan()` — ~linha 1500 · `rollbackApply()` — ~linha 1579
- Contratos: `schemas/ralph-installation-detection.schema.json`, `schemas/ralph-evolution.schema.json`
- README: seção “Instalação por projeto” (evolve/rollback); ADR `0001` (extração do núcleo),
  `0007` (escopo fechado de harnesses); reports `0018` (detecção ralph externo v0-7-0),
  `0019` (evolução opencode v0-8-0).

---

## 7. Próximos passos sugeridos

1. Decidir M1+M2 (essenciais para o caso real: instalação legada não desacoplada).
2. Escrever a fixture do padrão `harness/ralph/` no test-reproducibility antes do código
   (regressão TDD).
3. Implementar em `0.9.0` com report numerado + sync obrigatório de `AGENT_GUIDE.md`
   (`method_version`, `STATUS.md`, schema `ralph-installation-detection` v1.1 se os campos
   novos forem adicionados — atenção ao `additionalProperties: false` do schema).