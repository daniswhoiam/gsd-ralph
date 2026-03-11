---
phase: 21-correctness-checks
verified: 2026-03-11T12:07:15Z
status: passed
score: 4/4 must-haves verified
re_verification: false
---

# Phase 21: Correctness Checks and Challenge Definitions Verification Report

**Phase Goal:** Evaluation infrastructure is validated before any automated benchmark runs, ensuring correctness checks reliably distinguish passing from failing solutions
**Verified:** 2026-03-11T12:07:15Z
**Status:** PASSED
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP.md Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Each of the 5 challenge correctness checks FAILS when run against `bench/baseline` state (negative control) | VERIFIED | All 4 baseline-starting checks (fix-bug, add-feature, add-tests, refactor) return exit code 1 against `benchmarks/taskctl/`. check-multi-file correctly fails against simulated after-delete state. |
| 2 | Each of the 5 challenge correctness checks PASSES when run against its reference solution (positive control) | VERIFIED | All 5 checks return exit code 0 when reference solution overlay is applied. Confirmed live: fix-bug 3/3, add-feature 4/4, add-tests 4/4, refactor 4/4, multi-file 6/6. |
| 3 | `bench/after-delete` git tag exists and checking it out shows a working delete command (Challenge 5 starting state) | VERIFIED | `git tag -l bench/after-delete` returns the tag. Tag is annotated (type: tag object). `git show bench/after-delete:benchmarks/taskctl/src/commands/delete.sh` shows working delete.sh. Done bug confirmed still present (uses `jq --argjson idx "$task_id" '.[$idx].done = true'` — array index not .id). |
| 4 | Each challenge has a declarative JSON definition file containing prompt text, starting tag, time cap, and check script reference | VERIFIED | All 5 JSON files (fix-bug.json, add-feature.json, add-tests.json, refactor.json, multi-file.json) validated with `jq -e` — all required fields present: id, name, number, starting_tag, prompt, time_cap_minutes, check_script, check_count, checks, measures. |

**Score:** 4/4 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `benchmarks/challenges/reference-solutions/fix-bug/` | Fixed done.sh (ID lookup) + test_done.bats | VERIFIED | done.sh uses `jq map(if .id == $id then .done = true else . end)`. test_done.bats present. |
| `benchmarks/challenges/reference-solutions/add-feature/` | delete.sh + taskctl.sh dispatch + test_delete.bats | VERIFIED | All 3 files exist. delete.sh filters by `.id != $id`. taskctl.sh adds `delete)` case. |
| `benchmarks/challenges/reference-solutions/add-tests/` | test_storage.bats with 5+ tests | VERIFIED | 6 tests covering: empty file, missing file, storage_add fields, storage_next_id, multiple adds, read-after-add. |
| `benchmarks/challenges/reference-solutions/refactor/` | Cleaned format.sh | VERIFIED | File exists. Confirmed passes check-refactor.sh (10+ lines changed vs baseline, ShellCheck warnings reduced). |
| `benchmarks/challenges/reference-solutions/multi-file/` | Priority feature across add.sh, list.sh, storage.sh + test_priority.bats | VERIFIED | All 4 files exist. Confirmed passes check-multi-file.sh 6/6. |
| `benchmarks/challenges/checks/check-fix-bug.sh` | Behavioral check for Challenge 1, min 30 lines, executable | VERIFIED | 81 lines, -rwxr-xr-x permissions. Contains check() helper, PASS/FAIL output, Score format. |
| `benchmarks/challenges/checks/check-add-feature.sh` | Behavioral check for Challenge 2, min 30 lines, executable | VERIFIED | 74 lines, -rwxr-xr-x permissions. 4 behavioral checks. |
| `benchmarks/challenges/checks/check-add-tests.sh` | Behavioral check for Challenge 3, min 25 lines, executable | VERIFIED | 77 lines, -rwxr-xr-x permissions. 4 behavioral checks. |
| `benchmarks/challenges/checks/check-refactor.sh` | Behavioral check for Challenge 4, min 30 lines, executable | VERIFIED | 78 lines, -rwxr-xr-x permissions. 4 checks including ShellCheck comparison. |
| `benchmarks/challenges/checks/check-multi-file.sh` | Behavioral check for Challenge 5, min 40 lines, executable | VERIFIED | 132 lines, -rwxr-xr-x permissions. 6 behavioral checks with bench/after-delete references. |
| `benchmarks/challenges/fix-bug.json` | Challenge 1 definition containing `check-fix-bug.sh` | VERIFIED | All schema fields valid. `check_script: "checks/check-fix-bug.sh"`. |
| `benchmarks/challenges/add-feature.json` | Challenge 2 definition containing `check-add-feature.sh` | VERIFIED | All schema fields valid. `starting_tag: "bench/baseline"`. |
| `benchmarks/challenges/add-tests.json` | Challenge 3 definition containing `check-add-tests.sh` | VERIFIED | All schema fields valid. |
| `benchmarks/challenges/refactor.json` | Challenge 4 definition containing `check-refactor.sh` | VERIFIED | All schema fields valid. |
| `benchmarks/challenges/multi-file.json` | Challenge 5 definition containing `check-multi-file.sh` | VERIFIED | All schema fields valid. `starting_tag: "bench/after-delete"`. |
| `benchmarks/harness/bench-eval.sh` | Eval driver loading JSON and running checks, min 20 lines | VERIFIED | 42 lines, -rwxr-xr-x. Uses `BASH_SOURCE[0]` for path resolution. Outputs `RESULT: PASS/FAIL`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `benchmarks/harness/bench-eval.sh` | `benchmarks/challenges/*.json` | `jq -r '.check_script'` | VERIFIED | Line 24: `CHECK_SCRIPT=$(jq -r '.check_script' "$CHALLENGE_FILE")` |
| `benchmarks/harness/bench-eval.sh` | `benchmarks/challenges/checks/check-*.sh` | `bash "$CHALLENGES_DIR/$CHECK_SCRIPT"` | VERIFIED | Line 32: `bash "$CHALLENGES_DIR/$CHECK_SCRIPT" "$TASKCTL_DIR"` |
| `benchmarks/challenges/checks/check-multi-file.sh` | `bench/after-delete` | `git diff --name-only bench/after-delete` | VERIFIED | Lines 109 and 118 reference `bench/after-delete` for changed-file counting |
| `benchmarks/challenges/checks/check-fix-bug.sh` | `benchmarks/taskctl/src/commands/done.sh` | Sources done.sh, runs cmd_done, checks jq output | VERIFIED | Lines 43-48: sources done.sh in subshell, runs cmd_done 3, checks `.id == 3` with jq |
| `benchmarks/challenges/checks/check-add-feature.sh` | `benchmarks/taskctl/src/taskctl.sh` | Runs taskctl.sh delete command | VERIFIED | Line 39: `TASKCTL_DATA="$tmpdata" bash "$TASKCTL_DIR/src/taskctl.sh" delete 1` |
| `benchmarks/challenges/checks/check-add-tests.sh` | `benchmarks/taskctl/tests/test_storage.bats` | Checks file existence, test count, Bats pass | VERIFIED | Lines 35, 42, 54 reference `tests/test_storage.bats` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| CHAL-05 | 21-02-PLAN.md | `bench/after-delete` git tag exists with working delete command (for Challenge 5) | SATISFIED | Tag confirmed via `git tag -l`; delete.sh verified at tag; done bug confirmed still present at after-delete state |
| CHAL-06 | 21-01-PLAN.md | Reference solutions exist for all 5 challenges as correctness check validation controls | SATISFIED | All 5 reference solution directories verified with correct file sets (11 files total) |
| HARN-03 | 21-01-PLAN.md, 21-02-PLAN.md | `bench-eval.sh` runs behavioral (not structural) correctness checks per challenge | SATISFIED | All 5 check scripts test observable behavior (CLI output, file contents, test results) — no code pattern matching. Comment `# Behavioral checks ONLY -- tests outcomes, not code patterns (HARN-03)` appears in all scripts. bench-eval.sh delegates to check scripts. |
| HARN-05 | 21-02-PLAN.md | Challenge definitions are declarative JSON files with prompt, starting tag, time cap, and check reference | SATISFIED | All 5 JSON files validated with jq against full schema (10 required fields all present) |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| check-fix-bug.sh | 36 | `/tmp/taskctl_check_XXXX.json` in mktemp path | Info | Not a TODO — `XXXX` is mktemp template syntax. No actual anti-patterns found. |

