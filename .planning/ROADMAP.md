# Roadmap: gsd-ralph

## Milestones

- v1.0 MVP -- Phases 1-6 (shipped 2026-02-19)
- v1.1 Stability & Safety -- Phases 7-9 (shipped 2026-02-23)
- v2.0 Autopilot Core -- Phases 10-13 (shipped 2026-03-10)
- v2.1 Easy Install -- Phases 14-16 (in progress)

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

<details>
<summary>v2.0 Autopilot Core (Phases 10-13) -- SHIPPED 2026-03-10</summary>

- [x] Phase 10: Core Architecture and Autonomous Behavior (2/2 plans) -- completed 2026-03-09
- [x] Phase 11: Shell Launcher and Headless Invocation (2/2 plans) -- completed 2026-03-10
- [x] Phase 12: Defense-in-Depth and Observability (2/2 plans) -- completed 2026-03-10
- [x] Phase 13: Audit Path Fix and Config Enforcement (1/1 plan) -- completed 2026-03-10

</details>

### v2.1 Easy Install (In Progress)

**Milestone Goal:** Make gsd-ralph installable in any repo with a single command following current Claude Code ecosystem patterns.

- [x] **Phase 14: Location-Independent Scripts** - Refactor all scripts to work from any directory, not just the dev repo layout (completed 2026-03-10)
- [x] **Phase 15: Core Installer** - Single-command installer with prerequisite detection, file copy, config merge, and verification (completed 2026-03-10)
- [ ] **Phase 16: End-to-End Validation** - Integration tests proving the full install-then-use workflow in realistic target repos

## Phase Details

### Phase 14: Location-Independent Scripts
**Goal**: Ralph scripts work correctly whether sourced from `scripts/` (dev repo) or `scripts/ralph/` (installed repo)
**Depends on**: Phase 13 (v2.0 complete)
**Requirements**: PORT-01, PORT-02, PORT-03
**Success Criteria** (what must be TRUE):
  1. Running ralph-launcher.sh from a repo where scripts live under `scripts/ralph/` works identically to running from the dev repo
  2. All script-to-script source/reference paths resolve through a `RALPH_SCRIPTS_DIR` variable, not hardcoded paths
  3. All 315 existing tests pass without modification after the refactor
  4. Setting `RALPH_SCRIPTS_DIR` to a custom path before invoking ralph causes scripts to load from that path
**Plans:** 1/1 plans complete

Plans:
- [x] 14-01-PLAN.md -- Add RALPH_SCRIPTS_DIR auto-detection, replace hardcoded paths, full regression

### Phase 15: Core Installer
**Goal**: User can install gsd-ralph into any GSD project with a single terminal command and have a working Ralph setup immediately
**Depends on**: Phase 14
**Requirements**: INST-01, INST-02, INST-03, INST-04, INST-05, INST-06, INST-07, INST-08
**Success Criteria** (what must be TRUE):
  1. User runs one command and gsd-ralph files appear in the target repo under `scripts/ralph/`, `.claude/commands/`, and `.claude/skills/`
  2. If GSD framework, jq, git, or bash >= 3.2 is missing, the installer exits early with a clear message explaining what to install and how
  3. Running the installer a second time in the same repo produces no changes and no errors (idempotent)
  4. After install, running `/gsd:ralph execute-phase N --dry-run` in the target repo produces valid output (full workflow functional)
  5. Installer prints colored summary with count of files installed and explicit next-step instructions
**Plans:** 2/2 plans complete

Plans:
- [ ] 15-01-PLAN.md -- TDD installer prerequisites, file copy manifest, path adjustment, and idempotency
- [ ] 15-02-PLAN.md -- TDD config merge, post-install verification, and summary output

### Phase 16: End-to-End Validation
**Goal**: Automated test suite proves the complete install-then-use workflow works in realistic target repos with varying initial states
**Depends on**: Phase 15
**Requirements**: (verification phase -- validates INST and PORT requirements in integration)
**Success Criteria** (what must be TRUE):
  1. Test suite covers fresh GSD project, project with existing `.claude/` config, and non-GSD repo (error path)
  2. Install-then-dry-run test confirms `/gsd:ralph execute-phase` works in an installed repo
  3. Re-install idempotency test confirms no file changes on second run
  4. All tests run in isolated temporary directories (no side effects on dev repo)
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 14 -> 15 -> 16

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
| 15. Core Installer | 2/2 | Complete   | 2026-03-10 | - |
| 16. End-to-End Validation | v2.1 | 0/? | Not started | - |
