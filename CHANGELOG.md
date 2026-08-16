# Changelog

Todas as mudanças relevantes do Ralph Method são registradas aqui em
português do Brasil. A versão no arquivo `VERSION` identifica o bundle em
desenvolvimento; uma versão só é considerada publicada após commit, tag
anotada e promoção documentada.

## 0.10.0 — em desenvolvimento

### Adapter Cursor (FEATURE-098)

- schema `runner-result 1.2.0` para o runner `cursor` (terminal `result`,
  campos v2 null) com `declared` no enum de `permission_policy_status`;
  contratos v1/v1.1/v2 preservados;
- `bin/ralph-control` valida `1.2.0+cursor`, aceita o verify declarado
  (`--mode ask`, hash `null`, agente `ask`) e rejeita `verified` para o
  cursor; `runnerResults()`/`runControlled` aceitam o engine `cursor`;
- `bin/ralph-init` detecta a CLI Cursor (`agent`/`cursor-agent`), autentica
  pela sessão local (`status --format json`, sem API key) e habilita o
  adapter somente com `RALPH_CURSOR_MODEL` explícito; novo perfil
  `.ralph/cursor.env` gerado no `apply`;
- `scripts/ralph.sh` aceita `--engine cursor` (seam de adapters, preflight,
  fingerprint, modelo de verify) e exige modelo explícito;
- `adapters/cursor/` implementa a seam `preflight|run|version`, normaliza
  `--output-format stream-json` para `runner-result 1.2.0` e falha fechado em
  JSONL inválido, zero eventos, múltiplos `result`, escrita em verify e modelo
  divergente, sanitizando eventos persistidos;
- fixture offline `scripts/test-cursor-adapter.sh` incluída no
  `ci-portable.sh`.

## 0.9.2 — publicada em 2026-08-15

### Recuperação de gate distinta (FEATURE-097)

- `ralph-control` classifica o resultado do comando de gate em três estados:
  `gate.passed`, `gate.rejected` (evidência mostra falha da feature →
  `debugging_required`) e `gate.harness_error` (comando sem evidência — stdout
  e stderr vazios — ou timeout → a feature permanece `awaiting_gates`);
- um `gate_harness_error` não re-executa o bloco já commitado: o comando é
  re-rodado automaticamente até `--gate-harness-retries` (default 2) e, só
  então, o supervisor registra `recovery_required` com
  `reason=gate_harness_error_limit`;
- **retry pós-debugging de feature commitada não re-executa o bloco**: após
  `debugging_verified` com bloco commitado e falha de gate, o supervisor usa
  `beginGateRetry` (`gate.retry_started` → `awaiting_gates`) e re-roda só o
  gate pendente — corrige o INC-2026-0007 (7–9 re-execuções do bloco, ~10–16
  min cada);
- comando de gate com `exit 0` e stdout vazio é tratado como defeito de
  harness (evidência mínima obrigatória);
- novo self-test `ralph-control gate-test --gate <gate>`: valida o comando
  configurado em modo fixture (contexto por env, evidência, exit code) sem
  tocar no workflow/ledger; usa o `gate-timeout` do gate real (default 900s,
  `--gate-timeout` para override) — teria pego o INC-2026-0007 em segundos;
- default do gate `curation` corrigido: pré-release é read-only
  (`ralph-knowledge candidates`), sem exigir ação de retenção que falharia
  antes de `feature.released`;
- `AGENT_GUIDE` documenta a classificação (seção 6.2) e o self-test;
- regressão dedicada `scripts/test-ralph-gate-recovery.sh` (cenários A–D);
- regressão de resiliência a falha de filesystem na evolução assistida:
  `scripts/test-evolution-filesystem.sh` (SIGKILL real durante o rename de
  publicação e falha de escrita no destino → rollback restaura a árvore
  legada).

### Estado da publicação

A `0.9.2` publica a FEATURE-097 em `main`, identificada pela tag anotada
`v0.9.2`. A correção foi confirmada em campo pelo `refactor-radar`
(INC-2026-0007): a phase-25 fechou com os 5 gates e o workflow avançou para a
phase-26 sem re-execução do bloco commitado.

