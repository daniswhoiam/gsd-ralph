# commands/done.sh -- Mark a task as done
cmd_done() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Error: task ID required" >&2
        exit 1
    fi
    local tasks
    tasks=$(storage_read_all)
    # Look up by .id field, not array index
    local found
    found=$(echo "$tasks" | jq --argjson id "$task_id" '[.[] | select(.id == $id)] | length')
    if [[ "$found" -eq 0 ]]; then
        echo "Error: task $task_id not found" >&2
        exit 1
    fi
    local updated
    updated=$(echo "$tasks" | jq --argjson id "$task_id" \
        'map(if .id == $id then .done = true else . end)')
    echo "$updated" > "$STORAGE_FILE"
    echo "Task $task_id marked as done"
}
