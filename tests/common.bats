#!/usr/bin/env bats
# tests/common.bats -- Unit tests for lib/common.sh

setup() {
    load 'test_helper/common'
    _common_setup

    # Source lib/common.sh directly for unit testing
    VERBOSE=false
    source "$PROJECT_ROOT/lib/common.sh"
}

teardown() {
    _common_teardown
}

@test "print_success outputs [ok] prefix" {
    run print_success "it works"
    assert_success
    assert_output --partial "[ok]"
    assert_output --partial "it works"
}

@test "print_error outputs [error] prefix to stderr" {
    run print_error "bad thing"
    assert_success
    assert_output --partial "[error]"
    assert_output --partial "bad thing"
}

@test "print_warning outputs [warn] prefix" {
    run print_warning "be careful"
    assert_success
    assert_output --partial "[warn]"
    assert_output --partial "be careful"
}

@test "print_info outputs [info] prefix" {
    run print_info "info message"
    assert_success
    assert_output --partial "[info]"
    assert_output --partial "info message"
}

@test "die exits with code 1 and prints error" {
    run die "fatal error"
    assert_failure 1
    assert_output --partial "[error]"
    assert_output --partial "fatal error"
}

@test "die exits with custom code" {
    run die "custom error" 42
    assert_failure 42
}

@test "check_dependency succeeds for git" {
    run check_dependency "git" "install git"
    assert_success
}

@test "check_dependency fails for nonexistent tool" {
    run check_dependency "nonexistent_tool_xyz_99" "brew install nonexistent_tool_xyz_99"
    assert_failure
    assert_output --partial "nonexistent_tool_xyz_99 is not installed"
    assert_output --partial "Install:"
}

@test "iso_timestamp returns ISO 8601 format" {
    run iso_timestamp
    assert_success
    # Match YYYY-MM-DDTHH:MM:SSZ pattern
    assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
}

@test "ring_bell function exists and succeeds" {
    run ring_bell
    assert_success
}