## 0.9.1 — publicada em 2026-08-15

### Gates como contrato nativo (FEATURE-096)

- o supervisor passa a fornecer o contexto do comando de gate por ambiente
  (`RALPH_WORKFLOW_ID`, `RALPH_FEATURE_KEY`, `RALPH_ATTEMPT`, `RALPH_GATE`,
  `RALPH_REPORT_PATH`) em vez de argumentos posicionais; o lease não é
  exportado ao comando;
- os wrappers instalados `scripts/ralph-run-quality.sh`,
  `ralph-run-runtime-evidence.sh` e `ralph-run-independent-gate.sh` leem o
  contrato por env e, quando invocados pelo supervisor (presença de
  `RALPH_GATE`), apenas emitem evidência + exit code (o controlador registra o
  gate); a chamada manual com `--workflow/--feature/--lease` continua aceita e
  registra o gate;
- defaults nativos para os três gates sem default: `runtime_evidence`
  (env → `scripts/*runtime-evidence*` excluindo `ralph-run-*` → `bin/check`),
  `technical_review` (env; sem comando, rejeita sem inventar revisão) e
  `curation` (env → `bin/ralph-knowledge --workflow --feature`), de modo que o
  `supervise` executa os cinco gates numa instalação padrão sem retornar
  `gates_configuration_required`;
- refinamentos pós-revisão adversarial: detecção de runtime não recursa no
  próprio wrapper; modo manual dos wrappers preservado; higiene de ambiente
  (lease fora do comando de gate); `quality` com diagnóstico limpo quando
  `bin/check` ausente;
- `AGENT_GUIDE` documenta o contrato do comando de gate (seção 6.1);
- regressão dedicada `scripts/test-ralph-gates-native.sh`.

### Estado da publicação

A `0.9.1` publica a FEATURE-096 em `main`, identificada pela tag anotada
`v0.9.1`, com CI portátil verde (incluindo o novo `test-ralph-gates-native`).

## 0.9.0 — publicada em 2026-08-14

### Adapter nativo `agy` (FEATURE-095)

- adicionado o adapter `agy` como runner de primeira classe sob a seam comum
  `preflight|run|version` (ADR-0017), com implementação headless, verify
  isolado por `bwrap` allowlisted (ADR-0018) e resultado normalizado
  `runner-result 1.1.0` com terminal `result` (ADR-0019), preservando OpenCode
  `1.0.0`/`step_finish` e `fallback_policy=none`;
- preflight de verify comprova o agente `ralph-review` pelo arquivo
  `.agents/agents/ralph-review/agent.md` no workspace, e não pela listagem
  global `agy agents`, que expõe somente agentes instalados da sessão local;
- readiness usa `agy agents` apenas como prova de CLI funcional; a presença do
  agente de verify é validada no preflight e como superfície da policy;
- parser rejeita `step_update`/`result` anterior ao primeiro `init`, fechando a
  aceitação de evento de outra conversa pré-init;
- comprovada a regressão completa, o smoke real `agy 1.1.13` (impl + verify +
  probe de fronteira) e a revisão adversarial sem finding aberto;
- relatório numerado `docs/reports/0024-adapter-agy-funcional-2026-08-14.md` e
  promoção com revisão independente registrada.

### Detecção e evolução legada `bc-harness`

- validada a regressão das features `091-DETECT-BC-LEGACY` e
  `092-EVOLVE-BC-LEGACY` na branch `feat/detector-bc-legacy`;
- confirmado o reconhecimento da assinatura `bc-harness` (`install.sh` +
  `ralph.patch` + `ralph.sh.upstream`) somente em `harness/ralph`, com
  `external_ralph_legacy`, família, membros, SHA-256, fingerprint determinístico
  e `recommended_action=evolve`;
- confirmado que o `apply` comum permanece bloqueado (`apply_allowed=false`,
  exit `3`) sobre a raiz legada e que instalações neutras continuam permitidas;
- comprovado o ciclo evolve → aceite → drift → rollback em fixture isolada,
  preservando permissões, tipos e symlinks internos da árvore legada;
