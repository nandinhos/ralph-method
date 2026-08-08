# Plano arquitetural — engine OpenCode

## Status

Implementação em andamento na branch `feat/opencode-engine`. A prova real
exploratória já foi concluída; o adapter somente será considerado apto depois
da fixture complexa, da regressão e da revisão final.

Este documento descreve o contrato e o plano de implementação. Ele não afirma
que a engine OpenCode já está disponível para execução pelo Ralph.

## Objetivo

Adicionar ao Ralph Method uma engine OpenCode executável, agnóstica ao domínio
do projeto-alvo e isolada por um adapter. A engine deve transformar uma
invocação não interativa do OpenCode em uma execução que o Ralph consiga:

- iniciar com um prompt de fase;
- acompanhar sem abrir a TUI;
- encerrar sem deixar processos órfãos;
- classificar como concluída, falha, interrupção ou limite;
- capturar `sessionID`, provider e modelo sem inventar telemetria;
- devolver fatos ao `ralph-trace`;
- passar pelos gates existentes;
- continuar respeitando a autoridade exclusiva do `ralph-control`.

O alvo de alto nível é este:

```text
ralph.sh
  → contrato comum de runner
    → adapter OpenCode
      → opencode run --format json
        → JSONL local
      ← resultado normalizado
  → gates existentes
  → ralph-trace
  → feedback ao orquestrador
```

## Fonte dos requisitos e contexto de risco

O requisito desta entrega foi definido para esta branch: disponibilizar uma
ferramenta agnóstica de alto nível, testar a execução real pelo próprio
OpenCode e realizar depois uma prova de campo em projeto real, sem promover
`main` antes da validação. O objetivo é rastrear a delegação e provar a
execução; não é medir custo, tokens ou consumo de sessões.

As restrições operacionais são: uma feature por bloco, árvore limpa, gates
determinísticos, feedback ao orquestrador, recuperação explícita após pane,
sem fallback silencioso e sem credenciais no ledger. Como não há PRD
versionado neste repositório, este documento é a especificação técnica desta
entrega e deverá ser substituído ou ligado a um PRD quando o framework ganhar
um fluxo de produto próprio.

### Entrada específica da segunda etapa

Esta etapa adiciona uma feature de capacidade moderada, executada em uma
fixture descartável e verificada por um oráculo que fica fora do diretório
mutável pelo agente. O objetivo é exercitar parsing, validação, ordenação
determinística, dependências, ciclos, casos inválidos e saída canônica em uma
única execução real do OpenCode. O resultado esperado será conhecido antes da
execução e comparado por um script independente.

| Item | Contrato da prova |
|---|---|
| Feature | gerador de relatório de tarefas com validação de schema, prioridades, status, tags, dependências e ciclos |
| Entrada | JSON determinístico com casos válidos e fixtures negativas separadas |
| Saída esperada | JSON canônico com contagens, soma de estimativas, ordem estável e diagnóstico de erro |
| Evidência | hashes da entrada e dos arquivos protegidos calculados pelo controlador, não pelo agente |
| Oráculo | checker fora do checkout passado ao processo OpenCode; a sessão não pode alterá-lo |
| Desafio de transporte | nonce aleatório presente somente no prompt anexado e exigido na saída |
| Limite | bytes de stdout/stderr, linhas JSONL, tamanho do prompt e tempo de execução |
| Critério | feature, checker externo, processo, trace e relatório devem terminar verdes; qualquer dúvida bloqueia |

O checker não será instalado na fixture nem aceito como evidência se a sessão
puder alterá-lo. A fixture poderá conter apenas os dados e o código que a
feature deve produzir; a referência canônica, o nonce e a verificação final
pertencem ao harness da prova.

### Correções incorporadas após revisão adversarial

