# Roadmap: gsd-ralph

## Milestones

- ✅ **v1.0 MVP** -- Phases 1-6 (shipped 2026-02-19)
- ✅ **v1.1 Stability & Safety** -- Phases 7-9 (shipped 2026-02-23)
- ✅ **v2.0 Autopilot Core** -- Phases 10-13 (shipped 2026-03-10)
- ✅ **v2.1 Easy Install** -- Phases 14-16 (shipped 2026-03-10)
- 🚧 **v2.2 Ralph Visibility** -- Phases 17-19 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (10.1, 10.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

<details>
<summary>✅ v1.0 MVP (Phases 1-6) -- SHIPPED 2026-02-19</summary>

- [x] Phase 1: Project Initialization (2/2 plans) -- completed 2026-02-13
- [x] Phase 2: Prompt Generation (2/2 plans) -- completed 2026-02-18
- [x] Phase 3: Phase Execution (2/2 plans) -- completed 2026-02-18
- [x] Phase 4: Merge Orchestration (3/3 plans) -- completed 2026-02-19
- [x] Phase 5: Cleanup (2/2 plans) -- completed 2026-02-19
- [x] Phase 6: v1 Gap Closure (2/2 plans) -- completed 2026-02-19

</details>

<details>
<summary>✅ v1.1 Stability & Safety (Phases 7-9) -- SHIPPED 2026-02-23</summary>

- [x] Phase 7: Safety Guardrails (4/4 plans) -- completed 2026-02-23
- [x] Phase 8: Auto-Push & Merge UX (3/3 plans) -- completed 2026-02-23
- [x] Phase 9: CLI Guidance (2/2 plans) -- completed 2026-02-23

</details>

<details>
<summary>✅ v2.0 Autopilot Core (Phases 10-13) -- SHIPPED 2026-03-10</summary>

- [x] Phase 10: Core Architecture and Autonomous Behavior (2/2 plans) -- completed 2026-03-09
- [x] Phase 11: Shell Launcher and Headless Invocation (2/2 plans) -- completed 2026-03-10
- [x] Phase 12: Defense-in-Depth and Observability (2/2 plans) -- completed 2026-03-10
- [x] Phase 13: Audit Path Fix and Config Enforcement (1/1 plan) -- completed 2026-03-10

</details>

<details>
<summary>✅ v2.1 Easy Install (Phases 14-16) -- SHIPPED 2026-03-10</summary>

- [x] Phase 14: Location-Independent Scripts (1/1 plan) -- completed 2026-03-10
- [x] Phase 15: Core Installer (2/2 plans) -- completed 2026-03-10
- [x] Phase 16: End-to-End Validation (1/1 plan) -- completed 2026-03-10

</details>

### 🚧 v2.2 Ralph Visibility (In Progress)

**Milestone Goal:** Give Ralph operators real-time visibility into what Claude is doing via tmux panes, with graceful fallback when tmux is unavailable.

- [ ] **Phase 17: Tmux Pane Integration** - Launch Claude inside a managed tmux pane with streaming text output and automatic lifecycle management
- [ ] **Phase 18: Control Terminal Status and Resilience** - Status display between iterations and graceful degradation when tmux is missing or pane is lost
- [ ] **Phase 19: iTerm2 Native Panes** - Detect iTerm2 and use native split panes as an alternative to tmux sessions

## Phase Details

### Phase 17: Tmux Pane Integration
**Goal**: Operators can see exactly what Claude is doing in real time during Ralph execution
**Depends on**: Phase 16 (v2.1 complete)
**Requirements**: TMUX-01, TMUX-02, TMUX-03, CTRL-02
**Success Criteria** (what must be TRUE):
  1. Running `--ralph` with tmux available opens a visible pane where Claude's text output streams in real time
  2. Tool calls, agent spawns, and file writes are visible as they happen in the tmux pane
  3. The tmux pane is created automatically before the first iteration and cleaned up when Ralph completes or fails
  4. The existing loop engine, circuit breakers, and completion detection continue to work unchanged in the control terminal
  5. Claude runs via `claude -p --output-format text` inside the tmux pane, managed by the launcher
**Plans**: TBD

### Phase 18: Control Terminal Status and Resilience
**Goal**: Operators get useful status in the control terminal and Ralph never crashes due to missing or lost tmux infrastructure
**Depends on**: Phase 17
**Requirements**: CTRL-01, RSLN-01, RSLN-02
**Success Criteria** (what must be TRUE):
  1. Between iterations, the control terminal displays iteration count, elapsed time, and a STATE.md status snapshot
  2. When tmux is not installed or not available, Ralph falls back to current headless behavior (`--output-format json`) with a one-time warning
  3. If the tmux pane is killed or closed while Claude is running, Ralph detects this and continues the current iteration headlessly without crashing
**Plans**: TBD

### Phase 19: iTerm2 Native Panes
**Goal**: iTerm2 users get native split pane integration without requiring tmux
**Depends on**: Phase 17
**Requirements**: TMUX-04
**Success Criteria** (what must be TRUE):
  1. When running inside iTerm2, Ralph uses AppleScript-based native split panes instead of tmux sessions
  2. The iTerm2 pane provides the same streaming text visibility as the tmux pane
  3. When not in iTerm2 (or detection fails), Ralph falls through to tmux or headless behavior transparently
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 17 → 18 → 19

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
| 10. Core Architecture | v2.0 | 2/2 | Complete | 2026-03-09 |
| 11. Shell Launcher | v2.0 | 2/2 | Complete | 2026-03-10 |
| 12. Defense-in-Depth | v2.0 | 2/2 | Complete | 2026-03-10 |
| 13. Audit Path Fix | v2.0 | 1/1 | Complete | 2026-03-10 |
| 14. Location-Independent Scripts | v2.1 | 1/1 | Complete | 2026-03-10 |
| 15. Core Installer | v2.1 | 2/2 | Complete | 2026-03-10 |
| 16. End-to-End Validation | v2.1 | 1/1 | Complete | 2026-03-10 |
| 17. Tmux Pane Integration | v2.2 | 0/0 | Not started | - |
| 18. Control Terminal Status and Resilience | v2.2 | 0/0 | Not started | - |
| 19. iTerm2 Native Panes | v2.2 | 0/0 | Not started | - |
