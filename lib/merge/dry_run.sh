#!/bin/bash
# lib/merge/dry_run.sh -- Dry-run conflict detection using git merge-tree
#
# Provides zero-side-effect merge conflict detection without touching
# the working tree or index. Uses git merge-tree --write-tree (Git 2.38+)
# with a fallback to git merge --no-commit + abort for older versions.

# Check Git version >= 2.38 for git merge-tree --write-tree support.
# Returns: 0 if supported, 1 if not.
check_git_merge_tree_support() {
    local git_version
    git_version=$(git --version | sed 's/git version //')
    local major minor
    major=$(echo "$git_version" | cut -d. -f1)
    minor=$(echo "$git_version" | cut -d. -f2)

    if [[ "$major" -gt 2 ]] || { [[ "$major" -eq 2 ]] && [[ "$minor" -ge 38 ]]; }; then
        return 0
    else
        return 1
    fi
}

# Dry-run merge detection for a branch against current HEAD.
# Uses git merge-tree --write-tree if available, falls back to
# git merge --no-commit --no-ff + git merge --abort otherwise.
# Args: branch_name
# Returns: 0 if clean merge possible, 1 if conflicts detected
merge_dry_run() {
    local branch="$1"

    if check_git_merge_tree_support; then
        # git merge-tree --write-tree: exit 0 = clean, non-zero = conflicts
        if git merge-tree --write-tree --quiet HEAD "$branch" >/dev/null 2>&1; then
            return 0
        else
            return 1
        fi
    else
        # Fallback for Git < 2.38: attempt merge and abort
        print_warning "Git < 2.38 detected; using fallback dry-run (touches index briefly)"
        if git merge --no-commit --no-ff "$branch" >/dev/null 2>&1; then
            # Clean merge -- abort to restore state
            git merge --abort >/dev/null 2>&1 || git reset --merge >/dev/null 2>&1
            return 0
        else
            # Conflicts -- abort to restore state
            git merge --abort >/dev/null 2>&1 || git reset --merge >/dev/null 2>&1
            return 1
        fi
    fi
}

# Get list of conflicting file names for a branch merge.
# Uses git merge-tree --write-tree --name-only if available,
# falls back to git merge --no-commit + git diff --name-only --diff-filter=U.
# Args: branch_name
# Sets: DRY_RUN_CONFLICTS (newline-separated list of conflicting files)
# Returns: 0 if conflicts found, 1 if merge is clean (no conflicts)
merge_dry_run_conflicts() {
    local branch="$1"
    # shellcheck disable=SC2034
    DRY_RUN_CONFLICTS=""

    if check_git_merge_tree_support; then
        local output
        output=$(git merge-tree --write-tree --name-only HEAD "$branch" 2>&1)
        local exit_code=$?

        if [[ $exit_code -eq 0 ]]; then
            # Clean merge -- no conflicts
            return 1
        fi

        # Parse output: first line is tree SHA, then file names until first empty line.
        # After the empty line: informational messages (Auto-merging, CONFLICT).
        # Extract only actual file names (non-empty lines between SHA and messages).
        local conflicts=""
        local line
        local skip_first=true
        while IFS= read -r line; do
            if [[ "$skip_first" == true ]]; then
                skip_first=false
                continue  # Skip tree SHA line
            fi
            # Stop at first empty line or informational message
            [[ -z "$line" ]] && break
            if [[ -n "$conflicts" ]]; then
                conflicts="${conflicts}
${line}"
            else
                conflicts="$line"
            fi
        done <<< "$output"
        if [[ -n "$conflicts" ]]; then
            # shellcheck disable=SC2034
            DRY_RUN_CONFLICTS="$conflicts"
        fi
        return 0
    else
        # Fallback: attempt merge and collect conflicts
        if git merge --no-commit --no-ff "$branch" >/dev/null 2>&1; then
            git merge --abort >/dev/null 2>&1 || git reset --merge >/dev/null 2>&1
            return 1
        fi

        # shellcheck disable=SC2034
        DRY_RUN_CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null)
        git merge --abort >/dev/null 2>&1 || git reset --merge >/dev/null 2>&1
        return 0
    fi
}
