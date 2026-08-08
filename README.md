# Ralph Method

Framework local e agnóstico de stack para execução controlada de fases de
desenvolvimento. O Ralph executa, os hooks observam, o ledger registra, os
gates comprovam e o controlador decide.

## O que este projeto entrega

- máquina de estados com lease, fencing, lock e hash chain;
- uma feature por bloco de execução;
- cinco gates de entrega e recuperação explícita;
- systematic debugging read-only;
- handoff e documentos numerados;
- `ralph-trace` para a árvore de delegação entre executores;
- seam para Codex, Claude, OpenCode, Hermes e agy;
- instalação exclusiva por projeto, sem estado global do produto;
- desinstalação reversível por ownership e hashes;
- feedback JSONL/stdout/callback para o orquestrador externo.

## Estrutura

```text
bin/ralph-control       autoridade e ledger
bin/ralph-trace         registro/relatório de delegação
bin/ralph-monitor       snapshot de saúde
bin/ralph-block         uma feature por invocação
scripts/ralph.sh        loop de fases do harness
scripts/ralph-hook.sh   observabilidade best-effort
schemas/                contratos versionados
adapters/               normalizadores de providers
docs/                   fonte de verdade do framework
docs/AGENT_GUIDE.md     guia operacional para agentes de IA
```

## Instalação por projeto

O instalador pode ser exposto pelo `bc-harness` e é executado em duas fases:

```bash
ralph-init plan --project /caminho/do/projeto
ralph-init apply --project /caminho/do/projeto --provider auto
ralph-doctor --project /caminho/do/projeto
ralph-init uninstall --project /caminho/do/projeto
ralph-init uninstall --project /caminho/do/projeto --apply
```

`plan` é somente leitura. `apply` cria uma instalação local e idempotente. A
detecção padrão registra somente fatos como arquivos presentes, versões de CLI,
comando de teste e capacidade declarada; não consulta autenticação, não copia
tokens nem credenciais. Para certificar as sessões autenticadas, execute o
probe seguro explicitamente com `--verify-providers`. O status `functional`
certifica a CLI; `adapter_enabled` só fica verdadeiro quando também existe
runner do Ralph para aquele provider.
`uninstall` primeiro mostra um plano e só remove arquivos que continuam iguais
ao hash instalado quando recebe `--apply`. Arquivos modificados, histórico,
workflow, handoffs e relatórios são preservados.

## Feedback para o orquestrador

O loop publica eventos operacionais em
`.git/ralph-control/feedback/events.jsonl`. Para que uma camada externa mostre
o andamento em tempo real, configure `RALPH_FEEDBACK_STDOUT=1` ou um
`RALPH_FEEDBACK_CMD`. O consumidor observa o evento, mas a decisão continua
exclusiva do `ralph-control`.

## Providers

O caminho padrão é `native_codex`. O modo `auto` consulta todos os providers
certificados, mas seleciona somente um runner com `adapter_enabled=true`, em
ordem determinística e sem fallback silencioso. Nesta versão, Codex e Claude
possuem runner; OpenCode e Hermes podem ser certificados como CLIs prontas,
mas ainda aguardam seus adapters de execução. Ausência de telemetria não vira
erro de gate.

O `ralph-trace` diferencia identidade `exact`, `declared`, `observed`,
`partial` e `unavailable`. Um provider que não expõe modelo efetivo não pode
ser apresentado como exato. A prontidão de provider é independente da
identidade de modelo e segue `schemas/provider-readiness.schema.json`. Probes
seguros não executam geração; uma prova real de inferência futura terá de ser
opt-in.

## Estado

A versão atual em desenvolvimento é `0.3.1`, extraída do núcleo validado do
`refactor-radar` no commit `7ab25f8`. A instalação reversível e o canal de
feedback estão incluídos, assim como o guia operacional sincronizado para
agentes de IA. A certificação segura de OpenCode e Hermes está incluída; seus
adapters de execução continuam sendo incremento posterior, sempre acompanhado
de fixtures offline e regressão.

Consulte [docs/STATUS.md](docs/STATUS.md), [docs/architecture/README.md](docs/architecture/README.md),
[docs/AGENT_GUIDE.md](docs/AGENT_GUIDE.md) e [docs/roadmap.md](docs/roadmap.md).
