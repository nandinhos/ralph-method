# ADR 0005 — Contrato agnóstico de runner e engine OpenCode

## Status

Proposta em planejamento.

## Contexto

O Ralph Method já certifica a CLI OpenCode como funcional por meio de probes
locais, mas ainda não possui um runner que execute fases por ela. O loop atual
contém dispatch específico para Codex e Claude. Adicionar flags OpenCode
diretamente ao loop resolveria o primeiro caso, mas espalharia conhecimento de
provider no núcleo e tornaria a evolução para Hermes, agy ou outro executor
mais cara e menos auditável.

O projeto precisa de uma engine que possa ser testada pelo próprio OpenCode e
depois em um projeto real, sem abrir mão dos gates, do trace, da recuperação
explícita ou da ausência de fallback silencioso.

## Opções consideradas

### Espalhar condições OpenCode dentro de `scripts/ralph.sh`

Rejeitada. É a menor mudança imediata, mas aumenta o acoplamento do núcleo,
duplica parsing de saída e torna cada provider uma exceção no orquestrador.

### Criar apenas um wrapper específico para OpenCode

Rejeitada como solução final. Reduz o risco inicial, mas deixa Codex e Claude
fora de um contrato comum e impede que o teste de regressão prove a abstração.

### Extrair um contrato de runner e implementar OpenCode atrás dele

Escolhida. O núcleo passa a coordenar contexto, gates e recuperação; cada
adapter traduz invocação, saída e identidade do provider para um resultado
normalizado. O primeiro adapter real será OpenCode, preservando os runners
existentes por wrappers compatíveis.

## Decisão proposta

Implementar uma seam de runner com quatro operações: `preflight`, `run`,
`classify` e `metadata`. O adapter OpenCode usará `opencode run --format json`
em uma sessão nova, com `--dir` e `--model` explícitos. `--auto` e `--pure`
serão políticas configuráveis, nunca comportamentos implícitos do núcleo.

O adapter devolverá sessão, modelo e provider somente no nível comprovado pela
saída. O `ralph-trace` receberá fatos sanitizados; o adapter não poderá alterar
workflow, leases, gates ou fila.

## Consequências

### Positivas

- OpenCode entra como executor sem transformar o Ralph em um script específico;
- Codex e Claude podem ser protegidos por characterization tests e migrados
  gradualmente para o mesmo contrato;
- fallback silencioso continua impossível;
- a identidade de modelo permanece honesta quando a CLI não a expõe;
- a execução real e o teste de campo produzem evidência comparável;
- a futura versão para Hermes ou agy reaproveita o contrato.

### Custos

- a primeira entrega toca o dispatch do loop e exige regressão mais ampla;
- o perfil precisa de um modelo explícito;
- o gate de verificação precisa de uma política read-only real no OpenCode;
- o parser precisará acompanhar mudanças relevantes do JSONL.

## Gatilho para revisitar

Revisitar a seam se dois providers exigirem protocolos incompatíveis com o
contrato de processo — por exemplo, uma sessão persistente obrigatória ou um
stream bidirecional que não possa ser reduzido a `run` + resultado. Nesse caso,
acrescentar um segundo tipo de transporte ao contrato, sem mover autoridade
para o adapter.

## Responsável

Equipe do Ralph Method.

## Data

2026-08-08.
