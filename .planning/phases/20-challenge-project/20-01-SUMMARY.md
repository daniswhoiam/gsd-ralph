---
phase: 20-challenge-project
plan: 01
subsystem: testing
tags: [bash, jq, cli, benchmark, shellcheck, planted-bug]

# Dependency graph
requires: []
provides:
  - taskctl CLI source code with add/list/done commands
  - JSON storage layer with jq CRUD operations
  - Planted off-by-one bug in done.sh (array index vs ID lookup)
  - Deliberately messy format.sh with 9 code smells (22 ShellCheck warnings)
  - Seed data file with 4 sample tasks
affects: [20-02, 21-correctness-checks, 22-harness-core]

# Tech tracking
tech-stack:
  added: [jq]
  patterns: [bash-cli-dispatch, json-file-storage, planted-defect-pattern, deliberate-code-smells]

key-files:
  created:
    - benchmarks/taskctl/src/taskctl.sh
    - benchmarks/taskctl/src/storage.sh
    - benchmarks/taskctl/src/format.sh
    - benchmarks/taskctl/src/commands/add.sh
    - benchmarks/taskctl/src/commands/list.sh
    - benchmarks/taskctl/src/commands/done.sh
    - benchmarks/taskctl/.taskctl.json
  modified: []

key-decisions:
  - "Used -s flag in storage_read_all to handle empty files from mktemp (not just missing files)"
  - "format.sh stub created in Task 1 to satisfy taskctl.sh source, replaced with smelly version in Task 2"

patterns-established:
  - "TASKCTL_DATA env var for test isolation: export TASKCTL_DATA=$(mktemp) to redirect storage"
  - "Planted bug pattern: use array index where ID lookup is correct (natural off-by-one)"
  - "Code smell injection: write clean first, then introduce specific ShellCheck-detectable patterns"

requirements-completed: [CHAL-01, CHAL-02, CHAL-04]

# Metrics
duration: 2min
completed: 2026-03-11
---

# Phase 20 Plan 01: Build taskctl CLI Summary

**Complete taskctl Bash CLI with jq storage, add/list/done commands, planted off-by-one bug in done.sh, and 9 deliberate code smells in format.sh producing 22 ShellCheck warnings**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-11T10:45:10Z
- **Completed:** 2026-03-11T10:47:53Z
- **Tasks:** 2
- **Files modified:** 7

## Accomplishments
- Built complete taskctl CLI with storage layer, entry point, and 3 command modules
- Planted realistic off-by-one bug: `done 3` marks tasks[3] (id=4) instead of task with id=3
- Created format.sh with 9 code smells producing 22 ShellCheck warnings (SC2086, SC2155)
- All non-format files pass ShellCheck cleanly
- Seed data with 4 tasks supports observable bug demonstration

## Task Commits

Each task was committed atomically:

1. **Task 1: Create storage layer and CLI entry point** - `28722cf` (feat)
2. **Task 2: Create done.sh with planted bug and format.sh with code smells** - `2eca473` (feat)

## Files Created/Modified
- `benchmarks/taskctl/src/taskctl.sh` - CLI entry point with case dispatch for add/list/done
- `benchmarks/taskctl/src/storage.sh` - JSON CRUD via jq (read_all, add, next_id)
- `benchmarks/taskctl/src/format.sh` - Output formatting with 9 deliberate code smells
- `benchmarks/taskctl/src/commands/add.sh` - Add command: validates input, calls storage_add
- `benchmarks/taskctl/src/commands/list.sh` - List command: reads tasks, delegates to format
- `benchmarks/taskctl/src/commands/done.sh` - Done command with planted array-index bug
- `benchmarks/taskctl/.taskctl.json` - Seed data with 4 sample tasks

## Decisions Made
- Added `-s` (non-empty) check to `storage_read_all` alongside `-f` check, since `mktemp` creates 0-byte files that exist but cannot be parsed by jq
- Created format.sh as a working stub in Task 1 (required by taskctl.sh source), then replaced with the messy version in Task 2

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Empty file handling in storage_read_all**
- **Found during:** Task 1 (storage layer and CLI entry point)
- **Issue:** `storage_read_all` checked `-f` (file exists) but `mktemp` creates 0-byte files; jq fails to parse empty files
- **Fix:** Added `-s` (non-empty) check: `[[ -f "$STORAGE_FILE" ]] && [[ -s "$STORAGE_FILE" ]]`
- **Files modified:** benchmarks/taskctl/src/storage.sh
- **Verification:** `TASKCTL_DATA=$(mktemp) taskctl add "test"` succeeds
- **Committed in:** 28722cf (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 bug fix)
**Impact on plan:** Essential fix for test isolation via TASKCTL_DATA env var. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- All source files ready for Plan 20-02 (Bats tests, documentation, bench/baseline tag)
- TASKCTL_DATA env var pattern established for test isolation
- Seed data in original state (done command not applied)
- format.sh ready for ShellCheck-based refactoring challenge evaluation

## Self-Check: PASSED

All 8 files verified present. Both task commits (28722cf, 2eca473) verified in git log.

---
*Phase: 20-challenge-project*
*Completed: 2026-03-11*
