# ADR-0015 — Self-hosting do Ralph Method com runner Codex

- **Status:** accepted
- **Date:** `2026-08-13`
- **Owner:** Equipe do Ralph Method

## Contexto

O próprio repositório `ralph-method` precisa continuar sendo desenvolvido com
o control plane que fornece. O `ralph-init` bloqueia corretamente a instalação
normal quando detecta os binários e o ledger do Ralph no checkout, pois esse
fluxo é destinado a projetos-alvo externos e não pode sobrescrever uma
instalação existente.

O Codex CLI está autenticado, saudável e com runner suportado. O OpenCode não
é necessário para esta linha de implementação e seu diagnóstico atual está
degradado.

## Opções consideradas

| Opção | Vantagens | Desvantagens |
|---|---|---|
| **A — Forçar `ralph-init apply` no próprio repositório** | Reutiliza o fluxo padrão de instalação | Viola o bloqueio contra auto-instalação e mistura fonte com cópia gerenciada |
| **B — Executar `scripts/ralph.sh` diretamente em cada fase** | Funciona sem perfil adicional | Deixa a política do projeto implícita e facilita usar o engine errado |
| **C — Perfil self-hosted versionado com runner nativo Codex** | Explicita a política, preserva o bloqueio do instalador e usa o mesmo loop local | Exige árvore limpa e fase aprovada antes de cada execução |

## Decisão

Adotamos a opção C.

O arquivo `.ralph/codex.env` é o perfil self-hosted do repositório e define:

- `RALPH_BIN=scripts/ralph.sh`;
- `RALPH_CODEX_PROFILE=bc-harness`;
- `RALPH_CODEX_MODEL=gpt-5.6-luna`;
- `RALPH_CODEX_REASONING_EFFORT=high`;
- `RALPH_VERIFY_MODEL=gpt-5.6-luna`.
- `RALPH_TEST_CMD=bash scripts/ci-portable.sh`.

As fases do próprio projeto devem ser iniciadas pelo wrapper versionado:

```bash
bin/ralph-bloco <fase-inicial> <fase-final> codex
```

Codex é um runner nativo de `scripts/ralph.sh`; não há um diretório de
adapter Codex a criar. O `ralph-init` continua proibido de aplicar uma
instalação sobre este checkout.

## Consequências

- A escolha do engine fica explícita e reproduzível no projeto.
- A implementação e a verificação usam o Codex, sem fallback silencioso para
  OpenCode.
- O wrapper mantém os gates, commits por fase, autoridade do plano e logs do
  Ralph.
- A árvore precisa estar limpa antes da execução, inclusive o perfil
  self-hosted deve estar commitado.
- O método continua instalado de forma especial neste repositório, sem
  `install-manifest.json`; projetos externos seguem o fluxo normal de
  `ralph-init`.

## Gatilho para revisitar

Revisitar se o self-hosting precisar de manifesto gerenciado, evolução
transacional do próprio runtime ou distribuição de uma cópia separada do
framework. Nesse caso, criar um fluxo específico antes de relaxar o bloqueio
de auto-instalação.
