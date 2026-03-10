#!/bin/bash
# scripts/ralph-hook.sh -- PreToolUse hook: deny AskUserQuestion in autopilot mode
# Defense-in-depth behind SKILL.md Rule 1 ("Never Ask Questions")
# Bash 3.2 compatible
set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

# If empty input, exit silently (defensive)
if [ -z "$INPUT" ]; then
    exit 0
fi

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""')

if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
    # Extract the question text for audit logging
    QUESTION=$(echo "$INPUT" | jq -r '.tool_input.question // .tool_input.questions // "unknown"')
    TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S")

    # Log to audit file
    AUDIT_LOG="${RALPH_AUDIT_FILE:-.ralph/audit.log}"
    mkdir -p "$(dirname "$AUDIT_LOG")"
    echo "[$TIMESTAMP] DENIED AskUserQuestion: \"$QUESTION\"" >> "$AUDIT_LOG"

    # Return deny decision with guidance
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: "AskUserQuestion is blocked in autopilot mode. Pick the first option or log the blocker and exit."
        }
    }'
    exit 0
fi

# All other tools: allow (exit 0 with no output)
exit 0
