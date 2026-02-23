#!/bin/bash
# lib/safety.sh -- Safety guard functions for destructive operations
#
# Provides safe_remove() to prevent deletion of critical paths (/, HOME, git
# toplevel) and validate_registry_path() for worktree registry entry validation.
#
# This file does NOT source common.sh -- the sourcing chain is handled by
# the entry point (bin/gsd-ralph sources common.sh, then commands source this).

# Safely remove a file or directory after checking against dangerous paths.
# Refuses to remove empty paths, filesystem root, HOME, or the git working tree.
# Uses [[ -ef ]] for inode-level path comparison (handles symlinks).
#
# Args:
#   target_path   -- Path to remove
#   removal_type  -- "file" (default) or "directory"
# Returns: 0 on successful removal, 1 on refusal or error
safe_remove() {
    local target_path="$1"
    local removal_type="${2:-file}"

    # Guard 1: Block empty/unset path
    if [[ -z "$target_path" ]]; then
        print_error "SAFETY: Refusing to remove empty path"
        return 1
    fi

    # Resolve to absolute path
    local abs_path
    if [[ -d "$target_path" ]]; then
        abs_path=$(cd "$target_path" && pwd -P) || {
            print_error "SAFETY: Cannot resolve path: $target_path"
            return 1
        }
    elif [[ -e "$target_path" ]]; then
        local parent_dir
        parent_dir=$(cd "$(dirname "$target_path")" && pwd -P) || {
            print_error "SAFETY: Cannot resolve parent of: $target_path"
            return 1
        }
        abs_path="${parent_dir}/$(basename "$target_path")"
    else
        # Target does not exist -- nothing to remove
        print_verbose "SAFETY: Target does not exist, nothing to remove: $target_path"
        return 0
    fi

    # Guard 2: Block filesystem root
    if [[ "$abs_path" == "/" ]]; then
        print_error "SAFETY: Refusing to remove filesystem root (/)"
        return 1
    fi

    # Guard 3: Block home directory (inode-level comparison)
    if [[ -n "${HOME:-}" ]] && [[ -d "$abs_path" ]] && [[ "$abs_path" -ef "$HOME" ]]; then
        print_error "SAFETY: Refusing to remove home directory ($abs_path)"
        return 1
    fi

    # Guard 4: Block git toplevel (inode-level comparison)
    local git_toplevel
    git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_toplevel" ]] && [[ -d "$abs_path" ]] && [[ "$abs_path" -ef "$git_toplevel" ]]; then
        print_error "SAFETY: Refusing to remove git working tree ($abs_path)"
        return 1
    fi

    # All guards passed -- perform removal
    if [[ "$removal_type" == "directory" ]]; then
        rm -rf "$target_path"
    else
        rm -f "$target_path"
    fi

    return 0
}

# Validate a path for use in the worktree registry.
# Blocks empty paths, non-absolute paths, and paths containing traversal (../).
# Allows the __MAIN_WORKTREE__ sentinel as a valid non-removable entry.
#
# Args:
#   path -- Registry path to validate
# Returns: 0 if valid, 1 if invalid
validate_registry_path() {
    local path="$1"

    # Block empty path
    if [[ -z "$path" ]]; then
        print_error "SAFETY: Registry path must not be empty"
        return 1
    fi

    # Allow sentinel value (valid but non-removable)
    if [[ "$path" == "__MAIN_WORKTREE__" ]]; then
        return 0
    fi

    # Block non-absolute paths
    if [[ "$path" != /* ]]; then
        print_error "SAFETY: Registry path must be absolute (got: $path)"
        return 1
    fi

    # Block path traversal
    case "$path" in
        *..*)
            print_error "SAFETY: Registry path must not contain traversal (got: $path)"
            return 1
            ;;
    esac

    return 0
}
