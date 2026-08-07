# Fronteiras do Ralph Method

| Componente | Pode fazer | Não pode fazer |
|---|---|---|
| `ralph-control` | validar estado, lease, fencing, gates e avanço | delegar autoridade ao hook ou provider |
| `ralph-trace` | registrar fatos de execução e projetar relatório | alterar estado ou iniciar feature |
| `ralph-monitor` | observar processos e publicar snapshot | aprovar, retry ou liberar lease |
| `ralph.sh` | criar sessões e executar fases | concluir por parsing de log |
| adaptador provider | converter saída externa para contrato trace | escrever ledger ou alterar código |
| `ralph-init` | detectar contexto e instalar bundle local | copiar credenciais ou sobrescrever arquivos alheios |
| projeto-alvo | fornecer contexto, fases e comando de teste | depender do banco ou domínio do Ralph |

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
