# PHASES — Adapter nativo `agy`

## Phase 1: Registrar arquitetura e contratos

- [ ] **Task:** superseder o escopo fechado do ADR-0007 e registrar nova decisão.
  - **Acceptance criteria:** ADR novo contém opções, seam, schema 1.1, isolamento,
    consequências e gatilhos observáveis.
- [ ] **Task:** atualizar boundaries/interfaces/data-model/índice antes do código.
  - **Acceptance criteria:** arquitetura candidata diferencia fatos atuais de
    comportamento a implementar e mantém `bin/ralph-control` como autoridade.
- [ ] **Task:** congelar contrato de JSONL e projeção sanitizada.
  - **Acceptance criteria:** eventos, limites, allowlist e falhas estão definidos.

## Phase 2: Implementar resultado, política e parser

- [ ] **Task:** evoluir `runner-result.schema.json` de modo compatível.
  - **Acceptance criteria:** OpenCode 1.0 continua válido; `agy` 1.1 exige `result`.
- [ ] **Task:** implementar `adapters/agy/policy.php`.
  - **Acceptance criteria:** valida Linux, `bwrap`, token, agente e policy hash.
- [ ] **Task:** implementar `adapters/agy/parser.php`.
  - **Acceptance criteria:** aceita fixture válida e rejeita ambiguidade, modelo
    divergente, ferramenta proibida, terminal inválido e limites excedidos.

## Phase 3: Implementar runner e isolamento

- [ ] **Task:** implementar `preflight`, `run` e `version` em `runner.sh`.
  - **Acceptance criteria:** impl/verify usam flags e timeout explícitos, prompt
    hasheado e resultado normalizado.
- [ ] **Task:** implementar sandbox allowlisted do verify.
  - **Acceptance criteria:** host fora da allowlist não é visível, projeto é
    read-only, settings/env globais são ocultos e token não é copiado.
- [ ] **Task:** criar agente workspace e contrato do adapter.
  - **Acceptance criteria:** agente usa somente ferramentas read-only e arquivos
    descrevem limites sem conceder autoridade ao adapter.

## Phase 4: Integrar seam, readiness e instalação

- [ ] **Task:** criar seam comum de adapter no loop.
  - **Acceptance criteria:** OpenCode e `agy` passam por um único dispatch comum;
    Codex/Claude permanecem caracterizados.
- [ ] **Task:** registrar probes e isolamento no readiness `agy`.
  - **Acceptance criteria:** probes são não generativos e qualquer dependência
    ausente mantém `adapter_enabled=false`.
- [ ] **Task:** gerenciar adapter, agente e `.ralph/agy.env` no instalador.
  - **Acceptance criteria:** plan/apply/doctor/uninstall preservam atomicidade,
    ownership, conflitos e reversibilidade.

## Phase 5: Provar offline e contra regressão

- [ ] **Task:** adicionar fixtures e testes específicos do `agy`.
  - **Acceptance criteria:** parser, política, runner, canário e schema têm casos
    positivos e negativos sem credencial ou geração.
- [ ] **Task:** estender readiness, instalação, reprodução e multiprovider.
  - **Acceptance criteria:** seleção determinística passa a incluir `agy` na
    última posição executável, sem fallback.
- [ ] **Task:** executar checks obrigatórios.
  - **Acceptance criteria:** todos terminam com exit zero e saída capturada.

## Phase 6: Provar em campo, revisar e sincronizar

- [ ] **Task:** executar smoke real sanitizado de impl e verify.
  - **Acceptance criteria:** versão, sessão, modelo, terminal, policy hash e
    ausência de mutação são comprovados sem publicar conteúdo bruto.
- [ ] **Task:** realizar revisão adversarial independente.
  - **Acceptance criteria:** finding crítico/alto bloqueia promoção até correção.
- [ ] **Task:** atualizar STATUS, README, AGENT_GUIDE, backlog e relatório.
  - **Acceptance criteria:** documentação coincide com código/testes e separa
    suporte Linux atual de roadmap multiplataforma.
