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
- integração controlada com Codex, Claude CLI e OpenCode;
- readiness passiva compatível com Hermes e agy, sem adapter de execução nesta versão;
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

## Como entender o framework

O Ralph Method separa quatro responsabilidades. O projeto-alvo fornece as
features, critérios e comando de qualidade; o instalador identifica o harness
disponível; o runner executa uma feature por vez; e o `ralph-control` decide se
os gates permitem continuar.

```text
projeto-alvo
  → plan (detectar stack, harness e conflitos)
  → verify (probes seguros, somente quando solicitado)
  → apply (instalação local e idempotente)
  → workflow (uma feature por bloco)
  → gates + handoff + trace
  → próxima feature ou recuperação explícita
```

O usuário não precisa conhecer a implementação interna do provider. A
abstração está no contrato `runner`, `model`, `session`, `feedback` e
`ralph-control`; os detalhes específicos ficam atrás do runner nativo ou do
adapter correspondente.

## Identificação e configuração do harness

| Harness identificado | Execução configurada | O que o agente deve conferir |
|---|---|---|
| Codex | runner nativo do `scripts/ralph.sh` | `functional` e `adapter_enabled=true` |
| Claude CLI | runner nativo do `scripts/ralph.sh` | `functional` e `adapter_enabled=true` |
| OpenCode | adapter em `adapters/opencode/` | modelo, agente e prova read-only antes da revisão |
| Hermes ou agy | somente readiness passiva nesta versão | não iniciar execução; consultar backlog |

O caminho recomendado é sempre `--provider auto --verify-providers`: o plano
identifica os executáveis, certifica somente sessões autenticadas por probes
não generativos e escolhe um único runner elegível. Se nenhum estiver apto, o
plano retorna `needs_review`; não há fallback silencioso. O procedimento
completo para o agente de IA está em
[`docs/AGENT_GUIDE.md`](docs/AGENT_GUIDE.md), especialmente na seção de
configuração após a identificação do harness.

## Instalação por projeto

O instalador pode ser exposto pelo `bc-harness` e é executado em duas fases:

```bash
ralph-init plan --project /caminho/do/projeto
ralph-init apply --project /caminho/do/projeto --provider auto --verify-providers
ralph-doctor --project /caminho/do/projeto
ralph-init uninstall --project /caminho/do/projeto
ralph-init uninstall --project /caminho/do/projeto --apply
```

`plan` é somente leitura. `apply` cria uma instalação local e idempotente. A
detecção padrão registra somente fatos como arquivos presentes, versões de CLI,
comando de teste e capacidade declarada; não consulta autenticação, não copia
tokens nem credenciais. O exemplo usa `--verify-providers` para que a aplicação
seja feita somente depois da certificação segura; esse probe não conversa com
o modelo nem consome tokens. O status `functional` certifica a CLI;
`adapter_enabled` só fica verdadeiro quando também existe runner do Ralph para
aquele provider.
`uninstall` primeiro mostra um plano e só remove arquivos que continuam iguais
ao hash instalado quando recebe `--apply`. Arquivos modificados, histórico,
workflow, handoffs e relatórios são preservados.

Para comprovar a reprodução a partir de um bundle limpo e de um projeto Git
independente, execute:

```bash
bash scripts/test-reproducibility.sh
```

## Feedback para o orquestrador

O loop publica eventos operacionais em
`.git/ralph-control/feedback/events.jsonl`. Para que uma camada externa mostre
o andamento em tempo real, configure `RALPH_FEEDBACK_STDOUT=1` ou um
`RALPH_FEEDBACK_CMD`. O consumidor observa o evento, mas a decisão continua
exclusiva do `ralph-control`.

## Providers

O caminho padrão é `native_codex`. O modo `auto` consulta todos os providers
certificados, mas seleciona somente um runner com `adapter_enabled=true`, em
ordem determinística e sem fallback silencioso. A versão `0.4.0` fecha o
escopo em três harnesses: Codex e Claude CLI usam os runners nativos do loop;
OpenCode usa o adapter executável em `adapters/opencode/`, certificado com
JSONL, política read-only e teste de campo. Hermes e agy podem aparecer na
detecção passiva, mas ficam no backlog com prioridade nenhuma e não habilitam
execução.

O `ralph-trace` diferencia identidade `exact`, `declared`, `observed`,
`partial` e `unavailable`. Um provider que não expõe modelo efetivo não pode
ser apresentado como exato. A prontidão de provider é independente da
identidade de modelo e segue `schemas/provider-readiness.schema.json`. Probes
seguros não executam geração; uma prova real de inferência futura terá de ser
opt-in.

## Estado

A versão atual é `0.4.0`. O método nasceu da extração do núcleo validado no
`refactor-radar`, mas não possui dependência de runtime, importação de código,
banco ou credencial desse produto. O bundle pode ser instalado em qualquer
checkout Git compatível, conforme a prova em
[`scripts/test-reproducibility.sh`](scripts/test-reproducibility.sh). A
instalação reversível, o canal de feedback e o guia operacional sincronizado
para agentes de IA fazem parte da release.

O fechamento de escopo e as decisões de adiamento estão em
[`docs/adr/0007-escopo-fechado-de-harnesses.md`](docs/adr/0007-escopo-fechado-de-harnesses.md)
e [`docs/backlog.md`](docs/backlog.md).

Consulte [docs/README.md](docs/README.md), [docs/STATUS.md](docs/STATUS.md), [docs/architecture/README.md](docs/architecture/README.md),
[docs/AGENT_GUIDE.md](docs/AGENT_GUIDE.md) e [docs/roadmap.md](docs/roadmap.md).
