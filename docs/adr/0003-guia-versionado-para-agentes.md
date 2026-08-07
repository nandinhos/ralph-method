# ADR 0003 — Guia operacional versionado para agentes de IA

## Status

Aceita.

## Contexto

O Ralph Method será instalado em projetos e harnesses diferentes. A
implementação possui control plane, providers, gates, feedback, recuperação e
desinstalação segura. Sem um guia operacional único, cada agente precisa
reconstruir o protocolo a partir de comandos espalhados e pode confundir
observabilidade com autoridade.

Além disso, o guia precisa acompanhar as mudanças do framework. Um documento
de instalação que fique preso a uma versão anterior é uma fonte de regressão
operacional.

## Opções consideradas

### Deixar o conhecimento somente no `AGENTS.md`

Rejeitada. `AGENTS.md` deve conter regras de trabalho do repositório; o fluxo
completo de instalação, providers, comunicação, gates e desinstalação ficaria
grande e difícil de reutilizar.

### Manter um guia externo ao repositório

Rejeitada. O agente poderia receber uma versão diferente daquela realmente
instalada e não haveria uma prova local de compatibilidade.

### Manter `docs/AGENT_GUIDE.md` versionado e checado

Escolhida. O guia fica junto do código e do contrato, declara
`method_version`, e `scripts/check-doc-sync.sh` compara esse valor com
`VERSION` e `docs/STATUS.md`.

## Decisão

`docs/AGENT_GUIDE.md` é o manual operacional para agentes de IA. Ele define:

- ordem de leitura e precedência das instruções;
- papéis, autoridade e limites dos agentes;
- pacote de contexto e identidade de execução;
- comunicação via `ralph-control`, `ralph-trace` e feedback;
- instalação, configuração, execução, monitoramento e recuperação;
- gates, evidências, handoff, atualização e desinstalação;
- checklist de encerramento;
- obrigação de sincronização por versão.

O guia não substitui `AGENTS.md`, `docs/STATUS.md`, arquitetura, ADRs ou a
solicitação atual do usuário. Ele explica como aplicar essas fontes no ciclo
operacional do Ralph.

## Consequências

- agentes novos têm um caminho determinístico para operar o método;
- o orquestrador recebe identificadores suficientes para correlacionar
  `workflow_id`, `feature_key`, `attempt` e `run_id`;
- a publicação de uma versão com guia desatualizado falha no check documental;
- alterações futuras precisam manter o guia enxuto e atualizar somente as
  seções afetadas;
- o guia aumenta a superfície documental, mas reduz decisões implícitas e
  divergência entre harnesses.

## Gatilho para revisitar

Revisar este ADR se o framework passar a ter múltiplos protocolos incompatíveis
por provider ou se o guia precisar ser gerado automaticamente a partir de
schemas sem perder explicação operacional.

## Responsável

Equipe do Ralph Method.

## Data

2026-08-07.
