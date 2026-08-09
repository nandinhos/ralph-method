# Relatório 0011 — CI portátil da candidata v0.5.0

**Data:** 2026-08-09
**Versão:** `0.5.0`
**Branch:** `feat/ralph-hardening`
**Escopo:** execução repetível da regressão sem credenciais ou geração real

## Implementação

| Componente | Função |
|---|---|
| `.github/workflows/ci.yml` | dispara a CI em `main`, `feat/**` e pull requests para `main` |
| `scripts/ci-portable.sh` | mantém a lista oficial e ordenada de checks offline |
| `permissions: contents: read` | limita o token padrão do job à leitura |
| `concurrency` | cancela execução obsoleta da mesma referência |
| timeout de 20 minutos | impede job preso de consumir o runner indefinidamente |

O workflow usa `actions/checkout@v7` e `shivammathur/setup-php@v2`, com PHP
`8.2`. O ShellCheck é exigido pelo `check-shell.sh` e a imagem Ubuntu fornece
a ferramenta no ambiente oficial do job.

## Fronteira de segurança

Entram na CI apenas testes que não precisam de sessão autenticada, token,
rede de provider ou geração real. O teste de campo e o adversarial real do
OpenCode continuam comandos explícitos de validação de ambiente e não são
executados automaticamente em pull requests.

## Evidência local

```bash
bash scripts/ci-portable.sh
```

Resultado observado:

```text
OK: shell limpo.
OK: instalação, idempotência, ownership, desinstalação e preservação passaram.
OK: bundle Git reproduzido em projeto independente; plan/apply/doctor/uninstall e limpeza passaram.
OK: handoff, conhecimento non_blocking, curadoria idempotente e recuperação seletiva passaram.
TODOS VERDES: 163 asserts
OK: adapter OpenCode, transporte por arquivo, parser, schema impl/verify, sessão, evento terminal, tri-state e limites passaram.
OK: CI portátil concluída sem credenciais ou geração real.
```

## Limites

A execução local prova o script e os contratos da CI, mas não substitui a
confirmação do status do job no GitHub após o push. As provas reais de
Codex/Claude/OpenCode continuam dependentes do ambiente autenticado e serão
repetidas no checkpoint de promoção.
