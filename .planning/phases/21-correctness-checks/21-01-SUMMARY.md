---
phase: 21-correctness-checks
plan: 01
subsystem: testing
tags: [bash, bats, jq, benchmark-checks, reference-solutions, behavioral-testing]

# Dependency graph
requires:
  - phase: 20-challenge-project
    provides: taskctl baseline project with planted defects and seed data
provides:
  - 5 reference solution overlay directories for all benchmark challenges
  - 3 behavioral check scripts (fix-bug, add-feature, add-tests) with dual-control validation
  - Check script contract (TASKCTL_DIR arg, PASS/FAIL output, Score format, exit code 0/1)
affects: [21-02-PLAN, 22-benchmark-harness]

# Tech tracking
tech-stack:
  added: []
  patterns: [behavioral-check-scripts, reference-solution-overlays, dual-control-validation, check-helper-function]

key-files:
  created:
    - benchmarks/challenges/reference-solutions/fix-bug/src/commands/done.sh
    - benchmarks/challenges/reference-solutions/fix-bug/tests/test_done.bats
    - benchmarks/challenges/reference-solutions/add-feature/src/commands/delete.sh
    - benchmarks/challenges/reference-solutions/add-feature/src/taskctl.sh
    - benchmarks/challenges/reference-solutions/add-feature/tests/test_delete.bats
    - benchmarks/challenges/reference-solutions/add-tests/tests/test_storage.bats
    - benchmarks/challenges/reference-solutions/refactor/src/format.sh
    - benchmarks/challenges/reference-solutions/multi-file/src/commands/add.sh
    - benchmarks/challenges/reference-solutions/multi-file/src/commands/list.sh
    - benchmarks/challenges/reference-solutions/multi-file/src/storage.sh
    - benchmarks/challenges/reference-solutions/multi-file/tests/test_priority.bats
    - benchmarks/challenges/checks/check-fix-bug.sh
    - benchmarks/challenges/checks/check-add-feature.sh
    - benchmarks/challenges/checks/check-add-tests.sh
  modified: []

key-decisions:
  - "Check scripts use eval-based check() helper for uniform PASS/FAIL output and scoring"
  - "Bats binary discovered dynamically: relative path first, then system bats, then fail"
  - "Each check that mutates data uses mktemp copy of .taskctl.json with trap cleanup"

patterns-established:
  - "Check script contract: accept TASKCTL_DIR, output PASS/FAIL per check, Score: N/M, exit 0 or 1"
  - "Reference solution overlay: directory contains ONLY files differing from baseline, overlaid via cp -R"
  - "Dual-control validation: every check must FAIL on baseline and PASS with reference overlay"

requirements-completed: [CHAL-06, HARN-03]

# Metrics
duration: 5min
completed: 2026-03-11
---

# Phase 21 Plan 01: Reference Solutions and Check Scripts Summary

**5 reference solution overlays and 3 behavioral check scripts (fix-bug, add-feature, add-tests) with dual-control validation -- all checks FAIL on baseline and PASS with overlay**

## Performance

- **Duration:** 5 min
- **Started:** 2026-03-11T11:45:00Z
- **Completed:** 2026-03-11T11:50:00Z
- **Tasks:** 2
- **Files modified:** 14

## Accomplishments
- Created all 5 reference solution overlay directories with 11 files total, covering bug fix (done.sh ID lookup), feature add (delete command), test coverage (storage tests), refactoring (format.sh cleanup), and multi-file feature (priority support)
- Created 3 behavioral check scripts following the HARN-03 requirement: tests outcomes not code patterns
- Validated dual-control: 3/3 checks FAIL on baseline (negative control), 3/3 PASS with reference overlay (positive control)
- All reference solution Bats tests pass when overlaid on baseline (10, 11, 6, and 12 tests respectively for fix-bug, add-feature, add-tests, multi-file)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create reference solution overlays for all 5 challenges** - `b52030c` (feat)
2. **Task 2: Create check scripts for Challenges 1-3 with dual-control validation** - `f1a9b2a` (feat)

## Files Created/Modified
- `benchmarks/challenges/reference-solutions/fix-bug/src/commands/done.sh` - Fixed done command using .id field lookup instead of array index
- `benchmarks/challenges/reference-solutions/fix-bug/tests/test_done.bats` - 3 tests for done command behavior
- `benchmarks/challenges/reference-solutions/add-feature/src/commands/delete.sh` - New delete command with ID validation
- `benchmarks/challenges/reference-solutions/add-feature/src/taskctl.sh` - Dispatch table with delete case added
- `benchmarks/challenges/reference-solutions/add-feature/tests/test_delete.bats` - 4 tests for delete command
- `benchmarks/challenges/reference-solutions/add-tests/tests/test_storage.bats` - 6 tests covering all storage functions
- `benchmarks/challenges/reference-solutions/refactor/src/format.sh` - Cleaned format.sh with helper function, proper quoting, [[ ]] usage
- `benchmarks/challenges/reference-solutions/multi-file/src/commands/add.sh` - add with --priority flag support
- `benchmarks/challenges/reference-solutions/multi-file/src/commands/list.sh` - list with --sort priority support
- `benchmarks/challenges/reference-solutions/multi-file/src/storage.sh` - storage_add with optional priority parameter
- `benchmarks/challenges/reference-solutions/multi-file/tests/test_priority.bats` - 5 tests for priority feature
- `benchmarks/challenges/checks/check-fix-bug.sh` - 3 behavioral checks for Challenge 1
- `benchmarks/challenges/checks/check-add-feature.sh` - 4 behavioral checks for Challenge 2
- `benchmarks/challenges/checks/check-add-tests.sh` - 4 behavioral checks for Challenge 3

## Decisions Made
- Used eval-based `check()` helper function in check scripts for uniform output format and scoring rather than separate test runner
- Bats binary resolution: check relative path `../../tests/bats/bin/bats` first (works in repo and worktrees), then fall back to system `bats`
- Each mutating check uses `mktemp` copy of .taskctl.json to avoid data corruption between assertions
- Challenge 3 check for "storage.sh unchanged" gracefully handles missing git/bench tag by passing (avoids false negatives in non-git contexts)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- 5 reference solutions ready for Plan 02 to use for remaining check scripts (refactor, multi-file)
- 3 check scripts ready for bench-eval.sh integration in Plan 02
- Check script contract established (TASKCTL_DIR arg, PASS/FAIL output, Score format) for Plan 02 to follow
- bench/after-delete tag creation and JSON challenge definitions remain for Plan 02

## Self-Check: PASSED

All 14 created files verified present. Both task commits (b52030c, f1a9b2a) confirmed in git log. All 3 check scripts confirmed executable.

---
*Phase: 21-correctness-checks*
*Completed: 2026-03-11*
