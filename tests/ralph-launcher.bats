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

# ============================================================
# Plan 02: Loop execution engine tests
# ============================================================

# --- check_state_completion tests ---

@test "check_state_completion returns complete when phase number > target" {
    create_mock_state_advanced 12 1 "Executing"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    run check_state_completion "$STATE_FILE" 11
    assert_success
    assert_output "complete"
}

@test "check_state_completion returns complete when status is Complete" {
    create_mock_state_advanced 11 2 "Complete"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    run check_state_completion "$STATE_FILE" 11
    assert_success
    assert_output "complete"
}

@test "check_state_completion returns incomplete when phase is current and executing" {
    create_mock_state_advanced 11 1 "Executing"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    run check_state_completion "$STATE_FILE" 11
    assert_success
    assert_output "incomplete"
}

@test "check_state_completion returns missing when STATE.md does not exist" {
    run check_state_completion "$TEST_TEMP_DIR/.planning/nonexistent-STATE.md" 11
    assert_success
    assert_output "missing"
}

@test "check_state_completion returns unknown when phase number not found" {
    mkdir -p "$TEST_TEMP_DIR/.planning"
    echo "# Empty state file with no phase info" > "$TEST_TEMP_DIR/.planning/STATE.md"
    run check_state_completion "$TEST_TEMP_DIR/.planning/STATE.md" 11
    assert_success
    assert_output "unknown"
}

# --- execute_iteration tests ---

@test "execute_iteration calls assemble-context.sh with temp file path" {
    create_mock_assemble_context 0
    # Create a mock claude that records its args and succeeds
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<'MOCKEOF'
#!/bin/bash
echo '{"type":"result","result":"done","num_turns":5}'
exit 0
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    # Track assemble-context.sh calls (use unquoted heredoc to expand TEST_TEMP_DIR at write time)
    cat > "$TEST_TEMP_DIR/scripts/assemble-context.sh" <<TRACKEOF
#!/bin/bash
echo "ASSEMBLE_CALLED:\$1" >> "$TEST_TEMP_DIR/assemble-calls.log"
echo "# Mock context" > "\$1"
exit 0
TRACKEOF
    chmod +x "$TEST_TEMP_DIR/scripts/assemble-context.sh"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"

    run execute_iteration "test prompt" 50 "default"
    assert_success

    # Verify assemble-context.sh was called with a file path
    assert_file_exists "$TEST_TEMP_DIR/assemble-calls.log"
    run cat "$TEST_TEMP_DIR/assemble-calls.log"
    assert_output --partial "ASSEMBLE_CALLED:"
}

@test "execute_iteration calls claude -p command via env -u CLAUDECODE" {
    create_mock_assemble_context 0
    # Create a mock claude that logs invocation details (unquoted heredoc for path expansion)
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<MOCKEOF
#!/bin/bash
echo "CLAUDE_CALLED" >> "$TEST_TEMP_DIR/claude-calls.log"
echo '{"type":"result","result":"done","num_turns":5}'
exit 0
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"

    run execute_iteration "test prompt" 50 "default"
    assert_success

    # Verify claude was called
    assert_file_exists "$TEST_TEMP_DIR/claude-calls.log"
}

@test "execute_iteration returns the exit code from claude -p" {
    create_mock_assemble_context 0
    # Create a mock claude that exits with code 1
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<'MOCKEOF'
#!/bin/bash
echo '{"type":"result","result":"failed","num_turns":50}'
exit 1
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"

    run execute_iteration "test prompt" 50 "default"
    assert_failure
}

# --- run_loop tests ---

@test "run_loop stops when check_state_completion returns complete" {
    # STATE.md starts at phase 11, plan 1 -- mock claude will advance it to complete
    create_mock_state_advanced 11 2 "Complete"
    create_mock_assemble_context 0

    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<'MOCKEOF'
#!/bin/bash
echo '{"type":"result","result":"done","num_turns":5}'
exit 0
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    GSD_COMMAND="execute-phase 11"

    run run_loop "execute-phase 11"
    assert_success
    assert_output --partial "complete"
}

@test "run_loop retries once on failure when STATE.md shows no progress" {
    # STATE.md stays the same (no progress) across failures
    create_mock_state_advanced 11 1 "Executing"
    create_mock_assemble_context 0

    # Mock claude always fails
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<'MOCKEOF'
#!/bin/bash
echo '{"type":"result","result":"error","num_turns":5}'
exit 1
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    GSD_COMMAND="execute-phase 11"

    run run_loop "execute-phase 11"
    assert_failure
    assert_output --partial "Unrecoverable failure"
}