No genuine anti-patterns detected. No TODO/FIXME comments, no stub implementations, no empty handlers, no static returns.

### Human Verification Required

The following item requires human testing and cannot be verified programmatically:

**1. check-multi-file.sh negative control against actual bench/after-delete worktree**

**Test:** Check out bench/after-delete tag into a fresh worktree, run `bash benchmarks/challenges/checks/check-multi-file.sh <worktree-path>/benchmarks/taskctl`
**Expected:** Exit code 1 with checks 1-4 and 6 failing, check 5 (existing tests pass) passing
**Why human:** The negative control was verified against a simulated after-delete state (baseline + add-feature overlay). The actual git tag worktree environment and submodule initialization may differ slightly from a manual copy. This is a belt-and-suspenders check — the simulated test passed cleanly — but a live worktree checkout is definitive.

### Dual Control Validation Results

All checks were run live during verification:

**Negative controls (must FAIL against baseline/after-delete):**
- check-fix-bug.sh vs baseline: FAIL (exit 1) — Score 1/3
- check-add-feature.sh vs baseline: FAIL (exit 1) — Score 1/4
- check-add-tests.sh vs baseline: FAIL (exit 1) — Score 1/4
- check-refactor.sh vs baseline: FAIL (exit 1) — Score 2/4
- check-multi-file.sh vs simulated after-delete: FAIL (exit 1) — Score 1/6

**Positive controls (must PASS with reference solution):**
- check-fix-bug.sh + fix-bug overlay: PASS (exit 0) — Score 3/3
- check-add-feature.sh + add-feature overlay: PASS (exit 0) — Score 4/4
- check-add-tests.sh + add-tests overlay: PASS (exit 0) — Score 4/4
- check-refactor.sh + refactor overlay: PASS (exit 0) — Score 4/4
- check-multi-file.sh + add-feature + multi-file overlays: PASS (exit 0) — Score 6/6

**bench-eval.sh end-to-end:** Confirmed outputs `RESULT: FAIL` for fix-bug challenge against baseline.

### Git Commit Verification

All 4 task commits documented in summaries confirmed in git log:
- `b52030c` — feat(21-01): create reference solution overlays for all 5 challenges
- `f1a9b2a` — feat(21-01): create check scripts for challenges 1-3 with dual-control validation
- `a205f92` — feat(21-02): create check scripts for challenges 4-5 and bench/after-delete tag
- `b59779e` — feat(21-02): create 5 challenge JSON definitions and bench-eval.sh driver

---

_Verified: 2026-03-11T12:07:15Z_
_Verifier: Claude (gsd-verifier)_
