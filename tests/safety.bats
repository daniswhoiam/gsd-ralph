#!/usr/bin/env bats
# tests/safety.bats -- Tests for safety guardrails (SAFE-01 through SAFE-04)

load 'test_helper/common'

setup() {
    _common_setup
    create_test_repo
    # Source required libs (GSD_RALPH_HOME is needed for source chains)
    export GSD_RALPH_HOME="$PROJECT_ROOT"
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/safety.sh"
}

teardown() {
    _common_teardown
}

# ===========================================================================
# Unit tests: safe_remove() (SAFE-02)
# ===========================================================================

@test "safe_remove rejects empty path" {
    run safe_remove ""
    assert_failure
    assert_output --partial "SAFETY"
}

@test "safe_remove rejects filesystem root" {
    run safe_remove "/" "directory"
    assert_failure
    assert_output --partial "filesystem root"
}

@test "safe_remove rejects home directory" {
    local orig_home="$HOME"
    # Use the test temp dir as a stand-in HOME so -ef comparison works
    export HOME="$TEST_TEMP_DIR"
    run safe_remove "$TEST_TEMP_DIR" "directory"
    export HOME="$orig_home"
    assert_failure
    assert_output --partial "home directory"
}

@test "safe_remove rejects git toplevel" {
    local toplevel
    toplevel=$(git rev-parse --show-toplevel)
    run safe_remove "$toplevel" "directory"
    assert_failure
    assert_output --partial "git working tree"
}

@test "safe_remove allows regular file deletion" {
    local tempfile="$TEST_TEMP_DIR/deleteme.txt"
    echo "test content" > "$tempfile"
    [ -f "$tempfile" ]
    run safe_remove "$tempfile" "file"
    assert_success
    [ ! -f "$tempfile" ]
}

@test "safe_remove allows subdirectory deletion" {
    local subdir="$TEST_TEMP_DIR/subdir-to-delete"
    mkdir -p "$subdir"
    [ -d "$subdir" ]
    run safe_remove "$subdir" "directory"
    assert_success
    [ ! -d "$subdir" ]
}

@test "safe_remove rejects git toplevel via symlink" {
    local toplevel
    toplevel=$(git rev-parse --show-toplevel)
    local symlink="$TEST_TEMP_DIR/symlink-to-root"
    ln -s "$toplevel" "$symlink"
    run safe_remove "$symlink" "directory"
    assert_failure
    assert_output --partial "git working tree"
}

@test "safe_remove returns success for nonexistent target" {
    run safe_remove "$TEST_TEMP_DIR/does-not-exist" "file"
    assert_success
}

# ===========================================================================
# Unit tests: validate_registry_path() (SAFE-02, SAFE-03)
# ===========================================================================

@test "validate_registry_path rejects empty path" {
    run validate_registry_path ""
    assert_failure
    assert_output --partial "SAFETY"
}

@test "validate_registry_path accepts __MAIN_WORKTREE__ sentinel" {
    run validate_registry_path "__MAIN_WORKTREE__"
    assert_success
}

@test "validate_registry_path rejects relative path" {
    run validate_registry_path "relative/path"
    assert_failure
    assert_output --partial "absolute"
}

@test "validate_registry_path rejects path traversal" {
    run validate_registry_path "/some/../../../etc"
    assert_failure
    assert_output --partial "traversal"
}

@test "validate_registry_path accepts absolute path" {
    run validate_registry_path "/tmp/some-worktree"
    assert_success
}
