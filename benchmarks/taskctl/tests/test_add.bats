#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TASKCTL_DATA="$TEST_DIR/.taskctl.json"
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../src" && pwd)"
    source "$SCRIPT_DIR/storage.sh"
    source "$SCRIPT_DIR/format.sh"
    source "$SCRIPT_DIR/commands/add.sh"
    load '../../../tests/test_helper/bats-support/load'
    load '../../../tests/test_helper/bats-assert/load'
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "add creates a new task" {
    run cmd_add "Buy milk"
    assert_success
    local count
    count=$(jq length "$TASKCTL_DATA")
    [[ "$count" -eq 1 ]]
}

@test "add stores correct description" {
    run cmd_add "Buy milk"
    assert_success
    local desc
    desc=$(jq -r '.[0].description' "$TASKCTL_DATA")
    [[ "$desc" = "Buy milk" ]]
}

@test "add multiple tasks increments IDs" {
    run cmd_add "First task"
    assert_success
    run cmd_add "Second task"
    assert_success
    local id1
    id1=$(jq -r '.[0].id' "$TASKCTL_DATA")
    local id2
    id2=$(jq -r '.[1].id' "$TASKCTL_DATA")
    [[ "$id1" -eq 1 ]]
    [[ "$id2" -eq 2 ]]
}

@test "add with special characters" {
    run cmd_add "Task with 'quotes' & symbols"
    assert_success
    local desc
    desc=$(jq -r '.[0].description' "$TASKCTL_DATA")
    [[ "$desc" = "Task with 'quotes' & symbols" ]]
}
