# Status do Ralph Method

## Estado atual

A versão publicada atual é `0.9.2`. Ela publica a FEATURE-097 (recuperação
de gate distinta entre defeito do comando e falha da feature) sobre a base
`0.9.1`, identificada pela tag anotada `v0.9.2`. A correção foi confirmada em
campo pelo `refactor-radar` (INC-2026-0007): a phase-25 fechou com os 5 gates
e o workflow avançou para a phase-26 sem re-execução do bloco commitado. O
relatório da promoção está em
[`docs/reports/0027-promocao-v0-9-2.md`](reports/0027-promocao-v0-9-2.md).

### FEATURE-094 — failover controlado entre providers (em implementação)

A Phase 1 (contratos) está concluída sobre a base `0.9.2`, sem mudar o
comportamento operacional: o default continua `fallback_policy=none` e nenhum
evento `1.2.0` é emitido. Entregue:

- `schemas/runner-result.schema.json` aceita o contrato comum `2.0.0`
  (`codex`/`claude`/`opencode` com `profile`, `failure_domain` e
  `usage_limited` de confiança alta) com validação fail-closed; os contratos
  `1.0.0` (opencode) e `1.1.0` (agy) continuam lidos e campos exclusivos do
  v2 são rejeitados em resultados legados;
- novo `schemas/execution-policy.schema.json` para o opt-in `explicit_failover`
  com cadeia e limites obrigatórios;
- plano de promoção do ledger `1.2.0` em
  [`architecture/ledger-1.2.0-promotion-plan.md`](architecture/ledger-1.2.0-promotion-plan.md):
  o binário continua em `1.1.0`, lê `1.0.0`/`1.1.0` e rejeita `1.2.0`
  (fail-closed) até o leitor compatível ser promovido;
- base de `scripts/test-provider-failover.sh` com relógio injetável, CLIs
  fixture, validação jsonschema dos contratos, importação real de v2 pelo
  controlador e comprovação de que o ledger rejeita `1.2.0` sem leitor.
  `scripts/ci-portable.sh` inclui o novo teste;
- RFC `--fail-fast-on-limit` arquivado como supersedido pelo ADR-0016 em
  `docs/proposals/archived/`.

A Phase 2 (publicação do `runner-result` pelo Codex e classificação de rate
limit) está concluída sobre a base `0.9.2`, também sem mudar o comportamento
legado:

- `scripts/ralph.sh` classifica somente assinaturas terminais conhecidas como
  `provider_usage_limited` de confiança alta (fail-closed: `429` de saída de
  teste, erro genérico e arquivo ausente não classificam) e publica um
  `runner-result` v2 `usage_limited` correlacionado (workflow/feature/attempt/
  execution) com `retry_at`, fonte do classificador (`ralph_sh_classifier_v1`)
  e hash da evidência — nunca o texto bruto;
- com `RALPH_EXECUTION_POLICY_MODE=explicit_failover` (sinal do controlador
  quando a política estiver ativa), o loop devolve a decisão ao controlador
  sem dormir nem relançar o provider; workflows legados mantêm a espera
  interna (`wait_for_reset`), comprovado pelo `test-ralph.sh` (167 asserts);
- a sanitização é comprovada por fixture: segredo-canário emitido pelo provider
  não vaza para o resultado nem para o ledger.

As demais fases da FEATURE-094 (política/circuitos/roteamento, cápsula, espera
de capacidade, observabilidade, regressão e campo) permanecem planejadas em
[`.spec/features/094-provider-failover/PHASES.md`](../.spec/features/094-provider-failover/PHASES.md).

As Phases 3 e 4 (validação de política, circuitos e nova autoridade de
execução) estão concluídas sobre a base `0.9.2`, mantendo o default
`fallback_policy=none` para workflows sem opt-in:

- `ralph-control init` valida a `execution_policy` (fail-closed) e congela o
  hash canônico no workflow ativo; drift da política bloqueia nova attempt no
  `claim`;
- o readiness (`ralph-init plan --verify-providers`) expõe `failure_domain`
  opaco com `failure_domain_status=declared|unavailable` (rótulo do perfil);
  valor bruto e modelo/alias nunca são usados;
