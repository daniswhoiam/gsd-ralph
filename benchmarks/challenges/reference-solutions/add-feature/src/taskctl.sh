#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/storage.sh"
source "$SCRIPT_DIR/format.sh"

case "${1:-}" in
    add)    shift; source "$SCRIPT_DIR/commands/add.sh"; cmd_add "$@" ;;
    list)   shift; source "$SCRIPT_DIR/commands/list.sh"; cmd_list "$@" ;;
    done)   shift; source "$SCRIPT_DIR/commands/done.sh"; cmd_done "$@" ;;
    delete) shift; source "$SCRIPT_DIR/commands/delete.sh"; cmd_delete "$@" ;;
    *)      echo "Usage: taskctl {add|list|done|delete} [args]"; exit 1 ;;
esac
