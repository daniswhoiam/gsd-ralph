#!/bin/bash
# scripts/ralph-launcher.sh -- Ralph autopilot launcher
# Core functions: arg parsing, config reading, permission mapping, command building, dry-run
# Bash 3.2 compatible (no associative arrays, no ${var,,})
#
# Usage:
#   ralph-launcher.sh <gsd-command> [--dry-run] [--tier default|auto-mode|yolo]
#
# Examples:
#   ralph-launcher.sh execute-phase 11
#   ralph-launcher.sh execute-phase 11 --dry-run
#   ralph-launcher.sh execute-phase 11 --tier yolo --dry-run

set -euo pipefail

# --- Project root detection ---
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

# --- File paths ---
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
STATE_FILE="$PROJECT_ROOT/.planning/STATE.md"
CONTEXT_SCRIPT="$PROJECT_ROOT/scripts/assemble-context.sh"
VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate-config.sh"

# --- Constants ---
DEFAULT_MAX_TURNS=50
DEFAULT_PERMISSION_TIER="default"
DEFAULT_ALLOWED_TOOLS="Write,Read,Edit,Grep,Glob,Bash(*)"

# --- Mutable state (set by parse_args, read_config) ---
MAX_TURNS="$DEFAULT_MAX_TURNS"
PERMISSION_TIER="$DEFAULT_PERMISSION_TIER"
DRY_RUN=false
GSD_COMMAND=""

# --- Source config validation ---
if [ -f "$VALIDATE_SCRIPT" ]; then
    source "$VALIDATE_SCRIPT"
fi

# --- Functions ---

# Parse command-line arguments
# Sets: GSD_COMMAND, DRY_RUN, PERMISSION_TIER (override)
parse_args() {
    GSD_COMMAND=""
    DRY_RUN=false
    local tier_override=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --tier)
                if [ $# -lt 2 ]; then
                    echo "ERROR: --tier requires a value" >&2
                    return 1
                fi
                tier_override="$2"
                shift 2
                ;;
            *)
                if [ -z "$GSD_COMMAND" ]; then
                    GSD_COMMAND="$1"
                else
                    GSD_COMMAND="$GSD_COMMAND $1"
                fi
                shift
                ;;
        esac
    done

    # Apply tier override after config read (if provided)
    if [ -n "$tier_override" ]; then
        PERMISSION_TIER="$tier_override"
    fi
}

# Read Ralph config from config.json
# Sets: MAX_TURNS, PERMISSION_TIER (unless overridden by --tier)
read_config() {
    if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
        local cfg_turns cfg_tier
        cfg_turns=$(jq -r '.ralph.max_turns // empty' "$CONFIG_FILE" 2>/dev/null)
        cfg_tier=$(jq -r '.ralph.permission_tier // empty' "$CONFIG_FILE" 2>/dev/null)
        if [ -n "$cfg_turns" ]; then
            MAX_TURNS="$cfg_turns"
        fi
        if [ -n "$cfg_tier" ]; then
            PERMISSION_TIER="$cfg_tier"
        fi
    fi
}

# Build permission flags based on the current PERMISSION_TIER
# Outputs the appropriate CLI flags string
build_permission_flags() {
    case "$PERMISSION_TIER" in
        default)
            echo "--allowedTools \"$DEFAULT_ALLOWED_TOOLS\""
            ;;
        auto-mode)
            echo "--permission-mode auto"
            ;;
        yolo)
            echo "--dangerously-skip-permissions"
            ;;
        *)
            echo "ERROR: Unknown permission tier: $PERMISSION_TIER" >&2
            return 1
            ;;
    esac
}

# Translate a GSD slash command into a natural language prompt for claude -p
# Args: $1 = GSD command string (e.g., "execute-phase 11")
build_prompt() {
    local cmd="$1"
    local subcmd phase_num

    # Extract the sub-command and phase number
    subcmd=$(echo "$cmd" | awk '{print $1}')
    phase_num=$(echo "$cmd" | awk '{print $2}')

    case "$subcmd" in
        execute-phase)
            echo "You are executing Phase ${phase_num} of the GSD project plan. Read STATE.md for your current position. Follow the plan instructions for the active phase. Complete as many tasks as possible within the turn limit."
            ;;
        verify-work)
            echo "You are verifying the work completed in Phase ${phase_num}. Read STATE.md for context. Check all success criteria and test results."
            ;;
        plan-phase)
            echo "You are planning Phase ${phase_num}. Read STATE.md, the phase description from ROADMAP.md, and any existing CONTEXT.md or RESEARCH.md. Create plan files following GSD conventions."
            ;;
        *)
            echo "Execute the following GSD command: ${cmd}. Read STATE.md for current position and follow instructions."
            ;;
    esac
}

