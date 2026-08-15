# RPT-2026-0063 — Incidentes de FEATURE-095-AGY-ADAPTER

- Handoff: HND-2026-0004

Incidentes sanitizados registrados nesta tentativa:

- `--mode plan` não garante read-only: prova controlada executou
  `write_to_file` no scratch global da CLI; o canário foi removido após a
  inspeção. Fronteira preventiva passa a ser o namespace allowlisted do
  `bwrap`; `plan` e `--sandbox` são somente defesa em profundidade.
- Primeira prova de campo ocultou `repo-root` sob `/tmp` porque o `tmpfs /tmp`
  era montado depois do bind do projeto; a ordem foi invertida e ganhou
  regressão explícita.
- Review adversarial reprovou superfícies de verify mutáveis, canonicalização
  semântica fail-open e validação insuficiente de identidade/fallback no
  controlador; correções aplicadas e promoção permaneceu pendente.
- `test-reproducibility.sh` usava somente `git archive HEAD` e não exercitava
  arquivos novos pré-commit; o bundle passou a sobrepor mudanças versionáveis
  do checkout.
