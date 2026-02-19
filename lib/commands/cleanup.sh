#!/bin/bash
# lib/commands/cleanup.sh -- Remove worktrees and branches for a phase
#
# Registry-driven cleanup: reads the worktree registry to determine what
# was created by gsd-ralph, removes worktrees, deletes branches, prunes
# stale references, cleans signal/rollback files, and deregisters the phase.

# Source required modules
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/cleanup/registry.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/discovery.sh"

cleanup_usage() {
    cat <<EOF
Remove worktrees and branches for a completed phase

Usage: gsd-ralph cleanup [options] <phase_number>

Reads the worktree registry to find all worktrees and branches created
by 'gsd-ralph execute' for the given phase, removes them, prunes stale
worktree references, cleans up signal/rollback files, and deregisters
the phase from the registry.

Options:
  --force       Skip confirmation and force-delete unmerged branches
  -v, --verbose Enable verbose output
  -h, --help    Show this help message

Examples:
  gsd-ralph cleanup 3            Clean up all phase 3 worktrees/branches
  gsd-ralph cleanup 3 --force    Force cleanup without confirmation
EOF
}

# Main entry point for the cleanup command.
cmd_cleanup() {
    local phase_num=""
    local force=false

    # Parse arguments
    # shellcheck disable=SC2034
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)       cleanup_usage; exit 0 ;;
            -v|--verbose)    VERBOSE=true; shift ;;
            --force)         force=true; shift ;;
            -*)              die "Unknown option for cleanup: $1" ;;
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
        cleanup_usage
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

    # Read registry entries for this phase
    local registry_json
    registry_json=$(list_registered_worktrees "$phase_num")
    local entry_count
    entry_count=$(printf '%s' "$registry_json" | jq '. | length')

    if [[ "$entry_count" -eq 0 ]]; then
        # Check for unregistered branches (created before registry existed)
        local unregistered_branches=()
        local branch

        # Check sequential mode branch: phase-N/slug
        if find_phase_dir "$phase_num"; then
            local slug
            slug=$(basename "$PHASE_DIR")
            local slug_part="${slug#[0-9][0-9]-}"
            local seq_branch="phase-${phase_num}/${slug_part}"
            if git show-ref --verify --quiet "refs/heads/$seq_branch" 2>/dev/null; then
                unregistered_branches+=("$seq_branch")
            fi
        fi

        # Check per-plan branches: phase/N/*
        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            unregistered_branches+=("$branch")
        done < <(git for-each-ref --format='%(refname:short)' "refs/heads/phase-${phase_num}/" 2>/dev/null)
        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            unregistered_branches+=("$branch")
        done < <(git for-each-ref --format='%(refname:short)' "refs/heads/phase/${phase_num}/" 2>/dev/null)

        if [[ ${#unregistered_branches[@]} -gt 0 ]]; then
            print_info "No tracked worktrees for phase $phase_num."
            print_info "Unregistered branches exist (created before registry was active):"
            for branch in "${unregistered_branches[@]}"; do
                print_info "  - $branch"
            done
            if [[ "$force" == true ]]; then
                print_info "Force mode: deleting unregistered branches..."
                local del_count=0
                for branch in "${unregistered_branches[@]}"; do
                    if git branch -D "$branch" >/dev/null 2>&1; then
                        print_success "Deleted branch: $branch"
                        del_count=$((del_count + 1))
                    else
                        print_warning "Failed to delete branch: $branch"
                    fi
                done
                git worktree prune >/dev/null 2>&1
                print_info "Deleted $del_count unregistered branch(es)."
                return 0
            else
                print_info "Use --force to clean these up."
                return 0
            fi
        fi

        print_info "Nothing to clean for phase $phase_num."
        return 0
    fi

    # Preview what will be removed
    print_header "Cleanup Preview (Phase $phase_num)"
    local i=0
    while [[ $i -lt $entry_count ]]; do
        local wt_path br_name
        wt_path=$(printf '%s' "$registry_json" | jq -r ".[$i].worktree_path")
        br_name=$(printf '%s' "$registry_json" | jq -r ".[$i].branch")
        print_info "  Worktree: $(basename "$wt_path")  Branch: $br_name"
        i=$((i + 1))
    done

    # Confirmation
    if [[ "$force" != true ]]; then
        if ! [[ -t 0 ]]; then
            die "Non-interactive mode requires --force flag."
        fi
        printf "Confirm removal? [y/N]: "
        read -r confirm
        if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
            print_info "Aborted."
            return 0
        fi
    fi

    # Remove worktrees and branches
    local wt_removed=0
    local br_deleted=0
    local br_skipped=0

    i=0
    while [[ $i -lt $entry_count ]]; do
        local wt_path br_name
        wt_path=$(printf '%s' "$registry_json" | jq -r ".[$i].worktree_path")
        br_name=$(printf '%s' "$registry_json" | jq -r ".[$i].branch")

        # Remove worktree
        if [[ -d "$wt_path" ]]; then
            if git worktree remove --force "$wt_path" 2>/dev/null; then
                print_verbose "Removed worktree: $wt_path"
                wt_removed=$((wt_removed + 1))
            else
                # Fallback: force remove directory
                rm -rf "$wt_path" 2>/dev/null || true
                print_verbose "Force-removed worktree directory: $wt_path"
                wt_removed=$((wt_removed + 1))
            fi
        else
            print_verbose "Worktree already removed: $wt_path"
        fi

        # Delete branch
        if git show-ref --verify --quiet "refs/heads/$br_name" 2>/dev/null; then
            if git branch -d "$br_name" 2>/dev/null; then
                print_verbose "Deleted branch: $br_name"
                br_deleted=$((br_deleted + 1))
            elif [[ "$force" == true ]]; then
                if git branch -D "$br_name" 2>/dev/null; then
                    print_verbose "Force-deleted branch: $br_name"
                    br_deleted=$((br_deleted + 1))
                else
                    print_warning "Failed to delete branch: $br_name"
                    br_skipped=$((br_skipped + 1))
                fi
            else
                print_warning "Branch not fully merged: $br_name (use --force to delete)"
                br_skipped=$((br_skipped + 1))
            fi
        else
            print_verbose "Branch already deleted: $br_name"
        fi

        i=$((i + 1))
    done

    # Prune stale worktree references
    git worktree prune 2>/dev/null

    # Clean up signal files
    rm -f ".ralph/merge-signals/phase-${phase_num}-"* 2>/dev/null

    # Clean up rollback file if it matches this phase
    if [[ -f ".ralph/merge-rollback.json" ]]; then
        local rollback_phase
        rollback_phase=$(jq -r '.phase' ".ralph/merge-rollback.json" 2>/dev/null)
        if [[ "$rollback_phase" == "$phase_num" ]]; then
            rm -f ".ralph/merge-rollback.json"
            print_verbose "Removed rollback file for phase $phase_num"
        fi
    fi

    # Deregister phase from registry
    deregister_phase "$phase_num"

    # Print summary
    print_header "Cleanup Summary"
    print_info "Worktrees removed: $wt_removed"
    print_info "Branches deleted:  $br_deleted"
    if [[ $br_skipped -gt 0 ]]; then
        print_warning "Branches skipped:  $br_skipped (unmerged, use --force)"
    fi
    print_success "Phase $phase_num cleanup complete"

    return 0
}