# Build the full claude -p command string
# Args: $1 = prompt, $2 = context_file, $3 = max_turns, $4 = permission_tier
build_claude_command() {
    local prompt="$1"
    local context_file="$2"
    local max_turns="$3"
    local perm_tier="$4"

    local perm_flags
    PERMISSION_TIER="$perm_tier"
    perm_flags=$(build_permission_flags)

    local cmd="env -u CLAUDECODE claude -p \"${prompt}\""
    cmd="$cmd --append-system-prompt-file \"${context_file}\""
    cmd="$cmd --max-turns ${max_turns}"
    cmd="$cmd --output-format json"
    cmd="$cmd --worktree"
    cmd="$cmd ${perm_flags}"

    echo "$cmd"
}

# Print dry-run output: command preview and config summary
# Args: $1 = command string, $2 = context file path
dry_run_output() {
    local cmd="$1"
    local context_file="$2"

    echo "=== Ralph Dry Run ==="
    echo ""
    echo "Command:"
    echo "  $cmd"
    echo ""
    echo "Context file: $context_file"
    if [ -f "$context_file" ]; then
        local lines
        lines=$(wc -l < "$context_file" | tr -d ' ')
        echo "Context lines: $lines"
    fi
    echo ""
    echo "Config:"
    echo "  max_turns: $MAX_TURNS"
    echo "  permission_tier: $PERMISSION_TIER"
    echo "  worktree: always on"
    echo ""
    echo "To execute, run without --dry-run"
}

# --- Plan 02: Loop execution engine functions ---

# Check STATE.md for phase completion status
# Args: $1 = state_file path, $2 = target_phase number
# Returns (via echo): "complete", "incomplete", "missing", or "unknown"
check_state_completion() {
    local state_file="$1"
    local target_phase="$2"

    if [ ! -f "$state_file" ]; then
        echo "missing"
        return 0
    fi

    # Extract current phase number from "Phase: N of M" line
    local current_phase
    current_phase=$(grep -E 'Phase: [0-9]+' "$state_file" | grep -oE '[0-9]+' | head -1)

    if [ -z "$current_phase" ]; then
        echo "unknown"
        return 0
    fi

    # If current phase has advanced beyond target, it's complete
    if [ "$current_phase" -gt "$target_phase" ]; then
        echo "complete"
        return 0
    fi

    # Check the status field
    local status
    status=$(grep -E 'Status: ' "$state_file" | head -1 | sed 's/.*Status: //')

    case "$status" in
        Complete*|complete*)
            echo "complete"
            ;;
        *)
            echo "incomplete"
            ;;
    esac
}

# Capture a state snapshot for progress detection
# Args: $1 = state_file path
# Returns (via echo): "phase:N|plan:N|status:X" or "unavailable"
_capture_state_snapshot() {
    local state_file="$1"

    if [ ! -f "$state_file" ]; then
        echo "unavailable"
        return 0
    fi

    local phase plan status
    phase=$(grep -E 'Phase: [0-9]+' "$state_file" | grep -oE '[0-9]+' | head -1)
    plan=$(grep -E 'Plan: [0-9]+' "$state_file" | grep -oE '[0-9]+' | head -1)
    status=$(grep -E 'Status: ' "$state_file" | head -1 | sed 's/.*Status: //')

    echo "phase:${phase:-?}|plan:${plan:-?}|status:${status:-?}"
}

# Execute a single iteration: assemble context, build command, run claude -p
# Args: $1 = prompt, $2 = max_turns, $3 = permission_tier
# Returns: exit code from claude -p invocation
execute_iteration() {
    local prompt="$1"
    local max_turns="$2"
    local perm_tier="$3"

    # Create a fresh temp file for context
    local context_file
    context_file=$(mktemp "${TMPDIR:-/tmp}/ralph-context.XXXXXX")

    # Assemble context fresh for this iteration
    if [ -x "$CONTEXT_SCRIPT" ]; then
        if ! bash "$CONTEXT_SCRIPT" "$context_file"; then
            echo "ERROR: Context assembly failed" >&2
            rm -f "$context_file"
            return 1
        fi
    else
        echo "WARNING: Context script not found: $CONTEXT_SCRIPT" >&2
        echo "# No context assembled" > "$context_file"
    fi

    # Build the claude -p command
    local cmd
    cmd=$(build_claude_command "$prompt" "$context_file" "$max_turns" "$perm_tier")

    # Execute via env -u CLAUDECODE (already included in cmd by build_claude_command)
    local exit_code=0
    bash -c "$cmd" || exit_code=$?

    # Clean up temp context file
    rm -f "$context_file"

    return $exit_code
}

