# ADR 0004 — Prontidão condicional de providers

## Status

Aceita.

## Contexto

O Ralph Method detectava executáveis e versões, mas isso não comprovava que o
provider estava autenticado nem que sua integração local estava saudável. Um
adapter habilitado apenas pela presença da CLI poderia falhar no primeiro uso,
trocar o executor sem transparência ou consumir geração durante uma simples
instalação.

## Opções consideradas

### Habilitar pelo executável encontrado

Rejeitada. Instalação não é autenticação e versão não é prontidão.

### Executar um prompt real automaticamente

Rejeitada. Consome tokens, pode alterar estado externo e transforma instalação
em uma operação com custo e efeitos colaterais não autorizados.

### Probe seguro explícito, com diagnóstico local e estados fail-closed

Escolhida. `ralph-init` mantém a detecção passiva por padrão. A flag
`--verify-providers` chama somente comandos diagnósticos registrados para cada
provider, com timeout, resultado sanitizado e sem prompt. O adapter só é
habilitado quando autenticação e diagnóstico local passam.

## Decisão

O contrato versionado está em `schemas/provider-readiness.schema.json` e é
persistido em `.ralph/providers.json`. Cada provider informa:

- `auth_status`: `not_checked`, `unknown`, `authenticated` ou
  `unauthenticated`;
- `health_status`: `not_checked`, `unsupported`, `healthy` ou `unhealthy`;
- `status`: estado agregado, incluindo `functional`;
- `adapter_enabled`: verdadeiro somente para `functional`;
- `capabilities`, motivo sanitizado, códigos de saída e timestamps.

Seleção explícita de provider não funcional falha fechada no `apply`. Seleção
`auto` só escolhe provider funcional; se nenhum estiver pronto, o núcleo pode
ser instalado em `needs_review`, sem fallback silencioso.

`functional` significa autenticação confirmada e diagnóstico local não
generativo aprovado. Não é uma alegação de que uma chamada de modelo foi
executada. Probe de geração real fica para uma política futura, opt-in, com
consentimento e limites próprios.

## Consequências

- providers instalados, mas não autenticados, ficam visíveis sem serem usados;
- a instalação padrão não consome tokens nem chama geração;
- o resultado pode ser auditado e reproduzido por `ralph-doctor --verify-providers`;
- providers sem diagnóstico seguro, como agy nesta versão, permanecem
  `unsupported` até que um contrato seja validado;
- cada adapter futuro precisa acrescentar fixture offline e manter o mesmo
  contrato, sem escrever estado global.

## Gatilho para revisitar

Adicionar probe de inferência real somente quando houver uma política explícita
de custo/consentimento, um limite de tempo, um prompt canário não mutante e
evidência de que o diagnóstico local não é suficiente para o provider.

## Responsável

Equipe do Ralph Method.

## Data

2026-08-07.
