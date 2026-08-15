# Questões abertas

| Questão | Decisão provisória | Dono | Quando revisar |
|---|---|---|---|
| Qual modelo OpenCode será usado por um projeto? | exigir `RALPH_OPENCODE_MODEL` explícito; não escolher o primeiro modelo do catálogo | Ralph Method | antes do primeiro `apply` com runner OpenCode |
| O evento terminal será sempre `step_finish`? | OpenCode pode emitir vários `step_finish` na mesma sessão; o parser exige pelo menos um e rejeita sessões divergentes | Ralph Method | quando uma versão nova do OpenCode for certificada |
| O transporte do prompt será por argumento? | `--file` foi comprovado; argumento permanece fora do contrato inicial | Ralph Method | se uma versão futura retirar `--file` |
| Probe de geração real deve existir? | não nesta versão; probe seguro explícito usa diagnóstico local e não envia prompt | Ralph Method | política de custo/consentimento antes de uma versão futura |
| Como oferecer verify `agy` fora de Linux? | manter adapter degradado fora de Linux; não substituir `bwrap` por confiança em `--mode plan` | Ralph Method | sandbox externo equivalente comprovado em campo |

Hermes permanece adiado sem prioridade. O `agy` foi reaberto pelo
[`ADR-0017`](adr/0017-reabertura-agy-e-seam-comum-de-adapters.md); o suporte
multiplataforma continua explicitamente aberto sem enfraquecer o isolamento.
