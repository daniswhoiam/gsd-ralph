#!/usr/bin/env bats
# tests/strategy.bats -- Unit tests for lib/strategy.sh

setup() {
    load 'test_helper/common'
    _common_setup

    VERBOSE=false
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/discovery.sh"
    source "$PROJECT_ROOT/lib/frontmatter.sh"
    source "$PROJECT_ROOT/lib/strategy.sh"
}

teardown() {
    _common_teardown
}

# Helper: create a sequential phase (plan 01 wave 1, plan 02 wave 2 depends on 01)
create_sequential_phase() {
    local dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$dir"
    cat > "$dir/03-01-PLAN.md" << 'EOF'
---
phase: test
plan: 01
wave: 1
depends_on: []
---
<tasks><task type="auto"><name>Task 1: First</name></task></tasks>
EOF
    cat > "$dir/03-02-PLAN.md" << 'EOF'
---
phase: test
plan: 02
wave: 2
depends_on: ["01"]
---
<tasks><task type="auto"><name>Task 1: Second</name></task></tasks>
EOF
    echo "$dir"
}

# Helper: create a parallel phase (plan 01 and 02 both wave 1, plan 03 wave 2)
create_parallel_phase() {
    local dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$dir"
    cat > "$dir/03-01-PLAN.md" << 'EOF'
---
phase: test
plan: 01
wave: 1
depends_on: []
---
<tasks><task type="auto"><name>Task 1: Alpha</name></task></tasks>
EOF
    cat > "$dir/03-02-PLAN.md" << 'EOF'
---
phase: test
plan: 02
wave: 1
depends_on: []
---
<tasks><task type="auto"><name>Task 1: Beta</name></task></tasks>
EOF
    cat > "$dir/03-03-PLAN.md" << 'EOF'
---
phase: test
plan: 03
wave: 2
depends_on: ["01", "02"]
---
<tasks><task type="auto"><name>Task 1: Gamma</name></task></tasks>
EOF
    echo "$dir"
}

# Helper: create a single-plan phase
create_single_plan_phase() {
    local dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$dir"
    cat > "$dir/PLAN.md" << 'EOF'
---
phase: test
plan: 01
wave: 1
---
<tasks><task type="auto"><name>Task 1: Solo</name></task></tasks>
EOF
    echo "$dir"
}

# --- analyze_phase_strategy ---

@test "analyze_phase_strategy detects sequential phase" {
    local dir
    dir=$(create_sequential_phase)
    analyze_phase_strategy "$dir"
    assert_equal "$STRATEGY_MODE" "sequential"
}

@test "analyze_phase_strategy detects parallel phase" {
    local dir
    dir=$(create_parallel_phase)
    analyze_phase_strategy "$dir"
    assert_equal "$STRATEGY_MODE" "parallel"
}

@test "analyze_phase_strategy counts waves correctly for sequential" {
    local dir
    dir=$(create_sequential_phase)
    analyze_phase_strategy "$dir"
    assert_equal "$STRATEGY_WAVE_COUNT" "2"
}

@test "analyze_phase_strategy counts waves correctly for parallel" {
    local dir
    dir=$(create_parallel_phase)
    analyze_phase_strategy "$dir"
    assert_equal "$STRATEGY_WAVE_COUNT" "2"
}

@test "analyze_phase_strategy returns sequential for single plan" {
    local dir
    dir=$(create_single_plan_phase)
    analyze_phase_strategy "$dir"
    assert_equal "$STRATEGY_MODE" "sequential"
    assert_equal "$STRATEGY_WAVE_COUNT" "1"
}

@test "analyze_phase_strategy builds correct plan order for sequential" {
    local dir
    dir=$(create_sequential_phase)
    analyze_phase_strategy "$dir"
    assert_equal "${#STRATEGY_PLAN_ORDER[@]}" "2"
    [[ "$(basename "${STRATEGY_PLAN_ORDER[0]}")" == "03-01-PLAN.md" ]]
    [[ "$(basename "${STRATEGY_PLAN_ORDER[1]}")" == "03-02-PLAN.md" ]]
}

@test "analyze_phase_strategy builds correct plan order for parallel" {
    local dir
    dir=$(create_parallel_phase)
    analyze_phase_strategy "$dir"
    assert_equal "${#STRATEGY_PLAN_ORDER[@]}" "3"
    # Wave 1 plans come first, then wave 2
    [[ "$(basename "${STRATEGY_PLAN_ORDER[0]}")" == "03-01-PLAN.md" ]]
    [[ "$(basename "${STRATEGY_PLAN_ORDER[1]}")" == "03-02-PLAN.md" ]]
    [[ "$(basename "${STRATEGY_PLAN_ORDER[2]}")" == "03-03-PLAN.md" ]]
}

@test "analyze_phase_strategy returns 1 for empty directory" {
    local dir="$TEST_TEMP_DIR/empty"
    mkdir -p "$dir"
    run analyze_phase_strategy "$dir"
    assert_failure
}

# --- validate_phase_dependencies ---

@test "validate_phase_dependencies passes for valid sequential phase" {
    local dir
    dir=$(create_sequential_phase)
    run validate_phase_dependencies "$dir"
    assert_success
}

@test "validate_phase_dependencies passes for valid parallel phase" {
    local dir
    dir=$(create_parallel_phase)
    run validate_phase_dependencies "$dir"
    assert_success
}

@test "validate_phase_dependencies detects missing dependency" {
    local dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$dir"
    cat > "$dir/03-01-PLAN.md" << 'EOF'
---
phase: test
plan: 01
wave: 2
depends_on: ["99"]
---
<tasks></tasks>
EOF
    run validate_phase_dependencies "$dir"
    assert_failure
    assert_output --partial "does not exist"
}

@test "validate_phase_dependencies detects circular dependency" {
    local dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$dir"
    cat > "$dir/03-01-PLAN.md" << 'EOF'
---
phase: test
plan: 01
wave: 1
depends_on: ["02"]
---
<tasks></tasks>
EOF
    cat > "$dir/03-02-PLAN.md" << 'EOF'
---
phase: test
plan: 02
wave: 1
depends_on: ["01"]
---
<tasks></tasks>
EOF
    run validate_phase_dependencies "$dir"
    assert_failure
    assert_output --partial "Circular dependency"
}

@test "validate_phase_dependencies passes for no dependencies" {
    local dir
    dir=$(create_single_plan_phase)
    run validate_phase_dependencies "$dir"
    assert_success
}

# --- print_phase_structure ---

@test "print_phase_structure reports strategy mode" {
    local dir
    dir=$(create_sequential_phase)
    run print_phase_structure "$dir"
    assert_success
    assert_output --partial "sequential"
}

@test "print_phase_structure reports parallel mode" {
    local dir
    dir=$(create_parallel_phase)
    run print_phase_structure "$dir"
    assert_success
    assert_output --partial "parallel"
}
