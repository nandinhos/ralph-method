# Guia operacional para agentes de IA — Ralph Method

- guide_version: 1.7.0
- method_version: 0.9.0
- status: ativo
- fonte_do_metodo: `VERSION`
- contrato_de_feedback: `schemas/feedback-event.schema.json`

Escopo deste checkout: Codex e Claude CLI operam pelos runners nativos do loop;
OpenCode e `agy` operam por adapters executáveis. O verify `agy` exige Linux,
`bwrap`, token OAuth local e agente workspace. Hermes permanece somente em
detecção passiva e no backlog sem prioridade.

Esta versão de manutenção consolida a portabilidade do CI em PHP 8.2, a
supervisão sem namespace privilegiado e a documentação pós-promoção. Este
documento é o manual operacional para qualquer agente de IA, provider,
subagente ou orquestrador que instalar, executar, revisar, recuperar,
atualizar ou remover o Ralph Method de um projeto.

## Regra de sincronização

`VERSION` é a fonte da versão do framework. Sempre que a versão mudar, este
guia deve ser atualizado no mesmo commit ou release, incluindo seu campo
`method_version`, exemplos afetados e mudanças de contrato. O check obrigatório
é:

```bash
bash scripts/check-doc-sync.sh
```

Uma alteração de CLI, schema, máquina de estados, provider, comunicação ou
ownership exige também a atualização da seção correspondente deste guia, de
`docs/STATUS.md` e, quando houver decisão arquitetural, de um ADR em
`docs/adr/`.

## 0. Roteiro operacional obrigatório

Use esta sequência em qualquer projeto novo. O agente só avança quando a
saída da etapa atual for compatível com a decisão esperada.

### 0.1 Preparar o contexto

1. Identifique a raiz do checkout Git e leia `AGENTS.md`, `docs/STATUS.md`,
   convenções, arquitetura e ADRs do projeto-alvo.
2. Confira a árvore antes de agir:

   ```bash
   git -C "$PROJECT_ROOT" status --short --branch
   ```

3. Não instale, aplique ou inicie provider enquanto escopo, árvore e comando
   real de qualidade não estiverem claros.

O Ralph Method é instalado exclusivamente no projeto-alvo. O repositório que
distribui o método é apenas a fonte dos componentes; não é dependência de
runtime, banco ou credencial do projeto.

#### Self-hosting do próprio Ralph Method

Este repositório é uma exceção explícita: ele pode usar o próprio runtime para
implementar suas fases. O perfil versionado `.ralph/codex.env` aponta para
`scripts/ralph.sh` e usa o runner nativo do Codex. Execute o wrapper somente
após uma fase aprovada e com a árvore limpa:

```bash
bin/ralph-bloco <fase-inicial> <fase-final> codex
```

O perfil self-hosted também define `RALPH_TEST_CMD=bash scripts/ci-portable.sh`,
que é o comando de qualidade deste repositório; projetos com `bin/check`
continuam usando esse valor como padrão do wrapper.

Não use `ralph-init apply` sobre este checkout. O instalador deve continuar
bloqueando a auto-instalação como instalação externa; o perfil self-hosted é a
configuração explícita deste projeto e não uma migração do framework.

### 0.2 Fazer o dry-run

Use primeiro `plan`, sempre sem mutação:

```bash
"$METHOD_ROOT/bin/ralph-init" plan \
  --project "$PROJECT_ROOT" \
  --provider auto \
  --verify-providers
```

Leia o JSON completo:

| Resultado | Ação |
|---|---|
| `functional` + `adapter_enabled=true` | provider pode ser usado |
| `functional` + `adapter_enabled=false` | não executar; falta runner autorizado |
| `needs_review` | parar e reportar o requisito ausente |
| `conflict` ou `drift_detected` | preservar arquivos e resolver explicitamente |
| `ralph_installation.external.status=detected` ou `ambiguous` | não aplicar; preservar o Ralph externo e iniciar a revisão de evolução |
| provider não autenticado ou não saudável | corrigir a sessão; não usar fallback silencioso |

`--verify-providers` executa apenas probes seguros de prontidão; não envie uma
mensagem generativa para testar o modelo. Codex e Claude CLI usam runners
nativos; OpenCode exige modelo explícito e revisão read-only comprovada; `agy`
exige modelo explícito e isolamento Linux funcional para habilitar o adapter;
Hermes permanece em readiness passiva.

Se o plano não produzir runner elegível, não materialize configuração fictícia
e não avance para `apply`. O retorno correto é `needs_review` com a causa.

Se `ralph_installation.external.status` for `detected` ou `ambiguous`, o
projeto já contém sinais de um Ralph que não pertence ao manifesto do Ralph
Method. O instalador bloqueia o `apply` comum com exit code `3`. Preserve os
arquivos e reporte os campos `classification`, `confidence`, `signals` e
`reason`; não copie conteúdo, não apague o ledger e não tente traduzir
prompts, workflow ou credenciais por inferência.

