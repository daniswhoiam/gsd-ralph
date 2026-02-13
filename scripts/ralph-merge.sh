#!/bin/bash
# ralph-merge.sh - Merge all completed plan branches for a phase back to main
#
# Usage: ./scripts/ralph-merge.sh <phase_number>

set -e

PHASE_NUM="$1"
REPO_NAME=$(basename "$PWD")
PARENT_DIR=$(dirname "$PWD")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ -z "$PHASE_NUM" ]; then
    echo "Usage: $0 <phase_number>"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Merge Phase ${PHASE_NUM} Branches"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check all worktrees are complete
ALL_COMPLETE=true
for wt in "$PARENT_DIR"/${REPO_NAME}-p${PHASE_NUM}-*; do
    if [ -d "$wt" ]; then
        if [ -f "$wt/.ralph/status.json" ]; then
            STATUS=$(jq -r '.status // "unknown"' "$wt/.ralph/status.json" 2>/dev/null || echo "unknown")
            if [ "$STATUS" != "complete" ] && [ "$STATUS" != "completed" ]; then
                echo -e "${YELLOW}Warning: $(basename "$wt") status is '$STATUS' (not complete)${NC}"
                ALL_COMPLETE=false
            fi
        else
            echo -e "${YELLOW}Warning: $(basename "$wt") has no status file${NC}"
            ALL_COMPLETE=false
        fi
    fi
done

if [ "$ALL_COMPLETE" = false ]; then
    echo ""
    read -p "Some worktrees are not complete. Continue anyway? [y/N]: " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Aborted."
        exit 1
    fi
fi

# Ensure we're on main
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ] && [ "$CURRENT_BRANCH" != "master" ]; then
    echo "Switching to main branch..."
    git checkout main 2>/dev/null || git checkout master
fi

# Remove untracked .ralph/ runtime files that worktrees may have committed.
# These cause "untracked working tree files would be overwritten" errors.
if [ -d ".ralph" ]; then
    echo "Cleaning untracked .ralph/ runtime files before merge..."
    rm -f .ralph/fix_plan.md .ralph/status.json .ralph/.ralph_session .ralph/.call_count .ralph/.last_reset 2>/dev/null || true
fi

# Merge each branch
echo ""
echo "Merging branches..."
echo ""

for wt in "$PARENT_DIR"/${REPO_NAME}-p${PHASE_NUM}-*; do
    if [ -d "$wt" ]; then
        BRANCH=$(git -C "$wt" branch --show-current 2>/dev/null || echo "")
        if [ -n "$BRANCH" ]; then
            echo -e "${GREEN}▶ Merging $BRANCH...${NC}"

            if git merge "$BRANCH" --no-edit; then
                echo -e "  ${GREEN}✓ Merged successfully${NC}"
            else
                echo ""
                echo -e "  ${RED}✗ Merge conflict in $BRANCH${NC}"
                echo ""
                echo "  Conflicted files:"
                git diff --name-only --diff-filter=U 2>/dev/null | sed 's/^/    /'
                echo ""
                echo "  To resolve:"
                echo "    1. Edit the conflicted files (look for <<<<<<< markers)"
                echo "    2. git add <resolved-files>"
                echo "    3. git commit --no-edit"
                echo "    4. Re-run: ./scripts/ralph-merge.sh ${PHASE_NUM}"
                echo ""
                echo -e "  ${YELLOW}Tip: STATE.md conflicts are common with parallel plans.${NC}"
                echo -e "  ${YELLOW}Combine both plans' progress into one unified state.${NC}"
                exit 1
            fi
        fi
    fi
done

echo ""
echo -e "${GREEN}✓ All Phase ${PHASE_NUM} branches merged to main${NC}"
echo ""
echo "Next steps:"
echo "  1. Review the merged changes: git log --oneline -10"
echo "  2. Run tests to verify everything works"
echo "  3. Clean up worktrees: ./scripts/ralph-cleanup.sh ${PHASE_NUM}"
echo "  4. Update STATE.md to mark Phase ${PHASE_NUM} complete"
echo "  5. Start next phase: ./scripts/ralph-execute.sh $((PHASE_NUM + 1))"
echo ""
