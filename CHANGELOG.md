# Changelog

Todas as mudanças relevantes do Ralph Method são registradas aqui em
português do Brasil. A versão no arquivo `VERSION` identifica o bundle em
desenvolvimento; uma versão só é considerada publicada após commit, tag
anotada e promoção documentada.

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

## 0.7.0 — em desenvolvimento

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

Esta versão está em validação na branch `dev`; ainda não possui tag ou
promoção para `main`.

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