Quando `ralph_installation.external.classification` for
`external_ralph_legacy`, confira `family`, `signature_id`, `legacy_root`,
`members` e `tree_fingerprint`. Nesta linha, a assinatura `bc-harness` só é
reconhecida em `harness/ralph` quando contém `install.sh`, `ralph.patch` e
`ralph.sh.upstream`; `legacy_candidates` informa raízes aprovadas incompletas
ou rejeitadas sem transformar arquivos parecidos em instalação. O plano
recomenda `evolve`, mantém `apply_allowed=false` e não expõe conteúdo bruto.

A evolução deve ser solicitada como operação explícita, com inventário aprovado,
backup com hashes, instalação transacional, aceite e manifesto de rollback. O
modo atual é `quarantine_only`: nenhum ledger, workflow, prompt, credencial ou
evento legado é importado.

Quando a raiz legada for `legacy_directory`, a evolução move a árvore inteira
para um backup numerado, preservando subdiretórios, arquivos, permissões e
symlinks internos sem seguir symlinks durante o inventário. Cada membro registra
tipo, modo, SHA-256 e alvo do symlink quando aplicável; a árvore recebe um
fingerprint composto e o journal registra o evento `before`/`after` de cada
movimento. O ciclo completo evolve → aceite → drift → rollback foi comprovado em
fixture isolada na regressão `FEATURE-093-REGRESSION-RELEASE`; a evidência está
no relatório `0021` e foi revalidada no relatório `0023`.

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" "$METHOD_ROOT/bin/ralph-init" evolve --project "$PROJECT_ROOT" --provider auto --verify-providers
RALPH_METHOD_SOURCE="$METHOD_ROOT" "$METHOD_ROOT/bin/ralph-init" evolve --project "$PROJECT_ROOT" --provider auto --apply
```

O resultado `awaiting_acceptance` fornece um ID `EVL-YYYYMMDD-NNNN`. Antes
de aceitar, verifique o método novo com `ralph-doctor` e os testes do projeto.
Para rejeitar a evolução:

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" "$METHOD_ROOT/bin/ralph-init" rollback --project "$PROJECT_ROOT" --evolution EVL-YYYYMMDD-NNNN
RALPH_METHOD_SOURCE="$METHOD_ROOT" "$METHOD_ROOT/bin/ralph-init" rollback --project "$PROJECT_ROOT" --evolution EVL-YYYYMMDD-NNNN --apply
```

Para aceitar explicitamente, mantendo o backup disponível:

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" "$METHOD_ROOT/bin/ralph-init" evolve --project "$PROJECT_ROOT" --evolution EVL-YYYYMMDD-NNNN --accept --apply
```

Rollback é fail-closed: se qualquer arquivo do método novo tiver drift,
estiver ausente, ou o destino do legado estiver ocupado, o comando retorna
exit code `3` e não sobrescreve alterações do usuário.

### 0.3 Aplicar e verificar

Somente após revisar o dry-run:

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" apply \
  --project "$PROJECT_ROOT" \
  --provider auto \
  --verify-providers

"$PROJECT_ROOT/bin/ralph-doctor" --project "$PROJECT_ROOT"
```

Confirme `healthy`, os perfis gerados e o ownership em
`.ralph/install-manifest.json`. Se houver `drift_detected`, interrompa e
entregue a decisão ao usuário; não substitua arquivos modificados.

### 0.4 Preparar a fila

Antes de `ralph-control init`, o workflow deve ser versionável e conter:

- `workflow_id` único e estável;
- `plan_file` e comando real de qualidade;
- features ordenadas por `position`, com uma feature por bloco lógico;
- critérios de aceitação e evidências esperadas;
- `knowledge_policy.mode: non_blocking`, salvo decisão explícita diferente;
- árvore limpa e plano protegido contra alterações durante a execução.

Exemplo mínimo:

```json
{
  "schema_version": "1.0.0",
  "workflow_id": "wf_exemplo_20260810_001",
  "plan_file": ".spec/init/project-phases.md",
  "knowledge_policy": {"mode": "non_blocking"},
  "features": [{"feature_key":"FEATURE-001","title":"Primeira feature","position":1}]
}
```

Inicialize somente após validar o manifesto:

```bash
cd "$PROJECT_ROOT"
bin/ralph-control init \
  --workflow wf_exemplo_20260810_001 \
  --manifest workflow.json
```

### 0.5 Executar e comunicar

Mantenha uma única instância do supervisor por checkout:

```bash
bin/ralph-control supervise \
  --workflow wf_exemplo_20260810_001 \
  --interval 30 \
  --max-retries 3
```

Para acompanhamento em outro terminal:

```bash
bin/ralph-monitor \
  --workflow wf_exemplo_20260810_001 \
  --interval 30
```

O monitor e o hook observam; decisões usam sempre o controlador:

```bash
bin/ralph-control status --workflow wf_exemplo_20260810_001
```

Feedback ao orquestrador deve ser curto e factual:

```text
[Ralph] FEATURE-001 concluída: os cinco gates foram aprovados; handoff gerado.
O ralph-control selecionará a próxima feature.
```

Nunca converta `phase_done`, `run_end`, screenshot ou texto do provider em
aprovação. Aguarde a projeção do controlador e os cinco gates registrados.

### 0.6 Reagir a falha ou interrupção

Se parecer parado:

