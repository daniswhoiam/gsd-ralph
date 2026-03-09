# Roadmap: gsd-ralph

## Milestones

- v1.0 MVP -- Phases 1-6 (shipped 2026-02-19)
- v1.1 Stability & Safety -- Phases 7-9 (shipped 2026-02-23)
- v2.0 Autopilot Core -- Phases 10-12 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (10.1, 10.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>v1.0 MVP (Phases 1-6) -- SHIPPED 2026-02-19</summary>

- [x] Phase 1: Project Initialization (2/2 plans) -- completed 2026-02-13
- [x] Phase 2: Prompt Generation (2/2 plans) -- completed 2026-02-18
- [x] Phase 3: Phase Execution (2/2 plans) -- completed 2026-02-18
- [x] Phase 4: Merge Orchestration (3/3 plans) -- completed 2026-02-19
- [x] Phase 5: Cleanup (2/2 plans) -- completed 2026-02-19
- [x] Phase 6: v1 Gap Closure (2/2 plans) -- completed 2026-02-19

</details>

<details>
<summary>v1.1 Stability & Safety (Phases 7-9) -- SHIPPED 2026-02-23</summary>

- [x] Phase 7: Safety Guardrails (4/4 plans) -- completed 2026-02-23
- [x] Phase 8: Auto-Push & Merge UX (3/3 plans) -- completed 2026-02-23
- [x] Phase 9: CLI Guidance (2/2 plans) -- completed 2026-02-23

</details>

### v2.0 Autopilot Core (In Progress)

**Milestone Goal:** Complete rewrite from standalone CLI to thin GSD autopilot layer (~200-400 LOC). Add `--ralph` to any GSD command and walk away.

- [ ] **Phase 10: Core Architecture and Autonomous Behavior** - Foundational artifacts that define what gsd-ralph does vs. what GSD/Claude Code do
- [ ] **Phase 11: Shell Launcher and Headless Invocation** - The working autopilot: `--ralph` flag, loop execution, permission tiers, worktree isolation
- [ ] **Phase 12: Defense-in-Depth and Observability** - Hardening with circuit breakers, AskUserQuestion denial hook, progress monitoring, audit logging

## Phase Details

### Phase 10: Core Architecture and Autonomous Behavior
**Goal**: The autonomous behavior rules and architectural boundaries exist as artifacts that all downstream components reference
**Depends on**: Nothing (first phase of v2.0)
**Requirements**: AUTO-03, AUTO-04
**Success Criteria** (what must be TRUE):
  1. A SKILL.md file exists that instructs Claude to never call AskUserQuestion, auto-approve checkpoints, and follow GSD conventions during autonomous execution
  2. The config schema in `.planning/config.json` includes Ralph-specific fields (enabled, allowed_tools, max_turns) that the launcher will read
  3. GSD context assembly logic exists that collects PROJECT.md, STATE.md, and phase plan content into a format suitable for `--append-system-prompt` or `@file` injection
  4. The architectural boundary is documented: gsd-ralph NEVER parses `.planning/` files directly or replicates GSD logic
**Plans:** 2 plans

Plans:
- [ ] 10-01-PLAN.md -- SKILL.md autonomous behavior rules + config schema extension with validation
- [ ] 10-02-PLAN.md -- Context assembly script + architectural boundary documentation

### Phase 11: Shell Launcher and Headless Invocation
**Goal**: User can add `--ralph` to any GSD command and get autonomous execution with permission control, worktree isolation, and loop-based completion
**Depends on**: Phase 10
**Requirements**: AUTO-01, AUTO-02, AUTO-05, PERM-01, PERM-02, PERM-03, SAFE-01, SAFE-02, OBSV-01, OBSV-02
**Success Criteria** (what must be TRUE):
  1. User runs `gsd-ralph --ralph "/gsd:execute-phase 10"` and a headless Claude Code instance launches in an isolated worktree, executes the GSD command autonomously, and returns
  2. When an iteration completes or fails, the system detects the outcome from exit code and JSON output, and either launches a fresh instance to continue incomplete work or stops with a terminal bell notification
  3. User can choose between three permission tiers: default `--allowedTools` whitelist, `--auto-mode` for Claude risk reasoning, or `--yolo` for full bypass -- each resulting in the correct Claude Code flags
  4. User runs `--dry-run` and sees the exact `claude -p` command that would be launched, without executing it
  5. Each iteration runs with a `--max-turns` ceiling to prevent unbounded execution
**Plans**: TBD

### Phase 12: Defense-in-Depth and Observability
**Goal**: The autopilot is hardened against runaway execution and provides real-time visibility into what is happening during autonomous runs
**Depends on**: Phase 11
**Requirements**: SAFE-03, SAFE-04, OBSV-03, OBSV-04
**Success Criteria** (what must be TRUE):
  1. A wall-clock timeout circuit breaker stops execution after a configurable duration, with a graceful stop mechanism (e.g., `.ralph/.stop` file) that the user can trigger manually
  2. A PreToolUse hook denies AskUserQuestion calls as defense-in-depth, providing guidance feedback to the Claude instance instead of silently failing
  3. User can observe real-time progress during an autonomous run by parsing `stream-json` output (iteration count, current activity, elapsed time)
  4. All auto-approved decisions are logged to an audit file that the user can review after the run completes
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 10 -> 11 -> 12

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Project Initialization | v1.0 | 2/2 | Complete | 2026-02-13 |
| 2. Prompt Generation | v1.0 | 2/2 | Complete | 2026-02-18 |
| 3. Phase Execution | v1.0 | 2/2 | Complete | 2026-02-18 |
| 4. Merge Orchestration | v1.0 | 3/3 | Complete | 2026-02-19 |
| 5. Cleanup | v1.0 | 2/2 | Complete | 2026-02-19 |
| 6. v1 Gap Closure | v1.0 | 2/2 | Complete | 2026-02-19 |
| 7. Safety Guardrails | v1.1 | 4/4 | Complete | 2026-02-23 |
| 8. Auto-Push & Merge UX | v1.1 | 3/3 | Complete | 2026-02-23 |
| 9. CLI Guidance | v1.1 | 2/2 | Complete | 2026-02-23 |
| 10. Core Architecture and Autonomous Behavior | v2.0 | 0/2 | Planning | - |
| 11. Shell Launcher and Headless Invocation | v2.0 | 0/TBD | Not started | - |
| 12. Defense-in-Depth and Observability | v2.0 | 0/TBD | Not started | - |
