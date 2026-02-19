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

# ---------------------------------------------------------------------------
# Merge pipeline (Plan 04-02 tests)
# ---------------------------------------------------------------------------

# Helper: create a conflicting branch (same file, different content on main and branch)
setup_conflicting_branch() {
    local branch_name="${1:-phase-3/conflicting}"
    local phase_dir="${2:-.planning/phases/03-phase-execution}"

    # Ensure phase directory and plan exist on main
    mkdir -p "$phase_dir"
    if [[ ! -f "$phase_dir/03-01-PLAN.md" ]]; then
        cat > "$phase_dir/03-01-PLAN.md" << 'PLAN'
---
phase: 03-phase-execution
plan: 01
type: execute
wave: 1
depends_on: []
---
PLAN
        git add "$phase_dir/03-01-PLAN.md" >/dev/null 2>&1
        git commit -m "Add phase 3 plan" >/dev/null 2>&1
    fi

    # Create conflicting content on main first
    echo "main content" > shared-file.txt
    git add shared-file.txt >/dev/null 2>&1
    git commit -m "Add shared file on main" >/dev/null 2>&1

    # Create branch with conflicting content
    git checkout -b "$branch_name" >/dev/null 2>&1
    echo "branch content" > shared-file.txt
    git add shared-file.txt >/dev/null 2>&1
    git commit -m "Modify shared file on branch" >/dev/null 2>&1

    # Switch back to main
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1
}

@test "merge merges a clean branch into main" {
    setup_merge_branch

    # Capture main HEAD before merge
    local main_sha_before
    main_sha_before=$(git rev-parse HEAD)

    run gsd-ralph merge 3
    assert_success

    # Verify branch changes are in main (merge commit exists)
    local merge_log
    merge_log=$(git log --oneline)
    echo "$merge_log" | grep -q "Merge branch"

    # Verify the branch file exists on main now
    assert_file_exists "branch-file.txt"
}

@test "merge produces summary table" {
    setup_merge_branch

    run gsd-ralph merge 3
    assert_success

    # Assert output contains summary table with "merged" and branch name
    assert_output --partial "merged"
    assert_output --partial "phase-3/phase-execution"
    assert_output --partial "Branch"
    assert_output --partial "Status"
}

@test "merge skips conflicted branch and continues" {
    # Create phase directory with plan and a shared file as common ancestor
    mkdir -p .planning/phases/03-phase-execution
    cat > .planning/phases/03-phase-execution/03-01-PLAN.md << 'PLAN'
---
phase: 03-phase-execution
plan: 01
type: execute
wave: 1
depends_on: []
---
PLAN
    echo "original content" > shared-file.txt
    git add .planning/phases/03-phase-execution/03-01-PLAN.md shared-file.txt >/dev/null 2>&1
    git commit -m "Add phase 3 plan and shared file" >/dev/null 2>&1

    # Create clean branch with a non-conflicting file
    git checkout -b "phase-3/phase-execution" >/dev/null 2>&1
    echo "clean content" > clean-file.txt
    git add clean-file.txt >/dev/null 2>&1
    git commit -m "Add clean file" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    # Create per-plan branch that modifies shared-file.txt differently
    git checkout -b "phase/3/plan-02" >/dev/null 2>&1
    echo "branch version of content" > shared-file.txt
    git add shared-file.txt >/dev/null 2>&1
    git commit -m "Modify shared file on branch" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    # Modify shared-file.txt on main (creates true conflict with branch)
    echo "main version of content" > shared-file.txt
    git add shared-file.txt >/dev/null 2>&1
    git commit -m "Modify shared file on main" >/dev/null 2>&1

    run gsd-ralph merge 3
    # Exit code is 1 because some branches had conflicts
    assert_failure

    # Clean branch should be merged
    assert_output --partial "merged"
    assert_file_exists "clean-file.txt"

    # Conflicting branch should show conflict status
    assert_output --partial "conflict"
}

@test "merge with --dry-run shows report without merging" {
    setup_merge_branch

    # Record HEAD before dry-run
    local sha_before
    sha_before=$(git rev-parse HEAD)

    run gsd-ralph merge 3 --dry-run
    assert_success

    # Output shows clean status
    assert_output --partial "clean"
    assert_output --partial "phase-3/phase-execution"

    # Verify HEAD did not move (no merge happened)
    local sha_after
    sha_after=$(git rev-parse HEAD)
    [[ "$sha_before" == "$sha_after" ]]
}

