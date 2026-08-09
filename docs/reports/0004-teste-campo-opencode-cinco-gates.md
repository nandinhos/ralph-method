# Relatório 0004 — teste de campo real do OpenCode com cinco gates

## Resultado executivo

O Ralph Method foi executado contra uma checkout isolada e descartável do
`refactor-radar`, usando a engine OpenCode para implementar uma feature real.
O controlador completou a máquina de estados e aprovou os cinco gates sem
intervenção manual no estado global.

| Item | Resultado |
|---|---|
| Workflow | `wf_field_refactor_radar_20260808_004` |
| Feature | `FEATURE-FIELD-OPENCODE-001` — Sonda determinística de saúde do runtime |
| Checkout | `/tmp/ralph-method-refactor-radar-field-fast.hRxaK7` |
| Engine | `opencode` |
| CLI | OpenCode `1.18.15` |
| Modelo solicitado | `opencode/big-pickle` |
| Identidade do modelo | `declared` — o provider não comprovou o modelo efetivo |
| Commit de implementação | `cff8afeebe04454708e246712098936db99e8032` |
| Commit do handoff | `e49ad49` |
| Ledger | 50 eventos; `ralph-control verify` verde |
| Estado final | `released`; cursor vazio; workflow `complete` |
| Política de conhecimento | `non_blocking`; `knowledge_pending` não bloqueou a entrega |
| Promoção para a main do projeto | não realizada |

A `main` de `/home/nandodev/projects/ralph-method` permaneceu intacta. O
commit de implementação e o handoff existem somente na checkout de campo,
que não foi promovida nem publicada.

## Feature executada

O OpenCode criou somente:

- `routes/console.php`: comando `radar:health {--json}`;
- `tests/Feature/RuntimeHealthCommandTest.php`: exit code e payload exato.

O comando responde com uma linha JSON determinística:

```json
{"status":"ok","service":"refactor-radar"}
```

Não houve migration, alteração de banco, escrita de runtime, alteração de
autenticação ou mudança na superfície HTTP.

## Gates formais

| Gate | Relatório | Prova | Resultado |
|---|---|---|---|
| `validation` | `RPT-2026-0038` | commit/tree/processo compatíveis com a base; exit code `0` | aprovado |
| `quality` | `RPT-2026-0039` | `bin/check`: Pint, PHPStan 0 erros, Pest 501/501, Architecture 7/7, Vite e tema | aprovado |
| `runtime_evidence` | `RPT-2026-0040` | `php artisan radar:health --json`, exit `0`, payload exato | aprovado |
| `technical_review` | `RPT-2026-0041` | sessão separada `ralph-review`, read-only, `REVIEW_VERDICT: PASS` | aprovado |
| `curation` | `RPT-2026-0042` | curadoria independente, dois arquivos previstos, escopo confirmado | aprovado |

Todos os relatórios foram gerados pelo controlador no ledger local. A árvore
permaneceu limpa durante a sessão de gates (`tree_changed=false`).

## Delegações e ralph-trace

O trace local recebeu exatamente duas delegações da tentativa 1:

| Papel | `execution_id` | `session_id` | Status | Eventos | Política |
|---|---|---|---|---:|---|
| `implementation` | `exec_run_20260809T003215Z_2_impl_1_1` | `ses_01c10a4bbffexr4poCVrdFY8mA` | completed, exit `0` | 56 | `not_required` |
| `technical_review` | `exec_run_20260809T003739Z_3423730_verify_1_1` | `ses_01c0bbb31ffed03f7aRLWKlZJD` | completed, exit `0` | 89 | `verified` |

O relatório `TRC-2026-0001` é o identificador local do ledger desta fixture;
ele não substitui nem renumera os traces já documentados no repositório do
método. Os dois resultados possuem `provider=opencode`, modelo solicitado,
`terminal_event=step_finish`, hashes de resultado e vínculo explícito com
workflow, feature e tentativa.

## Prova read-only

| Evidência | Valor |
|---|---|
| Agente | `ralph-review` |
| Hash da política | `b6506ca35ebedbfd63b8ee10afb1594ce77f5971c8d4e6510124b4967b4657b8` |
| Hash da superfície antes/depois | `f57dd08346e8ffec2110b80c954db3d1d1698434cc57af3862f166229589aa65` em ambos |
| Evento terminal | `step_finish` |
| Marcador | `READONLY_DENIED` |
| Ferramentas negadas | `edit`, `bash` |
| Canário de mutação | ausente |
| Tentativas | 1 |
| Hash do JSONL | `0a9aac42c0faf3fd68d8c5a8f6a76bd425adc01147ebb6abe04c4ec3d4ec5be4` |

## Máquina de estados observada

```text
pending → running → awaiting_gates → approved → released → next_feature
```

O handoff foi gerado em `.ralph/handoffs/FEATURE-FIELD-OPENCODE-001/` com
`bug-report.json`, `bug-report.md`, `evidence-manifest.json`,
`execution-summary.json` e `execution-summary.md`. Em seguida o controlador
criou o Commit B, liberou a feature e avançou para uma fila vazia. A criação
do candidato de conhecimento foi registrada, mas não bloqueou a entrega,
conforme a política deliberada do workflow.

## Falhas encontradas antes da execução verde

| Ocorrência | Tratamento | Estado |
|---|---|---|
| PHPStan rejeitou `$this->artisan()` no teste | systematic debugging, consulta oficial e retry com chamada explícita | corrigida e comprovada |
| Modelo gratuito entrou em ciclo/timeout e não emitiu evento terminal | containment, diagnóstico verificado e escalonamento para `big-pickle` em checkout limpa | corrigida e comprovada |

As ocorrências não foram apagadas nem convertidas em aprovação. Elas ficaram
nos ledgers descartáveis e foram consolidadas nos incidentes
[`0003`](../incidents/0003-convergencia-operacional-opencode-em-campo.md) e
[`0004`](../incidents/0004-incompatibilidade-pest-phpstan-na-feature-de-campo.md).

## Limite da conclusão

Esta é uma certificação de campo real do caminho OpenCode + Ralph + cinco
gates em um projeto Laravel isolado. Ela comprova a engine e a coordenação,
mas não autoriza promoção automática para `main`: a decisão de promoção ainda
exige revisão adversarial do diff/documentação e a regressão final da branch
`feat/opencode-engine`.
