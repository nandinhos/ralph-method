# Plano de validação e promoção da engine OpenCode

## Status

Plano de execução controlada para a branch `feat/opencode-engine`. Este
documento não promove a branch e não autoriza alterações na `main`.

## Objetivo

Demonstrar que a engine OpenCode pode executar uma feature real pelo caminho
normativo do Ralph, sobreviver a falhas conhecidas, registrar evidências
reproduzíveis, cumprir os cinco gates de entrega e ser promovida para `main`
sem uma conclusão baseada apenas em logs ou em uma execução feliz.

A promoção somente será elegível quando a cadeia estiver completa:

```text
preflight
→ execução controlada
→ evidência externa
→ gates verdes
→ debug sistemático de falhas
→ revisão independente read-only
→ curadoria de entrega
→ regressão completa
→ revisão adversarial sem findings abertos
→ promoção
→ regressão pós-promoção
```

## O que já está comprovado

| Evidência | Estado | Limite atual |
|---|---|---|
| Adapter OpenCode real | verde | execução de implementação |
| Parser JSONL e sessão | verde | OpenCode `1.18.15` observado |
| Fixture complexa e oráculo externo | verde | fixture descartável |
| Capability sem lease no executor | verde | caminho controlado testado |
| Contenção e encerramento | verde | prova feita em namespace de PID |
| `ralph-trace` | verde | identidade efetiva ainda pode ser `declared` |
| Regressão portátil | verde | 163 asserts |
| Cinco gates da entrega | pendente | fixture terminou em `awaiting_gates`; ainda falta executar os cinco gates como entrega |
| Verificador read-only OpenCode | verde em fixture | política fingerprinted, prova externa, sessão separada e importação no trace; campo real ainda pendente |
| Projeto real | pendente | deve ocorrer em worktree isolada |

O estado anterior `awaiting_gates` é preservado como evidência honesta. Ele
não será convertido manualmente em `approved` ou `released`.

## Autoridade e responsabilidades

| Componente | Responsabilidade nesta validação | Proibição |
|---|---|---|
| `bin/ralph-control` | lock, lease, fencing, execução, gates, recovery e decisão | não delegar aprovação ao adapter |
| `scripts/ralph.sh` | executar uma feature/fase e devolver resultado | não escolher próxima feature |
| `adapters/opencode/` | traduzir CLI OpenCode para contrato normalizado | não escrever ledger ou workflow |
| `ralph-trace` | registrar fatos comprovados da delegação | não aprovar nem liberar |
| monitor | heartbeat, processo, logs e snapshot | não executar retry automático |
| revisor independente | technical review read-only | não editar o checkout revisado |
| curador independente | curation da entrega e dos incidentes | não substituir gates técnicos |

## Gates de promoção

O término do runner é uma pré-condição técnica. A entrega ainda precisa dos
cinco gates já definidos pelo Ralph:

| Gate | Evidência obrigatória | Condição de bloqueio |
|---|---|---|
| `validation` | critérios da feature, oráculo externo e saída esperada | qualquer critério ausente ou divergente |
| `quality` | comando real do projeto, com exit code `0` | teste, lint, análise ou arquitetura vermelha |
| `runtime_evidence` | smoke real, logs, versão e artefatos; Playwright quando houver UI | evidência ausente, parcial ou não reproduzível |
| `technical_review` | sessão independente, read-only, com política e hash comprovados | permissão não comprovada, mutação ou revisão da mesma sessão |
| `curation` | curadoria separada, relatório numerado e incidentes tratados | relatório incompleto, duplicado ou sem rastreabilidade |

Nenhum gate será considerado verde por declaração do modelo. O controlador
deve validar o código de saída, a árvore, os hashes e as referências de
artefato.

## Plano de execução

### Fase 0 — congelamento da linha de base

**Objetivo:** garantir que a validação parta de uma branch identificável e não
misture alterações externas.