- rodados `php -l`, `check-shell`, `check-doc-sync`, `test-installation`,
  `test-reproducibility`, regressão multiprovider/OpenCode e `ci-portable` com
  resultado verde;
- registrada a evidência em
  `docs/reports/0021-regressao-release-detector-legado-2026-08-12.md` e a
  decisão em [`ADR-0010`](docs/adr/0010-deteccao-evolucao-de-ralph-externo.md).

### Revalidação da regressão

- revalidada a regressão (attempt-4) após o hardening do supervisor com novo
  fencing ([`ADR-0013`](docs/adr/0013-retry-do-supervisor-com-novo-fencing.md))
  e o fix do falso negativo de SIGPIPE na prontidão de providers;
- CI portátil verde com 15 checks (incluindo `test-provider-readiness` e
  `test-ralph-method` com 163 asserts) e confirmações diretas reexecutadas em
  fixture isolada: instalação neutra permitida, bloqueio do `apply` sobre
  `harness/ralph/` e o ciclo evolve → aceite → drift → rollback;
- evidência do reateste em
  `docs/reports/0023-revalidacao-regressao-release-detector-legado-2026-08-12.md`.

### Estado da publicação

A `0.9.0` consolida o detector legado e o adapter `agy` em `main`, identificada
pela tag anotada `v0.9.0`, com revisão adversarial independente sem finding
aberto e CI portátil verde.

## 0.6.1 — publicada em 2026-08-09

### Portabilidade e fechamento da release

- preservado o PHP efetivo dos runners nos fixtures com PATH controlado;
- usado o exit code observado antes de `proc_close()` nos processos críticos;
- adicionada alternativa portátil a `rg` nos testes do Ralph Method;
- sondada a capacidade real de `unshare`, com fallback seguro para
  `process_group_observed` quando namespaces não estão disponíveis;
- sincronizados `VERSION`, `STATUS`, README, guia de agentes e incidente do
  CI pós-promoção;
- adicionada a evidência numerada da release em
  `docs/reports/0017-release-manutencao-v0-6-1.md`.

### Estado da publicação

O hotfix foi promovido para `main` pela PR #1 no merge `ba98dfa`. O CI remoto
passou no run `31341326999`, incluindo os checks portáteis e o GitGuardian. A
tag anotada `v0.6.1` identifica este fechamento documental e de portabilidade.

## 0.8.0 — publicada em 2026-08-10

### Evolução assistida com backup e rollback

- adicionados `evolve --plan/--apply` e `rollback --plan/--apply`;
- criado estado numerado `EVL-YYYYMMDD-NNNN` com backup e hashes;
- isolados somente sinais externos detectados, sem importar ledger, workflow,
  prompts, credenciais ou eventos;
- preservados sinais de runtime em `.git/ralph-control`;
- adicionado aceite explícito com backup mantido;
- bloqueado rollback quando a instalação nova possui drift, arquivo ausente,
  backup incompleto ou destino ocupado;
- adicionada regressão de idempotência, restauração, drift e runtime legado;
- adicionado o contrato `schemas/ralph-evolution.schema.json`;
- comprovado o ciclo completo em fixture isolada conduzida pelo OpenCode
  `1.18.15`, com relatório numerado `docs/reports/0019-evolucao-opencode-v0-8-0.md`.

### Detecção segura de instalação externa

- adicionada detecção somente leitura de sinais de Ralph fora do manifesto do
  Ralph Method;
- publicado o contrato `schemas/ralph-installation-detection.schema.json` com
  classificação, confiança, caminhos relativos e hashes SHA-256;
- bloqueado o `apply` comum quando há Ralph externo detectado ou origem
  ambígua, preservando os arquivos encontrados;
- adicionado `doctor` com status explícito para instalação externa;
- documentada a evolução futura com backup, rollback e adapter de origem, sem
  migração genérica de ledger, prompts, workflow ou credenciais.
- reconhecida a instalação legada `bc-harness` somente em `harness/ralph`, com
  assinatura, membros, hashes e fingerprint determinístico no schema `1.1.0`;
