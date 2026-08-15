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
- integração controlada com Codex, Claude CLI, OpenCode e Antigravity CLI (`agy`);
- readiness passiva compatível com Hermes, ainda sem adapter de execução;
- instalação exclusiva por projeto, sem estado global do produto;
- desinstalação reversível por ownership e hashes;
- feedback JSONL/stdout/callback para o orquestrador externo.

A evolução publicada está registrada no [CHANGELOG](CHANGELOG.md); a versão em
`VERSION` e o estado de promoção estão em [`docs/STATUS.md`](docs/STATUS.md).

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
| Antigravity CLI (`agy`) | adapter em `adapters/agy/` | modelo explícito; verify exige Linux, `bwrap`, token e agente workspace |
| Hermes | somente readiness passiva | não iniciar execução; consultar backlog |

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

O `plan` também verifica se já existe um Ralph de outra origem. O resultado em
`ralph_installation.external` lista somente sinais relativos, tipo e SHA-256;
não expõe conteúdo. Um Ralph externo ou uma origem ambígua bloqueia o `apply`
comum para evitar sobrescrita. A evolução assistida é uma operação separada e
explícita:

```bash
ralph-init evolve --project /caminho/do/projeto
ralph-init evolve --project /caminho/do/projeto --apply
ralph-init rollback --project /caminho/do/projeto --evolution EVL-YYYYMMDD-NNNN --apply
```

Ela cria um backup numerado com hashes, isola os sinais detectados, instala o
método novo e aguarda aceite. O modo é `quarantine_only`: nenhum ledger,
prompt, workflow, credencial ou estado legado é importado automaticamente.
Rollback só prossegue sem drift e preserva alterações feitas pelo usuário.

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
ordem determinística e sem fallback silencioso. Codex e Claude CLI usam os
runners nativos do loop; OpenCode e `agy` usam a seam executável
`preflight|run|version`. O verify `agy` é suportado nesta linha somente em
Linux com `bwrap` allowlisted. Hermes pode aparecer na detecção passiva, mas
permanece no backlog e não habilita execução.

O `ralph-trace` diferencia identidade `exact`, `declared`, `observed`,
`partial` e `unavailable`. Um provider que não expõe modelo efetivo não pode
ser apresentado como exato. A prontidão de provider é independente da
identidade de modelo e segue `schemas/provider-readiness.schema.json`. Probes
seguros não executam geração; uma prova real de inferência futura terá de ser
opt-in.

## Estado

A versão publicada atual é `0.8.0`, identificada pela tag `v0.8.0`. Ela
incorpora a manutenção `0.6.1`, consolida a portabilidade do CI em PHP 8.2,
o fallback seguro quando namespaces não estão disponíveis e adiciona a
evolução assistida de instalações externas. O método nasceu da extração do
núcleo validado no `refactor-radar`, mas não possui dependência de runtime, importação de código,
banco ou credencial desse produto. O bundle pode ser instalado em qualquer
checkout Git compatível, conforme a prova em
[`scripts/test-reproducibility.sh`](scripts/test-reproducibility.sh). A
instalação reversível, o canal de feedback e o guia operacional sincronizado
para agentes de IA fazem parte da release.

O Ralph Method está na versão publicada `0.8.0`, com memória episódica
sanitizada, retenção explícita, índices de engenharia por categoria e tema,
evolução externa com rollback e verificação de campo no OpenCode.
Este checkout contém também o candidato do adapter `agy`, reaberto pelo
[`ADR-0017`](docs/adr/0017-reabertura-agy-e-seam-comum-de-adapters.md), sem
alterar a versão publicada ou habilitar failover. O estado dos adiamentos está
em [`docs/backlog.md`](docs/backlog.md).

A versão atual é `0.8.0`. Ela adiciona evolução assistida com backup,
isolamento, aceite e rollback condicional para Ralph externo, mantendo o
método desacoplado de estado legado. O ciclo foi comprovado em campo pelo
OpenCode `1.18.15` e está detalhado em
[`docs/reports/0019-evolucao-opencode-v0-8-0.md`](docs/reports/0019-evolucao-opencode-v0-8-0.md).

Consulte [docs/README.md](docs/README.md), [docs/STATUS.md](docs/STATUS.md), [docs/architecture/README.md](docs/architecture/README.md),
[docs/AGENT_GUIDE.md](docs/AGENT_GUIDE.md) e [docs/roadmap.md](docs/roadmap.md).
