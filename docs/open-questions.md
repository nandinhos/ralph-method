# Questões abertas

| Questão | Decisão provisória | Dono | Quando revisar |
|---|---|---|---|
| Qual modelo OpenCode será usado por um projeto? | exigir `RALPH_OPENCODE_MODEL` explícito; não escolher o primeiro modelo do catálogo | Ralph Method | antes do primeiro `apply` com runner OpenCode |
| Como o gate de revisão será read-only no OpenCode? | resolvido nesta branch: `ralph-review` + fingerprint + prova externa com canário, marcador JSONL, superfície de política preservada e revalidação antes/depois | Ralph Method | ao certificar nova versão do OpenCode |
| O evento terminal será sempre `step_finish`? | OpenCode pode emitir vários `step_finish` na mesma sessão; o parser exige pelo menos um e rejeita sessões divergentes | Ralph Method | quando uma versão nova do OpenCode for certificada |
| O transporte do prompt será por argumento? | `--file` foi comprovado; argumento permanece fora do contrato inicial | Ralph Method | se uma versão futura retirar `--file` |
| O teste de campo usará `refactor-radar`? | candidato inicial, sempre em branch ou worktree isolada | Ralph Method | antes da execução de campo |
| Bundle local será versionado inteiro ou por release? | versionar o bundle inicial; medir tamanho antes de separar distribuição | Ralph Method | antes de 0.4.0 |
| OpenCode será engine principal ou apenas executor filho? | CLI certificada por probe seguro; engine só após adapter e smoke real | Ralph Method | após adapter OpenCode |
| Hermes será runner principal ou delegação filha? | CLI certificada por provider selecionado; runner só após adapter próprio | Ralph Method | após adapter Hermes |
| Probe de geração real deve existir? | não nesta versão; probe seguro explícito usa diagnóstico local e não envia prompt | Ralph Method | política de custo/consentimento antes de uma versão futura |
| Gate read-only OpenCode | comprovado em campo; implementação e revisão são sessões distintas no `ralph-trace` | Ralph Method | ao trocar agente, política ou versão da CLI |
| Revisão adversarial do adapter OpenCode | resolvido com probe direto do OpenCode, `--format json`, `ralph-review`, timeout de 180s, verdict estruturado e hash da superfície | Ralph Method | ao trocar agente, política ou versão da CLI |
