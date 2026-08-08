# ADR 0006 — Validação e promoção controlada da engine OpenCode

## Status

Proposta para execução na branch `feat/opencode-engine`.

## Contexto

O adapter OpenCode já executou uma fixture complexa pelo caminho controlado do
Ralph, mas essa prova usou `--no-verify` para medir o runner, o transporte, o
parser, a contenção de processo e o trace. O resultado correto foi
`awaiting_gates`, não `released`.

A promoção para `main` exige uma prova mais forte: revisão read-only efetiva,
teste em projeto real, recuperação de panes, regressão completa, curadoria,
revisão adversarial e validação pós-merge. Um caminho feliz isolado não prova
que o sistema é seguro para continuar automaticamente.

## Opções consideradas

### Promover após a fixture complexa

Rejeitada. A fixture comprova a execução real do adapter, mas não comprova a
política read-only, os cinco gates, o ambiente real ou a recuperação de pane.

### Executar somente smoke e testes portáteis

Rejeitada. Testes portáteis cobrem regressão do núcleo, mas não revelam
diferenças de permissões, processos, serviços, banco, runtime e feedback em um
projeto real.

### Validar em camadas, com panes injetadas, projeto real isolado e promoção
condicional

Escolhida. Cada camada tem uma saída objetiva, um bloqueio explícito e um
artefato numerado. A promoção só ocorre depois que todas as camadas passam e a
regressão pós-merge também fica verde.

## Decisão

Adotar o plano de
[`opencode-validation-promotion-plan.md`](../architecture/opencode-validation-promotion-plan.md)
com estas decisões irreversíveis:

1. a `main` nunca é usada como checkout de execução do teste de campo;
2. o revisor OpenCode precisa de política read-only efetiva e hash verificável;
3. toda pane bloqueia o avanço até possuir reprodução, causa, mitigação e
   verificação posterior;
4. após falhas repetidas sem progresso, o controlador entra em
   `recovery_required` e exige escalonamento explícito;
5. a promoção é uma decisão binária baseada em matriz de evidências, não em
   interpretação do modelo;
6. a regressão pós-merge é obrigatória antes da tag de versão.

## Consequências

### Positivas

- impede promoção baseada em uma única execução feliz;
- torna panes, hipóteses e correções auditáveis;
- comprova que o revisor não altera o checkout;
- separa fixture, projeto real, revisão e curadoria;
- preserva a `main` até o último passo;
- permite interromper ou escalar sem perder o contexto.

### Custos

- a validação exige mais de uma sessão e mais tempo de execução;
- o teste de campo depende de uma worktree e dos serviços reais do projeto;
- a política read-only precisa acompanhar mudanças no OpenCode;
- a decisão de promoção fica mais lenta quando há pane não reproduzível.

## Gatilho para revisitar

Revisitar este ADR quando o OpenCode alterar o contrato de permissões ou do
formato JSONL, quando um segundo provider exigir capacidades incompatíveis com
o contrato atual, ou quando a matriz de panes demonstrar que a contenção de
processos não é verificável no ambiente suportado.

## Responsável

Equipe do Ralph Method.

## Data

2026-08-08.