| Risco | Decisão de implementação |
|---|---|
| capability indireta por `observe` | o processo controlado não recebe `workflow_id`, `feature_key`, lease ou fencing; o hook fica sem contexto e o controlador registra o ciclo sob seu próprio lease |
| processo destacado | executar o bloco em namespace de PID quando o host permitir; caso contrário registrar a limitação e nunca afirmar contenção absoluta; qualquer processo observável restante exige recovery |
| oráculo mutável | referência e checker externos à raiz do projeto, com hashes calculados antes e depois |
| fallback tri-state | resultado, trace e schema passam a distinguir `false`, `true` e `null`, além de `unknown`, `detected` e `not_detected` |
| saída sem limite | captura em arquivo desde o primeiro chunk, com teto de bytes/eventos e encerramento fail-closed ao exceder |
| `--file` ambíguo | prompt contém nonce não previsível; a saída precisa devolvê-lo, vinculando transporte, hash do prompt e execução |
| instalação incompleta | adapter, parser, schema, contrato e perfil OpenCode entram no manifesto; instalação e uninstall serão testados juntos |

## Fora do escopo desta entrega

- alterar a máquina de estados, leases, fencing ou gates do Ralph;
- permitir que OpenCode escolha a próxima feature;
- fallback automático para Codex, Claude, Hermes ou agy;
- probe generativo durante `ralph-init plan`, `apply` ou `doctor`;
- implementar Hermes, agy ou um servidor OpenCode remoto;
- criar métricas de custo ou contabilização de tokens;
- armazenar prompts, respostas completas, credenciais ou conteúdo de
  raciocínio no ledger;
- alterar a `main` antes da validação integral da branch.

## Baseline auditado

| Área | Estado atual | Consequência para o plano |
|---|---|---|
| `scripts/ralph.sh` | Executa somente `codex` e `claude` | O dispatch precisa ganhar uma seam de adapter |
| `bin/ralph-bloco` | Aceita somente `codex` e `claude` | O wrapper precisa aceitar `opencode` explicitamente |
| `bin/ralph-init` | OpenCode funcional, mas `runner_supported=false` | A prontidão só será promovida após o runner e os testes |
| `adapters/` | Possui apenas o contrato documental | A implementação deve materializar o primeiro adapter real |
| `ralph-trace` | Aceita runner, provider, modelo e sessão | O adapter deve entregar fatos normalizados, não logs brutos |
| feedback | JSONL/stdout/callback já existente | A engine deve reutilizar o canal, sem criar outro |
| processo | `ralph-bloco` usa `setsid` e controla PGID | O runner OpenCode deve permanecer dentro do grupo do bloco |

## Prova exploratória real antecipada

Antes da implementação do adapter, foi executada uma sessão real do OpenCode
em fixture descartável. O relatório versionado é
[`reports/0001-prova-real-opencode.md`](../reports/0001-prova-real-opencode.md).

Resultado observado:

```text
CLI 1.18.15
exit code 0
16 eventos JSONL
sessionID presente
terminal step_finish
test-feature.sh: FEATURE_CHECK_OK
processo opencode run residual: nenhum encontrado
```

Essa prova confirma a capacidade da CLI, mas não certifica o Ralph: ainda não
houve `ralph-control`, lease isolado, trace importado, gates ou commit
controlado. O probe real passa a ser a primeira fase da execução da branch,
antes da integração do adapter.

## Princípios de desenho

### O núcleo não conhece flags de provider

`ralph.sh` deve conhecer apenas o contrato de um runner. Flags como `--format`,
`--auto`, `--pure`, `--variant` e `--dir` pertencem ao adapter OpenCode. O
mesmo contrato deve permitir que outro provider seja adicionado sem copiar a
política de gates.

### O adapter não possui autoridade

O adapter não pode escrever `workflow.json`, alterar o ledger, liberar lease,
aprovar gate ou iniciar outra feature. Ele recebe uma execução autorizada,
executa uma sessão e devolve um resultado.

