---
phase: 11-shell-launcher-and-headless-invocation
plan: 01
subsystem: cli
tags: [bash, claude-code, headless, permissions, worktree, tdd, bats]

# Dependency graph
requires:
  - phase: 10-core-architecture-and-autonomous-behavior
    provides: validate-config.sh, assemble-context.sh, SKILL.md, config.json schema
provides:
  - scripts/ralph-launcher.sh with 6 core functions (parse_args, read_config, build_permission_flags, build_prompt, build_claude_command, dry_run_output)
  - .claude/commands/gsd/ralph.md GSD command entry point
  - Permission tier mapping (default/auto-mode/yolo to CLI flags)
  - TDD test coverage for launcher and permissions (22 tests)
affects: [11-02-PLAN loop-engine, 12-defense-in-depth]

# Tech tracking
tech-stack:
  added: []
  patterns: [guarded-main-for-testability, env-u-CLAUDECODE-nesting, gsd-command-delegates-to-bash]

key-files:
  created:
    - scripts/ralph-launcher.sh
    - .claude/commands/gsd/ralph.md
    - tests/ralph-permissions.bats
    - tests/ralph-launcher.bats
  modified:
    - tests/test_helper/ralph-helpers.bash

key-decisions:
  - "GSD command file delegates all logic to bash script for testability"
  - "env -u CLAUDECODE prepended to all claude -p invocations for nested session safety"
  - "Permission tier uses case statement with error on unknown tier (fail-safe)"

patterns-established:
  - "Guarded main pattern: if BASH_SOURCE[0] = $0 for sourceable functions"
  - "GSD command files are declarative prompts that delegate to testable bash scripts"
  - "build_claude_command always prepends env -u CLAUDECODE"

requirements-completed: [AUTO-01, AUTO-05, PERM-01, PERM-02, PERM-03, SAFE-01, SAFE-02]

# Metrics
duration: 3min
completed: 2026-03-10
---

# Phase 11 Plan 01: Shell Launcher Core Summary

**Ralph launcher with arg parsing, config reading, 3 permission tiers, claude -p command builder, and --dry-run preview via /gsd:ralph command**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-10T10:41:15Z
- **Completed:** 2026-03-10T10:44:34Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments
- Built ralph-launcher.sh with 6 independently sourceable functions (236 LOC)
- Full TDD coverage: 22 tests across ralph-permissions.bats (4) and ralph-launcher.bats (18)
- Created /gsd:ralph command file for GSD slash command entry point
- All 3 permission tiers correctly mapped: default (--allowedTools), auto-mode (--permission-mode auto), yolo (--dangerously-skip-permissions)
- --dry-run shows full command preview with config summary

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: TDD failing tests** - `8883d35` (test)
2. **Task 1 GREEN: Launcher implementation** - `060fbbc` (feat)
3. **Task 2: /gsd:ralph command file** - `2837612` (feat)

_TDD task had separate RED and GREEN commits._

## Files Created/Modified
- `scripts/ralph-launcher.sh` - Core launcher with parse_args, read_config, build_permission_flags, build_prompt, build_claude_command, dry_run_output
- `.claude/commands/gsd/ralph.md` - GSD slash command entry point delegating to launcher
- `tests/ralph-permissions.bats` - 4 tests for permission tier flag mapping
- `tests/ralph-launcher.bats` - 18 tests for arg parsing, config, prompt, command building, dry-run
- `tests/test_helper/ralph-helpers.bash` - Added create_mock_claude_command and create_context_file helpers

## Decisions Made
- GSD command file is a declarative prompt that delegates to scripts/ralph-launcher.sh (testability over inline logic)
- `env -u CLAUDECODE` prepended to all claude -p invocations to prevent nested session blocking (Pitfall 1 from RESEARCH.md)
- Invalid permission tier returns error (fail-safe, not silent fallback)
- build_prompt handles 4 command types: execute-phase, verify-work, plan-phase, and unrecognized (with default fallback)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- ralph-launcher.sh has all core functions ready for Plan 02's loop engine
- Main execution block has placeholder for loop (prints error directing to --dry-run)
- assemble-context.sh integration point ready (called in main block)
- Plan 02 needs to add: iteration loop, STATE.md completion detection, retry logic, terminal bell

## Self-Check: PASSED

All 6 files verified present. All 3 task commits verified in git log.

---
*Phase: 11-shell-launcher-and-headless-invocation*
*Completed: 2026-03-10*
