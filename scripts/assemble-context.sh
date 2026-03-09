#!/bin/bash
# scripts/assemble-context.sh -- Build GSD context for --append-system-prompt-file
#
# Reads STATE.md and active phase plan files, producing a combined context
# blob suitable for Claude Code's --append-system-prompt-file flag.
#
# Usage:
#   assemble-context.sh              # Output to stdout
#   assemble-context.sh /path/to/out # Output to file
#
# Context scope (user decision): STATE.md + active phase plans ONLY.
# Claude discovers PROJECT.md/REQUIREMENTS.md from CLAUDE.md if needed.

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$PROJECT_ROOT/.planning/STATE.md"
OUTPUT_FILE="${1:-/dev/stdout}"

# Validate STATE.md exists
if [ ! -f "$STATE_FILE" ]; then
    printf "ERROR: %s not found\n" "$STATE_FILE" >&2
    exit 1
fi

{
    printf "# Ralph Autopilot Context\n\n"
    printf "## Current GSD State\n\n"
    cat "$STATE_FILE"
    printf "\n\n"

    # Extract phase number from STATE.md "Phase: N of M" line
    phase_num=$(grep -oE 'Phase: [0-9]+' "$STATE_FILE" | grep -oE '[0-9]+' | head -1)

    if [ -n "$phase_num" ]; then
        # Find phase directory (GSD NN-slug format)
        phase_dir=$(find "$PROJECT_ROOT/.planning/phases" -maxdepth 1 -type d -name "${phase_num}-*" 2>/dev/null | head -1)

        if [ -n "$phase_dir" ] && [ -d "$phase_dir" ]; then
            # Check if any plan files exist before emitting section header
            has_plans=false
            for plan_file in "$phase_dir"/*-PLAN.md; do
                if [ -f "$plan_file" ]; then
                    has_plans=true
                    break
                fi
            done

            if [ "$has_plans" = true ]; then
                printf "## Active Phase Plans\n\n"
                for plan_file in "$phase_dir"/*-PLAN.md; do
                    if [ -f "$plan_file" ]; then
                        printf "### %s\n\n" "$(basename "$plan_file")"
                        cat "$plan_file"
                        printf "\n\n"
                    fi
                done
            fi
        fi
    fi
} > "$OUTPUT_FILE"
