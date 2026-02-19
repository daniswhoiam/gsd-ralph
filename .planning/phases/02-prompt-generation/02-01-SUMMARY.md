---
phase: 02-prompt-generation
plan: 01
subsystem: discovery
tags: [bash, discovery, templates, test-fixtures]
requires: []
provides:
  - Plan file discovery module (find_phase_dir, discover_plan_files, plan_id_from_filename)
  - Parameterized PROMPT.md and AGENT.md templates
  - Test fixture infrastructure for plan files
  - 12 discovery unit tests
affects: [02-prompt-generation, 03-phase-execution]
tech-stack:
  added: []
  patterns: [glob-based-discovery, parameterized-templates, PLAN_FILES-global-array]
key-files:
  created:
    - lib/discovery.sh
    - templates/PROMPT.md.template
    - templates/AGENT.md.template
    - tests/discovery.bats
    - tests/test_helper/fixtures/
  modified: []
key-decisions:
  - "Glob pattern [0-9][0-9]-[0-9][0-9]-PLAN.md for precise plan matching"
  - "Global variables (PHASE_DIR, PLAN_FILES, PLAN_COUNT) for discovery results"
patterns-established:
  - "Discovery module: find_phase_dir sets PHASE_DIR, discover_plan_files sets PLAN_FILES array"
  - "Parameterized templates with {{VARIABLE}} placeholders rendered by templates.sh"
requirements-completed:
  - EXEC-07
duration: single-session
completed: 2026-02-18
---

# Plan 02-01 Summary: Discovery module, parameterized templates, and test fixtures

## What Was Built
- `lib/discovery.sh` — GSD plan file discovery module with 4 functions: find_phase_dir, discover_plan_files, plan_id_from_filename, worktree_path_for_plan
- `templates/PROMPT.md.template` — Fully parameterized PROMPT.md template with {{PROJECT_NAME}}, {{PROJECT_LANG}}, {{TEST_CMD}}, {{BUILD_CMD}} placeholders; all bayesian-it/TypeScript specifics removed
- `templates/AGENT.md.template` — Fully parameterized AGENT.md template with same variables
- `tests/discovery.bats` — 12 unit tests covering all discovery functions and edge cases
- `tests/test_helper/fixtures/` — Test fixture plan files for single-plan, multi-plan (3 plans), and edge-case (empty) scenarios

## Key Decisions
- Used `shellcheck disable` comments for SC2012 (ls vs find) and SC2034 (global variables used by callers) rather than restructuring — these are intentional patterns
- Glob pattern `[0-9][0-9]-[0-9][0-9]-PLAN.md` used for precise matching of numbered plans, avoiding false matches on files like RESEARCH-PLAN.md
- Removed File Structure section from PROMPT.md template (project-specific, will be populated dynamically by prompt.sh in Plan 02-02)
- AGENT.md template kept minimal: just build/test commands and project info

## Verification Results
- `shellcheck -s bash lib/discovery.sh` — PASS
- `make check` — PASS (lint clean, 50/50 tests)
- `grep -c '@test' tests/discovery.bats` — 12 (>= 10 required)
- No bayesian/vitest/zod/better-sqlite references in templates
- All 4 required placeholders present in both templates
- Test fixtures exist for single-plan, multi-plan, edge-cases
- No bash 4+ features in new code

## Files Modified
- Created: `lib/discovery.sh`
- Created: `tests/discovery.bats`
- Created: `tests/test_helper/fixtures/single-plan/PLAN.md`
- Created: `tests/test_helper/fixtures/multi-plan/02-01-PLAN.md`
- Created: `tests/test_helper/fixtures/multi-plan/02-02-PLAN.md`
- Created: `tests/test_helper/fixtures/multi-plan/02-03-PLAN.md`
- Created: `tests/test_helper/fixtures/edge-cases/empty-plan.md`
- Modified: `templates/PROMPT.md.template`
- Modified: `templates/AGENT.md.template`

## Metrics
- Tasks completed: 2
- Tests added: 12
- Lines of code added: ~77 (discovery.sh) + ~112 (discovery.bats) + ~50 (fixtures) = ~239
