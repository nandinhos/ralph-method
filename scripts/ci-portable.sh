#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Esta lista é a fronteira oficial da CI sem credenciais. Provas que exigem
# provider real permanecem explícitas e fora deste job, para não transformar
# autenticação do desenvolvedor em dependência oculta da qualidade do método.
checks=(
  scripts/check-doc-sync.sh
  scripts/check-shell.sh
  scripts/test-installation.sh
  scripts/test-reproducibility.sh
  scripts/test-feedback.sh
  scripts/test-provider-readiness.sh
  scripts/test-multiprovider.sh
  scripts/test-ralph-method.sh
  scripts/test-ralph-knowledge.sh
  scripts/test-ralph-metrics.sh
  scripts/test-ralph.sh
  scripts/test-opencode-policy.sh
  scripts/test-opencode-adapter.sh
)

for check in "${checks[@]}"; do
  printf '\n== CI portátil: %s ==\n' "$check"
  bash "$ROOT/$check"
done

printf '\nOK: CI portátil concluída sem credenciais ou geração real.\n'
