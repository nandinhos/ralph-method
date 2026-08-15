# SPEC — Adapter nativo Antigravity CLI (`agy`)

## 1. Intenção confirmada

Reabrir o item adiado `BL-0002` e tornar `agy` um runner de primeira classe do
Ralph Method, ampliando a capacidade do loop sem alterar autoridade, gates ou
política de fallback.

## 2. Resultado esperado

Um projeto Linux com `agy` autenticado e `bwrap` operacional pode:

1. comprovar readiness com probes não generativos;
2. instalar o adapter e o agente por ownership;
3. executar implementação headless em uma sessão nova;
4. executar verificação em outra sessão com raiz read-only;
5. normalizar a sessão no schema comum e submeter a fase aos gates existentes.

## 3. Evidência upstream e local

- binário observado: `agy 1.1.13`;
- modelos/agentes: `agy models` e `agy agents`;
- headless: `--print`, `--output-format stream-json`, `--model`, `--effort`;
- sequência observada/documentada: `init`, `step_update`, `result`;
- agente workspace: `.agents/agents/<agent>/agent.md`;
- `--mode plan` não garante read-only: prova controlada executou
  `write_to_file` fora da raiz pedida;
- `--disable-slash-commands` torna `--mode plan` sem efeito na versão observada;
- `bwrap` com allowlist de mounts, app-data efêmero, policy local restritiva e
  token OAuth read-only concluiu uma sessão autenticada real;
- `view_file` real terminou em `ERROR` ao tentar ler um canário no diretório do
  token, comprovando a negação preventiva fora do workspace.

## 4. Requisitos funcionais

### RF-01 — Readiness

- `providerDefinitions()` deve registrar probes `models` e `agents` para `agy`;
- probes não podem invocar `--print`, prompt ou inferência;
- autenticação exige catálogo de modelo reconhecível;
- health exige lista de agente reconhecível;
- suporte operacional exige Linux, `bwrap` executável e token OAuth legível;
- falha de qualquer requisito mantém `adapter_enabled=false`.

### RF-02 — Estrutura do adapter

```text
adapters/agy/
├── contract.md
├── runner.sh
├── parser.php
└── policy.php
```

O runner deve expor `preflight`, `run` e `version`.

### RF-03 — Implementação

- usar modelo e effort explícitos;
- usar `stream-json` e timeout explícito;
- usar `--mode accept-edits` e `--dangerously-skip-permissions` somente em impl;
- ler o prompt de `--prompt-file`, calcular SHA-256 e passá-lo à CLI sem
  persistir seu conteúdo em resultado, ledger ou documentação;
- executar dentro de `repo-root`.

### RF-04 — Verificação

- exigir agente `ralph-review` instalado no workspace;
- usar `--mode plan` e `--sandbox`, sem `--disable-slash-commands`;
- executar dentro de `bwrap` com raiz vazia e allowlist explícita;
- montar read-only somente `/usr`, arquivos mínimos de rede/certificados, o
  binário `agy` e `repo-root`;
- montar `/tmp` e app-data da CLI como temporários;
- montar `antigravity-oauth-token` read-only no app-data;
- ocultar `settings.json` global e montar policy efêmera com
  `allowNonWorkspaceAccess=false`, sem comandos liberados;
- limpar o ambiente e repor apenas `HOME`, `USER`, `PATH` e locale;
- rejeitar antes da geração symlink quebrado/externo e hardlink para o token;
- reprovar qualquer ferramenta fora da allowlist de leitura;
- rejeitar campos desconhecidos no schema de parâmetros de cada ferramenta;
- publicar policy hash e `verification_agent`.

### RF-05 — Normalização

O resultado deve usar `schema_version=1.1.0` para `agy`, preservando resultados
OpenCode `1.0.0` e reservando `2.0.0` ao contrato de failover, com:

- `runner` e `provider` iguais a `agy`;
- `terminal_event` igual a `result` quando completed;
- `session_id` vindo de `conversation_id`;
- `effective_model` observado em `init`;
- `fallback_status=not_detected` somente com modelo observado igual ao pedido;
- `status=failed` para JSONL inválido, múltiplas sessões/resultados, terminal
  ausente, modelo divergente, ferramenta proibida ou policy inválida;
- eventos persistidos sem prompt, resposta, parâmetros ou output de ferramenta.
- saída textual de verify limitada a `TASK <n>: DONE|INCOMPLETE`; impl não
  persiste resposta textual.
- qualquer prosa, exemplo, comentário ou task duplicada no veredito reprova a
  sessão em vez de ser canonicalizada.

### RF-06 — Loop

- aceitar `--engine agy` por uma seam comum baseada em `preflight|run|version`;
- preflight chamar o adapter e validar effort/model/verify;
- `run_engine` não pode cair no branch Claude;
- gate 0 comum aos adapters deve exigir resultado normalized completed, exit 0,
  sessão e terminal;
- impl e verify devem usar sessões novas;
- usage limit mantém a política atual, sem troca de provider.

### RF-07 — Instalação

