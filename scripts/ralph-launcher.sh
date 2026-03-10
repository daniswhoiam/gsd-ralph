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

    # Execution loop will be implemented in Plan 02
    echo "ERROR: Execution loop not yet implemented (Plan 02)" >&2
    echo "Use --dry-run to preview the command" >&2
    rm -f "$CONTEXT_FILE"
    exit 1
fi
