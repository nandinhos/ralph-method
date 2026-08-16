# Continuidade e failover controlado Codex → OpenCode

Este plano implementa
[`docs/architecture/provider-failover-continuity-plan.md`](../../../docs/architecture/provider-failover-continuity-plan.md)
sob a decisão proposta no
[`ADR-0016`](../../../docs/adr/0016-failover-controlado-entre-providers.md).

Invariantes para todas as fases:

- executar a implementação pelo runner nativo Codex do self-hosting;
- iniciar este workflow sem `execution_policy`, pois o próprio plano entrega
  esse contrato; o bootstrap não pode depender da capacidade ainda inexistente;
- preservar `fallback_policy=none` para workflows sem opt-in;
- não habilitar failover por erro genérico, autenticação ou gate vermelho;
- não expor tokens, prompts, respostas completas, leases ou proofs;
- não iniciar um segundo runner antes de comprovar o término do anterior;
- usar `bash scripts/ci-portable.sh` como portão de qualidade deste repositório;
- manter uma feature por bloco e um commit por fase aprovada.

## Phase 1: Congelar contratos, compatibilidade e testes vermelhos

- [x] **Task:** aceitar o ADR-0016 e manter o plano arquitetural como fonte da
  especificação.
  - **Acceptance criteria:** decisão, escopo inicial e gatilhos continuam
    limitados a Codex → OpenCode por `provider_usage_limited`.
- [ ] **Task:** evoluir `schemas/runner-result.schema.json` para um contrato v2
  comum a Codex, Claude e OpenCode, preservando leitura do v1 OpenCode.
  - **Acceptance criteria:** campos comuns, condicionais de revisão e status
    `usage_limited` possuem validação fail-closed.
- [ ] **Task:** criar `schemas/execution-policy.schema.json` para o opt-in
  `explicit_failover` e seus limites obrigatórios.
  - **Acceptance criteria:** cadeia vazia, profile ausente, motivo não
    suportado e limites inválidos são rejeitados.
- [ ] **Task:** planejar a promoção do ledger para `1.2.0` sem emitir eventos
  novos antes de o leitor compatível estar instalado.
  - **Acceptance criteria:** o binário novo lê ledgers `1.0.0` e `1.1.0`; o
    comportamento fail-closed de binários antigos fica documentado e testado.
- [ ] **Task:** criar a base de `scripts/test-provider-failover.sh` com relógio
  injetável e CLIs fixture, inicialmente vermelha para o novo comportamento.
  - **Acceptance criteria:** a fixture não usa rede, credenciais, geração real
    ou sleeps de cooldown.
- [ ] **Task:** proteger a regressão do comportamento legado.
  - **Acceptance criteria:** workflow sem `execution_policy` continua com
    `fallback_policy=none` e passa em `scripts/test-multiprovider.sh`.

## Phase 2: Publicar runner-result Codex e classificar rate limit

- [ ] **Task:** fazer o runner nativo Codex produzir `runner-result` v2
  correlacionado com workflow, feature, attempt e execution ID.
  - **Acceptance criteria:** resultado é sanitizado, referenciado por artifact
    e validado antes de qualquer decisão do controlador.
- [ ] **Task:** classificar somente assinaturas terminais conhecidas como
  `provider_usage_limited` de confiança alta.
  - **Acceptance criteria:** `429` em saída de teste, texto de arquivo e erro
    genérico não produzem rate limit.
- [ ] **Task:** registrar `retry_at`, fonte e versão do classificador e hash da
  evidência sem persistir o texto bruto no ledger.
  - **Acceptance criteria:** ausência ou ambiguidade de reset usa o estado
    previsto, sem inventar timestamp.
- [ ] **Task:** devolver a decisão ao controlador quando
  `explicit_failover` estiver ativo.
  - **Acceptance criteria:** `ralph.sh` não dorme nem relança Codex após o
    limite nesse modo; workflows legados mantêm a espera interna existente.
- [ ] **Task:** comprovar término do processo e do grupo antes de publicar o
  outcome terminal.
  - **Acceptance criteria:** processo ainda observável resulta em
    `recovery_required`, não em failover.
- [ ] **Task:** cobrir sanitização e limite de captura.
  - **Acceptance criteria:** segredo-canário e bytes UTF-8 inválidos não vazam
    nem quebram o evento terminal.

## Phase 3: Validar política, domínio de falha e roteamento read-only

- [ ] **Task:** validar `execution_policy` no `ralph-control init` e congelar
  seu hash no workflow ativo.
  - **Acceptance criteria:** drift da política depois do início bloqueia nova
    attempt.
- [ ] **Task:** estender readiness para produzir `failure_domain` opaco e
  `failure_domain_status=exact|observed|declared|unavailable`.
  - **Acceptance criteria:** domínio bruto de conta/projeto não é persistido e
    modelo/alias não é usado para inferência.
