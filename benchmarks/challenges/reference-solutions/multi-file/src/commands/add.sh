# commands/add.sh -- Add a task
cmd_add() {
    local priority="low"
    if [[ "${1:-}" = "--priority" ]]; then
        shift
        priority="${1:-}"
        shift
        # Validate priority
        case "$priority" in
            low|medium|high) ;;
            *) echo "Error: invalid priority '$priority' (must be low, medium, or high)" >&2; exit 1 ;;
        esac
    fi
    if [[ $# -eq 0 ]]; then
        echo "Error: task description required" >&2
        exit 1
    fi
    local description="$*"
    storage_add "$description" "$priority"
    local id
    id=$(storage_read_all | jq '.[length - 1].id')
    echo "Added task $id: $description"
}