- circuitos `closed|open|half_open` são derivados **somente** do ledger e do
  relógio injetável (`RALPH_TEST_CLOCK_EPOCH`), sem sidecar autoritativo;
  `selectEligibleRunner` pula runner com circuito aberto e exige
  `adapter_enabled`;
- o ledger foi promovido para `RALPH_SCHEMA_VERSION=1.2.0` com os eventos
  `provider.capacity_limited`, `continuation.generated`,
  `provider.failover_started`, `provider.capacity_wait_started` e
  `provider.capacity_wait_finished`; binário lê `1.0.0`/`1.1.0` e rejeita
  `1.3.0` (fail-closed);
- `provider-status` e `failover-plan` são comandos somente leitura que
  explicam circuitos, cooldown, seleção e próxima ação sem iniciar provider
  nem mutar eventos;
- **failover real comprovado por fixture**: Codex emite `usage_limited`
  confirmado → `provider.capacity_limited` abre o circuito → o supervisor
  registra `provider.failover_started` (codex→opencode) com nova attempt,
  lease e fencing → o OpenCode inicia a continuação. O run com política ativa
  devolve `provider_failover_pending` ao supervisor (sem debugging indevido) e
  o loop não dorme nem relança o provider.

As Phases 5–7 também estão concluídas sobre a base `0.9.2`:

- a cápsula de continuidade é uma projeção idempotente e regenerável em
  `.git/ralph-control/continuations/` com fingerprint canônico da árvore
  (commit, tree hash, paths staged/unstaged/untracked separando o runtime
  controlado) e sem segredos ou conteúdo bruto; o evento
  `continuation.generated` é emitido antes do `provider.failover_started`;
- o failover é bloqueado se um runner do workflow ainda estiver observável
  (`recovery_required`, nunca troca com processo vivo);
- o adapter OpenCode publica `runner-result` v2 por opt-in
  (`RALPH_OPENCODE_RESULT_V2=1`) com `profile`/`failure_domain` declarado,
  preservando o v1 como default da migração e a sessão/evento terminal/policy
  proof;
- a espera de capacidade é reapropriável: cooldown vencido re-seleciona um
  runner, o horizonte `max_no_progress_seconds` esgota em `recovery_required`
  e `short_wait_threshold_seconds` prefere espera curta sem trocar runner;
- observabilidade: o handoff final inclui `provider_transitions` derivadas do
  ledger, o monitor expõe `provider_circuits` read-only e o `ralph-metrics`
  agrega `provider_capacity_limits`, `provider_failovers` e
  `provider_capacity_waits` sem mutar o ledger nem medir tokens/custo.

### FEATURE-097 — recuperação de gate

- `gate.rejected` (evidência mostra falha da feature → `debugging_required`) vs
  `gate.harness_error` (comando sem evidência ou timeout → `awaiting_gates`);
- retry de gate **não re-executa o bloco já commitado**: após
  `debugging_verified`, o supervisor usa `beginGateRetry`
  (`gate.retry_started` → `awaiting_gates`) e re-roda só o gate pendente;
- default de `curation` pré-release é read-only (`ralph-knowledge candidates`);
- `ralph-control gate-test --gate <gate>` valida o comando em fixture com o
  `gate-timeout` do gate real.

O self-hosting do próprio Ralph Method foi exercitado em clone dedicado com o
engine OpenCode: o `ralph-control supervise` rodou o pipeline completo
(claim/lease/fencing, implementação via adapter, gates 1–3, revisão read-only
independente, systematic debugging e retry) sobre a fila da FEATURE-094
(failover). A certificação revelou e corrigiu três pontos que o uso real
expôs: o detector de rate limit do Codex não reconhecia a mensagem real
`You have hit your usage limit ... try again at <data>`; o health probe
`opencode models` demora ~11s e estourava o timeout de 8s, deixando o OpenCode
permanentemente `degraded`; e o preflight OpenCode exige as variáveis
`RALPH_OPENCODE_*` no ambiente do supervisor. Os perfis self-hosted
`.ralph/codex.env` e `.ralph/opencode.env` estão versionados; a prova
read-only do OpenCode é gerada fora da raiz mutável.

