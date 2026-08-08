# ADR 0005 — Contrato agnóstico de runner e engine OpenCode

## Status

Proposta em implementação controlada na branch `feat/opencode-engine`.

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

O processo controlado atualmente herda variáveis do controlador para o
executor e verifica o término principalmente pela árvore do PID raiz. Esses
fatos são riscos de segurança e recuperação que precisam ser resolvidos antes
de afirmar que um adapter é isolado.

## Opções consideradas

### Espalhar condições OpenCode dentro de `scripts/ralph.sh`

Rejeitada. É a menor mudança imediata, mas aumenta o acoplamento do núcleo,
duplica parsing de saída e torna cada provider uma exceção no orquestrador.

### Criar apenas um wrapper específico para OpenCode

Rejeitada como solução final. Reduz o risco inicial, mas deixa Codex e Claude
fora de um contrato comum e impede que o teste de regressão prove a abstração.

### Extrair um contrato de runner e implementar OpenCode atrás dele

Escolhida com escopo incremental. O núcleo passa a coordenar contexto, gates e
recuperação; o adapter OpenCode traduz invocação, saída e identidade do
provider para um resultado normalizado. Codex e Claude permanecem nos caminhos
estáveis durante a primeira entrega; sua migração para wrappers comuns só será
considerada depois de a seam provar valor com OpenCode.

## Decisão proposta

Implementar uma seam de runner com quatro operações: `preflight`, `run`,
`classify` e `metadata`. O adapter OpenCode usará `opencode run --format json`
em uma sessão nova, com `--dir` e `--model` explícitos. O transporte preferido
será arquivo anexado; argumento posicional só será permitido com limite
verificado. `--auto` e `--pure` serão políticas configuráveis, nunca
comportamentos implícitos do núcleo.

O adapter devolverá sessão, modelo e provider somente no nível comprovado pela
saída. Ausência de evidência de fallback será `unknown`, não `false`. O
`ralph-trace` receberá fatos sanitizados depois da importação feita pelo
controlador; o adapter não terá lease nem poderá alterar workflow, gates ou
fila.

Capability e término de processo são pré-condições do adapter: o controlador
deverá remover credenciais de transição do ambiente do executor, observar o
grupo mesmo após a saída do PID raiz e bloquear a execução quando não puder
provar que o grupo terminou.

## Consequências

### Positivas

- OpenCode entra como executor sem transformar o Ralph em um script específico;
- Codex e Claude permanecem protegidos por characterization tests sem migração
  especulativa nesta entrega;
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

Revisitar a seam quando um segundo provider novo, fora dos caminhos legacy,
precisar ser adicionado ou quando a execução real comprovar que o contrato de
processo não consegue transportar a sessão sem estado persistente. O dono é a
Equipe do Ralph Method; o sinal observável é uma segunda implementação que
exigiria exceção no núcleo ou um stream bidirecional não redutível a `run` +
resultado. Até esse gatilho, não migrar Codex/Claude por antecipação. Nesse
caso, acrescentar um segundo tipo de transporte ao contrato, sem mover
autoridade para o adapter.

## Responsável

Equipe do Ralph Method.

## Data

2026-08-08.
