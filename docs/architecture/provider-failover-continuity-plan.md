# Plano de continuidade e failover controlado entre providers

## Status

- Estado: proposto; implementação não iniciada.
- Data: 2026-08-13.
- Escopo inicial recomendado: Codex como runner primário e OpenCode como
  continuidade para `usage_limited` confirmado.
- Decisão relacionada:
  [`ADR-0016`](../adr/0016-failover-controlado-entre-providers.md).
- Plano executável pelo Ralph:
  [`.spec/features/094-provider-failover/PHASES.md`](../../.spec/features/094-provider-failover/PHASES.md),
  com workflow candidato no mesmo diretório.
- Bootstrap recomendado: clone Git dedicado, árvore limpa, engine `codex` e
  `ralph-control supervise`; não substituir o runtime de outro workflow.
- Baseline: o comportamento vigente mantém `fallback_policy=none`, espera o
  reset do mesmo runner e usa recovery explícito quando uma tentativa não pode
  continuar.

Este documento é intenção e especificação de uma evolução futura. Nenhuma
seção abaixo deve ser interpretada como comportamento já disponível.

## 1. Intenção

Permitir que um workflow longo continue sem intervenção humana quando o runner
ativo ficar temporariamente indisponível por limite de uso, preservando o
trabalho parcial e todas as garantias do `ralph-control`.

O objetivo operacional não é criar um processo literalmente infinito. É criar
um processo **contínuo até completar**, capaz de esperar capacidade ou trocar
de runner em falhas transitórias comprovadas, mas obrigado a parar quando
existir ambiguidade, risco de concorrência, falta de autoridade ou ausência de
progresso verificável.

## 2. Fonte do requisito e contexto

Não existe PRD específico para esta evolução. O requisito foi formulado na
discussão de continuidade operacional de 2026-08-13:

- um rate limit do modelo usado pelo Codex não deve necessariamente parar o
  projeto inteiro;
- o OpenCode pode assumir a mesma feature sem perder o andamento;
- a troca precisa produzir um handoff auditável;
- o processo deve continuar sozinho enquanto nenhuma decisão humana for
  realmente necessária.

O Ralph Method é um control plane local, com um workflow por checkout e uma
feature ativa por vez. O risco principal não é escala de infraestrutura; é
corromper o checkout ou permitir que duas sessões possuam autoridade sobre a
mesma feature. Por isso, consistência, fencing, classificação determinística e
evidência têm precedência sobre disponibilidade.

## 3. Resultado esperado

Quando o Codex atingir um limite confirmado:

1. o runner encerra a tentativa com resultado estruturado `usage_limited`;
2. o controlador comprova que o grupo de processos terminou;
3. o ledger registra o limite, a evidência sanitizada e o circuito aberto;
4. o controlador decide entre esperar um reset curto ou iniciar failover;
5. o estado parcial do checkout é inventariado em uma cápsula de continuidade;
6. o OpenCode é revalidado por probe seguro e não generativo;
7. a mesma feature recebe nova `attempt`, novo lease e novo fencing token;
8. o OpenCode recebe a especificação original e o contexto sanitizado da
   continuidade, inspeciona a árvore existente e prossegue;
9. testes, revisão independente, handoff final e demais gates permanecem
   obrigatórios;
10. features seguintes usam o primeiro runner elegível da cadeia enquanto o
    circuito do Codex estiver aberto.

Se nenhum runner estiver elegível, mas houver reset previsível, o workflow
entra em espera de capacidade com heartbeat. Se a espera exceder o horizonte
sem progresso ou surgir qualquer condição insegura, o estado final é
`recovery_required`.

## 4. Fora do escopo inicial

- fallback automático por erro genérico, teste vermelho ou revisão reprovada;
- troca de modelo dentro do próprio Codex;
- failover para Claude CLI, Hermes ou agy;
- execução paralela de providers na mesma feature;
- votação entre respostas de providers;
- migração ou reaproveitamento de sessão do provider anterior;
- serialização de prompt completo, resposta completa ou raciocínio privado;
- escolha automática de um modelo OpenCode não configurado;
- inferência do domínio de quota a partir do nome do modelo;
- failover distribuído entre máquinas ou checkouts diferentes.

Claude CLI permanece compatível com a seam, mas só entra em uma cadeia após
fixture, prova de campo e decisão própria. Hermes e agy continuam fora do
escopo operacional desta linha.

## 5. Baseline auditado