@test "merge with --review shows detailed diffs" {
    setup_merge_branch

    run gsd-ralph merge 3 --review
    assert_success

    # Review output should contain diff stats and commit log
    assert_output --partial "Detailed Review"
    assert_output --partial "Diff stat"
    assert_output --partial "Commits"
}

@test "merge auto-resolves .planning/ conflicts during pipeline" {
    # Create phase directory with plan
    mkdir -p .planning/phases/03-phase-execution
    cat > .planning/phases/03-phase-execution/03-01-PLAN.md << 'PLAN'
---
phase: 03-phase-execution
plan: 01
type: execute
wave: 1
depends_on: []
---
PLAN
    git add .planning/phases/03-phase-execution/03-01-PLAN.md >/dev/null 2>&1
    git commit -m "Add phase 3 plan" >/dev/null 2>&1

    # Create branch BEFORE changing STATE.md on main, so both sides diverge
    git checkout -b "phase-3/phase-execution" >/dev/null 2>&1
    echo "branch state content" > .planning/STATE.md
    echo "new feature" > feature.txt
    git add .planning/STATE.md feature.txt >/dev/null 2>&1
    git commit -m "Branch changes" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    # Now modify STATE.md on main (creates true conflict in .planning/)
    echo "main state content" > .planning/STATE.md
    git add .planning/STATE.md >/dev/null 2>&1
    git commit -m "Update STATE.md on main" >/dev/null 2>&1

    run gsd-ralph merge 3
    assert_success

    # Verify merge succeeded (auto-resolved)
    assert_output --partial "merged"
    # The feature file should be present
    assert_file_exists "feature.txt"
    # STATE.md should have main's version (auto-resolved with --ours)
    local state_content
    state_content=$(<.planning/STATE.md)
    [[ "$state_content" == "main state content" ]]
}

@test "merge reports conflict guidance for skipped branches" {
    # Create phase directory with plan and a shared file as common ancestor
    mkdir -p .planning/phases/03-phase-execution
    cat > .planning/phases/03-phase-execution/03-01-PLAN.md << 'PLAN'
---
phase: 03-phase-execution
plan: 01
type: execute
wave: 1
depends_on: []
---
PLAN
    echo "original code" > code-file.txt
    git add .planning/phases/03-phase-execution/03-01-PLAN.md code-file.txt >/dev/null 2>&1
    git commit -m "Add phase 3 plan and code file" >/dev/null 2>&1

    # Create branch that modifies code-file.txt
    git checkout -b "phase-3/phase-execution" >/dev/null 2>&1
    echo "branch code changes" > code-file.txt
    git add code-file.txt >/dev/null 2>&1
    git commit -m "Modify code file on branch" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    # Modify code-file.txt on main (creates true conflict)
    echo "main code changes" > code-file.txt
    git add code-file.txt >/dev/null 2>&1
    git commit -m "Modify code file on main" >/dev/null 2>&1

    run gsd-ralph merge 3
    # Should fail (conflict)
    assert_failure

    # Should show conflict guidance
    assert_output --partial "To resolve manually"
    assert_output --partial "code-file.txt"
}

# ---------------------------------------------------------------------------
# Post-merge testing (Plan 04-03 tests)
# ---------------------------------------------------------------------------

@test "merge runs post-merge tests when test command available" {
    setup_merge_branch

    # Create a package.json with a test script that always passes
    cat > package.json << 'PKG'
{
  "name": "test-project",
  "scripts": {
    "test": "exit 0"
  }
}
PKG
    git add package.json >/dev/null 2>&1
    git commit -m "Add package.json with test script" >/dev/null 2>&1

    run gsd-ralph merge 3
    assert_success

    # Should report tests passing
    assert_output --partial "All tests passing"
}

@test "merge warns when no test command configured" {
    setup_merge_branch

    # No package.json, Cargo.toml, etc. -- no detectable test command
    run gsd-ralph merge 3
    assert_success

    # Should warn about no test command
    assert_output --partial "No test command configured"
}

@test "merge writes wave completion signal" {
    setup_merge_branch

    run gsd-ralph merge 3
    assert_success

    # Check that wave completion signal file exists
    assert_file_exists ".ralph/merge-signals/phase-3-wave-1-complete"

    # Verify signal file is valid JSON with expected fields
    local phase_val
    phase_val=$(jq -r '.phase' ".ralph/merge-signals/phase-3-wave-1-complete")
    [[ "$phase_val" == "3" ]]
    local wave_val
    wave_val=$(jq -r '.wave' ".ralph/merge-signals/phase-3-wave-1-complete")
    [[ "$wave_val" == "1" ]]
}

