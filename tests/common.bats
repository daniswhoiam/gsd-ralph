#!/usr/bin/env bats
# tests/common.bats -- Unit tests for lib/common.sh

setup() {
    load 'test_helper/common'
    _common_setup
    source "$PROJECT_ROOT/lib/common.sh"
}

teardown() {
    _common_teardown
}

@test "print_success outputs [ok] prefix" {
    run print_success "test message"
    assert_success
    assert_output --partial "[ok]"
    assert_output --partial "test message"
}

@test "print_error outputs [error] prefix to stderr" {
    run print_error "error message"
    assert_success
    assert_output --partial "[error]"
    assert_output --partial "error message"
}

@test "print_warning outputs [warn] prefix" {
    run print_warning "warning message"
    assert_success
    assert_output --partial "[warn]"
    assert_output --partial "warning message"
}

@test "print_info outputs [info] prefix" {
    run print_info "info message"
    assert_success
    assert_output --partial "[info]"
    assert_output --partial "info message"
}

@test "die exits with code 1 and prints error" {
    run die "fatal error"
    assert_failure
    assert_output --partial "[error]"
    assert_output --partial "fatal error"
}

@test "die exits with custom code" {
    run die "fatal error" 42
    assert_failure 42
}

@test "check_dependency succeeds for git" {
    run check_dependency "git" "https://git-scm.com"
    assert_success
}

@test "check_dependency fails for nonexistent tool" {
    run check_dependency "nonexistent_tool_xyz" "install from example.com"
    assert_failure
    assert_output --partial "nonexistent_tool_xyz is not installed"
    assert_output --partial "Install: install from example.com"
}

@test "iso_timestamp returns ISO 8601 format" {
    run iso_timestamp
    assert_success
    # Match pattern YYYY-MM-DDTHH:MM:SSZ
    assert_output --regexp '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'
}