Essa regra exige uma barreira de capability, não apenas uma convenção. O
processo do executor não receberá `RALPH_LEASE_TOKEN`, `RALPH_CONTROL`,
`RALPH_WORKFLOW_ID`, `RALPH_FEATURE_KEY` ou qualquer outro contexto que possa
ser usado para alcançar uma operação de ledger. O hook fica inerte no caminho
controlado; o controlador fará a importação do resultado e o trace sob seu
próprio lease depois que o processo terminar.

Antes do OpenCode, a branch deverá corrigir o caminho controlado que atualmente
herda o ambiente completo do processo em `bin/ralph-control:2973-2981`.
Enquanto essa barreira não existir e não houver teste negativo provando que um
executor não consegue chamar `observe`, `gate`, `approve`, `release`, `advance`,
`retry`, `recover` ou `trace`, a engine não está apta para smoke nem campo.

### Identidade não comprovada permanece não comprovada

O modelo solicitado será registrado como `declared`. O modelo efetivo só será
classificado como `observed` ou `exact` quando um campo estruturado da saída do
OpenCode o comprovar. Ausência de telemetria não pode virar uma afirmação de
precisão.

### Falha não troca provider

Se OpenCode falhar, o Ralph registra a falha e aplica sua política de
recuperação. Não haverá tentativa silenciosa com Codex ou Claude. Um fallback
futuro precisará ser declarado no plano, autorizado pelo controlador e
registrado no trace.

## Contrato agnóstico de runner

O contrato interno proposto será uma seam de processo, com argumentos
estruturados e resultado JSON sanitizado. O núcleo não deve fazer parsing de
texto humano para decidir gates.

### Entrada

```text
runner.preflight
  repo_root
  mode: impl | verify
  requested_model
  role
  workflow_id
  feature_key
  phase_number
  attempt
  run_id
  policy

runner.run
  prompt_file
  log_file
  metadata_file
  mesma identidade da preflight
```

### Saída mínima

```json
{
  "schema_version": "1.0.0",
  "runner": "opencode",
  "runner_version": "1.18.15",
  "provider": "openai-compatible",
  "requested_model": "provider/model",
  "effective_model": null,
  "identity_status": "declared",
  "identity_source": "requested_model",
  "execution_id": "run_phase_attempt",
  "session_id": "ses_...",
  "status": "completed",
  "exit_code": 0,
  "fallback_used": null,
  "fallback_status": "unknown",
  "events_seen": 12,
  "terminal_event": "step_finish",
  "error_summary": null,
  "artifact_refs": []
}
```

Campos obrigatórios do contrato:

- `runner`, `runner_version`, `execution_id` e `status`;
- `requested_model` quando a execução for de implementação ou verificação;
- `session_id` quando o provider tiver criado uma sessão;
- `identity_status` e `identity_source`;
- `exit_code`, `fallback_used` e `fallback_status`;
- resumo de erro sanitizado quando a execução não for concluída.

O resultado não deve conter prompt, resposta, token, segredo, variável de
ambiente, conteúdo completo de evento ou raciocínio.

`fallback_used=false` não poderá significar “nenhum fallback ocorreu” quando a
CLI não forneceu evidência para essa conclusão. Nesse caso, o resultado usa
`fallback_used=null` e `fallback_status=unknown`. O trace será ampliado para
aceitar essa distinção; somente `fallback_status=detected` poderá afirmar uma
troca, e somente uma evidência estruturada poderá marcar `fallback_used=true`.

### Operações do adapter

```text
preflight(context) → readiness/configuration result
run(context)      → process exit + raw local log + normalized result
classify(log, rc) → completed | failed | interrupted | usage_limited
metadata(log)     → trace-safe JSON
```

O adapter pode manter um log bruto somente como artefato local de execução,
fora do ledger versionado. O trace recebe apenas o resultado normalizado e
referências de artefato com hash.

## Invocação OpenCode planejada