- mantidos `vendor` e `node_modules` fora da varredura, com rejeição de raiz
  inválida, traversal e symlink externo.

Esta versão foi validada na branch `dev`, promovida para `main` e identificada
pela tag anotada `v0.8.0`.

## 0.6.0 — publicada em 2026-08-09

### Memória episódica e retenção

- materializado um candidato sanitizado em
  `.ralph/knowledge-candidates/` após `feature.released`;
- adicionadas ações explícitas para persistir, rejeitar, revisar ou descartar
  uma memória sem bloquear a fila de features;
- impedidas decisões de retenção conflitantes para a mesma tentativa;
- adicionada taxonomia estruturada de categoria, temas, stack, domínio e
  fingerprints;
- gerados índice macro e subíndices por categoria e tema;
- adicionados filtros taxonômicos à recuperação seletiva;
- incluído contrato `schemas/knowledge-candidate.schema.json` e prova de
  instalação do novo artefato.

### Estado da publicação

Esta entrega foi promovida para `main` no commit `5d579b5`, recebeu a tag
anotada `v0.6.0` e está sincronizada com `origin/main`. A comprovação da
promoção está em
[`docs/reports/0016-promocao-v0-6-0.md`](docs/reports/0016-promocao-v0-6-0.md).

## 0.5.0 — não publicada

### Control plane

- adicionada exclusividade por `workflow_id` canônico e `feature_key` durante
  o bloco controlado;
- protegida a escrita do ledger e a criação inicial de `events.jsonl` com
  lock reentrante e escrita append-only;
- rejeitados aliases de workflow, `finish` concorrente e replay de tentativa
  sem evento terminal;
- adicionada detecção explícita de execução incompleta e recuperação com novo
  lease/fencing;
- adicionados cenários reproduzíveis de concorrência, crash, corrupção de
  ledger e reparo intermediário.

### Handoff e memória

- adicionada geração idempotente de handoff com bug report, evidências e
  resumo de execução;
- adicionada memória de engenharia versionada com documentos `LES-YYYY-NNNN`,
  índice e recuperação seletiva por contexto;
- mantida a política `knowledge_policy.mode: non_blocking`: curadoria é
  contribuição de memória e não bloqueia a continuidade da entrega;
- corrigido o escopo da recuperação para consultar a memória do projeto-alvo,
  e não a memória do repositório que distribui o método.

### Compatibilidade e segurança

- preservados os contratos dos três harnesses ativos: Codex, Claude CLI e
  OpenCode;
- adicionados ADR e incidente sobre a exclusividade e o ledger protegido;
- testes de instalação e reprodução passaram a comparar a versão publicada
  pelo bundle com o arquivo `VERSION`, evitando hardcode obsoleto.
- adicionada CI portátil com uma fronteira explícita de checks offline,
  permissões mínimas e exclusão consciente das provas reais de provider.
- adicionado `bin/ralph-metrics`, uma projeção JSON/Markdown somente leitura
  para contagens e durações do ledger, sem telemetria de custo/token.
- a CI portátil foi reexecutada contra o bundle commitado com as métricas
  instaláveis e permaneceu verde.
- `repair-ledger` passou a preservar e separar prefixo/sufixo quando a
  corrupção ocorre no meio do arquivo, gerando relatório numerado e exigindo
  restauração manual sem tocar no ledger original.
- previews de processo e resultados do parser passaram a normalizar bytes
  inválidos para UTF-8 antes da serialização JSON; o cenário foi reproduzido
  em teste e validado novamente no campo real OpenCode.

### Estado da publicação

Esta entrega está em `feat/ralph-hardening` para validação controlada. A
promoção para `main` depende das fases posteriores do plano, incluindo CI,
métricas read-only e regressão final.

## 0.4.0 — publicada

- engine OpenCode, adapter fail-closed, prova read-only e teste de campo;
- instalação reversível por projeto;
- prontidão condicional para providers;
- feedback operacional e trace multiprovider.

Consulte os relatórios numerados em [`docs/reports/`](docs/reports/).
