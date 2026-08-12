# Interfaces do Ralph Method

## CLI mínima

```text
ralph-init plan --project <path>
ralph-init apply --project <path> --provider auto|codex|claude|opencode|hermes|agy [--verify-providers]
ralph-init plan --project <path> [--provider ...] [--verify-providers]
ralph-init uninstall --project <path> [--apply]
ralph-doctor --project <path> [--verify-providers]
bin/ralph-control <command> ...
bin/ralph-trace record|report|tree ...
bin/ralph-monitor --workflow <id> [--interval 30]
bin/ralph-metrics [--workflow <id>] [--feature <key>] [--format json|markdown]
bin/ralph-knowledge candidates
bin/ralph-knowledge retrieve --query <texto> [--category <id>] [--topic <id>] [--stack <id>] [--domain <id>] [--limit N]
bin/ralph-control knowledge curated|rejected|review-required|skipped --workflow <id> --feature <key>
```

## Harnesses suportados nesta linha

| Harness | Caminho técnico | Situação |
|---|---|---|
| Codex | runner nativo de `scripts/ralph.sh` | suportado e coberto pelo loop |
| Claude CLI | runner nativo de `scripts/ralph.sh` | suportado e coberto pelo loop |
| OpenCode | `adapters/opencode/runner.sh` + parser/policy | adapter executável certificado |
| Hermes | readiness passiva | backlog, prioridade nenhuma |
| agy | readiness passiva quando detectável | backlog, prioridade nenhuma |

Codex e Claude não possuem diretórios de adapter dedicados nesta versão; o
termo adapter é reservado tecnicamente ao normalizador OpenCode. Todos os três
harnesses fechados compartilham trace, feedback, gates e autoridade do
`ralph-control`.

## Fluxo agnóstico de identificação e configuração

O usuário e o agente não precisam conhecer detalhes de cada CLI para operar o
framework. O contrato de integração é o mesmo; somente o runner selecionado e
seus campos específicos mudam:

```text
plan --provider auto --verify-providers
→ detection.providers
→ selection.selected_provider
→ orchestration.mode/primary_runner
→ apply
→ doctor
```

| Campo decisivo | Significado | Regra de uso |
|---|---|---|
| `status=functional` | autenticação e diagnóstico seguro passaram | ainda não basta sozinho |
| `runner_supported=true` | há execução compatível nesta versão | necessário para habilitar |
| `adapter_enabled=true` | provider apto para execução | única condição de elegibilidade |
| `selection.selected_provider` | provider escolhido pelo plano | não substituir por inferência textual |
| `orchestration.mode=needs_review` | nenhum executor autorizado | bloquear até decisão/correção |
| `fallback_policy=none` | não trocar executor silenciosamente | registrar qualquer fallback explicitamente |

O instalador gera perfis locais para os três harnesses fechados. Codex e
Claude CLI apontam para o runner nativo do loop; OpenCode aponta para seu
adapter e exige modelo/agente/prova read-only quando houver revisão. Hermes e
agy podem ser detectados, mas não atravessam a fronteira de execução.

O cenário completo, incluindo a prova dos três runners, está em
[`reports/0009-regressao-multiprovider.md`](../reports/0009-regressao-multiprovider.md).

O procedimento operacional completo para agentes está em
[`../AGENT_GUIDE.md`](../AGENT_GUIDE.md). Ele é parte do contrato versionado e
deve ser atualizado junto com `VERSION`.

`plan` é somente leitura. `apply` instala apenas os arquivos listados no
manifesto, com cópia atômica. `uninstall` sem `--apply` apenas calcula o plano;
com `--apply`, remove somente arquivos ainda iguais ao hash instalado e
preserva arquivos modificados pelo usuário. Os perfis locais de Codex, Claude e OpenCode
também são gerados com `RALPH_BIN=scripts/ralph.sh` e entram no ownership. O
relatório fica em
`.ralph/uninstall-report.json`. O histórico operacional (`.git/ralph-control`),
workflow, handoffs e relatórios não pertencem ao uninstall e são preservados.

## Detecção de Ralph externo

Todo `plan` também devolve `ralph_installation`, validável por
`schemas/ralph-installation-detection.schema.json`:

O schema `1.1.0` inclui a classificação `external_ralph_legacy` e os campos
sanitizados da raiz legada; classificações emitidas pelo detector precisam
permanecer aceitas pelo contrato antes de qualquer evolução do instalador.

| Campo | Valores | Decisão |
|---|---|---|
| `method.status` | `managed`, `not_installed`, `invalid` | informa se o manifesto pertence ao Ralph Method |
| `external.status` | `not_found`, `detected`, `ambiguous` | classifica sinais fora do ownership conhecido |
| `external.confidence` | `none`, `low`, `medium`, `high` | indica força do inventário, não semântica do legado |
| `external.apply_allowed` | booleano | somente `true` permite o `apply` comum |
| `external.signals` | id, caminho relativo, tipo e SHA-256 | comprova o que foi encontrado sem expor conteúdo |
| `external.family` / `signature_id` | linhagem e assinatura reconhecidas | identifica somente a composição legada aprovada |
| `external.members` / `tree_fingerprint` | membros relativos, tipos, hashes e fingerprint | permite auditoria determinística sem armazenar conteúdo |
| `external.legacy_candidates` | raízes aprovadas candidatas ou rejeitadas | informa caminhos sem transformar arquivos parecidos em instalação |