A forma preferida será transportar o prompt por arquivo anexado, evitando
expor todo o texto na lista de argumentos do processo:

```bash
opencode run \
  --format json \
  --dir "$RALPH_REPO" \
  --model "$RALPH_OPENCODE_MODEL" \
  --file "$PROMPT_FILE" \
  "Execute a instrução de fase anexada e devolva o resultado da execução."
```

O suporte de arquivo de texto será confirmado no smoke real. Se a versão
instalada não o tratar como instrução, o adapter poderá usar o modo de
argumento como fallback explícito, mas somente após validar o tamanho contra
`getconf ARG_MAX`, aplicar um limite próprio e registrar
`prompt_transport=argument`. O modo de arquivo continuará sendo o padrão
quando suportado.

Flags opcionais serão acrescentadas somente quando definidas na política do
projeto:

```text
--variant <variante>
--agent <agente>
--pure
--title <identificador sanitizado>
```

Regras da invocação:

1. `--model` deve ser explícito no perfil da instalação; o adapter não escolhe
   o primeiro modelo do catálogo.
2. `--format json` é obrigatório para a execução automatizada; saída formatada
   para terminal não é contrato de máquina.
3. `--dir` deve apontar para a raiz do projeto autorizado.
4. `--continue`, `--session` e `--fork` ficam proibidos na primeira versão; cada
   ciclo do Ralph abre uma execução nova, como ocorre nos runners atuais.
5. `--auto` não é implícito no contrato. Em modo de implementação, ele só será
   acrescentado quando `RALPH_OPENCODE_AUTO=1` estiver definido no perfil. Em
   modo de verificação, o preflight exigirá uma política read-only verificável
   antes de permitir qualquer autorização automática.
6. `--pure` será a opção recomendada para smoke e regressão, evitando plugins
   externos não declarados. Um projeto real poderá desativá-la explicitamente.
7. `--attach`, `--port`, servidor remoto e opções de sessão persistente ficam
   proibidos na primeira versão; o adapter não pode iniciar um processo fora do
   grupo controlado.
8. nenhuma opção de telemetria deve imprimir raciocínio ou resposta completa
   no trace.

## Classificação da saída JSONL

O OpenCode documenta `--format json` como uma linha JSON por evento, com campos
como `type`, `timestamp` e `sessionID`. O parser do adapter será tolerante a
campos opcionais, mas fail-closed para os fatos necessários. O conjunto de
eventos terminais será confirmado pela versão real no fixture e no smoke; a
documentação atual sugere `step_finish`, mas o parser não poderá aceitar essa
hipótese sem comprovação da execução.

### Sucesso

Considerar a execução concluída somente quando:

- o processo terminar com exit code `0`;
- todas as linhas necessárias forem JSON válidos;
- houver `sessionID` não vazio;
- existir evento terminal aceito pelo contrato e registrado no resultado;
- não existir evento `error` fatal.

### Falha

Classificar como falha quando ocorrer qualquer uma destas situações:

- exit code diferente de `0`;
- evento `error` fatal;
- JSONL corrompido ou incompleto;
- ausência de `sessionID`;
- encerramento sem evento terminal;
- modelo inválido, provider não disponível ou permissão não resolvida.

### Identidade

| Evidência disponível | Classificação |
|---|---|
| somente `--model provider/model` | `declared` |
| evento estruturado informa o modelo usado | `observed` |
| sessão exportada comprova modelo sem ambiguidade | `exact` |
| saída indica provider, mas não modelo completo | `partial` |
| nenhum identificador confiável | `unavailable` |

O parser nunca deve inferir `exact` a partir de texto de resposta.

### Identidade e fallback

O parser relacionará `execution_id`, `sessionID`, hash da invocação e arquivo
JSONL. Provider e modelo solicitados vêm do perfil; provider/modelo efetivos
somente entram como `observed` ou `exact` se houver campo estruturado ou
artefato de sessão que os vincule àquela execução. Caso contrário:

