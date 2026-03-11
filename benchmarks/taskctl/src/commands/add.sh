# commands/add.sh -- Add a task
cmd_add() {
    if [[ $# -eq 0 ]]; then
        echo "Error: task description required" >&2
        exit 1
    fi
    local description="$*"
    storage_add "$description"
    local id
    id=$(storage_read_all | jq '.[length - 1].id')
    echo "Added task $id: $description"
}