- gerenciar `adapters/agy/*` e `.agents/agents/ralph-review/agent.md`;
- gerar `.ralph/agy.env` sem credencial ou segredo;
- aplicar ownership, staging, conflito e uninstall existentes;
- doctor deve observar os arquivos pelo manifesto normal.

## 5. Invariantes

1. `bin/ralph-control` permanece a única autoridade de estado/ledger.
2. Adapter normaliza saída e nunca aprova gate ou grava estado global do Ralph.
3. Não há fallback silencioso; `fallback_policy=none` permanece.
4. `--mode plan` é defesa em profundidade, não fronteira de segurança.
5. Token é lido/montado, nunca copiado para o projeto ou logado.
6. Prompt/resposta completa não entram em result, readiness, feedback, trace ou docs.
7. Verify sem isolamento comprovado falha antes da geração.
8. Superfícies de verify alteradas por `impl` bloqueiam o gate antes do adapter.
9. `FEATURE-094` não é alterada nem parcialmente implementada.
10. OpenCode continua emitindo `runner-result 1.0.0`; `agy` emite `1.1.0`.

## 6. Critérios de aceitação verificáveis

- CA-01: fixture de readiness habilita `agy` apenas com modelos, agentes,
  `bwrap` e token; o fake falha se qualquer comando generativo for chamado.
- CA-02: preflight impl retorna `not_required`; verify retorna hash SHA-256 e
  agente `ralph-review` somente após smoke não generativo do `bwrap`.
- CA-03: fixture parser aceita uma sequência válida `init → step_update → result`.
- CA-04: fixture parser rejeita JSON inválido, segundo `result`, segunda sessão,
  modelo divergente, `result` não final e evento de ferramenta proibida.
- CA-05: teste adversarial tenta escrever sob `bwrap` real, comprova raiz
  idêntica e prova com CLI real que leitura externa termina em `ERROR` antes de
  expor o canário.
- CA-06: teste do loop prova que `agy` chama o adapter em impl e verify e que o
  gate 0 usa o resultado normalizado.
- CA-07: instalação/reprodução prova criação e remoção segura de todos os arquivos.
- CA-08: schema valida resultados OpenCode e `agy` com terminais próprios.
- CA-09: suite obrigatória de `AGENTS.md` termina com exit zero.
- CA-10: smoke real sanitizado em `agy 1.1.13` comprova sessão, modelo, terminal
  e isolamento; nenhum conteúdo bruto é publicado no relatório.

## 7. Casos de erro

| Caso | Resultado esperado |
|---|---|
| `agy` ausente | unavailable/erro de preflight |
| modelo vazio | erro antes da geração |
| `bwrap` ausente | verify/readiness degradado |
| token ausente | verify/readiness degradado |
| plataforma não Linux | verify não suportado na v1 |
| timeout | status não completed e exit não zero |
| status upstream diferente de SUCCESS | failed |
| ferramenta desconhecida em verify | failed |
| arquivo gerenciado conflitante | apply bloqueado |

## 8. Fora de escopo

- macOS/Windows para verify v1;
- failover, circuit breaker, capsule ou runner-result v2;
- aliases `antigravity`/`agy` simultâneos no schema;
- TUI ou aprovação humana;
- coleta de custo/tokens;
- mudança da máquina de estados.

## 9. Riscos residuais

- a CLI pode mudar o formato do JSONL; mitigação: parser fail-closed e teste real;
- o kernel pode desabilitar user namespaces; mitigação: readiness degradado;
- o prompt segue transporte file-to-argument por limitação da CLI; o conteúdo
  não é persistido pelo adapter, mas pode ser visível transitoriamente ao mesmo
  usuário no process table;
- o agente pode tentar escrever em app-data efêmero ou `/tmp`; o parser reprova
  a ferramenta e o mount namespace protege a raiz persistente.

## 9.1 Limites operacionais v1

| Limite | Default | Gatilho para revisar |
|---|---:|---|
| prompt | 262144 bytes | 1% das sessões alcançar 80% em 30 dias |
| stream JSONL | 5242880 bytes | mesmo gatilho |
| eventos | 10000 | mesmo gatilho |
| duração | 1800 segundos | mesmo gatilho |
| concorrência por feature | 1 runner | requisito de paralelismo aprovado pelo controlador |

## 9.2 Projeção sanitizada de eventos verify

Ferramentas permitidas: `view_file`, `list_dir`, `grep_search` e
`find_by_name`. Cada ferramenta possui schema fechado de parâmetros; qualquer
campo desconhecido, `tool_name` ausente ou path fora de `repo-root` invalida a
sessão. O artefato persistido conserva somente `event`, `state`, `step_type`,
`tool_name` e classificações opacas de scope/outcome; remove `text_delta`,
`response`, paths, parâmetros, `output`, prompts e usage. O parser avalia os
campos brutos antes de descartá-los e não carrega em memória streams acima do
limite.

## 10. Rastreabilidade

- PRD: `docs/prd/prd-adapter-agy.md`;
- decisão anterior: `docs/adr/0007-escopo-fechado-de-harnesses.md`;
- backlog: `docs/backlog.md`, item `BL-0002`;
- feature separada: `.spec/features/094-provider-failover/PHASES.md`.