1. leia o último snapshot do monitor e o último evento do ledger;
2. consulte `ralph-control status`;
3. verifique processo ativo antes de encerrar qualquer terminal;
4. não execute um segundo supervisor;
5. em crash, use `continue` e aguarde `recovery_required`;
6. encaminhe a falha ao systematic debugging;
7. só crie novo lease/retry após diagnóstico verificável;
8. registre causa, hipótese, correção e evidência antes/depois no handoff.

```bash
bin/ralph-control continue --workflow wf_exemplo_20260810_001
```

`recovery_required`, `debugging_required` e `knowledge_review_required` são
estados explícitos. Não force `approved`, edite o ledger ou avance a fila
manualmente para “destravar” a execução.

### 0.7 Encerrar e preservar conhecimento

Ao concluir a feature, confirme os cinco gates, handoff, evidências, commit,
árvore e liberação pelo controlador. A memória candidata pode ser curada,
rejeitada, descartada ou revisada; nesta versão ela é não bloqueante. Use
`ralph-knowledge candidates` e retenção explícita, sem copiar eventos brutos
para `docs/engineering/`.

### 0.8 Desinstalar com segurança

Faça primeiro o plano somente de leitura:

```bash
"$METHOD_ROOT/bin/ralph-init" uninstall \
  --project "$PROJECT_ROOT"
```

Use `--apply` apenas após revisar os arquivos. O método preserva runtime,
workflow, handoffs, relatórios e arquivos modificados pelo usuário.

### 0.9 Pós-atualização do harness e diagnóstico de MCP

Após atualizar o Codex CLI, um plugin MCP, o runtime usado por um servidor ou
o profile do harness, faça uma validação curta antes de retomar o trabalho
normal. Se o Codex exibir `MCP startup interrupted`, não desabilite o servidor,
troque provider ou aumente o timeout sem diagnóstico.

1. confirme a versão e a configuração efetiva sem expor ambiente sensível:

   ```bash
   codex --version
   codex --profile bc-harness mcp list --json
   ```

2. para cada servidor nomeado no erro, execute o comando configurado diretamente
   com um handshake MCP mínimo (`initialize` e, quando aplicável,
   `tools/list`), usando timeout explícito e sem prompts ou geração;
3. se o handshake direto falhar, corrija o servidor, dependência,
   autenticação ou ambiente específico antes de alterar o launcher;
4. se o handshake direto passar, mas o startup do Codex falhar, confira a
   resolução do executável (`command -v <executável>`) e use o caminho absoluto
   no profile, preservando os argumentos, transporte e timeouts já validados;
5. reinicie o Codex em uma sessão nova e confirme que os MCPs esperados chegam
   ao estado inicializado, que o prompt aparece e que não há novo aviso de
   startup interrompido;
6. registre causa, hipótese, correção e evidência sanitizada no capture log e,
   se for uma falha nova, em um incidente. Não registre tokens, prompts,
   respostas completas ou valores de ambiente.

O caminho absoluto é uma mitigação condicional para falha de resolução do
launcher. Não é uma regra para substituir qualquer `command` por caminho
absoluto quando o handshake direto também estiver falhando. A decisão completa
está no [`ADR-0014`](adr/0014-diagnostico-mcp-pos-atualizacao-de-harness.md), e o
caso que originou a rotina no [`Incidente 0014`](incidents/0014-startup-mcp-pos-atualizacao-codex.md).

## 1. Princípios que o agente deve respeitar

Antes de agir, leia nesta ordem:

1. `AGENTS.md` do projeto-alvo e os `AGENTS.md` mais próximos do diretório;
2. `docs/STATUS.md`;
3. `docs/architecture/` relevante;
4. ADRs aceitos em `docs/adr/`;
5. este guia;
6. o workflow e a feature autorizada.

As instruções do projeto-alvo e a solicitação atual do usuário têm precedência
sobre este guia. O guia explica o método; não concede autorização para ignorar
regras do projeto.

O agente nunca deve:

- escolher a próxima feature por conta própria;
- aprovar gate por texto, screenshot ou promessa;
- editar o ledger diretamente;
- expor lease token, credencial, prompt completo ou resposta completa;
- iniciar provider alternativo silenciosamente;
- apagar arquivos do projeto com `rm -rf`, `git reset --hard` ou restauração
  global;
- considerar um callback, hook ou feedback externo como autoridade.

## 2. Autoridade e responsabilidades

| Papel | Responsabilidade | Limite obrigatório |
|---|---|---|
| `ralph-control` | estado, lease, fencing, locks de workflow e execução, gates, recuperação e avanço | única autoridade de transição |
| `ralph.sh` | executar uma fase por sessão e produzir código/testes | não escolhe a próxima feature |
| implementação | alterar código dentro da feature autorizada | não cria commit nem altera o plano |
| revisão técnica | verificar código e critérios em modo read-only | deve ser independente do implementador |
| curadoria de entrega | confirmar os cinco gates e o handoff | não é curadoria de memória |
| `ralph-trace` | registrar delegações e identidade de provider | não aprova nem libera |
| `ralph-monitor` | mostrar saúde, processo, progresso e último feedback | não faz retry, recovery ou avanço |
| `ralph-metrics` | agregar o ledger em JSON/Markdown | não muta eventos, estados, gates ou custo/token |
| hook | observar eventos e emitir fatos | não muda estado global |
| orquestrador externo | exibir andamento e encaminhar decisões ao controlador | não interpreta feedback como aprovação |
| adapter de provider | normalizar runner, modelo e sessão | não grava ledger nem estado de produto |

