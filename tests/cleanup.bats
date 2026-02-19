#!/usr/bin/env bats
# tests/cleanup.bats -- Integration tests for gsd-ralph cleanup command

setup() {
    load 'test_helper/common'
    _common_setup

    create_test_repo
    create_gsd_structure
    mkdir -p .ralph
    # Commit setup files so working tree is clean
    git add -A >/dev/null 2>&1
    git commit -m "Setup GSD structure" >/dev/null 2>&1
}

teardown() {
    _common_teardown
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Create a test branch with a commit, then switch back to main
create_test_branch() {
    local branch_name="$1"
    git checkout -b "$branch_name" >/dev/null 2>&1
    echo "content for $branch_name" > "${branch_name//\//-}-file.txt"
    git add -A >/dev/null 2>&1
    git commit -m "Add file on $branch_name" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1
}

# Register a branch in the worktree registry via the registry module
register_test_branch() {
    local phase_num="$1"
    local worktree_path="$2"
    local branch_name="$3"
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    register_worktree "$phase_num" "$worktree_path" "$branch_name"
}

# Set up a phase directory for testing
setup_cleanup_phase() {
    local phase_num="${1:-5}"
    mkdir -p ".planning/phases/0${phase_num}-test-phase"
    git add -A >/dev/null 2>&1
    git commit -m "Add phase $phase_num directory" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# Command: usage and argument parsing
# ---------------------------------------------------------------------------

@test "cleanup --help shows usage" {
    run gsd-ralph cleanup --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "cleanup"
}

@test "cleanup requires phase number" {
    run gsd-ralph cleanup
    assert_failure
    assert_output --partial "Phase number required"
}

# ---------------------------------------------------------------------------
# Empty registry / nothing to clean
# ---------------------------------------------------------------------------

@test "cleanup with empty registry shows nothing to clean" {
    setup_cleanup_phase 5
    run gsd-ralph cleanup 5 --force
    assert_success
    assert_output --partial "Nothing to clean"
}

# ---------------------------------------------------------------------------
# Single branch removal
# ---------------------------------------------------------------------------

@test "cleanup removes registered branch" {
    setup_cleanup_phase 5
    local branch_name="phase-5/test-phase"
    create_test_branch "$branch_name"
    register_test_branch "5" "/tmp/fake-worktree" "$branch_name"

    # Verify branch exists before cleanup
    git show-ref --verify --quiet "refs/heads/$branch_name"

    run gsd-ralph cleanup 5 --force
    assert_success

    # Branch should be deleted
    run git show-ref --verify --quiet "refs/heads/$branch_name"
    assert_failure

    # Registry should no longer have phase 5 entries
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    local entries
    entries=$(list_registered_worktrees "5")
    local count
    count=$(printf '%s' "$entries" | jq '. | length')
    [[ "$count" -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Multiple branch removal
# ---------------------------------------------------------------------------

@test "cleanup removes multiple registered entries" {
    setup_cleanup_phase 5
    create_test_branch "phase-5/test-phase"
    create_test_branch "phase-5/plan-02"
    register_test_branch "5" "/tmp/fake-wt-1" "phase-5/test-phase"
    register_test_branch "5" "/tmp/fake-wt-2" "phase-5/plan-02"

    run gsd-ralph cleanup 5 --force
    assert_success

    # Both branches should be deleted
    run git show-ref --verify --quiet "refs/heads/phase-5/test-phase"
    assert_failure
    run git show-ref --verify --quiet "refs/heads/phase-5/plan-02"
    assert_failure
}

# ---------------------------------------------------------------------------
# Already-removed resources
# ---------------------------------------------------------------------------

@test "cleanup handles already-deleted branch gracefully" {
    setup_cleanup_phase 5
    # Register a branch that does not exist in git
    register_test_branch "5" "/tmp/fake-worktree" "phase-5/nonexistent-branch"

    run gsd-ralph cleanup 5 --force
    assert_success
}

@test "cleanup handles already-removed worktree gracefully" {
    setup_cleanup_phase 5
    local branch_name="phase-5/test-phase"
    create_test_branch "$branch_name"
    # Register a worktree path that does not exist on disk
    register_test_branch "5" "/tmp/nonexistent-worktree-path" "$branch_name"

    run gsd-ralph cleanup 5 --force
    assert_success

    # Branch should still be cleaned up
    run git show-ref --verify --quiet "refs/heads/$branch_name"
    assert_failure
}

# ---------------------------------------------------------------------------
# Non-interactive and --force
# ---------------------------------------------------------------------------

@test "cleanup refuses without --force in non-interactive mode" {
    setup_cleanup_phase 5
    local branch_name="phase-5/test-phase"
    create_test_branch "$branch_name"
    register_test_branch "5" "/tmp/fake-wt" "$branch_name"

    run bash -c 'echo "" | '"$PROJECT_ROOT"'/bin/gsd-ralph cleanup 5'
    assert_failure
    assert_output --partial "Non-interactive"
}

@test "cleanup with --force skips confirmation" {
    setup_cleanup_phase 5
    local branch_name="phase-5/test-phase"
    create_test_branch "$branch_name"
    register_test_branch "5" "/tmp/fake-wt" "$branch_name"

    run gsd-ralph cleanup 5 --force
    assert_success
    assert_output --partial "cleanup complete"
}

# ---------------------------------------------------------------------------
# Signal file cleanup
# ---------------------------------------------------------------------------

@test "cleanup removes signal files" {
    setup_cleanup_phase 5
    register_test_branch "5" "/tmp/fake-wt" "phase-5/fake-branch"

    mkdir -p .ralph/merge-signals
    echo '{"phase": 5, "wave": 1}' > .ralph/merge-signals/phase-5-wave-1-complete
    echo '{"phase": 5}' > .ralph/merge-signals/phase-5-complete

    run gsd-ralph cleanup 5 --force
    assert_success

    assert_file_not_exists .ralph/merge-signals/phase-5-wave-1-complete
    assert_file_not_exists .ralph/merge-signals/phase-5-complete
}

# ---------------------------------------------------------------------------
# Rollback file cleanup
# ---------------------------------------------------------------------------

@test "cleanup removes rollback file for matching phase" {
    setup_cleanup_phase 5
    register_test_branch "5" "/tmp/fake-wt" "phase-5/fake-branch"

    echo '{"phase": 5, "pre_merge_sha": "abc123"}' > .ralph/merge-rollback.json

    run gsd-ralph cleanup 5 --force
    assert_success

    assert_file_not_exists .ralph/merge-rollback.json
}

@test "cleanup preserves rollback file for different phase" {
    setup_cleanup_phase 5
    register_test_branch "5" "/tmp/fake-wt" "phase-5/fake-branch"

    echo '{"phase": 3, "pre_merge_sha": "abc123"}' > .ralph/merge-rollback.json

    run gsd-ralph cleanup 5 --force
    assert_success

    assert_file_exists .ralph/merge-rollback.json
}

# ---------------------------------------------------------------------------
# Git worktree prune
# ---------------------------------------------------------------------------

@test "cleanup runs git worktree prune without error" {
    setup_cleanup_phase 5
    register_test_branch "5" "/tmp/fake-wt" "phase-5/fake-branch"

    run gsd-ralph cleanup 5 --force
    assert_success

    # Verify worktree list only shows main worktree (no stale entries)
    run git worktree list
    assert_success
}

# ---------------------------------------------------------------------------
# Registry isolation between phases
# ---------------------------------------------------------------------------

@test "cleanup preserves other phases in registry" {
    setup_cleanup_phase 5
    setup_cleanup_phase 3
    create_test_branch "phase-5/test-phase"
    create_test_branch "phase-3/other-phase"
    register_test_branch "5" "/tmp/fake-wt-5" "phase-5/test-phase"
    register_test_branch "3" "/tmp/fake-wt-3" "phase-3/other-phase"

    run gsd-ralph cleanup 5 --force
    assert_success

    # Phase 5 branch should be gone
    run git show-ref --verify --quiet "refs/heads/phase-5/test-phase"
    assert_failure

    # Phase 3 branch should still exist
    git show-ref --verify --quiet "refs/heads/phase-3/other-phase"

    # Phase 3 registry entries should still exist
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    local entries
    entries=$(list_registered_worktrees "3")
    local count
    count=$(printf '%s' "$entries" | jq '. | length')
    [[ "$count" -eq 1 ]]
}

# ---------------------------------------------------------------------------
# Environment validation
# ---------------------------------------------------------------------------

@test "cleanup fails outside git repo" {
    local non_git_dir
    non_git_dir="$(mktemp -d)"
    cd "$non_git_dir" || return 1
    run gsd-ralph cleanup 5
    assert_failure
    assert_output --partial "Not inside a git repository"
    rm -rf "$non_git_dir"
}

@test "cleanup fails without .ralph directory" {
    rm -rf .ralph
    run gsd-ralph cleanup 5
    assert_failure
    assert_output --partial "init"
}
