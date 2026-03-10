---
phase: 16
slug: end-to-end-validation
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 16 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats 1.x (vendored at tests/bats/) |
| **Config file** | None (bats uses convention) |
| **Quick run command** | `./tests/bats/bin/bats tests/e2e-install.bats` |
| **Full suite command** | `./tests/bats/bin/bats tests/*.bats` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats tests/e2e-install.bats`
- **After every plan wave:** Run `./tests/bats/bin/bats tests/*.bats`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 16-01-01 | 01 | 1 | SC-1a | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "fresh GSD"` | ❌ W0 | ⬜ pending |
| 16-01-02 | 01 | 1 | SC-1b | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "existing .claude"` | ❌ W0 | ⬜ pending |
| 16-01-03 | 01 | 1 | SC-1c | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "non-GSD"` | ❌ W0 | ⬜ pending |
| 16-01-04 | 01 | 1 | SC-2 | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "dry-run"` | ❌ W0 | ⬜ pending |
| 16-01-05 | 01 | 1 | SC-3 | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "idempotent"` | ❌ W0 | ⬜ pending |
| 16-01-06 | 01 | 1 | SC-4 | structural | Inherent from `_common_setup` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/e2e-install.bats` — E2E install workflow scenario tests covering SC-1 through SC-4

*Existing infrastructure covers all phase requirements. No new frameworks or helpers needed.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