| Capacidade atual | Evidência | Limite para esta evolução |
|---|---|---|
| Espera e retry do mesmo runner após rate limit | `scripts/ralph.sh::detect_usage_limit()` e `wait_for_reset()` | o loop não troca de runner |
| Novo lease, `attempt` e fencing em recovery | `bin/ralph-control::beginFailedRetry()` | o motivo de recovery não escolhe outro provider |
| Árvore parcial preservável | `retry --preserve-tree` | não existe cápsula de continuidade entre runners |
| OpenCode com runner e resultado normalizado | `adapters/opencode/` e `schemas/runner-result.schema.json` | o contrato é específico do adapter e não autoriza failover |
| Seleção multiprovider determinística | `bin/ralph-init` e `scripts/test-multiprovider.sh` | a política comprovada é `fallback_policy=none` |
| Handoff final por feature | `.ralph/handoffs/<feature_key>/` | só existe depois dos gates; não representa transferência em andamento |

### 5.1 Correções incorporadas após revisão adversarial

Dois revisores independentes refutaram o primeiro rascunho. Os findings
aceitos mudaram o plano desta forma:

- uma política de failover ativa desliga a espera interna de rate limit do
  `ralph.sh`; o loop encerra o bloco com resultado estruturado e devolve a
  decisão ao controlador;
- toda retomada após rate limit usa nova `attempt`, inclusive quando o reset é
  curto;
- `schemas/runner-result.schema.json` evolui para um contrato comum, em vez de
  criar um segundo schema concorrente;
- `failure_domain` declarado pelo usuário não basta: a execução automática
  exige identidade `observed|exact` derivada da autoridade de credencial,
  endpoint e projeto/conta quando disponíveis;
- a cápsula é projeção idempotente do ledger, workflow e checkout, nunca uma
  segunda fonte de estado;
- o fingerprint inclui alterações staged, unstaged e untracked do projeto,
  mas exclui apenas runtime controlado e comprovado; `git write-tree` isolado
  seria insuficiente para preservar código parcial não staged;
- `capacity_wait` precisa ser reapropriável por um supervisor novo após crash;
- o horizonte sem progresso e a ação para cadeia esgotada são campos
  obrigatórios da política, sem default oculto adequado apenas ao modo local;
- a prova de campo será automatizada por script, com Codex limitado de forma
  determinística e OpenCode real sobre a worktree descartável.

## 6. Princípios e decisões de desenho

### 6.1 Opt-in explícito e compatibilidade

O default continua sendo `fallback_policy=none`. O failover só existe quando o
manifesto versionado do workflow declara `provider_strategy=explicit_failover`
e uma cadeia ordenada de runners.

Workflows antigos e instalações sem a nova política mantêm exatamente o
comportamento atual. `provider=auto` durante a instalação não autoriza failover
durante a execução.

### 6.2 Autoridade exclusiva do controlador

Somente `ralph-control` pode:

- classificar uma tentativa como apta a failover a partir de resultado
  estruturado;
- abrir ou fechar o circuito de um runner;
- escolher o próximo runner dentro da cadeia autorizada;
- gerar a cápsula de continuidade;
- criar nova `attempt`, lease e fencing token;
- decidir por espera de capacidade ou `recovery_required`.

`ralph.sh`, adapters, hooks, feedback e monitores apenas publicam fatos. Eles
não iniciam outro provider.

### 6.3 Mesma feature, nova tentativa

Failover nunca reutiliza sessão, lease, `attempt` ou `execution_id`. O trabalho
continua na mesma `feature_key`, no mesmo checkout e na mesma árvore parcial,
mas em uma tentativa formalmente nova.

Antes da nova tentativa, o controlador precisa comprovar:

- grupo de processos anterior encerrado;
- lock de execução anterior liberado;
- árvore igual ao fingerprint capturado no encerramento;
- plano e especificação sem drift;
- runner de destino elegível;
- novo fencing token maior que o anterior.

### 6.4 Resultado comum de execução

O control plane não deve procurar frases de rate limit em logs brutos. A seam
será a evolução de `schemas/runner-result.schema.json` para a versão `2.0.0`,
produzida por runners nativos e adapters e importada pelo controlador sob
lease. O schema `1.0.0` específico do OpenCode continua aceito durante a
migração e é normalizado pelo mesmo leitor.

O contrato comum possui, no mínimo:

```json
{
  "schema_version": "2.0.0",
  "workflow_id": "wf_exemplo",
  "feature_key": "FEATURE-001",
  "attempt": 1,
  "execution_id": "exec_exemplo_001",
  "runner": "codex",
  "profile": "codex",
  "failure_domain": "sha256:...",
  "failure_domain_status": "observed",
  "failure_domain_source": "credential_authority_endpoint",
  "status": "usage_limited",
  "reason_code": "provider_usage_limited",
  "classification_confidence": "high",
  "classifier_source": "known_terminal_signature",
  "retry_at": "2026-08-13T18:00:00Z",
  "result_commit": null,
  "result_tree_hash": "sha256:...",
  "artifact_refs": ["artifact_attempt_1_stderr"],
  "error_summary": "limite de uso confirmado"
}
```

