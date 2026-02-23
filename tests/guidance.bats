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
