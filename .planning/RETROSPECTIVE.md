# Project Retrospective

*A living document updated after each milestone. Lessons feed forward into future planning.*

## Milestone: v2.0 — Autopilot Core

**Shipped:** 2026-03-10
**Phases:** 4 | **Plans:** 7 | **Commits:** 55

### What Was Built
- Complete architectural rewrite from standalone CLI (9,693 LOC) to thin GSD autopilot layer (831 LOC)
- `--ralph` flag transforms any GSD command into autonomous execution
- Defense-in-depth safety: circuit breaker, graceful stop, PreToolUse hook, audit logging
- Three permission tiers (default/auto-mode/yolo) mapping to Claude Code's native flags
- Loop execution engine with STATE.md completion detection and progress-aware retry

### What Worked
- TDD methodology (RED-GREEN) kept each plan focused and delivered working code quickly
- Phase-based execution with clear success criteria prevented scope creep
- Milestone audit after Phase 12 caught two real integration gaps (split audit log, unused config field) that Phase 13 closed
- Clean architectural boundary: gsd-ralph never parses .planning/ files, delegates to GSD
- Leveraging Claude Code native features (worktree, headless mode, hooks) eliminated ~9,000 LOC of custom infrastructure

### What Was Inefficient
- Seven SUMMARY.md files all missing `requirements-completed` frontmatter field — caught in audit but never fixed (documentation debt)
- REQUIREMENTS.md coverage count said "15" when it was actually 16 — stale after Phase 13 added the 16th
- Nyquist validation partial across all 4 phases — VALIDATION.md files exist but aren't fully compliant
- Some decisions duplicated in STATE.md (Phase 11 and Phase 11-01 entries saying the same thing)

### Patterns Established
- `jq == false` for JSON boolean handling in bash (not `//` operator which treats false as falsy)
- `export` env vars inside `run_loop()` not at script top level to avoid test contamination
- Trap-based cleanup lifecycle for multi-resource management (hooks, audit, settings)
- `settings.local.json` merge/unmerge pattern preserving existing content via jq
- GSD command file delegates to bash script for testability (`gsd/ralph.md` → `ralph-launcher.sh`)

### Key Lessons
1. Milestone audits pay for themselves — both gaps found by the audit would have been production bugs
2. 92% LOC reduction proves "thin integration layer" architecture was correct — don't build what the platform provides
3. Circuit breaker + graceful stop + hook denial = defense-in-depth that covers different failure modes
4. STATE.md snapshot comparison is a reliable, simple progress detection mechanism
5. PreToolUse hooks are powerful but require careful lifecycle management (install/remove/cleanup)

### Cost Observations
- Model mix: 100% opus (quality profile)
- Sessions: ~5 (planning, Phase 10-11, Phase 12, Phase 13, audit/archive)
- Notable: 2-day execution for complete rewrite is fast — GSD planning + TDD methodology + clear architecture = efficient delivery

---

## Milestone: v2.1 — Easy Install

**Shipped:** 2026-03-10
**Phases:** 3 | **Plans:** 4 | **Commits:** 30

### What Was Built
- RALPH_SCRIPTS_DIR auto-detection making all scripts location-independent via BASH_SOURCE
- Single-command `install.sh` with prerequisite detection, 6-file copy manifest, config merge
- Post-install verification and colored summary with next-step guidance
- 5 E2E scenario tests proving complete install-then-use workflows

### What Worked
- BASH_SOURCE symlink resolution pattern reused from `bin/gsd-ralph` — proven pattern, no invention needed
- TDD continued to deliver reliable code — all 356 tests green, 0 regressions
- Tight milestone scope (install only, no uninstall/upgrade) enabled same-day completion
- Phase 14 portability work made Phase 15 trivial — installer copies scripts verbatim, no patching
- cmp -s for idempotency was the right call — simple, POSIX, no hashing overhead

### What Was Inefficient
- Nyquist VALIDATION.md files not updated post-execution (same issue as v2.0 — pattern not established)
- Phase 16 plan specified `assert_output --partial "execute-phase"` but dry-run output doesn't contain that literal string — had to fix during execution
- Course/PDF generation was a tangent that didn't contribute to milestone delivery

### Patterns Established
- `RALPH_SCRIPTS_DIR` as the single env var controlling script resolution for the entire scripts subsystem
- `install_file()` pattern for idempotent file copy with executable flag and counters
- `check_prerequisites()` pattern collecting all failures before exit for better UX
- jq existence-check-then-merge for config modification without overwrite

### Key Lessons
1. Location-independent scripts are a prerequisite for any installer — Phase 14 before 15 was the right order
2. `cmp -s` comparison is better than checksums for idempotent file operations in Bash
3. Keeping installer scope tight (no uninstall/upgrade) made it shippable in hours not days
4. E2E tests that exercise the full chain (install → configure → use) catch integration issues unit tests miss

### Cost Observations
- Model mix: 100% opus (quality profile)
- Sessions: ~3 (planning/research, Phase 14-15 execution, Phase 16 + audit/archive)
- Notable: Fastest milestone — 1 day for 3 phases. Tight scope + reusable patterns = efficient delivery

---

## Cross-Milestone Trends

### Process Evolution

| Milestone | Commits | Phases | Key Change |
|-----------|---------|--------|------------|
| v1.0 | 78 | 6 | Initial CLI with full lifecycle |
| v1.1 | 37 | 3 | Safety hardening, 1-day sprint |
| v2.0 | 55 | 4 | Complete rewrite, 92% LOC reduction |
| v2.1 | 30 | 3 | Single-command installer, location-independent scripts |

### Cumulative Quality

| Milestone | Tests | LOC (impl) | Key Metric |
|-----------|-------|------------|------------|
| v1.0 | ~80 | 3,695 | 20/20 requirements |
| v1.1 | 211 | 9,693 | Safe deletion, auto-push |
| v2.0 | 315 | 831 | 16/16 requirements, defense-in-depth |
| v2.1 | 356 | ~1,100 | 11/11 requirements, single-command install |

### Top Lessons (Verified Across Milestones)

1. Milestone audits catch real bugs — v1.1 passed clean, v2.0 found 2 gaps, v2.1 passed clean (pattern: audit before archive)
2. TDD with clear success criteria delivers reliable, well-tested code across all four milestones
3. Architecture that leverages platform capabilities beats custom infrastructure (v2.0 proved, v2.1 extended)
4. Tight milestone scoping enables same-day delivery — v1.1 (1 day), v2.1 (1 day) both scoped aggressively
