#!/usr/bin/env bash

set -euo pipefail

RALPH_ROOT="$(cd "$(dirname "$0")" && pwd)"
cp "$RALPH_ROOT/ralph.sh.upstream" "$RALPH_ROOT/ralph.sh"
patch -p1 < "$RALPH_ROOT/ralph.patch"
