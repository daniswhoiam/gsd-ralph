#!/bin/bash
# harness/lib/metrics.sh -- Metric extraction from claude -p JSON output and bench-eval.sh results
# Sourced by bench-run.sh. Do NOT execute directly.
set -euo pipefail

# Source guard: prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: metrics.sh must be sourced, not executed directly." >&2
    exit 1
fi

# extract_metrics(json_file)
#   Extracts structured metrics from claude -p --output-format json output.
#   Outputs a JSON object with defensive fallbacks for missing fields.
#   Per research Pitfall 1: tokens are NOT available in --output-format json top level.
#   Uses num_turns and total_cost_usd as primary efficiency metrics.
extract_metrics() {
    local json_file="${1:?Usage: extract_metrics <json_file>}"

    # Validate JSON is parseable
    if ! jq empty "$json_file" 2>/dev/null; then
        echo '{"error": "invalid_json"}'
        return 1
    fi

    jq '{
        session_id: (.session_id // "unknown"),
        total_cost_usd: (.total_cost_usd // 0),
        duration_ms: (.duration_ms // 0),
        duration_api_ms: (.duration_api_ms // 0),
        num_turns: (.num_turns // 0),
        is_error: (.is_error // false),
        result_text: (.result // "")
    }' "$json_file"
}

# parse_eval_score(eval_output)
#   Parses "Score: X/Y checks passed" from bench-eval.sh stdout.
#   Returns integer percentage (0-100).
parse_eval_score() {
    local eval_output="$1"

    # Extract the "Score: X/Y checks passed" line
    local score_line
    score_line=$(echo "$eval_output" | grep -E '^Score: [0-9]+/[0-9]+') || score_line=""

    if [[ -z "$score_line" ]]; then
        echo "0"
        return
    fi

    # Parse passed and total counts
    local passed total
    passed=$(echo "$score_line" | sed -E 's/^Score: ([0-9]+)\/[0-9]+.*/\1/')
    total=$(echo "$score_line" | sed -E 's/^Score: [0-9]+\/([0-9]+).*/\1/')

    if [[ "$total" -eq 0 ]]; then
        echo "0"
        return
    fi

    # Compute integer percentage
    echo $(( (passed * 100) / total ))
}

# capture_shellcheck_baseline(workdir)
#   Counts ShellCheck warnings in the taskctl source directory before Claude's changes.
#   workdir: path to benchmarks/taskctl/ in the worktree
#   Outputs warning count (integer) or "null" if shellcheck is not available.
capture_shellcheck_baseline() {
    local workdir="${1:?Usage: capture_shellcheck_baseline <workdir>}"

    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "null"
        return
    fi

    local count
    count=$(shellcheck -f json "$workdir/src/"*.sh "$workdir/src/commands/"*.sh 2>/dev/null | jq 'length' 2>/dev/null) || count=0
    echo "${count:-0}"
}

# capture_shellcheck_post(workdir)
#   Counts ShellCheck warnings after Claude's changes. Identical to baseline.
#   Separate function name for clarity in bench-run.sh pipeline.
capture_shellcheck_post() {
    local workdir="${1:?Usage: capture_shellcheck_post <workdir>}"

    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "null"
        return
    fi

    local count
    count=$(shellcheck -f json "$workdir/src/"*.sh "$workdir/src/commands/"*.sh 2>/dev/null | jq 'length' 2>/dev/null) || count=0
    echo "${count:-0}"
}

# count_commits(worktree_path, starting_tag)
#   Counts commits made since the starting tag in the given worktree.
count_commits() {
    local worktree_path="${1:?Usage: count_commits <worktree_path> <starting_tag>}"
    local starting_tag="${2:?Usage: count_commits <worktree_path> <starting_tag>}"

    git -C "$worktree_path" log --oneline "${starting_tag}..HEAD" 2>/dev/null | wc -l | tr -d ' '
}

# check_conventional_commits(worktree_path, starting_tag)
#   Returns "true" if all commits since starting_tag follow conventional commit format,
#   "false" otherwise.
check_conventional_commits() {
    local worktree_path="${1:?Usage: check_conventional_commits <worktree_path> <starting_tag>}"
    local starting_tag="${2:?Usage: check_conventional_commits <worktree_path> <starting_tag>}"

    local total
    total=$(git -C "$worktree_path" log --oneline "${starting_tag}..HEAD" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$total" -eq 0 ]]; then
        echo "true"
        return
    fi

    # Count commits that do NOT match conventional commit pattern
    local bad
    bad=$(git -C "$worktree_path" log --format='%s' "${starting_tag}..HEAD" 2>/dev/null \
        | grep -cvE '^(feat|fix|chore|docs|test|refactor|style|perf|build|ci)(\(.+\))?: .+') || bad=0

    if [[ "$bad" -eq 0 ]]; then
        echo "true"
    else
        echo "false"
    fi
}

# count_tests_added(worktree_path, starting_tag)
#   Counts new .bats test files added since the starting tag.
#   Rough proxy for test additions; exact test function count is harder to capture.
count_tests_added() {
    local worktree_path="${1:?Usage: count_tests_added <worktree_path> <starting_tag>}"
    local starting_tag="${2:?Usage: count_tests_added <worktree_path> <starting_tag>}"

    local count
    count=$(git -C "$worktree_path" diff --name-only --diff-filter=A "${starting_tag}..HEAD" 2>/dev/null \
        | grep -c '\.bats$') || count=0
    echo "$count"
}