Fluxo de autoridade:

```text
agente executa
→ loop emite feedback
→ hook/trace observam fatos
→ ledger registra
→ gates comprovam
→ ralph-control decide
→ handoff documenta
→ próximo bloco é autorizado
```

## 3. Como agentes se comunicam

### 3.1 Pacote de contexto enviado ao agente filho

O orquestrador deve iniciar cada agente com um pacote explícito contendo:

```json
{
  "workflow_id": "wf_exemplo_20260807_001",
  "feature_key": "FEATURE-001",
  "attempt": 1,
  "role": "implementation",
  "scope": ["app/", "tests/"],
  "acceptance_criteria": ["..."],
  "test_command": "bin/check",
  "evidence_required": ["test_output", "runtime_evidence"],
  "parent_execution_id": "exec_parent_001",
  "constraints": ["não editar .spec", "não criar commit"]
}
```

O lease token pode existir no ambiente interno do controlador, mas nunca deve
ser colocado no feedback visível, em documentação, em prompt salvo ou em uma
mensagem para outro agente que não precise dele.

### 3.2 Identidade de execução

Toda delegação deve possuir `execution_id` com formato `exec_<id>`. Quando for
uma delegação filha, use `parent_execution_id` e, quando aplicável,
`root_execution_id`. O provider deve informar a identidade do modelo com uma
das classificações:

```text
exact | declared | observed | partial | unavailable
```

Se o provider não comprovar o modelo efetivo, o agente deve declarar a
limitação. Nunca transforme um modelo apenas solicitado em modelo confirmado.

O registro deve passar pelo controlador, por exemplo:

```bash
bin/ralph-control trace \
  --workflow wf_exemplo_20260807_001 \
  --feature FEATURE-001 \
  --lease "$RALPH_LEASE_TOKEN" \
  --event started \
  --execution-id exec_implementation_001 \
  --runner codex \
  --role implementation \
  --identity-status declared \
  --identity-source runtime_configuration
```

O agente não deve executar `ralph-control trace` com texto inventado para
preencher lacunas. Se a evidência não existe, use `unavailable` ou registre a
falha factual.

### 3.3 Feedback do loop

O loop publica eventos JSON conforme
`schemas/feedback-event.schema.json`. Em modo controlado, os campos de
correlação estão presentes:

```json
{
  "schema_version": "1.0.0",
  "run_id": "run_20260807T180000Z_1234",
  "workflow_id": "wf_exemplo_20260807_001",
  "feature_key": "FEATURE-001",
  "attempt": 1,
  "timestamp": "2026-08-07T18:00:00Z",
  "event": "phase_done",
  "state": "completed",
  "health": "ok",
  "engine": "codex",
  "phase": {"number": 1, "total": 4, "title": "Exemplo", "attempt": 1},
  "progress": {"percent": 25},
  "detail": "fase concluída",
  "source": "ralph"
}
```

Os destinos são:

- JSONL local: `.git/ralph-control/feedback/events.jsonl`;
- terminal: `RALPH_FEEDBACK_STDOUT=1`;
- callback: `RALPH_FEEDBACK_CMD=/caminho/do/consumidor`;
- relay do bloco controlado: `ralph-control run` retransmite linhas
  `RALPH_FEEDBACK` enquanto o processo está vivo.

O consumidor deve usar `run_id`, `workflow_id`, `feature_key`, `attempt` e
`event` para correlacionar a tela. Ele pode apresentar uma mensagem amigável,
mas deve sempre consultar `ralph-control status` para decisões. Feedback
ausente ou atrasado significa falta de observabilidade, não aprovação.

Para uma revisão OpenCode, o controlador exige `RALPH_OPENCODE_VERIFY_AGENT`
e uma prova externa. O runner recebe essa prova por
`RALPH_OPENCODE_VERIFY_POLICY_PROOF` ou pelo argumento `--policy-proof`;
ausência de ambas bloqueia a chamada à CLI. Gere a prova somente fora da raiz
mutável:

```bash
scripts/opencode-readonly-proof.sh \
  --repo-root "$PROJECT_ROOT" \
  --agent ralph-review \
  --model "$RALPH_OPENCODE_MODEL" \
  --proof-file /tmp/ralph-readonly-policy-proof.json
```

O resultado do runner registra `permission_policy_hash` e o status da prova;
não copie o JSONL nem a resposta completa para documentação versionada.
Na prova, `policy_denied_tools` registra as negações verificadas no fingerprint
da política; `denied_tools_seen` registra apenas recusas que a CLI expôs como
eventos. Com `*: deny`, uma ferramenta pode ficar indisponível em vez de gerar
um evento, e o resultado continua válido somente com sessão terminal, canário
ausente, superfície de política preservada, marcador presente no JSONL e
política revalidada.

