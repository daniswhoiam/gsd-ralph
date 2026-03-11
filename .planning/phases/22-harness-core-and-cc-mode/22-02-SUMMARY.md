---
phase: 22-harness-core-and-cc-mode
plan: 02
subsystem: benchmarking
tags: [bash, jq, claude-cli, metrics, timeout, shellcheck]

# Dependency graph
requires:
  - phase: 21-correctness-checks-and-challenge-definitions
    provides: bench-eval.sh output format (Score X/Y) parsed by parse_eval_score
provides:
  - "metrics.sh: extract_metrics, parse_eval_score, shellcheck capture, commit metrics"
  - "cc.sh: mode_invoke implementing CC mode via timeout + claude -p --output-format json"
  - "Mode abstraction contract (mode_invoke signature) for all future mode implementations"
affects: [22-harness-core-and-cc-mode, 23-additional-modes]

# Tech tracking
tech-stack:
  added: [GNU timeout (time cap enforcement)]
  patterns: [defensive jq extraction with // fallbacks, mode abstraction via mode_invoke contract, source guard pattern for library scripts]

key-files:
  created:
    - benchmarks/harness/lib/metrics.sh
    - benchmarks/harness/lib/modes/cc.sh
  modified: []

key-decisions:
  - "Used --permission-mode auto instead of --dangerously-skip-permissions for safer tool auto-approval"
  - "Set tokens_input/tokens_output to 0 since --output-format json does not expose per-token counts (uses num_turns + total_cost_usd instead)"
  - "mode_invoke does cd into workdir to scope Claude to benchmarks/taskctl/ preventing out-of-scope file modifications"

patterns-established:
  - "Mode contract: mode_invoke(prompt, workdir, max_turns, time_cap_seconds) with JSON on stdout, stderr to .bench-stderr.log, exit code propagation"
  - "Source guard: BASH_SOURCE[0] == $0 check at top of sourced library files"
  - "Defensive jq: all field extractions use // fallbacks for missing or null values"

requirements-completed: [HARN-04, HARN-06, MODE-01, METR-01]

# Metrics
duration: 2min
completed: 2026-03-11
---

# Phase 22 Plan 02: CC Mode and Metrics Summary

**CC mode invocation via timeout + claude -p --output-format json, plus defensive metric extraction library with jq fallbacks**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-11T14:09:25Z
- **Completed:** 2026-03-11T14:12:06Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Created metrics.sh with 7 functions: extract_metrics, parse_eval_score, capture_shellcheck_baseline/post, count_commits, check_conventional_commits, count_tests_added
- Created cc.sh implementing the mode abstraction contract for CC mode (single claude -p call with timeout)
- All jq extractions use // fallbacks for missing fields per research Pitfall 1
- Time cap enforcement wired via GNU timeout with exit code 124 detection

## Task Commits

Each task was committed atomically:

1. **Task 1: Create metrics extraction library (metrics.sh)** - `202bb0e` (feat)
2. **Task 2: Create CC mode invocation script (cc.sh)** - `39f2527` (feat)

## Files Created/Modified
- `benchmarks/harness/lib/metrics.sh` - Metric extraction from claude -p JSON output and bench-eval.sh score parsing
- `benchmarks/harness/lib/modes/cc.sh` - CC mode invocation: thin wrapper around timeout + claude -p --output-format json

## Decisions Made
- Used --permission-mode auto (not --dangerously-skip-permissions) for safer benchmark runs
- Token fields (tokens_input/tokens_output) set to 0 in result schema since --output-format json lacks per-token counts; num_turns and total_cost_usd serve as efficiency proxies
- mode_invoke cd's into workdir before invoking claude to limit scope to benchmarks/taskctl/ (Pitfall 5 mitigation)
- --no-session-persistence used to avoid session file accumulation during benchmark runs

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- metrics.sh and cc.sh are ready to be sourced by bench-run.sh (Plan 03)
- Mode contract established: future modes (CC+GSD, CC+Ralph, CC+gsd-ralph in Phase 23) must implement mode_invoke with the same 4-argument signature
- Plan 01 (common.sh + bench-reset.sh) needed before bench-run.sh can orchestrate full pipeline

## Self-Check: PASSED

- FOUND: benchmarks/harness/lib/metrics.sh
- FOUND: benchmarks/harness/lib/modes/cc.sh
- FOUND: commit 202bb0e (Task 1)
- FOUND: commit 39f2527 (Task 2)

---
*Phase: 22-harness-core-and-cc-mode*
*Completed: 2026-03-11*
