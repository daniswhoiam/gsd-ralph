---
phase: 11
slug: shell-launcher-and-headless-invocation
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-03-10
---

# Phase 11 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.13.0 (git submodule in `tests/bats/`) |
| **Config file** | `tests/bats/` submodule |
| **Quick run command** | `./tests/bats/bin/bats tests/<specific>.bats -x` |
| **Full suite command** | `./tests/bats/bin/bats tests/*.bats` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-permissions.bats`
- **After every plan wave:** Run `./tests/bats/bin/bats tests/*.bats`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 11-01-T1 | 01 | 1 | AUTO-01, AUTO-05, PERM-01, PERM-02, PERM-03, SAFE-01, SAFE-02 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-permissions.bats -x` | ❌ W0 | ⬜ pending |
| 11-01-T2 | 01 | 1 | AUTO-01 | smoke | `test -f .claude/commands/gsd/ralph.md && grep -q 'ARGUMENTS' .claude/commands/gsd/ralph.md` | ❌ W0 | ⬜ pending |
| 11-02-T1 | 02 | 2 | AUTO-02, OBSV-01, OBSV-02 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-permissions.bats -x` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/ralph-launcher.bats` — stubs for AUTO-01, AUTO-02, AUTO-05, SAFE-01, SAFE-02, OBSV-01, OBSV-02
- [ ] `tests/ralph-permissions.bats` — stubs for PERM-01, PERM-02, PERM-03
- [ ] `tests/test_helper/ralph-helpers.bash` — mock claude command, mock STATE.md progression

*Existing infrastructure (bats-core submodule, test_helper/) covers framework needs.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Headless worktree cleanup | SAFE-01 | Worktree lifecycle in headless mode is undocumented; needs empirical validation | Run `gsd:ralph execute-phase` on a test project, verify worktree is created and cleaned up |
| SKILL.md auto-loading in headless mode | AUTO-01 | Requires live `claude -p` execution | Verify SKILL.md rules appear in headless session behavior |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
