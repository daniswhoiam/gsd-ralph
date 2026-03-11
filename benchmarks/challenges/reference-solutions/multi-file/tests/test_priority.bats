#!/usr/bin/env bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TASKCTL_DATA="$TEST_DIR/.taskctl.json"
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../src" && pwd)"
    source "$SCRIPT_DIR/storage.sh"
    source "$SCRIPT_DIR/format.sh"
    source "$SCRIPT_DIR/commands/add.sh"
    source "$SCRIPT_DIR/commands/list.sh"
    load '../../../tests/test_helper/bats-support/load'
    load '../../../tests/test_helper/bats-assert/load'
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "add with --priority stores priority" {
    run cmd_add --priority high "Urgent task"
    assert_success
    local priority
    priority=$(jq -r '.[0].priority' "$TASKCTL_DATA")
    [[ "$priority" = "high" ]]
}

@test "add without --priority defaults to low" {
    run cmd_add "Normal task"
    assert_success
    local priority
    priority=$(jq -r '.[0].priority' "$TASKCTL_DATA")
    [[ "$priority" = "low" ]]
}

@test "list --sort priority orders correctly" {
    cmd_add --priority low "Low task"
    cmd_add --priority high "High task"
    cmd_add --priority medium "Medium task"
    run cmd_list --sort priority
    assert_success
    # First task in output should be the high priority one
    local first_line
    first_line=$(echo "$output" | grep -v '^$' | head -1)
    echo "$first_line" | grep -q "High task"
}

@test "existing add behavior unchanged" {
    run cmd_add "Simple task"
    assert_success
    assert_output --partial "Added task"
    local count
    count=$(jq length "$TASKCTL_DATA")
    [[ "$count" -eq 1 ]]
    local desc
    desc=$(jq -r '.[0].description' "$TASKCTL_DATA")
    [[ "$desc" = "Simple task" ]]
}

@test "existing list behavior unchanged" {
    cmd_add "Task one"
    cmd_add "Task two"
    run cmd_list
    assert_success
    assert_output --partial "Task one"
    assert_output --partial "Task two"
}