A versão `0.4.0` foi a primeira promoção para `main`. A versão `0.6.1` foi a
release de manutenção baseada no merge `ba98dfa` em `main`, recebeu a tag
anotada `v0.6.1` e está sincronizada com `origin/main`. A `0.8.0` agora é a
release atual, promovida para `main` após a comprovação da base funcional em
[`docs/reports/0016-promocao-v0-6-0.md`](reports/0016-promocao-v0-6-0.md).
O fechamento da manutenção está em
[`docs/reports/0017-release-manutencao-v0-6-1.md`](reports/0017-release-manutencao-v0-6-1.md).
O guia operacional para agentes está na `guide_version: 1.7.0` e agora
descreve o ciclo completo de dry-run, instalação, execução, monitoramento,
recuperação, memória, desinstalação e diagnóstico pós-atualização de MCP. A
prática foi motivada pelo [`ADR-0014`](adr/0014-diagnostico-mcp-pos-atualizacao-de-harness.md)
e pelo [`incidente 0014`](incidents/0014-startup-mcp-pos-atualizacao-codex.md).
Este checkout também possui um perfil self-hosted em `.ralph/codex.env` para
que as próximas fases do próprio Ralph Method sejam executadas pelo runner
nativo do Codex através de `scripts/ralph.sh`; a decisão está no
[`ADR-0015`](adr/0015-self-hosting-com-runner-codex.md).

A branch `feat/ralph-hardening` concentrou a evolução de segurança da v0.5.0
e a evolução de memória da v0.6.0; essas mudanças agora fazem parte de
`main`.

A primeira execução remota do CI após a promoção falhou no teste de prontidão
de providers por incompatibilidades de `PATH` e de `proc_close()` no PHP 8.2.
O hotfix foi corrigido, validado em PHP 8.2, promovido pela PR #1 e certificado
no run remoto `31341326999`. O postmortem e a resolução estão em
[`docs/incidents/0010-ci-php82-process-status.md`](incidents/0010-ci-php82-process-status.md).

A primeira entrega adiciona exclusividade por feature durante o bloco controlado,
protege o ledger com `workflow.lock` e comprova a rejeição de duas execuções
simultâneas no teste de método. Essa evolução agora faz parte de `main`.
A aprovação também distingue uma feature já presente no `HEAD` de uma
implementação que produziu commit: o primeiro caso passa pelos gates sem criar
commit vazio e fica marcado no ledger como `implementation_mode=already_present`.
Resultado stale antes da promoção exige recovery explícito.
O supervisor também emite heartbeat durante a revisão read-only do OpenCode.
Se uma tentativa ficar stale ou terminar sem evento terminal, o retry registra
`recovery.required` e só inicia uma nova execução após `beginFailedRetry()`,
com novo `attempt`, novo lease e novo fencing token. A correção está registrada
no [`ADR-0013`](adr/0013-retry-do-supervisor-com-novo-fencing.md), no
[`incidente 0013`](incidents/0013-retry-stale-reutilizava-lease.md) e no
[`relatório 0022`](reports/0022-hardening-supervisor-recovery-2026-08-11.md).
O handoff e a memória de engenharia são uma camada não bloqueante: a entrega
pode continuar enquanto a curadoria aguarda revisão, sem perder o candidato
rastreável. A v0.6.0 adiciona cache episódico sanitizado, decisão explícita de
retenção, taxonomia de categoria/tema/stack/domínio/fingerprint e índices
macro/subíndices derivados. A promoção desta evolução foi concluída após a
regressão portátil final, sem revisão adversarial independente aprovada — a
última tentativa excedeu o timeout e foi encerrada sem veredicto.
O incidente e a correção estão documentados em
[`docs/incidents/0008-concorrencia-no-bloco-controlado.md`](incidents/0008-concorrencia-no-bloco-controlado.md).
Na revisão adversarial, o checkpoint encontrou e corrigiu o bypass por
`workflow_id` alternativo, o `finish` concorrente e o replay de uma tentativa
sem evento terminal após crash. O contrato executável dessa evolução está em
[`docs/architecture/control-plane-hardening-plan.md`](architecture/control-plane-hardening-plan.md).

