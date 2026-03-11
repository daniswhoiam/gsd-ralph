#!/bin/bash
# checks/check-add-tests.sh -- Challenge 3 correctness check
# Behavioral checks ONLY -- tests outcomes, not code patterns (HARN-03)
set -uo pipefail

TASKCTL_DIR="${1:-.}"
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

# Check 1: test_storage.bats exists
# At baseline FAILS: file does not exist
check "test_storage.bats exists" '
    [[ -f "$TASKCTL_DIR/tests/test_storage.bats" ]]
'

# Check 2: at least 5 tests in test_storage.bats
# At baseline FAILS: file does not exist
check "at least 5 tests in test_storage.bats" '
    [[ -f "$TASKCTL_DIR/tests/test_storage.bats" ]]
    test_count=$(grep -c "@test" "$TASKCTL_DIR/tests/test_storage.bats")
    [[ "$test_count" -ge 5 ]]
'

# Check 3: all storage tests pass
# At baseline FAILS: file does not exist
check "all storage tests pass" '
    if [[ -z "$BATS_BIN" ]]; then
        echo "SKIP: no bats binary found" >&2
        false
    fi
    [[ -f "$TASKCTL_DIR/tests/test_storage.bats" ]]
    (cd "$TASKCTL_DIR" && "$BATS_BIN" tests/test_storage.bats)
'

# Check 4: storage.sh unchanged from baseline
# At baseline PASSES (storage.sh is untouched). If git is not available, skip with PASS.
check "storage.sh unchanged from baseline" '
    if command -v git >/dev/null 2>&1; then
        baseline_storage=$(git show bench/baseline:benchmarks/taskctl/src/storage.sh 2>/dev/null) || true
        if [[ -n "$baseline_storage" ]]; then
            current_storage=$(cat "$TASKCTL_DIR/src/storage.sh")
            [[ "$baseline_storage" = "$current_storage" ]]
        else
            # Cannot access bench/baseline tag -- skip with PASS
            true
        fi
    else
        # No git available -- skip with PASS
        true
    fi
'

echo ""
echo "Score: $passed/$total checks passed"
exit $((failed > 0 ? 1 : 0))
