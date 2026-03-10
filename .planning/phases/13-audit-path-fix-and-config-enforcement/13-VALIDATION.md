---
phase: 13
slug: audit-path-fix-and-config-enforcement
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 13 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats 1.x (bats-core) |
| **Config file** | tests/bats/ (bundled binary) |
| **Quick run command** | `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats` |
| **Full suite command** | `./tests/bats/bin/bats tests/*.bats` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats`
- **After every plan wave:** Run `./tests/bats/bin/bats tests/*.bats`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 5 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 0 | OBSV-04a | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "exports RALPH_AUDIT_FILE"` | ❌ W0 | ⬜ pending |
| 13-01-02 | 01 | 1 | OBSV-04a | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "exports RALPH_AUDIT_FILE"` | ❌ W0 | ⬜ pending |
| 13-01-03 | 01 | 0 | OBSV-04c | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "disabled\|enabled"` | ❌ W0 | ⬜ pending |
| 13-01-04 | 01 | 1 | OBSV-04c | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "enabled"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] New tests in `tests/ralph-launcher.bats` for RALPH_AUDIT_FILE export verification
- [ ] New tests in `tests/ralph-launcher.bats` for ralph.enabled enforcement (true, false, missing)

*Existing infrastructure (`ralph-helpers.bash` with `create_ralph_config`) already supports creating configs with `enabled: true/false`.*

---

## Manual-Only Verifications

*All phase behaviors have automated verification.*

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 5s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