Estados mínimos:

```text
completed | failed | interrupted | usage_limited
```

`completed` continua sendo apenas término do runner; não aprova gates. Campos
de política read-only continuam condicionais ao modo `verify`. Assim, há uma
única fonte de verdade para término de runner, sem perder as provas específicas
do OpenCode.

### 6.5 Classificação fail-closed

Somente `reason_code=provider_usage_limited` com
`classification_confidence=high` é elegível na primeira versão.

Uma assinatura terminal conhecida do runner pode produzir confiança alta se:

- vier diretamente do processo do provider, antes dos testes do projeto;
- estiver limitada à superfície terminal prevista;
- não for apenas a presença genérica de `429`;
- registrar versão do classificador e hash do artefato;
- tiver fixture positiva e negativa específica da versão suportada.

Saída ambígua, erro de transporte, texto do projeto ou classificação
`low|unknown` não autoriza failover automático.

### 6.6 Domínios de falha independentes

OpenCode é um harness, não necessariamente um provider independente. Se ele
usar a mesma conta, quota ou backend do Codex, a troca pode repetir exatamente
o mesmo rate limit.

Cada profile informa metadados para resolver um `failure_domain` sanitizado e
sem segredos. O readiness produz também `failure_domain_status`:

```text
exact | observed | declared | unavailable
```

Um failover de capacidade só é automático quando origem e destino possuem
domínios diferentes e ambos estão em `exact|observed`. A identidade deve ser
derivada da autoridade de credencial, endpoint e fingerprint opaco de
conta/projeto quando a CLI os expuser; o valor bruto não é persistido. Um
rótulo fornecido no manifesto permanece `declared` e não basta para automação.
O controlador não infere domínio do nome do modelo nem de um alias OpenCode.

### 6.7 Cápsula de continuidade

O handoff intermediário será uma cápsula de continuidade controlada, distinta
do handoff final de uma feature aprovada. Ela é uma projeção idempotente e
regenerável do ledger, workflow e checkout; não possui fatos exclusivos e não
é fonte de transição.

Local proposto:

```text
.git/ralph-control/continuations/<feature_key>/CNT-<attempt>-<next_attempt>.json
```

Conteúdo permitido:

- IDs de workflow, feature, tentativas, execuções e runners;
- motivo classificado e `retry_at`;
- hash da política de failover;
- commit-base, commit atual e fingerprint da árvore;
- lista relativa de arquivos alterados, sem conteúdo;
- referência à especificação original e seus hashes;
- comando de qualidade;
- critérios de aceitação e evidências esperadas;
- referências sanitizadas aos artefatos;
- resumo factual dos gates já executados, normalmente vazio antes da
  conclusão.

Conteúdo proibido:

- lease token;
- credenciais ou valores de ambiente;
- prompt ou resposta completos;
- diff completo;
- raciocínio privado;
- prova read-only em conteúdo bruto;
- logs brutos.

O runner de destino recebe a especificação original e um resumo gerado a
partir da cápsula. O código parcial continua sendo lido diretamente do
checkout; a cápsula não tenta transportar código por texto.

### 6.8 Continuidade limitada por circuit breakers

Rate limit abre um circuito lógico para o par `runner + failure_domain`. O
estado é derivado do ledger e não exige um banco ou serviço novo.

Estados do circuito:

```text
closed | open | half_open
```

- `closed`: runner elegível;
- `open`: runner excluído até `retry_at` ou cooldown padrão;
- `half_open`: cooldown venceu; um probe seguro decide se ele volta a ser
  elegível para uma nova feature.

Não haverá alternância Codex → OpenCode → Codex dentro da mesma feature. O
runner só muda novamente em nova tentativa e dentro dos limites da política.

## 7. Política versionada do workflow

Forma proposta:

```json
{
  "execution_policy": {
    "provider_strategy": "explicit_failover",
    "provider_chain": [
      {
        "runner": "codex",
        "profile": "codex",
        "required_failure_domain_status": "observed"
      },
      {
        "runner": "opencode",
        "profile": "opencode",
        "required_failure_domain_status": "observed"
      }
    ],
    "failover": {
      "eligible_reasons": ["provider_usage_limited"],
      "short_wait_threshold_seconds": 120,
      "unknown_reset_cooldown_seconds": 1800,
      "max_switches_per_feature": 1,
      "max_no_progress_seconds": 21600,
      "when_chain_exhausted": "capacity_wait_then_recovery"
    }
  }
}
```

O exemplo acima é a recomendação para uma execução local longa. Os limites e
a ação de esgotamento são obrigatórios no manifesto; não existem defaults
ocultos para `explicit_failover`. Um workflow de CI deve preferir horizonte
menor e `when_chain_exhausted=recovery_required`.

