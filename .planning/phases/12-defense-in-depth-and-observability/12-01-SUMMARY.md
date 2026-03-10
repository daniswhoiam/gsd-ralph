---
phase: 12-defense-in-depth-and-observability
plan: 01
subsystem: infra
tags: [circuit-breaker, graceful-stop, audit-log, progress-display, bash, timeout]

# Dependency graph
requires:
  - phase: 11-shell-launcher-and-headless-invocation
    provides: ralph-launcher.sh run_loop, validate-config.sh, test infrastructure
provides:
  - _check_circuit_breaker wall-clock timeout function
  - _check_graceful_stop sentinel file detection
  - _format_duration human-readable time formatting
  - _init_audit_log / _print_audit_summary audit lifecycle
  - bin/ralph-stop convenience command
  - timeout_minutes config validation
affects: [12-02-hook-script, future-observability]

# Tech tracking
tech-stack:
  added: []
  patterns: [circuit-breaker-pattern, sentinel-file-stop, audit-log-lifecycle]

key-files:
  created:
    - bin/ralph-stop
  modified:
    - scripts/ralph-launcher.sh
    - scripts/validate-config.sh
    - .planning/config.json
    - tests/ralph-launcher.bats
    - tests/ralph-config.bats
    - tests/test_helper/ralph-helpers.bash

key-decisions:
  - "Circuit breaker uses wall-clock elapsed time (date +%s arithmetic), not iteration count"
  - "Graceful stop auto-removes sentinel file after detection to prevent stale state"
  - "Audit log truncated at each run start to keep logs scoped to current session"
  - "Progress line format: Ralph: Iter N done (Xm Ys) | Total: Xm Ys | state | exit=N"

patterns-established:
  - "Defense-in-depth: multiple independent stop mechanisms (timeout, sentinel, retry limit)"
  - "Audit lifecycle: init at start, summary at exit, log populated by hooks (Plan 02)"

requirements-completed: [SAFE-03, OBSV-03, OBSV-04]

# Metrics
duration: 9min
completed: 2026-03-10
---

# Phase 12 Plan 01: Defense-in-Depth Core Summary

**Circuit breaker with 30m wall-clock timeout, graceful stop via .ralph/.stop sentinel, per-iteration progress display, and audit log lifecycle for Ralph autopilot**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-10T14:00:51Z
- **Completed:** 2026-03-10T14:10:22Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files modified:** 7

## Accomplishments
- Wall-clock circuit breaker prevents runaway execution with configurable timeout (default 30 min)
- Graceful stop mechanism via .ralph/.stop sentinel file with auto-cleanup
- Per-iteration progress line with iteration number, duration, total elapsed, state snapshot, exit code
- Audit log lifecycle: init/truncate at run start, summary at exit (log population by Plan 02 hooks)
- Config validation extended for timeout_minutes with positive-integer check
- bin/ralph-stop convenience command for requesting graceful halt
- 16 new tests (47 total launcher, 11 total config), zero regressions

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing tests** - `6d497f9` (test)
2. **Task 1 (GREEN): Implementation** - `23c63ac` (feat)

_TDD task with RED-GREEN commits._

## Files Created/Modified
- `scripts/ralph-launcher.sh` - Added 5 new functions (_check_circuit_breaker, _check_graceful_stop, _format_duration, _init_audit_log, _print_audit_summary), extended run_loop with circuit breaker, graceful stop, progress display, and audit lifecycle
- `scripts/validate-config.sh` - Added timeout_minutes validation, updated known_keys list
- `bin/ralph-stop` - New convenience script: touches .ralph/.stop and prints confirmation
- `.planning/config.json` - Added timeout_minutes: 30 to ralph config
- `tests/ralph-launcher.bats` - 16 new tests for circuit breaker, graceful stop, progress, audit
- `tests/ralph-config.bats` - 2 new tests for timeout_minutes validation
- `tests/test_helper/ralph-helpers.bash` - Added create_mock_stop_file, create_mock_audit_log helpers

## Decisions Made
- Circuit breaker uses wall-clock elapsed time (date +%s arithmetic), not iteration count -- provides real-world timeout guarantee regardless of iteration speed
- Graceful stop auto-removes sentinel file after detection to prevent stale state on next run
- Audit log truncated at each run start to keep logs scoped to current session
- Progress line format chosen for machine-parseable structure: "Ralph: Iter N done (Xm Ys) | Total: Xm Ys | phase:N|plan:N|status:X | exit=N"

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Audit log lifecycle ready for Plan 02 hook script to populate via _init_audit_log/audit file path
- AUDIT_FILE path exported as module-level variable for hook integration
- All run_loop exit paths call _print_audit_summary

## Self-Check: PASSED

All files verified present. All commits verified in git log.

---
*Phase: 12-defense-in-depth-and-observability*
*Completed: 2026-03-10*