Para uma revisão `agy`, não gere proof externo. O adapter calcula o hash sobre
o runner, parser, policy e agente instalados e exige o token OAuth fora do
projeto. O preflight falha antes da geração se Linux, `bwrap`, token ou agente
`ralph-review` estiverem ausentes. Durante o verify, somente o projeto,
runtime mínimo e token são montados; `/tmp` e app-data são efêmeros, o ambiente
é limpo e um `settings.json` controlado define
`allowNonWorkspaceAccess=false` e nenhuma permissão de comando. O agente usa
`commandExecutionPolicy: strict`, MCP desativado e `--mode plan` como defesas
adicionais. Configure:

```bash
RALPH_AGY_MODEL=gemini-3.7-flash-high
RALPH_AGY_EFFORT=high
RALPH_AGY_VERIFY_AGENT=ralph-review
RALPH_VERIFY_MODEL=gemini-3.7-flash-high
```

Não grave o token em `.ralph/agy.env`; o caminho padrão é resolvido pela sessão
local do `agy`, e `RALPH_AGY_TOKEN_FILE` serve somente para um caminho local
alternativo fora de `PROJECT_ROOT`.

### 3.4 Prontidão de providers

A existência de uma CLI não habilita seu adapter. O estado precisa avançar
assim:

```text
unavailable|detected
→ autenticação confirmada
→ diagnóstico local seguro
→ functional
→ runner suportado
→ adapter_enabled=true
```

O plano padrão não consulta autenticação. Para solicitar probes explícitos,
use:

```bash
"$METHOD_ROOT/bin/ralph-init" plan \
  --project "$PROJECT_ROOT" \
  --provider auto \
  --verify-providers
```

O modo `safe` usa somente comandos diagnósticos do provider, tem timeout,
redige a saída e não inicia conversa, não envia prompt e não executa probe de
geração. `functional` significa que a sessão da CLI foi confirmada e o
diagnóstico local não generativo passou; não é uma afirmação de que uma
chamada de modelo foi consumida ou concluída.

`runner_supported` separa a certificação da sessão da existência do adapter de
execução no Ralph. `adapter_enabled` só fica verdadeiro quando a CLI está
functional e o runner correspondente já está implementado nesta versão.
OpenCode usa `auth list` e `models`; `agy` usa `models` e `agents`, depois
comprova Linux, `bwrap` e token OAuth legível. A presença do agente
`ralph-review` no workspace é validada pelo preflight do adapter
(`.agents/agents/ralph-review/agent.md`) e pela policy como superfície; a
listagem global `agy agents` expõe somente agentes instalados da sessão local
e não decide a elegibilidade do agente de verify. Hermes identifica o provider selecionado
no próprio `status` (ou respeita `RALPH_HERMES_PROVIDER`) e valida
`auth status <provider>`. O status de outros providers listados pelo Hermes
não reprova o provider selecionado.

Estados importantes em `.ralph/providers.json`:

```text
unavailable | detected | authentication_unknown | unauthenticated
authenticated | functional | degraded | unsupported
```

Somente uma CLI `functional` com `runner_supported=true` pode definir
`adapter_enabled=true`. Um provider alternativo explicitamente solicitado no
`apply` é recusado se não estiver functional e com adapter disponível. Em
`auto`, a instalação do núcleo pode continuar em
`orchestration.mode=needs_review`, sem fallback silencioso. Hermes tenta
identificar automaticamente o provider selecionado e aceita
`RALPH_HERMES_PROVIDER` como override. Quando não houver runner apto, o plano deixa
`selection.selected_provider` e `orchestration.primary_runner` como `null`; não
materializa um executor fantasma.

### 3.5 Configuração após a identificação do harness

Depois de executar `plan --provider auto --verify-providers`, o agente deve
seguir uma decisão determinística. Não escolha um provider pela preferência do
modelo ou por uma mensagem textual do CLI; use os campos do plano.

| Resultado do plano | Configuração correta | Próxima ação |
|---|---|---|
| `selected_provider=codex` e `adapter_enabled=true` | runner nativo Codex; perfil `.ralph/codex.env` | aplicar e executar pelo loop |
| `selected_provider=claude` e `adapter_enabled=true` | runner nativo Claude CLI; perfil `.ralph/claude.env` | aplicar e executar pelo loop |
| `selected_provider=opencode` e `adapter_enabled=true` | adapter OpenCode; preencher modelo/agente e prova read-only | aplicar, configurar e validar antes da revisão |
| `selected_provider=agy` e `adapter_enabled=true` | adapter `agy`; preencher modelo/effort e preservar token fora do projeto | aplicar e validar preflight impl/verify antes do loop |
| `selected_provider=null` ou `mode=needs_review` | nenhum executor autorizado | não executar; corrigir prontidão ou solicitar decisão |
| Hermes detectado sem adapter | readiness apenas | não promover; registrar ou consultar backlog |

O procedimento padrão é:

```bash
PLAN_JSON="$($METHOD_ROOT/bin/ralph-init plan \
  --project "$PROJECT_ROOT" \
  --provider auto \
  --verify-providers)"

RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" apply \
  --project "$PROJECT_ROOT" \
  --provider auto \
  --verify-providers

"$PROJECT_ROOT/bin/ralph-doctor" --project "$PROJECT_ROOT"
```

