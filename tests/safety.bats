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

# ===========================================================================
# Integration tests: register_worktree() guard (SAFE-03)
# ===========================================================================

@test "register_worktree uses sentinel for main working tree" {
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    mkdir -p .ralph

    # Register from within the test repo -- pwd IS the git toplevel
    register_worktree "1" "$(pwd)" "phase-1/test"

    # Read the registry and verify sentinel was stored
    local stored_path
    stored_path=$(jq -r '.["1"][0].worktree_path' .ralph/worktree-registry.json)
    [ "$stored_path" = "__MAIN_WORKTREE__" ]
}

@test "register_worktree stores real path for non-main worktree" {
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    mkdir -p .ralph

    # Create a subdirectory that is NOT the git toplevel
    local subdir="$TEST_TEMP_DIR/fake-worktree-dir"
    mkdir -p "$subdir"

    register_worktree "1" "$subdir" "phase-1/plan-01"

    # Read the registry and verify the real path was stored
    local stored_path
    stored_path=$(jq -r '.["1"][0].worktree_path' .ralph/worktree-registry.json)
    [ "$stored_path" = "$subdir" ]
}

# ===========================================================================
# Integration tests: cleanup safety (SAFE-01, SAFE-04)
# ===========================================================================

# Helper: set up a full GSD environment for cleanup integration tests
_setup_cleanup_env() {
    create_gsd_structure
    mkdir -p .ralph
    git add -A >/dev/null 2>&1
    git commit -m "Setup GSD structure" >/dev/null 2>&1
}

@test "cleanup does not rm -rf on worktree removal failure" {
    _setup_cleanup_env

    # Create a branch so cleanup has something to find
    git checkout -b "phase-9/test-plan" >/dev/null 2>&1
    echo "content" > test-file.txt
    git add -A >/dev/null 2>&1
    git commit -m "Add test file" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    # Create a directory that is NOT a git worktree (so git worktree remove fails)
    local fake_wt="$TEST_TEMP_DIR/not-a-real-worktree"
    mkdir -p "$fake_wt"
    echo "important data" > "$fake_wt/data.txt"

    # Register it in the worktree registry
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    init_registry
    local tmp
    tmp=$(jq --arg wt "$fake_wt" \
        '.["9"] = [{"worktree_path": $wt, "branch": "phase-9/test-plan", "created_at": "2026-01-01T00:00:00Z"}]' \
        .ralph/worktree-registry.json)
    printf '%s\n' "$tmp" > .ralph/worktree-registry.json

    # Run cleanup -- should warn about failed worktree removal but NOT rm -rf it
    run gsd-ralph cleanup 9 --force
    assert_success

    # The directory must STILL exist (no rm -rf fallback)
    [ -d "$fake_wt" ]
    [ -f "$fake_wt/data.txt" ]

    # Output should mention the failure
    assert_output --partial "Failed to remove worktree"
}

@test "cleanup skips directory removal for __MAIN_WORKTREE__ sentinel" {
    _setup_cleanup_env

    # Create and register a branch with sentinel worktree path
    git checkout -b "phase-9/sentinel-test" >/dev/null 2>&1
    echo "content" > sentinel-file.txt
    git add -A >/dev/null 2>&1
    git commit -m "Add sentinel test file" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    init_registry
    local tmp
    tmp=$(jq '.["9"] = [{"worktree_path": "__MAIN_WORKTREE__", "branch": "phase-9/sentinel-test", "created_at": "2026-01-01T00:00:00Z"}]' \
        .ralph/worktree-registry.json)
    printf '%s\n' "$tmp" > .ralph/worktree-registry.json

    local repo_root
    repo_root=$(pwd)

    # Run cleanup
    run gsd-ralph cleanup 9 --force
    assert_success

    # The test repo root must still exist
    [ -d "$repo_root" ]

    # Output should NOT contain errors about removing worktree
    refute_output --partial "Failed to remove worktree"
}

@test "cleanup handles pre-v1.0 registry entry pointing to project root" {
    _setup_cleanup_env

    # Create a branch for this test
    git checkout -b "phase-9/legacy-test" >/dev/null 2>&1
    echo "content" > legacy-file.txt
    git add -A >/dev/null 2>&1
    git commit -m "Add legacy test file" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    local repo_root
    repo_root=$(pwd)

    # Register with the actual project root path (simulating pre-v1.0 entry)
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    init_registry
    local tmp
    tmp=$(jq --arg wt "$repo_root" \
        '.["9"] = [{"worktree_path": $wt, "branch": "phase-9/legacy-test", "created_at": "2026-01-01T00:00:00Z"}]' \
        .ralph/worktree-registry.json)
    printf '%s\n' "$tmp" > .ralph/worktree-registry.json

    # Run cleanup
    run gsd-ralph cleanup 9 --force
    assert_success

    # The project root must still exist
    [ -d "$repo_root" ]

    # Output should contain warning about project root
    assert_output --partial "project root"
}

@test "no raw rm -rf in lib/ source files outside safety.sh" {
    # Static analysis: verify no rm -rf commands exist in lib/ outside of safety.sh
    # Exclude comment lines (starting with #) and safety.sh itself
    local matches
    matches=$(grep -rn 'rm -rf' "$PROJECT_ROOT/lib/" | grep -v 'safety.sh' | grep -v '^\s*#' | grep -v '# ' || true)
    [ -z "$matches" ]
}
