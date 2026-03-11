# commands/list.sh -- List tasks
cmd_list() {
    local tasks
    tasks=$(storage_read_all)
    local count
    count=$(echo "$tasks" | jq length)
    if [[ "$count" -eq 0 ]]; then
        echo "No tasks found"
        return
    fi
    local filter="${1:-all}"
    case "$filter" in
        --done)    format_task_list "$tasks" "done" ;;
        --pending) format_task_list "$tasks" "pending" ;;
        *)         format_task_list "$tasks" "all" ;;
    esac
}
