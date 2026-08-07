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
- instalação exclusiva por projeto, sem estado global do produto.

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
```

## Instalação por projeto

O instalador será exposto pelo `bc-harness` e executado em duas fases:

```bash
ralph-init plan --project /caminho/do/projeto
ralph-init apply --project /caminho/do/projeto --provider auto
ralph-doctor --project /caminho/do/projeto
```

`plan` é somente leitura. `apply` cria uma instalação local e idempotente. A
detecção registra somente fatos como arquivos presentes, versões de CLI,
comando de teste e capacidade declarada; não copia tokens nem credenciais.

## Providers

O caminho padrão é `native_codex`. Claude, OpenCode, Hermes e agy só são
selecionados por configuração explícita ou por uma decisão `auto` materializada
no manifesto da instalação. Ausência de telemetria não vira erro de gate.

O `ralph-trace` diferencia identidade `exact`, `declared`, `observed`,
`partial` e `unavailable`. Um provider que não expõe modelo efetivo não pode
ser apresentado como exato.

## Estado

A versão inicial é `0.1.0`, extraída do núcleo validado do `refactor-radar` no
commit `7ab25f8`. A instalação inteligente e os adaptadores OpenCode serão
incrementos versionados, sempre acompanhados de fixtures offline e regressão.

Consulte [docs/STATUS.md](docs/STATUS.md), [docs/architecture/README.md](docs/architecture/README.md)
e [docs/roadmap.md](docs/roadmap.md).
