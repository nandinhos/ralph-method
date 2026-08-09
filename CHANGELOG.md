# Changelog

Todas as mudanças relevantes do Ralph Method são registradas aqui em
português do Brasil. A versão no arquivo `VERSION` identifica o bundle em
desenvolvimento; uma versão só é considerada publicada após commit, tag
anotada e promoção documentada.

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