1. Confirmar `feat/opencode-engine` limpa e sincronizada com `origin`.
2. Registrar commit-base, hash da árvore, versão `0.4.0` e versão da CLI.
3. Confirmar que `main` não contém alterações locais e não será usada como
   checkout de execução.
4. Fixar modelo OpenCode explicitamente em `provider/model`.
5. Criar um manifesto de validação com `workflow_id`, `feature_key`, modelo,
   versão, limites, worktree e comandos esperados.
6. Confirmar que a autenticação já existente é usada sem registrar segredo.

**Saída verde:** manifesto de validação, árvore limpa, modelo explícito e
nenhum processo Ralph/OpenCode antigo no escopo.

**Bloqueio:** árvore suja, modelo ausente, provider não funcional, processo
residual ou divergência entre plano e checkout.

### Fase 1 — política read-only efetiva

**Objetivo:** habilitar o `technical_review` somente quando a limitação de
permissões for comprovada no nível do runtime.

O OpenCode suporta agente e regras de permissão para ferramentas como `read`,
`grep`, `glob`, `list`, `bash`, `edit`, `webfetch` e `external_directory`. A
implementação deverá usar configuração explícita e hash da política, não apenas
texto no prompt.

1. Criar uma configuração de revisão em fixture descartável com `edit: deny`
   e política de `bash` restrita a comandos de leitura.
2. Bloquear `external_directory` fora do snapshot autorizado.
3. Calcular `permission_policy_hash` antes da sessão.
4. Executar um canário que tente criar, editar, remover e commitar um arquivo
   dentro da fixture de teste.
5. Confirmar que o processo recebe as recusas, a árvore não muda e nenhum
   arquivo canário é criado.
6. Recalcular o hash depois da sessão e bloquear se a política estiver stale.
7. Repetir o canário com política alterada para comprovar que o preflight
   detecta a mudança.
8. Só então aceitar `RALPH_OPENCODE_VERIFY_AGENT` no modo `verify`.

**Saída verde:** agente read-only identificável, hash antes/depois igual,
tentativas de mutação negadas e árvore byte a byte preservada.

**Bloqueio:** qualquer mutação, permissão `ask` em operação crítica,
configuração não identificável ou impossibilidade de validar a política.

### Fase 2 — debug sistemático e recuperação

**Objetivo:** eliminar loops de tentativa e garantir que cada pane produza uma
correção comprovada ou uma pausa explícita.

Para cada falha, o controlador deve seguir esta sequência:

```text
detectar
→ congelar avanço
→ capturar evidência
→ reproduzir em menor escala
→ formular hipóteses
→ testar a hipótese mais barata
→ consultar documentação oficial quando aplicável
→ corrigir em nova tentativa
→ executar teste de regressão
→ validar evidência posterior
→ registrar incidente e decisão
```

O pacote de diagnóstico deve conter, no mínimo:

| Evidência | Conteúdo |
|---|---|
| identidade | `workflow_id`, `feature_key`, `attempt`, `execution_id`, lease |
| tempo | início, detecção, encerramento e duração |
| processo | PID, PGID/namespace, estado final e processo residual |
| execução | comando sanitizado, exit code, limite e status do runner |
| código | commit, tree hash, plano e hashes de artefatos |
| saída | resumo sanitizado, sem prompt completo, token ou segredo |
| hipótese | causa provável, evidência a favor e contra, teste realizado |
| correção | arquivos, commit, teste que falhou e teste posterior |

Política contra looping:

- a mesma combinação de causa, feature e tentativa não pode ser repetida
  indefinidamente;
- após três falhas equivalentes ou dois ciclos sem progresso, mover para
  `recovery_required`;
- nesse estado, escalar para uma sessão independente de maior capacidade,
  preservando a árvore e os artefatos;
- só retomar após uma hipótese validada e uma nova execução verde;
- se não houver mitigação reproduzível, a promoção é automaticamente `no-go`.

**Saída verde:** cada pane injetada termina em `blocked` ou
`recovery_required`, sem avanço silencioso, e cada correção produz evidência
posterior e regressão verde.

