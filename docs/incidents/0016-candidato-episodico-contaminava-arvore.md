# Incidente 0016 — Candidato episódico contaminava a árvore de trabalho

## Sintoma

Após uma feature ser liberada com `knowledge_policy.mode: non_blocking`, o
controlador criava `.ralph/knowledge-candidates/CUR-....json`. O arquivo era
útil para a curadoria, mas aparecia como não rastreado no checkout e fazia o
`claim` da feature seguinte reprovar por `working tree suja`. O portão oficial
também identificou que `observe` aceitava detalhe sensível depois de deixar de
escrever no ledger.

## Causa raiz

O cache episódico tinha ownership local, mas não havia sido registrado no
exclusor privado do Git. A política não bloqueante permitia avançar a fila,
mas o próprio mecanismo de limpeza do checkout tratava o cache como mudança de
produto. Em paralelo, a versão não mutante de `observe` retornava antes de
passar `event` e `detail` pelo sanitizador.

## Correção

Ao materializar o primeiro candidato, o controlador adiciona a entrada
relativa `/.ralph/knowledge-candidates/` a `.git/info/exclude`. O cache continua
no projeto para permitir retenção, rejeição, descarte e recuperação seletiva,
mas não é incluído em commits de feature nem interfere na máquina de estados.

`observe` permanece sem alterar ledger, workflow, gates ou leases. Ele exige
contexto mínimo e sanitiza os campos recebidos antes de responder; tokens,
senhas e padrões equivalentes continuam sendo rejeitados.

## Evidência

- `bash scripts/test-ralph-knowledge.sh` — candidato pendente, árvore limpa e
  exclusão local comprovada.
- `tests/Unit/RalphControlTest.php` — supervisor completo e rejeição de
  segredo em `observe`.
- `bin/check` no projeto-alvo — reprovações originais reproduziram o sintoma
  antes da reaplicação corrigida.

## Risco residual

O arquivo `.git/info/exclude` é local ao clone e não é versionado. Um usuário
que remova essa entrada verá novamente os candidatos como não rastreados, mas o
controlador a recriará na próxima materialização.

## Prevenção

Todo artefato episódico local deve declarar explicitamente seu ownership e
ficar fora da árvore de produto, do Commit B e dos gates de qualidade.
