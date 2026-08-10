# Arquitetura do Ralph Method

O Ralph Method é um framework local instalado dentro de um projeto-alvo. O
`bc-harness` distribui o instalador, mas não se torna dependência de runtime.

## Documentos

- [boundaries.md](boundaries.md) — componentes e seams;
- [data-model.md](data-model.md) — manifestos, ledger e ownership;
- [interfaces.md](interfaces.md) — CLI, events e providers.
- [opencode-engine-plan.md](opencode-engine-plan.md) — proposta de contrato
  agnóstico e plano da engine OpenCode.
- [opencode-validation-promotion-plan.md](opencode-validation-promotion-plan.md)
  — plano de validação, debug sistemático e promoção controlada.
- [control-plane-hardening-plan.md](control-plane-hardening-plan.md)
  — contrato executável da evolução de concorrência, crash e recuperação.
- [../backlog.md](../backlog.md) — itens adiados sem prioridade;
- [../adr/0007-escopo-fechado-de-harnesses.md](../adr/0007-escopo-fechado-de-harnesses.md)
  — decisão de escopo entre Codex, Claude CLI, OpenCode, Hermes e agy.
- [../adr/0008-execucao-exclusiva-e-ledger-protegido.md](../adr/0008-execucao-exclusiva-e-ledger-protegido.md)
  — decisão de exclusividade por feature e escrita protegida do ledger.
- [../adr/0009-memoria-episodica-e-taxonomia.md](../adr/0009-memoria-episodica-e-taxonomia.md)
  — decisão de retenção explícita, taxonomia e índices derivados.
- [../adr/0010-deteccao-evolucao-de-ralph-externo.md](../adr/0010-deteccao-evolucao-de-ralph-externo.md)
  — detecção segura de Ralph externo e evolução assistida futura.
- [../adr/0011-evolucao-assistida-backup-rollback.md](../adr/0011-evolucao-assistida-backup-rollback.md)
  — contrato executável de backup, isolamento, aceite e rollback condicional.
- [../reports/0001-prova-real-opencode.md](../reports/0001-prova-real-opencode.md)
  — evidência da primeira prova real isolada.

## Matriz de componentes e responsabilidades

Esta é a visão estrutural de referência. A coluna “limite” registra o que o
componente não pode fazer, para que a abstração permaneça segura quando o
Ralph for instalado em outro projeto ou receber outro harness.

### Núcleo de execução e autoridade

| Camada | Componente | Função | Responsabilidade e limite |
|---|---|---|---|
| Controle | `bin/ralph-control` | Control plane local | Única autoridade de estados, leases, fencing, locks, gates, recuperação, handoff e avanço; nenhum adapter pode substituí-lo. |
| Bloco | `bin/ralph-block` | Executar uma feature autorizada | Recebe uma feature já autorizada, executa um bloco e devolve resultado; não escolhe a próxima feature. |
| Compatibilidade | `bin/ralph-bloco` | Alias operacional do bloco | Mantém compatibilidade com invocações em português; não cria uma segunda máquina de estados. |
| Trace | `bin/ralph-trace` | Registrar delegações | Encaminha fatos de runner, provider, modelo, sessão e identidade ao controlador; não aprova nem libera. |
| Monitor | `bin/ralph-monitor` | Exibir saúde e progresso | Consulta snapshots, heartbeat, processo e último feedback; não faz retry, recovery ou transição. |
| Métricas | `bin/ralph-metrics` | Agregar o ledger historicamente | Emite JSON ou Markdown somente por leitura; não grava relatório, altera eventos ou calcula custo/token. |
| Loop | `scripts/ralph.sh` | Executar fases do harness | Abre sessões por fase, executa testes e emite feedback; não interpreta log como aprovação nem decide a fila. |
| Hook | `scripts/ralph-hook.sh` | Observar o loop | Emite telemetria sanitizada e best-effort; não altera ledger, gates, leases ou estado global. |

### Instalação, integridade e continuidade

