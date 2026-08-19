# Relatório 0031 — verificação do sistema para a UI de acompanhamento por projeto

**Data:** 2026-08-19
**Versão verificada:** `0.10.0`
**Commit verificado:** `ab7db89`
**Branch:** `main`
**Escopo:** diagnóstico somente leitura do núcleo e das fontes de dados que uma
interface de acompanhamento precisaria consumir em cada projeto onde o Ralph
Method está instalado. Nenhum comportamento do control plane foi alterado.

## 1. Resultado da verificação do núcleo

Ambiente usado: PHP 8.2.33, bash 5.1.16, shellcheck 0.8.0, bwrap 0.6.1,
`jsonschema` 4.26 (Python). `scripts/ci-portable.sh` executado por inteiro.

| Verificação | Resultado |
|---|---|
| `check-doc-sync.sh`, `check-shell.sh` | verde |
| `test-installation`, `test-reproducibility`, `test-feedback` | verde |
| `test-provider-readiness`, `test-multiprovider` | verde |
| `test-ralph-method`, `-reconciliation`, `-multi-cycle`, `-noop-approval` | verde |
| `test-ralph-knowledge`, `test-ralph-metrics`, `test-ralph` (167 asserts) | verde |
| `test-opencode-policy/-adapter`, `test-agy-*`, `test-cursor-adapter` | verde |
| `test-ralph-gates-native`, `-gate-recovery`, `test-evolution-filesystem` | verde |
| `test-provider-failover` | **vermelho na Phase 8.4** (ver D10) |

Duas dependências não estão declaradas em lugar nenhum do repositório e
quebram a regressão em máquina limpa antes de qualquer teste do método:
`python3-jsonschema` precisa ser `>= 4.18` (o pacote da distro traz 3.2 e
`Draft202012Validator` não existe) e o `php` precisa ser 8.2 (o guia e a CI
usam 8.2, mas nada no repositório verifica a versão local).

## 2. Estado real da interface

Não existe implementação de UI. O único artefato é
`docs/mockups/ralph-trace-web.html` (254 linhas, adicionado em `6d579fc`), um
HTML estático com dados fictícios embutidos no markup. O script da página tem
somente um filtro de exibição da timeline e um botão "Atualizar snapshot" que
troca o próprio rótulo por 1,6 s. Não há fetch, endpoint, arquivo de origem,
parâmetro de projeto nem qualquer ligação com o ledger. A branch remota
`feat/trace-cockpit` não contém código de interface: seus dois commits tratam
do incidente 0018.

Consequência prática: hoje não é possível acompanhar o andamento de nenhum
projeto pela interface; o acompanhamento só existe via `bin/ralph-monitor`
(texto/JSON no terminal) e `bin/ralph-metrics`.

## 3. Fontes de dados disponíveis por projeto

Todas locais ao checkout do projeto-alvo, todas somente leitura:

| Fonte | Caminho | Conteúdo útil para a UI |
|---|---|---|
| Estado do workflow | `<git-common-dir>/ralph-control/workflow.json` | `workflow_id`, features, branch, `execution_policy` |
| Ledger | `<git-common-dir>/ralph-control/events.jsonl` | hash chain de todos os fatos, com `timestamp`, `type`, `attempt`, `facts` |
| Snapshot do monitor | `<git-common-dir>/ralph-control/monitor/latest.json` | saúde, progresso, último evento, circuitos de provider |
| Feedback do loop | `<git-common-dir>/ralph-control/feedback/events.jsonl` | fase, ciclo, percentual, engine (`schemas/feedback-event.schema.json`) |
| Instalação | `.ralph/method.json`, `.ralph/install-manifest.json` | versão do método, projeto, componentes instalados |
| Handoffs | `.ralph/handoffs/<FEATURE>/` | resumo de execução, manifesto de evidências |
| Projeção | `ralph-control status` | features com estado, posição, tentativa e gates por nome |
| Agregados | `ralph-metrics --workflow <id>` | gates aprovados/rejeitados, recuperações, durações, failovers |
| Delegação | `ralph-control trace-report` | árvore de executores |
| Conhecimento | `ralph-knowledge` | lições e índices |

O dado necessário existe; o que falta é um contrato único e a superfície que o
entrega.

## 4. Mockup × dado real

