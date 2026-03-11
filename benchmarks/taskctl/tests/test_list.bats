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

@test "list shows all tasks" {
    run cmd_add "Task one"
    assert_success
    run cmd_add "Task two"
    assert_success
    run cmd_list
    assert_success
    assert_output --partial "Task one"
    assert_output --partial "Task two"
}

@test "list --done shows only completed tasks" {
    run cmd_add "Done task"
    assert_success
    run cmd_add "Pending task"
    assert_success
    # Manually mark first task as done
    local tasks
    tasks=$(jq '.[0].done = true' "$TASKCTL_DATA")
    echo "$tasks" > "$TASKCTL_DATA"
    run cmd_list "--done"
    assert_success
    assert_output --partial "Done task"
    refute_output --partial "Pending task"
}

@test "list empty shows no tasks message" {
    run cmd_list
    assert_success
    assert_output --partial "No tasks"
}
