#!/usr/bin/env bats
# tests/context-assembly.bats -- Tests for scripts/assemble-context.sh
# Covers AUTO-03: Context assembly for --append-system-prompt-file injection

setup() {
    load 'test_helper/common'
    _common_setup

    # Create a git repo in the temp directory for git rev-parse
    create_test_repo

    # Store the path to assemble-context.sh from the real project
    ASSEMBLE_SCRIPT="$PROJECT_ROOT/scripts/assemble-context.sh"
}

teardown() {
    _common_teardown
}

# -- Error handling --

@test "exits with error when STATE.md is missing" {
    # No .planning/STATE.md created
    mkdir -p .planning/phases

    run "$ASSEMBLE_SCRIPT"

    assert_failure
    assert_output --partial "STATE.md"
}

# -- Output header --

@test "outputs Ralph Autopilot Context header" {
    create_gsd_structure

    run "$ASSEMBLE_SCRIPT"

    assert_success
    assert_line --index 0 "# Ralph Autopilot Context"
}

# -- Current GSD State section --

@test "outputs Current GSD State section containing STATE.md content" {
    create_gsd_structure

    run "$ASSEMBLE_SCRIPT"

    assert_success
    assert_output --partial "## Current GSD State"
    assert_output --partial "# Project State"
}

# -- Active Phase Plans section --

@test "outputs Active Phase Plans section when plan files exist" {
    create_gsd_structure
    mkdir -p ".planning/phases/1-test-phase"
    cat > ".planning/phases/1-test-phase/1-01-PLAN.md" <<'PLAN'
---
phase: 1-test-phase
plan: 01
---
Test plan content
PLAN

    run "$ASSEMBLE_SCRIPT"

    assert_success
    assert_output --partial "## Active Phase Plans"
}

@test "includes plan file content in output" {
    create_gsd_structure
    mkdir -p ".planning/phases/1-test-phase"
    cat > ".planning/phases/1-test-phase/1-01-PLAN.md" <<'PLAN'
---
phase: 1-test-phase
plan: 01
---
Unique plan content for verification
PLAN

    run "$ASSEMBLE_SCRIPT"

    assert_success
    assert_output --partial "Unique plan content for verification"
}

@test "includes plan filename as subsection header" {
    create_gsd_structure
    mkdir -p ".planning/phases/1-test-phase"
    cat > ".planning/phases/1-test-phase/1-01-PLAN.md" <<'PLAN'
Test plan
PLAN

    run "$ASSEMBLE_SCRIPT"

    assert_success
    assert_output --partial "### 1-01-PLAN.md"
}

# -- Missing phase directory --

@test "handles missing phase directory gracefully" {
    # Create STATE.md with phase 99 which has no directory
    mkdir -p .planning/phases
    cat > .planning/STATE.md <<'EOF'
# Project State
## Current Position
Phase: 99 of 100 (Nonexistent Phase)
EOF

    run "$ASSEMBLE_SCRIPT"

    assert_success
    # Should have state content but no plans section
    assert_output --partial "## Current GSD State"
    refute_output --partial "## Active Phase Plans"
}

# -- Phase number extraction --

@test "extracts correct phase number from STATE.md Phase: N of M format" {
    mkdir -p .planning/phases
    cat > .planning/STATE.md <<'EOF'
# Project State
## Current Position
Phase: 10 of 12 (Core Architecture)
EOF

    mkdir -p ".planning/phases/10-core-architecture"
    cat > ".planning/phases/10-core-architecture/10-01-PLAN.md" <<'PLAN'
Phase 10 plan content
PLAN

    run "$ASSEMBLE_SCRIPT"

    assert_success
    assert_output --partial "Phase 10 plan content"
}

# -- Output to stdout --

@test "writes to stdout by default" {
    create_gsd_structure

    run "$ASSEMBLE_SCRIPT"

    assert_success
    # Output should contain the header (proves it went to stdout)
    assert_output --partial "# Ralph Autopilot Context"
}

# -- Output to file --

@test "writes to file when output path argument is provided" {
    create_gsd_structure

    local output_file="$TEST_TEMP_DIR/context-output.md"

    run "$ASSEMBLE_SCRIPT" "$output_file"

    assert_success
    assert_file_exists "$output_file"
    run cat "$output_file"
    assert_output --partial "# Ralph Autopilot Context"
    assert_output --partial "## Current GSD State"
}

# -- Multiple plan files --

@test "includes all plan files in phase directory" {
    create_gsd_structure
    mkdir -p ".planning/phases/1-test-phase"
    cat > ".planning/phases/1-test-phase/1-01-PLAN.md" <<'PLAN'
First plan content
PLAN
    cat > ".planning/phases/1-test-phase/1-02-PLAN.md" <<'PLAN'
Second plan content
PLAN

    run "$ASSEMBLE_SCRIPT"

    assert_success
    assert_output --partial "First plan content"
    assert_output --partial "Second plan content"
}
