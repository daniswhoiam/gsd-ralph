---
phase: 14-location-independent-scripts
plan: 01
subsystem: scripts
tags: [bash, bash-source, path-resolution, portability]

# Dependency graph
requires: []
provides:
  - "RALPH_SCRIPTS_DIR variable for location-independent script resolution"
  - "Auto-detection from BASH_SOURCE[0] with external override support"
  - "All script-to-script paths configurable via single variable"
affects: [15-bash-installer, 16-end-to-end-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "BASH_SOURCE self-detection with symlink resolution (same pattern as bin/gsd-ralph)"
    - "Environment variable override with auto-detected default"

key-files:
  created: []
  modified:
    - "scripts/ralph-launcher.sh"
    - "tests/ralph-launcher.bats"

key-decisions:
  - "Copied proven BASH_SOURCE symlink resolution pattern from bin/gsd-ralph verbatim"
  - "Used underscore-prefixed temporary variables (_RALPH_SCRIPT_SOURCE, _RALPH_SCRIPT_DIR) to avoid namespace pollution"

patterns-established:
  - "RALPH_SCRIPTS_DIR: single env var controls script resolution for entire scripts/ subsystem"
  - "Override before source: set RALPH_SCRIPTS_DIR externally to redirect all script paths"

requirements-completed: [PORT-01, PORT-02, PORT-03]

# Metrics
duration: 4min
completed: 2026-03-10
---

# Phase 14 Plan 01: Location-Independent Scripts Summary

**RALPH_SCRIPTS_DIR auto-detection via BASH_SOURCE with configurable override, replacing 3 hardcoded $PROJECT_ROOT/scripts/ paths**

## Performance

- **Duration:** 4 min
- **Started:** 2026-03-10T17:53:05Z
- **Completed:** 2026-03-10T17:56:49Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Introduced RALPH_SCRIPTS_DIR with BASH_SOURCE-based auto-detection and external override support
- Replaced all 3 hardcoded `$PROJECT_ROOT/scripts/` references (CONTEXT_SCRIPT, VALIDATE_SCRIPT, hook_script)
- Full regression suite passes: 319 tests (315 original + 4 new), 0 failures
- RALPH_SCRIPTS_DIR exported for subprocess access

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Add failing RALPH_SCRIPTS_DIR tests** - `7856ea1` (test)
2. **Task 1 (GREEN): Implement RALPH_SCRIPTS_DIR auto-detection** - `dfa5321` (feat)
3. **Task 2: Full regression suite** - verification only, no code changes

_Note: TDD task had RED and GREEN commits. No refactor needed._

## Files Created/Modified
- `scripts/ralph-launcher.sh` - Added RALPH_SCRIPTS_DIR auto-detection block (10 lines), replaced 3 hardcoded path references
- `tests/ralph-launcher.bats` - Added 4 new portability tests (auto-detection, override, hook path, export)

## Decisions Made
- Copied the proven BASH_SOURCE symlink resolution pattern from bin/gsd-ralph verbatim rather than inventing a new approach
- Used underscore-prefixed temporary variables (_RALPH_SCRIPT_SOURCE, _RALPH_SCRIPT_DIR) to avoid polluting the global namespace

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- scripts/ralph-launcher.sh is now location-independent via RALPH_SCRIPTS_DIR
- Phase 15 installer can set RALPH_SCRIPTS_DIR to point to scripts/ralph/ in target repos
- All existing functionality preserved (319 tests green)

## Self-Check: PASSED

- FOUND: 14-01-SUMMARY.md
- FOUND: scripts/ralph-launcher.sh
- FOUND: tests/ralph-launcher.bats
- FOUND: 7856ea1 (RED commit)
- FOUND: dfa5321 (GREEN commit)

---
*Phase: 14-location-independent-scripts*
*Completed: 2026-03-10*
