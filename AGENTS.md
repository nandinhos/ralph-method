# Ralph Method — instruções do repositório

## Idioma

- Comunicação, documentação, planos, relatórios e commits em português do Brasil.
- Preserve comandos, paths, identificadores e nomes de providers.

## Papel do projeto

Este repositório contém o `Ralph Method`: um control plane local para execução
faseada, gates determinísticos, recuperação, handoff, memória e trace de
orquestração. Ele é agnóstico ao domínio do projeto-alvo.

O núcleo não importa código da aplicação-alvo, não usa banco de dados de
produto e não lê credenciais. O projeto-alvo fornece somente seu contrato de
fases, comandos de teste e contexto técnico.

Para instalação, execução, comunicação entre agentes, recuperação, atualização
e desinstalação, leia também [`docs/AGENT_GUIDE.md`](docs/AGENT_GUIDE.md). Esse
guia é versionado junto com `VERSION` e não pode ficar desatualizado.

## Fronteiras

- `bin/ralph-control` é a única autoridade da máquina de estados e do ledger.
- `bin/ralph-trace` registra fatos delegados através do controlador.
- `bin/ralph-monitor` observa execução e publica snapshots locais.
- `scripts/ralph.sh` executa fases; não aprova por texto de log.
- `bin/ralph-init` instala e desinstala o framework somente após plano explícito.
- Adaptadores de provider apenas normalizam saída; nunca gravam estado global.

## Verificação

```bash
bash scripts/check-shell.sh
bash scripts/check-doc-sync.sh
bash scripts/test-installation.sh
bash scripts/test-feedback.sh
bash scripts/test-ralph-method.sh
bash scripts/test-ralph.sh
```

Uma alteração do contrato de eventos, instalação ou fases exige teste de
regressão correspondente. Nunca usar SQLite, Laravel ou credenciais para
testar o núcleo portátil.

## Segurança

- Não registrar tokens, prompts, respostas completas ou valores de ambiente.
- Não sobrescrever arquivos existentes do projeto-alvo sem ownership explícito.
- Não trocar provider silenciosamente após falha.
- A instalação deve ser atômica, idempotente e reversível.
- O loop publica feedback sanitizado em JSONL; o consumidor externo observa,
  mas não aprova gates, muda leases ou escolhe a próxima feature.