O agente deve interromper se o JSON indicar `conflict`, `needs_review`,
`adapter_enabled=false`, working tree inconsistente ou ausência de comando de
qualidade. A variável `PLAN_JSON` é apenas um exemplo de captura local; não
salve credenciais ou a saída integral em prompt, ledger ou documentação.

#### Configuração específica por harness

- **Codex:** use o perfil gerado `.ralph/codex.env`. O loop nativo mantém a
  execução e a revisão dentro do contrato do `ralph-control`; registre no
  `ralph-trace` o modelo somente quando o runtime o comprovar.
- **Claude CLI:** use `.ralph/claude.env`. O princípio é o mesmo do Codex:
  runner nativo, uma feature por bloco, gates no controlador e identidade
  marcada como `declared`, `observed` ou `exact` conforme a evidência.
- **OpenCode:** use `.ralph/opencode.env`, preencha
  `RALPH_OPENCODE_MODEL`, `RALPH_OPENCODE_AGENT` e, para technical review,
  gere `RALPH_OPENCODE_VERIFY_POLICY_PROOF` fora da raiz mutável. A ausência
  da prova ou do agente read-only bloqueia a chamada.
- **agy:** use `.ralph/agy.env`, preencha `RALPH_AGY_MODEL` e, se necessário,
  `RALPH_VERIFY_MODEL`. Não copie credenciais. O verify só pode avançar após
  `adapters/agy/runner.sh preflight --mode verify --repo-root "$PROJECT_ROOT"`.
- **Hermes:** não configure execução nesta versão. A presença da CLI não
  implica adapter; o agente deve manter `needs_review` ou seguir o backlog.

Após o `apply`, confira `.ralph/method.json`, `.ralph/providers.json` e o
manifesto de ownership. Esses arquivos descrevem a instalação local; não são
autorização para ignorar o workflow, os gates ou o lease.

## 4. Instalação em um projeto-alvo

Defina o caminho do checkout do Ralph Method e o caminho do projeto. O projeto
alvo precisa ser um checkout Git.

```bash
METHOD_ROOT=/caminho/para/ralph-method
PROJECT_ROOT=/caminho/para/projeto
```

### 4.1 Auditar antes de instalar

```bash
git -C "$PROJECT_ROOT" status --short
git -C "$PROJECT_ROOT" rev-parse --show-toplevel
"$METHOD_ROOT/bin/ralph-init" plan --project "$PROJECT_ROOT"
```

Leia o JSON do plano. Procure especialmente por:

- `conflict` em qualquer arquivo;
- provider detectado e seu `auth_status`;
- `status`, `health_status` e `adapter_enabled` do provider;
- `runner_supported`, `functional_providers` e `available_runners`;
- comando de teste detectado;
- sinais de `.codex`, `.claude` ou OpenCode;
- `ralph_installation.method` e `ralph_installation.external`;
- working tree suja;
- modo `needs_review` quando não houver runner habilitado.

`plan` não altera o projeto.

Para auditar autenticação e prontidão sem gerar uma mensagem:

```bash
"$METHOD_ROOT/bin/ralph-init" plan \
  --project "$PROJECT_ROOT" \
  --provider auto \
  --verify-providers
```

### 4.2 Aplicar a instalação

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" apply \
  --project "$PROJECT_ROOT" \
  --provider auto \
  --verify-providers
```

O instalador cria uma cópia local dos componentes, `.ralph/method.json`,
`.ralph/providers.json`, perfis de execução e
`.ralph/install-manifest.json`. Os perfis Codex e Claude apontam para
`scripts/ralph.sh` do próprio projeto.

Providers aceitos pelo instalador:

```text
auto | codex | claude | opencode | hermes | agy
```

`auto` só materializa como executor o provider com `adapter_enabled=true`. Se
nenhum provider estiver funcional, a instalação do núcleo termina com
`needs_review` e não habilita adapter. Uma seleção explícita de provider não
funcional falha fechada; corrija a sessão e repita o comando com
`--verify-providers`.

### 4.3 Verificar a instalação

```bash
"$PROJECT_ROOT/bin/ralph-doctor" --project "$PROJECT_ROOT"
```

Resultado esperado:

```json
{"status":"healthy", "runtime_preserved":true}
```

Se houver `drift_detected`, pare o fluxo, leia os paths divergentes e não
substitua arquivos modificados automaticamente.

## 5. Configuração e execução do workflow

### 5.1 Criar ou revisar o manifesto de features

O arquivo de origem do workflow deve ser versionável no projeto. Ele deve
conter `workflow_id`, `plan_file` ou dados equivalentes e uma lista ordenada de
features pendentes. Exemplo mínimo:

```json
{
  "schema_version": "1.0.0",
  "workflow_id": "wf_exemplo_20260807_001",
  "plan_file": ".spec/init/project-phases.md",
  "knowledge_policy": {"mode": "non_blocking"},
  "features": [
    {"feature_key":"FEATURE-001", "title":"Primeira feature", "position":1}
  ]
}
```

`knowledge_policy.mode` controla memória de engenharia; conhecimento não é
gate obrigatório de entrega nesta configuração. O arquivo de workflow não
deve ser editado pelo agente durante uma execução autorizada.

### 5.2 Inicializar o control plane

```bash
cd "$PROJECT_ROOT"
bin/ralph-control init \
  --workflow wf_exemplo_20260807_001 \
  --manifest workflow.json
