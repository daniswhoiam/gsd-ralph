#!/usr/bin/env bats
# tests/discovery.bats -- Unit tests for lib/discovery.sh

setup() {
    load 'test_helper/common'
    _common_setup

    # Source dependencies
    VERBOSE=false
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/discovery.sh"
}

teardown() {
    _common_teardown
}

# --- find_phase_dir ---

@test "find_phase_dir finds phase by number" {
    mkdir -p "$TEST_TEMP_DIR/.planning/phases/02-prompt-generation"

    run find_phase_dir 2 "$TEST_TEMP_DIR/.planning/phases"
    assert_success

    # Verify PHASE_DIR was set by calling directly (not via run)
    find_phase_dir 2 "$TEST_TEMP_DIR/.planning/phases"
    assert_equal "$PHASE_DIR" "$TEST_TEMP_DIR/.planning/phases/02-prompt-generation"
}

@test "find_phase_dir returns 1 for missing phase" {
    mkdir -p "$TEST_TEMP_DIR/.planning/phases"

    run find_phase_dir 99 "$TEST_TEMP_DIR/.planning/phases"
    assert_failure

    find_phase_dir 99 "$TEST_TEMP_DIR/.planning/phases" || true
    assert_equal "$PHASE_DIR" ""
}

@test "find_phase_dir zero-pads single digit" {
    mkdir -p "$TEST_TEMP_DIR/.planning/phases/03-test-phase"

    find_phase_dir 3 "$TEST_TEMP_DIR/.planning/phases"
    assert_equal "$PHASE_DIR" "$TEST_TEMP_DIR/.planning/phases/03-test-phase"
}

# --- discover_plan_files ---

@test "discover_plan_files finds numbered plans" {
    local phase_dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$phase_dir"
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md" "$phase_dir/"
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-02-PLAN.md" "$phase_dir/"
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-03-PLAN.md" "$phase_dir/"

    discover_plan_files "$phase_dir"
    assert_equal "$PLAN_COUNT" 3
    assert_equal "${#PLAN_FILES[@]}" 3
}

@test "discover_plan_files falls back to PLAN.md" {
    local phase_dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$phase_dir"
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/single-plan/PLAN.md" "$phase_dir/"

    discover_plan_files "$phase_dir"
    assert_equal "$PLAN_COUNT" 1
    assert_equal "${PLAN_FILES[0]}" "$phase_dir/PLAN.md"
}

@test "discover_plan_files returns 1 for empty directory" {
    local phase_dir="$TEST_TEMP_DIR/empty-phase"
    mkdir -p "$phase_dir"

    run discover_plan_files "$phase_dir"
    assert_failure

    discover_plan_files "$phase_dir" || true
    assert_equal "$PLAN_COUNT" 0
}

@test "discover_plan_files ignores non-plan files" {
    local phase_dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$phase_dir"
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/single-plan/PLAN.md" "$phase_dir/"
    # Create a file that should NOT match the numbered plan glob
    echo "# Not a plan" > "$phase_dir/RESEARCH-PLAN.md"

    discover_plan_files "$phase_dir"
    # Should find only PLAN.md via fallback, not RESEARCH-PLAN.md
    assert_equal "$PLAN_COUNT" 1
    assert_equal "${PLAN_FILES[0]}" "$phase_dir/PLAN.md"
}

@test "discover_plan_files returns plans in sorted order" {
    local phase_dir="$TEST_TEMP_DIR/phase"
    mkdir -p "$phase_dir"
    # Create files in reverse order to test sorting
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-03-PLAN.md" "$phase_dir/"
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md" "$phase_dir/"
    cp "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-02-PLAN.md" "$phase_dir/"

    discover_plan_files "$phase_dir"
    assert_equal "$PLAN_COUNT" 3
    # Verify sorted order by basename
    [[ "$(basename "${PLAN_FILES[0]}")" == "02-01-PLAN.md" ]]
    [[ "$(basename "${PLAN_FILES[1]}")" == "02-02-PLAN.md" ]]
    [[ "$(basename "${PLAN_FILES[2]}")" == "02-03-PLAN.md" ]]
}

# --- plan_id_from_filename ---

@test "plan_id_from_filename extracts ID from numbered plan" {
    run plan_id_from_filename "02-01-PLAN.md"
    assert_success
    assert_output "01"
}

@test "plan_id_from_filename handles bare PLAN.md" {
    run plan_id_from_filename "PLAN.md"
    assert_success
    assert_output "01"
}

@test "plan_id_from_filename extracts from full path" {
    run plan_id_from_filename "/some/path/03-02-PLAN.md"
    assert_success
    assert_output "02"
}
