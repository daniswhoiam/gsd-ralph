---
phase: 11-shell-launcher-and-headless-invocation
plan: 02
subsystem: cli
tags: [bash, claude-code, headless, loop-engine, state-detection, retry, tdd, bats]

# Dependency graph
requires:
  - phase: 11-shell-launcher-and-headless-invocation
    provides: ralph-launcher.sh core functions (parse_args, read_config, build_permission_flags, build_prompt, build_claude_command, dry_run_output)
provides:
  - check_state_completion function for STATE.md phase completion detection
  - execute_iteration function for single claude -p invocation with fresh context
  - run_loop function for autonomous iteration until phase complete
  - Progress-aware retry logic (continue on progress, retry-once on no-progress)
  - Terminal bell notification on completion or unrecoverable failure
  - Complete working autopilot launcher (420 LOC)
affects: [12-defense-in-depth]

# Tech tracking
tech-stack:
  added: []
  patterns: [state-snapshot-progress-detection, retry-once-on-no-progress, fresh-context-per-iteration]

key-files:
  created: []
  modified:
    - scripts/ralph-launcher.sh
    - tests/ralph-launcher.bats
    - tests/test_helper/ralph-helpers.bash

key-decisions:
  - "Progress detection via state snapshot comparison (phase/plan/status triple) before and after each iteration"
  - "Non-zero exit with progress = max-turns exhaustion (continue), without progress = failure (retry once)"
  - "Terminal bell via printf '\\a' on both success and failure paths"
  - "Fresh context assembly per iteration via assemble-context.sh to prevent stale context (Pitfall 3)"

patterns-established:
  - "State snapshot comparison: _capture_state_snapshot captures phase:N|plan:N|status:X for diff"
  - "Retry-once pattern: consecutive_no_progress counter, 2 = unrecoverable"
  - "Loop engine pattern: while true with explicit break conditions (complete or 2x no-progress)"

requirements-completed: [AUTO-02, OBSV-01, OBSV-02]

# Metrics
duration: 6min
completed: 2026-03-10
---

# Phase 11 Plan 02: Loop Execution Engine Summary

**Autonomous loop engine with STATE.md completion detection, progress-aware retry, fresh context per iteration, and terminal bell notification**

## Performance

- **Duration:** 6 min
- **Started:** 2026-03-10T10:47:36Z
- **Completed:** 2026-03-10T10:53:46Z
- **Tasks:** 1 (TDD with RED + GREEN commits)
- **Files modified:** 3

## Accomplishments
- Built loop execution engine with 3 new functions: check_state_completion, execute_iteration, run_loop
- Full TDD coverage: 15 new tests (37 total across ralph-launcher.bats + ralph-permissions.bats)
- Progress-aware retry logic distinguishes max-turns exhaustion from genuine failure
- State snapshot comparison (phase/plan/status triple) detects any STATE.md advancement
- Terminal bell notification on both completion and unrecoverable failure
- 280 total suite tests green with zero regressions

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: TDD failing tests** - `e7be66e` (test)
2. **Task 1 GREEN: Loop engine implementation** - `e3f7ada` (feat)

_TDD task had separate RED and GREEN commits._

## Files Created/Modified
- `scripts/ralph-launcher.sh` - Added check_state_completion, _capture_state_snapshot, execute_iteration, run_loop; updated main guard to wire run_loop
- `tests/ralph-launcher.bats` - 15 new tests covering completion detection, iteration execution, retry logic, progress continuation, terminal bell, fresh context
- `tests/test_helper/ralph-helpers.bash` - Added create_mock_state_advanced and create_mock_assemble_context helpers

## Decisions Made
- Progress detection uses state snapshot comparison (phase:N|plan:N|status:X) rather than parsing JSON result field -- STATE.md is authoritative GSD state
- Non-zero exit code + state change = max-turns exhaustion (continue looping), not failure -- per RESEARCH.md Pitfall 2
- Retry counter uses consecutive_no_progress (resets on any progress) rather than total failure count
- Mock scripts use unquoted heredocs to expand TEST_TEMP_DIR at write time for subprocess compatibility

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed mock script heredoc quoting for subprocess compatibility**
- **Found during:** Task 1 GREEN (test execution)
- **Issue:** Mock assemble-context.sh and claude scripts used single-quoted heredocs ('TRACKEOF'), so $TEST_TEMP_DIR was not expanded at write time. Subprocess bash processes could not resolve the variable.
- **Fix:** Changed to unquoted heredocs (TRACKEOF) with escaped $1 references (\$1) so TEST_TEMP_DIR paths are baked into mock scripts at creation time.
- **Files modified:** tests/ralph-launcher.bats
- **Verification:** All 37 tests pass
- **Committed in:** e3f7ada (part of GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Necessary fix for test subprocess compatibility. No scope creep.

## Issues Encountered
None beyond the heredoc quoting issue documented above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- ralph-launcher.sh is a complete working autopilot (420 LOC, 9 functions)
- Loop engine ready for Phase 12 defense-in-depth additions (circuit breaker, AskUserQuestion hook)
- All loop control points are explicit and extensible (completion check, retry logic, bell notification)
- Phase 12 can add wall-clock timeout by wrapping run_loop or adding check inside the while loop

## Self-Check: PASSED

All 3 modified files verified present. Both task commits verified in git log. SUMMARY.md verified present.

---
*Phase: 11-shell-launcher-and-headless-invocation*
*Completed: 2026-03-10*