| Campo | Valor recomendado no modo local | Justificativa |
|---|---:|---|
| `short_wait_threshold_seconds` | 120 | um reset curto custa menos que trocar contexto e runner |
| `unknown_reset_cooldown_seconds` | 1800 | preserva o fallback temporal já usado pelo loop atual |
| `max_switches_per_feature` | 1 | v1 cobre apenas Codex → OpenCode e impede flapping |
| `max_no_progress_seconds` | 21600 | seis horas sem tentativa concluída exigem diagnóstico humano |
| `when_chain_exhausted` | `capacity_wait_then_recovery` | espera capacidade conhecida, mas não mascara indisponibilidade indefinida |

O validador da política no workflow deve rejeitar:

- cadeia vazia ou runners repetidos;
- `profile` ausente;
- profile cujo readiness devolva domínio vazio, igual ao de outro membro ou
  com status inferior a `observed` em uma política de capacidade;
- motivos não suportados;
- limites ausentes, zero, negativos ou acima do teto operacional definido;
- OpenCode sem modelo explícito, agente de revisão e prova read-only válida;
- estratégia desconhecida.

## 8. Máquina de estados proposta

### 8.1 Caminho com failover

```text
pending
  -> running(attempt=1, runner=codex)
  -> provider_failover_pending
  -> running(attempt=2, runner=opencode)
  -> awaiting_gates
  -> approved
  -> released
```

### 8.2 Caminho com espera curta

```text
running(attempt=1, codex)
  -> capacity_wait
  -> running(attempt=2, codex)
```

Uma política de failover ativa faz `ralph.sh` devolver o `runner-result` ao
controlador, inclusive para reset curto. A retomada usa nova attempt, lease e
fencing, mas não consome ciclo de correção da feature. Workflows sem a política
continuam usando a espera interna legada no mesmo bloco.

### 8.3 Cadeia esgotada

```text
running
  -> capacity_wait
  -> half_open probe
  -> running com runner elegível
```

ou, sem progresso dentro do horizonte:

```text
capacity_wait -> recovery_required
```

O estado `capacity_wait` é persistido no ledger, mas o lock do supervisor não
é sua autoridade durável. Se o supervisor cair, uma nova instância adquire o
lock do SO, reconcilia `retry_at`, o horizonte e a ausência de processos, e
retoma a espera idempotentemente.

### 8.4 Condições que sempre terminam em recovery

- processo anterior ainda observável;
- árvore divergente da cápsula;
- plano ou especificação alterados;
- lease ou fencing incompatível;
- provider de destino não funcional;
- domínios de falha iguais ou desconhecidos;
- prova read-only OpenCode ausente, expirada ou divergente;
- mais de um supervisor ativo;
- resultado de runner sem contrato válido;
- limite de switches ou horizonte sem progresso atingido;
- ledger inválido ou evento conflitante.

## 9. Eventos e projeções

Novos tipos de evento propostos para `RALPH_SCHEMA_VERSION=1.2.0`:

| Evento | Fato registrado | Efeito na projeção |
|---|---|---|
| `provider.capacity_limited` | runner, domínio, classificação, `retry_at`, artefatos | abre circuito e encerra a tentativa atual |
| `continuation.generated` | ID e hash da cápsula, árvore e política | torna a continuidade auditável; não inicia runner |
| `provider.failover_started` | origem, destino, tentativas e novo fencing | entra em `running` na nova attempt |
| `provider.capacity_wait_started` | cadeia indisponível e primeira janela de retry | entra em `capacity_wait` |
| `provider.capacity_wait_finished` | runner revalidado ou horizonte esgotado | volta a `running` ou encaminha a recovery |

Não é necessário persistir eventos separados para cada transição interna do
circuit breaker. A projeção deriva `open|half_open|closed` dos eventos acima,
de `retry_at` e do probe mais recente.

O envelope de evento continua sem prompt, resposta, custo ou lease em claro.
A compatibilidade é unidirecional: o binário novo deve ler ledgers `1.0.0` e
`1.1.0`; binários antigos continuarão rejeitando eventos `1.2.0` por segurança.
A atualização do leitor e da lista de tipos precisa ser promovida antes de
qualquer writer emitir o primeiro evento novo. Tolerar tipo desconhecido
silenciosamente não é permitido porque esconderia transições de autoridade.

## 10. Algoritmo determinístico

### 10.1 Antes do workflow

1. validar o schema da política;
2. executar readiness seguro dos runners declarados;
3. validar profiles e modelo explícito do OpenCode;
4. comparar `failure_domain`;
5. calcular e registrar o hash canônico da política;
6. bloquear a inicialização se o primário não estiver apto;
7. bloquear `explicit_failover` se qualquer membro da cadeia não estiver
   pronto; para executar só com o primário, o manifesto precisa declarar
   explicitamente `fallback_policy=none`.

