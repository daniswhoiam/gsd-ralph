#!/usr/bin/env bats
# tests/frontmatter.bats -- Unit tests for lib/frontmatter.sh

setup() {
    load 'test_helper/common'
    _common_setup

    VERBOSE=false
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/frontmatter.sh"
}

teardown() {
    _common_teardown
}

# --- parse_plan_frontmatter: basic extraction ---

@test "parse_plan_frontmatter extracts wave from plan" {
    parse_plan_frontmatter "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md"
    assert_equal "$FM_WAVE" "1"
}

@test "parse_plan_frontmatter extracts phase from plan" {
    parse_plan_frontmatter "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md"
    assert_equal "$FM_PHASE" "test-phase"
}

@test "parse_plan_frontmatter extracts plan number" {
    parse_plan_frontmatter "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md"
    assert_equal "$FM_PLAN" "01"
}

@test "parse_plan_frontmatter extracts type" {
    parse_plan_frontmatter "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-01-PLAN.md"
    assert_equal "$FM_TYPE" "execute"
}

# --- parse_plan_frontmatter: depends_on ---

@test "parse_plan_frontmatter extracts inline array depends_on" {
    parse_plan_frontmatter "$PROJECT_ROOT/tests/test_helper/fixtures/multi-plan/02-03-PLAN.md"
    assert_equal "$FM_DEPENDS_ON" "01"
}

@test "parse_plan_frontmatter extracts quoted inline array depends_on" {
    local plan="$TEST_TEMP_DIR/plan.md"
    cat > "$plan" << 'EOF'
---
phase: test
plan: 02
wave: 2
depends_on: ["01", "02"]
---
EOF
    parse_plan_frontmatter "$plan"
    assert_equal "$FM_DEPENDS_ON" "01 02"
}

@test "parse_plan_frontmatter extracts empty depends_on" {
    local plan="$TEST_TEMP_DIR/plan.md"
    cat > "$plan" << 'EOF'
---
phase: test
plan: 01
wave: 1
depends_on: []
---
EOF
    parse_plan_frontmatter "$plan"
    assert_equal "$FM_DEPENDS_ON" ""
}

# --- parse_plan_frontmatter: files_modified ---

@test "parse_plan_frontmatter extracts files_modified multi-line list" {
    local plan="$TEST_TEMP_DIR/plan.md"
    cat > "$plan" << 'EOF'
---
phase: test
plan: 01
wave: 1
files_modified:
  - lib/foo.sh
  - lib/bar.sh
  - tests/foo.bats
---
EOF
    parse_plan_frontmatter "$plan"
    assert_equal "$FM_FILES_MODIFIED" "lib/foo.sh lib/bar.sh tests/foo.bats"
}

@test "parse_plan_frontmatter extracts files_modified inline array" {
    local plan="$TEST_TEMP_DIR/plan.md"
    cat > "$plan" << 'EOF'
---
phase: test
plan: 01
wave: 1
files_modified: ["lib/foo.sh", "lib/bar.sh"]
---
EOF
    parse_plan_frontmatter "$plan"
    assert_equal "$FM_FILES_MODIFIED" "lib/foo.sh lib/bar.sh"
}

# --- parse_plan_frontmatter: edge cases ---

@test "parse_plan_frontmatter handles missing fields gracefully" {
    local plan="$TEST_TEMP_DIR/plan.md"
    cat > "$plan" << 'EOF'
---
phase: test
plan: 01
---
EOF
    parse_plan_frontmatter "$plan"
    assert_equal "$FM_PHASE" "test"
    assert_equal "$FM_PLAN" "01"
    assert_equal "$FM_WAVE" ""
    assert_equal "$FM_DEPENDS_ON" ""
    assert_equal "$FM_TYPE" ""
}

@test "parse_plan_frontmatter returns 1 for no frontmatter" {
    local plan="$TEST_TEMP_DIR/plan.md"
    echo "# Just a markdown file" > "$plan"
    run parse_plan_frontmatter "$plan"
    assert_failure
}

@test "parse_plan_frontmatter returns 1 for missing file" {
    run parse_plan_frontmatter "$TEST_TEMP_DIR/nonexistent.md"
    assert_failure
    assert_output --partial "Plan file not found"
}

@test "parse_plan_frontmatter resets globals between calls" {
    local plan1="$TEST_TEMP_DIR/plan1.md"
    cat > "$plan1" << 'EOF'
---
phase: phase1
plan: 01
wave: 1
depends_on: ["03"]
---
EOF
    local plan2="$TEST_TEMP_DIR/plan2.md"
    cat > "$plan2" << 'EOF'
---
phase: phase2
plan: 02
---
EOF

    parse_plan_frontmatter "$plan1"
    assert_equal "$FM_DEPENDS_ON" "03"

    parse_plan_frontmatter "$plan2"
    assert_equal "$FM_PHASE" "phase2"
    assert_equal "$FM_DEPENDS_ON" ""
    assert_equal "$FM_WAVE" ""
}

@test "parse_plan_frontmatter handles real plan file with full frontmatter" {
    parse_plan_frontmatter "$PROJECT_ROOT/.planning/milestones/v1.0-phases/02-prompt-generation/02-01-PLAN.md"
    assert_equal "$FM_PHASE" "02-prompt-generation"
    assert_equal "$FM_PLAN" "01"
    assert_equal "$FM_WAVE" "1"
    assert_equal "$FM_TYPE" "execute"
}
