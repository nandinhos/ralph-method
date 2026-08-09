# Relatório 0007 — certificação e promoção local da v0.4.0

**Data:** 2026-08-08
**Projeto:** Ralph Method
**Branch de origem:** `feat/opencode-engine`
**Commit candidato:** `c6a7f74995bc5f93aefe51212b3ba1e949788baf`
**Destino:** `main`
**Modo de promoção:** `git merge --ff-only` local
**Push remoto:** não realizado

## Decisão

A engine OpenCode `v0.4.0` foi considerada apta e promovida localmente para
`main`. A promoção ocorreu somente depois da regressão determinística, da
prova externa de política, da revisão independente bounded, do probe
adversarial real e do teste de campo com os cinco gates.

## Evidências finais

| Verificação | Resultado | Evidência objetiva |
|---|---:|---|
| Prova externa read-only | verde | `policy.php check` exit `0`; hash da política e da superfície estável preservados |
| Revisão independente bounded | verde | uma sessão, dois `step_finish`, oito leituras, `FINAL_REVIEW_VERDICT: PASS` |
| Shell e documentação | verde | `check-shell.sh`, `check-doc-sync.sh` e `git diff --check` exit `0` |
| Adapter e política | verde | `test-opencode-adapter.sh` e `test-opencode-policy.sh` exit `0` |
| Instalação e comunicação | verde | installation, feedback, provider-readiness e smoke do método exit `0` |
| Regressão do loop | verde | `test-ralph.sh`: `TODOS VERDES: 163 asserts` |
| Probe adversarial real | verde | `OPENCODE_ADVERSARIAL_TEST_OK`, uma sessão, hash estável, 61s, modelo `deepseek-v4-flash-free` |
| Teste de campo real | verde | `FIELD_TEST_OK`, 136s, `FEATURE_CHECK_OK`, trace, processo contido e cinco gates |

## Escopo consolidado

- `bin/ralph-control` continua sendo a autoridade exclusiva de estado,
  leases, fencing, gates, recuperação e avanço.
- `bin/ralph-block` executa uma feature por bloco e não escolhe a próxima.
- O hook observa e emite eventos; não promove estado.
- O `ralph-trace` registra provider, modelo, sessão e delegações sem inferência
  silenciosa.
- O adapter OpenCode valida sessão única, aceita múltiplos `step_finish` da
  mesma sessão e rejeita sessões divergentes.
- A revisão read-only exige prova externa, política revalidada e superfície
  estável preservada.
- Instalação, idempotência, ownership, desinstalação e preservação de arquivos
  do usuário continuam cobertas.

## Falha operacional mitigada

A revisão ampla exploratória e uma tentativa com `big-pickle` expiraram sem
veredicto. Isso não foi convertido em aprovação. A causa, a evidência e a
mitigação bounded estão registradas em
[`docs/incidents/0007-timeout-revisao-ampla-release.md`](../incidents/0007-timeout-revisao-ampla-release.md).

## Próximos limites conhecidos na data da promoção

Esta promoção encerrou a maturação do adapter OpenCode nesta versão. Na data
do relatório, permaneciam fora do escopo imediato o adapter Hermes, o adapter
agy, contratos dedicados para Codex/Claude e a regressão multiprovider
completa. A regressão dos três harnesses fechados foi concluída posteriormente
no relatório
[`0009-regressao-multiprovider.md`](0009-regressao-multiprovider.md). Hermes e
agy continuam adiados sem prioridade no backlog atual.