Sinais canônicos como `Ralphfile`, `ralph.sh`, `bin/ralph-control` ou
`scripts/ralph.sh` produzem `detected` com confiança alta. Um marcador
genérico isolado pode produzir `ambiguous`; por segurança também bloqueia o
`apply`. Em ambos os casos o exit code é `3`, nenhum arquivo é movido e a
instalação externa permanece intacta.

A assinatura legada `bc-harness` é procurada somente em `harness/ralph`. Ela
exige a composição `install.sh`, `ralph.patch` e `ralph.sh.upstream`; quando
confirmada, o plano usa `classification=external_ralph_legacy`, recomenda
`evolve` e mantém `apply_allowed=false` e `migration_supported=false`. O
fingerprint é calculado a partir dos caminhos relativos à raiz, tipos e
SHA-256 ordenados dos membros, incluindo tipo e permissões; raízes absolutas,
traversal e symlinks fora do projeto são rejeitados; `vendor` e `node_modules`
não são varridos.

O caminho de evolução é deliberadamente explícito:

```text
plan → inventário aprovado → backup com hashes → isolamento
→ instalação transacional → doctor → manifesto de rollback
→ rollback condicional se a nova instalação for rejeitada
```

Não existe migração genérica nesta versão. O método não importa ledger,
workflow, prompts, credenciais ou eventos de uma origem desconhecida.

### Evolução assistida e rollback

Quando o `plan` detectar uma instalação externa, o agente pode solicitar a
operação explícita abaixo:

```bash
bin/ralph-init evolve --project /projeto
bin/ralph-init evolve --project /projeto --apply
bin/ralph-init rollback --project /projeto --evolution EVL-YYYYMMDD-NNNN
bin/ralph-init rollback --project /projeto --evolution EVL-YYYYMMDD-NNNN --apply
bin/ralph-init evolve --project /projeto --evolution EVL-YYYYMMDD-NNNN --accept --apply
```

`evolve --apply` adquire o mesmo `install.lock`, revalida os hashes, move os
sinais não-runtime para `.ralph/evolutions/<id>/backup/`, preserva
`.git/ralph-control` e instala o bundle atual. O estado termina em
`awaiting_acceptance`; repetir o comando é idempotente e devolve o mesmo ID.
`rollback --apply` verifica o manifesto novo, todos os hashes instalados, a
existência do backup e a ausência de destino ocupado. Qualquer drift bloqueia
com exit code `3`; nenhuma alteração do usuário é sobrescrita. O aceite marca
o estado como `accepted`, mas mantém o backup para uma decisão posterior.

## Canal de feedback do loop

`scripts/ralph.sh` emite um evento sanitizado para cada início, tentativa,
falha, espera, conclusão e encerramento. O evento segue
`schemas/feedback-event.schema.json` e contém `run_id`, fase, tentativa,
`workflow_id`, `feature_key`, percentual estimado, estado e saúde. O canal é
unidirecional: quem recebe o evento não pode aprovar gates, adquirir leases ou
escolher a próxima feature.

Por padrão, o loop grava JSONL local em:

```text
.git/ralph-control/feedback/events.jsonl
```

Para exibir o fluxo na tela do orquestrador, use:

```bash
RALPH_FEEDBACK_STDOUT=1 scripts/ralph.sh
```

O consumidor deve ler linhas com o prefixo `RALPH_FEEDBACK `. Para integração
direta, `RALPH_FEEDBACK_CMD=/caminho/do/consumidor` executa um binário com
`<evento> <detalhe>` nos argumentos e o JSON completo no stdin. O callback tem
timeout e qualquer falha é apenas reportada; a execução não é aprovada nem
interrompida por ele.

Quando o bloco é iniciado pelo `ralph-control run` ou pelo supervisor, o
controlador ativa esse canal por padrão e retransmite as linhas
`RALPH_FEEDBACK` enquanto o processo está vivo. Assim o terminal do
orquestrador recebe progresso sem esperar o encerramento do bloco. O relay
continua sendo somente saída; gates, leases e transições permanecem no
controlador.

Os detalhes textuais são reduzidos e têm padrões óbvios de token, senha e API
key redigidos antes da publicação. O evento não carrega prompt, resposta,
credencial ou saída integral do comando.
Bytes inválidos para UTF-8 também são normalizados antes da serialização; uma
falha de encoding não pode transformar o encerramento do provider em um
evento JSON inválido.

`bin/ralph-monitor` continua sendo somente leitura. Além do snapshot do
workflow, ele mostra o último evento do JSONL do loop e permite detectar
processo ausente, heartbeat parado, gates sem atividade e workflow bloqueado.

`bin/ralph-metrics` também é somente leitura. Ele agrega `events.jsonl` em
JSON ou Markdown, aceita filtros por workflow/feature e calcula contagens de
eventos, comandos, gates, recuperações, conhecimento e durações observadas.
Não grava arquivo por padrão e não deve ser interpretado como métrica de
custo, consumo de tokens ou autorização de continuidade.