### 10.2 Ao detectar rate limit

1. importar e validar `runner-result` sob o lease atual;
2. verificar correlação de workflow, feature, attempt e execution;
3. confirmar o término do grupo de processos;
4. registrar `provider.capacity_limited`;
5. se `retry_at - now <= short_wait_threshold_seconds`, encerrar o bloco e
   entrar em espera curta sob o controlador;
6. caso contrário, projetar os circuitos e localizar o próximo runner da
   cadeia;
7. revalidar readiness, profile, failure domain e política do destino;
8. capturar fingerprint canônico de `git status`, diff staged, diff unstaged e
   untracked, excluindo apenas paths de runtime controlados e testados;
9. gerar a cápsula e registrar `continuation.generated`;
10. iniciar `beginProviderFailover()` sob `workflow.lock`;
11. gerar novo lease, attempt, correlation ID e fencing token;
12. registrar `provider.failover_started`;
13. iniciar o runner de destino com a especificação original e o resumo da
    cápsula.

### 10.3 Ao concluir uma feature

1. manter os cinco gates existentes;
2. gerar o handoff final com uma seção `provider_transitions` derivada do
   ledger;
3. registrar runner/modelo efetivos de cada tentativa no trace;
4. atualizar métricas derivadas;
5. selecionar o runner da próxima feature a partir dos circuitos vigentes;
6. retornar ao Codex somente após o cooldown e o probe half-open verde.

## 11. Interfaces propostas

### 11.1 CLI

```text
ralph-control init --workflow <id> --manifest <file>
ralph-control supervise --workflow <id> --max-retries <N>
ralph-control provider-status --workflow <id>
ralph-control failover-plan --workflow <id> --feature <key>
```

`provider-status` e `failover-plan` são somente leitura. Não será criado um
comando manual de troca que ignore a política; uma troca manual precisa usar o
mesmo validador, nova attempt e fencing.

### 11.2 Funções internas

| Seam | Responsabilidade |
|---|---|
| `validateExecutionPolicy()` | schema, cadeia, domínios e limites |
| `validateRunnerResultV2()` | validar resultado estruturado; nunca ler ledger ou escolher destino |
| `projectProviderCircuits()` | derivar elegibilidade do ledger e do tempo atual |
| `selectEligibleRunner()` | escolher o primeiro runner permitido e funcional |
| `generateContinuationCapsule()` | inventário sanitizado e hash do contexto |
| `beginProviderFailover()` | transição atômica, nova attempt, lease e fencing |
| `waitForCapacity()` | heartbeat, cooldown e horizonte sem progresso |

Essa seam permanece interna ao `ralph-control`; não será criado serviço,
daemon ou banco separado.

## 12. Segurança e invariantes

1. Nunca existem dois processos de provider vivos para a mesma feature.
2. Failover só acontece depois do terminal da tentativa anterior.
3. Novo runner significa nova sessão, attempt, lease e fencing.
4. O checkout e a especificação são a fonte de contexto; o handoff é
   sanitizado e complementar.
5. O destino não recebe lease, credencial alheia ou prova de revisão no modo
   de implementação.
6. A prova OpenCode fica apenas no controlador e na sessão read-only.
7. Logs brutos permanecem em artifacts locais com permissão `0600` e entram no
   ledger apenas por referência e hash.
8. Nenhum callback ou feedback escolhe runner.
9. Gate vermelho nunca é convertido em failover de provider.
10. Falha de autenticação nunca troca silenciosamente para outro provider.
11. O mesmo `failure_domain` não é usado como alternativa de capacidade.
12. Qualquer drift entre cápsula e nova tentativa bloqueia o início.
13. Com failover ativo, `ralph.sh` não dorme nem relança o provider após
    `usage_limited`; ele encerra o bloco e devolve a decisão ao controlador.

## 13. Observabilidade e métricas

O monitor deve mostrar:

- runner e attempt atuais;
- circuito por runner;
- motivo e horário do último rate limit;
- destino planejado;
- tempo restante de cooldown;
- quantidade de switches da feature;
- tempo sem progresso;
- último ID de cápsula.

`ralph-metrics` deve derivar, sem mutar o ledger:

- `provider_attempts_total`;
- `provider_failovers_total`;
- `provider_capacity_wait_seconds`;
- `provider_failover_success_total`;
- `provider_failover_exhausted_total`;
- tempo da detecção até a nova tentativa;
- features concluídas após failover;
- taxa de retorno ao primário após cooldown.

Essas métricas não medem custo nem tokens.

## 14. Estratégia de testes

### 14.1 Fixture offline obrigatória

Novo script recomendado: `scripts/test-provider-failover.sh`.