O repositório é uma extração independente do núcleo Ralph validado no
`refactor-radar`: essa é a origem histórica, não uma dependência de runtime.
Não há importação de código, banco, credencial ou módulo do produto-alvo. A
base `0.4.0` mantém a instalação local reversível, doctor, ownership por hash
e canal de feedback para o orquestrador externo; as evoluções `0.5.0` e `0.6.0`
adicionam hardening do control plane e memória de engenharia versionada.

O escopo operacional deste checkout inclui quatro harnesses: Codex e Claude CLI
pelos runners nativos do loop, OpenCode pelo adapter certificado e `agy` pelo
adapter candidato em `adapters/agy/`. O verify `agy` é fail-closed e limitado a
Linux com `bwrap` allowlisted e file access restrito ao workspace; Hermes
permanece somente na detecção passiva e
no [`docs/backlog.md`](backlog.md).

A v0.7.0 adicionou uma camada de detecção somente leitura para identificar
Ralph externo antes do `apply`. A v0.8.0 transforma a evolução em uma operação
explícita: `evolve --plan/--apply` cria um backup numerado com hashes, isola os
sinais detectados — inclusive árvores `legacy_directory` recursivas com tipos,
permissões e journal before/after — instala o método de forma transacional e aguarda aceite;
`rollback --plan/--apply` remove a instalação nova somente quando não há drift
e restaura o legado. Ledger, workflow, prompts e credenciais continuam fora da
migração. A prova automatizada cobre idempotência, drift, runtime preservado e
restauração. A prova de campo conduzida pelo OpenCode `1.18.15`, com o ciclo
completo de instalação e rollback, está registrada no
[`Relatório 0019`](reports/0019-evolucao-opencode-v0-8-0.md). A decisão está no
[`ADR-0011`](adr/0011-evolucao-assistida-backup-rollback.md); a evidência de
campo confirmou o contrato `quarantine_only` sem importação de estado legado.
O timeout observado na revisão adversarial foi isolado como falha de contexto
de checkout do subagente, não como falha do detector; a correção e a
reprodução estão em [`incidente 0011`](incidents/0011-timeout-revisao-adversarial-contexto.md).
O detector também reconhece, de forma limitada à raiz aprovada `harness/ralph`,
a assinatura `bc-harness` formada por `install.sh`, `ralph.patch` e
`ralph.sh.upstream`. O plano expõe família, assinatura, membros, SHA-256 e
fingerprint determinístico sem conteúdo bruto, classifica a origem como
`external_ralph_legacy` e recomenda `evolve`.

Durante a primeira evolução assistida com o provider Codex no `refactor-radar`,
o portão oficial reproduziu duas regressões da 0.8.0: o cache não bloqueante de
conhecimento aparecia como arquivo não rastreado, e `observe` não sanitizava
detalhes depois de se tornar não mutante. A correção está registrada nos
[`incidentes 0015`](incidents/0015-evolve-superficie-incompleta.md) e
[`0016`](incidents/0016-candidato-episodico-contaminava-arvore.md): a evolução
agora inventaria toda a superfície gerenciada, registra o cache episódico no
`.git/info/exclude` e mantém a sanitização sem conceder autoridade ao hook. A
CI portátil foi reexecutada com exit `0`, incluindo 163 asserts do loop e as
provas de instalação, rollback, provider Codex, conhecimento e reprodutibilidade.
Na mesma validação, o executor controlado recuperou os identificadores seguros
de workflow e feature para manter feedback e artefatos correlacionados; leases,
credenciais e proofs continuam fora do ambiente. O incidente está detalhado no
[`incidente 0017`](incidents/0017-contexto-seguro-ausente-no-executor.md), com
regressão reproduzida no `bin/check` do projeto-alvo e corrigida antes do aceite.