@test "run_loop continues on non-zero exit when STATE.md shows progress" {
    # Start at phase 11 plan 1
    create_mock_state_advanced 11 1 "Executing"
    create_mock_assemble_context 0

    # Mock claude: first call fails but advances state, second call succeeds and completes
    mkdir -p "$TEST_TEMP_DIR/bin"
    local iteration_file="$TEST_TEMP_DIR/iteration_count"
    echo "0" > "$iteration_file"

    cat > "$TEST_TEMP_DIR/bin/claude" <<MOCKEOF
#!/bin/bash
ITER=\$(cat "$iteration_file")
ITER=\$((ITER + 1))
echo "\$ITER" > "$iteration_file"
if [ "\$ITER" -eq 1 ]; then
    # First iteration: advance plan but exit non-zero (max-turns hit)
    cat > "$TEST_TEMP_DIR/.planning/STATE.md" <<STATEEOF
---
gsd_state_version: 1.0
status: executing
---

# Project State

## Current Position

Phase: 11 of 12
Plan: 2 of 2
Status: Executing
STATEEOF
    echo '{"type":"result","result":"partial","num_turns":50}'
    exit 1
elif [ "\$ITER" -eq 2 ]; then
    # Second iteration: complete
    cat > "$TEST_TEMP_DIR/.planning/STATE.md" <<STATEEOF
---
gsd_state_version: 1.0
status: executing
---

# Project State

## Current Position

Phase: 11 of 12
Plan: 2 of 2
Status: Complete
STATEEOF
    echo '{"type":"result","result":"done","num_turns":10}'
    exit 0
fi
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    GSD_COMMAND="execute-phase 11"

    run run_loop "execute-phase 11"
    assert_success
    assert_output --partial "complete"
    # Verify it ran 2 iterations (progress on first, complete on second)
    run cat "$iteration_file"
    assert_output "2"
}

@test "run_loop stops after retry also fails" {
    create_mock_state_advanced 11 1 "Executing"
    create_mock_assemble_context 0

    # Track iteration count
    local iteration_file="$TEST_TEMP_DIR/iteration_count"
    echo "0" > "$iteration_file"

    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<MOCKEOF
#!/bin/bash
ITER=\$(cat "$iteration_file")
ITER=\$((ITER + 1))
echo "\$ITER" > "$iteration_file"
echo '{"type":"result","result":"error","num_turns":5}'
exit 1
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    GSD_COMMAND="execute-phase 11"

    run run_loop "execute-phase 11"
    assert_failure
    # Should have run original + 1 retry = 2 iterations
    run cat "$iteration_file"
    assert_output "2"
}

@test "run_loop emits terminal bell on completion" {
    create_mock_state_advanced 11 2 "Complete"
    create_mock_assemble_context 0

    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<'MOCKEOF'
#!/bin/bash
echo '{"type":"result","result":"done","num_turns":5}'
exit 0
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    GSD_COMMAND="execute-phase 11"

    run run_loop "execute-phase 11"
    assert_success
    # Check for bell character (octal 007) in output
    echo "$output" | od -c | grep -q '\\a' || echo "$output" | grep -qP '\x07' || [[ "$output" == *$'\a'* ]]
}

@test "run_loop emits terminal bell on unrecoverable failure" {
    create_mock_state_advanced 11 1 "Executing"
    create_mock_assemble_context 0

    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<'MOCKEOF'
#!/bin/bash
echo '{"type":"result","result":"error","num_turns":5}'
exit 1
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    GSD_COMMAND="execute-phase 11"

    run run_loop "execute-phase 11"
    assert_failure
    # Check for bell character in output (combined stdout+stderr)
    echo "$output" | od -c | grep -q '\\a' || echo "$output" | grep -qP '\x07' || [[ "$output" == *$'\a'* ]]
}

@test "run_loop reassembles context before each iteration" {
    # Two iterations: first makes progress, second completes
    create_mock_state_advanced 11 1 "Executing"

    # Track assemble calls (unquoted heredoc for path expansion)
    mkdir -p "$TEST_TEMP_DIR/scripts"
    cat > "$TEST_TEMP_DIR/scripts/assemble-context.sh" <<TRACKEOF
#!/bin/bash
echo "ASSEMBLE_CALL" >> "$TEST_TEMP_DIR/assemble-calls.log"
echo "# Mock context" > "\$1"
exit 0
TRACKEOF
    chmod +x "$TEST_TEMP_DIR/scripts/assemble-context.sh"

    local iteration_file="$TEST_TEMP_DIR/iteration_count"
    echo "0" > "$iteration_file"

    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<MOCKEOF
#!/bin/bash
ITER=\$(cat "$iteration_file")
ITER=\$((ITER + 1))
echo "\$ITER" > "$iteration_file"
if [ "\$ITER" -eq 1 ]; then
    cat > "$TEST_TEMP_DIR/.planning/STATE.md" <<STATEEOF
---
gsd_state_version: 1.0
status: executing
---

# Project State

## Current Position

Phase: 11 of 12
Plan: 2 of 2
Status: Executing
STATEEOF
    echo '{"type":"result","result":"partial","num_turns":50}'
    exit 1
else
    cat > "$TEST_TEMP_DIR/.planning/STATE.md" <<STATEEOF
---
gsd_state_version: 1.0
status: executing
---

# Project State

## Current Position

Phase: 11 of 12
Plan: 2 of 2
Status: Complete
STATEEOF
    echo '{"type":"result","result":"done","num_turns":10}'
    exit 0
fi
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    GSD_COMMAND="execute-phase 11"

    run run_loop "execute-phase 11"
    assert_success

    # Verify assemble-context.sh was called at least twice (once per iteration)
    local call_count
    call_count=$(wc -l < "$TEST_TEMP_DIR/assemble-calls.log" | tr -d ' ')
    [ "$call_count" -ge 2 ]
}
