#!/usr/bin/env bats
# tests/merge.bats -- Integration tests for gsd-ralph merge command and
# merge infrastructure modules (dry_run, rollback, auto_resolve)

setup() {
    load 'test_helper/common'
    _common_setup

    create_test_repo
    create_gsd_structure
    mkdir -p .ralph
    # Commit all setup files so working tree is clean for merge tests
    git add -A >/dev/null 2>&1
    git commit -m "Setup GSD structure" >/dev/null 2>&1
}

teardown() {
    _common_teardown
}

# ---------------------------------------------------------------------------
# Helper: create a phase directory with a plan and a branch with changes
# ---------------------------------------------------------------------------

setup_merge_branch() {
    # Create phase directory with a plan and commit it on main
    mkdir -p .planning/phases/03-phase-execution
    cat > .planning/phases/03-phase-execution/03-01-PLAN.md << 'PLAN'
---
phase: 03-phase-execution
plan: 01
type: execute
wave: 1
depends_on: []
---

<tasks>
<task type="auto">
  <name>Task 1: Test task</name>
  <files>test.txt</files>
  <action>Create a file.</action>
  <verify>File exists.</verify>
  <done>File created.</done>
</task>
</tasks>
PLAN
    git add .planning/phases/03-phase-execution/03-01-PLAN.md >/dev/null 2>&1
    git commit -m "Add phase 3 plan" >/dev/null 2>&1

    # Create a branch with a committed change
    git checkout -b "phase-3/phase-execution" >/dev/null 2>&1
    echo "branch content" > branch-file.txt
    git add branch-file.txt >/dev/null 2>&1
    git commit -m "Add branch file" >/dev/null 2>&1

    # Switch back to main (the initial branch)
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Command: usage and argument parsing
# ---------------------------------------------------------------------------

@test "merge shows usage with --help" {
    run gsd-ralph merge --help
    assert_success
    assert_output --partial "Usage:"
    assert_output --partial "gsd-ralph merge"
}

@test "merge requires phase number" {
    run gsd-ralph merge
    assert_failure
    assert_output --partial "Phase number required"
}

# ---------------------------------------------------------------------------
# Command: environment validation
# ---------------------------------------------------------------------------

@test "merge fails outside git repo" {
    local non_git_dir
    non_git_dir="$(mktemp -d)"
    cd "$non_git_dir" || return 1
    run gsd-ralph merge 3
    assert_failure
    assert_output --partial "Not inside a git repository"
    rm -rf "$non_git_dir"
}

@test "merge fails without .planning directory" {
    rm -rf .planning
    run gsd-ralph merge 3
    assert_failure
    assert_output --partial ".planning"
}

@test "merge fails without .ralph directory" {
    rm -rf .ralph
    run gsd-ralph merge 3
    assert_failure
    assert_output --partial "init"
}

@test "merge fails with dirty working tree" {
    setup_merge_branch
    echo "uncommitted" > dirty-file.txt
    run gsd-ralph merge 3
    assert_failure
    assert_output --partial "not clean"
}

# ---------------------------------------------------------------------------
# Branch discovery
# ---------------------------------------------------------------------------

@test "merge discovers sequential branch" {
    setup_merge_branch
    run gsd-ralph merge 3 --dry-run
    assert_success
    assert_output --partial "phase-3/phase-execution"
}

@test "merge skips already-merged branches" {
    setup_merge_branch
    # Manually merge the branch
    git merge "phase-3/phase-execution" --no-edit >/dev/null 2>&1
    run gsd-ralph merge 3
    assert_success
    assert_output --partial "No unmerged branches"
}

# ---------------------------------------------------------------------------
# Dry-run conflict detection (module: lib/merge/dry_run.sh)
# ---------------------------------------------------------------------------

@test "dry_run detects clean merge" {
    setup_merge_branch
    # Branch has non-conflicting changes (new file)
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/merge/dry_run.sh"
    run merge_dry_run "phase-3/phase-execution"
    assert_success
}

@test "dry_run detects conflicting merge" {
    setup_merge_branch
    # Create a conflicting change on main: same file, different content
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1
    echo "main content" > branch-file.txt
    git add branch-file.txt >/dev/null 2>&1
    git commit -m "Add conflicting file on main" >/dev/null 2>&1

    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/merge/dry_run.sh"
    run merge_dry_run "phase-3/phase-execution"
    assert_failure
}

# ---------------------------------------------------------------------------
# Rollback (module: lib/merge/rollback.sh)
# ---------------------------------------------------------------------------

@test "rollback saves and restores" {
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/merge/rollback.sh"

    # Save rollback point at current HEAD
    local original_sha
    original_sha=$(git rev-parse HEAD)
    save_rollback_point 3

    # Verify rollback file exists
    assert_file_exists ".ralph/merge-rollback.json"

    # Make a commit to move HEAD forward
    echo "new content" > new-file.txt
    git add new-file.txt >/dev/null 2>&1
    git commit -m "New commit to move HEAD" >/dev/null 2>&1

    # Verify HEAD moved
    local new_sha
    new_sha=$(git rev-parse HEAD)
    [[ "$original_sha" != "$new_sha" ]]

    # Rollback
    rollback_merge 3

    # Verify HEAD is back at original SHA
    local restored_sha
    restored_sha=$(git rev-parse HEAD)
    [[ "$original_sha" == "$restored_sha" ]]

    # Verify rollback file was removed
    assert_file_not_exists ".ralph/merge-rollback.json"
}

# ---------------------------------------------------------------------------
# Auto-resolve (module: lib/merge/auto_resolve.sh)
# ---------------------------------------------------------------------------

@test "auto_resolve resolves .planning/ conflicts" {
    # Create a branch that modifies .planning/STATE.md
    git checkout -b "test-branch" >/dev/null 2>&1
    echo "branch state" > .planning/STATE.md
    git add .planning/STATE.md >/dev/null 2>&1
    git commit -m "Branch modifies STATE.md" >/dev/null 2>&1

    # Switch back to main and make a conflicting change
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1
    echo "main state" > .planning/STATE.md
    git add .planning/STATE.md >/dev/null 2>&1
    git commit -m "Main modifies STATE.md" >/dev/null 2>&1

    # Start a merge (will conflict)
    git merge --no-commit --no-ff "test-branch" 2>/dev/null || true

    # Source and run auto-resolve
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/merge/auto_resolve.sh"
    run auto_resolve_known_conflicts
    assert_success

    # Verify the conflict was resolved (--ours = main's version)
    local content
    content=$(<.planning/STATE.md)
    [[ "$content" == "main state" ]]
}
