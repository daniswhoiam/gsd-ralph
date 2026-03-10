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

## Cross-Milestone Trends

### Process Evolution

| Milestone | Commits | Phases | Key Change |
|-----------|---------|--------|------------|
| v1.0 | 78 | 6 | Initial CLI with full lifecycle |
| v1.1 | 37 | 3 | Safety hardening, 1-day sprint |
| v2.0 | 55 | 4 | Complete rewrite, 92% LOC reduction |

### Cumulative Quality

| Milestone | Tests | LOC (impl) | Key Metric |
|-----------|-------|------------|------------|
| v1.0 | ~80 | 3,695 | 20/20 requirements |
| v1.1 | 211 | 9,693 | Safe deletion, auto-push |
| v2.0 | 315 | 831 | 16/16 requirements, defense-in-depth |

### Top Lessons (Verified Across Milestones)

1. Milestone audits catch real bugs — v1.1 audit passed clean, v2.0 audit found 2 gaps that Phase 13 fixed
2. TDD with clear success criteria delivers reliable, well-tested code across all three milestones
3. Architecture that leverages platform capabilities beats custom infrastructure (v2.0 proved this definitively)
