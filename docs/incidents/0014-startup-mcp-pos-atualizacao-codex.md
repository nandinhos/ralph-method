# Incidente 0014 — Startup MCP interrompido após atualização do Codex

- **Data:** `2026-08-12` · **Severidade:** `média`
- **Responsável:** Equipe do Ralph Method
- **Estado:** `corrigido`

## Sintoma

Após uma atualização do Codex CLI, uma sessão nova exibiu:

```text
MCP startup interrupted. The following servers were not initialized: context7, headroom, openai-api-key-local-confirmation
```

O startup podia permanecer em `Starting MCP servers` por mais de um ciclo de
timeout antes de retornar ao prompt. Os três servidores estavam configurados e
o projeto do Ralph Method não apresentava alterações relacionadas ao MCP.

## Linha do tempo

| Quando (`YYYY-MM-DD HH:MM`) | O que aconteceu |
|---|---|
| `2026-08-11` | atualização do Codex CLI para `0.147.0` e primeira observação da interrupção MCP |
| `2026-08-11` | handshakes diretos de `context7`, `headroom` e `openai-api-key-local-confirmation` responderam corretamente |
| `2026-08-11` | teste isolado reproduziu a falha somente quando o Codex iniciava `context7` por `command = "npx"` |
| `2026-08-11` | caminho absoluto de `npx` foi aplicado no profile local e uma sessão nova inicializou os MCPs sem o aviso |

## Causa raiz (o PORQUÊ)

O Codex CLI `0.147.0` não completava de forma confiável o startup do
`context7` quando o profile usava `command = "npx"`, embora o mesmo servidor
respondesse ao handshake MCP quando iniciado diretamente. O launcher cancelava
a inicialização pendente; por isso o aviso final falava em servidores “não
inicializados”, em vez de indicar uma falha de protocolo do servidor.

A causa não foi credencial, incompatibilidade do protocolo MCP ou falha do
`headroom`/plugin. O gatilho foi a resolução do executável pelo launcher após a
atualização do Codex.

## Onde e como foi corrigido

O profile local foi ajustado em
`/home/nandodev/.codex/bc-harness.config.toml:27`:

```toml
[mcp_servers.context7]
command = "/home/nandodev/.nvm/versions/node/v22.22.1/bin/npx"
```

Os argumentos, timeouts, estado habilitado e os demais MCPs permaneceram
inalterados. Nenhuma configuração do projeto `ralph-method` foi modificada.

## Por que essa correção

O caminho absoluto remove a ambiguidade de resolução do launcher, preservando o
mesmo executável, pacote, argumentos e transporte. É uma correção menor e
reversível que trata a causa observada sem desabilitar o MCP, trocar provider ou
transformar um timeout maior em falsa evidência de saúde.

## Prevenção e próximos passos

- `docs/AGENT_GUIDE.md` passa a exigir um diagnóstico pós-atualização de
  harness para falhas MCP.
- A rotina exige `codex mcp list --json`, handshake direto e startup em sessão
  nova antes de aceitar a correção.
- O caminho absoluto só deve ser aplicado quando o handshake direto passar e a
  falha ficar restrita ao launcher do Codex.
- Se o handshake direto falhar, a rotina deve investigar dependência,
  autenticação ou servidor; não deve aplicar essa mitigação por inferência.
- O ADR-0014 registra a decisão operacional e seu gatilho de revisão.

## Validação

- `codex --profile bc-harness mcp list --json` confirmou `context7` e
  `headroom` habilitados e o comando absoluto de `npx`.
- Os três handshakes MCP responderam corretamente.
- Uma sessão nova do Codex `0.147.0` avançou pelo startup dos MCPs, chegou ao
  prompt e não exibiu `MCP startup interrupted`.
