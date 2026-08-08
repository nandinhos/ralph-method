# INC-0002 — classificação estreita de sessões CLI

## Estado

Resolvido em `0.3.1`.

## Sintoma

OpenCode e Hermes retornavam exit code `0` nos comandos locais, mas o
`ralph-init plan --verify-providers` os classificava como
`authentication_unknown` ou `degraded`.

## Causa raiz

O classificador assumia que todo provider emitiria marcadores textuais iguais,
como `logged in` ou `authenticated`. OpenCode apresenta uma tabela de
credenciais e um catálogo de modelos. Hermes apresenta vários providers no
mesmo relatório, incluindo providers não autenticados que não são o provider
selecionado.

## Correção

Foram adicionados classificadores específicos e não generativos:

- OpenCode: inventário de credenciais em `auth list` e catálogo de modelos em
  `models`;
- Hermes: provider selecionado em `status`, modelo selecionado e
  `auth status <provider>`;
- seleção automática: lista ordenada de providers funcionais e runners
  disponíveis, sem fallback silencioso;
- `runner_supported` separa CLI certificada de adapter de execução disponível.
- plano sem runner: seleção e `primary_runner` ficam nulos, sem materializar
  `codex` como fallback fantasma.

O conteúdo bruto das CLIs continua fora do relatório; somente status, códigos,
provider-alvo sanitizado e motivo factual são persistidos.

## Comprovação

- `scripts/test-provider-readiness.sh` com fixtures offline de OpenCode e
  Hermes;
- dry-run real contra `refactor-radar` com Codex, Claude, OpenCode e Hermes
  classificados como `functional`;
- nenhum fixture permite `run`, `exec` ou `--print` durante o probe.

## Risco residual

`functional` comprova a sessão da CLI e seu diagnóstico local, não uma chamada
real de inferência. OpenCode e Hermes ainda não são runners do `ralph.sh` e,
por isso, permanecem fora de `available_runners` até seus adapters serem
implementados e validados.