| Elemento do mockup | Fonte real | Situação |
|---|---|---|
| Workflow, branch | `workflow.json` | disponível |
| "Último evento há Ns" | `snapshot.last_event.age_seconds` | disponível |
| Anel de % do workflow | `snapshot.progress.estimated_percent` | disponível |
| Features `2 / 3` | `snapshot.completed_features/total_features` | disponível |
| Estado de saúde | `snapshot.health` | disponível, porém incorreto (D1, D2) |
| Lista/sequência de features com estado e duração | projeção do `status` + `ralph-metrics` | **descartado pelo snapshot** (D3) |
| Cinco gates com nome, detalhe e tempo | `projection.features[].gates` | **descartado pelo snapshot** (só a contagem) (D3) |
| "Gates verdes 10" e "Recovery 2" | `ralph-metrics` | segunda fonte, fora do snapshot (D4) |
| "Tempo ativo 01:42:18" | derivável do primeiro evento do ledger | **não existe** em nenhuma saída (D4) |
| "attempt 5 · OpenCode" (runner atual) | `facts` dos eventos de delegação | **não existe** no snapshot (D5) |
| Timeline de eventos | `events.jsonl` | só o último evento é exposto (D3) |
| Memória de engenharia | `ralph-knowledge` | terceira fonte |
| Árvore de delegação | `ralph-control trace-report` | quarta fonte |
| Botões de filtro/atualizar | — | sem binding (D6) |
| Seleção de projeto | — | **não existe** (D7, D8) |

Uma UI honesta ao contrato atual precisaria orquestrar quatro comandos
diferentes por projeto e ainda assim ficaria sem gates por nome, sem timeline e
sem tempo de execução.

## 5. Defeitos encontrados

**D1 — o monitor conta observadores como processo de execução.**
`bin/ralph-monitor:188` aceita qualquer linha de `ps` que contenha o
`workflow_id` e case com `ralph-control|ralph.sh|ralph-block|ralph-bloco`.
Comprovado em fixture: um `ralph-control status --workflow <id>` read-only e o
próprio `bash -c` do observador aparecem em `processes`. Uma UI que consulte o
projeto passa a "provar" que há execução viva, e o health `process_missing`
deixa de ser alcançável enquanto a UI estiver aberta.

**D2 — estados do failover não têm saúde própria.**
O `match` de `bin/ralph-monitor:321` não conhece `capacity_wait` nem
`provider_failover_pending` (introduzidos pela FEATURE-094) nem os estados de
conhecimento. Comprovado em fixture: workflow parado em `capacity_wait`
aguardando capacidade até 2030 é publicado como `health: ok`, com a mensagem
"execução acompanhada normalmente".

**D3 — o snapshot achata a projeção.** Ele reduz os gates a um contador
(`passed_gates`) e a lista de features a `total/completed`, descartando
`gates` por nome, `position`, `state` por feature e o histórico de eventos.
São exatamente os três blocos centrais do mockup.

**D4 — não há linha do tempo nem agregados no snapshot.** Sem
`started_at`/`elapsed_seconds` do workflow e sem contadores de recovery e
failover, "Tempo ativo" e "Recovery" só saem de um segundo processo
(`ralph-metrics`), que relê o ledger inteiro.

**D5 — o runner/provider corrente não é publicado.** Existe em `facts` dos
eventos de delegação e em `provider_circuits`, mas não como campo do estado
atual.

**D6 — o mockup não é implementação.** Dados fixos no HTML, sem origem, sem
schema, sem atualização. Não há como "corrigir" a UI: ela precisa ser
implementada a partir de um contrato.

**D7 — não há índice de projetos.** A instalação é por projeto e sem estado
global do produto (README). Nenhum componente sabe quais projetos usam o
método, então uma visão "por projeto" precisa de uma decisão nova e explícita
sobre descoberta/registro.

**D8 — o monitor exige `--workflow`.** O id já está em `workflow.json`, mas
não há `--discover`, nem um comando que liste workflows conhecidos do
checkout; a UI teria de ler o arquivo por fora do contrato.

**D9 — resíduo em `doneStates`.** `bin/ralph-monitor:307` conta
`knowledge_pending|knowledge_curated|knowledge_skipped` como estados de
feature, mas a projeção grava isso em `knowledge_state`; o ramo é morto e
induz a leitura errada do progresso.

**D10 — `test-provider-failover.sh` Phase 8.4 falha de forma reproduzível.**
O teste mata o PID do subshell (`scripts/test-provider-failover.sh:1293`), não
o `php ralph-control supervise` filho. O filho sobrevive, mantém o `flock` do
supervisor, e a retomada aborta com `erro: já existe um supervisor ativo para
este checkout` (exit 12). Reproduzido em PHP 8.1 e 8.2. O invariante que a
Phase 8.4 diz provar (retomada idempotente após SIGKILL) hoje não é provado.

## 6. Correção proposta

