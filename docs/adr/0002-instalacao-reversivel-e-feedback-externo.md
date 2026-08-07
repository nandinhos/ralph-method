# ADR 0002 — Instalação reversível e feedback para o orquestrador

## Status

Aceita.

## Contexto

O Ralph Method será acoplado a projetos diferentes e não pode presumir que o
usuário queira mantê-lo para sempre. A instalação precisa ser explícita,
idempotente, auditável e removível sem apagar código alterado pelo usuário,
workflow, histórico ou evidências.

Ao mesmo tempo, o loop interno precisa informar o orquestrador externo sobre
início, tentativas, gates, esperas, falhas e conclusão. Essa comunicação deve
servir à interação em tela, mas não pode introduzir uma segunda autoridade para
a máquina de estados.

## Opções consideradas

### Remover todos os caminhos conhecidos pelo nome

Rejeitada. Um arquivo pode ter sido alterado pelo usuário, pode pertencer a
outra ferramenta ou pode conter uma correção posterior. Remover por nome causa
perda de trabalho e não é auditável.

### Manter uma cópia global e apenas apontar o projeto para ela

Rejeitada. Cria dependência oculta do ambiente e permite que uma atualização
global mude a execução de um projeto sem que sua árvore local registre a
versão usada.

### Manifesto local com hashes e uninstall conservador

Escolhida. `ralph-init apply` grava ownership, versão e hashes. O uninstall
remove somente arquivos que ainda correspondem ao hash instalado; arquivos
modificados ficam preservados e aparecem no relatório.

Os perfis gerados apontam para o `scripts/ralph.sh` instalado no próprio
projeto, evitando dependência acidental de um caminho global do harness.

### Usar somente o hook como canal externo

Rejeitada. Hook é extensível e best-effort, mas não deve ser pré-requisito para
feedback nem fronteira de segurança. O loop publica um contrato JSONL próprio,
com stdout e callback opcionais; o hook continua dedicado à observabilidade.

## Decisão

O instalador oferece `plan`, `apply`, `uninstall` e `doctor`. O manifesto em
`.ralph/install-manifest.json` é a única base de ownership do uninstall. O
runtime operacional e as evidências permanecem fora da remoção.

O loop emite eventos conforme `schemas/feedback-event.schema.json` para
`.git/ralph-control/feedback/events.jsonl`. `RALPH_FEEDBACK_STDOUT=1` permite
que o orquestrador leia o progresso em tempo real, e
`RALPH_FEEDBACK_CMD=<executável>` oferece um callback com timeout. Qualquer
falha do consumidor é registrada como aviso e não muda gates, leases, estados
ou a seleção da próxima feature.

No caminho controlado, `ralph-control` força stdout de feedback por padrão e
retransmite somente as linhas prefixadas pelo contrato enquanto o processo
está vivo. Isso dá visibilidade imediata sem conceder autoridade ao texto
retransmitido.

Detalhes textuais publicados pelo loop recebem redaction de padrões óbvios de
token, senha e API key; prompts, respostas, credenciais e saídas integrais não
entram no evento.

## Consequências

- o usuário pode experimentar e retirar o Ralph sem perder o histórico do
  projeto;
- drift e conflitos são visíveis antes de qualquer remoção;
- o orquestrador externo recebe fatos suficientes para feedback de tela sem
  ganhar autoridade sobre o control plane;
- o arquivo JSONL cresce localmente e deve ser rotacionado pelo ambiente quando
  execuções muito longas exigirem saneamento;
- a interface de callback é local e síncrona por evento, portanto consumidores
  lentos são encerrados por timeout e não podem travar o loop.

## Gatilho para revisitar

Adicionar transporte remoto ou rotação automática quando houver requisito de
supervisão entre máquinas. Essa evolução deve preservar o JSONL local e não
transformar o consumidor externo em autoridade de transição.

## Responsável

Equipe do Ralph Method.

## Data

2026-08-07.
