#!/usr/bin/env bats
# tests/guidance.bats -- Tests verifying context-sensitive "Next:" guidance
# output across all commands (GUID-01, GUID-02)

setup() {
    load 'test_helper/common'
    _common_setup

    create_test_repo
    create_gsd_structure
    mkdir -p .ralph/logs
}

teardown() {
    _common_teardown
}

# Helper: create a minimal phase with a single plan (for execute/generate tests)
setup_guidance_phase() {
    mkdir -p .planning/phases/03-phase-execution
    cat > .planning/phases/03-phase-execution/03-01-PLAN.md << 'PLAN'
---
phase: 03-phase-execution
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - test.txt
autonomous: true
must_haves:
  truths: []
  artifacts: []
---

<tasks>

<task type="auto">
  <name>Task 1: Test task</name>
  <files>test.txt</files>
  <action>Create a test file.</action>
  <verify>File exists.</verify>
  <done>File created.</done>
</task>

</tasks>
PLAN
}

# ---------------------------------------------------------------------------
# print_guidance helper
# ---------------------------------------------------------------------------

@test "print_guidance outputs formatted message" {
    export GSD_RALPH_HOME="$PROJECT_ROOT"
    source "$PROJECT_ROOT/lib/common.sh"

    run print_guidance "test message"
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "test message"
}

# ---------------------------------------------------------------------------
# init guidance
# ---------------------------------------------------------------------------

@test "init success shows guidance" {
    # Fresh project -- no .ralph/ yet
    rm -rf .ralph
    run gsd-ralph init
    assert_success
    assert_output --partial "Next:"
    # Should NOT contain old multi-line "Next steps:" format
    refute_output --partial "Next steps:"
}

@test "init already initialized shows guidance" {
    # First init
    run gsd-ralph init
    assert_success
    # Second init without --force
    run gsd-ralph init
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "reinitialize"
}

# ---------------------------------------------------------------------------
# execute guidance
# ---------------------------------------------------------------------------

@test "execute dry-run shows guidance" {
    setup_guidance_phase
    run gsd-ralph execute 3 --dry-run
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "execute"
}

@test "execute success shows guidance" {
    setup_guidance_phase
    run gsd-ralph execute 3
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "ralph"
}

# ---------------------------------------------------------------------------
# generate guidance
# ---------------------------------------------------------------------------

@test "generate success shows guidance" {
    setup_guidance_phase
    run gsd-ralph generate 3
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "generated"
}

# ---------------------------------------------------------------------------
# merge guidance
# ---------------------------------------------------------------------------

# Helper: create a phase branch for merge tests
setup_merge_guidance() {
    setup_guidance_phase
    # Commit the phase directory so merge can discover it
    git add -A >/dev/null 2>&1
    git commit -m "Add phase 3 plan" >/dev/null 2>&1

    # Create a branch with a committed change
    git checkout -b "phase-3/phase-execution" >/dev/null 2>&1
    echo "branch content" > branch-file.txt
    git add branch-file.txt >/dev/null 2>&1
    git commit -m "Add branch file" >/dev/null 2>&1

    # Switch back to main
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    # Disable auto-push to avoid push attempts in tests
    echo 'AUTO_PUSH=false' > .ralphrc
    git add .ralphrc >/dev/null 2>&1
    git commit -m "Disable auto-push" >/dev/null 2>&1
}

@test "merge no unmerged branches shows guidance" {
    setup_guidance_phase
    git add -A >/dev/null 2>&1
    git commit -m "Setup" >/dev/null 2>&1
    # No phase branches exist -- nothing to merge
    echo 'AUTO_PUSH=false' > .ralphrc
    git add .ralphrc >/dev/null 2>&1
    git commit -m "Disable auto-push" >/dev/null 2>&1

    run gsd-ralph merge 3
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "execute"
}

@test "merge full success shows guidance" {
    setup_merge_guidance

    run gsd-ralph merge 3
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "cleanup"
}

@test "merge dry-run shows guidance" {
    setup_merge_guidance

    run gsd-ralph merge 3 --dry-run
    assert_success
    assert_output --partial "Next:"
}

@test "merge rollback shows guidance" {
    setup_merge_guidance

    # First do a merge to create rollback point
    run gsd-ralph merge 3
    assert_success

    # Recreate the branch so rollback has something to test
    # Actually, rollback works from the rollback file, so just run it
    run gsd-ralph merge 3 --rollback
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "re-run"
}

# ---------------------------------------------------------------------------
# cleanup guidance
# ---------------------------------------------------------------------------

# Helper: set up cleanup environment
setup_cleanup_guidance() {
    local phase_num="${1:-5}"
    mkdir -p ".planning/phases/0${phase_num}-test-phase"
    git add -A >/dev/null 2>&1
    git commit -m "Add phase $phase_num directory" >/dev/null 2>&1 || true
}

@test "cleanup nothing to clean shows no guidance" {
    setup_cleanup_guidance 5
    run gsd-ralph cleanup 5 --force
    assert_success
    # Nothing happened, nothing to suggest
    refute_output --partial "Next:"
}

@test "cleanup success shows guidance" {
    setup_cleanup_guidance 5
    local branch_name="phase-5/test-phase"
    # Create a branch
    git checkout -b "$branch_name" >/dev/null 2>&1
    echo "content for $branch_name" > phase-5-test-phase-file.txt
    git add -A >/dev/null 2>&1
    git commit -m "Add file on $branch_name" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    # Register the branch
    export GSD_RALPH_HOME="$PROJECT_ROOT"
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/cleanup/registry.sh"
    register_worktree "5" "/tmp/fake-worktree" "$branch_name"

    run gsd-ralph cleanup 5 --force
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "cleaned up"
}

@test "cleanup unregistered branches without force shows guidance" {
    setup_cleanup_guidance 5
    # Create an unregistered branch (no registry entry)
    git checkout -b "phase-5/test-phase" >/dev/null 2>&1
    echo "content" > unregistered-file.txt
    git add -A >/dev/null 2>&1
    git commit -m "Add unregistered branch file" >/dev/null 2>&1
    git checkout main >/dev/null 2>&1 || git checkout master >/dev/null 2>&1

    run gsd-ralph cleanup 5
    assert_success
    assert_output --partial "Next:"
    assert_output --partial "--force"
}

# ---------------------------------------------------------------------------
# Context-sensitivity test (GUID-02)
# ---------------------------------------------------------------------------

@test "guidance is context-sensitive across commands" {
    # Capture init guidance
    rm -rf .ralph
    run gsd-ralph init
    assert_success
    local init_guidance
    # Extract the line containing "Next:"
    init_guidance=$(echo "$output" | grep "Next:" | head -1)

    # Recreate state for generate
    setup_guidance_phase
    run gsd-ralph generate 3
    assert_success
    local generate_guidance
    generate_guidance=$(echo "$output" | grep "Next:" | head -1)

    # The two guidance messages should be different (context-sensitive)
    [[ "$init_guidance" != "$generate_guidance" ]]
}
