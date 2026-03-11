---
phase: 22-harness-core-and-cc-mode
plan: 01
subsystem: benchmarking
tags: [bash, git-worktree, harness, benchmark-pipeline]

# Dependency graph
requires:
  - phase: 21-correctness-checks-and-challenge-definitions
    provides: challenge JSON definitions (fix-bug.json etc.), check scripts, bench-eval.sh driver
provides:
  - Shared constants library (HARNESS_DIR, CHALLENGES_DIR, RESULTS_DIR, BENCH_TMPDIR, BENCH_MODEL_VERSION, DEFAULT_MAX_TURNS)
  - Logging functions (log_info, log_error)
  - Utility functions (require_command, load_challenge, ensure_results_dir)
  - Worktree lifecycle management (create_run_worktree, cleanup_run_worktree)
affects: [22-02-PLAN, 22-03-PLAN, 23-01-PLAN]

# Tech tracking
tech-stack:
  added: []
  patterns: [git-worktree-isolation, source-guard-pattern, cli-dual-mode-sourced-or-executed]

key-files:
  created:
    - benchmarks/harness/lib/common.sh
    - benchmarks/harness/bench-reset.sh
  modified: []

key-decisions:
  - "Redirect both stdout and stderr from git worktree add to prevent polluting the function return value channel"
  - "RESULTS_DIR uses relative path from HARNESS_DIR (not cd-resolved) since directory may not exist yet"

patterns-established:
  - "Source guard: BASH_SOURCE[0] == $0 check prevents accidental direct execution of library scripts"
  - "CLI dual-mode: scripts can be sourced for function access or executed directly with subcommand CLI"
  - "Path resolution: BASH_SOURCE-based cd/pwd for all directory constants"

requirements-completed: [HARN-01]

# Metrics
duration: 3min
completed: 2026-03-11
---

# Phase 22 Plan 01: Harness Core Library and Worktree Isolation Summary

**Shared Bash library (common.sh) with constants/logging/path-resolution and bench-reset.sh for git worktree isolation per benchmark run**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-11T14:09:30Z
- **Completed:** 2026-03-11T14:12:12Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- common.sh provides all shared constants (HARNESS_DIR, CHALLENGES_DIR, RESULTS_DIR, BENCH_TMPDIR, BENCH_MODEL_VERSION, DEFAULT_MAX_TURNS, BENCH_REPO_ROOT), logging (log_info, log_error), and utilities (require_command, load_challenge, ensure_results_dir)
- bench-reset.sh creates isolated git worktrees at challenge starting tags with full validation (taskctl.sh presence, git clean, submodule init) and cleanup
- Both scripts support Bash 3.2 compatibility and dual-mode operation (source or direct execution)

## Task Commits

Each task was committed atomically:

1. **Task 1: Create shared library (common.sh)** - `bd6caac` (feat)
2. **Task 2: Create worktree isolation script (bench-reset.sh)** - `f56d4a8` (feat)

## Files Created/Modified
- `benchmarks/harness/lib/common.sh` - Shared constants, logging, path resolution, and utility functions for all harness scripts
- `benchmarks/harness/bench-reset.sh` - Worktree lifecycle management with create/validate/cleanup functions and CLI interface

## Decisions Made
- Redirect both stdout and stderr from `git worktree add` command: git outputs "HEAD is now at..." to stdout which would pollute the function's return value (the workdir path on stdout)
- RESULTS_DIR uses a relative path (`$HARNESS_DIR/../results`) instead of cd-resolved absolute path, since the results directory may not exist at source time
- Submodule update uses `>/dev/null 2>&1` to prevent "Submodule path..." messages from polluting stdout

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed stdout pollution from git commands**
- **Found during:** Task 2 (bench-reset.sh verification)
- **Issue:** `git worktree add` outputs "HEAD is now at..." to stdout, and `git submodule update` outputs "Submodule path..." to stdout. This polluted the function's return value channel (workdir path echoed on stdout).
- **Fix:** Changed `2>/dev/null` to `>/dev/null 2>&1` for both git worktree add and git submodule update commands.
- **Files modified:** benchmarks/harness/bench-reset.sh
- **Verification:** `WORKDIR=$(bash bench-reset.sh create <id> bench/baseline)` returns only the workdir path, no git noise.
- **Committed in:** f56d4a8 (Task 2 commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Essential fix for correctness. Without it, callers capturing stdout would get corrupted paths. No scope creep.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- common.sh is ready to be sourced by all future harness scripts (bench-run.sh, modes/cc.sh, metrics.sh)
- bench-reset.sh is ready to be called by bench-run.sh for worktree lifecycle management
- Plan 02 (CC mode and metrics extraction) can proceed immediately

---
*Phase: 22-harness-core-and-cc-mode*
*Completed: 2026-03-11*
