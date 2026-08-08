# Relatório 0003 — validação read-only e trace multiagente do OpenCode

## Resultado executivo

Esta execução valida a evolução do adapter OpenCode na branch
`feat/opencode-engine`. Ela foi realizada em fixture descartável, com uma
feature complexa, oráculo externo, processo contido e duas sessões OpenCode:
uma de implementação e outra de revisão técnica read-only.

| Verificação | Resultado |
|---|---|
| Execução controlada | verde |
| Duração do Ralph | 116 s |
| Cadeia | `ralph-control → namespace PID → ralph.sh → adapter → opencode run` |
| Feature | relatório determinístico de tarefas |
| CLI | OpenCode `1.18.15` |
| Modelo solicitado | `opencode/deepseek-v4-flash-free` |
| Oráculo externo | `FEATURE_CHECK_OK` |
| Processo residual | nenhum; `process_verified_terminated=true` |
| Contenção | `pid_namespace` |
| Trace | 2 delegações, correlacionadas por workflow, feature e tentativa |
| Estado final | `awaiting_gates` |
| Promoção para `main` | não realizada |

O estado `awaiting_gates` é correto. A fixture comprova a execução, a
qualidade do artefato, o oráculo e a revisão independente; ela não deve ser
interpretada como aprovação artificial dos gates de entrega que não foram
executados pelo controlador desta prova, nem como liberação automática da
feature.

## Delegações registradas

O controlador importou somente os resultados do bloco atual, após validar o
contrato normalizado e a correspondência entre `workflow_id`, `feature_key` e
`attempt`. A sessão `.verify-` é uma delegação `technical_review`; a sessão
`.cycle-` é `implementation`. A execução usou o caminho normativo
`ralph-control run --engine opencode`, com o perfil `.ralph/opencode.env` da
fixture.

| Papel | `execution_id` | `session_id` | Status | Eventos | Política |
|---|---|---|---|---:|---|
| `implementation` | `exec_run_20260808T203301Z_2_impl_1_1` | `ses_01cebb52cffeMtoceAyybh1dCE` | `completed`, exit `0` | 35 | `not_required` |
| `technical_review` | `exec_run_20260808T203416Z_3226349_verify_1_1` | `ses_01cea8e02ffe2ygvID1V0rEpzu` | `completed`, exit `0` | 23 | `verified` |

Em ambas as sessões, a identidade do modelo permanece `declared`: a saída
JSONL não apresentou um campo estruturado suficiente para afirmar o modelo
efetivo. O trace registra o modelo solicitado sem promovê-lo a `exact`.

## Prova da política read-only

| Evidência | Valor |
|---|---|
| Agente | `ralph-review` |
| Hash da política | `sha256:94189167c56a50dc0f794470716796c54a8abca988055b2174cca9ae80de4c54` |
| Sessão do canário | `ses_01cebf294ffed1zeOnTPbWg14f` |
| Evento terminal | `step_finish` |
| Marcador final | `READONLY_DENIED` |
| Eventos de ferramenta observados | 0 |
| `policy_denied_tools` | `edit`, `bash` |
| `denied_tools_seen` | vazio nesta amostra; a política global tornou as ferramentas indisponíveis |
| `denial_evidence` | `edit: policy`; `bash: policy` |
| Canário de mutação | ausente |
| Hash da superfície de política antes/depois | `d93bd711ad2343f316ba484f10f0e6d5755c1f7e470f706a6a30c4b1c53d285e` em ambos |
| `forbidden_tools_seen` | lista vazia |
| Tentativas do proof | `1` |
| Hash do JSONL da prova | `sha256:487683e775ecee9d964541d84749dec5f59c2cb93506ba941656e86766646b73` |

A prova foi armazenada fora da raiz mutável em
`/tmp/ralph-method-opencode-field.DljQ2L/readonly-policy-proof.json`.
O controlador captura o caminho em memória, remove-o do ambiente antes de
iniciar a implementação e só o injeta em um processo separado de revisão após
o grupo da implementação terminar. Os artefatos de bootstrap que o OpenCode gera em `.opencode/`
são excluídos somente por entradas locais e limitadas em `.git/info/exclude`;
o teste confirmou que nenhum deles entrou no commit. O único arquivo
versionado nessa árvore foi `.opencode/agents/ralph-review.md`.

