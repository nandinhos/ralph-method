# Fronteiras do Ralph Method

| Componente | Pode fazer | Não pode fazer |
|---|---|---|
| `ralph-control` | validar estado, lease, fencing, gates e avanço | delegar autoridade ao hook ou provider |
| `ralph-trace` | registrar fatos de execução e projetar relatório | alterar estado ou iniciar feature |
| `ralph-monitor` | observar processos e publicar snapshot | aprovar, retry ou liberar lease |
| `ralph.sh` | criar sessões e executar fases | concluir por parsing de log |
| canal de feedback | publicar fatos sanitizados ao consumidor externo | alterar estado, gate, lease ou fila |
| relay do `ralph-control` | retransmitir feedback durante o bloco | interpretar feedback como aprovação |
| adaptador provider | converter saída externa para contrato trace | escrever ledger ou alterar código |
| `ralph-init` | detectar contexto, instalar e remover bundle com ownership | copiar credenciais, remover histórico ou sobrescrever arquivos sem ownership |
| projeto-alvo | fornecer contexto, fases e comando de teste | depender do banco ou domínio do Ralph |

## Instalação e remoção

O `install-manifest.json` é a fronteira de ownership. Cada arquivo instalado
recebe hash de origem e hash efetivamente instalado. Na remoção, um arquivo
modificado é preservado e listado como `preserve_modified`; somente um arquivo
inalterado e pertencente ao manifesto pode ser removido. A desinstalação não
remove `.git/ralph-control`, `.ralph/workflow.json`, handoffs nem relatórios.

O `bc-harness` pode distribuir o instalador, mas não é necessário em runtime.
Depois de instalado, o projeto-alvo possui cópia própria do método e pode
desinstalá-la sem apagar suas evidências.

## Seam de providers

O contrato comum é um fato sanitizado de delegação entregue ao
`ralph-trace record`. A implementação inicial pode usar somente Codex; cada
provider adicional entra atrás do mesmo contrato.

| Future | Seam atual | Trigger |
|---|---|---|
| Claude | adapter de saída + runner selecionável | fixture e smoke CLI verdes |
| OpenCode | adapter de saída + runner selecionável | saída normalizada com sessão/modelo ou identidade parcial |
| Hermes/agy | delegação filha registrada no trace | provider instalado e contrato de execução definido |
| instalação remota | manifesto local com hashes | necessidade de vários hosts compartilhando estado |
