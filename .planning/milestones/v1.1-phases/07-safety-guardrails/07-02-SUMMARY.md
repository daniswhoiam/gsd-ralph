---
phase: 07-safety-guardrails
plan: 02
subsystem: safety
tags: [bash, rm-rf-protection, safe-remove, cleanup, sentinel-handling]

# Dependency graph
requires:
  - phase: 07-safety-guardrails
    provides: "safe_remove() and validate_registry_path() from plan 07-01"
provides:
  - "cleanup.sh with zero raw rm calls and no rm-rf fallback"
  - "sentinel handling for __MAIN_WORKTREE__ in cleanup workflow"
  - "defense-in-depth check for pre-v1.0 registry entries pointing to git toplevel"
  - "all lib/ rm calls routed through safe_remove()"
  - "legacy scripts with rm-rf fallback removed and deprecation notices"
affects: [cleanup, merge, prompt-generation]

# Tech tracking
tech-stack:
  added: []
  patterns: ["safe_remove() integration pattern: source safety.sh + replace rm calls", "failed worktree removal as warning not escalation"]

key-files:
  created: []
  modified: [lib/commands/cleanup.sh, lib/prompt.sh, lib/merge/rollback.sh, scripts/ralph-cleanup.sh, scripts/ralph-execute.sh]

key-decisions:
  - "Failed worktree removals reported as warnings with manual cleanup instructions, not escalated with rm -rf"
  - "Signal file cleanup uses for-loop with safe_remove instead of glob rm -f"
  - "Legacy scripts get error reporting instead of safe_remove (standalone, no safety.sh dependency)"

patterns-established:
  - "Integration pattern: source safety.sh at file top, replace all rm -f/rm -rf with safe_remove()"
  - "Legacy script pattern: remove dangerous fallback, add deprecation notice, provide manual cleanup instructions"

requirements-completed: [SAFE-01, SAFE-04]

# Metrics
duration: 3min
completed: 2026-02-23
---

# Phase 7 Plan 2: Cleanup Safety Integration Summary

**Eliminated rm-rf data-loss vector in cleanup.sh, routed all lib/ rm calls through safe_remove(), added __MAIN_WORKTREE__ sentinel handling**

## Performance

- **Duration:** 3 min
- **Started:** 2026-02-23T08:50:56Z
- **Completed:** 2026-02-23T08:54:07Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Eliminated the rm -rf fallback at cleanup.sh:180 that destroyed the vibecheck project -- failed worktree removals now report a warning with manual cleanup instructions
- Added __MAIN_WORKTREE__ sentinel handling so sequential-mode registry entries skip directory removal entirely
- Added defense-in-depth check detecting pre-v1.0 registry entries where worktree_path resolves to git toplevel
- Routed all rm calls in lib/commands/cleanup.sh, lib/prompt.sh, and lib/merge/rollback.sh through safe_remove()
- Removed rm -rf fallback in both legacy scripts (ralph-cleanup.sh, ralph-execute.sh) and added deprecation notices

## Task Commits

Each task was committed atomically:

1. **Task 1: Fix cleanup.sh -- remove rm-rf fallback, add sentinel handling, route rm calls through safe_remove()** - `d1ca1ba` (feat)
2. **Task 2: Route remaining rm calls in lib/ and fix legacy scripts in scripts/** - `413717b` (feat)

## Files Created/Modified
- `lib/commands/cleanup.sh` - Eliminated rm-rf fallback, added sentinel/toplevel guards, routed rm calls through safe_remove()
- `lib/prompt.sh` - Added safety.sh source, replaced temp file rm -f with safe_remove()
- `lib/merge/rollback.sh` - Added safety.sh source, replaced rollback file rm -f with safe_remove()
- `scripts/ralph-cleanup.sh` - Removed rm -rf fallback, added deprecation notice
- `scripts/ralph-execute.sh` - Removed rm -rf fallback, added deprecation notice

## Decisions Made
- Failed worktree removals are reported as warnings with manual cleanup instructions rather than escalated with rm -rf. This prevents data loss at the cost of occasionally requiring manual cleanup.
- Signal file cleanup uses a for-loop with safe_remove() instead of a glob rm -f, maintaining consistency with the safe_remove pattern throughout the codebase.
- Legacy scripts in scripts/ do not source safety.sh (they are standalone with their own color definitions). Instead, the dangerous rm -rf fallback is simply removed and replaced with error reporting.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All rm -rf data-loss vectors eliminated across lib/ and scripts/
- safe_remove() is fully integrated into the cleanup, prompt, and rollback workflows
- Ready for Plan 07-03 (testing/verification of safety guards)
- The CRITICAL pending todo (cleanup deletes project root) is now resolved

## Self-Check: PASSED

All files and commits verified:
- FOUND: lib/commands/cleanup.sh
- FOUND: lib/prompt.sh
- FOUND: lib/merge/rollback.sh
- FOUND: scripts/ralph-cleanup.sh
- FOUND: scripts/ralph-execute.sh
- FOUND: d1ca1ba (Task 1)
- FOUND: 413717b (Task 2)

---
*Phase: 07-safety-guardrails*
*Completed: 2026-02-23*
