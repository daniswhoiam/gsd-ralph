#!/bin/bash
# ralph-worktrees.sh
# Creates git worktrees for parallel plan execution within a phase
#
# Uses .ralph/PROMPT.md as the base template and extends it with
# phase-specific context (peer visibility, dependency checking).
#
# GSD naming conventions supported:
#   Single plan:   PLAN.md
#   Multiple plans: NN-MM-PLAN.md (e.g., 02-01-PLAN.md, 02-02-PLAN.md)
#
# Usage: ./scripts/ralph-worktrees.sh <phase_number>
# Example: ./scripts/ralph-worktrees.sh 2

set -e

PHASE_NUM="$1"
REPO_NAME=$(basename "$PWD")
PARENT_DIR=$(dirname "$PWD")
PLANNING_DIR="$PWD"

if [ -z "$PHASE_NUM" ]; then
    echo "Usage: $0 <phase_number>"
    echo "Example: $0 2"
    exit 1
fi

# Validate phase directory exists
PHASE_DIR=".planning/phases/phase-${PHASE_NUM}"
if [ ! -d "$PHASE_DIR" ]; then
    echo "Error: Phase ${PHASE_NUM} not planned yet."
    echo "Run: /gsd:plan-phase ${PHASE_NUM}"
    exit 1
fi

# Validate Ralph base config exists
if [ ! -f ".ralph/PROMPT.md" ]; then
    echo "Error: .ralph/PROMPT.md not found."
    echo "Set up Ralph first (run ralph-setup or create .ralph/PROMPT.md manually)."
    exit 1
fi

# Discover plan files using GSD naming conventions.
#
# GSD produces:
#   Single plan:   PLAN.md
#   Multiple plans: NN-MM-PLAN.md (e.g., 02-01-PLAN.md, 02-02-PLAN.md)
#
# We detect numbered plans first, falling back to PLAN.md.
PLAN_FILES=()

# Look for numbered plan files (NN-MM-PLAN.md)
NUMBERED_PLANS=$(find "$PHASE_DIR" -maxdepth 1 -name "*-PLAN.md" -type f 2>/dev/null | sort)

if [ -n "$NUMBERED_PLANS" ]; then
    while IFS= read -r f; do
        PLAN_FILES+=("$f")
    done <<< "$NUMBERED_PLANS"
elif [ -f "$PHASE_DIR/PLAN.md" ]; then
    PLAN_FILES+=("$PHASE_DIR/PLAN.md")
fi

