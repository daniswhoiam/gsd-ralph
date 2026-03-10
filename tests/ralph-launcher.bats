#!/usr/bin/env bats
# tests/ralph-launcher.bats -- Tests for launcher arg parsing, command building, dry-run

setup() {
    load 'test_helper/common'
    load 'test_helper/ralph-helpers'
    _common_setup
    REAL_PROJECT_ROOT="$(get_real_project_root)"

    # Create a git repo so PROJECT_ROOT detection works
    create_test_repo

    # Create required scripts directory with validate-config.sh stub
    mkdir -p scripts
    cat > scripts/validate-config.sh <<'STUBEOF'
validate_ralph_config() { return 0; }
STUBEOF

    # Source the launcher script (functions only, guarded main)
    source "$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh"
}

teardown() {
    _common_teardown
}

# --- parse_args tests ---

@test "parse_args extracts GSD command from arguments" {
    parse_args execute-phase 11
    [ "$GSD_COMMAND" = "execute-phase 11" ]
}

@test "parse_args detects --dry-run flag" {
    parse_args execute-phase 11 --dry-run
    [ "$DRY_RUN" = "true" ]
    [ "$GSD_COMMAND" = "execute-phase 11" ]
}

@test "parse_args extracts --tier override" {
    parse_args execute-phase 11 --tier yolo
    [ "$PERMISSION_TIER" = "yolo" ]
    [ "$GSD_COMMAND" = "execute-phase 11" ]
}

# --- read_config tests ---

@test "read_config reads max_turns from config.json" {
    create_ralph_config true 75 "default"
    PROJECT_ROOT="$TEST_TEMP_DIR"
    CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
    read_config
    [ "$MAX_TURNS" = "75" ]
}

@test "read_config reads permission_tier from config.json" {
    create_ralph_config true 50 "auto-mode"
    PROJECT_ROOT="$TEST_TEMP_DIR"
    CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
    read_config
    [ "$PERMISSION_TIER" = "auto-mode" ]
}

@test "read_config uses defaults when config missing" {
    PROJECT_ROOT="$TEST_TEMP_DIR"
    CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
    MAX_TURNS="$DEFAULT_MAX_TURNS"
    PERMISSION_TIER="$DEFAULT_PERMISSION_TIER"
    read_config
    [ "$MAX_TURNS" = "50" ]
    [ "$PERMISSION_TIER" = "default" ]
}

# --- build_prompt tests ---

@test "build_prompt translates execute-phase N into natural language prompt" {
    run build_prompt "execute-phase 11"
    assert_success
    assert_output --partial 'Phase 11'
    assert_output --partial 'STATE.md'
}

@test "build_prompt translates verify-work N correctly" {
    run build_prompt "verify-work 5"
    assert_success
    assert_output --partial 'verifying'
    assert_output --partial 'Phase 5'
}

@test "build_prompt translates plan-phase N correctly" {
    run build_prompt "plan-phase 3"
    assert_success
    assert_output --partial 'planning Phase 3'
    assert_output --partial 'ROADMAP.md'
}

@test "build_prompt handles unrecognized commands with default" {
    run build_prompt "some-unknown-cmd 7"
    assert_success
    assert_output --partial 'some-unknown-cmd 7'
    assert_output --partial 'STATE.md'
}

# --- build_claude_command tests ---

@test "build_claude_command includes --worktree flag" {
    run build_claude_command "test prompt" "/tmp/ctx.md" 50 "default"
    assert_success
    assert_output --partial '--worktree'
}

@test "build_claude_command includes --max-turns from config" {
    run build_claude_command "test prompt" "/tmp/ctx.md" 75 "default"
    assert_success
    assert_output --partial '--max-turns 75'
}

@test "build_claude_command includes --output-format json" {
    run build_claude_command "test prompt" "/tmp/ctx.md" 50 "default"
    assert_success
    assert_output --partial '--output-format json'
}

@test "build_claude_command includes --append-system-prompt-file with context file" {
    run build_claude_command "test prompt" "/tmp/my-ctx.md" 50 "default"
    assert_success
    assert_output --partial '--append-system-prompt-file'
    assert_output --partial '/tmp/my-ctx.md'
}

@test "build_claude_command uses correct permission flags for each tier" {
    run build_claude_command "test prompt" "/tmp/ctx.md" 50 "default"
    assert_output --partial '--allowedTools'

    run build_claude_command "test prompt" "/tmp/ctx.md" 50 "auto-mode"
    assert_output --partial '--permission-mode auto'

    run build_claude_command "test prompt" "/tmp/ctx.md" 50 "yolo"
    assert_output --partial '--dangerously-skip-permissions'
}

@test "build_claude_command prepends env -u CLAUDECODE" {
    run build_claude_command "test prompt" "/tmp/ctx.md" 50 "default"
    assert_success
    assert_output --partial 'env -u CLAUDECODE'
}

# --- dry_run_output tests ---

@test "dry_run_output prints command without executing" {
    create_context_file "Some context content here"
    local cmd="env -u CLAUDECODE claude -p \"test\" --worktree --max-turns 50"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    run dry_run_output "$cmd" "$TEST_TEMP_DIR/context.md"
    assert_success
    assert_output --partial '=== Ralph Dry Run ==='
    assert_output --partial 'claude -p'
}

@test "dry_run_output shows config summary" {
    create_context_file "Context lines here"
    local cmd="env -u CLAUDECODE claude -p \"test\" --worktree --max-turns 50"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    run dry_run_output "$cmd" "$TEST_TEMP_DIR/context.md"
    assert_success
    assert_output --partial 'max_turns: 50'
    assert_output --partial 'permission_tier: default'
    assert_output --partial 'worktree: always on'
}
