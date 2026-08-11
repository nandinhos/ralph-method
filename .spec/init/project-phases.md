# Plano de evolução do detector de Ralph legado

Workflow: `wf_detector_bc_legacy_20260810_001`

Este plano é executado pelo próprio Ralph Method. Cada feature é autorizada
separadamente pelo `ralph-control`. O projeto real `teste-events-opencode` não
será alterado por este workflow; a validação usa fixtures isoladas.

## Phase 1: Detector legado `bc-harness`

- [ ] detectar o padrão de diretório legado `install.sh` + `ralph.patch` + `ralph.sh.upstream`;
- [ ] emitir família, assinatura, caminho relativo e hashes;
- [ ] bloquear o `apply` comum quando a assinatura for confirmada;
- [ ] não realizar varredura global nem importar estado externo;
- [ ] cobrir fixture canônica, ambígua e falso positivo;
- [ ] atualizar contrato e documentação.

## Phase 2: Evolução e rollback de diretório

- [ ] criar backup integral de diretórios legados;
- [ ] registrar hashes individuais e hash composto;
- [ ] bloquear drift, path traversal e symlink externo;
- [ ] restaurar o diretório completo de forma idempotente;
- [ ] cobrir interrupção durante staging e restauração;
- [ ] preservar runtime e workflow do projeto.

## Phase 3: Regressão e release

- [ ] executar a suíte portátil completa;
- [ ] verificar instalação neutra sem falso positivo;
- [ ] verificar instalação legada com bloqueio correto;
- [ ] verificar repetição de evolve e rollback;
- [ ] atualizar relatórios, ADR, changelog, status e roadmap;
- [ ] preparar evidência para revisão e promoção.
