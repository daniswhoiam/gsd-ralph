#!/bin/bash
# harness/lib/modes/cc.sh -- CC mode: direct claude -p invocation
# Sourced by bench-run.sh. Do NOT execute directly.
#
# Mode Contract:
# All mode scripts must implement mode_invoke() with this signature:
#   mode_invoke(prompt, workdir, max_turns, time_cap_seconds)
#     - stdout: JSON from the mode's execution
#     - stderr: redirected to workdir/.bench-stderr.log
#     - exit code: 0 = normal, 124 = timeout, other = error
#     - side effects: modifies files in workdir
set -euo pipefail

# Source guard: prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: cc.sh must be sourced, not executed directly." >&2
    exit 1
fi

# mode_invoke(prompt, workdir, max_turns, time_cap_seconds)
#   Invokes claude -p with --output-format json under a time cap.
#   This is CC mode: the simplest mode -- a single claude -p call.
#   The caller (bench-run.sh) handles exit code interpretation and metric extraction.
mode_invoke() {
    local prompt="${1:?Usage: mode_invoke <prompt> <workdir> <max_turns> <time_cap_seconds>}"
    local workdir="${2:?Usage: mode_invoke <prompt> <workdir> <max_turns> <time_cap_seconds>}"
    local max_turns="${3:?Usage: mode_invoke <prompt> <workdir> <max_turns> <time_cap_seconds>}"
    local time_cap_seconds="${4:?Usage: mode_invoke <prompt> <workdir> <max_turns> <time_cap_seconds>}"

    # cd into workdir to scope Claude's default working directory to benchmarks/taskctl/
    # This prevents Claude from modifying files outside the challenge project (Pitfall 5)
    cd "$workdir"

    # Invoke claude -p under timeout with structured JSON output
    # --permission-mode auto: auto-approves tool use (safer than --dangerously-skip-permissions)
    # --no-session-persistence: avoids accumulating session files during benchmark runs
    # Exit codes: 0 = normal completion, 124 = timeout (from GNU timeout), other = claude error
    # Let exit code propagate naturally -- caller handles interpretation
    timeout "$time_cap_seconds" \
        claude -p "$prompt" \
        --output-format json \
        --max-turns "$max_turns" \
        --permission-mode auto \
        --no-session-persistence \
        2>"$workdir/.bench-stderr.log"
}
