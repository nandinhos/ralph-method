# Relatório 0009 — regressão multiprovider dos harnesses fechados

**Data:** 2026-08-09
**Versão:** `0.4.0`
**Branch de validação:** `feat/multiprovider-regression`
**Escopo:** seleção `auto`, prontidão, ausência de fallback silencioso e
identidade no `ralph-trace` para Codex, Claude CLI e OpenCode

## Conclusão

A regressão offline passou. O controlador seleciona somente providers com
autenticação confirmada, diagnóstico saudável, runner suportado e adapter
habilitado. A ordem permanece determinística — Codex, Claude CLI e OpenCode —
e a ausência de um provider funcional não produz executor fictício nem troca
silenciosa de provider.

Esta prova não gera tokens nem chama uma sessão real. Cada CLI do fixture
rejeita argumentos de execução (`--print`, `exec` e `run`), e o teste falharia
se qualquer probe tentasse gerar conteúdo. As provas reais dos harnesses
continuam separadas: smoke de Codex/Claude e campo/adversarial do OpenCode.

## Matriz de cenários

| Cenário | Providers funcionais | Seleção `auto` | Modo | Runners disponíveis | Resultado |
|---|---|---|---|---|---|
| Todos autenticados | Codex, Claude, OpenCode | `codex` | `native_codex` | `codex`, `claude`, `opencode` | verde |
| Codex não autenticado | Claude, OpenCode | `claude` | `single_provider` | `claude`, `opencode` | verde |
| Somente OpenCode autenticado | OpenCode | `opencode` | `single_provider` | `opencode` | verde |
| Nenhum autenticado | nenhum | `null` | `needs_review` | nenhum | bloqueio correto |
| Claude explícito não autenticado | nenhum apto para o pedido | `claude` sem adapter | `needs_review` | nenhum apto | `apply` exit `3` |

Em todos os cenários, `fallback_policy` permaneceu `none`. Quando o provider
solicitado explicitamente não está apto, o plano não muda o pedido para outro
provider e o `apply` é rejeitado pelo instalador.

## Identidade registrada no trace

O fixture abriu um único bloco sob lease do controlador e registrou três
delegações, uma por harness. O relatório confirmou `identity_status=exact`,
`identity_source=usage_file` e `fallback_status=not_detected` para cada linha:

| Runner | Provider | Modelo efetivo | Sessão |
|---|---|---|---|
| `codex` | `openai` | `gpt-5-codex` | `sess_trace_codex` |
| `claude` | `anthropic` | `claude-sonnet-4-20250514` | `sess_trace_claude` |
| `opencode` | `opencode` | `opencode/deepseek-v4-flash-free` | `sess_trace_opencode` |

O segundo `plan` com os mesmos sinais produziu o mesmo resumo de seleção,
confirmando o determinismo sem comparar timestamps ou caminhos temporários.

## Comando e resultado

```bash
bash scripts/test-multiprovider.sh
```

Saída observada:

```text
OK: regressão multiprovider offline, seleção determinística, bloqueio sem fallback, probes não generativos e trace dos três harnesses passaram.
```

O script também verifica que:

- o probe é `safe` e `live_generation_probe=false`;
- Codex não autenticado fica fora de `available_runners`;
- `needs_review` materializa `selected_provider=null` e
  `primary_runner=null` quando não há runner apto;
- nenhum argumento generativo chega às fixtures;
- Hermes e agy não são promovidos por estarem instalados ou detectáveis;
- a ordem da fila do `ralph-control` não pode ser burlada pelo teste de trace.

## Limites e decisão

Esta regressão fecha a validação da seleção multiprovider dos três harnesses
ativos. Ela não transforma Hermes ou agy em adapters executáveis e não altera a
política de conhecimento, que permanece não bloqueante. A implementação de
adapters Hermes/agy continua registrada no backlog com prioridade nenhuma.