A regressão da entrega do detector legado (`FEATURE-093-REGRESSION-RELEASE`)
foi concluída na branch `feat/detector-bc-legacy`: lint dos componentes
alterados, `check-shell`, `check-doc-sync`, `test-installation`,
`test-reproducibility`, regressão multiprovider e OpenCode, e `ci-portable`
verdes. As confirmações diretas em fixture isolada provaram instalação neutra
permitida, bloqueio fail-closed do `apply` comum sobre `harness/ralph/` e o
ciclo evolve → aceite → drift → rollback. A evidência completa está no
[`Relatório 0021`](reports/0021-regressao-release-detector-legado-2026-08-12.md).

Após o hardening do supervisor (retry com novo fencing, ADR-0013) e o fix do
falso negativo de SIGPIPE na prontidão de providers, a regressão foi
revalidada (attempt-4): os mesmos checks verdes, incluindo
`test-provider-readiness` e `test-ralph-method` com 163 asserts, e o mesmo
ciclo de confirmações diretas em fixture isolada. A evidência do reateste está
no [`Relatório 0023`](reports/0023-revalidacao-regressao-release-detector-legado-2026-08-12.md).

## Componentes extraídos

| Componente | Path | Responsabilidade |
|---|---|---|
| Control plane | `bin/ralph-control` | estado, lease, fencing, gates e ledger |
| Trace | `bin/ralph-trace` | fatos de delegação e relatório `TRC` |
| Monitor | `bin/ralph-monitor` | snapshot operacional sem transição |
| Métricas | `bin/ralph-metrics` | agregação JSON/Markdown somente leitura do ledger |
| Bloco | `bin/ralph-block`, `bin/ralph-bloco` | uma feature por execução |
| Loop | `scripts/ralph.sh` | sessões por fase e gates externos |
| Hook | `scripts/ralph-hook.sh` | observabilidade best-effort |
| Conhecimento | `bin/ralph-knowledge`, `.ralph/knowledge-candidates/` | cache episódico, retenção explícita, taxonomia e recuperação seletiva |
| Índices de memória | `docs/engineering/INDEX.md`, `categories/`, `topics/` | índice macro e subíndices derivados por categoria e tema |
| Instalação | `bin/ralph-init` | plan/apply/uninstall com manifesto |
| Evolução assistida | `bin/ralph-init evolve|rollback` | backup numerado, isolamento, aceite e rollback condicional |
| Doctor | `bin/ralph-doctor` | drift e integridade da instalação |
| Feedback | `schemas/feedback-event.schema.json` | contrato JSONL/stdout/callback |
| Prontidão de provider | `schemas/provider-readiness.schema.json` | autenticação, diagnóstico seguro e elegibilidade do adapter |
| Detecção de instalação | `schemas/ralph-installation-detection.schema.json` | Ralph Method gerenciado, Ralph externo ou origem ambígua |
| Evolução | `schemas/ralph-evolution.schema.json`, `.ralph/evolutions/` | estado persistente, hashes, drift e rollback sem importar estado legado |
| Migração por origem | `schemas/migration-adapter.schema.json`, ADR-0020 | contrato fechado por origem (bc-harness, knowledge_only); nunca importa ledger/workflow/prompts/credenciais |
| Adapter OpenCode | `adapters/opencode/` | preflight, execução JSONL, parser fail-closed e resultado normalizado |
| Adapter agy | `adapters/agy/` | preflight, `stream-json`, parser/policy fail-closed e verify isolado por `bwrap` |
| Runners Codex/Claude | `scripts/ralph.sh` | integração nativa de execução e revisão do loop |
| Resultado de runner | `schemas/runner-result.schema.json` | OpenCode 1.0/`step_finish`, `agy` 1.1/`result` e contrato comum 2.0 (`codex`/`claude`/`opencode` com `failure_domain` e `usage_limited` de confiança alta) sob validação fail-closed |
| Política de execução | `schemas/execution-policy.schema.json` | opt-in `explicit_failover` com cadeia e limites obrigatórios; default continua `fallback_policy=none` |
| Política read-only OpenCode | `adapters/opencode/policy.php`, `scripts/opencode-readonly-proof.sh` | fingerprint, prova externa e bloqueio fail-closed da revisão |
| Política read-only agy | `adapters/agy/policy.php`, `.agents/agents/ralph-review/agent.md` | hash versionado, allowlist e isolamento preventivo Linux |
| Guia de agentes | `docs/AGENT_GUIDE.md` | operação, comunicação e ciclo de vida |

