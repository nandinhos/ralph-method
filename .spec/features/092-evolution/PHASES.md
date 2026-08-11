# FEATURE-092-EVOLVE-BC-LEGACY

## Phase 1: Evoluir e restaurar diretório legado por hashes

- [ ] aceitar candidato de instalação do tipo `legacy_directory`;
- [ ] criar backup recursivo do diretório completo;
- [ ] registrar cada membro e o hash composto da árvore;
- [ ] preservar permissões e tipos de entrada suportados;
- [ ] não seguir symlink para fora da raiz do projeto;
- [ ] registrar journal antes e depois de cada movimento;
- [ ] instalar o Ralph Method somente após a quarentena completa;
- [ ] manter o estado em `awaiting_acceptance`;
- [ ] bloquear rollback se houver drift em qualquer membro;
- [ ] restaurar todos os membros com validação de hashes;
- [ ] manter staging em caso de falha intermediária;
- [ ] garantir que a repetição não duplique backup ou evolução;
- [ ] preservar `.git/ralph-control`, workflow, prompts e credenciais fora da migração;
- [ ] cobrir interrupção durante staging e restauração;
- [ ] atualizar o schema de evolução, testes e ADR.
