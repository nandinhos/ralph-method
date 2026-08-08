# Relatório 0003 — validação read-only e trace multiagente do OpenCode

## Resultado executivo

Esta execução valida a evolução do adapter OpenCode na branch
`feat/opencode-engine`. Ela foi realizada em fixture descartável, com uma
feature complexa, oráculo externo, processo contido e duas sessões OpenCode:
uma de implementação e outra de revisão técnica read-only.

| Verificação | Resultado |
|---|---|
| Execução controlada | verde |
| Duração do Ralph | 139 s |
| Cadeia | `ralph-control → namespace PID → ralph.sh → adapter → opencode run` |
| Feature | relatório determinístico de tarefas |
| CLI | OpenCode `1.18.15` |
| Modelo solicitado | `opencode/deepseek-v4-flash-free` |
| Oráculo externo | `FEATURE_CHECK_OK` |
| Processo residual | nenhum; `process_verified_terminated=true` |
| Contenção | `pid_namespace` |
| Trace | `TRC-2026-0001`, 2 delegações |
| Estado final | `awaiting_gates` |
| Promoção para `main` | não realizada |

O estado `awaiting_gates` é correto. A fixture comprova a execução, a
qualidade do artefato, o oráculo e a revisão independente; ela não deve ser
interpretada como aprovação artificial dos gates de entrega que não foram
executados pelo controlador desta prova, nem como liberação automática da
feature.

## Delegações registradas

O defeito encontrado durante a análise do primeiro relatório foi corrigido no
controlador: todos os resultados JSON produzidos pelo bloco são importados e
classificados pelo nome do artefato. A sessão `.verify-` é uma delegação
`technical_review`; a sessão `.cycle-` é `implementation`.

| Papel | `execution_id` | `session_id` | Status | Eventos | Política |
|---|---|---|---|---:|---|
| `implementation` | `exec_run_20260808T183200Z_2_impl_1_1` | `ses_01d5a7f9bffec3JUFado6l5Siw` | `completed`, exit `0` | 48 | `not_required` |
| `technical_review` | `exec_run_20260808T183200Z_2_verify_1_1` | `ses_01d591ebcffeUQcFOD7mSs9m6R` | `completed`, exit `0` | 31 | `verified` |

Em ambas as sessões, a identidade do modelo permanece `declared`: a saída
JSONL não apresentou um campo estruturado suficiente para afirmar o modelo
efetivo. O trace registra o modelo solicitado sem promovê-lo a `exact`.

## Prova da política read-only

| Evidência | Valor |
|---|---|
| Agente | `ralph-review` |
| Hash da política | `sha256:94189167c56a50dc0f794470716796c54a8abca988055b2174cca9ae80de4c54` |
| Sessão do canário | `ses_01d5adb24ffehsqsECctedKqEH` |
| Evento terminal | `step_finish` |
| Marcador final | `READONLY_DENIED` |
| Eventos de ferramenta observados | 4 |
| Canário de mutação | ausente |
| Hash da árvore antes/depois | `52330786eee654936fbabfa412d2a83b1e591fe7d329acb4bfb844ca296ef5bc` em ambos |
| `forbidden_tools_seen` | lista vazia |
| Hash do JSONL da prova | `sha256:af352a95835e45ff2ba8d992868e2766b9aa73e0a4c223b6591ccc10c771ffb8` |

A prova foi armazenada fora da raiz mutável em
`/tmp/ralph-method-opencode-field.LXQofj/readonly-policy-proof.json`.
Artefatos de bootstrap que o OpenCode gera em `.opencode/` são ignorados
somente no hash da fixture descartável; os arquivos da feature continuam
submetidos ao checker externo.

## Feature e evidências

| Critério | Resultado |
|---|---|
| tarefas válidas, prioridades, status e tags | verde |
| ordem topológica determinística | verde |
| IDs duplicados | `duplicate_id`, verde |
| dependência desconhecida | `unknown_dependency`, verde |
| ciclo | `cycle_detected`, verde |
| status inválido | `invalid_status`, verde |
| nonce aleatório | `nonce-eb78754a289992b5`, validado pelo checker externo |
| entrada e README protegidos | hashes preservados |
| captura do bloco | 6.181 bytes de stdout, 0 stderr |
| limite de captura | 5.242.880 bytes, não excedido |
| árvore após execução | compatível com o commit `0616851e964830c8845533a132eb856be32ce143` |

Hashes dos JSONL da execução final:

| Artefato | Eventos | Bytes | SHA-256 |
|---|---:|---:|---|
| implementação | 48 | 76.260 | `e81d580db322b53ed37ad00ebd6d3a3a665f2bf1d32e6b29f4f144bfa5317fe5` |
| revisão | 31 | 42.503 | `7c80c79301cd74a2fbf444a1b0f574d6b70fc56af94a818a46251aa77ccb09c2` |

Eventos brutos e a fixture permanecem descartáveis em `/tmp`; o repositório
versiona apenas este relatório sanitizado e os contratos necessários para
reproduzir a prova.

## Incidentes e correções

| Incidente | Causa raiz | Correção | Comprovação |
|---|---|---|---|
| primeira execução de campo falhou antes da feature | prova read-only intermitente não atingiu o contrato terminal | execução fail-closed, preservação da fixture e repetição controlada; a tentativa manual confirmou a hipótese sem alterar o projeto | prova posterior verde, árvore preservada |
| primeiro relatório do campo mostrava uma única delegação | `ralph-control` importava somente o resultado mais recente e sempre usava o papel `implementation` | importar todos os `*.result.json` e classificar `.verify-` como `technical_review` | trace final com 2 delegações e teste de campo exigindo os dois papéis |
| bootstrap do OpenCode alterava a árvore da probe | arquivos de dependência locais não pertencem à feature, mas eram incluídos no hash | exclusão limitada e explícita desses arquivos somente na probe descartável | hash antes/depois idêntico e canário ausente |

## Limite desta validação

Esta é a validação da engine e do caminho multiagente em ambiente isolado.
Ainda falta executar a regressão final da branch e a revisão adversarial antes
de preparar promoção para `main`. O teste em projeto real permanece uma etapa
separada e não foi inferido a partir desta fixture.
