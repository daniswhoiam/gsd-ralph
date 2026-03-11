# format.sh -- Output formatting (stub, replaced in Task 2)
format_task_list() {
    local tasks="$1"
    local filter="${2:-all}"
    local total
    total=$(echo "$tasks" | jq length)
    local i=0
    while [ "$i" -lt "$total" ]; do
        local id
        id=$(echo "$tasks" | jq -r ".[$i].id")
        local desc
        desc=$(echo "$tasks" | jq -r ".[$i].description")
        local done_val
        done_val=$(echo "$tasks" | jq -r ".[$i].done")
        local created
        created=$(echo "$tasks" | jq -r ".[$i].created")
        local marker=" "
        if [ "$done_val" = "true" ]; then
            marker="x"
        fi
        if [ "$filter" = "done" ] && [ "$done_val" = "true" ]; then
            printf "[%s] #%s %s (%s)\n" "$marker" "$id" "$desc" "$created"
        elif [ "$filter" = "pending" ] && [ "$done_val" = "false" ]; then
            printf "[%s] #%s %s (%s)\n" "$marker" "$id" "$desc" "$created"
        elif [ "$filter" = "all" ]; then
            printf "[%s] #%s %s (%s)\n" "$marker" "$id" "$desc" "$created"
        fi
        i=$((i + 1))
    done
}
