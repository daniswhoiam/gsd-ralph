---
phase: 12-defense-in-depth-and-observability
plan: 02
subsystem: infra
tags: [pretooluse-hook, askuserquestion-denial, audit-logging, settings-lifecycle, bash, jq]

# Dependency graph
requires:
  - phase: 12-defense-in-depth-and-observability
    provides: ralph-launcher.sh run_loop with audit lifecycle, _init_audit_log, _print_audit_summary, AUDIT_FILE path
provides:
  - scripts/ralph-hook.sh PreToolUse hook denying AskUserQuestion with guidance
  - _install_hook function for auto-installing hook into settings.local.json
  - _remove_hook function for cleanly removing hook preserving other settings
  - _cleanup function with trap-based lifecycle on EXIT/INT/TERM
  - Audit logging of denied AskUserQuestion calls with timestamps
affects: [future-resilience, future-orchestration]

# Tech tracking
tech-stack:
  added: []
  patterns: [pretooluse-hook-pattern, settings-merge-lifecycle, trap-cleanup]

key-files:
  created:
    - scripts/ralph-hook.sh
    - tests/ralph-hook.bats
  modified:
    - scripts/ralph-launcher.sh
    - tests/ralph-launcher.bats
    - tests/test_helper/ralph-helpers.bash
    - .planning/REQUIREMENTS.md

key-decisions:
  - "Hook uses jq for both JSON parsing (stdin) and JSON output (deny decision) -- consistent, handles escaping"
  - "Trap-based cleanup replaces explicit _print_audit_summary calls at each exit path -- simpler, guaranteed"
  - "settings.local.json merge/unmerge via jq preserves existing permissions and other hooks"
  - "RALPH_AUDIT_FILE env var allows hook to write to same audit log as launcher"

patterns-established:
  - "Settings lifecycle: read-merge-write on install, selective-remove on cleanup"
  - "Defense-in-depth: SKILL.md Rule 1 (behavioral) + PreToolUse hook (enforcement) + headless mode (structural)"
  - "Trap cleanup: single _cleanup function handles both hook removal and audit summary"

requirements-completed: [SAFE-04, OBSV-04]

# Metrics
duration: 9min
completed: 2026-03-10
---

# Phase 12 Plan 02: PreToolUse Hook and Lifecycle Summary

**PreToolUse hook denying AskUserQuestion with audit logging, auto-installed into settings.local.json by launcher with trap-based cleanup on exit**

## Performance

- **Duration:** 9 min
- **Started:** 2026-03-10T14:13:33Z
- **Completed:** 2026-03-10T14:22:47Z
- **Tasks:** 2 (TDD: RED + GREEN each)
- **Files modified:** 6

## Accomplishments
- PreToolUse hook script that denies AskUserQuestion with correct JSON format and guidance message
- Hook logs all denied questions with timestamps to the audit log for post-run review
- Auto-install/remove lifecycle merges hook config into settings.local.json preserving existing content
- Trap-based cleanup ensures hook is removed on normal exit, Ctrl+C, and TERM signals
- 14 new tests (7 hook, 7 launcher), 310 total suite, zero regressions
- All 16 v2.0 requirements now complete in REQUIREMENTS.md traceability

## Task Commits

Each task was committed atomically:

1. **Task 1 (RED): Failing hook tests** - `8bd2770` (test)
2. **Task 1 (GREEN): Hook implementation** - `fa88453` (feat)
3. **Task 2 (RED): Failing install/remove tests** - `a3eb6e7` (test)
4. **Task 2 (GREEN): Hook lifecycle implementation** - `713f2bf` (feat)
5. **Task 2 (REQUIREMENTS): Traceability update** - `381525e` (docs)

_TDD tasks with RED-GREEN commits._

## Files Created/Modified
- `scripts/ralph-hook.sh` - PreToolUse hook: reads JSON stdin, denies AskUserQuestion with hookSpecificOutput.permissionDecision: "deny", logs to audit, allows all other tools
- `tests/ralph-hook.bats` - 7 tests covering deny/allow/audit behaviors
- `scripts/ralph-launcher.sh` - Added _install_hook, _remove_hook, _cleanup functions; trap EXIT/INT/TERM in run_loop; removed explicit _print_audit_summary calls
- `tests/ralph-launcher.bats` - 7 new tests for hook install/remove lifecycle
- `tests/test_helper/ralph-helpers.bash` - Added create_mock_settings_local helper
- `.planning/REQUIREMENTS.md` - SAFE-04 complete, OBSV-03 deferred note, all 16 requirements complete

## Decisions Made
- Hook uses jq for both JSON parsing (stdin) and JSON construction (deny output) -- consistent tooling, handles escaping correctly
- Trap-based cleanup replaces explicit _print_audit_summary calls at each run_loop exit path -- simpler code, guaranteed execution
- Settings lifecycle uses jq merge on install and selective jq filter on remove -- preserves all existing content
- RALPH_AUDIT_FILE environment variable shared between launcher and hook script for unified audit logging
- create_mock_settings_local helper uses heredoc instead of echo to avoid bats/glob expansion issues with JSON content

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed create_mock_settings_local helper using echo**
- **Found during:** Task 2 (GREEN phase, running tests)
- **Issue:** `echo "$content"` in the helper function caused jq parse errors when JSON contained special characters like `*)` due to bats test framework interaction
- **Fix:** Switched helper to use heredoc (`cat > file <<JSONEOF`) for reliable JSON writing
- **Files modified:** tests/test_helper/ralph-helpers.bash
- **Verification:** All 7 install/remove tests pass
- **Committed in:** 713f2bf (Task 2 GREEN commit)

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** Minor test helper fix. No scope creep.

## Issues Encountered

None beyond the auto-fixed deviation above.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness
- Phase 12 complete: all defense-in-depth and observability features implemented
- v2.0 Autopilot Core milestone ready for verification
- All 16 v2.0 requirements addressed and complete in REQUIREMENTS.md

## Self-Check: PASSED

All files verified present. All commits verified in git log.

---
*Phase: 12-defense-in-depth-and-observability*
*Completed: 2026-03-10*
