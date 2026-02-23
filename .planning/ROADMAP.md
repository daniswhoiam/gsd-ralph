# Roadmap: gsd-ralph

## Milestones

- v1.0 MVP -- Phases 1-6 (shipped 2026-02-19)
- v1.1 Stability & Safety -- Phases 7-9 (in progress)

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (7.1, 7.2): Urgent insertions (marked with INSERTED)

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

### v1.1 Stability & Safety

**Milestone Goal:** Make gsd-ralph safe and smooth for developers trying it out for the first time.

- [ ] **Phase 7: Safety Guardrails** - Eliminate the data-loss bug and harden all deletion paths
- [ ] **Phase 8: Auto-Push & Merge UX** - Back up branches to remote automatically and make merge work from any branch state
- [ ] **Phase 9: CLI Guidance** - Every command tells the user what to do next

## Phase Details

### Phase 7: Safety Guardrails
**Goal**: Cleanup command can never cause data loss
**Depends on**: Phase 6 (v1.0 complete)
**Requirements**: SAFE-01, SAFE-02, SAFE-03, SAFE-04
**Success Criteria** (what must be TRUE):
  1. `gsd-ralph cleanup N` never deletes the project root directory, even when the registry contains a path matching the git toplevel
  2. If `git worktree remove` fails, the cleanup command reports the error and exits without attempting `rm -rf` as fallback
  3. Running `gsd-ralph execute N` in sequential mode does not register the main working tree as a removable worktree in the registry
  4. Every file/directory deletion in the codebase routes through a safe_remove guard that refuses to remove HOME, /, or the git toplevel
**Plans:** 4 plans

Plans:
- [ ] 07-01-PLAN.md -- Safety foundation: safe_remove() guard and registry main-worktree guard
- [ ] 07-02-PLAN.md -- Remove rm-rf fallback, route all rm calls through safe_remove(), fix legacy scripts
- [ ] 07-03-PLAN.md -- Comprehensive tests for all safety guardrails
- [ ] 07-04-PLAN.md -- Gap closure: fix GSD_RALPH_HOME export in test helpers (24 test regressions)

### Phase 8: Auto-Push & Merge UX
**Goal**: Branches are automatically backed up to remote and merge works from any branch state
**Depends on**: Phase 7
**Requirements**: PUSH-01, PUSH-02, PUSH-03, PUSH-04, MRGX-01, MRGX-02, MRGX-03
**Success Criteria** (what must be TRUE):
  1. After `gsd-ralph execute N`, the phase branch is pushed to remote (if remote exists), with a warning (not crash) on push failure
  2. After `gsd-ralph merge N`, main is pushed to remote (if remote exists), with a warning (not crash) on push failure
  3. Running `gsd-ralph merge N` from a phase branch automatically switches to main and completes the merge without manual intervention
  4. Running `gsd-ralph merge N` with uncommitted changes auto-stashes before merge and restores the stash after completion (success or rollback)
  5. Auto-push can be disabled via .ralphrc configuration, and when disabled, no push attempts are made
**Plans**: TBD

### Phase 9: CLI Guidance
**Goal**: Every command tells the user what to do next
**Depends on**: Phase 8
**Requirements**: GUID-01, GUID-02
**Success Criteria** (what must be TRUE):
  1. After every command completes, the terminal output includes a clear next-step suggestion (e.g., "Next: gsd-ralph merge 3")
  2. The guidance is context-sensitive -- different suggestions appear based on command outcome (e.g., merge success vs rollback suggest different next steps)
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 7 -> 8 -> 9

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Project Initialization | v1.0 | 2/2 | Complete | 2026-02-13 |
| 2. Prompt Generation | v1.0 | 2/2 | Complete | 2026-02-18 |
| 3. Phase Execution | v1.0 | 2/2 | Complete | 2026-02-18 |
| 4. Merge Orchestration | v1.0 | 3/3 | Complete | 2026-02-19 |
| 5. Cleanup | v1.0 | 2/2 | Complete | 2026-02-19 |
| 6. v1 Gap Closure | v1.0 | 2/2 | Complete | 2026-02-19 |
| 7. Safety Guardrails | v1.1 | 0/3 | Planned | - |
| 8. Auto-Push & Merge UX | v1.1 | 0/TBD | Not started | - |
| 9. CLI Guidance | v1.1 | 0/TBD | Not started | - |
