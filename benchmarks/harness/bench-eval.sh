#!/bin/bash
# harness/bench-eval.sh -- Run correctness checks for a challenge
# Usage: bench-eval.sh <challenge-name> [taskctl-dir]
set -euo pipefail

CHALLENGE="${1:?Usage: bench-eval.sh <challenge-name> [taskctl-dir]}"
TASKCTL_DIR="${2:-benchmarks/taskctl}"
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHALLENGES_DIR="$(cd "$HARNESS_DIR/../challenges" && pwd)"

# Load challenge definition
CHALLENGE_FILE="$CHALLENGES_DIR/$CHALLENGE.json"
if [[ ! -f "$CHALLENGE_FILE" ]]; then
    echo "Error: Unknown challenge '$CHALLENGE'" >&2
    echo "Available challenges:" >&2
    for f in "$CHALLENGES_DIR"/*.json; do
        if [[ -f "$f" ]]; then
            echo "  $(basename "$f" .json)" >&2
        fi
    done
    exit 1
fi

CHECK_SCRIPT=$(jq -r '.check_script' "$CHALLENGE_FILE")
CHALLENGE_NAME=$(jq -r '.name' "$CHALLENGE_FILE")

echo "=== Evaluating: $CHALLENGE_NAME ==="
echo ""

# Run the check script
set +e
bash "$CHALLENGES_DIR/$CHECK_SCRIPT" "$TASKCTL_DIR"
exit_code=$?
set -e

echo ""
if [[ $exit_code -eq 0 ]]; then
    echo "RESULT: PASS"
else
    echo "RESULT: FAIL"
fi
exit $exit_code
