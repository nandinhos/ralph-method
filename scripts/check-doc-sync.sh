#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
GUIDE_FILE="$ROOT/docs/AGENT_GUIDE.md"

version="$(tr -d '[:space:]' < "$VERSION_FILE")"
guide_version="$(sed -n 's/^- method_version: //p' "$GUIDE_FILE" | head -1)"

if [ -z "$version" ] || [ -z "$guide_version" ]; then
  printf 'FALHA: VERSION ou method_version do guia está ausente.\n' >&2
  exit 1
fi

if [ "$version" != "$guide_version" ]; then
  printf 'FALHA: guia desatualizado (VERSION=%s, guia=%s).\n' "$version" "$guide_version" >&2
  exit 1
fi

if ! grep -q "A versão .*\`$version\`" "$ROOT/docs/STATUS.md"; then
  printf 'FALHA: docs/STATUS.md não referencia a versão %s.\n' "$version" >&2
  exit 1
fi

printf 'OK: guia de agente sincronizado com Ralph Method %s.\n' "$version"
