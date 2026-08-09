# Incidente 0008 — concorrência no bloco controlado

## Sintoma

Antes do hardening, duas invocações de `bin/ralph-control run` podiam usar a
mesma `feature_key` e o mesmo `lease_token` ao mesmo tempo. As duas chegavam
ao provider e escreviam fatos no ledger. O resultado dependia da disputa entre
processos: trabalho duplicado, transições ambíguas e possibilidade de quebra da
cadeia `prev_event_hash`.

## Causa raiz

`workflow.lock` protegia apenas trechos curtos de leitura, claim e transição.
Ele não representava a exclusividade da execução longa do bloco, e a função
de append podia ser chamada fora de uma região explicitamente protegida. Ter
um lease válido identificava a sessão, mas não impedia uma segunda sessão de
reutilizar o mesmo lease antes do encerramento da primeira.

## Impacto

O control plane poderia iniciar duas execuções para uma única feature. Isso
violava a regra de uma feature por bloco, podia duplicar comandos do provider e
reduzia a confiabilidade do ledger como fonte de auditoria.

## Correção aplicada

- `bin/ralph-control` adquiriu um lock exclusivo por
  `sha256(workflow_id|feature_key)` durante todo o bloco controlado;
- a segunda execução falha de forma determinística com exit code `12`, antes
  de iniciar provider, comando ou nova transição;
- o estado e o lease são revalidados depois da aquisição do lock de execução;
- todo `appendEvent()` passa pelo `workflow.lock`, com reentrada segura para
  chamadas já protegidas;
- o lock de execução é local em `.git/ralph-control/executions/`, não é
  versionado e é liberado pelo sistema operacional se o processo morrer.

## Evidência

O teste de método primeiro reproduziu a falha com duas execuções concorrentes:
a segunda terminou com exit code `0`. Após a correção, a mesma fixture passou a
obter exit code `12`, uma única tentativa, um único comando e um único
`block.finished`; a verificação do ledger também permaneceu verde.

Comandos de prova:

```sh
bash scripts/test-ralph-method.sh
bash scripts/check-shell.sh
bash scripts/test-ralph.sh
```

## Prevenção

- não confiar apenas no lease para garantir exclusividade;
- manter a escrita do ledger centralizada na função protegida;
- revalidar estado e lease após qualquer espera por lock;
- tratar contenção como bloqueio auditável, e não como fallback silencioso;
- preservar testes de concorrência junto da regressão do método.

## Risco residual

Crash recovery, fencing após expiração de lease, reparo de ledger truncado e
concorrência entre workflows distintos ainda são etapas posteriores do
hardening v0.5.0. Esta correção impede a duplicidade focal por feature, mas não
é apresentada como conclusão de toda a máquina de recuperação.

## Rastreabilidade

- Decisão: [`ADR 0008`](../adr/0008-execucao-exclusiva-e-ledger-protegido.md)
- Implementação: [`bin/ralph-control`](../../bin/ralph-control)
- Regressão: [`scripts/test-ralph-method.sh`](../../scripts/test-ralph-method.sh)
