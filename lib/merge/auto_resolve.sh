#!/bin/bash
# lib/merge/auto_resolve.sh -- Auto-resolution of known safe file conflicts
#
# Resolves merge conflicts in predictable files (.planning/, lock files,
# generated files) by preferring main's version (--ours during merge on main).
# Files not matching known patterns are left unresolved.

# Glob patterns for files that can be auto-resolved by preferring main's version.
# These are files that are either regenerated or where main is authoritative.
# shellcheck disable=SC2034
AUTO_RESOLVE_PATTERNS=(
    ".planning/*"
    "package-lock.json"
    "yarn.lock"
    "pnpm-lock.yaml"
    "Cargo.lock"
    "*.lock"
    ".gitignore"
)

# Globals set by auto_resolve_known_conflicts
AUTO_RESOLVED=""
AUTO_REMAINING=""

# Check if a file path matches any auto-resolve pattern.
# Uses case statement with glob matching for Bash 3.2 compatibility.
# Args: file_path
# Returns: 0 if matches any pattern, 1 if not
matches_auto_resolve_pattern() {
    local file_path="$1"

    # Check each pattern using case statement (Bash 3.2 compatible glob matching)
    # Specific patterns before globs to avoid ShellCheck SC2221/SC2222
    case "$file_path" in
        .planning/*)       return 0 ;;
        package-lock.json) return 0 ;;
        pnpm-lock.yaml)    return 0 ;;
        .gitignore)        return 0 ;;
        *.lock)            return 0 ;;
    esac

    return 1
}

# Auto-resolve known safe conflicts by preferring main's version (--ours).
# Gets list of conflicted files, resolves matching ones, tracks results.
# Sets: AUTO_RESOLVED (space-separated resolved files)
#       AUTO_REMAINING (space-separated unresolved files)
# Returns: 0 if all conflicts resolved, 1 if some remain
auto_resolve_known_conflicts() {
    AUTO_RESOLVED=""
    AUTO_REMAINING=""

    # Get list of conflicted files
    local conflicted_output
    conflicted_output=$(git diff --name-only --diff-filter=U 2>/dev/null)

    if [[ -z "$conflicted_output" ]]; then
        # No conflicts to resolve
        return 0
    fi

    local file
    local all_resolved=true

    while IFS= read -r file; do
        [[ -z "$file" ]] && continue

        if matches_auto_resolve_pattern "$file"; then
            git checkout --ours -- "$file" 2>/dev/null
            git add "$file" 2>/dev/null
            if [[ -n "$AUTO_RESOLVED" ]]; then
                AUTO_RESOLVED="$AUTO_RESOLVED $file"
            else
                AUTO_RESOLVED="$file"
            fi
        else
            all_resolved=false
            if [[ -n "$AUTO_REMAINING" ]]; then
                AUTO_REMAINING="$AUTO_REMAINING $file"
            else
                AUTO_REMAINING="$file"
            fi
        fi
    done <<< "$conflicted_output"

    if [[ "$all_resolved" == true ]]; then
        # All conflicts resolved -- complete the merge commit
        git commit --no-edit >/dev/null 2>&1
        return 0
    fi

    return 1
}
