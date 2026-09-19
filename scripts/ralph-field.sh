#!/usr/bin/env bash
#
# ralph-field.sh — gerenciador canônico de campos de prova e worktrees isoladas.
#
# Permite criar, listar e destruir ambientes isolados de teste e prova de fogo
# sem poluir a raiz do repositório principal, centralizando tudo em .ralph/fields/.
#
# Uso:
#   bash scripts/ralph-field.sh create <nome> [--branch <branch>] [--clone]
#   bash scripts/ralph-field.sh list
#   bash scripts/ralph-field.sh destroy <nome|--all>

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIELDS_DIR="$ROOT/.ralph/fields"

usage() {
  sed -n '3,11p' "$0" | sed 's/^#//; s/^ //'
  exit 0
}

command="${1:-}"
shift || true

case "$command" in
  create)
    NAME="${1:-}"
    if [ -z "$NAME" ]; then
      echo "ERRO: Nome do campo não especificado." >&2
      echo "Uso: bash scripts/ralph-field.sh create <nome> [--branch <branch>] [--clone]" >&2
      exit 2
    fi
    shift || true

    BRANCH=""
    MODE="worktree"

    while [ $# -gt 0 ]; do
      case "$1" in
        --branch)
          BRANCH="$2"
          shift 2
          ;;
        --branch=*)
          BRANCH="${1#*=}"
          shift
          ;;
        --clone)
          MODE="clone"
          shift
          ;;
        *)
          echo "Opção desconhecida: $1" >&2
          exit 2
          ;;
      esac
    done

    DEST="$FIELDS_DIR/$NAME"
    if [ -e "$DEST" ]; then
      echo "ERRO: Campo já existe em $DEST" >&2
      exit 1
    fi

    mkdir -p "$FIELDS_DIR"

    if [ "$MODE" = "clone" ]; then
      echo "[ralph-field] Criando clone dedicado em $DEST..."
      git clone "$ROOT" "$DEST"
      if [ -n "$BRANCH" ]; then
        git -C "$DEST" checkout "$BRANCH" 2>/dev/null || git -C "$DEST" checkout -b "$BRANCH"
      fi
    else
      echo "[ralph-field] Criando git worktree em $DEST..."
      if [ -n "$BRANCH" ]; then
        git -C "$ROOT" worktree add -b "field-$NAME" "$DEST" "$BRANCH"
      else
        git -C "$ROOT" worktree add "$DEST" HEAD
      fi
    fi

    mkdir -p "$DEST/.ralph"
    echo "[ralph-field] Campo '$NAME' inicializado com sucesso em $DEST"
    echo "[ralph-field] Para supervisionar este campo:"
    echo "  bash scripts/ralph-supervise.sh --target-dir \"$DEST\""
    ;;

  list)
    echo "================================================================================"
    echo " Ralph Method — Campos de Prova Ativos (.ralph/fields/)"
    echo "================================================================================"
    if [ ! -d "$FIELDS_DIR" ] || [ -z "$(ls -A "$FIELDS_DIR" 2>/dev/null)" ]; then
      echo " Nenhum campo de prova ativo encontrado."
      echo "================================================================================"
      exit 0
    fi

    for d in "$FIELDS_DIR"/*; do
      if [ -d "$d" ]; then
        name="$(basename "$d")"
        branch="$(git -C "$d" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'desconhecido')"
        commit="$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo 'n/a')"
        echo " - Campo:  $name"
        echo "   Local:  $d"
        echo "   Branch: $branch ($commit)"
        echo
      fi
    done
    echo "================================================================================"
    ;;

  destroy)
    TARGET_NAME="${1:-}"
    if [ -z "$TARGET_NAME" ]; then
      echo "ERRO: Especifique o nome do campo a ser destruído ou --all." >&2
      exit 2
    fi

    if [ "$TARGET_NAME" = "--all" ]; then
      if [ -d "$FIELDS_DIR" ]; then
        for d in "$FIELDS_DIR"/*; do
          if [ -d "$d" ]; then
            name="$(basename "$d")"
            echo "[ralph-field] Destruindo campo '$name'..."
            git -C "$ROOT" worktree remove --force "$d" 2>/dev/null || rm -rf "$d"
          fi
        done
        echo "[ralph-field] Todos os campos foram removidos com sucesso."
      fi
    else
      DEST="$FIELDS_DIR/$TARGET_NAME"
      if [ ! -e "$DEST" ]; then
        echo "ERRO: Campo '$TARGET_NAME' não encontrado em $DEST" >&2
        exit 1
      fi
      echo "[ralph-field] Destruindo campo '$TARGET_NAME'..."
      git -C "$ROOT" worktree remove --force "$DEST" 2>/dev/null || rm -rf "$DEST"
      echo "[ralph-field] Campo '$TARGET_NAME' destruído com sucesso."
    fi
    ;;

  -h|--help|help)
    usage
    ;;

  *)
    echo "Comando desconhecido: $command" >&2
    usage
    ;;
esac