@test "merge updates STATE.md on full phase completion" {
    setup_merge_branch

    run gsd-ralph merge 3
    assert_success

    # STATE.md should be updated to show phase complete
    local state_content
    state_content=$(<.planning/STATE.md)
    echo "$state_content" | grep -q "Complete"
}

@test "merge updates ROADMAP.md on full phase completion" {
    setup_merge_branch

    # Create a ROADMAP.md with a progress table matching the expected pattern
    cat > .planning/ROADMAP.md << 'ROADMAP'
# Roadmap

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 3. Phase Execution | 1/1 | In Progress | - |
ROADMAP
    git add .planning/ROADMAP.md >/dev/null 2>&1
    git commit -m "Update ROADMAP with progress table" >/dev/null 2>&1

    run gsd-ralph merge 3
    assert_success

    # ROADMAP.md should show phase complete
    local roadmap_content
    roadmap_content=$(<.planning/ROADMAP.md)
    echo "$roadmap_content" | grep -q "Complete"
}

@test "merge with test regressions suggests rollback" {
    setup_merge_branch

    # Create a test script that always fails (simulating regression)
    cat > run-tests.sh << 'TESTSCRIPT'
#!/bin/bash
exit 1
TESTSCRIPT
    chmod +x run-tests.sh

    # Create a package.json pointing to the failing test script
    cat > package.json << 'PKG'
{
  "name": "test-project",
  "scripts": {
    "test": "./run-tests.sh"
  }
}
PKG
    git add package.json run-tests.sh >/dev/null 2>&1
    git commit -m "Add package.json with failing test" >/dev/null 2>&1

    run gsd-ralph merge 3
    # Merge itself succeeds but tests fail -- need to check output
    # The exit code depends on whether pre-merge tests also fail (they should,
    # since run-tests.sh exists on main too). So this is pre-existing failure.
    # The merge should succeed with a warning about pre-existing failures.
    assert_output --partial "Tests failing, but failures existed before merge"
}

@test "merge detects new regressions when pre-merge tests passed" {
    # Setup: create package.json with passing tests on main BEFORE branching
    mkdir -p .planning/phases/03-phase-execution
    cat > .planning/phases/03-phase-execution/03-01-PLAN.md << 'PLAN'
---
phase: 03-phase-execution
plan: 01
type: execute
wave: 1
depends_on: []
---
PLAN
    # Create package.json with test command that runs run-tests.sh
    cat > package.json << 'PKG'
{
  "name": "test-project",
  "scripts": {
    "test": "./run-tests.sh"
  }
}
PKG
    # Create a passing test script on main
    cat > run-tests.sh << 'TESTSCRIPT'
#!/bin/bash
exit 0
TESTSCRIPT
    chmod +x run-tests.sh
    git add .planning/phases/03-phase-execution/03-01-PLAN.md package.json run-tests.sh >/dev/null 2>&1
    git commit -m "Add phase 3 plan with passing tests" >/dev/null 2>&1

    # Create branch that replaces test script with a failing one
    git checkout -b "phase-3/phase-execution" >/dev/null 2>&1
    cat > run-tests.sh << 'TESTSCRIPT'
#!/bin/bash
exit 1
TESTSCRIPT
    chmod +x run-tests.sh
    echo "branch feature" > feature.txt
    git add run-tests.sh feature.txt >/dev/null 2>&1
    git commit -m "Add failing test and feature on branch" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    run gsd-ralph merge 3
    # Should fail because merge introduces regressions
    assert_failure
    assert_output --partial "regressions"
    assert_output --partial "--rollback"
}

# ---------------------------------------------------------------------------
# Execute-merge integration (Plan 04-03 tests)
# ---------------------------------------------------------------------------

@test "ralph-execute.sh calls gsd-ralph merge after completion" {
    # Check that the script contains the automatic merge call
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/ralph-execute.sh")
    echo "$script_content" | grep -q "gsd-ralph merge"
    echo "$script_content" | grep -q "Merging completed branches"
}

@test "ralph-execute.sh --no-merge skips automatic merge" {
    # Check that the script handles --no-merge flag
    local script_content
    script_content=$(<"$PROJECT_ROOT/scripts/ralph-execute.sh")
    echo "$script_content" | grep -q "no-merge"
    echo "$script_content" | grep -q "Automatic merge skipped"
}

# ---------------------------------------------------------------------------
# Terminal bell (Plan 06-01 tests)
# ---------------------------------------------------------------------------

@test "merge rings terminal bell on completion" {
    setup_merge_branch
    run gsd-ralph merge 3
    assert_success
    # BEL character (ASCII 0x07) should be in output from ring_bell
    [[ "$output" == *$'\a'* ]]
}
