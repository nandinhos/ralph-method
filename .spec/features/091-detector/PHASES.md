# FEATURE-091-DETECT-BC-LEGACY

## Phase 1: Detectar instalação Ralph legada bc-harness

- [ ] auditar o detector atual e preservar os 17 sinais canônicos;
- [ ] adicionar detector limitado para `harness/ralph/` e raízes legadas aprovadas;
- [ ] reconhecer a composição `install.sh`, `ralph.patch` e `ralph.sh.upstream`;
- [ ] emitir `family=bc-harness` e `signature_id` sem armazenar conteúdo bruto;
- [ ] registrar membros, caminhos relativos, tipos e SHA-256;
- [ ] calcular fingerprint determinístico da árvore legada;
- [ ] classificar a instalação como `external_ralph_legacy`;
- [ ] retornar `apply_allowed=false` e recomendar `evolve`;
- [ ] manter `migration_supported=false`;
- [ ] listar candidatos legados sem transformar qualquer arquivo parecido em instalação;
- [ ] rejeitar caminhos absolutos, traversal e symlink externo;
- [ ] adicionar fixture TDD para o padrão legado real;
- [ ] adicionar fixture de falso positivo em `vendor` e `node_modules`;
- [ ] atualizar o schema de detecção, testes e documentação.
