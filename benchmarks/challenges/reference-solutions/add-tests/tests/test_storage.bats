#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TASKCTL_DATA="$TEST_DIR/.taskctl.json"
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../src" && pwd)"
    source "$SCRIPT_DIR/storage.sh"
    load '../../../tests/test_helper/bats-support/load'
    load '../../../tests/test_helper/bats-assert/load'
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "storage_read_all returns empty array for missing file" {
    run storage_read_all
    assert_success
    assert_output "[]"
}

@test "storage_read_all returns empty array for empty file" {
    touch "$TASKCTL_DATA"
    run storage_read_all
    assert_success
    assert_output "[]"
}

@test "storage_add creates task with correct fields" {
    storage_add "Test task"
    local count
    count=$(jq length "$TASKCTL_DATA")
    [[ "$count" -eq 1 ]]
    local desc
    desc=$(jq -r '.[0].description' "$TASKCTL_DATA")
    [[ "$desc" = "Test task" ]]
    local done_val
    done_val=$(jq -r '.[0].done' "$TASKCTL_DATA")
    [[ "$done_val" = "false" ]]
    local id
    id=$(jq -r '.[0].id' "$TASKCTL_DATA")
    [[ "$id" -eq 1 ]]
}

@test "storage_next_id returns max plus one" {
    cat > "$TASKCTL_DATA" <<'JSON'
[
  {"id": 1, "description": "First", "done": false, "created": "2026-03-01T10:00:00Z"},
  {"id": 5, "description": "Fifth", "done": false, "created": "2026-03-01T11:00:00Z"}
]
JSON
    local next
    next=$(storage_next_id)
    [[ "$next" -eq 6 ]]
}

@test "storage_add multiple tasks increments IDs" {
    storage_add "First task"
    storage_add "Second task"
    local id1
    id1=$(jq -r '.[0].id' "$TASKCTL_DATA")
    local id2
    id2=$(jq -r '.[1].id' "$TASKCTL_DATA")
    [[ "$id1" -eq 1 ]]
    [[ "$id2" -eq 2 ]]
}

@test "storage_read_all after add returns added items" {
    storage_add "My task"
    local tasks
    tasks=$(storage_read_all)
    local count
    count=$(echo "$tasks" | jq length)
    [[ "$count" -eq 1 ]]
    local desc
    desc=$(echo "$tasks" | jq -r '.[0].description')
    [[ "$desc" = "My task" ]]
}
