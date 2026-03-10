---
phase: 10
slug: core-architecture-and-autonomous-behavior
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-09
---

# Phase 10 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core 1.13.0 (git submodules in `tests/`) |
| **Config file** | `tests/bats/` submodule |
| **Quick run command** | `./tests/bats/bin/bats tests/<specific>.bats` |
| **Full suite command** | `make test` |
| **Estimated runtime** | ~5 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats tests/<relevant>.bats`
- **After every plan wave:** Run `make test`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 10 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | AUTO-04 | unit | `./tests/bats/bin/bats tests/skill-validation.bats` | ❌ W0 | ⬜ pending |
| 10-02-01 | 02 | 1 | CONFIG | unit | `./tests/bats/bin/bats tests/ralph-config.bats` | ❌ W0 | ⬜ pending |
| 10-03-01 | 03 | 1 | AUTO-03 | unit | `./tests/bats/bin/bats tests/context-assembly.bats` | ❌ W0 | ⬜ pending |
| 10-04-01 | 04 | 1 | ARCH | smoke | `test -f ARCHITECTURE.md && grep -q "NEVER" ARCHITECTURE.md` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/context-assembly.bats` — stubs for AUTO-03 (context assembly output format, error handling)
- [ ] `tests/skill-validation.bats` — stubs for AUTO-04 (SKILL.md content validation, frontmatter checks)
- [ ] `tests/ralph-config.bats` — covers config schema (valid/invalid config, unknown key warnings)
- [ ] `tests/test_helper/ralph-helpers.bash` — shared test fixtures (mock STATE.md, config.json)

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SKILL.md auto-loads in headless mode | AUTO-04 | Requires live `claude -p` execution | Run `claude -p "echo loaded" --append-system-prompt-file .claude/skills/gsd-ralph-autopilot/SKILL.md` and verify behavior |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 10s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
