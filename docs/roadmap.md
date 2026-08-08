# Roadmap do Ralph Method

## 0.3.1 — certificação de sessões CLI

- [x] reconhecer inventário de credenciais e catálogo de modelos do OpenCode;
- [x] identificar automaticamente o provider selecionado pelo Hermes;
- [x] separar `functional` da disponibilidade de `runner_supported`;
- [x] publicar providers funcionais e runners disponíveis no dry-run;
- [x] selecionar runners em ordem determinística, sem fallback silencioso;
- [x] fixtures offline de OpenCode e Hermes com bloqueio de geração;
- [ ] adapters de execução OpenCode e Hermes.

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
- [ ] contrato de adapter Codex;
- [ ] fixture e adapter Claude;
- [ ] adapter de execução OpenCode;
- [ ] Hermes/agy como delegações filhas;
- [ ] regressão de execução multiprovider.
