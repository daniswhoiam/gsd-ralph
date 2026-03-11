# storage.sh -- JSON file storage layer
STORAGE_FILE="${TASKCTL_DATA:-.taskctl.json}"

storage_read_all() {
    if [[ -f "$STORAGE_FILE" ]] && [[ -s "$STORAGE_FILE" ]]; then
        jq '.' "$STORAGE_FILE"
    else
        echo '[]'
    fi
}

storage_add() {
    local description="$1"
    local priority="${2:-low}"
    local id
    id=$(storage_next_id)
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tasks
    tasks=$(storage_read_all)
    echo "$tasks" | jq --arg desc "$description" --arg id "$id" --arg ts "$timestamp" --arg pri "$priority" \
        '. + [{"id": ($id | tonumber), "description": $desc, "done": false, "created": $ts, "priority": $pri}]' \
        > "$STORAGE_FILE"
}

storage_next_id() {
    local max_id
    max_id=$(storage_read_all | jq '[.[].id] | max // 0')
    echo $((max_id + 1))
}
