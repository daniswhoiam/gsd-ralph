#!/bin/bash
# lib/merge/test_runner.sh -- Post-merge test execution with regression detection
#
# Runs the project test suite after merging and compares results against
# the pre-merge baseline. Only halts on newly-introduced regressions;
# pre-existing test failures do not block the merge.

# Run post-merge tests and detect newly-introduced regressions.
#
# Workflow:
#   1. If no test command, warn and return 0 (don't block merge).
#   2. Run tests at current (post-merge) state.
#   3. If tests pass, return 0.
#   4. If tests fail, compare against pre-merge baseline:
#      - If pre-merge also failed: pre-existing failures, return 0.
#      - If pre-merge passed: NEW regressions, return 1.
#   5. If git operations fail during baseline check, warn and return 0.
#
# Args: test_cmd (string), pre_merge_sha (string)
# Returns: 0 if no new regressions, 1 if new regressions detected
run_post_merge_tests() {
    local test_cmd="$1"
    local pre_merge_sha="$2"

    # No test command configured
    if [[ -z "$test_cmd" ]]; then
        print_warning "No test command configured. Skipping post-merge tests."
        return 0
    fi

    print_info "Running post-merge tests: $test_cmd"

    # ── Step 1: Run tests at current (post-merge) state ──
    local post_exit=0
    eval "$test_cmd" >/dev/null 2>&1 || post_exit=$?

    if [[ $post_exit -eq 0 ]]; then
        print_success "All tests passing after merge"
        return 0
    fi

    # ── Step 2: Tests failed -- check pre-merge baseline ──
    print_info "Post-merge tests failed (exit $post_exit). Checking pre-merge baseline..."

    local current_head
    current_head=$(git rev-parse HEAD 2>/dev/null)

    if [[ -z "$current_head" ]] || [[ -z "$pre_merge_sha" ]]; then
        print_warning "Cannot determine git state for baseline check. Skipping regression detection."
        return 0
    fi

    # Save any uncommitted state and checkout pre-merge SHA
    git stash --include-untracked >/dev/null 2>&1 || true

    local checkout_ok=true
    git checkout "$pre_merge_sha" --detach >/dev/null 2>&1 || checkout_ok=false

    if [[ "$checkout_ok" == false ]]; then
        # Git operation failed -- return to post-merge state and don't block
        git checkout "$current_head" --detach >/dev/null 2>&1 || true
        git checkout - >/dev/null 2>&1 || true
        git stash pop >/dev/null 2>&1 || true
        print_warning "Could not checkout pre-merge state for baseline check. Skipping regression detection."
        return 0
    fi

    # ── Step 3: Run tests at pre-merge state ──
    local pre_exit=0
    eval "$test_cmd" >/dev/null 2>&1 || pre_exit=$?

    # ── Step 4: Return to post-merge state ──
    git checkout "$current_head" --detach >/dev/null 2>&1 || true
    git checkout - >/dev/null 2>&1 || true
    git stash pop >/dev/null 2>&1 || true

    # ── Step 5: Compare results ──
    if [[ $pre_exit -ne 0 ]]; then
        # Pre-existing failures -- don't halt
        print_warning "Tests failing, but failures existed before merge. Pre-merge exit: $pre_exit, Post-merge exit: $post_exit."
        return 0
    fi

    # Pre-merge passed but post-merge failed: NEW regressions
    print_error "NEW test regressions introduced by merge!"
    return 1
}
