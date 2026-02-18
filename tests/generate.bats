#!/usr/bin/env bats
# tests/generate.bats -- Integration tests for gsd-ralph generate command

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

# Helper: create a multi-plan phase with 2 numbered plans
setup_multi_plan_phase() {
    mkdir -p .planning/phases/02-test-phase
    cat > .planning/phases/02-test-phase/02-01-PLAN.md << 'PLAN'
---
phase: 02-test-phase
plan: 01
type: execute
wave: 1
---

<tasks>

<task type="auto">
  <name>Task 1: Create the widget</name>
  <files>src/widget.sh</files>
  <action>Create the widget file.</action>
  <verify>File exists.</verify>
  <done>Widget created.</done>
</task>

<task type="auto">
  <name>Task 2: Test the widget</name>
  <files>tests/widget.bats</files>
  <action>Write widget tests.</action>
  <verify>Tests pass.</verify>
  <done>Tests passing.</done>
</task>

</tasks>
PLAN

    cat > .planning/phases/02-test-phase/02-02-PLAN.md << 'PLAN'
---
phase: 02-test-phase
plan: 02
type: execute
wave: 2
depends_on: ["01"]
---

<tasks>

<task type="auto">
  <name>Task 1: Build the pipeline</name>
  <files>lib/pipeline.sh</files>
  <action>Create pipeline module.</action>
  <verify>Module loads.</verify>
  <done>Pipeline created.</done>
</task>

</tasks>
PLAN
}

# Helper: create a single-plan phase with bare PLAN.md
setup_single_plan_phase() {
    mkdir -p .planning/phases/03-single-phase
    cat > .planning/phases/03-single-phase/PLAN.md << 'PLAN'
---
phase: 03-single-phase
plan: 01
type: execute
wave: 1
---

<tasks>

<task type="auto">
  <name>Task 1: Solo task</name>
  <files>src/solo.sh</files>
  <action>Create the solo file.</action>
  <verify>File exists.</verify>
  <done>Solo file created.</done>
</task>

</tasks>
PLAN
}

# --- Success cases ---

@test "generate creates output directory" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    assert [ -d ".ralph/generated" ]
}

@test "generate creates per-plan directories" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    assert [ -d ".ralph/generated/plan-01" ]
    assert [ -d ".ralph/generated/plan-02" ]
}

@test "generate creates PROMPT.md per plan" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    assert [ -f ".ralph/generated/plan-01/PROMPT.md" ]
    assert [ -s ".ralph/generated/plan-01/PROMPT.md" ]
}

@test "generate creates fix_plan.md per plan" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    assert [ -f ".ralph/generated/plan-01/fix_plan.md" ]
    run cat .ralph/generated/plan-01/fix_plan.md
    assert_output --partial "- [ ]"
}

@test "generate creates AGENT.md per plan" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    assert [ -f ".ralph/generated/plan-01/AGENT.md" ]
}

@test "generate creates .ralphrc per plan" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    assert [ -f ".ralph/generated/plan-01/.ralphrc" ]
}

@test "generate creates status.json per plan" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    assert [ -f ".ralph/generated/plan-01/status.json" ]
    # Verify valid JSON
    run jq '.status' .ralph/generated/plan-01/status.json
    assert_success
    assert_output '"ready"'
}

@test "generate PROMPT.md contains project name" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    local repo_name
    repo_name=$(basename "$TEST_TEMP_DIR")
    run cat .ralph/generated/plan-01/PROMPT.md
    assert_output --partial "$repo_name"
}

@test "generate PROMPT.md contains scope lock" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    run cat .ralph/generated/plan-01/PROMPT.md
    assert_output --partial "Scope Lock"
    assert_output --partial "Phase 2, Plan 01"
}

@test "generate PROMPT.md contains peer visibility for multi-plan" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    run cat .ralph/generated/plan-01/PROMPT.md
    assert_output --partial "Read-Only Peer Visibility"
    assert_output --partial "p2-02"
}

@test "generate fix_plan.md has correct task count" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    local line_count
    line_count=$(wc -l < .ralph/generated/plan-01/fix_plan.md | tr -d ' ')
    assert_equal "$line_count" "2"
}

# --- Failure cases ---

@test "generate fails without phase argument" {
    run gsd-ralph generate
    assert_failure
    assert_output --partial "Phase number required"
}

@test "generate fails for nonexistent phase" {
    run gsd-ralph generate 99
    assert_failure
    assert_output --partial "Phase 99 not found"
}

@test "generate fails without init" {
    rm -rf .ralph
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_failure
    assert_output --partial "init"
}

# --- Single-plan phase ---

@test "generate handles single-plan phase" {
    setup_single_plan_phase
    run gsd-ralph generate 3
    assert_success
    assert [ -f ".ralph/generated/plan-01/PROMPT.md" ]
    run cat .ralph/generated/plan-01/PROMPT.md
    assert_output --partial "only plan"
    refute_output --partial "Read-Only Peer Visibility"
}

# --- Template quality ---

@test "generate .ralphrc has no unresolved placeholders" {
    setup_multi_plan_phase
    run gsd-ralph generate 2
    assert_success
    run grep '{{' .ralph/generated/plan-01/.ralphrc
    assert_failure
}

@test "generate supports --output-dir flag" {
    setup_multi_plan_phase
    run gsd-ralph generate 2 --output-dir "$TEST_TEMP_DIR/custom-output"
    assert_success
    assert [ -d "$TEST_TEMP_DIR/custom-output/plan-01" ]
    assert [ -f "$TEST_TEMP_DIR/custom-output/plan-01/PROMPT.md" ]
}