### Fase 3 — prova complexa com os cinco gates

**Objetivo:** repetir a fixture complexa já aprovada, agora com o caminho de
verificação independente habilitado.

1. Recriar fixture, nonce, oráculo e referências externas.
2. Executar `ralph-control → ralph.sh → adapter OpenCode` sem `--no-verify`.
3. Confirmar `FEATURE_CHECK_OK`, hashes externos, casos negativos, saída
   canônica e repetição determinística.
4. Executar `quality` com o comando real da fixture.
5. Executar `runtime_evidence` e guardar logs, versão e artefatos.
6. Executar `technical_review` em sessão independente read-only.
7. Executar `curation` em sessão separada da implementação e da revisão.
8. Gerar o relatório numerado da execução, com tabela de duração e evidência.
9. Reexecutar o controlador para provar idempotência e ausência de eventos ou
   commits duplicados.

**Saída verde:** workflow `released`, cinco gates verdes, handoff completo,
trace íntegro e relatório reproduzível.

**Bloqueio:** qualquer gate vermelho, sessão não independente, relatório sem
referência ou repetição não idempotente.

### Fase 4 — teste de campo em projeto real

**Objetivo:** comprovar que o adapter funciona fora da fixture, sem contaminar
o projeto real ou a `main` do Ralph Method.

O candidato será uma worktree descartável do `refactor-radar`, criada a partir
de um commit conhecido. A feature de campo deverá ser delimitada antes da
execução e conter:

- objetivo observável e critérios de aceite;
- arquivos permitidos e arquivos protegidos;
- comando de qualidade real `bin/check`;
- comando de runtime reproduzível;
- oráculo externo ou assertions independentes;
- resultado esperado conhecido antes da sessão;
- plano de rollback da worktree.

Sequência obrigatória:

1. Criar worktree isolada e confirmar árvore limpa.
2. Executar `ralph-init plan --verify-providers` em modo somente leitura.
3. Configurar modelo OpenCode explicitamente e validar `ralph-doctor`.
4. Iniciar exatamente uma feature pelo controlador.
5. Acompanhar feedback em stdout e heartbeat do monitor.
6. Validar o código produzido, o commit, o tree hash e os arquivos protegidos.
7. Rodar `bin/check` sem substituir o banco ou o ambiente exigido pelo projeto.
8. Executar o smoke de runtime; se a feature tocar UI, usar Playwright com
   screenshot, console e versão do navegador.
9. Executar revisão independente read-only e curadoria separada.
10. Gerar handoff e relatório com duração por fase, tentativas, correções e
    incidentes.
11. Repetir o relatório/consulta para provar idempotência.
12. Desinstalar o Ralph apenas na worktree de campo e confirmar preservação do
    histórico e das evidências.

**Saída verde:** feature liberada na worktree descartável, cinco gates verdes,
feedback recebido, nenhum processo residual, nenhum segredo exposto e
worktree removível sem dano ao projeto original.

### Fase 5 — matriz de panes e adversarial

**Objetivo:** provar que a promoção não depende apenas do caminho feliz.

Injetar, uma por vez, os seguintes cenários em fixtures controladas:

| Pane | Veredito esperado |
|---|---|
| modelo ausente ou inválido | preflight bloqueia |
| JSONL corrompido | runner falha fechado |
| sessão ausente | gate do engine bloqueia |
| evento terminal ausente | recovery obrigatório |
| timeout | processo encerrado e recovery |
| processo filho destacado | bloqueio, sem afirmar término |
| limite de captura | execução interrompida, artefato preservado |
| `bin/check` vermelho | gate `quality` bloqueia |
| evidência de runtime ausente | gate `runtime_evidence` bloqueia |
| mutação pela revisão | gate `technical_review` bloqueia |
| curador indisponível | `knowledge_review_required`, conforme política |
| ledger corrompido ou hash inválido | workflow bloqueado |
| árvore divergente | nenhum avanço |
| dois controladores | um adquire lease; outro falha de forma auditável |
| repetição do controlador | nenhum evento ou commit duplicado |