- [ ] **Task:** exigir origem e destino distintos em `observed|exact` para
  failover automático.
  - **Acceptance criteria:** domínio igual, declarado ou indisponível deixa o
    destino inelegível.
- [ ] **Task:** projetar circuitos `closed|open|half_open` exclusivamente do
  ledger e do relógio injetado.
  - **Acceptance criteria:** nenhum arquivo sidecar vira fonte autoritativa.
- [ ] **Task:** implementar `provider-status` e `failover-plan` como comandos
  somente leitura.
  - **Acceptance criteria:** os comandos explicam seleção, bloqueios, cooldown
    e próxima ação sem iniciar provider ou mutar eventos.
- [ ] **Task:** exigir que toda a cadeia esteja pronta antes de ativar
  `explicit_failover`.
  - **Acceptance criteria:** target incompleto bloqueia o opt-in; o sistema não
    degrada silenciosamente para outra política.

## Phase 4: Gerar continuidade e nova autoridade de execução

- [ ] **Task:** gerar cápsula de continuidade como projeção regenerável em
  `.git/ralph-control/continuations/`.
  - **Acceptance criteria:** a cápsula contém somente IDs, hashes, paths,
    critérios e artifact refs; nenhum fato existe apenas nela.
- [ ] **Task:** calcular fingerprint canônico da árvore parcial.
  - **Acceptance criteria:** status Git, staged, unstaged e untracked do
    projeto entram no hash; runtime controlado usa allowlist fechada e testada.
- [ ] **Task:** adicionar eventos `provider.capacity_limited`,
  `continuation.generated` e `provider.failover_started` ao schema `1.2.0`.
  - **Acceptance criteria:** projeções históricas continuam legíveis pelo
    binário novo e tipos desconhecidos não são ignorados silenciosamente.
- [ ] **Task:** implementar `beginProviderFailover()` sob `workflow.lock`.
  - **Acceptance criteria:** nova attempt, lease, correlation ID, execution ID
    e fencing token são distintos e monotônicos.
- [ ] **Task:** bloquear processo vivo, lock anterior, drift, replay e capsule
  stale antes do spawn.
  - **Acceptance criteria:** cada cenário termina sem iniciar target.
- [ ] **Task:** reconciliar crash entre limite, cápsula e nova attempt.
  - **Acceptance criteria:** `continue`/`supervise` retoma idempotentemente ou
    entra em `recovery_required`, sem duplicar processo.

## Phase 5: Continuar a feature com OpenCode

- [ ] **Task:** selecionar OpenCode somente como próximo membro autorizado da
  cadeia, nunca por fallback interno do adapter.
  - **Acceptance criteria:** destino, profile e policy hash correspondem ao
    manifesto congelado.
- [ ] **Task:** repetir readiness do OpenCode imediatamente antes do spawn.
  - **Acceptance criteria:** autenticação, health, modelo, agente, proof e
    failure domain permanecem válidos.
- [ ] **Task:** montar contexto de continuidade com a especificação original,
  resumo sanitizado e instrução para inspecionar a árvore existente.
  - **Acceptance criteria:** prompt não contém logs brutos, resposta Codex,
    segredo, lease ou diff serializado.
- [ ] **Task:** fazer o adapter OpenCode publicar `runner-result` v2.
  - **Acceptance criteria:** resultado v1 segue compatível durante a migração
    e o v2 mantém sessão, evento terminal e policy proof.
- [ ] **Task:** executar implementação e revisão OpenCode em sessões separadas.
  - **Acceptance criteria:** revisão read-only revalida agente, proof,
    fingerprint e ausência de canário.
- [ ] **Task:** concluir a fixture offline Codex parcial → OpenCode → gates.
  - **Acceptance criteria:** mesma feature termina em nova attempt, passa pelos
    testes e rejeita o lease antigo.

## Phase 6: Sustentar espera de capacidade e fila longa

- [ ] **Task:** implementar `provider.capacity_wait_started` e
  `provider.capacity_wait_finished` com heartbeat.
  - **Acceptance criteria:** espera não ocupa o lock curto do workflow nem usa
    busy loop.
- [ ] **Task:** aplicar `short_wait_threshold_seconds` sempre em nova attempt
  quando a política estiver ativa.
  - **Acceptance criteria:** reset curto não troca runner, mas também não
    reutiliza lease ou fencing.
- [ ] **Task:** tornar `capacity_wait` reapropriável após crash do supervisor.
  - **Acceptance criteria:** nova instância reconcilia `retry_at`, processos e
    horizonte antes de retomar.
- [ ] **Task:** manter o circuito Codex aberto nas features seguintes.
  - **Acceptance criteria:** OpenCode permanece selecionado enquanto elegível,
    sem testar Codex a cada feature.
