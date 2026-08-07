#!/usr/bin/env bash

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec "$REPO/bin/ralph-knowledge" "$@"
