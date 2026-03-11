#!/bin/bash
# benchmarks/harness/bench-run.sh -- Full benchmark pipeline orchestrator
# Usage: bench-run.sh --mode <mode> --challenge <challenge>
#
# Wires the complete benchmark pipeline end-to-end:
#   parse args -> load challenge -> generate run_id -> create worktree ->
#   capture pre-metrics -> invoke mode -> capture post-metrics -> run eval ->
#   assemble result JSON -> write to results/ -> cleanup
set -euo pipefail

# --------------------------------------------------------------------------
# Source dependencies
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/bench-reset.sh"
source "$SCRIPT_DIR/lib/metrics.sh"

# --------------------------------------------------------------------------
# Usage
# --------------------------------------------------------------------------

usage() {
    echo "Usage: bench-run.sh --mode <mode> --challenge <challenge>"
    echo "Modes: cc"
    echo "Challenges: fix-bug, add-feature, add-tests, refactor, multi-file"
}

# --------------------------------------------------------------------------
# Argument parsing
# --------------------------------------------------------------------------

mode=""
challenge=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode=*)
            mode="${1#--mode=}"
            shift
            ;;
        --mode)
            shift
            mode="${1:-}"
            shift
            ;;
        --challenge=*)
            challenge="${1#--challenge=}"
            shift
            ;;
        --challenge)
            shift
            challenge="${1:-}"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown argument: $1"
            usage >&2
            exit 1
            ;;
    esac
done

if [[ -z "$mode" ]] || [[ -z "$challenge" ]]; then
    usage >&2
    exit 1
fi

# --------------------------------------------------------------------------
# Prerequisite validation
# --------------------------------------------------------------------------

require_command jq
require_command git
require_command uuidgen
require_command timeout
require_command claude

# --------------------------------------------------------------------------
# Main pipeline
# --------------------------------------------------------------------------