| Camada | Componente | Função | Responsabilidade e limite |
|---|---|---|---|
| Instalação | `bin/ralph-init` | Instalar, evoluir e remover localmente | Faz `plan`, `apply`, `evolve`, `rollback` e `uninstall` com ownership, hashes, staging, lock, idempotência e aceite explícito; não importa estado legado. |
| Diagnóstico | `bin/ralph-doctor` | Verificar a instalação | Detecta drift, arquivos ausentes, manifesto inválido e integridade; não corrige silenciosamente. |
| Handoff | `scripts/ralph-generate-handoff.sh` | Projetar o encerramento da feature | Gera resumo, bugs, evidências e manifestos numerados; não aprova gate. |
| Qualidade | `scripts/ralph-run-quality.sh` | Executar o comando real do projeto | Centraliza o gate de qualidade e seu exit code; não substitui o comando declarado pelo projeto. |
| Runtime evidence | `scripts/ralph-run-runtime-evidence.sh` | Reunir prova de funcionamento | Executa a evidência configurada, como smoke test ou browser; não transforma ausência de prova em sucesso. |
| Gate independente | `scripts/ralph-run-independent-gate.sh` | Rodar revisão técnica read-only | Isola a verificação do implementador e registra falhas; não modifica o produto para fazer o gate passar. |
| Curadoria | `scripts/ralph-run-curator.sh` | Curar conhecimento pós-entrega | Converte evidência validada em memória reutilizável; não substitui a curadoria dos cinco gates. |
| Conhecimento | `bin/ralph-knowledge` | Consultar, classificar e publicar memória | Mantém candidatos episódicos, lições sanitizadas, taxonomia e retenção explícita; não recebe eventos brutos como se fossem conhecimento. |
| Índices de memória | `docs/engineering/INDEX.md`, `categories/`, `topics/` | Navegar por categoria e tema | Projeções regeneráveis; não substituem os documentos individuais nem o ledger. |

### Integração com harnesses e providers

| Harness/provider | Componente | Função | Responsabilidade e limite |
|---|---|---|---|
| Codex | runner nativo em `scripts/ralph.sh` | Executar implementação e revisão pelo fluxo nativo | Deve informar identidade do modelo conforme evidência; não possui autoridade de workflow. |
| Claude CLI | runner nativo em `scripts/ralph.sh` | Executar implementação e revisão pelo fluxo nativo | Usa o contrato comum de sessão, feedback, gates e trace; não faz seleção silenciosa de outro provider. |
| OpenCode | `adapters/opencode/runner.sh` | Executar o adapter com transporte controlado | Faz preflight, isolamento, política e execução; não grava estado global nem libera feature. |
| OpenCode | `adapters/opencode/parser.php` | Normalizar JSONL do runner | Exige schema, sessão e evento terminal válidos; rejeita payload ambíguo ou incompleto. |
| OpenCode | `adapters/opencode/policy.php` | Validar política read-only | Produz fingerprint e verifica recusas; não é aprovação técnica por si só. |
| OpenCode | `adapters/opencode/contract.md` | Documentar o contrato do adapter | Define entrada, saída, identidade, fallback e limites; não substitui o schema executável. |
| OpenCode | `scripts/opencode-readonly-proof.sh` | Gerar prova externa de revisão | Cria prova fora da raiz mutável; sua ausência bloqueia o runner de revisão. |
| OpenCode | `.opencode/agents/ralph-review.md` | Definir agente read-only | Restringe a revisão independente; não pode implementar ou editar o checkout. |
| Hermes | readiness em `bin/ralph-init` | Detectar sessão/provider passivamente | Nesta linha não possui adapter de execução e não pode ser fallback. |
| agy | readiness passiva em `bin/ralph-init` | Detectar presença compatível | Nesta linha não possui probe/adapter executável e permanece bloqueado. |

### Contratos versionados

