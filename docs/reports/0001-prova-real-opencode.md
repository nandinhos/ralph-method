# REP-0001 — Prova real isolada do OpenCode

## Status

Aprovado como prova exploratória do provider; não representa ainda a
certificação da engine OpenCode pelo Ralph Method.

## Objetivo

Verificar, em um repositório Git descartável, se o OpenCode consegue receber
uma feature pequena, alterar o checkout, executar a verificação determinística
e devolver eventos JSONL utilizáveis pelo futuro adapter.

## Ambiente

| Campo | Resultado |
|---|---|
| CLI | OpenCode `1.18.15` |
| Modelo solicitado | `opencode/deepseek-v4-flash-free` |
| Diretório | fixture temporário fora dos repositórios do projeto |
| Transporte | `--file README.md` + mensagem curta |
| Formato | `--format json` |
| Permissão | `--auto`, explicitamente usado somente no fixture descartável |
| Plugins | `--pure` |
| Sessão | prefixo `ses_01e30822` |
| Identidade | `declared` — o JSONL não comprovou modelo efetivo |

Nenhum token, prompt completo, resposta completa ou log bruto foi versionado.

## Feature solicitada

O OpenCode recebeu a instrução para criar `feature.sh` com o contrato:

```text
sem argumento → RALPH-OPENCODE-OK: Mundo
nome informado → RALPH-OPENCODE-OK: <nome>
nome vazio → RALPH-OPENCODE-OK: Mundo
```

Os arquivos `README.md`, `expected-output.txt` e `test-feature.sh` foram
protegidos e não poderiam ser modificados pela sessão.

## Verificações realizadas

| Verificação | Resultado |
|---|---:|
| `opencode run` terminou | exit code `0` |
| JSONL válido | 16 eventos lidos |
| `sessionID` presente | sim |
| evento terminal | `step_finish` |
| stderr | vazio |
| `./test-feature.sh` | `FEATURE_CHECK_OK` |
| saída sem argumento | correta |
| saída com `Codex` | correta |
| saída com nome vazio | correta |
| arquivos protegidos inalterados | sim |
| processo `opencode run` remanescente | não encontrado |

## Resultado produzido

O OpenCode criou um `feature.sh` executável, sem dependências externas:

```bash
#!/usr/bin/env bash
set -euo pipefail

name="${1:-Mundo}"
printf 'RALPH-OPENCODE-OK: %s\n' "${name:-Mundo}"
```

O verificador final passou integralmente.

## O que esta prova comprovou

- o provider autenticado consegue executar uma tarefa real;
- `opencode run --format json` pode ser usado sem abrir a TUI;
- `--file` foi aceito como transporte da instrução;
- a saída JSONL contém `type`, `timestamp` e `sessionID`;
- `step_finish` apareceu como evento terminal nesta versão;
- a feature foi criada corretamente;
- o check determinístico detectou a entrega correta;
- a sessão terminou sem processo OpenCode residual observável.

## O que esta prova ainda não comprovou

- execução pelo `scripts/ralph.sh` com `--engine opencode`;
- capability isolada sem `RALPH_LEASE_TOKEN`;
- importação pelo `ralph-control` e `ralph-trace` sob lease;
- cinco gates e commit controlado pelo Ralph;
- política read-only do agente de verificação;
- prova de processo desacoplado em outro PGID;
- identificação exata do modelo efetivo;
- teste de campo no `refactor-radar`.

## Decisão

O resultado é verde para a capacidade real da CLI e verde para o protocolo
JSONL observado nesta versão. A engine OpenCode permanece bloqueada até que o
adapter reproduza essa prova com capability isolada, gates, trace e controle de
processo verificável.
