---
phase: 09-cli-guidance
plan: 02
subsystem: testing
tags: [bash, bats, guidance, ux, print_guidance]

# Dependency graph
requires:
  - phase: 09-cli-guidance
    provides: print_guidance() helper and guidance calls at all command exit points
provides:
  - Comprehensive test coverage for all command guidance output
  - Context-sensitivity verification for GUID-02
affects: []

# Tech tracking
tech-stack:
  added: []
  patterns: [guidance output assertions using assert_output --partial "Next:"]

key-files:
  created:
    - tests/guidance.bats
  modified: []

key-decisions:
  - "Used refute_output for negative assertions (cleanup nothing-to-clean has no guidance)"
  - "Context-sensitivity test compares init vs generate guidance lines, not just presence"

patterns-established:
  - "Guidance test pattern: run command, assert_output --partial Next: plus context-specific keyword"

requirements-completed: [GUID-01, GUID-02]

# Metrics
duration: 3min
completed: 2026-02-23
---

# Phase 9 Plan 02: CLI Guidance Tests Summary

**14 bats tests verifying context-sensitive "Next:" guidance across all 5 commands and 12 exit paths**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-23T11:12:44Z
- **Completed:** 2026-02-23T11:15:43Z
- **Tasks:** 2
- **Files created:** 1

## Accomplishments
- Created `tests/guidance.bats` with 14 passing tests covering all major command exit paths
- Verified guidance presence for init (success, already-initialized), execute (dry-run, success), generate (success), merge (no-branches, full-success, dry-run, rollback), and cleanup (success, unregistered-force)
- Verified guidance absence for cleanup nothing-to-clean path (no action = no guidance)
- Verified context-sensitivity (GUID-02): init and generate produce different guidance messages

## Task Commits

Each task was committed atomically:

1. **Task 1: Create guidance test suite for init, execute, and generate** - `84f7aa1` (test)
2. **Task 2: Add guidance tests for merge, cleanup, and context-sensitivity** - `39610c0` (test)

## Files Created/Modified
- `tests/guidance.bats` - 273 lines, 14 tests covering all command guidance output

## Decisions Made
- Used `refute_output --partial "Next:"` for cleanup nothing-to-clean test (no action means no guidance suggestion)
- Context-sensitivity test extracts and compares actual guidance lines rather than just checking presence
- Merge tests use `AUTO_PUSH=false` in `.ralphrc` to avoid push attempts (following merge.bats pattern)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Phase 09 (CLI Guidance) is fully complete: both implementation and tests done
- Full test suite (211 tests) passes with zero regressions

## Self-Check: PASSED

- tests/guidance.bats: FOUND
- Commit 84f7aa1: FOUND
- Commit 39610c0: FOUND

---
*Phase: 09-cli-guidance*
*Completed: 2026-02-23*
