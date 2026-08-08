# Plano arquitetural — engine OpenCode

## Status

Proposta em planejamento na branch `feat/opencode-engine`.

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
  "fallback_used": false,
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
- `exit_code` e `fallback_used`;
- resumo de erro sanitizado quando a execução não for concluída.

O resultado não deve conter prompt, resposta, token, segredo, variável de
ambiente, conteúdo completo de evento ou raciocínio.

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

A forma base será equivalente a:

```bash
opencode run \
  --format json \
  --dir "$RALPH_REPO" \
  --model "$RALPH_OPENCODE_MODEL" \
  --auto \
  "$PROMPT"
```

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
5. `--auto` deve ser uma escolha visível da política do perfil e permanecer
   sujeito a regras explícitas de negação do `opencode.json`.
6. `--pure` será a opção recomendada para smoke e regressão, evitando plugins
   externos não declarados. Um projeto real poderá desativá-la explicitamente.
7. nenhuma opção de telemetria deve imprimir raciocínio ou resposta completa
   no trace.

## Classificação da saída JSONL

O OpenCode documenta `--format json` como uma linha JSON por evento, com campos
como `type`, `timestamp` e `sessionID`. O parser do adapter será tolerante a
campos opcionais, mas fail-closed para os fatos necessários.

### Sucesso

Considerar a execução concluída somente quando:

- o processo terminar com exit code `0`;
- todas as linhas necessárias forem JSON válidos;
- houver `sessionID` não vazio;
- existir evento terminal aceito pelo contrato, inicialmente `step_finish`;
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
permissões. Uma instrução textual de “não editar” não é uma fronteira de
segurança suficiente.

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
- `fallback_used=false` ou um fallback explicitamente autorizado.

O relatório `TRC` deverá mostrar OpenCode como nó do executor, sem confundir
`session_id` com `execution_id` e sem duplicar eventos quando o controlador for
executado novamente.

## Estrutura alvo

```text
adapters/
├── README.md
├── contract.md
├── common.sh
├── codex/
│   └── runner.sh
├── claude/
│   └── runner.sh
└── opencode/
    ├── runner.sh
    ├── parser.sh
    └── fixtures/
        ├── completed.jsonl
        ├── error.jsonl
        ├── missing-session.jsonl
        └── malformed.jsonl

.ralph/
└── opencode.env
```

O desenho pode ser implementado inicialmente com wrappers shell, mantendo a
possibilidade de substituir apenas o adapter por uma implementação diferente
quando outro provider exigir protocolo mais rico.

## Fases de implementação

### Fase A — contrato e proteção da regressão

- congelar o comportamento atual de Codex e Claude com characterization tests;
- documentar o contrato do runner;
- definir o schema do resultado normalizado;
- definir eventos mínimos aceitos e estados de falha;
- adicionar fixture JSONL do OpenCode sem chamar rede ou modelo.

Saída: contrato revisável e nenhuma alteração de comportamento existente.

### Fase B — seam agnóstica no loop

- extrair o dispatch provider-específico de `scripts/ralph.sh`;
- preservar exatamente os comandos atuais de Codex e Claude atrás do contrato;
- manter o mesmo gate 0, detecção de limite, log e feedback;
- tornar o engine desconhecido um erro explícito de preflight.

Saída: o núcleo passa a depender de um runner, não de flags Codex/Claude.

### Fase C — adapter OpenCode

- implementar preflight do modelo e das opções de segurança;
- montar a invocação por arrays shell, sem `eval` nem concatenação insegura;
- executar `opencode run --format json` com diretório e modelo explícitos;
- capturar saída JSONL e código de saída sem perder o status do processo;
- encerrar o grupo de processos em caso de interrupção;
- classificar sucesso, erro, saída incompleta e limite;
- produzir resultado normalizado e fatos para o trace.

Saída: uma execução isolada OpenCode funciona sem tocar no controlador.

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
- referenciar hashes dos artefatos locais;
- validar idempotência e não duplicação de eventos;
- atualizar o relatório `TRC` e a documentação operacional.

Saída: o orquestrador externo acompanha a execução real do OpenCode.

### Fase F — regressão automatizada

- fixtures de sucesso, erro, timeout, processo interrompido e saída inválida;
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
10. feedback recebido no terminal do orquestrador;
11. monitor sem heartbeat parado ou processo órfão;
12. handoff e evidências gerados;
13. uninstall testado somente na cópia de campo;
14. nenhuma alteração na `main` do Ralph Method.

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
| prompt exceder limite de argumento | medir no smoke; introduzir transporte por arquivo/protocolo somente se ocorrer | fase real com prompt acima do limite do sistema |
| `--auto` liberar ferramenta perigosa | deny explícito e branch/worktree isolada | primeiro incidente de permissão ou necessidade de granularidade |
| provider interno fazer fallback | registrar somente o que for comprovado e falhar em contradição | evento estruturado indicar troca de modelo |
| plugins alterarem comportamento | `--pure` no smoke/regressão | projeto real depender de plugin para executar a feature |

## Decisão de promoção

A branch só poderá ser promovida para `main` depois de uma revisão que confirme
simultaneamente:

```text
contrato agnóstico
→ regressão verde
→ smoke real pelo OpenCode
→ teste de campo real
→ trace e feedback comprovados
→ documentação sincronizada
→ working tree limpo
```

A versão sugerida para a entrega completa é `v0.4.0`, pois a branch adiciona um
runner efetivo a um provider que antes era apenas diagnosticado.
