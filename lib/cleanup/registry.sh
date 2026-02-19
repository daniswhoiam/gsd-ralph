#!/bin/bash
# lib/cleanup/registry.sh -- Worktree registry for tracking created worktrees and branches
#
# Provides init, register, list, deregister, and validate functions for a JSON
# registry file at .ralph/worktree-registry.json. The registry is keyed by phase
# number and stores arrays of {worktree_path, branch, created_at} entries.

# Registry file location
WORKTREE_REGISTRY=".ralph/worktree-registry.json"

# Initialize the registry file if it does not exist.
# Creates a version-1 JSON object. If the file exists but is invalid JSON,
# prints a warning and recreates it.
# Returns: 0 on success
init_registry() {
    if [[ -f "$WORKTREE_REGISTRY" ]]; then
        # Validate existing file is parseable JSON
        if ! jq -e . "$WORKTREE_REGISTRY" >/dev/null 2>&1; then
            print_warning "Registry file is invalid JSON, recreating: $WORKTREE_REGISTRY"
            printf '%s\n' '{"version": 1}' > "$WORKTREE_REGISTRY"
        fi
        return 0
    fi

    # Ensure .ralph directory exists
    mkdir -p "$(dirname "$WORKTREE_REGISTRY")"
    printf '%s\n' '{"version": 1}' > "$WORKTREE_REGISTRY"
    print_verbose "Initialized worktree registry at $WORKTREE_REGISTRY"
    return 0
}

# Register a worktree and branch for a phase.
# Args: phase_num, worktree_path, branch_name
# Returns: 0 on success
register_worktree() {
    local phase_num="$1"
    local worktree_path="$2"
    local branch_name="$3"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    init_registry

    local tmp
    tmp=$(jq --arg phase "$phase_num" \
             --arg wt "$worktree_path" \
             --arg br "$branch_name" \
             --arg ts "$timestamp" \
        'if .[$phase] then
            .[$phase] += [{"worktree_path": $wt, "branch": $br, "created_at": $ts}]
         else
            .[$phase] = [{"worktree_path": $wt, "branch": $br, "created_at": $ts}]
         end' "$WORKTREE_REGISTRY")
    printf '%s\n' "$tmp" > "$WORKTREE_REGISTRY"

    print_verbose "Registered worktree for phase $phase_num: $branch_name"
    return 0
}

# List registered worktrees for a phase.
# Args: phase_num
# Output: JSON array of entries (or empty array if no registry or no entries)
list_registered_worktrees() {
    local phase_num="$1"

    if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
        echo '[]'
        return
    fi

    jq --arg phase "$phase_num" '.[$phase] // []' "$WORKTREE_REGISTRY"
}

# Deregister all worktrees for a phase (remove the phase key).
# Args: phase_num
# Returns: 0 always
deregister_phase() {
    local phase_num="$1"

    if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
        return 0
    fi

    local tmp
    tmp=$(jq --arg phase "$phase_num" 'del(.[$phase])' "$WORKTREE_REGISTRY")
    printf '%s\n' "$tmp" > "$WORKTREE_REGISTRY"

    print_verbose "Deregistered phase $phase_num from worktree registry"
    return 0
}

# Validate the registry file exists and contains valid JSON.
# Returns: 0 if valid, 1 otherwise
validate_registry() {
    if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
        return 1
    fi

    jq -e . "$WORKTREE_REGISTRY" >/dev/null 2>&1
}
