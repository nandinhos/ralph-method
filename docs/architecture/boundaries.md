# Fronteiras do Ralph Method

| Componente | Pode fazer | Não pode fazer |
|---|---|---|
| `ralph-control` | validar estado, lease, fencing, gates e avanço | delegar autoridade ao hook ou provider |
| `ralph-trace` | registrar fatos de execução e projetar relatório | alterar estado ou iniciar feature |
| `ralph-monitor` | observar processos e publicar snapshot | aprovar, retry ou liberar lease |
| `ralph.sh` | criar sessões e executar fases | concluir por parsing de log |
| canal de feedback | publicar fatos sanitizados ao consumidor externo | alterar estado, gate, lease ou fila |
| relay do `ralph-control` | retransmitir feedback durante o bloco | interpretar feedback como aprovação |
| adaptador provider | converter saída externa para contrato trace e reportar política comprovada | escrever ledger ou alterar código |
| `ralph-init` | detectar contexto, instalar e remover bundle com ownership | copiar credenciais, remover histórico ou sobrescrever arquivos sem ownership |
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

## Seam de providers

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

| Future | Seam atual | Trigger |
|---|---|---|
| Claude | adapter de saída + runner selecionável após prontidão | fixture, probe seguro e smoke CLI verdes |
| OpenCode | adapter de saída + runner selecionável após prontidão | fixture real, política read-only, saída normalizada, prova de capability/processo e probe seguro; dono: Equipe Ralph Method |
| Hermes/agy | delegação filha registrada no trace após diagnóstico suportado | provider instalado, backend identificado e contrato de execução definido |
| instalação remota | manifesto local com hashes | necessidade de vários hosts compartilhando estado |
