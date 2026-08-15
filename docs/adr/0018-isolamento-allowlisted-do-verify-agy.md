# ADR 0018 — Isolamento allowlisted do verify `agy`

- **Status:** accepted
- **Date:** `2026-08-14`
- **Owner:** Equipe do Ralph Method

## Context

Uma prova com `agy 1.1.13` refutou a premissa de que `--mode plan` é read-only:
o agente executou `write_to_file`. Montar `/` inteiro read-only protegeria a
integridade, mas ainda exporia arquivos legíveis do host. A revisão precisa
inspecionar o projeto, acessar o modelo autenticado e não ver o restante do
filesystem ou ambiente do usuário.

## Options considered

| Option | Pros | Cons |
|---|---|---|
| **A — Confiar em `--mode plan`** | multiplataforma e simples | escrita real foi observada |
| **B — Hash before/after** | detecta drift | detecta somente depois da mutação |
| **C — `/` inteiro read-only em `bwrap`** | impede escrita persistente | expõe arquivos e credenciais legíveis |
| **D — Raiz vazia com mounts allowlisted** | protege integridade e reduz exposição | v1 restrita a Linux e requer lista mínima mantida |

## Decision

Adotar a opção D. O verify inicia com ambiente limpo e uma raiz vazia. O
namespace monta read-only somente `/usr`, certificados e arquivos mínimos de
resolução de rede, binário `agy`, `repo-root` e o token OAuth no app-data
efêmero. `/tmp`, `/proc`, `/dev` e app-data são efêmeros/isolados. Settings
globais, skills, outros diretórios do usuário e variáveis externas não são
herdados. Em seu lugar, o runner monta um `settings.json` controlado com
`allowNonWorkspaceAccess=false`, `permissions.allow=[]` e apenas `repo-root`
em `trustedWorkspaces`.

`--mode plan`, `--sandbox` e o agente `ralph-review`, com
`commandExecutionPolicy: strict` e `inheritMcp: false`, permanecem defesa em
profundidade. A política nativa de file access nega preventivamente leitura
fora do workspace; uma prova real observou `view_file` terminar em `ERROR` ao
tentar um canário montado ao lado do token, sem publicar seu conteúdo. O parser
reprova ferramentas fora de `view_file`, `list_dir`, `grep_search` e
`find_by_name`, schemas de parâmetros desconhecidos, paths fora de `repo-root`
e qualquer ambiguidade de evento. O policy hash cobre as superfícies
versionadas dessa decisão.

Como paths lexicamente internos podem atravessar symlinks antes da inspeção do
evento, a policy também percorre `repo-root` antes da geração e rejeita symlink
quebrado ou resolvido externamente, além de hardlink para o inode do token.

O loop captura antes de `impl` a assinatura direta de runner, parser, policy,
agente e `scripts/ralph.sh`, incluindo tipo, modo, inode e conteúdo. Antes do
gate 3, qualquer divergência encerra a verificação sem chamar o adapter; o hash
autodeclarado pela policy não é usado como âncora contra adulteração do próprio
checker.

## Consequences

- verify `agy` v1 é suportado somente em Linux com `bwrap` funcional;
- ausência de isolamento ou token deixa readiness degradado e adapter disabled;
- o token é montado read-only, nunca copiado ou registrado, e a política de
  file access o mantém fora do alcance das ferramentas;
- rede continua disponível para a API do modelo, mas ferramentas de URL,
  browser, MCP e comandos não são autorizadas na sessão headless;
- impl não usa esse sandbox porque precisa mutar o projeto.

## Trigger to revisit

Revisitar quando houver sandbox externo equivalente comprovado em macOS/Windows,
quando o `agy` oferecer um modo read-only preventivo verificável ou quando uma
atualização da CLI exigir novo mount. Qualquer expansão da allowlist requer
fixture adversarial e nova prova real. Owner: Equipe do Ralph Method.