```

O controlador copia a definição para o runtime local em
`.git/ralph-control/workflow.json` e começa o ledger em
`.git/ralph-control/events.jsonl`. O runtime local não substitui o manifesto
versionado de origem.

### 5.3 Rodar a fila automaticamente

Modo supervisionado, recomendado para execução contínua:

```bash
bin/ralph-control supervise \
  --workflow wf_exemplo_20260807_001 \
  --interval 30 \
  --max-retries 3
```

O supervisor seleciona somente a feature autorizada, adquire lease, executa
um bloco, acompanha heartbeat, roda gates, aciona systematic debugging quando
necessário e tenta avançar apenas após o estado correto. O monitor de tela
pode rodar em outro terminal:

```bash
bin/ralph-monitor \
  --workflow wf_exemplo_20260807_001 \
  --interval 30
```

Para uma visão histórica compacta, use `bin/ralph-metrics`:

```bash
bin/ralph-metrics --workflow wf_exemplo_20260807_001 --format markdown
bin/ralph-metrics --feature FEATURE-123 --format json
```

O comando lê `.git/ralph-control/events.jsonl`, agrega contagens e durações e
escreve apenas em stdout. Ele não corrige ledger, não muda estados, não
autoriza gates e não mede custos ou tokens.

Textos provenientes de runners são sanitizados para UTF-8 antes de entrarem
em eventos ou resultados JSON. Bytes inválidos são removidos de forma
determinística; isso evita que uma mensagem binária do provider derrube o
encerramento do bloco ou corrompa a saída estruturada.

Para uma retomada pontual do controlador, use:

```bash
bin/ralph-control continue --workflow wf_exemplo_20260807_001
```

Não execute vários supervisores no mesmo checkout. O lock do supervisor existe
para impedir concorrência.

Além do lock do supervisor, cada bloco controlado adquire uma exclusividade por
`workflow_id + feature_key` em `.git/ralph-control/executions/`. Se outra sessão
tentar executar a mesma feature enquanto o bloco estiver ativo, ela será
rejeitada antes de iniciar provider ou processo. O `workflow.lock` protege as
escritas curtas de estado e ledger; ele não permanece retido durante a execução
do agente.

## 6. Gates, estados e evidências

Uma feature só pode avançar quando os cinco gates estão comprovados:

```text
validation
quality
runtime_evidence
technical_review
curation
```

Estados normais:

```text
pending → running → awaiting_gates → approved → released → next_feature
```

Estados de atenção:

```text
blocked | recovery_required | debugging_required | knowledge_review_required
```

O agente deve produzir ou localizar evidências reais: saída do comando de
qualidade, testes, runtime evidence, screenshot quando aplicável, logs
relevantes, revisão independente e handoff. A curadoria de conhecimento pode
ser `non_blocking`, mas não deve ser descartada silenciosamente.

O handoff deve registrar o que ocorreu, erros encontrados, correções, arquivos,
commit, evidência antes/depois, comprovação e risco residual. Nunca copie
prompts completos ou segredos para o handoff.

## 7. Memória episódica, retenção e índices

A memória de engenharia é uma camada pós-entrega e não substitui os cinco
gates. Depois de `feature.released`, o controlador cria um candidato local em
`.ralph/knowledge-candidates/` e registra `knowledge.candidate_created`. Esse
manifesto é um cache sanitizado da execução: contém somente workflow, feature,
tentativa, handoff e decisão de retenção; não contém prompts, respostas,
credenciais ou eventos brutos. Ao materializar o primeiro candidato, o
controlador também registra `/.ralph/knowledge-candidates/` em
`.git/info/exclude`; esse cache não deve sujar a árvore nem ser adicionado ao
`.gitignore` versionado.

Liste os candidatos antes de decidir o que deve permanecer:

```bash
bin/ralph-knowledge candidates
```

As ações de decisão são explícitas e não bloqueiam a fila:

```bash
bin/ralph-control knowledge curated \
  --workflow wf_exemplo_20260807_001 \
  --feature FEATURE-001 \
  --title "Saída externa precisa ser normalizada" \
  --summary "Normalizar bytes antes do ledger evita falha de serialização." \
  --category providers \
  --topics utf8,jsonl \
  --stack php,bash \
  --domain orchestration \
  --fingerprints invalid-provider-output \
  --root-cause invalid-external-output \
  --commit abc123 \
  --test scripts/test-ralph-method.sh
