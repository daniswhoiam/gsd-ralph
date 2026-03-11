#!/bin/bash
# checks/check-add-feature.sh -- Challenge 2 correctness check
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

# Check 1: delete removes a task
# At baseline FAILS: no delete command
check "delete removes a task" '
    tmpdata=$(mktemp /tmp/taskctl_check_XXXX.json)
    trap "rm -f \"$tmpdata\"" RETURN
    cp "$TASKCTL_DIR/.taskctl.json" "$tmpdata"
    TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" delete 1 >/dev/null 2>&1
    task1_exists=$(jq "[.[] | select(.id == 1)] | length" "$tmpdata")
    [[ "$task1_exists" -eq 0 ]]
'

# Check 2: delete nonexistent ID shows error
# At baseline FAILS: no delete command
check "delete nonexistent ID shows error" '
    tmpdata=$(mktemp /tmp/taskctl_check_XXXX.json)
    trap "rm -f \"$tmpdata\"" RETURN
    cp "$TASKCTL_DIR/.taskctl.json" "$tmpdata"
    output=$(TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" delete 999 2>&1 || true)
    echo "$output" | grep -qi "not found\|error\|no task\|invalid"
'

# Check 3: test_delete.bats exists with 2+ tests
# At baseline FAILS: no test_delete.bats
check "test_delete.bats exists with 2+ tests" '
    [[ -f "$TASKCTL_DIR/tests/test_delete.bats" ]]
    test_count=$(grep -c "@test" "$TASKCTL_DIR/tests/test_delete.bats")
    [[ "$test_count" -ge 2 ]]
'

# Check 4: existing tests pass
# Should pass at both baseline and after fix
check "existing tests pass" '
    if [[ -z "$BATS_BIN" ]]; then
        echo "SKIP: no bats binary found" >&2
        false
    fi
    (cd "$TASKCTL_DIR" && "$BATS_BIN" tests/test_add.bats tests/test_list.bats)
'

echo ""
echo "Score: $passed/$total checks passed"
exit $((failed > 0 ? 1 : 0))
