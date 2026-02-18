#!/bin/bash
# lib/discovery.sh -- GSD plan file discovery and naming convention handling

# Find phase directory by number.
# Supports GSD format: NN-slug (e.g., 01-project-initialization)
# Args: phase_number, [planning_base] (defaults to .planning/phases)
# Sets: PHASE_DIR (global, used by callers)
# Returns: 0 if found, 1 if not found
find_phase_dir() {
    local phase_num="$1"
    local base="${2:-.planning/phases}"
    local padded
    padded=$(printf "%02d" "$phase_num")

    local dir
    # shellcheck disable=SC2012
    dir=$(ls -d "${base}/${padded}"-* 2>/dev/null | head -1)
    if [[ -n "$dir" ]] && [[ -d "$dir" ]]; then
        # shellcheck disable=SC2034
        PHASE_DIR="$dir"
        return 0
    fi

    # shellcheck disable=SC2034
    PHASE_DIR=""
    return 1
}

# Discover plan files in a phase directory.
# Uses precise glob: NN-MM-PLAN.md for numbered plans, PLAN.md fallback for single-plan phases.
# Args: phase_dir
# Sets: PLAN_FILES (global array), PLAN_COUNT (global integer)
# Returns: 0 if plans found, 1 if none found
discover_plan_files() {
    local phase_dir="$1"
    PLAN_FILES=()
    PLAN_COUNT=0

    # Numbered plans: NN-MM-PLAN.md (precise glob avoids matching non-plan files)
    local f
    for f in "$phase_dir"/[0-9][0-9]-[0-9][0-9]-PLAN.md; do
        [[ -f "$f" ]] || continue
        PLAN_FILES+=("$f")
    done

    # Fallback: single PLAN.md
    if [[ ${#PLAN_FILES[@]} -eq 0 ]] && [[ -f "$phase_dir/PLAN.md" ]]; then
        PLAN_FILES+=("$phase_dir/PLAN.md")
    fi

    PLAN_COUNT=${#PLAN_FILES[@]}
    [[ $PLAN_COUNT -gt 0 ]]
}

# Extract plan ID from plan filename.
# "02-01-PLAN.md" -> "01", "PLAN.md" -> "01" (single-plan default)
# Args: plan_filename (basename or full path)
plan_id_from_filename() {
    local filename="$1"
    local base
    base=$(basename "$filename")

    if [[ "$base" =~ ^[0-9][0-9]-([0-9][0-9])-PLAN\.md$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "01"
    fi
}

# Compute worktree path for a plan.
# Format: ${parent_dir}/${repo_name}-p${phase_num}-${plan_id}
# Args: parent_dir, repo_name, phase_num, plan_id
worktree_path_for_plan() {
    local parent_dir="$1"
    local repo_name="$2"
    local phase_num="$3"
    local plan_id="$4"
    echo "${parent_dir}/${repo_name}-p${phase_num}-${plan_id}"
}
