#!/bin/bash
# ralph-execute - Orchestrates Ralph phase execution
#
# This script guides you through the entire execution workflow:
# 1. Planning a phase (if not done)
# 2. Creating worktrees
# 3. Starting Ralph instances
# 4. Monitoring progress
# 5. Merging completed work
#
# Usage: ./scripts/ralph-execute.sh <phase_number>
# Example: ./scripts/ralph-execute.sh 1

set -e

# Parse arguments
PHASE_NUM=""
NO_MERGE=false

for arg in "$@"; do
    case "$arg" in
        --no-merge) NO_MERGE=true ;;
        -*)         echo "Unknown option: $arg"; exit 1 ;;
        *)
            if [ -z "$PHASE_NUM" ]; then
                PHASE_NUM="$arg"
            fi
            ;;
    esac
done

REPO_NAME=$(basename "$PWD")
PARENT_DIR=$(dirname "$PWD")
PLANNING_DIR="$PWD"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_step() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE} $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_action() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

wait_for_enter() {
    echo ""
    read -p "Press ENTER when ready to continue..."
}

# Find phase directory by phase number.
# Supports both GSD format (NN-slug, e.g., 01-project-initialization)
# and legacy format (phase-N).
find_phase_dir() {
    local phase_num="$1"
    local padded
    padded=$(printf "%02d" "$phase_num")

    # Try GSD format first: NN-slug
    local dir
    dir=$(ls -d .planning/phases/${padded}-* 2>/dev/null | head -1)
    if [ -n "$dir" ] && [ -d "$dir" ]; then
        echo "$dir"
        return 0
    fi

    # Fallback: phase-N format (legacy)
    if [ -d ".planning/phases/phase-${phase_num}" ]; then
        echo ".planning/phases/phase-${phase_num}"
        return 0
    fi

    return 1
}

# Discover plan files for a phase directory.
# GSD naming conventions:
#   Single plan:   PLAN.md
#   Multiple plans: NN-MM-PLAN.md (e.g., 02-01-PLAN.md, 02-02-PLAN.md)
# Returns plan files in sorted order via PLAN_FILES array.
discover_plans() {
    local phase_dir="$1"
    PLAN_FILES=()

    # Look for numbered plan files first (NN-MM-PLAN.md)
    local numbered_plans
    numbered_plans=$(find "$phase_dir" -maxdepth 1 -name "*-PLAN.md" -type f 2>/dev/null | sort)

    if [ -n "$numbered_plans" ]; then
        while IFS= read -r f; do
            PLAN_FILES+=("$f")
        done <<< "$numbered_plans"
    elif [ -f "$phase_dir/PLAN.md" ]; then
        # Fallback: single PLAN.md
        PLAN_FILES+=("$phase_dir/PLAN.md")
    fi
}

if [ -z "$PHASE_NUM" ]; then
    print_step "Ralph Phase Execution"
    echo "Usage: $0 [options] <phase_number>"
    echo ""
    echo "Options:"
    echo "  --no-merge  Skip automatic merge after Ralph completes"
    echo ""
    echo "This script guides you through:"
    echo "  1. Planning the phase (if not done)"
    echo "  2. Creating worktrees for parallel execution"
    echo "  3. Starting Ralph instances"
    echo "  4. Monitoring progress"
    echo "  5. Waiting for Ralph to complete"
    echo "  6. Merging completed work (automatic, unless --no-merge)"
    echo ""
    echo "Available phases:"
    grep -E "^- \[ \] \*\*Phase" .planning/ROADMAP.md | head -10
    exit 0
fi

print_step "Ralph Execute: Phase ${PHASE_NUM}"

# Step 1: Check if phase is planned
PHASE_DIR=$(find_phase_dir "$PHASE_NUM" 2>/dev/null) || true

if [ -z "$PHASE_DIR" ] || [ ! -d "$PHASE_DIR" ]; then
    print_warning "Phase ${PHASE_NUM} has not been planned yet."
    echo ""
    echo "You need to plan this phase first. Run:"
    echo ""
    echo -e "  ${GREEN}/gsd:plan-phase ${PHASE_NUM}${NC}"
    echo ""
    exit 1
fi

# Discover plans using GSD naming conventions
discover_plans "$PHASE_DIR"