A ordem abaixo mantém a fronteira do método: a interface observa, nunca aprova
gate, nunca altera lease, nunca inicia feature.

**F0 — destravar a verificação.** Corrigir a Phase 8.4 para matar o grupo de
processos (`setsid` + `kill -KILL -PGID`) e declarar as dependências
(`php 8.2`, `jsonschema >= 4.18`) na CI e no guia.

**F1 — contrato do snapshot (`schemas/monitor-snapshot.schema.json` 1.0.0).**
Publicar em `bin/ralph-monitor --json` um documento versionado com: workflow,
projeto, `started_at`/`elapsed_seconds`, features com `position`, `state`,
`attempt` e `gates` por nome, runner corrente, contadores de recovery e
failover, circuitos de provider e as N últimas linhas do ledger já
sanitizadas. Junto: corrigir D1 (só processo com lease/heartbeat do próprio
workflow conta), D2 (saúde para `capacity_wait`, `provider_failover_pending` e
conhecimento), D5 e D9.

**F2 — descoberta local.** `ralph-monitor --discover` resolve o `workflow_id`
pelo `workflow.json` do checkout, para a UI não depender de conhecer o id.

**F3 — visão multi-projeto.** Decisão explícita em ADR: ou a UI recebe
`--project` repetível (sem estado global do produto), ou existe um
índice do usuário (`~/.config/ralph-method/projects.json`) alimentado por
opt-in no `ralph-init apply/uninstall`. Recomendo começar por `--project`
repetível e só depois avaliar o índice.

**F4 — a interface.** Substituir o mockup por uma página gerada a partir do
schema de F1, servida por um comando somente leitura
(`ralph-ui serve --project <p> [--project <p>]` ou
`ralph-monitor --emit-html`), com atualização por polling do próprio snapshot,
sem escrita e sem rede externa. Lista de projetos → workflow → features →
gates → timeline.

**F5 — regressão.** `scripts/test-monitor-snapshot.sh` validando o schema e
cada `health` por fixture; teste de render da UI sem rede; sincronizar
`AGENT_GUIDE`, `STATUS` e `CHANGELOG`.

## 7. Estado da implementação

Decisão do responsável: `--project` repetível agora, índice do usuário depois.
Esta entrega fecha F0–F5 na forma stateless; o índice em
`~/.config/ralph-method/projects.json` continua fora de escopo.

| Item | Estado | Onde |
|---|---|---|
| D1 observador contado como runner | corrigido | `monitorIsRunnerProcess()`; observador vivo não esconde `process_missing` |
| D2 saúde de `capacity_wait`/failover | corrigido | `monitorHealth()` publica `capacity_wait` e `provider_failover` |
| D3 snapshot achatado | corrigido | `features` com `state`, `attempt`, `knowledge_state` e gates por nome |
| D4 sem timeline nem agregados | corrigido | `timeline` (recorte declarado) e `progress` |
| D5 runner corrente ausente | corrigido | `runner` derivado de delegação e failover |
| D6 mockup sem dados | corrigido | painel servido por `ralph-monitor serve`, alimentado pela API local |
| D7 sem visão multi-projeto | corrigido na forma A | `--project` repetível, um cartão por checkout |
| D8 `--workflow` obrigatório | corrigido | descoberta em `<git-common-dir>/ralph-control/workflow.json` |
| D9 resíduo em `doneStates` | corrigido | terminais são `approved` e `released` |
| D10 Phase 8.4 não provava a retomada | corrigido | `exec php` no subshell: o SIGKILL atinge o supervisor, não o shell |

A correção de D10 não foi por grupo de processos como previsto em F0: bastou
`exec` no subshell para que o PID capturado fosse o do supervisor. `setsid` +
`kill -PGID` mataria também o que o teste ainda precisa observar.

O contrato é `schemas/monitor-snapshot.schema.json` (`schema_version` 1.0.0) e a
regressão é `scripts/test-monitor-ui.sh`, já na CI portátil. Ela prova o schema,
a descoberta do workflow, a distinção observador/runner com processo real, a
classificação de saúde, o isolamento de projeto inválido, a recusa de escrita
(405/404) e a integridade do ledger depois do painel.

Fora de escopo desta entrega, na ordem sugerida: índice do usuário (F3-B),
`started_at`/`elapsed_seconds` no contrato, e contadores históricos de recovery
e failover no snapshot — hoje eles vivem só no `ralph-metrics`.

## 8. Não-objetivos

Nenhuma ação de controle na interface, nenhum estado global obrigatório,
nenhum dado sensível (prompt, token, resposta) na superfície observável.
