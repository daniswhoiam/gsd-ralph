---
phase: 12
slug: defense-in-depth-and-observability
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-03-10
---

# Phase 12 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | bats-core (bundled in tests/test_helper/bats/) |
| **Config file** | none — existing infrastructure |
| **Quick run command** | `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats tests/ralph-config.bats` |
| **Full suite command** | `./tests/bats/bin/bats tests/` |
| **Estimated runtime** | ~10 seconds |

---

## Sampling Rate

- **After every task commit:** Run `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats tests/ralph-config.bats`
- **After every plan wave:** Run `./tests/bats/bin/bats tests/`
- **Before `/gsd:verify-work`:** Full suite must be green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 12-01-01 | 01 | 1 | SAFE-03 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "circuit_breaker"` | ❌ W0 | ⬜ pending |
| 12-01-02 | 01 | 1 | SAFE-03 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "graceful_stop"` | ❌ W0 | ⬜ pending |
| 12-01-03 | 01 | 1 | SAFE-03 | unit | `./tests/bats/bin/bats tests/ralph-config.bats -f "timeout"` | ❌ W0 | ⬜ pending |
| 12-01-04 | 01 | 1 | OBSV-03 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "progress"` | ❌ W0 | ⬜ pending |
| 12-01-05 | 01 | 1 | OBSV-04 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "audit_summary"` | ❌ W0 | ⬜ pending |
| 12-02-01 | 02 | 1 | SAFE-04 | unit | `./tests/bats/bin/bats tests/ralph-hook.bats -f "deny"` | ❌ W0 | ⬜ pending |
| 12-02-02 | 02 | 1 | SAFE-04 | unit | `./tests/bats/bin/bats tests/ralph-hook.bats -f "allow"` | ❌ W0 | ⬜ pending |
| 12-02-03 | 02 | 1 | SAFE-04 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "install_hook"` | ❌ W0 | ⬜ pending |
| 12-02-04 | 02 | 1 | SAFE-04 | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "remove_hook"` | ❌ W0 | ⬜ pending |
| 12-02-05 | 02 | 1 | OBSV-04 | unit | `./tests/bats/bin/bats tests/ralph-hook.bats -f "audit"` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `tests/ralph-hook.bats` — NEW file: covers SAFE-04 hook deny/allow/audit behaviors
- [ ] `tests/test_helper/ralph-helpers.bash` — add helpers: `create_mock_audit_log`, `create_mock_stop_file`, `create_mock_settings_local`
- [ ] Extend `tests/ralph-launcher.bats` — add circuit breaker, graceful stop, progress display, hook install/cleanup tests
- [ ] Extend `tests/ralph-config.bats` — add timeout_minutes validation tests

*Existing infrastructure covers framework setup. Wave 0 adds test stubs only.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| AskUserQuestion denied in live headless session | SAFE-04 | Requires actual Claude instance in headless mode | 1. Run `scripts/ralph-launcher.sh` against a phase that triggers AskUserQuestion. 2. Verify hook fires and question is blocked. 3. Check `.ralph/audit.log` for denial entry. |
| Circuit breaker terminates long autonomous run | SAFE-03 | Requires real wall-clock time passage | 1. Set `ralph.timeout_minutes` to 1. 2. Run launcher against a multi-iteration task. 3. Verify termination after ~1 minute with bell notification. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