main() {
    # Step 1: Load challenge JSON
    local challenge_file
    challenge_file=$(load_challenge "$challenge")
    local starting_tag time_cap_minutes prompt check_count
    starting_tag=$(jq -r '.starting_tag' "$challenge_file")
    time_cap_minutes=$(jq -r '.time_cap_minutes' "$challenge_file")
    prompt=$(jq -r '.prompt' "$challenge_file")
    check_count=$(jq -r '.check_count' "$challenge_file")
    local time_cap_seconds=$((time_cap_minutes * 60))

    # Step 2: Generate run_id
    local run_id
    run_id=$(uuidgen | tr '[:upper:]' '[:lower:]')

    # Step 3: Source mode script
    local mode_script="$SCRIPT_DIR/lib/modes/${mode}.sh"
    if [[ ! -f "$mode_script" ]]; then
        log_error "Unknown mode: $mode (no script at $mode_script)"
        exit 1
    fi
    source "$mode_script"

    # Step 4: Create worktree
    local workdir
    workdir=$(create_run_worktree "$run_id" "$starting_tag")
    # Compute worktree root (2 levels up from benchmarks/taskctl/)
    local worktree_path
    worktree_path=$(cd "$workdir/../.." && pwd)

    # Temp file for claude JSON output
    local claude_json_file
    claude_json_file=$(mktemp)

    # Cleanup on exit: remove worktree and temp file
    trap "cleanup_run_worktree '$run_id'; rm -f '$claude_json_file'" EXIT

    # Step 5: Capture pre-run metrics
    local sc_before git_sha cli_version
    sc_before=$(capture_shellcheck_baseline "$workdir")
    git_sha=$(git -C "$BENCH_REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
    cli_version=$(claude --version 2>/dev/null || echo "unknown")
    local start_time
    start_time=$(date +%s)

    # Step 6: Invoke mode
    log_info "Running $mode mode for challenge '$challenge' (run_id: $run_id)"
    log_info "Time cap: ${time_cap_minutes}m (${time_cap_seconds}s)"

    local invoke_exit=0
    mode_invoke "$prompt" "$workdir" "$DEFAULT_MAX_TURNS" "$time_cap_seconds" > "$claude_json_file" 2>/dev/null || invoke_exit=$?

    local timed_out="false"
    if [[ $invoke_exit -eq 124 ]]; then
        timed_out="true"
        log_info "Run timed out after ${time_cap_seconds}s"
    elif [[ $invoke_exit -ne 0 ]]; then
        log_info "Mode exited with code $invoke_exit"
    fi

    # Step 7: Capture post-run metrics
    local end_time wall_clock
    end_time=$(date +%s)
    wall_clock=$((end_time - start_time))

    # Extract claude metrics from JSON output
    local session_id="unknown" cost_usd=0 duration_ms=0 num_turns=0
    if [[ -f "$claude_json_file" ]] && jq empty "$claude_json_file" 2>/dev/null; then
        session_id=$(jq -r '.session_id // "unknown"' "$claude_json_file")
        cost_usd=$(jq -r '.total_cost_usd // 0' "$claude_json_file")
        duration_ms=$(jq -r '.duration_ms // 0' "$claude_json_file")
        num_turns=$(jq -r '.num_turns // 0' "$claude_json_file")
    fi

    local sc_after commit_count conventional tests_added
    sc_after=$(capture_shellcheck_post "$workdir")
    commit_count=$(count_commits "$worktree_path" "$starting_tag")
    conventional=$(check_conventional_commits "$worktree_path" "$starting_tag")
    tests_added=$(count_tests_added "$worktree_path" "$starting_tag")

    # Step 8: Run evaluation
    log_info "Running correctness evaluation..."
    local eval_exit=0
    local eval_output
    eval_output=$(bash "$HARNESS_DIR/bench-eval.sh" "$challenge" "$workdir" 2>/dev/null) || eval_exit=$?
    local correctness_score
    correctness_score=$(parse_eval_score "$eval_output")
    # Regression score: for now, same as correctness (existing tests are part of check scripts)
    local regression_score=100

    # Step 9: Compute derived values and assemble result JSON
    local shellcheck_delta=0
    if [[ "$sc_before" != "null" ]] && [[ "$sc_after" != "null" ]]; then
        shellcheck_delta=$((sc_after - sc_before))
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    ensure_results_dir
    local result_file="$RESULTS_DIR/${mode}-${challenge}-${run_id}.json"

    jq -n \
        --arg mode "$mode" \
        --arg challenge "$challenge" \
        --arg timestamp "$timestamp" \
        --arg run_id "$run_id" \
        --argjson wall_clock_seconds "$wall_clock" \
        --argjson tokens_input 0 \
        --argjson tokens_output 0 \
        --argjson num_turns "$num_turns" \
        --argjson iterations 1 \
        --argjson human_interventions 0 \
        --argjson correctness_score "$correctness_score" \
        --argjson regression_score "$regression_score" \
        --argjson tests_added "$tests_added" \
        --argjson shellcheck_warnings_delta "$shellcheck_delta" \
        --argjson commits "$commit_count" \
        --argjson conventional_commits "$conventional" \
        --argjson timed_out "$timed_out" \
        --arg session_id "$session_id" \
        --arg cost_usd_str "$cost_usd" \
        --argjson duration_ms "$duration_ms" \
        --arg model_version "$BENCH_MODEL_VERSION" \
        --arg cli_version "$cli_version" \
        --arg git_sha "$git_sha" \
        '{
            mode: $mode,
            challenge: $challenge,
            timestamp: $timestamp,
            run_id: $run_id,
            wall_clock_seconds: $wall_clock_seconds,
            tokens_input: $tokens_input,
            tokens_output: $tokens_output,
            num_turns: $num_turns,
            iterations: $iterations,
            human_interventions: $human_interventions,
            correctness_score: $correctness_score,
            regression_score: $regression_score,
            tests_added: $tests_added,
            shellcheck_warnings_delta: $shellcheck_warnings_delta,
            commits: $commits,
            conventional_commits: $conventional_commits,
            timed_out: $timed_out,
            session_id: $session_id,
            total_cost_usd: ($cost_usd_str | tonumber),
            duration_ms: $duration_ms,
            model_version: $model_version,
            cli_version: $cli_version,
            git_sha: $git_sha
        }' > "$result_file"

    # Step 10: Print result path and summary
    log_info "Result written to: $result_file"
    log_info "Correctness: ${correctness_score}% | Time: ${wall_clock}s | Turns: ${num_turns} | Cost: \$${cost_usd}"
    echo "$result_file"
}

main
