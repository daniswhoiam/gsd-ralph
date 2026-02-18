#!/usr/bin/env bats
# tests/prompt.bats -- Unit tests for lib/prompt.sh

setup() {
    load 'test_helper/common'
    _common_setup

    # Source dependencies
    VERBOSE=false
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/templates.sh"
    source "$PROJECT_ROOT/lib/prompt.sh"
}

teardown() {
    _common_teardown
}

# --- extract_tasks_to_fix_plan ---

@test "extract_tasks_to_fix_plan extracts tasks from multi-plan fixture" {
    local output="$TEST_TEMP_DIR/fix_plan.md"
    extract_tasks_to_fix_plan \
        "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md" \
        "$output"
    local line_count
    line_count=$(wc -l < "$output" | tr -d ' ')
    assert_equal "$line_count" "2"
}

@test "extract_tasks_to_fix_plan extracts task names correctly" {
    local output="$TEST_TEMP_DIR/fix_plan.md"
    extract_tasks_to_fix_plan \
        "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md" \
        "$output"

    run cat "$output"
    assert_line --index 0 "- [ ] Task 1: Create the first component"
    assert_line --index 1 "- [ ] Task 2: Add tests for the component"
}

@test "extract_tasks_to_fix_plan handles empty plan" {
    local output="$TEST_TEMP_DIR/fix_plan.md"
    extract_tasks_to_fix_plan \
        "$PROJECT_ROOT/tests/test_helper/fixtures/edge-cases/empty-plan.md" \
        "$output"
    # Output file should be empty (no tasks)
    [[ ! -s "$output" ]]
}

@test "extract_tasks_to_fix_plan returns 1 for missing file" {
    local output="$TEST_TEMP_DIR/fix_plan.md"
    run extract_tasks_to_fix_plan \
        "$TEST_TEMP_DIR/nonexistent.md" \
        "$output"
    assert_failure
    assert_output --partial "Plan file not found"
}

@test "extract_tasks_to_fix_plan handles single plan fixture" {
    local output="$TEST_TEMP_DIR/fix_plan.md"
    extract_tasks_to_fix_plan \
        "$PROJECT_ROOT/tests/test_helper/fixtures/single-plan/PLAN.md" \
        "$output"

    local line_count
    line_count=$(wc -l < "$output" | tr -d ' ')
    assert_equal "$line_count" "1"
}

# --- append_scope_lock ---

@test "append_scope_lock adds scope section" {
    local output="$TEST_TEMP_DIR/prompt.md"
    echo "# Base content" > "$output"
    append_scope_lock "$output" "2" "01" "02-01-PLAN.md" ".planning/phases/02-prompt-generation"

    run cat "$output"
    assert_output --partial "Scope Lock"
    assert_output --partial "Phase 2, Plan 01"
    assert_output --partial "02-01-PLAN.md"
}

# --- append_merge_order ---

@test "append_merge_order adds section for multi-plan" {
    local output="$TEST_TEMP_DIR/prompt.md"
    echo "# Base content" > "$output"
    append_merge_order "$output" "01" "3"

    run cat "$output"
    assert_output --partial "Merge Order"
    assert_output --partial "Plan 01 of 3"
}

@test "append_merge_order skips for single plan" {
    local output="$TEST_TEMP_DIR/prompt.md"
    echo "# Base content" > "$output"
    append_merge_order "$output" "01" "1"

    run cat "$output"
    refute_output --partial "Merge Order"
}

# --- append_peer_visibility ---

@test "append_peer_visibility lists peer paths for multi-plan" {
    local output="$TEST_TEMP_DIR/prompt.md"
    echo "# Base content" > "$output"
    append_peer_visibility "$output" "2" "01" "3" "myrepo" "/home/user/projects"

    run cat "$output"
    assert_output --partial "Read-Only Peer Visibility"
    assert_output --partial "myrepo-p2-02"
    assert_output --partial "myrepo-p2-03"
    refute_output --partial "myrepo-p2-01"
}

@test "append_peer_visibility notes no peers for single plan" {
    local output="$TEST_TEMP_DIR/prompt.md"
    echo "# Base content" > "$output"
    append_peer_visibility "$output" "2" "01" "1" "myrepo" "/home/user/projects"

    run cat "$output"
    assert_output --partial "only plan"
    refute_output --partial "Read-Only Peer Visibility"
}

# --- generate_prompt_md ---

@test "generate_prompt_md creates complete file" {
    local output="$TEST_TEMP_DIR/prompt.md"
    local template="$TEST_TEMP_DIR/template.md"
    echo "# Instructions -- {{PROJECT_NAME}}" > "$template"

    generate_prompt_md "$output" "$template" \
        "2" "01" "2" "02-01-PLAN.md" ".planning/phases/02-test" \
        "testproject" "bash" "make test" "make lint" \
        "testproject" "/tmp/projects"

    [[ -f "$output" ]]
    run cat "$output"
    assert_output --partial "Scope Lock"
    assert_output --partial "testproject"
}

@test "generate_prompt_md uses template variables" {
    local output="$TEST_TEMP_DIR/prompt.md"
    local template="$TEST_TEMP_DIR/template.md"
    cat > "$template" << 'TMPL'
# {{PROJECT_NAME}}
Lang: {{PROJECT_LANG}}
Test: {{TEST_CMD}}
Build: {{BUILD_CMD}}
TMPL

    generate_prompt_md "$output" "$template" \
        "1" "01" "1" "PLAN.md" ".planning/phases/01-test" \
        "myapp" "rust" "cargo test" "cargo build" \
        "myapp" "/tmp"

    run cat "$output"
    assert_output --partial "# myapp"
    assert_output --partial "Lang: rust"
    assert_output --partial "Test: cargo test"
    assert_output --partial "Build: cargo build"
}
