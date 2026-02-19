#!/bin/bash
# lib/commands/merge.sh -- Merge completed branches for a phase back to main
#
# Provides dry-run conflict detection, auto-resolution of known safe conflicts,
# rollback safety, and branch discovery. The actual merge pipeline loop is
# implemented in Plan 04-02.

# Source required modules
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/discovery.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/frontmatter.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/strategy.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/merge/dry_run.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/merge/rollback.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/merge/auto_resolve.sh"

merge_usage() {
    cat <<EOF
Merge completed phase branches back into main

Usage: gsd-ralph merge [options] <phase_number>

Discovers branches created by 'gsd-ralph execute' for the given phase,
performs dry-run conflict detection, auto-resolves known safe conflicts
(.planning/, lock files), and merges with rollback safety.

Options:
  --rollback    Rollback the last merge for this phase
  --review      Show full diffs for each merged branch
  --dry-run     Only show dry-run conflict report, do not merge
  -v, --verbose Enable verbose output
  -h, --help    Show this help message

Examples:
  gsd-ralph merge 3              Merge all phase 3 branches
  gsd-ralph merge 3 --dry-run    Preview conflicts without merging
  gsd-ralph merge 3 --rollback   Rollback phase 3 merge
  gsd-ralph merge 3 --review     Merge with full diff review
EOF
}

# Discover branches belonging to a phase that need merging.
# Checks for sequential-mode branch (phase-N/slug) and per-plan branches.
# Filters out branches already merged into HEAD.
# Args: phase_num
# Sets: MERGE_BRANCHES (array of branch names), MERGE_BRANCH_COUNT (integer)
# Returns: 0 if branches found, 1 if none
discover_merge_branches() {
    local phase_num="$1"

    MERGE_BRANCHES=()
    # shellcheck disable=SC2034
    MERGE_BRANCH_COUNT=0

    # Sequential mode: single branch named phase-N/slug
    if find_phase_dir "$phase_num"; then
        local slug
        slug=$(basename "$PHASE_DIR")
        local slug_part="${slug#[0-9][0-9]-}"
        local branch_name="phase-${phase_num}/${slug_part}"

        if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
            # Check if already merged into HEAD
            if ! git merge-base --is-ancestor "$branch_name" HEAD 2>/dev/null; then
                MERGE_BRANCHES+=("$branch_name")
            else
                print_verbose "Skipping already-merged branch: $branch_name"
            fi
        fi
    fi

    # Also check for per-plan branches: phase/N/plan-NN (future parallel mode)
    local branch
    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        # Skip if already in the list
        local already_listed=false
        local existing
        for existing in "${MERGE_BRANCHES[@]}"; do
            if [[ "$existing" == "$branch" ]]; then
                already_listed=true
                break
            fi
        done
        [[ "$already_listed" == true ]] && continue

        # Skip if already merged
        if ! git merge-base --is-ancestor "$branch" HEAD 2>/dev/null; then
            MERGE_BRANCHES+=("$branch")
        else
            print_verbose "Skipping already-merged branch: $branch"
        fi
    done < <(git for-each-ref --format='%(refname:short)' "refs/heads/phase/${phase_num}/" 2>/dev/null)

    # shellcheck disable=SC2034
    MERGE_BRANCH_COUNT=${#MERGE_BRANCHES[@]}
    [[ ${#MERGE_BRANCHES[@]} -gt 0 ]]
}

# Main entry point for the merge command.
cmd_merge() {
    local phase_num=""
    local do_rollback=false
    local do_review=false
    local dry_run=false

    # Parse arguments
    # shellcheck disable=SC2034
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)       merge_usage; exit 0 ;;
            -v|--verbose)    VERBOSE=true; shift ;;
            --rollback)      do_rollback=true; shift ;;
            --review)        do_review=true; shift ;;
            --dry-run)       dry_run=true; shift ;;
            -*)              die "Unknown option for merge: $1" ;;
            *)
                if [[ -z "$phase_num" ]]; then
                    phase_num="$1"; shift
                else
                    die "Unexpected argument: $1"
                fi
                ;;
        esac
    done

    if [[ -z "$phase_num" ]]; then
        print_error "Phase number required"
        merge_usage
        exit 1
    fi

    # Validate environment
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die "Not inside a git repository. Run this from your project root."
    fi
    if [[ ! -d ".planning" ]]; then
        die "No .planning/ directory found. Initialize GSD first."
    fi
    if [[ ! -d ".ralph" ]]; then
        die "Not initialized. Run 'gsd-ralph init' first."
    fi

    # Handle --rollback early
    if [[ "$do_rollback" == true ]]; then
        rollback_merge "$phase_num"
        return $?
    fi

    # Find phase directory
    if ! find_phase_dir "$phase_num"; then
        die "Phase $phase_num not found. Check .planning/phases/ for available phases."
    fi

    # Ensure on main branch
    local current_branch
    current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
    local main_branch=""
    if [[ "$current_branch" == "main" ]]; then
        main_branch="main"
    elif [[ "$current_branch" == "master" ]]; then
        main_branch="master"
    else
        die "Not on main branch (currently on '$current_branch'). Switch to main first: git checkout main"
    fi

    # Verify clean working tree
    local porcelain
    porcelain=$(git status --porcelain 2>/dev/null)
    if [[ -n "$porcelain" ]]; then
        die "Working tree is not clean. Commit or stash changes before merging."
    fi

    # Discover branches to merge
    if ! discover_merge_branches "$phase_num"; then
        print_info "No unmerged branches found for phase $phase_num."
        return 0
    fi

    print_header "gsd-ralph merge (Phase $phase_num)"
    print_info "Main branch: $main_branch"
    print_info "Branches to merge: $MERGE_BRANCH_COUNT"

    local branch
    for branch in "${MERGE_BRANCHES[@]}"; do
        print_info "  - $branch"
    done

    # Dry-run mode: show conflict report and exit
    if [[ "$dry_run" == true ]]; then
        print_header "Dry-Run Conflict Report"
        local has_conflicts=false
        for branch in "${MERGE_BRANCHES[@]}"; do
            if merge_dry_run "$branch"; then
                print_success "$branch: clean merge"
            else
                has_conflicts=true
                print_warning "$branch: conflicts detected"
                if merge_dry_run_conflicts "$branch"; then
                    local conflict_file
                    while IFS= read -r conflict_file; do
                        [[ -n "$conflict_file" ]] && print_info "    $conflict_file"
                    done <<< "$DRY_RUN_CONFLICTS"
                fi
            fi
        done
        if [[ "$has_conflicts" == true ]]; then
            return 1
        fi
        return 0
    fi

    # Merge pipeline placeholder -- Plan 04-02 implements the actual merge loop
    print_info ""
    print_info "Merge pipeline not yet implemented (see Plan 04-02)."
    print_info "Use --dry-run to preview conflicts."

    # Suppress unused variable warnings for flags consumed by future pipeline
    : "${do_review:=false}"

    return 0
}
