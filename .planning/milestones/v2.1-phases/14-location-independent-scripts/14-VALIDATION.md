---
phase: 14
slug: location-independent-scripts
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 14 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats 1.x (vendored at tests/bats/) |
| **Config file** | none — no config file needed |
| **Quick run command** | `./tests/bats/bin/bats tests/ralph-launcher.bats` |
| **Full suite command** | `./tests/bats/bin/bats tests/*.bats` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-permissions.bats tests/ralph-hook.bats`
- **After every plan wave:** Run `./tests/bats/bin/bats tests/*.bats`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 14-01-01 | 01 | 1 | PORT-01, PORT-02 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "RALPH_SCRIPTS_DIR"` | ❌ W0 | ⬜ pending |
| 14-01-02 | 01 | 1 | PORT-01, PORT-02 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "auto-detects"` | ❌ W0 | ⬜ pending |
| 14-01-03 | 01 | 1 | PORT-03 | regression | `./tests/bats/bin/bats tests/*.bats` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New tests for `RALPH_SCRIPTS_DIR` override behavior (in `tests/ralph-launcher.bats`)
- [ ] New tests for `RALPH_SCRIPTS_DIR` auto-detection (in `tests/ralph-launcher.bats`)
- [ ] New test for hook script path using `RALPH_SCRIPTS_DIR` (in `tests/ralph-launcher.bats`)

*Existing infrastructure covers PORT-03 (regression). Wave 0 adds tests for PORT-01 and PORT-02.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
