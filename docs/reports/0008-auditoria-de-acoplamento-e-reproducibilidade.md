# Relatório 0008 — auditoria de desacoplamento e reprodução

**Data:** 2026-08-09
**Versão:** `0.4.0`
**Branch:** `main`
**Escopo:** dependência do projeto de origem, instalação, desinstalação e
reprodução em outro projeto

## Conclusão

O Ralph Method está desacoplado do `refactor-radar` em runtime e é instalável
em outro checkout Git. A referência ao `refactor-radar` encontrada na árvore é
histórica ou documental: origem da extração, ADRs, relatórios do teste de campo
e planejamento. Nenhum arquivo em `bin/`, `scripts/`, `adapters/` ou `schemas/`
contém essa dependência textual ou importa código do produto.

## Matriz de harnesses

| Harness | Forma técnica | Resultado |
|---|---|---|
| Codex | runner nativo de `scripts/ralph.sh` | fechado e coberto pela regressão do loop |
| Claude CLI | runner nativo de `scripts/ralph.sh` | fechado e coberto pela regressão do loop |
| OpenCode | adapter em `adapters/opencode/` | fechado, adversarial e campo real verdes |
| Hermes | readiness passiva | backlog, prioridade nenhuma |
| agy | readiness passiva quando detectável | backlog, prioridade nenhuma |

## Provas executadas

| Prova | Resultado | Fato observado |
|---|---:|---|
| Fonte independente | verde | `RALPH_METHOD_SOURCE` apontou para um bundle temporário fora do projeto-alvo |
| Bundle limpo | verde | fonte criada por `git archive --format=tar HEAD` |
| Projeto-alvo | verde | checkout Git fixture independente, sem código do Radar |
| `plan` | verde | método `0.4.0` e raiz Git do projeto identificados |
| `apply` repetido | verde | duas aplicações sem conflito ou instalação parcial |
| `doctor` | verde | instalação reportada como `healthy` |
| `uninstall --apply` | verde | arquivos do método removidos por ownership |
| Preservação | verde | `README.md`, relatório de remoção e lock local preservados |
| Limpeza | verde | nenhum artefato inesperado; saída `OK` de `scripts/test-reproducibility.sh` |

## Limites confirmados

- O projeto-alvo precisa ser um checkout Git; isso é uma pré-condição explícita
  do instalador.
- O bundle copia o método para o projeto; o runtime instalado não precisa
  acessar o repositório do Ralph Method nem o `refactor-radar`.
- As credenciais continuam fora do bundle e os probes de provider continuam
  opt-in e não generativos.
- A reprodução prova instalação, ciclo de vida e fronteira de arquivos; não
  substitui o teste real de cada provider. Codex, Claude CLI e OpenCode já têm
  as evidências específicas registradas no status e nos relatórios anteriores.

## Documentos relacionados

- [`docs/adr/0007-escopo-fechado-de-harnesses.md`](../adr/0007-escopo-fechado-de-harnesses.md)
- [`docs/backlog.md`](../backlog.md)
- [`scripts/test-reproducibility.sh`](../../scripts/test-reproducibility.sh)
- [`docs/reports/0007-certificacao-e-promocao-v0-4-0.md`](0007-certificacao-e-promocao-v0-4-0.md)
