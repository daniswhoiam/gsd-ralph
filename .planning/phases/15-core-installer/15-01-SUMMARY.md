---
phase: 15-core-installer
plan: 01
subsystem: installer
tags: [bash, installer, idempotent, cmp, sed, prerequisites]

# Dependency graph
requires:
  - "Phase 14: RALPH_SCRIPTS_DIR auto-detection for location-independent scripts"
provides:
  - "install.sh single-command installer for gsd-ralph"
  - "Prerequisite detection (bash, git, jq, GSD framework)"
  - "6-file copy manifest with path adjustment for ralph.md"
  - "Idempotent re-run via cmp -s comparison"
affects: [15-02-PLAN, 16-end-to-end-validation]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Idempotent file copy via cmp -s with skip/install counters"
    - "sed path adjustment for command file (scripts/ -> scripts/ralph/)"
    - "Self-install guard comparing resolved source and target directories"

key-files:
  created:
    - "install.sh"
    - "tests/installer.bats"
  modified: []

key-decisions:
  - "Collected all prerequisite failures before returning (not exit-on-first) for better UX"
  - "Used cmp -s for idempotency rather than checksums -- simpler, POSIX standard, sufficient for file equality"
  - "Command file path adjustment via sed to temp file first, then cmp for idempotent comparison"

patterns-established:
  - "install_file(): reusable idempotent file copy with executable flag and counters"
  - "install_command_file(): sed-based path transformation with temp-file idempotency"
  - "check_prerequisites(): all-failures-before-exit pattern with actionable install instructions"

requirements-completed: [INST-01, INST-02, INST-03, INST-04, INST-06]

# Metrics
duration: 8min
completed: 2026-03-10
---

# Phase 15 Plan 01: Core Installer Summary

**Single-command install.sh with prerequisite detection, 6-file copy manifest, sed path adjustment for ralph.md, and cmp-based idempotency**

## Performance

- **Duration:** 8 min
- **Started:** 2026-03-10T18:37:12Z
- **Completed:** 2026-03-10T18:46:06Z
- **Tasks:** 1 (TDD: RED + GREEN)
- **Files created:** 2

## Accomplishments
- Created install.sh at repo root: prerequisite checks, file copy manifest, path adjustment, idempotency
- 16 new tests covering all installer behaviors: prerequisites, file copy, idempotency, self-detection
- Full regression suite: 335 tests passing (319 existing + 16 new), 0 failures
- Running installer from non-GSD directory exits with clear actionable error messages

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Add failing tests for installer prerequisites and file copy** - `d511ecd` (test)
2. **Task 1 (GREEN): Implement installer prerequisites and file copy** - `e2e7789` (feat)

_Note: TDD task had RED and GREEN commits. No refactor needed._

## Files Created/Modified
- `install.sh` - Single-command installer: prerequisite checks, 6-file copy manifest, sed path adjustment, idempotency (172 lines)
- `tests/installer.bats` - 16 tests covering prerequisites (INST-02/03), file copy (INST-01/06), idempotency (INST-04), self-detection (319 lines)

## Decisions Made
- Collected all prerequisite failures before returning instead of exiting on the first failure -- provides a complete picture of what needs fixing
- Used cmp -s for idempotency comparison -- POSIX standard, no hashing overhead, simpler than checksums
- Generated sed-modified ralph.md to temp file before cmp comparison for command file idempotency
- Guarded main execution with BASH_SOURCE check for future testability of individual functions

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- install.sh handles prerequisite detection and all 6 file copies
- Plan 15-02 will add config merge (INST-05), post-install verification (INST-07), and summary output (INST-08)
- All 335 tests green, no regressions

## Self-Check: PASSED

- FOUND: install.sh
- FOUND: tests/installer.bats
- FOUND: d511ecd (RED commit)
- FOUND: e2e7789 (GREEN commit)

---
*Phase: 15-core-installer*
*Completed: 2026-03-10*
