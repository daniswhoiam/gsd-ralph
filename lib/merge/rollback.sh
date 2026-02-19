#!/bin/bash
# lib/merge/rollback.sh -- Rollback point saving and restoration for merge operations
#
# Saves pre-merge SHA to a JSON file and provides rollback capability.
# Rollback scope is phase-level: resets to the SHA captured before any
# merges for the phase began.

# Rollback state file location
ROLLBACK_FILE=".ralph/merge-rollback.json"

# Save a rollback point before starting merges for a phase.
# Uses cat heredoc for initial creation (no dependency on existing file).
# Args: phase_num
# Returns: 0 on success
save_rollback_point() {
    local phase_num="$1"
    local sha
    sha=$(git rev-parse HEAD)
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Ensure .ralph directory exists
    mkdir -p .ralph

    cat > "$ROLLBACK_FILE" <<EOF
{
  "phase": ${phase_num},
  "pre_merge_sha": "${sha}",
  "timestamp": "${timestamp}",
  "branches_merged": []
}
EOF
    return 0
}

# Record a successfully merged branch in the rollback file.
# Args: branch_name, sha_before
# Returns: 0 on success, 1 if rollback file missing
record_merged_branch() {
    local branch="$1"
    local sha_before="$2"
    local sha_after
    sha_after=$(git rev-parse HEAD)

    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        print_error "No rollback file found. Call save_rollback_point first."
        return 1
    fi

    local tmp
    tmp=$(jq --arg b "$branch" --arg before "$sha_before" --arg after "$sha_after" \
        '.branches_merged += [{"branch": $b, "sha_before": $before, "sha_after": $after}]' \
        "$ROLLBACK_FILE")
    printf '%s\n' "$tmp" > "$ROLLBACK_FILE"
    return 0
}

# Rollback to the pre-merge state for a phase.
# Reads the saved SHA from the rollback file and resets to it.
# Args: phase_num
# Returns: 0 on success, exits with error if no rollback file
rollback_merge() {
    local phase_num="$1"

    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        die "No rollback point found for phase ${phase_num}. Nothing to roll back."
    fi

    local saved_sha
    saved_sha=$(jq -r '.pre_merge_sha' "$ROLLBACK_FILE")

    if [[ -z "$saved_sha" ]] || [[ "$saved_sha" == "null" ]]; then
        die "Invalid rollback file: no pre_merge_sha found."
    fi

    print_warning "Rollback is only possible before pushing merged changes."
    git reset --hard "$saved_sha" >/dev/null 2>&1
    rm -f "$ROLLBACK_FILE"
    print_success "Rolled back to pre-merge state: ${saved_sha}"
    return 0
}

# Check if a rollback point exists and is valid.
# Returns: 0 if valid rollback file exists, 1 otherwise
has_rollback_point() {
    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        return 1
    fi

    # Verify it is valid JSON with the expected field
    if jq -e '.pre_merge_sha' "$ROLLBACK_FILE" >/dev/null 2>&1; then
        return 0
    fi

    return 1
}
