# format.sh -- Output formatting

# Helper: print a single formatted task line
_format_task_line() {
    local id="$1"
    local description="$2"
    local done="$3"
    local created="$4"
    local marker=" "
    if [[ "$done" = "true" ]]; then
        marker="x"
    fi
    printf "[%s] #%s %s (%s)\n" "$marker" "$id" "$description" "$created"
}

format_task_list() {
    local tasks="$1"
    local filter="${2:-all}"
    local cnt=0
    local total
    total=$(echo "$tasks" | jq length)
    local i=0
    while [[ "$i" -lt "$total" ]]; do
        local t
        t=$(echo "$tasks" | jq -r ".[$i].description")
        local d
        d=$(echo "$tasks" | jq -r ".[$i].done")
        local s
        s=$(echo "$tasks" | jq -r ".[$i].created")
        local id
        id=$(echo "$tasks" | jq -r ".[$i].id")
        if [[ "$filter" = "done" ]] && [[ "$d" = "true" ]]; then
            _format_task_line "$id" "$t" "$d" "$s"
            cnt=$((cnt + 1))
        elif [[ "$filter" = "pending" ]] && [[ "$d" = "false" ]]; then
            _format_task_line "$id" "$t" "$d" "$s"
            cnt=$((cnt + 1))
        elif [[ "$filter" = "all" ]]; then
            _format_task_line "$id" "$t" "$d" "$s"
            cnt=$((cnt + 1))
        fi
        i=$((i + 1))
    done
    echo ""
    if [[ "$filter" = "done" ]]; then
        echo "$cnt done tasks"
    elif [[ "$filter" = "pending" ]]; then
        echo "$cnt pending tasks"
    else
        echo "$cnt total tasks"
    fi
}

format_single_task() {
    local tasks="$1"
    local task_id="$2"
    local total
    total=$(echo "$tasks" | jq length)
    local i=0
    while [[ "$i" -lt "$total" ]]; do
        local id
        id=$(echo "$tasks" | jq -r ".[$i].id")
        if [[ "$id" = "$task_id" ]]; then
            local t
            t=$(echo "$tasks" | jq -r ".[$i].description")
            local d
            d=$(echo "$tasks" | jq -r ".[$i].done")
            local s
            s=$(echo "$tasks" | jq -r ".[$i].created")
            _format_task_line "$id" "$t" "$d" "$s"
            return 0
        fi
        i=$((i + 1))
    done
    echo "Task $task_id not found"
    return 1
}