```

Use `knowledge rejected --reason "..."` quando o candidato não tiver
aprendizado reutilizável, `knowledge skipped` quando a curadoria for dispensada
e `knowledge review-required` quando a decisão exigir análise posterior. Essas
ações preservam o fato no ledger, mas não publicam uma lição. Uma decisão de
retenção já registrada não pode ser substituída por outra decisão conflitante.

Uma lição curada recebe ID `LES-YYYY-NNNN` e é gravada em
`docs/engineering/lessons/`. O Ralph também mantém projeções hierárquicas:

```text
docs/engineering/
├── INDEX.md
├── categories/<categoria>.md
├── topics/<tema>.md
└── lessons/<lição>.yaml + <lição>.md
```

`INDEX.md` é o índice macro. Os arquivos de `categories/` e `topics/` são
subíndices gerados e podem ser reconstruídos com:

```bash
bin/ralph-control document-index
```

Consulte somente conhecimento validado, aplicando filtros estruturados antes
de entregar contexto ao agente:

```bash
bin/ralph-knowledge retrieve \
  --query "provider jsonl utf8" \
  --category providers \
  --topic utf8 \
  --stack php \
  --limit 3
```

A política de continuidade continua sendo `knowledge_policy.mode:
non_blocking`. Isso é diferente da retenção: liberar a feature e decidir se
uma lição deve ser persistida são decisões separadas. Descartar um candidato
não apaga evidências, handoff ou eventos operacionais.

## 8. Falha, pane ou interrupção

Ao detectar uma pane:

1. não mate processos sem identificar o checkout e o grupo correto;
2. consulte o snapshot:

   ```bash
   bin/ralph-monitor --workflow wf_exemplo_20260807_001 --once --json
   ```

3. consulte o estado autoritativo:

   ```bash
   bin/ralph-control status --workflow wf_exemplo_20260807_001
   ```

4. confira `events.jsonl`, heartbeat, lease e working tree;
5. se o estado for `debugging_required`, o supervisor deve acionar systematic
   debugging read-only;
6. se o estado for `recovery_required`, pare e faça recuperação explícita e
   auditável antes de nova tentativa;
7. depois da correção comprovada, deixe o controlador iniciar a próxima
   tentativa.

Uma queda de energia ou encerramento do terminal não autoriza avanço silencioso.
O estado incompleto deve ser reconciliado pelo controlador.

## 9. Atualização do Ralph Method

Antes de atualizar:

```bash
git -C "$PROJECT_ROOT" status --short
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" plan --project "$PROJECT_ROOT"
```

Se o plano mostrar `conflict`, preserve o arquivo modificado e resolva a
decisão explicitamente. Não force overwrite.

Se o plano mostrar `ralph_installation.external.status` como `detected` ou
`ambiguous`, interrompa a atualização normal e use `evolve --plan`. O Ralph
Method não assume que conhece o contrato da instalação antiga: a evolução
isola somente sinais detectados, preserva o histórico e não importa estado.

Depois da atualização:

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" apply \
  --project "$PROJECT_ROOT" \
  --provider auto
"$PROJECT_ROOT/bin/ralph-doctor" --project "$PROJECT_ROOT"
```

Rode as validações do Ralph Method antes de publicar uma nova versão:

```bash
bash scripts/check-shell.sh
bash scripts/check-doc-sync.sh
bash scripts/test-installation.sh
bash scripts/test-feedback.sh
bash scripts/test-provider-readiness.sh
bash scripts/test-multiprovider.sh
bash scripts/test-ralph-method.sh
bash scripts/test-ralph.sh
bash scripts/test-reproducibility.sh
```

## 10. Desinstalação segura

Primeiro gere o plano, sem alterar o projeto:

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" uninstall \
  --project "$PROJECT_ROOT"
```

Revise cada ação. `remove` é seguro apenas quando o arquivo ainda corresponde
ao hash instalado. `preserve_modified` deve permanecer no projeto. Para
aplicar:

```bash
RALPH_METHOD_SOURCE="$METHOD_ROOT" \
  "$METHOD_ROOT/bin/ralph-init" uninstall \
  --project "$PROJECT_ROOT" \
  --apply
```

O uninstall preserva:

```text
.git/ralph-control/
.git/ralph-control/workflow.json
.ralph/handoffs/
.ralph/reports/
```

O relatório fica em `.ralph/uninstall-report.json`. Se um arquivo foi
modificado, o agente deve entregar a decisão ao usuário; nunca removê-lo por
conveniência.

## 11. Checklist de encerramento do agente

Antes de declarar uma feature ou etapa concluída, confirme:

- [ ] li `AGENTS.md`, `docs/STATUS.md`, arquitetura e ADRs relevantes;
- [ ] estou usando o `workflow_id`, `feature_key`, `attempt` e `execution_id`
      corretos;
- [ ] não alterei plano aprovado, lease, ledger ou arquivos fora do escopo;
- [ ] o comando real de qualidade terminou com exit code `0`;
- [ ] runtime evidence existe quando aplicável;
- [ ] technical review e curation foram produzidos por atores independentes;
- [ ] handoff e referências de evidência foram gerados;
- [ ] feedback foi emitido sem dados sensíveis;
- [ ] o estado foi confirmado pelo `ralph-control`;
- [ ] não iniciei a próxima feature diretamente;
- [ ] `bash scripts/check-doc-sync.sh` passou quando alterei documentação ou
      versão.

Se qualquer item estiver pendente, reporte `blocked` ou `recovery_required`
com a causa factual e as evidências disponíveis. Não use `completed` por
inferência.