PLAN_COUNT=${#PLAN_FILES[@]}

if [ "$PLAN_COUNT" -eq 0 ]; then
    echo "Error: No plan files found in $PHASE_DIR"
    echo ""
    echo "Expected either:"
    echo "  - $PHASE_DIR/PLAN.md (single plan)"
    echo "  - $PHASE_DIR/NN-MM-PLAN.md (numbered plans, e.g., 02-01-PLAN.md)"
    exit 1
fi

echo "Phase ${PHASE_NUM}: Found ${PLAN_COUNT} plan(s)"
for pf in "${PLAN_FILES[@]}"; do
    echo "  - $(basename "$pf")"
done
echo ""

# Create branches and worktrees for each plan
for i in $(seq 0 $((PLAN_COUNT - 1))); do
    PLAN_IDX=$((i + 1))
    PLAN_ID=$(printf "%02d" $PLAN_IDX)
    PLAN_FILE="${PLAN_FILES[$i]}"
    PLAN_FILENAME=$(basename "$PLAN_FILE")
    BRANCH_NAME="phase/${PHASE_NUM}/plan-${PLAN_ID}"
    WORKTREE_PATH="${PARENT_DIR}/${REPO_NAME}-p${PHASE_NUM}-${PLAN_ID}"

    echo "Creating worktree for Plan ${PHASE_NUM}-${PLAN_ID} (${PLAN_FILENAME})..."

    # Create branch if it doesn't exist
    if ! git show-ref --verify --quiet "refs/heads/${BRANCH_NAME}"; then
        git branch "$BRANCH_NAME"
        echo "  Created branch: $BRANCH_NAME"
    else
        echo "  Branch exists: $BRANCH_NAME"
    fi

    # Create worktree if it doesn't exist
    if [ ! -d "$WORKTREE_PATH" ]; then
        git worktree add "$WORKTREE_PATH" "$BRANCH_NAME"
        echo "  Created worktree: $WORKTREE_PATH"
    else
        echo "  Worktree exists: $WORKTREE_PATH"
    fi

    # Copy planning docs to worktree
    cp -r .planning "$WORKTREE_PATH/"

    # Copy Ralph base config to worktree
    mkdir -p "$WORKTREE_PATH/.ralph/logs"
    cp .ralph/AGENT.md "$WORKTREE_PATH/.ralph/" 2>/dev/null || true
    cp .ralphrc "$WORKTREE_PATH/" 2>/dev/null || true

    # Build worktree PROMPT.md: base template + phase-specific overrides
    cp .ralph/PROMPT.md "$WORKTREE_PATH/.ralph/PROMPT.md"

    # Append phase-specific execution context
    cat >> "$WORKTREE_PATH/.ralph/PROMPT.md" << EOF

# --- WORKTREE OVERRIDES (Phase ${PHASE_NUM}, Plan ${PLAN_ID}) ---

## Scope Lock

You are executing **Phase ${PHASE_NUM}, Plan ${PLAN_ID}** ONLY.

- Your plan file: \`.planning/phases/phase-${PHASE_NUM}/${PLAN_FILENAME}\`
- Do NOT work on tasks from other phases or plans
- Do NOT modify the task discovery sequence — your tasks are in the plan file above

## Read-Only Peer Visibility

Other plans in this phase are executing in parallel. You may READ these
files to check peer status, but do NOT edit them:
EOF

    # Add peer worktree paths for this phase
    PEERS_ADDED=0
    for j in $(seq 0 $((PLAN_COUNT - 1))); do
        if [ "$j" -ne "$i" ]; then
            PEER_IDX=$((j + 1))
            PEER_ID=$(printf "%02d" $PEER_IDX)
            PEER_PATH="${PARENT_DIR}/${REPO_NAME}-p${PHASE_NUM}-${PEER_ID}"
            echo "- \`${PEER_PATH}/.planning/STATE.md\`" >> "$WORKTREE_PATH/.ralph/PROMPT.md"
            echo "- \`${PEER_PATH}/.ralph/status.json\`" >> "$WORKTREE_PATH/.ralph/PROMPT.md"
            PEERS_ADDED=1
        fi
    done

    # If no peers, note it
    if [ "$PEERS_ADDED" -eq 0 ]; then
        echo "" >> "$WORKTREE_PATH/.ralph/PROMPT.md"
        echo "_No peer worktrees — this is the only plan in Phase ${PHASE_NUM}._" >> "$WORKTREE_PATH/.ralph/PROMPT.md"
    fi

    # Extract tasks from this plan's specific file into fix_plan.md
    # GSD plans use XML task format:
    #   <task type="auto">
    #     <name>Task N: Description</name>
    #     <action>...</action>
    #     <verify>...</verify>
    #     <done>Acceptance criteria (always present, NOT a completion marker)</done>
    #   </task>
    #
    # Note: <done> is the "definition of done" (acceptance criteria), not a
    # completion signal. GSD tracks completion via commits and Summary files.
    # We extract all task names as unchecked items for Ralph to work through.
    if [ -f "$PLAN_FILE" ]; then
        python3 -c "
import re, sys
content = open(sys.argv[1]).read()
tasks = re.findall(r'<task[^>]*>(.*?)</task>', content, re.DOTALL)
for t in tasks:
    name_m = re.search(r'<name>(.*?)</name>', t)
    if not name_m:
        continue
    name = name_m.group(1).strip()
    print(f'- [ ] {name}')
" "$PLAN_FILE" > "$WORKTREE_PATH/.ralph/fix_plan.md" 2>/dev/null || true
    fi

    # Also create the legacy @fix_plan.md at worktree root for compatibility
    if [ -f "$WORKTREE_PATH/.ralph/fix_plan.md" ]; then
        cp "$WORKTREE_PATH/.ralph/fix_plan.md" "$WORKTREE_PATH/@fix_plan.md"
    fi

    # Create initial status.json
    cat > "$WORKTREE_PATH/.ralph/status.json" << EOF
{
  "phase": ${PHASE_NUM},
  "plan": "${PLAN_ID}",
  "plan_file": "${PLAN_FILENAME}",
  "status": "ready",
  "started_at": null,
  "blocked_reason": null,
  "last_activity": "$(date -Iseconds)"
}
EOF

    echo "  Setup complete for Plan ${PHASE_NUM}-${PLAN_ID}"
    echo ""
done

# Update PHASES.md in planning checkout
PHASES_FILE="${PLANNING_DIR}/PHASES.md"
if [ ! -f "$PHASES_FILE" ]; then
    echo "# Phase Worktrees" > "$PHASES_FILE"
    echo "" >> "$PHASES_FILE"
    echo "Index of all phase worktrees for parallel execution." >> "$PHASES_FILE"
    echo "" >> "$PHASES_FILE"
fi

# Add/update this phase's entries
echo "" >> "$PHASES_FILE"
echo "## Phase ${PHASE_NUM}" >> "$PHASES_FILE"
echo "" >> "$PHASES_FILE"
echo "| Plan | Plan File | Branch | Worktree Path | Status |" >> "$PHASES_FILE"
echo "|------|-----------|--------|---------------|--------|" >> "$PHASES_FILE"
for i in $(seq 0 $((PLAN_COUNT - 1))); do
    PLAN_IDX=$((i + 1))
    PLAN_ID=$(printf "%02d" $PLAN_IDX)
    PLAN_FILENAME=$(basename "${PLAN_FILES[$i]}")
    BRANCH_NAME="phase/${PHASE_NUM}/plan-${PLAN_ID}"
    WORKTREE_PATH="${PARENT_DIR}/${REPO_NAME}-p${PHASE_NUM}-${PLAN_ID}"
    echo "| ${PLAN_ID} | ${PLAN_FILENAME} | ${BRANCH_NAME} | ${WORKTREE_PATH} | Ready |" >> "$PHASES_FILE"
done

echo "========================================="
echo "Phase ${PHASE_NUM} worktrees created!"
echo "========================================="
echo ""
echo "To start Ralph in each worktree:"
echo ""
for i in $(seq 0 $((PLAN_COUNT - 1))); do
    PLAN_IDX=$((i + 1))
    PLAN_ID=$(printf "%02d" $PLAN_IDX)
    WORKTREE_PATH="${PARENT_DIR}/${REPO_NAME}-p${PHASE_NUM}-${PLAN_ID}"
    echo "  cd ${WORKTREE_PATH} && ralph"
done
echo ""
echo "Monitor progress:"
echo "  ralph --status  (in each worktree)"
echo "  ./scripts/ralph-status.sh ${PHASE_NUM}"
echo ""