| Cenário | Resultado esperado |
|---|---|
| Codex escreve parcialmente e retorna rate limit confirmado | OpenCode recebe nova attempt e continua sobre a árvore preservada |
| Reset do Codex em até 120s | espera curta; nenhum switch |
| `429` aparece no teste do projeto | não classificar como rate limit do provider |
| Assinatura desconhecida no stderr | `recovery_required`; nenhum failover |
| OpenCode não autenticado | nenhum processo OpenCode iniciado |
| Modelo OpenCode ausente | preflight bloqueia antes da chamada à CLI |
| Prova read-only divergente | implementação não é liberada pelos gates |
| Mesmo `failure_domain` | destino recusado |
| Processo Codex ainda vivo | failover recusado |
| Árvore muda após a cápsula | failover recusado por drift |
| Evento repetido | transição idempotente; uma única nova attempt |
| Lease antigo tenta escrever | fencing rejeita o evento |
| Supervisor cai entre cápsula e nova attempt | `continue` reconcilia sem duplicar processo |
| Codex e OpenCode limitados com reset conhecido | `capacity_wait` com heartbeat e retomada |
| Cadeia sem progresso por seis horas simuladas | `recovery_required` |
| Gate de qualidade falha | systematic debugging; nenhum failover |
| Política ausente | comportamento legado `fallback_policy=none` |
| Capsule/artifacts contêm segredo-canário | teste falha |

O relógio deve ser injetável nas fixtures; a suíte não deve dormir por tempo
real para testar cooldown.

### 14.2 Regressões existentes

Executar pelo menos:

```bash
bash scripts/check-shell.sh
bash scripts/check-doc-sync.sh
bash scripts/test-feedback.sh
bash scripts/test-provider-readiness.sh
bash scripts/test-multiprovider.sh
bash scripts/test-opencode-policy.sh
bash scripts/test-opencode-adapter.sh
bash scripts/test-opencode-adversarial.sh
bash scripts/test-ralph-method.sh
bash scripts/test-ralph.sh
bash scripts/ci-portable.sh
```

`test-multiprovider.sh` deve continuar provando `fallback_policy=none` para
workflows sem opt-in e adicionar uma fixture separada para `explicit_failover`.

### 14.3 Pane e concorrência

Injetar:

- SIGTERM e SIGKILL antes e depois de `provider.capacity_limited`;
- queda entre `continuation.generated` e `provider.failover_started`;
- dois supervisores tentando consumir a mesma cápsula;
- processo órfão do runner anterior;
- ledger truncado no novo evento;
- timeout durante o probe half-open;
- saída acima do limite de captura;
- OpenCode criando bootstrap inesperado;
- relógio avançando durante o lock.

Toda pane precisa terminar em retomada idempotente ou `recovery_required`,
nunca em dois processos ou avanço de feature.

### 14.4 Prova de campo

Executar por um novo script reproduzível,
`scripts/test-provider-failover-field.sh`, em worktree descartável do
`refactor-radar`, nunca na `main` ativa:

1. instalar/evoluir o Ralph Method candidato;
2. usar Codex primário e OpenCode com modelo e domínio distintos;
3. usar um shim Codex versionado na fixture para injetar `usage_limited`
   determinístico após uma alteração parcial controlada;
4. comprovar a nova attempt OpenCode sobre a mesma árvore;
5. executar `bin/check` real;
6. concluir os cinco gates e gerar handoff final;
7. verificar trace com as duas execuções e fencing distinto;
8. confirmar ausência de segredos e processos órfãos;
9. desinstalar ou descartar a worktree conforme o manifesto.

Um rate limit real não é requisito do teste de campo porque não é reproduzível.
A classificação exata fica provada por fixture; o campo automatizado prova a
continuidade com OpenCode real e `bin/check` real. Execução manual não satisfaz
o gate de promoção.

## 15. Fases de implementação

### Fase 0 — contrato e testes vermelhos

- evoluir `runner-result` e adicionar o contrato de política;
- adicionar fixture da política e do `runner-result` v2;
- proteger o default `none`;
- criar testes vermelhos para classificação, domínios e transições;
- registrar versão e compatibilidade do ledger.

Critério de saída: contratos falham corretamente sem implementação e não
quebram workflows legados.

### Fase 1 — runner-result comum e classificação Codex

- fazer o runner nativo publicar resultado estruturado;
- separar rate limit de falha genérica;
- registrar `retry_at`, confiança, fonte e artefatos;
- manter o comportamento de espera atual somente em workflows sem opt-in; a
  política nova ainda não é habilitada nesta fase.

Critério de saída: classificação positiva e todos os falsos positivos da
matriz estão cobertos.

### Fase 2 — política, circuitos e seleção somente leitura