```text
effective_model=null
identity_status=declared|partial|unavailable
fallback_used=null
fallback_status=unknown
```

Isso impede que a ausência de telemetria seja publicada como prova negativa de
fallback.

## Capability, permissões e término do processo

### Capability do controlador

O `ralph-control` continuará sendo a única autoridade, mas o plano precisa
fechar a capability herdada antes da engine:

1. não entregar ao executor nem contexto nem credenciais que permitam chamar
   comandos do controlador que escrevem ledger;
2. fazer o controlador importar o resultado normalizado e chamar o trace sob
   lock e lease, depois do retorno do bloco;
3. adicionar fixture adversarial em que o executor tenta `observe`, `gate`,
   `approve`, `release`, `advance`, `retry`, `recover` e `trace` sem receber
   capability; nenhuma tentativa pode criar evento ou mudar estado;
4. falhar fechado se o bloco não conseguir provar que executou sem capability
   privilegiada.

### Permissões do OpenCode

`--auto` é uma autorização ampla e não pode ser tratado como detalhe de CLI.
O preflight deverá produzir um `permission_policy_hash` e validar:

- modo de implementação: `RALPH_OPENCODE_AUTO=1` explícito, branch/worktree
  limpa e deny rules do projeto carregadas;
- modo de verificação: agente ou configuração read-only identificável, com
  mutações (`edit`, `write`, `bash` e equivalentes disponíveis) negadas;
- ausência de política read-only: execução de verificação bloqueada, sem
  tentar convencer o modelo por texto;
- mudança no `opencode.json`, agente ou política depois do preflight:
  resultado stale e recuperação necessária.

O hash e o resumo da política entram no artefato, nunca o conteúdo de segredo.

### Término e processo órfão

O caminho `ralph-control → ralph.sh` é o caminho normativo de execução; a
garantia não pode depender apenas do wrapper manual `ralph-bloco`. Antes do
smoke, o controlador deverá:

- registrar PID raiz, PGID, árvore inicial e fingerprint da invocação;
- preferir namespace de PID criado com `unshare --user --map-root-user --pid
  --fork --mount-proc`, mantendo a unidade externa observável pelo controlador;
- quando namespace não estiver disponível, observar o PGID e todos os PIDs
  conhecidos mesmo depois que o PID raiz sair;
- encerrar primeiro o grupo e depois os descendentes registrados;
- tratar qualquer processo ainda vivo ou qualquer impossibilidade de prova
  como `recovery_required`, nunca como término verificado;
- rejeitar `--attach`, `--port` e daemonização na engine inicial;
- executar fixture adversarial com filho que tenta criar nova sessão/PGID;
- documentar o limite residual: um processo que escape completamente da
  observação do sistema operacional exige recuperação manual e bloqueia a
  liberação.

O plano não promete “sem órfãos” fora de uma contenção disponível no host. Ele
promete somente `process_verified_terminated=true` quando a evidência da
contenção escolhida for conclusiva; em host sem namespace/cgroup compatível,
uma saída limpa do PGID é evidência de grupo observado, não de ausência
absoluta de processos destacados.

## Gates e recuperação

O adapter participa somente do gate de término do engine e fornece evidência
para o trace. Os cinco gates do Ralph permanecem inalterados:

```text
engine terminou
→ testes reais do projeto
→ revisão independente
→ evidência de runtime quando aplicável
→ curadoria de entrega
→ controlador decide
```

O erro do OpenCode deve alimentar a mesma estrutura de correção do loop:

```text
failure.detected
→ fix.applied
→ verification.passed
→ gate.passed
```

Durante uma falha:

- o adapter não chama outro provider;
- o controlador decide se haverá novo ciclo da mesma feature;
- o mesmo `feature_key` e `attempt` são preservados;
- um novo `execution_id` e uma nova `session_id` distinguem a tentativa;
- se o processo for encerrado pelo monitor, o resultado é `interrupted` e a
  recuperação explícita prevalece sobre avanço automático.

