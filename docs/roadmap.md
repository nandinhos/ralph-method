# Roadmap do Ralph Method

## Entrega atual — engine OpenCode (`v0.4.0` promovida localmente)

O trabalho foi executado isoladamente na branch `feat/opencode-engine` e
promovido localmente para `main` depois da regressão completa, da execução real
pelo próprio OpenCode e do teste de campo em projeto real.

- [x] fechar a capability: executor sem contexto/lease e teste negativo de transição;
- [x] provar término do grupo no caminho `ralph-control`, inclusive PID raiz que sai;
- [x] congelar o contrato agnóstico de runner e a caracterização de Codex/Claude;
- [x] introduzir a seam mínima sem migrar Codex/Claude prematuramente;
- [x] implementar preflight, execução e parser JSONL do OpenCode;
- [x] registrar sessão, provider e modelo no `ralph-trace` sem inferência indevida;
- [x] adicionar perfil, doctor, install/uninstall e seleção condicional;
- [x] validar permissões read-only do gate de verificação;
- [x] executar fixtures negativas e regressão completa;
- [x] provar uma sessão real em fixture descartável;
- [x] realizar teste de campo em worktree isolada de projeto real, com os cinco gates e handoff;
- [x] maturar completamente o adversarial do adapter OpenCode: revisão independente bounded, contrato de timeout, saída estruturada e repetição sem timeout; relatório `0006`;
- [x] revisar a superfície crítica da release com agente independente bounded e preparar promoção para `main`; relatório `0007`.
- [x] promover localmente a `v0.4.0` para `main` com `merge --ff-only`; push remoto permanece deliberadamente pendente.

O desenho detalhado, os riscos e os critérios estão em
[`architecture/opencode-engine-plan.md`](architecture/opencode-engine-plan.md).

O escopo ativo termina nos três harnesses Codex, Claude CLI e OpenCode. Hermes
e agy não são prioridades desta linha; seus itens estão formalmente adiados em
[`backlog.md`](backlog.md), com prioridade nenhuma.

- [x] prova exploratória real em fixture isolado, com output esperado e check;
- [x] prova complexa real com oráculo externo, hashes protegidos, trace e relatório `0002`;
- [x] prova complexa com revisão read-only real, fingerprint de política e duas delegações no trace; relatório `0003`;
- [x] teste de campo real com OpenCode, feature Laravel, cinco gates, handoff e continuidade automática; relatório `0004`;
- [x] certificação adversarial repetível do adapter OpenCode, incluindo prova das duas fontes da política (`--policy-proof` e `RALPH_OPENCODE_VERIFY_POLICY_PROOF`); relatório `0006`;
- [x] certificação final e promoção local da `v0.4.0`, incluindo timeout mitigado, revisão bounded, probe adversarial e campo real; relatório `0007`.
- [x] auditar desacoplamento, instalação reversível e reprodução em bundle Git independente; relatório `0008`.

## 0.3.1 — certificação de sessões CLI (base concluída)

- [x] reconhecer inventário de credenciais e catálogo de modelos do OpenCode;
- [x] identificar automaticamente o provider selecionado pelo Hermes;
- [x] separar `functional` da disponibilidade de `runner_supported`;
- [x] publicar providers funcionais e runners disponíveis no dry-run;
- [x] selecionar runners em ordem determinística, sem fallback silencioso;
- [x] fixtures offline de OpenCode e Hermes com bloqueio de geração;
- [x] adapter de execução OpenCode entregue na v0.4.0;
- [ ] adapter de execução Hermes — adiado para `BL-0001`, prioridade nenhuma;
- [ ] adapter de execução agy — adiado para `BL-0002`, prioridade nenhuma.

## 0.1.0 — extração do núcleo

- [x] control plane, trace, monitor e bloco extraídos;
- [x] contrato arquitetural inicial;
- [x] suíte portátil da extração.

## 0.2.0 — instalação exclusiva

- [x] `ralph-init plan` somente leitura;
- [x] `ralph-init apply` atômico e idempotente;
- [x] `ralph-init uninstall` reversível e protegido por ownership;
- [x] `ralph-doctor`;
- [x] manifesto e hashes da instalação;
- [x] matriz de capabilities;
- [x] feedback JSONL, stdout e callback para o orquestrador;
- [x] monitor mostra o último evento do loop;
- [x] fixtures de instalação, desinstalação e comunicação.

## 0.3.0 — prontidão condicional de providers

- [x] contrato de prontidão versionado;
- [x] autenticação e diagnóstico seguro explícitos;
- [x] bloqueio de adapter não funcional;
- [x] fixture offline de provider funcional, não autenticado e unsupported;
- [x] runner nativo Codex e fixture do loop;
- [x] runner nativo Claude CLI e fixture do loop;
- [x] adapter de execução OpenCode (entregue na v0.4.0);
- [ ] Hermes/agy como delegações filhas — backlog sem prioridade;
- [ ] regressão de execução multiprovider.
