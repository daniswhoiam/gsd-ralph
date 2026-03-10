#!/usr/bin/env bats
# tests/ralph-permissions.bats -- Tests for permission tier flag mapping

setup() {
    load 'test_helper/common'
    load 'test_helper/ralph-helpers'
    _common_setup
    REAL_PROJECT_ROOT="$(get_real_project_root)"

    # Create a git repo so PROJECT_ROOT detection works
    create_test_repo

    # Create required scripts directory with validate-config.sh stub
    mkdir -p scripts
    cat > scripts/validate-config.sh <<'STUBEOF'
validate_ralph_config() { return 0; }
STUBEOF

    # Source the launcher script (functions only, guarded main)
    source "$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh"
}

teardown() {
    _common_teardown
}

# --- build_permission_flags tests ---

@test "default tier produces --allowedTools with correct whitelist" {
    PERMISSION_TIER="default"
    run build_permission_flags
    assert_success
    assert_output --partial '--allowedTools'
    assert_output --partial 'Write'
    assert_output --partial 'Read'
    assert_output --partial 'Edit'
    assert_output --partial 'Grep'
    assert_output --partial 'Glob'
    assert_output --partial 'Bash(*)'
}

@test "auto-mode tier produces --permission-mode auto" {
    PERMISSION_TIER="auto-mode"
    run build_permission_flags
    assert_success
    assert_output '--permission-mode auto'
}

@test "yolo tier produces --dangerously-skip-permissions" {
    PERMISSION_TIER="yolo"
    run build_permission_flags
    assert_success
    assert_output '--dangerously-skip-permissions'
}

@test "invalid tier returns error" {
    PERMISSION_TIER="superuser"
    run build_permission_flags
    assert_failure
    assert_output --partial 'Unknown permission tier'
}