## Modelo e perfis

O perfil gerado para OpenCode não armazenará credenciais. A forma proposta é:

```dotenv
RALPH_BIN=scripts/ralph.sh
RALPH_OPENCODE_MODEL=provider/model
RALPH_OPENCODE_VARIANT=
RALPH_OPENCODE_AGENT=
RALPH_OPENCODE_AUTO=1
RALPH_OPENCODE_PURE=1
RALPH_OPENCODE_VERIFY_AGENT=ralph-review
RALPH_VERIFY_MODEL=provider/reviewer-model
```

O instalador poderá gerar o arquivo com o modelo vazio e marcar a instalação
como `needs_configuration` até que o usuário defina um modelo válido. O
catálogo de `opencode models` é evidência de disponibilidade, não autorização
para escolher um modelo arbitrariamente.

Para o gate de revisão, a primeira versão deve exigir um perfil de agente
read-only (`RALPH_OPENCODE_VERIFY_AGENT`) ou uma política equivalente de
permissões validada pelo preflight. Uma instrução textual de “não editar” não é
uma fronteira de segurança suficiente. Essa condição é bloqueante para o gate
de verificação, e não uma pendência do smoke.

## Trace e evidências

Cada execução OpenCode deverá gerar:

```text
.git/ralph-control/
└── artifacts/
    └── <run_id>/
        ├── opencode-events.jsonl
        └── opencode-result.json
```

O ledger registra somente:

- `execution_id`, `session_id`, `runner`, `runner_version`;
- provider e identidade do modelo conforme o nível comprovado;
- modo (`impl` ou `verify`), feature, fase e tentativa;
- status, exit code, evento terminal e hash dos artefatos;
- `fallback_status` e `fallback_used` somente quando houver evidência; ausência
  de observação fica como `unknown`/`null`.

O relatório `TRC` deverá mostrar OpenCode como nó do executor, sem confundir
`session_id` com `execution_id` e sem duplicar eventos quando o controlador for
executado novamente.

## Estrutura alvo

```text
adapters/
├── README.md
├── contract.md
└── opencode/
    ├── runner.sh
    ├── parser.php
    └── contract.md

.ralph/
└── opencode.env
```

O desenho pode ser implementado inicialmente com um adapter OpenCode isolado.
Codex e Claude permanecem nos caminhos estáveis até que um segundo adapter
real prove que a migração para wrappers comuns paga seu custo de regressão.

Os arquivos de fixture de capacidade e seus oráculos não serão distribuídos
como parte do projeto instalado. Eles vivem no harness de teste e são
descartáveis, justamente para que o agente não possa validar ou desativar o
próprio verificador.

## Fases de implementação

### Fase 0 — prova real exploratória isolada — concluída

- criar fixture Git descartável;
- definir output esperado antes da execução;
- executar uma feature real via `opencode run`;
- executar verificador determinístico;
- guardar somente evidência sanitizada e o resultado observado.

Saída: a CLI real foi comprovada; os limites do protocolo foram registrados
antes da implementação do adapter.

### Fase A — contrato, capability e proteção da regressão

- congelar o comportamento atual de Codex e Claude com characterization tests;
- documentar o contrato do runner;
- definir o schema do resultado normalizado;
- definir eventos mínimos aceitos e estados de falha;
- remover capability de lease do ambiente do executor;
- fortalecer a prova de término no caminho `ralph-control`;
- adicionar testes negativos de transição e de processo desacoplado;
- adicionar fixture JSONL do OpenCode sem chamar rede ou modelo.
- limitar captura por bytes, linhas/eventos e tamanho de prompt;
- registrar fallback tri-state sem converter ausência em `false`.

Saída: contrato revisável, capability isolada e nenhuma alteração de
comportamento existente.