| Contrato | Componente | Função | Responsabilidade e limite |
|---|---|---|---|
| Eventos de feedback | `schemas/feedback-event.schema.json` | Validar progresso JSONL/stdout/callback | Define correlação, estado, saúde e percentual; feedback é observabilidade, não autorização. |
| Instalação | `schemas/method-install.schema.json` | Validar manifesto e ownership | Protege hashes, versão e arquivos gerenciados; não autoriza substituir alterações do usuário. |
| Detecção de instalação | `schemas/ralph-installation-detection.schema.json` | Classificar Ralph Method e Ralph externo | Expõe sinais relativos e hashes sem conteúdo; não migra ou importa runtime desconhecido. |
| Evolução | `schemas/ralph-evolution.schema.json`, `.ralph/evolutions/` | Controlar backup, isolamento e rollback | Registra estado `EVL-YYYYMMDD-NNNN`, hashes e drift; o modo `quarantine_only` não importa ledger, workflow, prompts ou credenciais. |
| Readiness | `schemas/provider-readiness.schema.json` | Validar autenticação e capacidade | Separa `functional`, `runner_supported` e `adapter_enabled`; não prova geração real. |
| Runner | `schemas/runner-result.schema.json` | Validar resultado normalizado | Garante identidade, sessão, evento terminal, fallback e modo impl/verify; não faz transição de estado. |
| Política read-only | `schemas/readonly-policy-proof.schema.json` | Validar prova externa | Garante fingerprint e status da política; não substitui a revisão independente. |

### Documentação, evidência e operação

| Camada | Componente | Função | Responsabilidade e limite |
|---|---|---|---|
| Índice | `docs/README.md` | Orientar usuários e agentes | Apresenta a navegação e a ordem de leitura; não duplica a fonte técnica. |
| Estado | `docs/STATUS.md` | Registrar o estado atual | Resume capacidades comprovadas e links de evidência; fatos devem corresponder ao código. |
| Guia de agentes | `docs/AGENT_GUIDE.md` | Ensinar instalação e execução | Define o procedimento pós-identificação do harness, comunicação, recuperação e desinstalação. |
| Arquitetura | `docs/architecture/` | Explicar limites e contratos | Mantém boundaries, modelo de dados, interfaces e planos; não é fila operacional. |
| Decisões | `docs/adr/` | Registrar decisões imutáveis de contexto | Explica o porquê, consequências e gatilho de revisão; não substitui implementação. |
| Incidentes | `docs/incidents/` | Preservar falhas e correções | Mantém causa raiz, mitigação e prevenção; não é log bruto. |
| Relatórios | `docs/reports/` | Publicar evidências numeradas | Registra comandos, resultados, escopo e limitações; não contém segredos ou prompts completos. |
| Plano futuro | `docs/roadmap.md` e `docs/backlog.md` | Controlar trabalho futuro | Separa itens ativos de itens adiados; não autoriza execução por si só. |
| Questões abertas | `docs/open-questions.md` | Registrar decisões pendentes | Evita que uma hipótese seja tratada como contrato; exige dono ou decisão posterior. |

### Estado local e artefatos gerados

| Local | Componente | Função | Responsabilidade e limite |
|---|---|---|---|
| Ledger | `.git/ralph-control/events.jsonl` | Registrar fatos operacionais append-only | É escrito pelo controlador, usa correlação e hash chain; hooks não escrevem estado global diretamente. |
| Workflow | `.git/ralph-control/workflow.json` | Fixar a fila em execução | É uma cópia operacional do manifesto; a feature atual é sempre escolhida pelo controlador. |
| Feedback | `.git/ralph-control/feedback/events.jsonl` | Armazenar progresso sanitizado | Serve ao monitor/orquestrador; não pode liberar gates. |
| Artefatos | `.git/ralph-control/artifacts/` | Guardar evidências de execução | Referenciado pelo ledger e protegido por hash; não deve conter segredos. |
| Relatórios locais | `.git/ralph-control/reports/` | Armazenar projeções operacionais | Mantém relatórios do runtime sem transformar evento bruto em documentação curada. |
| Instalação | `.ralph/method.json`, `.ralph/providers.json` | Descrever método e readiness instalados | São metadados locais e não substituem workflow, lease ou gates. |
| Perfis | `.ralph/codex.env`, `.ralph/claude.env`, `.ralph/opencode.env` | Configurar runners por projeto | São gerados com ownership; credenciais não devem ser gravadas neles. |
| Handoffs | `.ralph/handoffs/<feature_key>/` | Preservar entrega por feature | Contêm resumo, incidentes e evidências versionáveis; não contêm raciocínio privado. |

## Princípio central

```text
executor executa
→ hook observa
→ feedback informa o orquestrador
→ ralph-control retransmite o feedback do bloco
→ ralph-trace normaliza fatos
→ ralph-control registra e valida
→ gates comprovam
→ ralph-control decide
```

O trace não aprova, não libera e não escolhe a próxima feature.
