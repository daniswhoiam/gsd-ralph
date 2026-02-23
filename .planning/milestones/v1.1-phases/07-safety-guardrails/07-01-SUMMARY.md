---
phase: 07-safety-guardrails
plan: 01
subsystem: safety
tags: [bash, safety-guards, rm-rf-protection, worktree-registry]

# Dependency graph
requires: []
provides:
  - "safe_remove() guard function blocking deletion of /, HOME, git toplevel"
  - "validate_registry_path() for worktree registry entry validation"
  - "__MAIN_WORKTREE__ sentinel in register_worktree() preventing project root removal"
affects: [07-safety-guardrails, cleanup]

# Tech tracking
tech-stack:
  added: []
  patterns: ["inode-level path comparison with [[ -ef ]]", "__MAIN_WORKTREE__ sentinel for non-removable registry entries"]

key-files:
  created: [lib/safety.sh]
  modified: [lib/cleanup/registry.sh]

key-decisions:
  - "safe_remove() resolves paths before comparing, using cd+pwd -P (no readlink -f for Bash 3.2 compat)"
  - "validate_registry_path() uses case pattern matching for traversal detection (Bash 3.2 compatible)"
  - "SC1091 shellcheck suppression added for dynamic source path in registry.sh"

patterns-established:
  - "Safety guard pattern: check guards in order, print_error on refusal, return 1"
  - "Sentinel pattern: __MAIN_WORKTREE__ replaces dangerous paths in registry to prevent rm -rf"

requirements-completed: [SAFE-02, SAFE-03]

# Metrics
duration: 2min
completed: 2026-02-23
---

# Phase 7 Plan 1: Safety Foundation Summary

**safe_remove() guard blocking /, HOME, git toplevel deletion plus __MAIN_WORKTREE__ sentinel in register_worktree()**

## Performance

- **Duration:** 2 min
- **Started:** 2026-02-23T08:45:25Z
- **Completed:** 2026-02-23T08:47:53Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created lib/safety.sh with safe_remove() that blocks deletion of filesystem root, HOME, git toplevel, and empty paths using inode-level [[ -ef ]] comparison
- Created validate_registry_path() that blocks empty, non-absolute, and traversal-containing paths while allowing __MAIN_WORKTREE__ sentinel
- Added main worktree detection guard to register_worktree() in registry.sh that replaces project root paths with __MAIN_WORKTREE__ sentinel

## Task Commits

Each task was committed atomically:

1. **Task 1: Create lib/safety.sh with safe_remove() and validate_registry_path()** - `9ec5d27` (feat)
2. **Task 2: Add main worktree guard to register_worktree() in registry.sh** - `10e4699` (feat)

## Files Created/Modified
- `lib/safety.sh` - New file with safe_remove() and validate_registry_path() safety guard functions
- `lib/cleanup/registry.sh` - Added main worktree detection guard and safety.sh sourcing

## Decisions Made
- Used `cd + pwd -P` for path resolution instead of `readlink -f` (not available in Bash 3.2 on macOS)
- Used `case` pattern matching for traversal detection in validate_registry_path() (Bash 3.2 compatible)
- Added `# shellcheck disable=SC1091` for the dynamic `$GSD_RALPH_HOME` source path, matching project convention for dynamic sources

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added SC1091 shellcheck suppression for dynamic source**
- **Found during:** Task 2 (registry.sh modification)
- **Issue:** ShellCheck SC1091 info-level diagnostic causes exit code 1 for the dynamic `$GSD_RALPH_HOME/lib/safety.sh` source line
- **Fix:** Added `# shellcheck disable=SC1091` inline comment before the source line
- **Files modified:** lib/cleanup/registry.sh
- **Verification:** `shellcheck lib/cleanup/registry.sh` exits 0
- **Committed in:** 10e4699 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Minimal -- standard shellcheck suppression for dynamic source paths. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- safe_remove() is ready for integration into cleanup.sh (Plan 07-02)
- validate_registry_path() is available for registry validation hardening
- __MAIN_WORKTREE__ sentinel is in place; cleanup code needs to recognize and skip it (Plan 07-02)

## Self-Check: PASSED

All files and commits verified:
- FOUND: lib/safety.sh
- FOUND: lib/cleanup/registry.sh
- FOUND: 9ec5d27 (Task 1)
- FOUND: 10e4699 (Task 2)

---
*Phase: 07-safety-guardrails*
*Completed: 2026-02-23*
