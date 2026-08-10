# Fronteiras do Ralph Method

| Componente | Pode fazer | Não pode fazer |
|---|---|---|
| `ralph-control` | validar estado, lease, fencing, locks de workflow e execução, gates e avanço | delegar autoridade ao hook ou provider |
| `ralph-trace` | registrar fatos de execução e projetar relatório | alterar estado ou iniciar feature |
| `ralph-monitor` | observar processos e publicar snapshot | aprovar, retry ou liberar lease |
| `ralph.sh` | criar sessões e executar fases | concluir por parsing de log |
| canal de feedback | publicar fatos sanitizados ao consumidor externo | alterar estado, gate, lease ou fila |
| relay do `ralph-control` | retransmitir feedback durante o bloco | interpretar feedback como aprovação |
| adaptador provider | converter saída externa para contrato trace e reportar política comprovada | escrever ledger ou alterar código |
| `ralph-init` | detectar contexto, instalar/remover bundle com ownership e executar evolução explícita com backup/rollback | copiar credenciais, remover histórico, importar runtime desconhecido, sobrescrever arquivos sem ownership ou liberar rollback com drift |
| verificador de provider | executar probes seguros explícitos e materializar prontidão | iniciar geração, salvar saída sensível ou habilitar adapter sem diagnóstico |
| projeto-alvo | fornecer contexto, fases e comando de teste | depender do banco ou domínio do Ralph |

## Instalação e remoção

O `install-manifest.json` é a fronteira de ownership. Cada arquivo instalado
recebe hash de origem e hash efetivamente instalado. Na remoção, um arquivo
modificado é preservado e listado como `preserve_modified`; somente um arquivo
inalterado e pertencente ao manifesto pode ser removido. A desinstalação não
remove `.git/ralph-control`, `.git/ralph-control/workflow.json`, handoffs nem
relatórios.

O `bc-harness` pode distribuir o instalador, mas não é necessário em runtime.
Depois de instalado, o projeto-alvo possui cópia própria do método e pode
desinstalá-la sem apagar suas evidências.

Antes do `apply`, o instalador executa uma detecção somente leitura de sinais
de um Ralph que não pertence ao manifesto do método. A saída usa caminhos
relativos, tipos e SHA-256, sem conteúdo. Sinal canônico ou combinação de
sinais gera bloqueio fail-closed; uma pasta `.ralph` sem marcador conhecido é
insuficiente para bloquear. A evolução com backup e rollback é uma operação
explícita, separada do `apply` comum. Ela opera em modo `quarantine_only`:
não traduz estado legado, mantém sinais de runtime e exige aceite ou rollback
após a instalação nova.

## Seam de harnesses e providers

O contrato comum é um fato sanitizado de delegação entregue ao
`ralph-trace record`. A implementação inicial pode usar somente Codex; cada
provider adicional entra atrás do mesmo contrato. Antes disso, o instalador
aplica o contrato de prontidão em `schemas/provider-readiness.schema.json`.
Executável encontrado, autenticação isolada ou versão conhecida não habilitam
um adapter.

O probe da primeira versão é explícito (`--verify-providers`), não generativo,
tem timeout e não publica a saída bruta. `functional` certifica a CLI;
`adapter_enabled=true` exige também um runner implementado para ela.
`needs_review` é preservado quando não há runner apto.

| Harness | Seam atual | Estado |
|---|---|---|
| Codex | runner nativo selecionável após prontidão | fechado e coberto pela regressão do loop |
| Claude CLI | runner nativo selecionável após prontidão | fechado e coberto pela regressão do loop |
| OpenCode | adapter de saída + runner selecionável após prontidão | fechado; fixture real, política read-only, saída normalizada, prova de processo e campo verde |
| Hermes/agy | delegação filha registrada no trace após diagnóstico suportado | backlog, prioridade nenhuma |
| instalação remota | manifesto local com hashes | necessidade de vários hosts compartilhando estado |

## Exclusividade de execução

O controlador mantém um lock de execução por `workflow_id + feature_key` em
`.git/ralph-control/executions/`. O lock fica adquirido durante todo o bloco
controlado e impede que dois processos usem o mesmo checkout para executar a
mesma feature simultaneamente. O `workflow.lock` continua protegendo cada
mutação curta do estado e do ledger; ele não fica retido durante a chamada ao
provider.

O bloqueio é fail-closed: uma segunda execução recebe erro e não inicia
provider, não cria processo e não altera a fila. O lock é local ao checkout e
não é uma autorização para executar features diferentes em paralelo.
