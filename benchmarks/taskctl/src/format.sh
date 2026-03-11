# format.sh -- Output formatting

format_task_list() {
    local tasks="$1"
    local filter="${2:-all}"
    local cnt=0
    local total=0
    local done_cnt=0
    local t=""
    local d=""
    local s=""
    total=$(echo $tasks | jq length)
    local i=0
    while [ $i -lt $total ]; do
        t=$(echo $tasks | jq -r ".[$i].description")
        d=$(echo $tasks | jq -r ".[$i].done")
        s=$(echo $tasks | jq -r ".[$i].created")
        local id=$(echo $tasks | jq -r ".[$i].id")
        if [ "$filter" = "done" ] && [ "$d" = "true" ]; then
            printf "[%s] #%s %s (%s)\n" "x" "$id" "$t" "$s"
            cnt=$((cnt + 1))
        elif [ "$filter" = "pending" ] && [ "$d" = "false" ]; then
            printf "[%s] #%s %s (%s)\n" " " "$id" "$t" "$s"
            cnt=$((cnt + 1))
        elif [ "$filter" = "all" ]; then
            if [ "$d" = "true" ]; then
                printf "[%s] #%s %s (%s)\n" "x" "$id" "$t" "$s"
            else
                printf "[%s] #%s %s (%s)\n" " " "$id" "$t" "$s"
            fi
            cnt=$((cnt + 1))
        fi
        i=$((i + 1))
        done_cnt=$((done_cnt + 1))
    done
    if [ "$filter" = "done" ]; then
        echo ""
        echo "$cnt done tasks"
    elif [ "$filter" = "pending" ]; then
        echo ""
        echo "$cnt pending tasks"
    else
        echo ""
        echo "$cnt total tasks"
    fi
}

format_single_task() {
    local tasks="$1"
    local task_id="$2"
    local total=$(echo $tasks | jq length)
    local i=0
    while [ $i -lt $total ]; do
        local id=$(echo $tasks | jq -r ".[$i].id")
        if [ "$id" = "$task_id" ]; then
            local t=$(echo $tasks | jq -r ".[$i].description")
            local d=$(echo $tasks | jq -r ".[$i].done")
            local s=$(echo $tasks | jq -r ".[$i].created")
            if [ "$d" = "true" ]; then
                printf "[x] #%s %s (%s)\n" "$id" "$t" "$s"
            else
                printf "[ ] #%s %s (%s)\n" "$id" "$t" "$s"
            fi
            return 0
        fi
        i=$((i + 1))
    done
    echo "Task $task_id not found"
    return 1
}
