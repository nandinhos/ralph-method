# FEATURE-093-REGRESSION-RELEASE

## Phase 1: Validar regressão e preparar release do detector legado

- [ ] executar `php -l` nos componentes alterados;
- [ ] executar `bash scripts/check-shell.sh`;
- [ ] executar `bash scripts/check-doc-sync.sh`;
- [ ] executar `bash scripts/test-installation.sh`;
- [ ] executar `bash scripts/test-reproducibility.sh`;
- [ ] executar a regressão multiprovider e OpenCode;
- [ ] executar `bash scripts/ci-portable.sh`;
- [ ] confirmar que instalação neutra continua permitida;
- [ ] confirmar que `harness/ralph/` bloqueia o apply comum;
- [ ] confirmar evolve, aceite, drift e rollback em fixture isolada;
- [ ] produzir relatório numerado 0021, 0022 ou 0023 conforme o escopo;
- [ ] atualizar ADR, status, roadmap, changelog e guia;
- [ ] registrar limitações sem executar o projeto-alvo original;
- [ ] preparar commit e promoção somente após revisão independente.