## Memória episódica e taxonomia

Depois de `feature.released`, o controlador materializa um candidato
sanitizado em `.ralph/knowledge-candidates/<CUR-...>.json`. Esse cache não é
fonte de conhecimento e pode ser persistido, rejeitado, enviado para revisão
ou descartado por ação explícita. Todas as decisões continuam no ledger e não
bloqueiam `feature.advanced`.

Uma lição persistida possui os campos estruturados:

```text
category, topics[], stack[], domain[], fingerprints[]
```

`docs/engineering/INDEX.md` agrega as categorias e temas; os subíndices em
`docs/engineering/categories/` e `docs/engineering/topics/` são projeções
regeneráveis. `retrieve` aceita os mesmos filtros antes da pontuação lexical e
retorna somente documentos com `status: validated`, respeitando limite de
lições e de contexto.

## Prontidão de provider

`ralph-init` detecta providers sem tocar autenticação por padrão. A flag
`--verify-providers` solicita probes `safe` explícitos, com timeout e sem
geração. O resultado é persistido em `.ralph/providers.json` conforme
`schemas/provider-readiness.schema.json`.

O contrato mínimo de cada provider contém:

```text
installed, path, version,
auth_status, health_status, status,
capabilities, runner_supported, adapter_enabled, reason
```

Uma CLI é certificada quando `status=functional`. Um adapter somente é
elegível se `status=functional`, `runner_supported=true` e
`adapter_enabled=true`. `detected`, `authenticated`, `degraded`,
`unsupported` e `authentication_unknown` nunca habilitam execução alternativa.
O modo `auto` considera todos os providers certificados, mas escolhe somente
os runners disponíveis em ordem determinística. Ele não faz fallback silencioso;
quando não encontra runner apto, materializa `orchestration.mode=needs_review`.
Nesse caso, `selection.selected_provider` e `orchestration.primary_runner` são
`null`.

## Contrato de provider

Um adapter não grava arquivos de estado. Ele entrega ao controlador os campos:

```text
runner, runner_version, role, execution_id,
requested_model, effective_model, provider,
session_id ou conversation_id,
identity_status, identity_source,
status, reason, fallback_used e fallback_status
```

Quando o provider não expõe modelo efetivo, a identidade deve ser marcada como
`declared`, `observed`, `partial` ou `unavailable`.

O adapter OpenCode também exige `runner-result.schema.json`, uma única sessão e
pelo menos um evento terminal `step_finish`; múltiplos `step_finish` na mesma
sessão são válidos. Falta de evidência de fallback permanece como
`fallback_used=null` e `fallback_status=unknown`.

No modo de revisão, o resultado também deve conter `permission_policy_hash`,
`permission_policy_status=verified` e `verification_agent`. O resultado
normalizado carrega ainda `workflow_id`, `feature_key` e `attempt`; o
`ralph-control` só importa um resultado quando esses três identificadores
correspondem ao bloco atual. A classificação usa `execution_mode` e confirma
que o nome do artefato é compatível: `verify` vira `technical_review` e `impl`
vira `implementation`; ambos permanecem delegações distintas no
`ralph-trace`.

## Aprovação da implementação

Após os cinco gates, `ralph-control approve` revalida o resultado contra o
checkout atual e exige working tree limpa. O caminho normal continua exigindo
que `base_commit` seja o pai imediato do `HEAD` e que exista exatamente um
commit novo.

Uma execução que comprova que a feature já estava implementada pode ser
aprovada sem commit vazio quando `base_commit`, `base_tree_hash`,
`implementation_commit`, `result_commit` e `result_tree_hash` correspondem ao
checkout atual. O evento `feature.approved` registra
`implementation_mode=already_present` e `no_op=true`; isso diferencia a
idempotência de uma implementação que produziu commit.

Se o resultado ficar stale antes da promoção, o controlador registra
`recovery.required` com os hashes divergentes e bloqueia a aprovação. A
retomada precisa passar por `recover` e uma nova tentativa; nenhum gate antigo
é promovido silenciosamente contra outro checkout.

### Recovery do supervisor e heartbeat de verificação

Uma revisão read-only longa não pode ser confundida com inatividade. O
`runReadOnlyCommand()` aceita um callback opcional e o fluxo OpenCode emite
`command.heartbeat` com `facts.phase=verification` enquanto o processo está
vivo. O heartbeat é observabilidade; ele não promove estado nem libera lease.

Quando `supervise` detecta `heartbeat_stale`, `activity_stale`,
`process_missing` ou término sem evento terminal, o controlador encerra o
grupo, registra `recovery.required` de forma idempotente e somente então chama
`beginFailedRetry()`. Essa chamada cria novo `attempt`, novo lease e novo
fencing token. O supervisor nunca relança a mesma tentativa com a autoridade
anterior.

## Política de fallback

O padrão é `none`. Fallback precisa estar declarado no manifesto e sempre ser
registrado pelo `ralph-trace`; nenhuma falha pode trocar executor
silenciosamente.
