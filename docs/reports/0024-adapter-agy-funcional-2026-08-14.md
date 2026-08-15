# Relatório 0024 — adapter `agy` funcional

- **Data:** 2026-08-14
- **Feature:** `FEATURE-095`
- **Status:** candidato validado localmente; promoção não executada
- **Versão publicada preservada:** `0.8.0`

## Intenção

Reabrir `BL-0002` e tornar a Antigravity CLI (`agy`) um runner de primeira
classe do Ralph Method, ampliando a capacidade do loop sem conceder autoridade
ao adapter, sem fallback silencioso e sem antecipar a FEATURE-094.

## Especificação entregue

- seam comum `preflight|run|version` para OpenCode e `agy`;
- adapter em `adapters/agy/` com runner Bash e parser/policy PHP fail-closed;
- `runner-result 1.1.0` para `agy`, terminal `result`, preservando OpenCode
  `1.0.0` e `step_finish`;
- implementação headless com modelo/effort explícitos;
- verify Linux dentro de raiz `bwrap` allowlisted, app-data e `/tmp` efêmeros,
  token OAuth read-only, file access restrito e ambiente limpo;
- agente workspace `ralph-review` e allowlist de ferramentas read-only;
- preflight contra symlink externo/quebrado e hardlink para o token;
- readiness não generativa, perfil `.ralph/agy.env`, ownership, doctor e
  uninstall pelo instalador existente;
- importação do resultado pelo controlador sem alteração de máquina de estados,
  leases, fencing ou gates.

## Segurança observada

A hipótese de que `agy --mode plan` seria uma fronteira read-only foi refutada:
uma prova controlada conseguiu executar `write_to_file` no scratch global da
CLI. O arquivo canário foi removido após a inspeção. Por isso, `plan` e
`--sandbox` são somente defesa em profundidade; a fronteira preventiva da v1 é
o namespace allowlisted do `bwrap`.

O parser avalia o JSONL bruto em diretório privado efêmero fora do projeto e
persiste somente a
projeção sanitizada. Prompt, resposta, parâmetros, output de ferramenta, usage,
stderr e token não entram em resultado, trace, relatório ou documentação.
Para o gate 3, a resposta é reduzida a linhas canônicas
`TASK <n>: DONE|INCOMPLETE`; prosa, exemplos, comentários e duplicatas reprovam
a sessão. Impl não publica texto de resposta.
Symlinks que saem do projeto e hardlinks para o token são rejeitados antes da
geração, evitando leitura de mount sensível por path lexicalmente interno.
O loop também fixa a assinatura das superfícies de verify antes de `impl` e
bloqueia qualquer adulteração antes de chamar o gate 3. O controlador revalida
provider, modelo observado e ausência de fallback e exige exatamente um
resultado `impl` e um `verify` no caminho normativo `--engine agy`.

A revisão adversarial inicial apontou que o token no mesmo namespace ainda
poderia ser alvo de uma ferramenta de leitura. A correção adicionou
`allowNonWorkspaceAccess=false`, lista vazia de comandos permitidos,
`commandExecutionPolicy: strict` e MCP desativado. No probe real, `view_file`
contra um canário montado ao lado do token terminou em `ERROR`; nenhum conteúdo
do canário apareceu nos artefatos. O parser também passou a aceitar somente
schemas exatos de parâmetros e a interromper antes de carregar streams acima
do limite.

## Evidência de campo sanitizada

Comando explícito:

```bash
bash scripts/test-agy-field.sh
```

Resultado observado com `agy 1.1.13` e `gemini-3.7-flash-high`:

| Modo | Schema | Terminal | Eventos | Política | Árvore Git |
|---|---|---|---:|---|---|
| impl | `1.1.0` | `result` | 6 | `not_required` | inalterada |
| verify | `1.1.0` | `result` | 9 | `verified`, agente `ralph-review` | inalterada |

O probe adicional de leitura fora do workspace foi reprovado como esperado,
com evidência sanitizada `outside_workspace/denied` e árvore inalterada.

A primeira tentativa de verify encerrou antes de `init`: o projeto temporário
estava sob `/tmp`, e o `tmpfs /tmp` posterior ocultava o bind já criado. A ordem
foi corrigida para montar primeiro o `/tmp` efêmero e depois `repo-root`; a
fixture offline passou a afirmar essa ordem e a repetição real terminou verde.

## Evidência automatizada

| Check | Cobertura | Resultado |
|---|---|---|
| `scripts/test-agy-adapter.sh` | parser, schema real, policy hash, sanitização, allowlist e isolamento fake | verde |
| `scripts/test-agy-loop.sh` | dispatch impl + verify, gate 0 e ausência de queda no branch Claude | verde |
| `scripts/test-agy-control.sh` | importação `agy` 1.1.0 e integridade do ledger | verde |
| `scripts/test-provider-readiness.sh` | modelos/agentes, dependências Linux e degradação fail-closed | verde |
| `scripts/test-multiprovider.sh` | seleção determinística de quatro runners e `fallback_policy=none` | verde |
| `scripts/test-installation.sh` | apply, ownership, idempotência e uninstall dos arquivos `agy` | verde |
| OpenCode policy/adapter | compatibilidade do adapter existente após a seam | verde |
| `scripts/test-ralph-method.sh` | máquina de estados e importação controlada | verde |
| `scripts/test-ralph.sh` | 163 asserts do loop | verde |
| matriz obrigatória de `AGENTS.md` | dez comandos, incluindo reprodução e loop | verde |
| `scripts/ci-portable.sh` | matriz sem credenciais, reconciliação, métricas e ambos os adapters | verde |

A primeira execução da matriz expôs que `test-reproducibility.sh` criava o
bundle somente de `HEAD` e, portanto, não exercitava arquivos novos antes do
commit. A prova passou a sobrepor ao archive apenas mudanças versionáveis do
checkout e a repetição terminou verde. Nenhuma alegação de promoção, tag ou
publicação decorre deste relatório.

## Decisões e limites

- ADR-0017: reabertura e seam comum de adapters;
- ADR-0018: isolamento allowlisted do verify `agy`;
- ADR-0019: matriz `runner-result` 1.0/1.1;
- verify v1 fora de Linux permanece adiado;
- `FEATURE-094` e `fallback_policy=none` permanecem inalterados;
- o transporte `file_to_argument` é uma limitação conhecida da CLI e pode ser
  visível transitoriamente ao mesmo usuário no process table;
- a versão publicada continua `0.8.0`; este trabalho é um candidato no checkout.
