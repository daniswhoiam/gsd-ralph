# commands/done.sh -- Mark a task as done
cmd_done() {
    local task_id="${1:-}"
    if [[ -z "$task_id" ]]; then
        echo "Error: task ID required" >&2
        exit 1
    fi
    local tasks
    tasks=$(storage_read_all)
    local updated
    updated=$(echo "$tasks" | jq --argjson idx "$task_id" \
        '.[$idx].done = true')
    echo "$updated" > "$STORAGE_FILE"
    echo "Task $task_id marked as done"
}
