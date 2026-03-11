#!/bin/bash
# benchmarks/harness/lib/common.sh -- Shared constants, logging, and path resolution
# Must be sourced, not executed directly.
set -euo pipefail

# Source guard: prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Error: common.sh must be sourced, not executed" >&2
    exit 1
fi

# --------------------------------------------------------------------------
# Path resolution
# --------------------------------------------------------------------------

# HARNESS_DIR: one level up from lib/
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# CHALLENGES_DIR: sibling to harness/
CHALLENGES_DIR="$(cd "$HARNESS_DIR/../challenges" && pwd)"

# RESULTS_DIR: sibling to harness/
RESULTS_DIR="$HARNESS_DIR/../results"

# BENCH_REPO_ROOT: main repo root (not worktree)
BENCH_REPO_ROOT="$(git -C "$HARNESS_DIR" rev-parse --show-toplevel)"

# --------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------

# Temp directory for worktrees (configurable via env var)
BENCH_TMPDIR="${BENCH_TMPDIR:-/tmp}"

# Model version -- update when the default Claude Code model changes
BENCH_MODEL_VERSION="claude-opus-4-20250514"

# Default max turns for CC mode (generous default)
DEFAULT_MAX_TURNS=50

# --------------------------------------------------------------------------
# Logging functions
# --------------------------------------------------------------------------

log_info() {
    echo "[bench] $*" >&2
}

log_error() {
    echo "[bench:ERROR] $*" >&2
}

# --------------------------------------------------------------------------
# Utility functions
# --------------------------------------------------------------------------

# require_command -- check that a command is available
# Usage: require_command jq
require_command() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
}

# load_challenge -- resolve and validate a challenge JSON file
# Usage: load_challenge fix-bug
# Echoes the full path to the challenge JSON file on stdout
load_challenge() {
    local challenge_name="$1"
    local challenge_file="$CHALLENGES_DIR/${challenge_name}.json"

    if [[ ! -f "$challenge_file" ]]; then
        log_error "Challenge not found: $challenge_name (expected $challenge_file)"
        exit 1
    fi

    echo "$challenge_file"
}

# ensure_results_dir -- create the results directory if it does not exist
ensure_results_dir() {
    mkdir -p "$RESULTS_DIR"
}
