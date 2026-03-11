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
    # Check for --sort priority flag
    if [[ "${1:-}" = "--sort" ]] && [[ "${2:-}" = "priority" ]]; then
        # Sort by priority: high=1, medium=2, low=3
        tasks=$(echo "$tasks" | jq '
            sort_by(
                if .priority == "high" then 1
                elif .priority == "medium" then 2
                else 3
                end
            )
        ')
        format_task_list "$tasks" "all"
        return
    fi
    local filter="${1:-all}"
    case "$filter" in
        --done)    format_task_list "$tasks" "done" ;;
        --pending) format_task_list "$tasks" "pending" ;;
        *)         format_task_list "$tasks" "all" ;;
    esac
}
