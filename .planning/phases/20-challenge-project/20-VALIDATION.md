---
phase: 20
slug: challenge-project
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-11
---

# Phase 20 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats-core 1.13.0 (bundled at tests/bats/) |
| **Config file** | None — Bats uses command-line invocation |
| **Quick run command** | `./tests/bats/bin/bats benchmarks/taskctl/tests/` |
| **Full suite command** | `./tests/bats/bin/bats benchmarks/taskctl/tests/` |
| **Estimated runtime** | ~2 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats benchmarks/taskctl/tests/`
- **After every plan wave:** Run `./tests/bats/bin/bats benchmarks/taskctl/tests/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 20-01-xx | 01 | 1 | CHAL-01 | integration | `./tests/bats/bin/bats benchmarks/taskctl/tests/test_add.bats benchmarks/taskctl/tests/test_list.bats` | ❌ W0 | ⬜ pending |
| 20-01-xx | 01 | 1 | CHAL-02 | manual+smoke | `cd benchmarks/taskctl && src/taskctl.sh done 3` then verify wrong task marked | N/A | ⬜ pending |
| 20-01-xx | 01 | 1 | CHAL-03 | smoke | `ls benchmarks/taskctl/tests/test_done.bats 2>/dev/null && echo "FAIL" \|\| echo "PASS"` | N/A | ⬜ pending |
| 20-01-xx | 01 | 1 | CHAL-04 | smoke | `shellcheck benchmarks/taskctl/src/format.sh 2>&1 \| grep -c 'SC[0-9]'` (expect > 0) | N/A | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `benchmarks/taskctl/tests/test_add.bats` — created as part of this phase (4 tests for CHAL-01)
- [ ] `benchmarks/taskctl/tests/test_list.bats` — created as part of this phase (3 tests for CHAL-01/CHAL-03)
- [ ] Bats helper setup for taskctl tests (load paths pointing to project bats-core)

*Note: The taskctl Bats tests are part of the DELIVERABLE, not pre-existing infrastructure. They are written as part of CHAL-03 to provide partial coverage.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| done.sh marks wrong task | CHAL-02 | Planted bug must be observable, not auto-fixed | 1. `cd benchmarks/taskctl` 2. Add 4 tasks 3. Run `src/taskctl.sh done 3` 4. Verify task 4 is marked instead of task 3 |
| bench/baseline tag restores exact state | CHAL-01 | One-time tag verification | `git tag -l 'bench/baseline'` returns tag; checkout restores clean state |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
