# commands/delete.sh -- Delete a task by ID
cmd_delete() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Error: task ID required" >&2
        exit 1
    fi
    local tasks
    tasks=$(storage_read_all)
    local found
    found=$(echo "$tasks" | jq --argjson id "$task_id" '[.[] | select(.id == $id)] | length')
    if [[ "$found" -eq 0 ]]; then
        echo "Error: task $task_id not found" >&2
        exit 1
    fi
    local updated
    updated=$(echo "$tasks" | jq --argjson id "$task_id" \
        '[.[] | select(.id != $id)]')
    echo "$updated" > "$STORAGE_FILE"
    echo "Task $task_id deleted"
}
