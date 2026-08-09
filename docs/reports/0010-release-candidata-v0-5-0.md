# Relatório 0010 — higiene da release candidata v0.5.0

**Data:** 2026-08-09  
**Versão:** `0.5.0`  
**Branch:** `feat/ralph-hardening`  
**Escopo:** sincronização de versão, documentação operacional e reprodução do bundle

## Objetivo

Preparar a evolução do control plane e da memória de engenharia para uma
validação controlada, sem declarar publicação, criar tag ou alterar `main`.

## Alterações verificadas

| Área | Evidência | Resultado |
|---|---|---|
| Fonte da versão | `VERSION` = `0.5.0` | verde |
| Guia do agente | `docs/AGENT_GUIDE.md` usa `method_version: 0.5.0` | verde |
| Instalador | `bin/ralph-init plan` devolve a versão do bundle | verde |
| Status | `docs/STATUS.md` registra a candidata sem promoção | verde |
| Changelog | `CHANGELOG.md` separa mudanças novas de `v0.4.0` publicada | verde |
| Teste de instalação | idempotência, ownership, uninstall e preservação | verde |
| Reprodução | archive Git, `plan/apply/doctor/uninstall` em projeto independente | verde |

## Comandos executados

```bash
bash scripts/check-doc-sync.sh
php -l bin/ralph-init
bash scripts/check-shell.sh
bash scripts/test-installation.sh
bash scripts/test-reproducibility.sh
git diff --check
```

Todos os comandos terminaram com exit code `0` no checkpoint da fase.

## Decisão

A Fase 2 está concluída nesta branch. A versão `0.5.0` permanece candidata:
não foi criada tag anotada, não houve push e `main` continua em `v0.4.0`.
A promoção depende da regressão final, da CI portátil e das métricas
somente leitura previstas nas fases seguintes.

## Limites

Este relatório não certifica a execução real de provider nem substitui a
regressão completa do control plane. As provas de OpenCode e dos três
harnesses permanecem nos relatórios próprios e serão reexecutadas no
checkpoint final antes da promoção.