- [ ] **Task:** realizar probe half-open antes de retornar ao Codex.
  - **Acceptance criteria:** retorno acontece apenas em nova feature e após
    readiness verde.
- [ ] **Task:** aplicar `max_switches_per_feature`, `max_no_progress_seconds` e
  `when_chain_exhausted` exatamente como declarados.
  - **Acceptance criteria:** cadeia esgotada espera ou falha conforme política,
    sem default oculto e sem execução infinita sem progresso.

## Phase 7: Projetar handoff, trace, monitor e métricas

- [ ] **Task:** incluir `provider_transitions` no handoff final a partir do
  ledger.
  - **Acceptance criteria:** origem, destino, attempts, motivo, capsule e
    resultados podem ser auditados sem logs brutos.
- [ ] **Task:** projetar cada sessão no `ralph-trace` com runner, provider,
  modelo e identidade comprovada.
  - **Acceptance criteria:** modelo solicitado nunca é relatado como efetivo
    sem evidência.
- [ ] **Task:** mostrar circuitos, cooldown, runner atual, próxima ação e tempo
  sem progresso no monitor.
  - **Acceptance criteria:** monitor continua sem autoridade de retry ou
    transição.
- [ ] **Task:** adicionar métricas read-only de attempts, failovers, espera,
  sucesso e esgotamento.
  - **Acceptance criteria:** `ralph-metrics` não muta ledger e não mede tokens
    ou custo.
- [ ] **Task:** estender sanitização a capsule, eventos, feedback, handoff e
  relatórios.
  - **Acceptance criteria:** fixture com tokens, API keys e texto inválido não
    produz vazamento.
- [ ] **Task:** atualizar interfaces e exemplos ainda como candidata.
  - **Acceptance criteria:** `STATUS` não declara o failover entregue antes da
    prova de campo e da promoção.

## Phase 8: Executar matriz adversarial e regressão completa

- [ ] **Task:** injetar SIGTERM/SIGKILL nos limites entre processo, outcome,
  capsule e nova attempt.
  - **Acceptance criteria:** nenhum cenário deixa dois runners vivos ou avança
    feature sem gates.
- [ ] **Task:** testar evento duplicado, ledger truncado, relógio avançando,
  timeout half-open e output acima do limite.
  - **Acceptance criteria:** retomada é idempotente ou termina em
    `recovery_required` com evidência.
- [ ] **Task:** testar gate vermelho, autenticação inválida, proof divergente e
  domínio desconhecido.
  - **Acceptance criteria:** nenhum desses casos inicia failover automático.
- [ ] **Task:** executar a regressão de shell, docs, feedback, readiness,
  multiprovider, OpenCode, método, loop e CI portátil.
  - **Acceptance criteria:** todos os comandos obrigatórios terminam com exit
    code zero e saída preservada como evidência.
- [ ] **Task:** submeter código e design a revisão adversarial independente.
  - **Acceptance criteria:** todo finding crítico/alto é corrigido ou bloqueia
    a promoção; timeout sem veredito não conta como aprovação.
- [ ] **Task:** produzir relatório numerado da candidata.
  - **Acceptance criteria:** relatório separa fixture, regressão, limitações e
    itens ainda não comprovados em campo.

## Phase 9: Provar em campo e preparar promoção

- [ ] **Task:** criar `scripts/test-provider-failover-field.sh` reproduzível
  para uma worktree descartável do `refactor-radar`.
  - **Acceptance criteria:** a `main` ativa não é usada nem modificada.
- [ ] **Task:** instalar/evoluir o bundle candidato e validar doctor, profiles e
  domínios observados.
  - **Acceptance criteria:** Codex e OpenCode estão funcionais e independentes
    antes do teste.
- [ ] **Task:** injetar Codex `usage_limited` por shim versionado depois de uma
  alteração parcial controlada e continuar com OpenCode real.
  - **Acceptance criteria:** nova attempt preserva a árvore, passa `bin/check`
    e não deixa processo órfão.
- [ ] **Task:** concluir os cinco gates, handoff final e trace multiprovider.
  - **Acceptance criteria:** transições, sessões e fencing distintos ficam
    comprovados por artifacts sanitizados.
- [ ] **Task:** executar rollback/desinstalação ou descartar a worktree de modo
  verificável.
  - **Acceptance criteria:** projeto original e runtime preservado não sofrem
    drift não autorizado.
- [ ] **Task:** atualizar `STATUS`, `AGENT_GUIDE`, roadmap, changelog e versão
  somente após o campo verde.
  - **Acceptance criteria:** documentação diferencia defaults, opt-in,
    operação, recovery e limitações.
- [ ] **Task:** executar revisão independente, commit único da fase, regressão
  pós-merge e promoção pelo Ralph.
  - **Acceptance criteria:** release só é declarada após todos os gates e
    checks finais verdes.
