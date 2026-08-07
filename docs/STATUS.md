# Status do Ralph Method

## Estado atual

O repositório foi criado como extração independente do núcleo Ralph validado
no `refactor-radar`. O control plane, trace, monitor, bloco, hooks e wrappers
de gates já estão presentes. A primeira versão do framework é `0.1.0`.

## Componentes extraídos

| Componente | Path | Responsabilidade |
|---|---|---|
| Control plane | `bin/ralph-control` | estado, lease, fencing, gates e ledger |
| Trace | `bin/ralph-trace` | fatos de delegação e relatório `TRC` |
| Monitor | `bin/ralph-monitor` | snapshot operacional sem transição |
| Bloco | `bin/ralph-block`, `bin/ralph-bloco` | uma feature por execução |
| Loop | `scripts/ralph.sh` | sessões por fase e gates externos |
| Hook | `scripts/ralph-hook.sh` | observabilidade best-effort |

## Próxima entrega

Implementar `ralph-init plan/apply`, `ralph-doctor`, manifesto de instalação e
registro de capabilities dos providers. A instalação deve ser local,
idempotente, atômica e sem sobrescrever arquivos que não pertençam ao Ralph.

## Providers

O loop herdado do `bc-harness` possui execução Codex e Claude. OpenCode ainda é
uma capability detectável, mas não está habilitado como engine até existir um
adaptador validado. Hermes e agy permanecem candidatos a executores delegados.

## Validação

Os testes completos desta extração ainda serão executados após a criação da
suíte portátil. Nenhuma alegação de compatibilidade está sendo feita apenas
porque os arquivos foram copiados.
