# Relatório 0030 — promoção da v0.10.0

**Versão:** `0.10.0`
**Commit promovido:** `HEAD` da `main`
**Branch de destino:** `main`
**Tag:** `v0.10.0` anotada
**Data:** 2026-08-16
**Status:** publicada em `origin/main`

## Resultado

A `v0.10.0` publica duas entregas sobre a base `0.9.2`: a **FEATURE-094**
(failover controlado Codex → OpenCode) e a **FEATURE-098** (adapter Cursor,
quinto runner executável: Codex, Claude, OpenCode, agy, Cursor). A tag
anotada `v0.10.0` aponta para o commit promovido, publicada em `origin/main`.

## Pré-condições verificadas

| Verificação | Resultado |
|---|---|
| Árvore local antes da promoção | limpa |
| `bash scripts/check-shell.sh` | exit `0` |
| `bash scripts/check-doc-sync.sh` | exit `0` (VERSION `0.10.0`) |
| `bash scripts/ci-portable.sh` | exit `0` (24 testes; inclui `test-cursor-adapter.sh` e `test-provider-failover.sh`) |
| CI remota (GitHub Actions) | exit `0` nos commits da release (`da695e3` → `d673f39` → `f899d03`) |
| Regressão de campo FEATURE-094 | `refactor-radar`, 5/5 gates (Phase 9) |
| Revisão adversarial FEATURE-094 | sem finding crítico/alto |
| Revisão adversarial FEATURE-098 | 10/10 claims; 3 findings de baixa severidade corrigidos |
| Prova de campo FEATURE-098 | pendente (opt-in, rito do `agy`) |

## FEATURE-094 — failover controlado entre providers

Continuação Codex → OpenCode quando o Codex confirma `provider_usage_limited`
de alta confiança e o workflow opta pela política `explicit_failover`. Default
permanece `fallback_policy=none`. Inclui contratos v2 (`runner-result 2.0.0` e
`execution-policy`), circuitos `closed|open|half_open` derivados do ledger,
cápsula de continuidade com fingerprint, eventos do ledger `1.2.0`
(`provider.capacity_limited`, `continuation.generated`,
`provider.failover_started`), espera de capacidade reapropriável,
observabilidade (`provider-status`, `failover-plan`, `provider_circuits`,
métricas) e a matriz adversarial (SIGKILL, duplicação, truncamento). A prova
de campo no `refactor-radar` fechou os 5 gates; a revisão adversarial
independente não encontrou finding crítico/alto.

Dois fixes de robustez entraram nesta release:

- **supervisor aguarda o runner anterior antes do failover** em vez de
  abandonar quando o processo ainda é observável logo após `block.finished`
  (corrida que quebrava a CI remota de forma intermitente);
- **fake opencode determinístico no readiness** do teste de failover: o
  `supervisorHandleFailover` roda `ralph-init plan --verify-providers`, que
  dependia de um opencode real no PATH (presente no host do dev, ausente na
  CI), tornando o teste intermitente. Agora um fake opencode (`auth list` +
  `models`) é injetado no PATH dos supervises da fixture; o teste passa sem
  opencode real, inclusive nas fases 4 e 8.4.

## FEATURE-098 — adapter Cursor (quinto runner)

Adapter executável para a CLI headless `agent`/`cursor-agent` (instalada à
parte da IDE; no Windows roda no PowerShell, o runner do método continua
bash), com contrato `runner-result 1.2.0`, terminal `result` e verify v1
**declarado** (`--mode ask`, `permission_policy_status=declared`, hash `null`,
agente `ask` — `verified` é proibido nesta v1). O Cursor é uma IDE com LLM
embutido, sem API key: autenticação pela sessão local da conta. Entregue:

- schema `1.2.0` com `declared` no enum; v1/v1.1/v2 preservados;
- `ralph-control`: contrato, terminal, verify declarado e fluxo normativo;
- `ralph-init`: detecção de `agent`/`cursor-agent` (sessão local), perfil
  `.ralph/cursor.env` e `RALPH_CURSOR_MODEL` obrigatório;
- `ralph.sh --engine cursor`: seam de adapters, preflight, fingerprint;
- `adapters/cursor/`: `runner.sh` (seam `preflight|run|version`, `stream-json`,
  limites 256 KiB/5 MiB/10k/30 min, `RALPH_CURSOR_CLI` como caminho ou
  comando) e `parser.php` fail-closed (JSONL inválido, zero eventos, múltiplos
  `result`, escrita em verify, modelo divergente) com sanitização;
- fixture offline `test-cursor-adapter.sh` na CI portátil.

A revisão adversarial independente sustentou as 10 claims com evidência
executável e encontrou 3 findings de baixa severidade, todos corrigidos nesta
release: schema `failure_domain_status` aceita `null` (consistente com o
validador PHP), parser sem código morto (zero eventos é detectado antes de
sem terminal) e usage do `ralph-init` lista `cursor`.

A prova de campo opt-in (CLI headless real + sessão autenticada) permanece
pendente, no mesmo rito do `agy`: a prova real de inferência é uma política
futura, separada e opt-in, e não faz parte da CI sem credenciais.

## Revisão adversarial

- **FEATURE-094**: revisão independente (Phase 8, task 5) com 8 claims
  verificadas por artefatos literais; veredito sem finding crítico/alto.
- **FEATURE-098**: revisão independente refute-first; 10/10 claims
  sustentadas; 3 findings de baixa severidade corrigidos e revalidados.

## Limitações e itens ainda não comprovados

- **campo opt-in do Cursor**: não executado com CLI headless real + sessão;
  permanece como política futura separada;
- verify v1 do Cursor é `declared`, não `verified`: não há isolamento mecânico
  nesta versão;
- `docs/design/` (artefato do usuário) permanece fora do commit.

## Próxima etapa

Configurar o harness do editor Cursor (`cursor-ralph-profile`) para consumir o
adapter oficial (`adapters/cursor/`, schema `1.2.0`, `RALPH_CURSOR_CLI`) e
rodar o campo opt-in; elevar o verify de `declared` para `verified` somente
quando o Cursor expuser prova mecânica de política read-only equivalente à do
OpenCode.