A matriz completa de componentes, responsabilidades e limites está em
[`docs/architecture/README.md`](architecture/README.md). Ela é a referência
para abstrair o Ralph Method para outro projeto ou harness sem misturar
autoridade do controlador, execução do runner, observabilidade e documentação.

## Entrega concluída nesta fase

`ralph-init plan/apply/uninstall`, `ralph-doctor`, manifesto de instalação,
capabilities dos providers, prontidão condicional, seleção determinística e
feedback do loop foram
implementados com testes portáteis. O uninstall preserva runtime, workflow e evidências; arquivos
alterados pelo usuário ficam intactos. O apply usa staging e rollback para não
deixar instalação parcial em falha; os perfis gerados apontam para o loop local.
Quando o bloco é lançado pelo controlador, o feedback também é retransmitido
ao terminal em tempo real. O guia de agentes acompanha a versão do método e é
verificado por `scripts/check-doc-sync.sh`. A verificação de providers é
passiva por padrão; `--verify-providers` executa somente probes seguros não
generativos.

## Providers e harnesses

O loop herdado do `bc-harness` possui execução Codex e Claude. Nesta versão,
provider pode ser certificado como `functional` quando `auth_status` é
`authenticated` e `health_status` é `healthy`. `adapter_enabled` exige também
`runner_supported=true`. OpenCode é certificado com `auth list` + `models`,
JSONL e prova read-only externa. `agy` usa `models` +
`--add-dir <repo-root> agents` como probes não generativos, exige exatamente
`ralph-review` e só habilita o adapter com Linux, `bwrap` operacional e token
OAuth legível; sua prova real usa isolamento allowlisted. Hermes continua sem
adapter. Nenhum provider entra como fallback. Nenhum probe inicia geração. Quando nenhum runner
está disponível, `auto` mantém o plano em `needs_review` sem materializar
`codex` ou outro executor fictício.

## Validação

Os checks portáteis verdes são `scripts/check-shell.sh`,
`scripts/ci-portable.sh`,
`scripts/test-installation.sh`, `scripts/test-feedback.sh`,
`scripts/test-provider-readiness.sh`, `scripts/test-multiprovider.sh`,
`scripts/test-ralph-method.sh`, `scripts/test-ralph-knowledge.sh` e
`scripts/test-ralph.sh`, `scripts/test-ralph-metrics.sh`, além de `scripts/test-opencode-policy.sh`,
`scripts/test-opencode-adapter.sh`, `scripts/test-opencode-adversarial.sh`,
`scripts/test-agy-adapter.sh`, `scripts/test-agy-loop.sh` e
`scripts/test-agy-control.sh`. As provas reais explícitas são
`scripts/test-opencode-field.sh` e `scripts/test-agy-field.sh`. Eles cobrem ownership, conflito, idempotência,
remoção segura, eventos, prontidão de providers, progresso e a regressão do
loop, capability adversarial, parsing JSONL, política read-only e execução
complexa por OpenCode com implementação e revisão preservadas no trace.

O teste de métricas comprova agregação por workflow/feature, duração observada,
saída Markdown, rejeição de ledger corrompido e ausência de mutação no arquivo
de eventos. A evidência completa está em
[`docs/reports/0012-metricas-read-only-v0-5-0.md`](reports/0012-metricas-read-only-v0-5-0.md).

