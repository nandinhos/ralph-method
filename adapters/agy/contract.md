# Contrato do adapter `agy`

O adapter implementa a seam `preflight|run|version` descrita no ADR-0017. Ele
normaliza a Antigravity CLI; não escolhe feature/provider, não grava ledger e
não aprova gates.

## Execução

- `impl`: `agy --mode accept-edits --dangerously-skip-permissions`;
- `verify`: agente `ralph-review`, `--mode plan`, `--sandbox` e isolamento
  preventivo `bwrap` conforme ADR-0018;
- formato upstream: `stream-json` com `init`, `step_update` e `result`;
- terminal normalizado: `result`;
- transporte: o runner lê `--prompt-file`, hasheia o arquivo e o converte para
  argumento porque a CLI não oferece transporte por arquivo.

## Limites

Defaults: prompt 262144 bytes, stream 5242880 bytes, 10000 eventos e 1800
segundos. Exceder qualquer limite falha closed.

## Sanitização

O JSONL bruto existe apenas em diretório privado efêmero fora do projeto,
preferencialmente em `/dev/shm`, e é removido no fim. O
artefato persistido contém somente tipo/state/step/tool, sem prompt, resposta,
parâmetros, output ou usage. O resultado `1.1.0` contém apenas fatos de sessão,
modelo, policy, hashes, status e referências.

Para alimentar o gate 3, o parser projeta da resposta somente linhas canônicas
`TASK <n>: DONE|INCOMPLETE`; toda linha não vazia precisa corresponder
integralmente ao formato e cada task pode aparecer uma única vez. Prosa,
exemplos, comentários e duplicatas reprovam a sessão. Em `impl`, nenhum texto
de resposta é publicado pelo adapter.

No verify, a allowlist é `view_file`, `list_dir`, `grep_search` e
`find_by_name`, com schema fechado por ferramenta e paths sempre sob
`repo-root`. Parâmetro desconhecido, path externo ou qualquer outra ferramenta
reprova a sessão, mesmo quando a permissão upstream já bloqueou a chamada.

O app-data efêmero recebe um `settings.json` controlado com
`allowNonWorkspaceAccess=false`, lista vazia de comandos permitidos e apenas o
workspace atual como confiável. O agente declara `commandExecutionPolicy:
strict` e `inheritMcp: false`. Um probe real deve observar `ERROR` antes de
conteúdo ao tentar `view_file` no canário ao lado do token.

Antes da geração, a policy percorre o projeto e rejeita symlink quebrado ou
resolvido fora de `repo-root`, além de hardlink que compartilhe o inode do token.
Isso impede que uma ferramenta com path lexicalmente interno atravesse para um
mount sensível antes da validação pós-evento.
