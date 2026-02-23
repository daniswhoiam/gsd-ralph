---
phase: 09-cli-guidance
plan: 01
subsystem: cli
tags: [bash, ux, guidance, print_guidance]

# Dependency graph
requires:
  - phase: 01-project-initialization
    provides: lib/common.sh output helpers
provides:
  - print_guidance() helper function in lib/common.sh
  - Context-sensitive next-step guidance at all command exit points
affects: [09-cli-guidance]

# Tech tracking
tech-stack:
  added: []
  patterns: [print_guidance for user-facing next-step hints]

key-files:
  created: []
  modified:
    - lib/common.sh
    - lib/commands/init.sh
    - lib/commands/execute.sh
    - lib/commands/generate.sh
    - lib/commands/merge.sh
    - lib/commands/cleanup.sh
    - lib/merge/rollback.sh

key-decisions:
  - "No guidance after die() or --help -- error messages and usage text are self-explanatory"
  - "No guidance at abort or nothing-to-clean cleanup exits -- user chose to stop or nothing happened"
  - "Conditional guidance in cleanup for skipped branches vs full cleanup"

patterns-established:
  - "print_guidance pattern: always call after print_success/print_info at exit points, never after die()"

requirements-completed: [GUID-01, GUID-02]

# Metrics
duration: 4min
completed: 2026-02-23
---

# Phase 9 Plan 01: CLI Guidance Summary

**print_guidance() helper with context-sensitive next-step hints at all 16 command exit points across 7 files**

## Performance

- **Duration:** 4 min
- **Started:** 2026-02-23T11:06:29Z
- **Completed:** 2026-02-23T11:10:35Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Added `print_guidance()` helper to `lib/common.sh` with green "Next:" prefix
- Wired guidance into all 5 active commands (init, execute, generate, merge, cleanup) plus rollback
- Replaced old 4-line "Next steps:" block in init.sh with single print_guidance call
- Context-sensitive messages at every non-die, non-help exit path (16 total calls)

## Task Commits

Each task was committed atomically:

1. **Task 1: Add print_guidance() helper and wire into init, execute, generate** - `d1906ad` (feat)
2. **Task 2: Wire guidance into merge, cleanup, and rollback** - `09562e8` (feat)

## Files Created/Modified
- `lib/common.sh` - Added print_guidance() function after ring_bell()
- `lib/commands/init.sh` - 2 guidance calls (success + already-initialized), old Next steps block removed
- `lib/commands/execute.sh` - 2 guidance calls (dry-run + success)
- `lib/commands/generate.sh` - 1 guidance call (success)
- `lib/commands/merge.sh` - 7 guidance calls (no-branches, dry-run-clean, dry-run-conflict, all-conflict, test-regression, full-success, partial-success)
- `lib/commands/cleanup.sh` - 4 guidance calls (unregistered-force, unregistered-no-force, normal-complete, skipped-branches conditional)
- `lib/merge/rollback.sh` - 1 guidance call (after successful rollback)

## Decisions Made
- No guidance after die() or --help -- error messages and usage text are self-explanatory
- No guidance at abort or nothing-to-clean cleanup exits -- user chose to stop or nothing happened
- Conditional guidance in cleanup: different message when branches are skipped (suggests --force) vs full cleanup (confirms done)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All command exit points now have guidance, ready for Plan 02 (testing guidance output)
- No blockers or concerns

---
*Phase: 09-cli-guidance*
*Completed: 2026-02-23*