Cada cenário precisa de: reprodução, causa raiz, mitigação, teste posterior e
registro de incidente. Um cenário sem evidência posterior permanece vermelho.

### Fase 6 — regressão, documentação e revisão adversarial

Executar, com exit code verificado individualmente:

```text
bash scripts/check-shell.sh
bash scripts/check-doc-sync.sh
bash scripts/test-installation.sh
bash scripts/test-feedback.sh
bash scripts/test-provider-readiness.sh
bash scripts/test-ralph-method.sh
bash scripts/test-opencode-adapter.sh
bash scripts/test-opencode-field.sh
bash scripts/test-ralph.sh
php -l bin/ralph-control
php -l bin/ralph-init
php -l adapters/opencode/parser.php
git diff --check
```

Depois dos checks:

1. reabrir o diff completo com foco em autoridade, shell injection, limites,
   sanitização e idempotência;
2. executar uma revisão adversarial independente;
3. verificar todos os itens do relatório contra artefatos reais;
4. sincronizar `STATUS.md`, `roadmap.md`, `AGENT_GUIDE.md`, arquitetura e ADRs;
5. confirmar branch limpa e ausência de finding crítico, alto ou não mitigado.

### Fase 7 — decisão e promoção

Criar uma matriz final com estado binário:

| Critério | Resultado exigido | Evidência |
|---|---|---|
| branch e documentação | verde | commit, diff e sync |
| fixture complexa | verde | relatório numerado e oráculo |
| política read-only | verde | canário, hash e árvore |
| panes e recovery | verde | matriz de incidentes |
| projeto real | verde | handoff e gates |
| regressão | verde | logs individuais |
| adversarial | sem finding aberto | parecer independente |
| working tree | limpa | `git status` |

Se qualquer linha não for verde, a decisão será `NO-GO` e a branch não será
promovida.

Somente com `GO`:

1. revisar o diff entre `main` e `feat/opencode-engine`;
2. abrir ou atualizar a revisão de integração;
3. promover a branch por merge controlado, sem rebase destrutivo;
4. rodar a suíte completa novamente em `main` após o merge;
5. validar `ralph-init plan` e `ralph-doctor` a partir da `main`;
6. criar a tag de versão somente após a regressão pós-merge;
7. publicar o relatório final de promoção.

Se a regressão pós-merge falhar, não apagar evidências: registrar incidente,
bloquear a release e criar um commit de correção ou reversão explícito.

## Artefatos e padronização

| Artefato | Local | Regra |
|---|---|---|
| ledger | `.git/ralph-control/` | local, append-only e não versionado |
| resultado do runner | `.git/ralph-control/artifacts/<run>/` | hash e referência no trace |
| handoff | `.ralph/handoffs/<feature>/` | versionável, com erro/correção/evidência |
| relatório de validação | `docs/reports/0003-*.md` | numerado, PT-BR e rastreável |
| incidente | `docs/engineering/incidents/INC-*.md` | somente após causa e mitigação |
| decisão arquitetural | `docs/adr/0006-*.md` | contexto, opções, decisão e gatilho |
| memória curada | `docs/engineering/lessons/` | somente conhecimento validado |

Relatórios e incidentes não podem conter prompt completo, resposta completa,
raciocínio privado, token, credencial ou dado sensível.

## Critério final de aceite

A engine só poderá ser promovida quando for possível demonstrar, em uma
execução reproduzível:

```text
feature executada
→ falhas possíveis detectadas e mitigadas
→ cinco gates verdes
→ evidências independentes
→ trace íntegro
→ recuperação comprovada
→ regressão verde
→ revisão adversarial sem risco aberto
→ promoção e regressão pós-promoção verdes
```

Sem comprovação ou sem mitigação de uma pane, a decisão permanece `NO-GO`.
