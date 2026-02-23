---
status: resolved
trigger: "execute-dependency-validation-failure: dependency validation fails with Plan 02 depends on '09-01' which does not exist in phase"
created: 2026-02-23T00:00:00Z
updated: 2026-02-23T00:10:00Z
---

## Current Focus

hypothesis: CONFIRMED -- plan_id_from_filename extracts plan-only IDs ("01") but depends_on values in frontmatter use phase-prefixed format ("09-01"), causing a mismatch in validate_phase_dependencies
test: All 214 tests pass including 3 new regression tests
expecting: n/a
next_action: Archive session

## Symptoms

expected: Phase execution should succeed -- all plans exist and dependencies should resolve
actual: Dependency validation fails immediately, execution never starts
errors: |
  [info] Phase directory: .planning/phases/09-frontend-evolution
  [info] Found 6 plan(s)
  [info] Strategy: parallel (5 wave(s))
  [info] Phase has parallel-capable plans, but executing sequentially (parallel mode deferred)
  [error] Plan 02 depends on '09-01' which does not exist in phase
  [error] Phase dependency validation failed
reproduction: Run gsd execute on phase 09 in ~/Projects/vibecheck
started: First time trying execute on this project

## Eliminated

(none -- root cause found on first hypothesis)

## Evidence

- timestamp: 2026-02-23T00:01:00Z
  checked: Plan file 09-02-PLAN.md frontmatter
  found: depends_on field is [09-01] -- phase-prefixed format
  implication: The dependency is declared with phase prefix "09-01"

- timestamp: 2026-02-23T00:01:30Z
  checked: plan_id_from_filename() in lib/discovery.sh (line 58-68)
  found: Regex ^[0-9][0-9]-([0-9][0-9])-PLAN\.md$ captures only group 1 (the plan number). "09-01-PLAN.md" -> "01"
  implication: Plan IDs are plan-number-only ("01", "02", etc.)

- timestamp: 2026-02-23T00:02:00Z
  checked: parse_plan_frontmatter() inline array parsing in lib/frontmatter.sh
  found: Strips brackets and quotes but preserves the value "09-01" as-is
  implication: FM_DEPENDS_ON contains "09-01" (phase-prefixed)

- timestamp: 2026-02-23T00:02:30Z
  checked: validate_phase_dependencies() in lib/strategy.sh (line 108-128)
  found: Compares plan_ids[j] ("01") against dep ("09-01") with exact string match
  implication: "01" != "09-01" causes the false "does not exist" error

- timestamp: 2026-02-23T00:05:00Z
  checked: All 6 plan files in vibecheck phase 09
  found: Every plan with dependencies uses phase-prefixed format (09-01, 09-02, etc.)
  implication: This is a consistent convention in the user's project, not a one-off typo

- timestamp: 2026-02-23T00:08:00Z
  checked: Existing test fixtures in tests/strategy.bats
  found: All test helpers use plan-only format (depends_on: ["01"]), which is why bug was never caught
  implication: Tests only covered the plan-only format; phase-prefixed format was untested

## Resolution

root_cause: Format mismatch between plan IDs and dependency references. plan_id_from_filename() extracts plan-only IDs (e.g., "01") from filenames like "09-01-PLAN.md". But depends_on values in plan frontmatter use phase-prefixed format (e.g., "09-01"). validate_phase_dependencies() does an exact string comparison, so "01" never matches "09-01".
fix: Added _normalize_dep_ref() helper function in lib/strategy.sh that strips the NN- phase prefix from dependency references (e.g., "09-01" -> "01"). validate_phase_dependencies() now normalizes all dependency references before comparison, supporting both "01" and "09-01" formats transparently.
verification: All 214 tests pass (15 pre-existing strategy tests + 3 new regression tests). New tests cover: (1) phase-prefixed sequential deps, (2) phase-prefixed multi-deps, (3) missing dep detection with phase-prefixed format.
files_changed:
  - lib/strategy.sh (added _normalize_dep_ref helper, normalize deps in validate_phase_dependencies)
  - tests/strategy.bats (added 3 regression tests for phase-prefixed depends_on format)
