# Relatório 0014 — regressão final da candidata v0.5.0

**Data:** 2026-08-09
**Versão:** `0.5.0`
**Branch:** `feat/ralph-hardening`
**Escopo:** control plane, instalação, memória, métricas e OpenCode real

## Resultado

| Bloco | Resultado | Evidência |
|---|---|---|
| CI portátil | verde | `bash scripts/ci-portable.sh` |
| Control plane | verde | concorrência, crash, fencing, ledger terminal/intermediário, 163 asserts do `test-ralph` |
| Handoff e memória | verde | curadoria idempotente e recuperação seletiva |
| Métricas | verde | JSON/Markdown read-only, filtros, duração e ledger corrompido |
| Instalação/reprodução | verde | bundle Git independente, doctor, uninstall e ownership |
| Adversarial OpenCode | verde | `OPENCODE_ADVERSARIAL_TEST_OK`, 97s, `opencode/big-pickle` |
| Campo OpenCode | verde | `FIELD_TEST_OK`, 118s, `FEATURE_CHECK_OK` |
| Sanitização UTF-8 | verde | saída deliberada `0xFF` e ledger verificável |

## Campo real

O teste de campo validou uma feature complexa em fixture isolada com o adapter
OpenCode real. O resultado confirmou:

- implementação e revisão read-only como delegações distintas;
- política externa verificada;
- cinco fontes de evidência do runner e trace importado no controlador;
- oráculo externo `FEATURE_CHECK_OK`;
- hash dos arquivos protegidos preservado;
- processo terminado e contenção `pid_namespace` observada.

## Incidente resolvido durante o fechamento

Uma primeira repetição do campo encontrou erro de serialização por byte UTF-8
inválido após os gates. O caso foi isolado, documentado no
[`incidente 0009`](../incidents/0009-saida-provider-utf8-invalida.md), corrigido
no control plane/parser e reproduzido com teste negativo antes da repetição
verde do campo.

## Decisão

A regressão técnica da candidata está verde e não há bloqueio funcional
conhecido para revisão de promoção. A branch ainda não foi promovida, tagueada
ou publicada; a decisão de `main` exige revisão final do diff e confirmação
explícita do proprietário do repositório.

## Limites

Hermes e agy continuam fora do escopo de execução. A Fase 5 de melhorias de
DX/escala permanece opcional e não é requisito para a promoção desta linha,
pois nenhum gatilho de extração ou benefício comprovado justifica ampliar o
núcleo agora.
