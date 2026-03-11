#!/bin/bash
# checks/check-multi-file.sh -- Challenge 5 correctness check
# Behavioral checks ONLY -- tests outcomes, not code patterns (HARN-03)
# Starting state: bench/after-delete (NOT bench/baseline)
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

# Check 1: priority stored on add
# At after-delete FAILS (add does not accept --priority)
check "priority stored on add" '
    tmpdata=$(mktemp /tmp/taskctl_check_XXXX.json)
    trap "rm -f \"$tmpdata\"" RETURN
    echo "[]" > "$tmpdata"
    TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" add --priority high "Deploy fix"
    priority=$(jq -r ".[0].priority" "$tmpdata")
    [[ "$priority" = "high" ]]
'

# Check 2: default priority is low
# At after-delete FAILS (no priority support)
check "default priority is low" '
    tmpdata=$(mktemp /tmp/taskctl_check_XXXX.json)
    trap "rm -f \"$tmpdata\"" RETURN
    echo "[]" > "$tmpdata"
    TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" add "Normal task"
    priority=$(jq -r ".[0].priority // empty" "$tmpdata")
    [[ "$priority" = "low" ]]
'

# Check 3: list --sort priority orders correctly
# At after-delete FAILS (no --sort priority support)
check "list --sort priority orders correctly" '
    tmpdata=$(mktemp /tmp/taskctl_check_XXXX.json)
    trap "rm -f \"$tmpdata\"" RETURN
    echo "[]" > "$tmpdata"
    TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" add --priority low "Low task"
    TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" add --priority high "Deploy fix"
    TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" add --priority medium "Medium task"
    output=$(TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" list --sort priority 2>&1)
    first_task=$(echo "$output" | grep -v "^$" | head -1)
    echo "$first_task" | grep -q "Deploy fix"
'

# Check 4: at least 3 priority tests exist
# At after-delete FAILS (no priority tests)
check "at least 3 priority tests exist" '
    priority_test_count=0
    for f in "$TASKCTL_DIR/tests/"*.bats; do
        if [[ -f "$f" ]]; then
            c=$(grep -ci "@test.*\(priority\|sort\)" "$f" 2>/dev/null) || c=0
            priority_test_count=$((priority_test_count + c))
        fi
    done
    [[ "$priority_test_count" -ge 3 ]]
'

# Check 5: existing tests pass
# At after-delete PASSES (test_add, test_list, test_delete all pass)
check "existing tests pass" '
    if [[ -z "$BATS_BIN" ]]; then
        echo "SKIP: no bats binary found" >&2
        false
    fi
    # Run the tests that exist at after-delete state
    test_files=""
    for f in test_add.bats test_list.bats test_delete.bats; do
        if [[ -f "$TASKCTL_DIR/tests/$f" ]]; then
            test_files="$test_files tests/$f"
        fi
    done
    if [[ -z "$test_files" ]]; then
        false
    fi
    (cd "$TASKCTL_DIR" && $BATS_BIN $test_files)
'

# Check 6: changes span 3+ source files
# At after-delete FAILS (0 files changed)
check "changes span 3+ source files" '
    changed_count=0
    if command -v git >/dev/null 2>&1; then
        # Try git diff first (works in worktrees)
        diff_output=$(git diff --name-only bench/after-delete -- "$TASKCTL_DIR/src/" 2>/dev/null) || diff_output=""
        if [[ -n "$diff_output" ]]; then
            changed_count=$(echo "$diff_output" | wc -l | tr -d " ")
        else
            # Fallback: compare files against bench/after-delete tag content
            for src_file in "$TASKCTL_DIR/src/"*.sh "$TASKCTL_DIR/src/commands/"*.sh; do
                if [[ -f "$src_file" ]]; then
                    # Get relative path from TASKCTL_DIR
                    rel_path="${src_file#$TASKCTL_DIR/}"
                    baseline_content=$(git show "bench/after-delete:benchmarks/taskctl/$rel_path" 2>/dev/null) || baseline_content=""
                    current_content=$(cat "$src_file" 2>/dev/null) || current_content=""
                    if [[ -z "$baseline_content" ]] || [[ "$baseline_content" != "$current_content" ]]; then
                        changed_count=$((changed_count + 1))
                    fi
                fi
            done
        fi
    fi
    [[ "$changed_count" -ge 3 ]]
'

echo ""
echo "Score: $passed/$total checks passed"
exit $((failed > 0 ? 1 : 0))
