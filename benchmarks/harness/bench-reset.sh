#!/bin/bash
# benchmarks/harness/bench-reset.sh -- Worktree lifecycle management
# Creates isolated git worktrees for benchmark runs and cleans them up.
#
# Can be sourced (provides create_run_worktree/cleanup_run_worktree functions)
# or run directly as a CLI:
#   bench-reset.sh create <run_id> <starting_tag>
#   bench-reset.sh cleanup <run_id>
#   bench-reset.sh --help
set -euo pipefail

# Source the shared library
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/common.sh"

# --------------------------------------------------------------------------
# Functions
# --------------------------------------------------------------------------

# create_run_worktree -- create an isolated git worktree for a benchmark run
# Arguments: run_id (string), starting_tag (string)
# Stdout: path to the workdir (benchmarks/taskctl inside the worktree)
create_run_worktree() {
    local run_id="$1"
    local starting_tag="$2"
    local worktree_path="${BENCH_TMPDIR}/bench-run-${run_id}"

    # Create detached worktree at the challenge starting tag
    # Redirect both stdout and stderr: git outputs "HEAD is now at..." to stdout
    if ! git -C "$BENCH_REPO_ROOT" -c advice.detachedHead=false worktree add --detach "$worktree_path" "$starting_tag" >/dev/null 2>&1; then
        log_error "Failed to create worktree at tag '$starting_tag'"
        return 1
    fi

    local workdir="$worktree_path/benchmarks/taskctl"

    # Validate starting state
    if [[ ! -f "$workdir/src/taskctl.sh" ]]; then
        log_error "taskctl not found at tag $starting_tag (expected $workdir/src/taskctl.sh)"
        # Clean up the broken worktree
        git -C "$BENCH_REPO_ROOT" worktree remove --force "$worktree_path" 2>/dev/null || true
        return 1
    fi

    # Clean any untracked files for safety
    git -C "$worktree_path" clean -fdx 2>/dev/null

    # Verify worktree HEAD matches expected starting tag commit (HARN-01 checksum)
    local expected_sha actual_sha
    expected_sha=$(git -C "$BENCH_REPO_ROOT" rev-parse "$starting_tag" 2>/dev/null)
    actual_sha=$(git -C "$worktree_path" rev-parse HEAD 2>/dev/null)
    if [[ "$expected_sha" != "$actual_sha" ]]; then
        log_error "Worktree commit mismatch: expected ${expected_sha:-unknown} (tag: $starting_tag) but got ${actual_sha:-unknown}"
        git -C "$BENCH_REPO_ROOT" worktree remove --force "$worktree_path" 2>/dev/null || true
        return 1
    fi
    log_info "Worktree verified at commit ${actual_sha:0:8} (tag: $starting_tag)"

    # Initialize submodules (needed for Bats helpers per Phase 21 lessons)
    git -C "$worktree_path" submodule update --init --recursive >/dev/null 2>&1 || true

    # Return the workdir path on stdout
    echo "$workdir"

    log_info "Created worktree at $worktree_path (tag: $starting_tag)"
}

# cleanup_run_worktree -- remove a benchmark run's worktree
# Arguments: run_id (string)
cleanup_run_worktree() {
    local run_id="$1"
    local worktree_path="${BENCH_TMPDIR}/bench-run-${run_id}"

    git -C "$BENCH_REPO_ROOT" worktree remove --force "$worktree_path" 2>/dev/null || true

    log_info "Cleaned up worktree for run $run_id"
}

# --------------------------------------------------------------------------
# CLI mode (when executed directly, not sourced)
# --------------------------------------------------------------------------

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    usage() {
        echo "Usage: bench-reset.sh <command> [args]"
        echo ""
        echo "Commands:"
        echo "  create <run_id> <starting_tag>   Create an isolated worktree"
        echo "  cleanup <run_id>                 Remove a worktree"
        echo "  --help                           Show this help"
    }

    if [[ $# -lt 1 ]]; then
        usage >&2
        exit 1
    fi

    case "$1" in
        create)
            if [[ $# -lt 3 ]]; then
                echo "Error: create requires <run_id> and <starting_tag>" >&2
                usage >&2
                exit 1
            fi
            create_run_worktree "$2" "$3"
            ;;
        cleanup)
            if [[ $# -lt 2 ]]; then
                echo "Error: cleanup requires <run_id>" >&2
                usage >&2
                exit 1
            fi
            cleanup_run_worktree "$2"
            ;;
        --help|-h)
            usage
            ;;
        *)
            echo "Error: Unknown command '$1'" >&2
            usage >&2
            exit 1
            ;;
    esac
fi
