---
phase: 23
slug: remaining-execution-modes
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-03-11
---

# Phase 23 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | Bats 1.13.0 (vendored at tests/bats/) + bash -n syntax checks |
| **Config file** | None (Bats uses CLI args) |
| **Quick run command** | `bash -n benchmarks/harness/lib/modes/{gsd,ralph,gsd-ralph}.sh` |
| **Full suite command** | `bash -n benchmarks/harness/lib/modes/*.sh` |
| **Estimated runtime** | ~1 second (syntax checks only; live execution requires API calls) |

---

## Sampling Rate

- **After every task commit:** Run `bash -n` on modified mode scripts
- **After every plan wave:** Run `bash -n benchmarks/harness/lib/modes/*.sh`
- **Before `/gsd:verify-work`:** Full syntax check must pass
- **Max feedback latency:** 1 second

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|-----------|-------------------|-------------|--------|
| 23-01-01 | 01 | 1 | MODE-02 | syntax + manual | `bash -n benchmarks/harness/lib/modes/gsd.sh` | N/A (new file) | pending |
| 23-01-02 | 01 | 1 | MODE-03 | syntax + manual | `bash -n benchmarks/harness/lib/modes/ralph.sh` | N/A (new file) | pending |
| 23-02-01 | 02 | 1 | MODE-04 | syntax + manual | `bash -n benchmarks/harness/lib/modes/gsd-ralph.sh` | N/A (new file) | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements. No new test framework setup needed. Syntax checks via `bash -n` are available immediately.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| GSD mode produces valid result JSON | MODE-02 | Requires Claude CLI with API key | `bash benchmarks/harness/bench-run.sh --mode gsd --challenge fix-bug` and verify JSON output in results/ |
| Ralph mode invokes ralph-launcher.sh | MODE-03 | Requires Claude CLI with API key and ralph-launcher.sh | `bash benchmarks/harness/bench-run.sh --mode ralph --challenge fix-bug` and verify JSON output |
| gsd-ralph mode runs with Agent tool | MODE-04 | Requires Claude CLI with API key | `bash benchmarks/harness/bench-run.sh --mode gsd-ralph --challenge fix-bug` and verify JSON output |
| All modes conform to mode_invoke contract | MODE-02/03/04 | Contract conformance verified by code review + live execution | Inspect each mode script for correct function signature and test via bench-run.sh |

---

## Validation Sign-Off

- [x] All tasks have automated verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 1s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
