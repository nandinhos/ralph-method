# Questões abertas

| Questão | Decisão provisória | Dono | Quando revisar |
|---|---|---|---|
| Qual modelo OpenCode será usado por um projeto? | exigir `RALPH_OPENCODE_MODEL` explícito; não escolher o primeiro modelo do catálogo | Ralph Method | antes do primeiro `apply` com runner OpenCode |
| Como o gate de revisão será read-only no OpenCode? | exigir agente ou política local com permissões de escrita negadas, comprovada no preflight | Ralph Method | antes de qualquer smoke real |
| O evento terminal será sempre `step_finish`? | duas provas reais em OpenCode 1.18.15 observaram `step_finish`; o parser falha fechado se não houver esse evento | Ralph Method | quando uma versão nova do OpenCode for certificada |
| O transporte do prompt será por argumento? | `--file` foi comprovado; argumento permanece fora do contrato inicial | Ralph Method | se uma versão futura retirar `--file` |
| O teste de campo usará `refactor-radar`? | candidato inicial, sempre em branch ou worktree isolada | Ralph Method | antes da execução de campo |
| Bundle local será versionado inteiro ou por release? | versionar o bundle inicial; medir tamanho antes de separar distribuição | Ralph Method | antes de 0.4.0 |
| OpenCode será engine principal ou apenas executor filho? | CLI certificada por probe seguro; engine só após adapter e smoke real | Ralph Method | após adapter OpenCode |
| Hermes será runner principal ou delegação filha? | CLI certificada por provider selecionado; runner só após adapter próprio | Ralph Method | após adapter Hermes |
| Probe de geração real deve existir? | não nesta versão; probe seguro explícito usa diagnóstico local e não envia prompt | Ralph Method | política de custo/consentimento antes de uma versão futura |
| Gate read-only OpenCode | ainda requer um agente/política verificável para o modo `verify`; a prova de implementação usou `--no-verify` explicitamente | Ralph Method | antes de habilitar os cinco gates com OpenCode |