## Feature e evidências

| Critério | Resultado |
|---|---|
| tarefas válidas, prioridades, status e tags | verde |
| ordem topológica determinística | verde |
| IDs duplicados | `duplicate_id`, verde |
| dependência desconhecida | `unknown_dependency`, verde |
| ciclo | `cycle_detected`, verde |
| status inválido | `invalid_status`, verde |
| nonce aleatório | `nonce-7ee2358ae5a32e65`, validado pelo checker externo |
| entrada e README protegidos | hashes preservados |
| captura do bloco | 5.096 bytes de stdout, 0 stderr |
| limite de captura | 5.242.880 bytes, não excedido |
| árvore após execução | compatível com o commit `f75e29988ef12f00e70a02b6c73c0d0d5a82851d` |

Hashes dos JSONL da execução final:

| Artefato | Eventos | Bytes | SHA-256 |
|---|---:|---:|---|
| implementação | 35 | 63.298 | `fd5962523c223ade0b5bfbac5b01c68ec68fc8e8729637e0966eb9a8c392a656` |
| revisão | 23 | 33.827 | `ffe31067cefe59443661eba23ae0ebf6a4de8a5757d9cdc32f250d3a13af0c64` |

Eventos brutos e a fixture permanecem descartáveis em `/tmp`; o repositório
versiona apenas este relatório sanitizado e os contratos necessários para
reproduzir a prova.

## Incidentes e correções

| Incidente | Causa raiz | Correção | Comprovação |
|---|---|---|---|
| prova read-only dependia de o modelo emitir uma chamada para ferramenta indisponível | a política `*: deny` pode remover `edit` e `bash` do conjunto de ferramentas, em vez de gerar evento de recusa | prova separa `policy_denied_tools` da telemetria efetivamente observada; hash da política, sessão terminal, ausência de canário, marcador JSONL e superfície de política preservada continuam obrigatórios | `policy_denied_tools=[edit,bash]`, `denied_tools_seen=[]` nesta amostra, `denial_evidence=policy`, superfície preservada |
| caminho da prova podia ser descoberto pela implementação | a variável externa era herdada por um processo ancestral do agente | controlador limpa a variável antes da implementação e executa `--verify-only` em processo separado, com a prova injetada somente depois do término do primeiro grupo | implementação sem política; revisão importada com `permission_policy_status=verified` |
| resultado histórico podia ser associado à feature atual | importador não tinha vínculo explícito com o bloco | resultado carrega `workflow_id`, `feature_key`, `attempt`; controlador filtra contexto, valida contrato e mantém idempotência por `execution_id` | trace final com duas delegações da tentativa 1 |
| a revisão separada apagava os resultados da implementação | `split_phases` recriava `.phases` ao iniciar `--verify-only` | o modo de verificação preserva logs/resultados existentes e apenas regenera a definição das fases | dois arquivos `*.result.json` importados no trace |
| referências internas de stdout da revisão violavam o contrato do ledger | o controlador retornava nomes de arquivos sem o prefixo `artifact_` | revisão publica referências sanitizadas e compatíveis com o schema do evento | `artifact_FEATURE-OPENCODE-COMPLEX_verification_*` |
| caminho normativo não iniciava OpenCode | `configuredRalph` e o supervisor não aceitavam/propagavam `opencode` | perfil OpenCode elegível e `--engine` propagado ao subprocesso | campo executado por `ralph-control run --engine opencode` |
| bootstrap do OpenCode alterava o commit | `.opencode/.gitignore` era criado fora do ownership do Ralph | exclusão local apenas para artefatos ausentes antes da sessão; arquivos já existentes não são apropriados | `git ls-files .opencode` contém somente o agente versionado |

## Limite desta validação

Esta é a validação da engine e do caminho multiagente em ambiente isolado.
O campo terminou em `awaiting_gates`: a engine, o oráculo, o processo, o trace
e a importação das duas sessões ficaram verdes, mas esta fixture não executa
os cinco gates de entrega nem gera handoff de projeto real. A regressão final
da branch, a revisão adversarial do snapshot final e o teste em projeto real
continuam necessários; nenhuma promoção para `main` foi inferida a partir
desta prova.
