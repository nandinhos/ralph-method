# Roadmap do Ralph Method

## Entrega concluída — engine OpenCode (`v0.4.0`)

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
- [x] promover a `v0.4.0` para `main` e sincronizar `origin/main`.

## Próxima evolução — hardening do control plane (`v0.5.0`)

- [x] reproduzir a concorrência de duas execuções para a mesma feature;
- [x] rejeitar a segunda execução antes de iniciar provider ou processo;
- [x] proteger `appendEvent()` com `workflow.lock` e posse reentrante;
- [x] validar o ledger após a execução concorrente focal;
- [x] cobrir crash, fencing, recuperação, workflow divergente, transição concorrente e append de eventos;
- [x] cobrir `repair-ledger`, restauração após falha intermediária e inicialização concorrente do runtime;
- [x] validar handoff e conhecimento não bloqueante, com curadoria idempotente e recuperação seletiva;
- [x] sincronizar `VERSION`, guia de agentes, `STATUS` e changelog da candidata `v0.5.0`;
- [x] automatizar regressão portátil em CI sem credenciais ou geração real;
- [x] publicar métricas operacionais somente leitura, sem custo/token e sem mutação.
- [x] repetir regressão adversarial e teste de campo OpenCode após o hardening;
- [x] corrigir e comprovar sanitização de UTF-8 em previews e resultados de runner.

O desenho detalhado, os riscos e os critérios estão em
[`architecture/control-plane-hardening-plan.md`](architecture/control-plane-hardening-plan.md).
O plano histórico da engine OpenCode permanece em
[`architecture/opencode-engine-plan.md`](architecture/opencode-engine-plan.md).

O escopo ativo termina nos três harnesses Codex, Claude CLI e OpenCode. Hermes
e agy não são prioridades desta linha; seus itens estão formalmente adiados em
[`backlog.md`](backlog.md), com prioridade nenhuma.

## Evolução concluída — instalação externa e rollback assistido (`v0.8.0`)

- [x] detectar sinais canônicos de Ralph fora do manifesto do Ralph Method;
- [x] emitir classificação, confiança, caminhos relativos e SHA-256 sem expor conteúdo;
- [x] bloquear `apply` comum para origem externa ou ambígua;
- [x] cobrir instalação externa, origem neutra, doctor e idempotência em fixture;
- [x] documentar a separação entre detecção, migração, backup e rollback;
- [x] implementar `evolve --plan/--apply` com inventário aprovado e backup verificável;
- [x] implementar `rollback --plan/--apply` com verificação de drift e restauração condicional;
- [ ] adicionar adapters de migração por origem, sem importar estado desconhecido por inferência;
- [x] testar backup incompleto e rollback após alteração do usuário;
- [x] testar recuperação de estado interrompido com reconstrução pelo manifesto;
- [ ] testar SIGKILL real durante rename e espaço insuficiente com fixture de falha de filesystem.

O detector e a evolução assistida foram validados na branch `dev`, incluindo
uma prova de campo conduzida pelo OpenCode, e promovidos para `main`; o
resultado está no relatório
[`0019`](reports/0019-evolucao-opencode-v0-8-0.md). A importação semântica de
estado legado e os adapters por origem continuam deliberadamente separados
até que exista um contrato específico e comprovado.

### Detector legado `bc-harness` — regressão e preparação de release

Na branch `feat/detector-bc-legacy`, as features `091-DETECT-BC-LEGACY` e
`092-EVOLVE-BC-LEGACY` entregaram o reconhecimento da assinatura `bc-harness`
somente em `harness/ralph` e a evolução de árvores `legacy_directory`. A
regressão que prepara a release desta entrega concluiu:

- [x] lint dos componentes alterados e `check-shell`/`check-doc-sync` verdes;
- [x] `test-installation` e `test-reproducibility` verdes;
- [x] regressão multiprovider e OpenCode verdes;
- [x] `ci-portable.sh` verde;
- [x] instalação neutra continua permitida;
- [x] `harness/ralph/` bloqueia o `apply` comum com `apply_allowed=false`;
- [x] evolve → aceite → drift → rollback comprovados em fixture isolada;
- [x] relatório `0021` e sincronização de ADR, status, roadmap, changelog e guia.
- [x] revalidada a regressão (attempt-4) após o hardening do supervisor e o fix
  de SIGPIPE: CI portátil verde e confirmações diretas reexecutadas, com
  evidência no relatório `0023`.

O commit da fase e a promoção para `main` aguardam a revisão independente
(regra do `ralph.sh`); a prova real de campo com o projeto-alvo original segue
como passo obrigatório antes da publicação desta release.

## Próxima evolução — memória episódica e taxonomia (`v0.6.0`)

- [x] materializar candidato sanitizado em `.ralph/knowledge-candidates/`;
- [x] separar retenção explícita de continuidade não bloqueante;
- [x] persistir lições com categoria, temas, stack, domínio e fingerprints;
- [x] gerar índice macro e subíndices derivados por categoria e tema;
- [x] filtrar recuperação por taxonomia antes do limite de contexto;
- [x] comprovar curadoria idempotente, descarte e decisão conflitante;
- [ ] integrar busca semântica ou hub externo de memória;
- [ ] projetar grafo de relações entre feature, incidente, commit, teste e lição.

A integração semântica e o grafo permanecem deliberadamente adiados até que
volume, recorrência ou necessidade de compartilhamento entre projetos forneçam
um gatilho mensurável.

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
- [x] regressão de execução multiprovider dos três harnesses fechados; relatório `0009`.
