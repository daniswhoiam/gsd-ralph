#!/bin/bash
# lib/commands/merge.sh -- Merge completed branches for a phase back to main
#
# Provides dry-run conflict detection, auto-resolution of known safe conflicts,
# rollback safety, branch discovery, and post-merge summary with optional review.

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
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/merge/review.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/merge/signals.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/merge/test_runner.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/config.sh"

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

    # ── Phase 1: Dry-run preflight (all branches before any merge) ──
    print_header "Dry-Run Preflight"
    local clean_branches=()
    local conflict_branches=()
    local conflict_files_map=()  # parallel array: conflict file lists per conflict_branches entry

    for branch in "${MERGE_BRANCHES[@]}"; do
        if merge_dry_run "$branch"; then
            print_success "$branch: clean merge"
            clean_branches+=("$branch")
        else
            print_warning "$branch: conflicts detected"
            local conflict_file_list=""
            if merge_dry_run_conflicts "$branch"; then
                conflict_file_list="$DRY_RUN_CONFLICTS"
                local conflict_file
                while IFS= read -r conflict_file; do
                    [[ -n "$conflict_file" ]] && print_info "    $conflict_file"
                done <<< "$DRY_RUN_CONFLICTS"
            fi
            # Check if ALL conflicting files are auto-resolvable
            # If so, still attempt the merge (auto-resolve will handle it)
            local all_auto_resolvable=true
            local cfile
            for cfile in $conflict_file_list; do
                [[ -z "$cfile" ]] && continue
                if ! matches_auto_resolve_pattern "$cfile"; then
                    all_auto_resolvable=false
                    break
                fi
            done
            if [[ "$all_auto_resolvable" == true ]] && [[ -n "$conflict_file_list" ]]; then
                print_info "$branch: all conflicts auto-resolvable, will attempt merge"
                clean_branches+=("$branch")
            else
                conflict_branches+=("$branch")
                conflict_files_map+=("$conflict_file_list")
            fi
        fi
    done

    # Dry-run mode: show report and return without merging
    if [[ "$dry_run" == true ]]; then
        if [[ ${#conflict_branches[@]} -gt 0 ]]; then
            return 1
        fi
        return 0
    fi

    # If ALL branches conflict, nothing to merge
    if [[ ${#clean_branches[@]} -eq 0 ]]; then
        print_warning "All branches have conflicts. Nothing to merge."
        # Report conflict guidance for each
        local idx=0
        for branch in "${conflict_branches[@]}"; do
            print_conflict_guidance "$branch" "${conflict_files_map[$idx]}"
            idx=$((idx + 1))
        done
        return 1
    fi

    # ── Phase 2: Save rollback point ──
    save_rollback_point "$phase_num"
    local rollback_sha
    rollback_sha=$(git rev-parse HEAD)
    print_verbose "Rollback point saved at $rollback_sha"

    # ── Phase 3: Merge clean branches sequentially ──
    print_header "Merging Branches"

    # Results array: colon-delimited "branch:status:details:commits"
    local merge_results=()
    local success_count=0
    local skip_count=0

    for branch in "${clean_branches[@]}"; do
        print_info "Merging $branch ..."
        local sha_before
        sha_before=$(git rev-parse HEAD)

        if git merge --no-ff --no-edit "$branch" >/dev/null 2>&1; then
            # Merge succeeded cleanly
            local stat_line commit_count
            stat_line=$(git diff --stat "$sha_before"..HEAD 2>/dev/null | tail -1)
            commit_count=$(git rev-list --count "$sha_before"..HEAD 2>/dev/null)
            record_merged_branch "$branch" "$sha_before"
            merge_results+=("${branch}:merged:${stat_line}:${commit_count}")
            success_count=$((success_count + 1))
            print_success "$branch merged"
        else
            # Merge conflict -- attempt auto-resolution
            print_verbose "Conflict during merge of $branch, attempting auto-resolve ..."
            auto_resolve_known_conflicts
            local resolve_exit=$?

            if [[ $resolve_exit -eq 0 ]]; then
                # Auto-resolved all conflicts
                local stat_line commit_count
                stat_line=$(git diff --stat "$sha_before"..HEAD 2>/dev/null | tail -1)
                commit_count=$(git rev-list --count "$sha_before"..HEAD 2>/dev/null)
                record_merged_branch "$branch" "$sha_before"
                merge_results+=("${branch}:merged*:${stat_line}:${commit_count}")
                success_count=$((success_count + 1))
                print_success "$branch merged (auto-resolved)"
            else
                # Remaining conflicts -- skip this branch
                local conflicted_files
                conflicted_files=$(git diff --name-only --diff-filter=U 2>/dev/null | tr '\n' ' ')
                git merge --abort >/dev/null 2>&1
                merge_results+=("${branch}:skipped:conflict in ${conflicted_files}:0")
                skip_count=$((skip_count + 1))
                print_warning "$branch skipped (unresolvable conflicts)"
                print_conflict_guidance "$branch" "$conflicted_files"
            fi
        fi
    done

    # Add dry-run-detected conflict branches to results (not attempted)
    if [[ ${#conflict_branches[@]} -gt 0 ]]; then
        for branch in "${conflict_branches[@]}"; do
            merge_results+=("${branch}:conflict:dry-run detected:0")
        done
    fi

    # ── Phase 4: Post-merge testing ──
    local test_failed=false
    if [[ $success_count -gt 0 ]]; then
        print_header "Post-Merge Testing"
        detect_project_type "."
        local pre_merge_sha
        pre_merge_sha=$(jq -r '.pre_merge_sha' "$ROLLBACK_FILE" 2>/dev/null)

        if ! run_post_merge_tests "$DETECTED_TEST_CMD" "$pre_merge_sha"; then
            test_failed=true
            print_error "New test regressions detected after merge."
            print_info "To undo the merge: gsd-ralph merge $phase_num --rollback"
        fi
    fi

    # ── Phase 5: Wave signaling and state updates ──
    if [[ $success_count -gt 0 ]] && [[ "$test_failed" == false ]]; then
        print_header "Wave Signaling"

        # Build space-separated list of successfully merged branches
        local merged_branches_list=""
        local result
        for result in "${merge_results[@]}"; do
            local r_status
            r_status=$(echo "$result" | cut -d: -f2)
            case "$r_status" in
                merged|merged*)
                    local r_branch
                    r_branch=$(echo "$result" | cut -d: -f1)
                    if [[ -n "$merged_branches_list" ]]; then
                        merged_branches_list="$merged_branches_list $r_branch"
                    else
                        merged_branches_list="$r_branch"
                    fi
                    ;;
            esac
        done

        # Determine wave number: for sequential mode, always wave 1
        local wave_num=1
        signal_wave_complete "$phase_num" "$wave_num" "$merged_branches_list"

        # Check if ALL branches for the phase are merged (no skipped, no conflicts)
        local conflict_branch_count=${#conflict_branches[@]}
        if [[ $skip_count -eq 0 ]] && [[ $conflict_branch_count -eq 0 ]]; then
            signal_phase_complete "$phase_num"
        else
            print_info "Some branches not merged. Phase $phase_num not yet complete."
            if [[ $skip_count -gt 0 ]]; then
                print_info "  Skipped: $skip_count branch(es) with unresolvable conflicts"
            fi
            if [[ $conflict_branch_count -gt 0 ]]; then
                print_info "  Conflicts: $conflict_branch_count branch(es) detected in dry-run"
            fi
        fi
    fi

    # ── Phase 6: Store results and print summary ──
    # shellcheck disable=SC2034
    MERGE_RESULTS=("${merge_results[@]}")
    # shellcheck disable=SC2034
    MERGE_PHASE="$phase_num"
    # shellcheck disable=SC2034
    MERGE_ROLLBACK_SHA="$rollback_sha"
    # shellcheck disable=SC2034
    MERGE_BRANCH_COUNT=${#MERGE_BRANCHES[@]}
    # shellcheck disable=SC2034
    MERGE_SUCCESS_COUNT=$success_count
    # shellcheck disable=SC2034
    MERGE_SKIP_COUNT=$skip_count

    # Print summary table
    print_merge_summary "${merge_results[@]}"

    # Add test and signal status to summary output
    if [[ "$test_failed" == true ]]; then
        print_error "Tests: REGRESSIONS DETECTED"
    elif [[ $success_count -gt 0 ]] && [[ -n "$DETECTED_TEST_CMD" ]]; then
        print_success "Tests: passing"
    fi
    if [[ $success_count -gt 0 ]] && [[ "$test_failed" == false ]]; then
        print_success "Wave ${wave_num:-1} complete signal written"
    fi

    # Optional detailed review
    if [[ "$do_review" == true ]]; then
        print_merge_review "$phase_num"
    fi

    # Return non-zero if any branches were skipped, had dry-run conflicts, or tests failed
    local conflict_branch_count=${#conflict_branches[@]}
    if [[ $skip_count -gt 0 ]] || [[ $conflict_branch_count -gt 0 ]] || [[ "$test_failed" == true ]]; then
        return 1
    fi
    return 0
}