- validar `execution_policy`;
- projetar circuitos do ledger;
- implementar `provider-status` e `failover-plan` read-only;
- validar readiness e `failure_domain`.

Critério de saída: o controlador explica deterministicamente qual runner seria
escolhido, sem iniciar provider.

### Fase 3 — cápsula e nova autoridade

- gerar cápsula atômica com permissão `0600`;
- implementar `beginProviderFailover()`;
- criar nova attempt, lease e fencing;
- bloquear processo vivo, drift e replay;
- recuperar crash entre cápsula e tentativa.

Critério de saída: fixture prova exclusividade e preservação da árvore sem
chamar OpenCode real.

### Fase 4 — continuidade Codex → OpenCode

- integrar seleção ao supervisor;
- revalidar profile, modelo, agente e proof;
- montar o prompt de continuidade sanitizado;
- executar implementação e revisão OpenCode em sessões separadas;
- fazer o adapter OpenCode publicar o mesmo contrato v2.

Critério de saída: fixture offline completa a mesma feature em nova attempt e
passa pelos gates.

### Fase 5 — espera de capacidade e fila longa

- implementar cooldown, half-open e heartbeat;
- manter OpenCode como runner das features seguintes enquanto o Codex estiver
  aberto;
- retornar ao Codex somente após probe seguro;
- aplicar horizonte sem progresso e cadeia esgotada.

Critério de saída: workflow com várias features continua sem flapping e para
somente no circuito de segurança.

### Fase 6 — handoff, trace, monitor e métricas

- incluir `provider_transitions` no handoff final;
- projetar tentativas no trace;
- publicar estado no monitor;
- adicionar métricas read-only;
- sanitizar todos os novos artifacts.

Critério de saída: operador consegue reconstruir a troca sem ler logs brutos.

### Fase 7 — adversarial, pane e regressão

- executar a matriz de panes;
- revisar classificação, processo, fencing e secrets;
- rodar a CI portátil completa;
- corrigir todo finding crítico ou alto antes do campo.

Critério de saída: nenhuma pane causa processo concorrente, avanço indevido ou
perda silenciosa da árvore.

### Fase 8 — campo, promoção e documentação operacional

- executar a worktree do `refactor-radar`;
- publicar relatório sanitizado;
- atualizar `STATUS`, `AGENT_GUIDE`, changelog e exemplos somente depois da
  prova;
- promover a release pelo fluxo do Ralph.

Critério de saída: cinco gates, campo real, revisão independente e regressão
pós-merge verdes.

## 16. Mapa inicial de arquivos

| Área | Arquivos esperados |
|---|---|
| Contratos | `schemas/runner-result.schema.json` v2 e novo `schemas/execution-policy.schema.json` referenciado pelo workflow |
| Control plane | `bin/ralph-control` |
| Loop nativo | `scripts/ralph.sh` |
| OpenCode | `adapters/opencode/runner.sh`, `adapters/opencode/parser.php` |
| Handoff | `scripts/ralph-generate-handoff.sh`, projeção em `bin/ralph-control` |
| Observabilidade | `bin/ralph-monitor`, `bin/ralph-metrics`, `schemas/feedback-event.schema.json` se necessário |
| Instalação/perfis | `bin/ralph-init`, `.ralph/*.env` gerados |
| Testes | novos `scripts/test-provider-failover.sh` e `scripts/test-provider-failover-field.sh`, além das regressões existentes |
| Documentação pós-implementação | `docs/STATUS.md`, `docs/AGENT_GUIDE.md`, arquitetura, ADR, roadmap e changelog |

O mapa é um orçamento de toque, não autorização para alterar todos os arquivos.
Cada fase deve confirmar a necessidade real antes de expandir o diff.

## 17. Critérios de aceite da evolução

### Funcionais

- Codex → OpenCode ocorre automaticamente apenas para `usage_limited`
  confirmado;
- a mesma feature continua em nova attempt sobre a árvore parcial;
- a fila segue para as próximas features enquanto houver runner elegível;
- cooldown curto prefere espera à troca;
- cadeia esgotada espera capacidade antes de exigir ação humana.

### Integridade

- nenhum lease ou fencing é reutilizado;
- nenhum runner anterior permanece vivo;
- plano, especificação e árvore são protegidos por hashes;
- eventos duplicados não criam duas tentativas;
- ledger histórico permanece legível;
- gates continuam sendo a única aprovação.

### Segurança

- nenhum segredo, prompt ou resposta integral entra em ledger, capsule,
  feedback ou handoff;
- destino só é usado com readiness e profile comprovados;
- failure domains precisam ser diferentes;
- proof read-only é validada antes da revisão OpenCode;
- nenhum fallback ocorre para autenticação, erro genérico ou gate vermelho.

### Evidência

