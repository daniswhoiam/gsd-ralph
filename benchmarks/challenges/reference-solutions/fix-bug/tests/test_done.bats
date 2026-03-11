#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TASKCTL_DATA="$TEST_DIR/.taskctl.json"
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../src" && pwd)"
    source "$SCRIPT_DIR/storage.sh"
    source "$SCRIPT_DIR/format.sh"
    source "$SCRIPT_DIR/commands/done.sh"
    load '../../../tests/test_helper/bats-support/load'
    load '../../../tests/test_helper/bats-assert/load'
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "done marks correct task by ID" {
    # Seed with two tasks
    cat > "$TASKCTL_DATA" <<'JSON'
[
  {"id": 1, "description": "Task one", "done": false, "created": "2026-03-01T10:00:00Z"},
  {"id": 2, "description": "Task two", "done": false, "created": "2026-03-01T11:00:00Z"}
]
JSON
    run cmd_done 2
    assert_success
    # Task 2 should be done
    local task2_done
    task2_done=$(jq -r '.[] | select(.id == 2) | .done' "$TASKCTL_DATA")
    [[ "$task2_done" = "true" ]]
    # Task 1 should still be not done
    local task1_done
    task1_done=$(jq -r '.[] | select(.id == 1) | .done' "$TASKCTL_DATA")
    [[ "$task1_done" = "false" ]]
}

@test "done on nonexistent ID shows error" {
    cat > "$TASKCTL_DATA" <<'JSON'
[
  {"id": 1, "description": "Task one", "done": false, "created": "2026-03-01T10:00:00Z"}
]
JSON
    run cmd_done 999
    assert_failure
    assert_output --partial "not found"
}

@test "done with no argument shows error" {
    run cmd_done
    assert_failure
    assert_output --partial "ID required"
}