A regressão multiprovider offline está verde no relatório
[`docs/reports/0009-regressao-multiprovider.md`](reports/0009-regressao-multiprovider.md).
A CI portátil local também está verde no relatório
[`docs/reports/0011-ci-portatil-v0-5-0.md`](reports/0011-ci-portatil-v0-5-0.md);
o workflow não usa credenciais nem executa geração real de provider.
O reparo do ledger também preserva corrupção intermediária sem truncamento
silencioso, com prefixo/sufixo forenses e recovery explícito; a prova está em
[`docs/reports/0013-reparo-intermediario-ledger-v0-5-0.md`](reports/0013-reparo-intermediario-ledger-v0-5-0.md).
Após a correção de encoding, a regressão adversarial e o teste de campo real do
OpenCode terminaram verdes no relatório
[`docs/reports/0014-regressao-final-v0-5-0.md`](reports/0014-regressao-final-v0-5-0.md).
Ela prova que a seleção `auto` escolhe somente providers funcionais com
`runner_supported=true`, mantém a ordem Codex → Claude CLI → OpenCode, não
faz fallback silencioso, bloqueia `apply` explícito não autenticado e mantém
`fallback_policy=none`. A mesma prova histórica registra no `ralph-trace`
identidade exata, modelo e sessão dos três harnesses então ativos. A regressão
atual inclui `agy` como quarto runner sem mudar a política de fallback; Hermes
continua no backlog sem prioridade.

Os smoke tests reais dos CLIs também foram comprovados fora do loop: Codex
retornou exit `0`, JSONL válido, thread e marcador determinístico; Claude
retornou exit `0`, JSON válido, sessão e marcador após a correção do limite de
orçamento artificial da primeira tentativa. O teste de campo complexo OpenCode
foi repetido no commit candidato com `opencode/deepseek-v4-flash-free` e
terminou verde em 136s, com `FEATURE_CHECK_OK`, trace, processo contido e
revisão read-only.

O hardening adicionou uma prova específica de handoff e memória em
[`scripts/test-ralph-knowledge.sh`](../scripts/test-ralph-knowledge.sh): a
feature avança antes da curadoria, a lição é publicada com ID `LES-YYYY-NNNN`,
a segunda curadoria é idempotente, a decisão conflitante é rejeitada, o
candidato pode ser descartado sem publicar lição e a recuperação consulta
somente lições validadas do projeto-alvo por filtros taxonômicos. Conhecimento
permanece `non_blocking`.

O relatório da implementação está em
[`docs/reports/0015-memoria-episodica-taxonomia-v0-6-0.md`](reports/0015-memoria-episodica-taxonomia-v0-6-0.md).

A reprodução independente foi comprovada a partir de um `git archive` limpo:
o bundle foi instalado duas vezes em um projeto Git fixture fora do
`refactor-radar`, validado pelo doctor, desinstalado por ownership e deixou o
projeto original limpo. O comando reproduzível é
`bash scripts/test-reproducibility.sh`.
O relatório da auditoria está em
[`docs/reports/0008-auditoria-de-acoplamento-e-reproducibilidade.md`](reports/0008-auditoria-de-acoplamento-e-reproducibilidade.md).

O adversarial do adapter OpenCode foi maturado com um probe direto da CLI real:
`ralph-review` retornou `ADVERSARIAL_VERDICT: PASS` em 38s, com uma sessão,
quatro `step_finish`, dez operações somente de leitura, política revalidada e
hash da superfície idêntico antes/depois. O teste também reproduz e protege a
rejeição de múltiplas sessões e de agente divergente.

O teste de campo real do OpenCode foi concluído com a feature
`FEATURE-FIELD-OPENCODE-001` em checkout descartável: implementação, revisão
read-only, `bin/check`, evidência de runtime e curadoria passaram; o handoff
foi versionado e o controlador avançou para uma fila vazia. O relatório
sanitizado está em
[`docs/reports/0004-teste-campo-opencode-cinco-gates.md`](reports/0004-teste-campo-opencode-cinco-gates.md).
O reteste adversarial oficial está em
[`docs/reports/0006-reteste-adversarial-oficial-opencode.md`](reports/0006-reteste-adversarial-oficial-opencode.md).
O relatório final de certificação e promoção está em
[`docs/reports/0007-certificacao-e-promocao-v0-4-0.md`](reports/0007-certificacao-e-promocao-v0-4-0.md).
As falhas anteriores foram preservadas nos incidentes 0003 a 0007. A revisão
ampla exploratória que expirou não foi considerada aprovação; a decisão usou a
prova externa, a revisão bounded estruturada, a regressão e os testes reais.
