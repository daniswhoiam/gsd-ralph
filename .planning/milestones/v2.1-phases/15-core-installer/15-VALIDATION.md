---
phase: 15
slug: core-installer
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 15 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats 1.x (vendored at tests/bats/) |
| **Config file** | None (bats uses convention) |
| **Quick run command** | `./tests/bats/bin/bats tests/installer.bats` |
| **Full suite command** | `./tests/bats/bin/bats tests/*.bats` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats tests/installer.bats`
- **After every plan wave:** Run `./tests/bats/bin/bats tests/*.bats`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 0 | INST-01..08 | integration | `./tests/bats/bin/bats tests/installer.bats` | No -- Wave 0 | pending |
| 15-01-02 | 01 | 1 | INST-02, INST-03 | unit | `./tests/bats/bin/bats tests/installer.bats -f "prerequisite"` | No -- Wave 0 | pending |
| 15-01-03 | 01 | 1 | INST-06 | integration | `./tests/bats/bin/bats tests/installer.bats -f "copies"` | No -- Wave 0 | pending |
| 15-01-04 | 01 | 1 | INST-05 | unit | `./tests/bats/bin/bats tests/installer.bats -f "config"` | No -- Wave 0 | pending |
| 15-01-05 | 01 | 1 | INST-04 | integration | `./tests/bats/bin/bats tests/installer.bats -f "idempotent"` | No -- Wave 0 | pending |
| 15-01-06 | 01 | 1 | INST-07 | unit | `./tests/bats/bin/bats tests/installer.bats -f "verify"` | No -- Wave 0 | pending |
| 15-01-07 | 01 | 1 | INST-08 | integration | `./tests/bats/bin/bats tests/installer.bats -f "summary"` | No -- Wave 0 | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

- [ ] `tests/installer.bats` -- test file covering all INST-* requirements
- [ ] Test helpers for creating mock GSD projects in temp directories
- [ ] `install.sh` -- the installer script itself (does not exist yet)

*Wave 0 creates both the installer and its test file via TDD.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Colored output renders correctly in terminal | INST-08 | Color rendering is visual | Run `bash install.sh` in a real terminal and verify colors appear |
| Dry-run produces valid output after install | Success Criteria #4 | Requires full Claude Code environment | After install, run `/gsd:ralph execute-phase N --dry-run` in target repo |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