### Fase B — seam mínima, sem migração especulativa

- introduzir a interface de runner sem mover ainda os caminhos estáveis de
  Codex e Claude;
- adicionar o dispatch OpenCode atrás dessa interface;
- preservar os comandos atuais de Codex e Claude como legacy até a prova real;
- manter o mesmo gate 0, detecção de limite, log e feedback;
- tornar o engine desconhecido um erro explícito de preflight.

Saída: OpenCode tem uma seam limpa sem criar wrappers especulativos para todos
os providers.

### Fase C — adapter OpenCode

- implementar preflight do modelo e das opções de segurança;
- montar a invocação por arrays shell, sem `eval` nem concatenação insegura;
- validar transporte por arquivo e, se necessário, modo de argumento com limite
  de bytes antes do primeiro smoke;
- executar `opencode run --format json` com diretório e modelo explícitos;
- capturar saída JSONL e código de saída sem perder o status do processo;
- encerrar o grupo de processos em caso de interrupção;
- classificar sucesso, erro, saída incompleta e limite;
- produzir resultado normalizado e fatos para o trace.

Saída: uma execução isolada OpenCode funciona sem tocar no controlador.

### Fase I — feature complexa e teste de capacidade real

- gerar fixture descartável com input, README da feature e arquivos protegidos;
- gerar referência, checker externo e nonce fora da fixture;
- executar a feature por `ralph-control → ralph.sh → adapter OpenCode`;
- validar a saída canônica, os casos negativos, o nonce e os hashes externos;
- verificar que o agente não acessou uma capability de ledger;
- provar o término contido e registrar qualquer limitação como bloqueio;
- gerar relatório numerado com tabela de comandos, tempos, limites, saída e
  evidências.

Saída: uma prova de campo local, repetível e independente do próprio agente,
com complexidade suficiente para revelar falhas de transporte, parsing,
permissão, capacidade ou supervisão.

### Fase D — instalação e seleção condicional

- marcar `runner_supported=true` somente com o adapter concluído;
- adicionar o perfil `.ralph/opencode.env` ao manifesto e ao uninstall;
- manter `functional` separado de `configured` e `adapter_enabled`;
- impedir `apply`/execução quando o modelo obrigatório estiver vazio;
- atualizar `ralph-bloco` para aceitar `opencode` explicitamente;
- manter `auto` determinístico e sem fallback.

Saída: a instalação reconhece OpenCode como runner somente quando ele estiver
realmente configurado.

### Fase E — trace, feedback e observabilidade de execução

- registrar `session_id` e identidade do modelo conforme evidência;
- publicar feedback com `engine=opencode` sem incluir resposta completa;
- importar trace no controlador depois do retorno, sem entregar lease ao
  adapter;
- referenciar hashes dos artefatos locais;
- validar idempotência e não duplicação de eventos;
- atualizar o relatório `TRC` e a documentação operacional.

Saída: o orquestrador externo acompanha a execução real do OpenCode.

### Fase F — regressão automatizada

- fixtures de sucesso, erro, timeout, processo interrompido e saída inválida;
- teste de capability ausente para gates e transições;
- teste de filho desacoplado e grupo ainda vivo após PID raiz;
- teste de modelo ausente e modelo sem formato `provider/model`;
- teste de permissão não resolvida sem loop infinito;
- teste de ausência de sessão e de evento terminal;
- teste de não fallback;
- teste de repetição do controlador;
- teste de instalação, doctor e uninstall;
- suite completa existente sem regressão em Codex e Claude.

Saída: todos os checks portáteis e a regressão do loop verdes.

### Fase G — prova pelo próprio OpenCode

Executar uma feature mínima em um repositório fixture descartável:

- o processo é iniciado com `opencode run` real;
- o OpenCode altera somente o fixture;
- o Ralph executa o comando de teste do fixture;
- o trace contém `session_id` real;
- a saída não expõe segredo nem resposta completa;
- o commit da fase é criado pelo Ralph;
- o processo termina sem órfãos;
- o relatório reúne o resultado e os artefatos.

