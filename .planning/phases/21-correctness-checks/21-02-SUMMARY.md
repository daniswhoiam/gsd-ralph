---
phase: 21-correctness-checks
plan: 02
subsystem: testing
tags: [bash, jq, benchmark-checks, json-definitions, eval-driver, git-tagging, behavioral-testing]

# Dependency graph
requires:
  - phase: 21-correctness-checks
    plan: 01
    provides: 3 check scripts (fix-bug, add-feature, add-tests), 5 reference solution overlays, check script contract
  - phase: 20-challenge-project
    provides: taskctl baseline project with planted defects and seed data
provides:
  - 2 additional check scripts (check-refactor.sh, check-multi-file.sh) completing the full suite of 5
  - 5 declarative JSON challenge definitions with prompts, tags, time caps, and check references
  - bench-eval.sh eval driver as single entry point for correctness evaluation
  - bench/after-delete annotated git tag for Challenge 5 starting state
affects: [22-benchmark-harness]

# Tech tracking
tech-stack:
  added: []
  patterns: [declarative-challenge-json, eval-driver-pattern, git-tag-starting-states, pipefail-safe-grep]

key-files:
  created:
    - benchmarks/challenges/checks/check-refactor.sh
    - benchmarks/challenges/checks/check-multi-file.sh
    - benchmarks/challenges/fix-bug.json
    - benchmarks/challenges/add-feature.json
    - benchmarks/challenges/add-tests.json
    - benchmarks/challenges/refactor.json
    - benchmarks/challenges/multi-file.json
    - benchmarks/harness/bench-eval.sh
  modified: []

key-decisions:
  - "Used pipefail-safe grep pattern: c=$(grep ...) || c=0 instead of c=$(grep ... || echo 0)"
  - "Check-multi-file uses fallback file comparison when git diff unavailable for changed-file counting"
  - "bench/after-delete tag created from worktree with submodule initialization for proper test validation"

patterns-established:
  - "Declarative challenge JSON: id, name, number, starting_tag, prompt, time_cap_minutes, check_script, check_count, checks, measures"
  - "bench-eval.sh driver: loads JSON by challenge name, resolves check_script, runs it, reports RESULT: PASS/FAIL"
  - "Git tag starting states: bench/baseline for challenges 1-4, bench/after-delete for challenge 5"

requirements-completed: [CHAL-05, HARN-03, HARN-05]

# Metrics
duration: 8min
completed: 2026-03-11
---

# Phase 21 Plan 02: Challenge Definitions and Eval Driver Summary

**2 check scripts (refactor + multi-file), 5 declarative JSON challenge definitions, bench-eval.sh driver, and bench/after-delete git tag -- completing the full evaluation infrastructure**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-11T11:53:48Z
- **Completed:** 2026-03-11T12:02:37Z
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments
- Created bench/after-delete annotated tag from baseline + Challenge 2 reference solution, verified delete works and done bug still present
- Created check-refactor.sh (4 checks: tests pass, 10+ lines changed, ShellCheck reduced, no new commands) and check-multi-file.sh (6 checks: priority add/default/sort, priority tests, existing tests, 3+ files changed)
- Created 5 declarative JSON challenge definitions with all required fields (id, name, number, starting_tag, prompt, time_cap_minutes, check_script, check_count, checks, measures)
- Created bench-eval.sh driver that loads JSON by name, resolves check script path, runs it, and reports structured RESULT: PASS/FAIL
- Validated dual controls: all 5 checks FAIL against baseline/after-delete (negative), all 5 PASS with reference overlay (positive)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create bench/after-delete tag and check scripts for Challenges 4-5** - `a205f92` (feat)
2. **Task 2: Create 5 JSON challenge definitions and bench-eval.sh driver** - `b59779e` (feat)

## Files Created/Modified
- `benchmarks/challenges/checks/check-refactor.sh` - 4 behavioral checks for Challenge 4 (refactoring with behavior preservation)
- `benchmarks/challenges/checks/check-multi-file.sh` - 6 behavioral checks for Challenge 5 (multi-file priority feature)
- `benchmarks/challenges/fix-bug.json` - Challenge 1 definition (bug diagnosis, 10min cap)
- `benchmarks/challenges/add-feature.json` - Challenge 2 definition (delete command, 15min cap)
- `benchmarks/challenges/add-tests.json` - Challenge 3 definition (storage test coverage, 15min cap)
- `benchmarks/challenges/refactor.json` - Challenge 4 definition (format.sh refactor, 10min cap)
- `benchmarks/challenges/multi-file.json` - Challenge 5 definition (priority feature, 20min cap, starts from bench/after-delete)
- `benchmarks/harness/bench-eval.sh` - Eval driver: loads challenge JSON, resolves check script, runs and reports results

## Decisions Made
- Used `c=$(grep ...) || c=0` pattern instead of `c=$(grep ... || echo 0)` to avoid double-output bug under pipefail when grep returns 0 matches
- Check-multi-file.sh includes fallback file comparison (comparing against git show output) for environments where git diff on paths outside the repo root fails
- bench/after-delete tag created via temporary worktree with submodule initialization to properly verify all tests pass before tagging

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed pipefail-incompatible grep patterns in check scripts**
- **Found during:** Task 1 (check-refactor.sh and check-multi-file.sh creation)
- **Issue:** `$(command | grep -c ... || echo 0)` produces "0\n0" when both the pipeline and grep fail, causing arithmetic errors in bash
- **Fix:** Changed to `$(diff ... || true)` and `$(grep ...) || c=0` patterns that correctly handle non-zero exit codes under pipefail
- **Files modified:** benchmarks/challenges/checks/check-refactor.sh, benchmarks/challenges/checks/check-multi-file.sh
- **Verification:** Both scripts pass dual-control validation (FAIL on baseline, PASS with reference overlay)
- **Committed in:** a205f92 (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for check script correctness under pipefail. No scope creep.

## Issues Encountered
- Temporary worktree for bench/after-delete tag required submodule initialization (`git submodule update --init --recursive`) for Bats tests to resolve -- resolved by running submodule init before test validation
- Positive control validation required temp directories within the benchmarks/ tree (not /tmp/) so the relative bats path `../../tests/bats/bin/bats` could resolve correctly

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Full evaluation infrastructure complete: 5 check scripts, 5 JSON definitions, bench-eval.sh driver
- All checks validated with dual controls (negative and positive)
- bench/baseline and bench/after-delete tags establish both starting states
- Phase 22 (benchmark harness) can use `bash benchmarks/harness/bench-eval.sh <challenge> <taskctl-dir>` as the single evaluation entry point
- All challenge prompts defined in JSON for the harness to read and pass to AI agents

## Self-Check: PASSED

All 8 created files verified present. Both task commits (a205f92, b59779e) confirmed in git log. bench/after-delete tag confirmed. All 5 JSON files reference correct check scripts. Line count requirements met (check-refactor: 78, check-multi-file: 132, bench-eval: 42).

---
*Phase: 21-correctness-checks*
*Completed: 2026-03-11*
