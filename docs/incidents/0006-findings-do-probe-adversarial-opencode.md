# Incidente 0006 — findings do probe adversarial OpenCode

## Contexto

Após a revisão `bc-reviewer` expirar, foi criado um probe adversarial direto
usando o próprio OpenCode, com `--format json`, `--agent ralph-review`,
`--pure`, prompt por `--file` e timeout externo de 180 segundos.

## Causas confrontadas

| Finding | Evidência | Causa | Correção |
|---|---|---|---|
| O teste exigia exatamente um `step_finish` | primeira execução real: 4 `step_finish`, 1 sessão, exit do probe 1 | confundia evento terminal de etapa com cardinalidade da sessão | aceitar pelo menos um `step_finish` na mesma sessão |
| Parser aceitava JSONL com sessões diferentes | revisão real apontou `parser.php` usando `sessionId ??=` | somente a primeira sessão era considerada | rejeitar imediatamente `sessionID` divergente |
| Runner podia enviar dois `--agent` | revisão real apontou `runner.sh:176` e `runner.sh:180` | argumento e variável de ambiente eram anexados separadamente | resolver um único agente; divergência falha antes da CLI |

## Reteste real

Depois das correções, o probe terminou:

| Campo | Resultado |
|---|---|
| Modelo | `opencode/big-pickle` |
| Versão | OpenCode `1.18.15` |
| Exit code | `0` |
| Verdict | `ADVERSARIAL_VERDICT: PASS` |
| Sessões | 1 |
| `step_finish` | 4 |
| Ferramentas observadas | 10: 2 glob, 6 read, 2 grep |
| Ferramentas proibidas | nenhuma executada |
| Hash da superfície | idêntico antes/depois |
| Duração | 38s |

O probe também possui regressões locais para múltiplos `step_finish` na mesma
sessão, múltiplas sessões e agentes divergentes.

## Confronto com documentação oficial

- OpenCode documenta `run --format json`, seleção por `--agent`, agente por
  configuração e permissões `deny`; `--auto` não substitui uma regra explícita
  `deny`.
- Codex documenta `exec --json`, `--ephemeral` e `--sandbox read-only`.
- Claude Code documenta `--print`, `--output-format json`,
  `--allowedTools`/`--disallowedTools` e `--max-turns`.

Referências primárias consultadas em 08/08/2026:

- https://opencode.ai/docs/cli/
- https://opencode.ai/docs/agents
- https://opencode.ai/v2/docs/permissions
- https://docs.anthropic.com/en/docs/claude-code/cli-usage
- https://github.com/openai/codex/blob/main/codex-rs/README.md
- https://github.com/openai/codex/blob/main/codex-rs/exec/src/cli.rs

## Estado

`resolved` — os findings foram corrigidos e o probe adversarial direto passou.
A revisão final da branch completa e a regressão antes da promoção permanecem
como gates de release.
