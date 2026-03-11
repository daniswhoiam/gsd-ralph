#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TASKCTL_DATA="$TEST_DIR/.taskctl.json"
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../src" && pwd)"
    source "$SCRIPT_DIR/storage.sh"
    source "$SCRIPT_DIR/format.sh"
    source "$SCRIPT_DIR/commands/delete.sh"
    load '../../../tests/test_helper/bats-support/load'
    load '../../../tests/test_helper/bats-assert/load'
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "delete removes a task" {
    cat > "$TASKCTL_DATA" <<'JSON'
[
  {"id": 1, "description": "Task one", "done": false, "created": "2026-03-01T10:00:00Z"},
  {"id": 2, "description": "Task two", "done": false, "created": "2026-03-01T11:00:00Z"}
]
JSON
    run cmd_delete 1
    assert_success
    local count
    count=$(jq length "$TASKCTL_DATA")
    [[ "$count" -eq 1 ]]
    # Remaining task should be id=2
    local remaining_id
    remaining_id=$(jq -r '.[0].id' "$TASKCTL_DATA")
    [[ "$remaining_id" -eq 2 ]]
}

@test "delete nonexistent ID shows error" {
    cat > "$TASKCTL_DATA" <<'JSON'
[
  {"id": 1, "description": "Task one", "done": false, "created": "2026-03-01T10:00:00Z"}
]
JSON
    run cmd_delete 999
    assert_failure
    assert_output --partial "not found"
}

@test "delete preserves other tasks" {
    cat > "$TASKCTL_DATA" <<'JSON'
[
  {"id": 1, "description": "Task one", "done": false, "created": "2026-03-01T10:00:00Z"},
  {"id": 2, "description": "Task two", "done": true, "created": "2026-03-01T11:00:00Z"},
  {"id": 3, "description": "Task three", "done": false, "created": "2026-03-02T09:00:00Z"}
]
JSON
    run cmd_delete 2
    assert_success
    local count
    count=$(jq length "$TASKCTL_DATA")
    [[ "$count" -eq 2 ]]
    # Tasks 1 and 3 should remain
    local ids
    ids=$(jq -r '.[].id' "$TASKCTL_DATA")
    echo "$ids" | grep -q "1"
    echo "$ids" | grep -q "3"
}

@test "delete with no argument shows error" {
    run cmd_delete
    assert_failure
    assert_output --partial "ID required"
}
