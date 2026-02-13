#!/bin/bash
# ralph-cleanup.sh - Remove worktrees and branches for a completed phase
#
# Usage: ./scripts/ralph-cleanup.sh <phase_number>

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
echo " Cleanup Phase ${PHASE_NUM} Worktrees"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# List what will be removed
echo "Will remove:"
for wt in "$PARENT_DIR"/${REPO_NAME}-p${PHASE_NUM}-*; do
    if [ -d "$wt" ]; then
        BRANCH=$(git -C "$wt" branch --show-current 2>/dev/null || echo "unknown")
        echo "  - $(basename "$wt") (branch: $BRANCH)"
    fi
done

echo ""
read -p "Confirm removal? [y/N]: " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Aborted."
    exit 1
fi

echo ""
for wt in "$PARENT_DIR"/${REPO_NAME}-p${PHASE_NUM}-*; do
    if [ -d "$wt" ]; then
        NAME=$(basename "$wt")
        BRANCH=$(git -C "$wt" branch --show-current 2>/dev/null || echo "")

        echo -e "${GREEN}▶ Removing $NAME...${NC}"

        # Remove worktree
        git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
        echo "  Worktree removed"

        # Delete branch (if merged)
        if [ -n "$BRANCH" ]; then
            if git branch -d "$BRANCH" 2>/dev/null; then
                echo "  Branch deleted"
            else
                echo -e "  ${YELLOW}Branch not deleted (may not be merged)${NC}"
                echo "  To force delete: git branch -D $BRANCH"
            fi
        fi
    fi
done

echo ""
echo -e "${GREEN}✓ Phase ${PHASE_NUM} cleanup complete${NC}"
echo ""

# Prune stale worktree references
git worktree prune

echo "Worktree list:"
git worktree list
echo ""