- fixture offline determinística;
- regressão completa verde;
- matriz de panes verde;
- revisão adversarial independente;
- teste de campo no `refactor-radar` em worktree descartável;
- relatório sanitizado e handoff final com transições de provider.

## 18. Riscos e mitigação

| Risco | Mitigação |
|---|---|
| Falso positivo de rate limit | `runner-result` estruturado, confiança alta, assinatura versionada e teste negativo com `429` do projeto |
| OpenCode usar a mesma quota | `failure_domain` distinto e observado pelo readiness, nunca apenas declarado |
| Duas sessões escreverem juntas | processo anterior encerrado, execution lock, nova attempt e fencing |
| Handoff ficar stale | capsule com hashes e revalidação imediatamente antes do spawn |
| Flapping entre runners | cadeia ordenada, circuit breaker e um switch por feature |
| Espera eterna sem capacidade | horizonte sem progresso e `recovery_required` |
| Target funcional no início e inválido na troca | readiness repetido no momento do failover |
| Perda de contexto | especificação original + checkout parcial + capsule sanitizada |
| Provider mudar contrato de saída | classifier versionado, fixture e falha fechada |
| Política enfraquecer segurança | hash canônico, schema e rejeição de drift |
| Complexidade excessiva no núcleo | seam interna no controlador, sem daemon, banco ou fila novos |

## 19. Decisões adiadas e gatilhos

| Evolução futura | Decisão atual | Gatilho para revisitar |
|---|---|---|
| Claude como terceiro runner | fora da v1 | dois incidentes em que Codex e OpenCode compartilhem indisponibilidade e Claude esteja comprovadamente independente |
| Failover por erro de transporte | bloquear | taxonomia reproduzível distinguir indisponibilidade transitória de configuração inválida com taxa de falso positivo zero nas fixtures suportadas |
| Troca de modelo dentro do mesmo runner | bloquear | provider expor contrato estruturado de quota por modelo e identidade efetiva comprovável |
| Estado distribuído | manter ledger local | necessidade real de coordenar o mesmo workflow entre hosts diferentes |
| Política adaptativa por custo | fora do escopo | telemetria de custo autorizada, sanitizada e requisito explícito de orçamento |
| Paralelismo especulativo | rejeitado | não há gatilho previsto; viola a exclusividade por feature |

## 20. Definição de concluído

O plano só estará implementado quando todas as fases 0–8 estiverem verdes e a
documentação deixar explicitamente de marcar o comportamento como proposto.
Até lá, a verdade operacional permanece:

```text
fallback_policy=none
rate limit -> esperar o mesmo runner ou recovery explícito
```

## 21. Bootstrap e execução futura pelo próprio Ralph

O workflow candidato foi preparado para self-hosting, mas não deve ser
inicializado enquanto estes documentos estiverem sem commit ou houver outro
workflow ocupando o runtime do Git common dir. O `ralph-control` aceita um
único workflow por runtime e não deve ter seu ledger movido, apagado ou
substituído manualmente.

A forma recomendada é criar um clone Git dedicado do próprio `ralph-method`,
em branch própria, depois que este plano estiver versionado. Um worktree do
mesmo clone não isola o runtime atual porque o controlador usa o Git common
dir. O clone dedicado preserva o workflow histórico e ainda executa a mudança
no próprio projeto Ralph Method.

Nesse clone, a sequência de bootstrap é:

```bash
git status --short --branch
bin/ralph-control init \
  --workflow wf_provider_failover_20260813_001 \
  --manifest .spec/features/094-provider-failover/workflow.json

bin/ralph-control supervise \
  --workflow wf_provider_failover_20260813_001 \
  --engine codex \
  --test-cmd "bash scripts/ci-portable.sh" \
  --interval 30 \
  --max-retries 3
```

O manifesto candidato não declara `execution_policy`: essa ausência é
intencional, porque a capacidade é implementada pelas fases 1–6. Portanto, a
construção começa e permanece no runner Codex. OpenCode participa somente das
fixtures e da prova de continuidade até a política estar implementada,
habilitada por opt-in e validada.

Em outro terminal, o acompanhamento permanece read-only:

```bash
bin/ralph-monitor \
  --workflow wf_provider_failover_20260813_001 \
  --interval 30
```

Antes do primeiro `supervise`, precisam estar verdes:

- árvore limpa e branch dedicada;
- manifesto aceito por `ralph-control init`;
- `.ralph/codex.env` e runner Codex funcionais;
- `bash scripts/ci-portable.sh` verde no commit-base;
- nenhuma credencial ou configuração local adicionada ao commit;
- runtime sem workflow concorrente.

A troca Codex → OpenCode não será usada para construir a si própria antes de
estar pronta. A primeira execução em que o failover pode ser habilitado é a
fixture controlada da fase 5; a primeira prova real é a fase 9.
