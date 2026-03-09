---
phase: 10-core-architecture-and-autonomous-behavior
plan: 01
subsystem: infra
tags: [skill-md, config-validation, autonomous-behavior, bash, jq]

# Dependency graph
requires: []
provides:
  - "SKILL.md with 5 autonomous behavior rules (never AskUserQuestion, auto-approve, skip human-action, GSD conventions, clean exit)"
  - "Ralph config schema under config.json ralph key (enabled, max_turns, permission_tier)"
  - "Config validation script with strict-with-warnings semantics"
  - "Shared test helpers for Ralph test fixtures"
affects: [10-02, 11-launcher, 12-guardrails]

# Tech tracking
tech-stack:
  added: [jq]
  patterns: [skill-md-auto-discovery, strict-with-warnings-validation, bash-3.2-compatible]

key-files:
  created:
    - ".claude/skills/gsd-ralph-autopilot/SKILL.md"
    - "scripts/validate-config.sh"
    - "tests/skill-validation.bats"
    - "tests/ralph-config.bats"
    - "tests/test_helper/ralph-helpers.bash"
  modified:
    - ".planning/config.json"

key-decisions:
  - "SKILL.md kept as separate persistent file (not bundled into context assembly) for independent evolution"
  - "Config validation returns 0 (success) even with warnings -- strict-with-warnings, not strict-with-errors"
  - "Missing ralph key in config is a warning, not an error -- supports projects without Ralph configured"

patterns-established:
  - "SKILL.md user-invocable: false pattern for background auto-discovery by Claude Code"
  - "Config validation via jq in Bash 3.2 compatible scripts"
  - "Ralph test helpers in tests/test_helper/ralph-helpers.bash with create_ralph_config and create_mock_state fixtures"

requirements-completed: [AUTO-04]

# Metrics
duration: 3min
completed: 2026-03-09
---

# Phase 10 Plan 01: SKILL.md and Config Schema Summary

**Autonomous behavior SKILL.md with 5 rules (never AskUserQuestion, auto-approve checkpoints, skip human-action) plus ralph config schema with jq-based strict-with-warnings validation**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-09T18:59:34Z
- **Completed:** 2026-03-09T19:02:31Z
- **Tasks:** 1
- **Files modified:** 6

## Accomplishments
- Created SKILL.md at .claude/skills/gsd-ralph-autopilot/SKILL.md with all 5 autonomous behavior rules and user-invocable: false for auto-discovery
- Extended config.json with ralph key containing 3 essential settings (enabled, max_turns=50, permission_tier=default)
- Built validate-config.sh with strict-with-warnings validation (Bash 3.2 compatible, jq-based)
- Full TDD coverage: 18 tests across 2 test suites (skill-validation.bats + ralph-config.bats)

## Task Commits

Each task was committed atomically:

1. **Task 1 (TDD RED - SKILL.md tests):** `c2c9185` (test) - Failing tests for SKILL.md content and shared test helpers
2. **Task 1 (TDD GREEN - SKILL.md):** `e17dde4` (feat) - SKILL.md with 5 autonomous behavior rules
3. **Task 1 (TDD RED - config tests):** `1b088e0` (test) - Failing tests for config schema validation
4. **Task 1 (TDD GREEN - config + validation):** `1eede21` (feat) - Config schema extension and validate-config.sh

_Note: TDD task split into 4 commits following RED-GREEN-RED-GREEN cycle for two test suites._

## Files Created/Modified
- `.claude/skills/gsd-ralph-autopilot/SKILL.md` - Autonomous behavior rules (5 rules: decision handling, checkpoint approval, human-action skip, GSD conventions, clean exit)
- `.planning/config.json` - Extended with ralph key (enabled, max_turns, permission_tier)
- `scripts/validate-config.sh` - Config validation with strict-with-warnings semantics using jq
- `tests/skill-validation.bats` - 9 tests validating SKILL.md content and structure
- `tests/ralph-config.bats` - 9 tests validating config schema and validation function
- `tests/test_helper/ralph-helpers.bash` - Shared fixtures (create_ralph_config, create_mock_state, get_real_project_root)

## Decisions Made
- SKILL.md kept as separate persistent file for independent evolution (not bundled into context assembly blob)
- Config validation returns success (0) with warnings on stderr -- does not block on unknown keys or missing ralph key
- Used jq for all JSON parsing (no hand-rolled JSON parsing in bash)

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- SKILL.md is ready for auto-discovery by Claude Code in headless execution
- Config schema is ready for Phase 11 launcher to read ralph.enabled, ralph.max_turns, ralph.permission_tier
- validate-config.sh is ready for integration into launcher startup validation
- Test infrastructure (ralph-helpers.bash) available for Plan 02 and downstream phases

## Self-Check: PASSED

All 5 created files verified present. All 4 commit hashes verified in git log.

---
*Phase: 10-core-architecture-and-autonomous-behavior*
*Completed: 2026-03-09*
