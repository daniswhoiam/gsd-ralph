#!/usr/bin/env bats
# tests/ralph-hook.bats -- Tests for PreToolUse hook deny/allow/audit behaviors

setup() {
    load 'test_helper/common'
    load 'test_helper/ralph-helpers'
    _common_setup
    REAL_PROJECT_ROOT="$(get_real_project_root)"
    HOOK_SCRIPT="$REAL_PROJECT_ROOT/scripts/ralph-hook.sh"
    export RALPH_AUDIT_FILE="$TEST_TEMP_DIR/.ralph/audit.log"
    mkdir -p "$TEST_TEMP_DIR/.ralph"
}

teardown() {
    _common_teardown
}

# --- Hook deny tests ---

@test "deny: hook denies AskUserQuestion with correct JSON" {
    local input='{"tool_name":"AskUserQuestion","tool_input":{"question":"Which approach?"}}'
    run bash -c "echo '$input' | '$HOOK_SCRIPT'"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecision == "deny"'
}

@test "deny: hook returns guidance message in deny reason" {
    local input='{"tool_name":"AskUserQuestion","tool_input":{"question":"Which approach?"}}'
    run bash -c "echo '$input' | '$HOOK_SCRIPT'"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.permissionDecisionReason | test("blocked in autopilot mode")'
}

@test "deny: hook exits 0 on AskUserQuestion" {
    local input='{"tool_name":"AskUserQuestion","tool_input":{"question":"Which approach?"}}'
    run bash -c "echo '$input' | '$HOOK_SCRIPT'"
    assert_success
}

# --- Hook allow tests ---

@test "allow: hook produces no output for non-AskUserQuestion tools" {
    local input='{"tool_name":"Read","tool_input":{"file_path":"/tmp/test.txt"}}'
    run bash -c "echo '$input' | '$HOOK_SCRIPT'"
    assert_success
    assert_output ""
}

@test "allow: hook exits 0 for non-AskUserQuestion tools" {
    local input='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run bash -c "echo '$input' | '$HOOK_SCRIPT'"
    assert_success
}

# --- Hook audit logging tests ---

@test "audit: hook logs denied question to audit file" {
    local input='{"tool_name":"AskUserQuestion","tool_input":{"question":"Which approach should I use?"}}'
    bash -c "echo '$input' | '$HOOK_SCRIPT'" >/dev/null
    assert_file_exists "$RALPH_AUDIT_FILE"
    run cat "$RALPH_AUDIT_FILE"
    assert_output --partial "DENIED AskUserQuestion"
    assert_output --partial "Which approach should I use?"
}

@test "audit: hook handles missing question field gracefully" {
    local input='{"tool_name":"AskUserQuestion","tool_input":{"options":["A","B"]}}'
    bash -c "echo '$input' | '$HOOK_SCRIPT'" >/dev/null
    run cat "$RALPH_AUDIT_FILE"
    assert_output --partial "unknown"
}
