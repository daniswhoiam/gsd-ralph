#!/usr/bin/env bats
# tests/execute.bats -- Integration tests for gsd-ralph execute command

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

# Helper: create a two-plan phase with dependency chain (sequential)
setup_sequential_phase() {
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
  <name>Task 1: Create frontmatter parser</name>
  <files>lib/frontmatter.sh</files>
  <action>Build the frontmatter parser module.</action>
  <verify>ShellCheck passes.</verify>
  <done>Parser created.</done>
</task>

<task type="auto">
  <name>Task 2: Write frontmatter tests</name>
  <files>tests/frontmatter.bats</files>
  <action>Write unit tests.</action>
  <verify>Tests pass.</verify>
  <done>Tests passing.</done>
</task>

</tasks>
PLAN

    cat > .planning/phases/03-phase-execution/03-02-PLAN.md << 'PLAN'
---
phase: 03-phase-execution
plan: 02
type: execute
wave: 2
depends_on: ["01"]
---

<tasks>

<task type="auto">
  <name>Task 1: Implement execute command</name>
  <files>lib/commands/execute.sh</files>
  <action>Build the execute command.</action>
  <verify>Command runs.</verify>
  <done>Execute works.</done>
</task>

</tasks>
PLAN
}

# Helper: create a single-plan phase
setup_single_plan_phase() {
    mkdir -p .planning/phases/04-merge
    cat > .planning/phases/04-merge/PLAN.md << 'PLAN'
---
phase: 04-merge
plan: 01
type: execute
wave: 1
---

<tasks>

<task type="auto">
  <name>Task 1: Merge command</name>
  <files>lib/commands/merge.sh</files>
  <action>Implement merge.</action>
  <verify>Tests pass.</verify>
  <done>Merge works.</done>
</task>

</tasks>
PLAN
}

# --- Success cases ---

@test "execute creates branch with correct name" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success

    run git branch --list "phase-3/phase-execution"
    assert_output --partial "phase-3/phase-execution"
}

@test "execute generates protocol PROMPT.md" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success
    assert [ -f ".ralph/PROMPT.md" ]

    run cat .ralph/PROMPT.md
    assert_output --partial "GSD Execution Protocol"
}

@test "execute generates combined fix_plan.md with tasks from all plans" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success
    assert [ -f ".ralph/fix_plan.md" ]

    run cat .ralph/fix_plan.md
    # Should have tasks from both plans
    assert_output --partial "Create frontmatter parser"
    assert_output --partial "Write frontmatter tests"
    assert_output --partial "Implement execute command"
}

@test "execute creates execution log file" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success
    assert [ -f ".ralph/logs/execution-log.md" ]

    run cat .ralph/logs/execution-log.md
    assert_output --partial "Execution Log"
}

@test "execute updates STATE.md" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success

    run cat .planning/STATE.md
    assert_output --partial "Phase: 3"
}

@test "execute commits setup changes" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success

    run git log --oneline -1
    assert_output --partial "set up execution environment"
}

@test "execute prints launch instructions" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success
    assert_output --partial "ralph"
}

@test "execute reports strategy analysis to user" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success
    assert_output --partial "sequential"
}

# --- Error cases ---

@test "execute fails without phase argument" {
    run gsd-ralph execute
    assert_failure
    assert_output --partial "Phase number required"
}

@test "execute fails for nonexistent phase" {
    run gsd-ralph execute 99
    assert_failure
    assert_output --partial "Phase 99 not found"
}

@test "execute fails without init" {
    rm -rf .ralph
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_failure
    assert_output --partial "init"
}

# --- Single-plan phase ---

@test "execute handles single-plan phase" {
    setup_single_plan_phase
    run gsd-ralph execute 4
    assert_success
    assert [ -f ".ralph/PROMPT.md" ]
    assert [ -f ".ralph/fix_plan.md" ]

    run cat .ralph/fix_plan.md
    assert_output --partial "Merge command"
}

# --- Dry run ---

@test "execute --dry-run doesn't create branch" {
    setup_sequential_phase
    run gsd-ralph execute 3 --dry-run
    assert_success

    # Should still be on original branch (main/master)
    local current_branch
    current_branch=$(git branch --show-current)
    [[ "$current_branch" != "phase-3/phase-execution" ]]
}

# --- Fix plan quality ---

@test "combined fix_plan.md groups tasks by plan" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success

    run cat .ralph/fix_plan.md
    assert_output --partial "## Plan 01"
    assert_output --partial "## Plan 02"
}

@test "combined fix_plan.md includes summary creation tasks" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success

    run cat .ralph/fix_plan.md
    assert_output --partial "SUMMARY.md"
}

# --- PROMPT.md quality ---

@test "protocol PROMPT.md contains project name" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success

    local repo_name
    repo_name=$(basename "$TEST_TEMP_DIR")
    run cat .ralph/PROMPT.md
    assert_output --partial "$repo_name"
}

@test "protocol PROMPT.md contains file permissions table" {
    setup_sequential_phase
    run gsd-ralph execute 3
    assert_success

    run cat .ralph/PROMPT.md
    assert_output --partial "File Permissions"
    assert_output --partial "PROJECT.md"
    assert_output --partial "ROADMAP.md"
}