if [ ${#PLAN_FILES[@]} -eq 0 ]; then
    print_warning "Phase ${PHASE_NUM} directory exists but has no plan files."
    echo ""
    echo "Expected either:"
    echo "  - $PHASE_DIR/PLAN.md (single plan)"
    echo "  - $PHASE_DIR/NN-MM-PLAN.md (numbered plans, e.g., 02-01-PLAN.md)"
    echo ""
    echo "Run: /gsd:plan-phase ${PHASE_NUM}"
    exit 1
fi

PLAN_COUNT=${#PLAN_FILES[@]}
print_success "Phase ${PHASE_NUM} is planned (${PLAN_COUNT} plan(s))"
for pf in "${PLAN_FILES[@]}"; do
    echo "  - $(basename "$pf")"
done

# Step 2: Create worktrees
print_step "Step 2: Create Worktrees"

# Count existing worktrees for this phase
EXISTING_WORKTREES=$(find "$PARENT_DIR" -maxdepth 1 -type d -name "${REPO_NAME}-p${PHASE_NUM}-*" 2>/dev/null | wc -l | tr -d ' ')

if [ "$EXISTING_WORKTREES" -gt 0 ]; then
    print_warning "Found ${EXISTING_WORKTREES} existing worktree(s) for Phase ${PHASE_NUM}"
    echo ""
    echo "Options:"
    echo "  1) Skip worktree creation (use existing)"
    echo "  2) Remove and recreate"
    echo ""
    read -p "Choice [1/2]: " CHOICE

    if [ "$CHOICE" = "2" ]; then
        print_action "Removing existing worktrees..."
        for wt in "$PARENT_DIR"/${REPO_NAME}-p${PHASE_NUM}-*; do
            if [ -d "$wt" ]; then
                BRANCH=$(git -C "$wt" branch --show-current 2>/dev/null || echo "")
                git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
                if [ -n "$BRANCH" ]; then
                    git branch -D "$BRANCH" 2>/dev/null || true
                fi
                echo "  Removed: $wt"
            fi
        done
    else
        print_action "Using existing worktrees"
    fi
fi

if [ "$EXISTING_WORKTREES" -eq 0 ] || [ "$CHOICE" = "2" ]; then
    print_action "Creating worktrees for Phase ${PHASE_NUM}..."
    ./scripts/ralph-worktrees.sh "$PHASE_NUM"
fi

# Step 3: Show worktrees and start instructions
print_step "Step 3: Start Ralph Instances"

# Find all worktrees for this phase
WORKTREES=($(find "$PARENT_DIR" -maxdepth 1 -type d -name "${REPO_NAME}-p${PHASE_NUM}-*" | sort))
NUM_WORKTREES=${#WORKTREES[@]}

echo "Found ${NUM_WORKTREES} worktree(s) for Phase ${PHASE_NUM}:"
echo ""

for i in "${!WORKTREES[@]}"; do
    wt="${WORKTREES[$i]}"
    echo "  $((i + 1)). $(basename "$wt")"
done

echo ""
echo "To start Ralph in each worktree, open ${NUM_WORKTREES} terminal(s) and run:"
echo ""

for wt in "${WORKTREES[@]}"; do
    echo -e "  ${GREEN}cd $wt && ralph${NC}"
done

echo ""
print_warning "Each Ralph instance will:"
echo "  - Read .ralph/PROMPT.md for execution rules"
echo "  - Execute tasks from the phase plan"
echo "  - Check dependencies, block if needed (retry every 2 min)"
echo "  - Update .ralph/status.json with progress"
echo ""

# Step 4: Monitoring
print_step "Step 4: Monitor Progress"

echo "While Ralph instances are running, monitor with:"
echo ""
echo "  Quick status check:"
echo -e "    ${GREEN}./scripts/ralph-status.sh ${PHASE_NUM}${NC}"
echo ""
echo "  Check status from any worktree:"
echo -e "    ${GREEN}ralph --status${NC}"
echo ""
echo "  Watch logs:"
for wt in "${WORKTREES[@]}"; do
    echo -e "    ${GREEN}tail -f $wt/.ralph/logs/ralph.log${NC}"
done
echo ""

# Step 5: Wait for Ralph to complete
print_step "Step 5: Wait for Ralph to Complete"

echo "Open ${NUM_WORKTREES} terminal(s) and start Ralph in each worktree."
echo ""
echo "When all Ralph instances have finished, return here and press ENTER."
echo ""
echo "  Review changes in each worktree before continuing:"
for wt in "${WORKTREES[@]}"; do
    echo -e "       ${GREEN}cd $wt && git diff main${NC}"
done
echo ""

wait_for_enter

# Step 6: Merge completed work
print_step "Step 6: Merge Completed Work"

if [ "$NO_MERGE" = true ]; then
    print_warning "Automatic merge skipped (--no-merge flag)."
    echo ""
    echo "  To merge manually, run:"
    echo -e "    ${GREEN}gsd-ralph merge ${PHASE_NUM}${NC}"
    echo ""
else
    print_action "Merging completed branches back to main..."
    cd "$PLANNING_DIR"
    if gsd-ralph merge "$PHASE_NUM"; then
        print_success "Merge completed successfully."
    else
        print_warning "Merge completed with warnings. Check output above for details."
    fi
fi

echo ""

# Step 7: Next steps
print_step "Step 7: Next Steps"

echo "  1. Clean up worktrees:"
echo -e "       ${GREEN}./scripts/ralph-cleanup.sh ${PHASE_NUM}${NC}"
echo ""
echo "  2. Move to next phase:"
echo -e "       ${GREEN}./scripts/ralph-execute.sh $((PHASE_NUM + 1))${NC}"
echo ""
