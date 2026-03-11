#!/bin/bash
# checks/check-fix-bug.sh -- Challenge 1 correctness check
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

# Check 1: done 3 marks task with id=3
# At baseline this FAILS: done 3 uses array index [3] which is task id=4
check "done 3 marks task with id=3" '
    tmpdata=$(mktemp /tmp/taskctl_check_XXXX.json)
    trap "rm -f \"$tmpdata\"" RETURN
    cp "$TASKCTL_DIR/.taskctl.json" "$tmpdata"
    (
        export TASKCTL_DATA="$tmpdata"
        export STORAGE_FILE="$tmpdata"
        source "$SCRIPT_DIR/storage.sh"
        source "$SCRIPT_DIR/format.sh"
        source "$SCRIPT_DIR/commands/done.sh"
        cmd_done 3
    ) >/dev/null 2>&1
    task3_done=$(jq -r ".[] | select(.id == 3) | .done" "$tmpdata")
    [[ "$task3_done" = "true" ]]
'

# Check 2: Existing tests pass
# Should pass at both baseline and after fix
check "existing tests pass" '
    if [[ -z "$BATS_BIN" ]]; then
        echo "SKIP: no bats binary found" >&2
        false
    fi
    (cd "$TASKCTL_DIR" && "$BATS_BIN" tests/test_add.bats tests/test_list.bats)
'

# Check 3: Test coverage for done command exists
# At baseline FAILS: no test_done.bats, exactly 7 tests
check "test coverage for done command exists" '
    if [[ -f "$TASKCTL_DIR/tests/test_done.bats" ]]; then
        true
    else
        # Count total @test across all bats files
        test_count=0
        for f in "$TASKCTL_DIR/tests/"*.bats; do
            if [[ -f "$f" ]]; then
                c=$(grep -c "@test" "$f" 2>/dev/null || echo 0)
                test_count=$((test_count + c))
            fi
        done
        [[ "$test_count" -gt 7 ]]
    fi
'

echo ""
echo "Score: $passed/$total checks passed"
exit $((failed > 0 ? 1 : 0))
