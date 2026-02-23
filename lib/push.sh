#!/bin/bash
# lib/push.sh -- Remote detection and push operations
#
# Provides has_remote() to check for origin remote and push_branch_to_remote()
# to push branches non-fatally. Push failures are warnings, never crashes.
#
# This file does NOT source common.sh -- the sourcing chain is handled by
# the entry point (bin/gsd-ralph sources common.sh, then commands source this).

# Check if a pushable remote "origin" exists.
# Uses git remote get-url (no network call).
# Returns: 0 if origin exists, 1 if not
has_remote() {
    git remote get-url origin >/dev/null 2>&1
}

# Push a branch to origin, non-fatal.
# Respects AUTO_PUSH setting -- skips if set to "false".
# Always returns 0 -- push failures must never crash the command.
#
# Args:
#   branch_name -- Branch to push
# Returns: 0 always
push_branch_to_remote() {
    local branch_name="$1"

    # Check AUTO_PUSH setting -- opt-out via .ralphrc
    if [[ "${AUTO_PUSH:-true}" == "false" ]]; then
        print_verbose "AUTO_PUSH is disabled, skipping push"
        return 0
    fi

    # Check for origin remote
    if ! has_remote; then
        print_verbose "No origin remote configured, skipping push"
        return 0
    fi

    # Attempt push
    print_info "Pushing $branch_name to origin..."
    if git push -u origin "$branch_name" >/dev/null 2>&1; then
        print_success "Pushed $branch_name to origin"
    else
        print_warning "Could not push $branch_name to origin (network issue or auth failure)"
        print_warning "Branch is still available locally. Push manually with: git push origin $branch_name"
    fi

    return 0
}
