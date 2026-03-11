---
phase: 21
slug: correctness-checks
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 21 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats-core 1.13.0 (bundled at tests/bats/) + standalone Bash check scripts |
| **Config file** | None — Bats uses CLI invocation; check scripts are standalone |
| **Quick run command** | `bash benchmarks/challenges/checks/check-fix-bug.sh benchmarks/taskctl` |
| **Full suite command** | `for c in fix-bug add-feature add-tests refactor multi-file; do bash benchmarks/harness/bench-eval.sh "$c"; done` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run the check script for the challenge being implemented + validate against baseline (negative control)
- **After every plan wave:** Run all 5 check scripts against baseline (all should FAIL) + all 5 against reference solutions (all should PASS)
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 21-01-01 | 01 | 1 | HARN-03 | integration | `bash benchmarks/challenges/checks/check-fix-bug.sh benchmarks/taskctl` (should FAIL on baseline) | ❌ W0 | ⬜ pending |
| 21-01-02 | 01 | 1 | HARN-03 | integration | `bash benchmarks/challenges/checks/check-add-feature.sh benchmarks/taskctl` (should FAIL on baseline) | ❌ W0 | ⬜ pending |
| 21-01-03 | 01 | 1 | HARN-03 | integration | `bash benchmarks/challenges/checks/check-add-tests.sh benchmarks/taskctl` (should FAIL on baseline) | ❌ W0 | ⬜ pending |
| 21-01-04 | 01 | 1 | HARN-03 | integration | `bash benchmarks/challenges/checks/check-refactor.sh benchmarks/taskctl` (should FAIL on baseline) | ❌ W0 | ⬜ pending |
| 21-01-05 | 01 | 1 | HARN-03 | integration | `bash benchmarks/challenges/checks/check-multi-file.sh benchmarks/taskctl` (should FAIL on baseline) | ❌ W0 | ⬜ pending |
| 21-02-01 | 02 | 1 | CHAL-06 | integration | Overlay reference solution + run check (should PASS) | ❌ W0 | ⬜ pending |
| 21-02-02 | 02 | 1 | HARN-05 | unit | `for f in benchmarks/challenges/*.json; do jq -e '.id and .prompt and .starting_tag and .time_cap_minutes and .check_script' "$f"; done` | ❌ W0 | ⬜ pending |
| 21-02-03 | 02 | 1 | CHAL-05 | smoke | `git tag -l 'bench/after-delete'` + verify delete works | ❌ W0 | ⬜ pending |
| 21-02-04 | 02 | 1 | HARN-03 | integration | `bash benchmarks/harness/bench-eval.sh fix-bug benchmarks/taskctl` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `benchmarks/challenges/` directory structure
- [ ] `benchmarks/challenges/checks/check-*.sh` — 5 check scripts
- [ ] `benchmarks/challenges/*.json` — 5 challenge definition files
- [ ] `benchmarks/challenges/reference-solutions/` — 5 reference solution sets
- [ ] `benchmarks/harness/bench-eval.sh` — eval driver script
- [ ] `bench/after-delete` git tag

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| bench/after-delete tag is clean | CHAL-05 | Git tag state verified visually | `git checkout bench/after-delete && bash benchmarks/taskctl/src/taskctl.sh delete 1 && git checkout -` |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
