#!/bin/bash
# checks/check-refactor.sh -- Challenge 4 correctness check
# Behavioral checks ONLY -- tests outcomes, not code patterns (HARN-03)
set -uo pipefail

TASKCTL_DIR="${1:-.}"
SCRIPT_DIR="$TASKCTL_DIR/src"
passed=0
failed=0
total=0

# Resolve Bats binary
BATS_BIN=""
if [[ -x "$TASKCTL_DIR/../../tests/bats/bin/bats" ]]; then
    BATS_BIN="$(cd "$TASKCTL_DIR/../../tests/bats/bin" && pwd)/bats"
elif command -v bats >/dev/null 2>&1; then
    BATS_BIN="bats"
fi

check() {
    local name="$1"
    local test_cmd="$2"
    total=$((total + 1))
    if eval "$test_cmd" >/dev/null 2>&1; then
        echo "PASS: $name"
        passed=$((passed + 1))
    else
        echo "FAIL: $name"
        failed=$((failed + 1))
    fi
}

# Check 1: all existing tests pass
# At baseline PASSES (existing tests pass on unmodified code)
check "all existing tests pass" '
    if [[ -z "$BATS_BIN" ]]; then
        echo "SKIP: no bats binary found" >&2
        false
    fi
    (cd "$TASKCTL_DIR" && "$BATS_BIN" tests/test_add.bats tests/test_list.bats)
'

# Check 2: format.sh has more than 10 lines changed
# At baseline FAILS (0 lines changed -- identical to baseline)
check "format.sh has more than 10 lines changed" '
    baseline_format=$(git show bench/baseline:benchmarks/taskctl/src/format.sh 2>/dev/null) || {
        echo "SKIP: cannot access bench/baseline tag" >&2
        false
    }
    diff_output=$(diff <(echo "$baseline_format") "$TASKCTL_DIR/src/format.sh" 2>/dev/null || true)
    diff_lines=$(echo "$diff_output" | grep -c "^[<>]" || echo 0)
    [[ "$diff_lines" -gt 10 ]]
'

# Check 3: ShellCheck warnings reduced
# Baseline has 22 warnings. At baseline FAILS (22 is not less than 22).
check "ShellCheck warnings reduced" '
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "SKIP: shellcheck not installed" >&2
        false
    fi
    baseline_warnings=22
    sc_output=$(shellcheck "$TASKCTL_DIR/src/format.sh" 2>&1 || true)
    current_warnings=$(echo "$sc_output" | grep -c "SC[0-9]" || echo 0)
    [[ "$current_warnings" -lt "$baseline_warnings" ]]
'

# Check 4: no new commands added
# Counts case dispatch entries in taskctl.sh. Baseline has 3 (add, list, done).
# At baseline PASSES (3 <= 3).
check "no new commands added" '
    case_count=$(grep -c "^[[:space:]]*[a-z]*)" "$TASKCTL_DIR/src/taskctl.sh" || echo 0)
    [[ "$case_count" -le 3 ]]
'

echo ""
echo "Score: $passed/$total checks passed"
exit $((failed > 0 ? 1 : 0))