# Main loop: iterate claude -p instances until STATE.md shows phase complete
# Args: $1 = gsd_command (e.g., "execute-phase 11")
# Behavior:
#   - Loops until check_state_completion returns "complete"
#   - On exit code 0: check completion
#   - On exit code non-zero: check STATE.md for progress
#     - Progress detected: continue (max-turns exhaustion, not failure)
#     - No progress: retry once, then stop
#   - Emits terminal bell on completion or unrecoverable failure
run_loop() {
    local gsd_command="$1"

    # Extract target phase number from command
    local target_phase
    target_phase=$(echo "$gsd_command" | grep -oE '[0-9]+' | head -1)
    if [ -z "$target_phase" ]; then
        target_phase="unknown"
    fi

    # Validate STATE.md exists before starting
    if [ ! -f "$STATE_FILE" ]; then
        echo "ERROR: STATE.md not found at $STATE_FILE" >&2
        printf '\a'
        return 1
    fi

    # Build the prompt once (context is reassembled each iteration)
    local prompt
    prompt=$(build_prompt "$gsd_command")

    local consecutive_no_progress=0

    while true; do
        # Capture state snapshot before iteration
        local pre_snapshot
        pre_snapshot=$(_capture_state_snapshot "$STATE_FILE")

        # Execute iteration
        local iter_exit=0
        execute_iteration "$prompt" "$MAX_TURNS" "$PERMISSION_TIER" || iter_exit=$?

        # Check completion status
        local completion
        completion=$(check_state_completion "$STATE_FILE" "$target_phase")

        if [ "$completion" = "complete" ]; then
            # Phase complete -- success
            printf '\a'
            echo "Ralph: Phase $target_phase complete."
            return 0
        fi

        if [ $iter_exit -eq 0 ]; then
            # Exit code 0 but not complete yet -- continue looping
            consecutive_no_progress=0
            continue
        fi

        # Non-zero exit: check for progress
        local post_snapshot
        post_snapshot=$(_capture_state_snapshot "$STATE_FILE")

        if [ "$pre_snapshot" != "$post_snapshot" ]; then
            # Progress detected despite non-zero exit (max-turns exhaustion)
            # Continue looping, not a retry
            consecutive_no_progress=0
            continue
        fi

        # No progress on non-zero exit -- count toward retry
        consecutive_no_progress=$((consecutive_no_progress + 1))

        if [ $consecutive_no_progress -ge 2 ]; then
            # Retry also failed with no progress -- unrecoverable
            printf '\a'
            echo "Ralph: Unrecoverable failure after retry. Check logs." >&2
            return 1
        fi

        # First failure with no progress -- retry once
        # (loop continues, next iteration is the retry)
    done
}

# --- Main execution (guarded for testability) ---
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    # Parse arguments
    parse_args "$@"

    # Read config (may adjust MAX_TURNS, PERMISSION_TIER)
    read_config

    # Validate config
    if command -v validate_ralph_config >/dev/null 2>&1; then
        validate_ralph_config "$CONFIG_FILE"
    fi

    if [ -z "$GSD_COMMAND" ]; then
        echo "ERROR: No GSD command specified" >&2
        echo "Usage: ralph-launcher.sh <gsd-command> [--dry-run] [--tier default|auto-mode|yolo]" >&2
        exit 1
    fi

    # Build prompt from GSD command
    PROMPT=$(build_prompt "$GSD_COMMAND")

    # Assemble context
    CONTEXT_FILE=$(mktemp "${TMPDIR:-/tmp}/ralph-context.XXXXXX")
    if [ -x "$CONTEXT_SCRIPT" ]; then
        bash "$CONTEXT_SCRIPT" "$CONTEXT_FILE"
    else
        echo "WARNING: Context script not found or not executable: $CONTEXT_SCRIPT" >&2
        echo "# No context assembled" > "$CONTEXT_FILE"
    fi

    # Build the claude command
    CLAUDE_CMD=$(build_claude_command "$PROMPT" "$CONTEXT_FILE" "$MAX_TURNS" "$PERMISSION_TIER")

    if [ "$DRY_RUN" = "true" ]; then
        dry_run_output "$CLAUDE_CMD" "$CONTEXT_FILE"
        rm -f "$CONTEXT_FILE"
        exit 0
    fi

    # Clean up the initial context file (run_loop assembles fresh context each iteration)
    rm -f "$CONTEXT_FILE"

    # Execute the loop
    run_loop "$GSD_COMMAND"
fi
