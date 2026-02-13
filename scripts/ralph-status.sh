#!/bin/bash
# ralph-status.sh - Check status of all worktrees for a phase
#
# Usage: ./scripts/ralph-status.sh <phase_number>

set -e

PHASE_NUM="$1"
REPO_NAME=$(basename "$PWD")
PARENT_DIR=$(dirname "$PWD")

if [ -z "$PHASE_NUM" ]; then
    echo "Usage: $0 <phase_number>"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Phase ${PHASE_NUM} Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

printf "%-30s %-12s %-20s\n" "Worktree" "Status" "Last Activity"
echo "─────────────────────────────────────────────────────────────────"

for wt in "$PARENT_DIR"/${REPO_NAME}-p${PHASE_NUM}-*; do
    if [ -d "$wt" ]; then
        NAME=$(basename "$wt")

        if [ -f "$wt/.ralph/status.json" ]; then
            STATUS=$(jq -r '.status // "unknown"' "$wt/.ralph/status.json" 2>/dev/null || echo "error")
            LAST=$(jq -r '.last_activity // "unknown"' "$wt/.ralph/status.json" 2>/dev/null || echo "unknown")
            BLOCKED=$(jq -r '.blocked_reason // ""' "$wt/.ralph/status.json" 2>/dev/null || echo "")
        else
            STATUS="not_started"
            LAST="-"
            BLOCKED=""
        fi

        # Color code status
        case "$STATUS" in
            "complete"|"completed")
                STATUS_COLOR="\033[0;32m${STATUS}\033[0m"  # Green
                ;;
            "blocked"|"BLOCKED")
                STATUS_COLOR="\033[1;33m${STATUS}\033[0m"  # Yellow
                ;;
            "running"|"active")
                STATUS_COLOR="\033[0;34m${STATUS}\033[0m"  # Blue
                ;;
            "error"|"failed")
                STATUS_COLOR="\033[0;31m${STATUS}\033[0m"  # Red
                ;;
            *)
                STATUS_COLOR="$STATUS"
                ;;
        esac

        printf "%-30s " "$NAME"
        echo -e "${STATUS_COLOR}"

        if [ -n "$BLOCKED" ] && [ "$BLOCKED" != "null" ]; then
            echo "   └─ Blocked: $BLOCKED"
        fi
    fi
done

echo ""
echo "─────────────────────────────────────────────────────────────────"

# Summary
TOTAL=$(find "$PARENT_DIR" -maxdepth 1 -type d -name "${REPO_NAME}-p${PHASE_NUM}-*" 2>/dev/null | wc -l | tr -d ' ')
COMPLETE=0
BLOCKED=0
RUNNING=0

for wt in "$PARENT_DIR"/${REPO_NAME}-p${PHASE_NUM}-*; do
    if [ -d "$wt" ] && [ -f "$wt/.ralph/status.json" ]; then
        STATUS=$(jq -r '.status // "unknown"' "$wt/.ralph/status.json" 2>/dev/null || echo "unknown")
        case "$STATUS" in
            "complete"|"completed") ((COMPLETE++)) ;;
            "blocked"|"BLOCKED") ((BLOCKED++)) ;;
            "running"|"active") ((RUNNING++)) ;;
        esac
    fi
done

echo "Summary: ${COMPLETE}/${TOTAL} complete, ${RUNNING} running, ${BLOCKED} blocked"
echo ""
