# Milestones

## v1.0 MVP (Shipped: 2026-02-19)

**Phases completed:** 6 phases, 13 plans
**Timeline:** 7 days (Feb 13 - Feb 19, 2026)
**Git range:** 56b3ea7..c888f07 (78 commits)
**Codebase:** 3,695 LOC Bash + 2,533 LOC Bats tests

**Key accomplishments:**
1. Delivered `gsd-ralph init` with dependency checking and project type auto-detection
2. Delivered `gsd-ralph generate N` producing per-plan PROMPT.md, fix_plan.md, and AGENT.md
3. Delivered `gsd-ralph execute N` creating branch, protocol PROMPT.md, and combined fix_plan for Ralph
4. Delivered `gsd-ralph merge N` with dry-run conflict detection, review mode, and wave signaling
5. Delivered `gsd-ralph cleanup N` with registry-driven worktree and branch removal
6. Closed all v1 gaps: terminal bell, retroactive verification, requirements cleanup, tech debt

**Delivered:** Complete CLI lifecycle (init, generate, execute, merge, cleanup) bridging GSD planning with Ralph autonomous execution. 20/20 v1 requirements satisfied.

**Archives:** `milestones/v1.0-ROADMAP.md`, `milestones/v1.0-REQUIREMENTS.md`

---


## v1.1 Stability & Safety (Shipped: 2026-02-23)

**Phases completed:** 3 phases, 9 plans, 17 tasks
**Timeline:** 1 day (Feb 23, 2026, ~3 hours)
**Git range:** 9ec5d27..ebf959a (17 implementation commits + 20 docs commits)
**Codebase:** 9,693 LOC total (49 files changed, +5,827 / -81)
**Test suite:** 211 tests (21 new)

**Key accomplishments:**
1. Centralized `safe_remove()` guard eliminating the data-loss bug — all file deletions routed through safety checks blocking /, HOME, git toplevel
2. `__MAIN_WORKTREE__` sentinel preventing cleanup from ever registering project root as removable
3. Auto-push to remote after execute and merge (non-fatal, configurable via `.ralphrc`)
4. Auto-switch to main and auto-stash/restore dirty worktree during merge
5. Context-sensitive CLI guidance at all command exit points (17 guidance calls across 7 files)
6. 211-test suite covering all safety, push, merge UX, and guidance features

**Delivered:** Safety guardrails, auto-push, merge UX improvements, and CLI guidance — making gsd-ralph safe and smooth for first-time users. 13/13 v1.1 requirements satisfied. Audit passed with zero critical gaps.

**Archives:** `milestones/v1.1-ROADMAP.md`, `milestones/v1.1-REQUIREMENTS.md`, `milestones/v1.1-MILESTONE-AUDIT.md`

---