Saída: prova de que o adapter não é apenas um parser de fixture.

### Fase H — teste de campo em projeto real

O candidato inicial é o `refactor-radar`, usando uma branch ou worktree
descartável e uma feature pequena, reversível e previamente delimitada.

Checklist obrigatório:

1. árvore do projeto limpa;
2. `ralph-init plan --verify-providers` verde;
3. provider OpenCode funcional, runner suportado e modelo configurado;
4. plano da feature aprovado;
5. comando de qualidade real definido (`bin/check` no Refactor Radar);
6. execução de exatamente uma feature por bloco;
7. cinco gates verdes;
8. commit da feature e árvore compatível;
9. trace com sessão e modelo classificados honestamente;
10. política de permissão read-only comprovada para a revisão;
11. feedback recebido no terminal do orquestrador;
12. monitor sem heartbeat parado ou processo órfão;
13. handoff e evidências gerados;
14. uninstall testado somente na cópia de campo;
15. nenhuma alteração na `main` do Ralph Method.

Esse teste será uma etapa posterior de execução, não parte do dry-run de
instalação.

## Critérios de aceite da branch

### Funcionais

- `scripts/ralph.sh --engine opencode` é aceito somente com preflight completo;
- uma fase pode ser executada por OpenCode em sessão nova;
- o resultado é normalizado e chega ao trace;
- gates existentes continuam sendo a autoridade de aprovação;
- falhas não iniciam provider alternativo;
- `auto` escolhe OpenCode apenas quando a prontidão e a configuração passam.

### Segurança

- sem `eval` para argumentos do provider;
- sem credenciais nos perfis ou eventos;
- logs brutos ficam fora do commit e do ledger sem necessidade;
- prompt e resposta não entram no trace;
- interrupção mata o grupo correto;
- execução em árvore suja é recusada;
- `--auto` fica explícito e auditável;
- gate de verificação possui política read-only real.

### Evidência

- checks existentes verdes;
- fixtures negativas verdes;
- smoke real pelo OpenCode verde;
- teste de campo real verde;
- branch limpa;
- revisão adversarial sem finding aberto crítico;
- documentação sincronizada com a versão e o comportamento implementado.

## Riscos e decisões adiadas

| Risco | Mitigação planejada | Gatilho para revisitar |
|---|---|---|
| formato JSONL evoluir | parser tolerante + versão registrada + fixtures reais | mudança de versão sem evento terminal reconhecível |
| modelo efetivo não ser exposto | identidade `declared`/`partial`, nunca `exact` por inferência | necessidade de auditoria exata por execução |
| prompt exceder limite de argumento | preferir `--file`; modo de argumento só com limite e teste prévios | falha no transporte por arquivo ou fase acima do limite próprio |
| `--auto` liberar ferramenta perigosa | deny explícito e branch/worktree isolada | primeiro incidente de permissão ou necessidade de granularidade |
| provider interno fazer fallback | registrar somente o que for comprovado e falhar em contradição | evento estruturado indicar troca de modelo |
| plugins alterarem comportamento | `--pure` no smoke/regressão | projeto real depender de plugin para executar a feature |

## Decisão de promoção

A branch só poderá ser promovida para `main` depois de uma revisão que confirme
simultaneamente:

```text
capability isolada
→ término verificável
→ contrato agnóstico
→ regressão verde
→ smoke real pelo OpenCode
→ teste de campo real
→ trace e feedback comprovados
→ documentação sincronizada
→ working tree limpo
```

A versão sugerida para a entrega completa continua sendo `v0.4.0`, pois a
branch adiciona um runner efetivo a um provider que antes era apenas
diagnosticado. Essa sugestão só permanece válida depois dos bloqueios de
capability, permissões e processo.
