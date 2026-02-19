# Roadmap: gsd-ralph

## Overview

gsd-ralph delivers a CLI tool that bridges GSD structured planning with Ralph autonomous execution. The roadmap moves from project initialization and CLI scaffolding, through prompt generation and worktree-based execution, to merge orchestration and cleanup -- each phase delivering a complete, testable CLI command. By Phase 5, a user can run the full lifecycle: init, execute, merge, cleanup.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Project Initialization** - CLI scaffolding, dependency validation, and project type detection
- [x] **Phase 2: Prompt Generation** - Template system that produces PROMPT.md, fix_plan.md, and .ralphrc from GSD plans
- [x] **Phase 3: Phase Execution** - Sequential GSD-protocol execution with frontmatter parsing and strategy analysis
- [ ] **Phase 4: Merge Orchestration** - Wave-aware auto-merge with dry-run conflict detection, review mode, and rollback safety
- [ ] **Phase 5: Cleanup** - Registry-driven worktree and branch removal after phase completion

## Phase Details

### Phase 1: Project Initialization
**Goal**: User can initialize gsd-ralph in any GSD project and get a working configuration
**Depends on**: Nothing (first phase)
**Requirements**: INIT-01, INIT-02, INIT-03, XCUT-01
**Success Criteria** (what must be TRUE):
  1. User can run `gsd-ralph init` in any GSD project and get a .ralph/ configuration directory created with sensible defaults
  2. User sees clear, actionable error messages when required dependencies (git, jq, python3, ralph) are missing
  3. Tool auto-detects project language, test command, and build tool without manual configuration
  4. Tool works regardless of the project's tech stack (Node.js, Python, Rust, Go, etc.)
**Plans:** 2 plans

Plans:
- [x] 01-01-PLAN.md -- CLI skeleton, shared libraries, and bats-core test infrastructure
- [x] 01-02-PLAN.md -- Init command implementation with integration tests

### Phase 2: Prompt Generation
**Goal**: Tool can parse GSD plans and generate complete, correct per-worktree files from templates
**Depends on**: Phase 1
**Requirements**: EXEC-02, EXEC-03, EXEC-04, EXEC-07
**Success Criteria** (what must be TRUE):
  1. Tool generates a context-specific PROMPT.md for each plan that includes project context, plan-specific tasks, and conventions
  2. Tool extracts tasks from GSD XML plan format into a correctly structured fix_plan.md with checkable items
  3. Tool generates a .ralphrc per worktree with project-specific configuration (test command, build tool, working directory)
  4. Tool handles both PLAN.md and NN-MM-PLAN.md naming conventions without errors
**Plans:** 2 plans

Plans:
- [x] 02-01-PLAN.md -- Discovery module, parameterized templates, and test fixtures
- [x] 02-02-PLAN.md -- File generation pipeline and generate subcommand

### Phase 3: Phase Execution
**Goal**: User can run `gsd-ralph execute N` to create an execution environment where a GSD-disciplined Ralph autonomously completes all plans in a phase
**Depends on**: Phase 2
**Requirements**: EXEC-01 (adapted), EXEC-05, WAVE-01 (partial)
**Success Criteria** (what must be TRUE):
  1. User can run `gsd-ralph execute N` and get a git branch with GSD-protocol PROMPT.md, combined fix_plan.md, and execution log — ready for Ralph
  2. Execute command parses plan frontmatter and reports the phase's dependency structure (sequential vs parallel-capable)
  3. Execute command validates dependencies (no circular refs, no missing deps)
  4. Generated PROMPT.md contains the 7-step GSD Execution Protocol that Ralph follows autonomously
  5. Generated fix_plan.md groups tasks by plan with summary creation tasks
  6. Ralph can be launched on the branch and complete the phase following the protocol (verified by running Phase 3 itself this way)
**Plans:** 2/2 plans complete

Plans:
- [x] 03-01-PLAN.md -- Frontmatter parsing and execution strategy analysis
- [x] 03-02-PLAN.md -- Execute command with sequential mode and protocol PROMPT.md

### Phase 4: Merge Orchestration
**Goal**: User can merge all completed branches for a phase with safety guarantees, conflict prevention, and wave-aware triggering
**Depends on**: Phase 3
**Requirements**: MERG-01, MERG-02, MERG-03, MERG-04, MERG-05, MERG-06, MERG-07
**Success Criteria** (what must be TRUE):
  1. User can run `gsd-ralph merge N` and all completed branches for the phase are merged into main in plan order
  2. User can run `gsd-ralph merge N --review` to see a diff for each branch and approve or skip before merging
  3. When a merge conflict occurs, the user sees clear guidance on which files conflict and how to resolve them
  4. Conflicts in .planning/ files are auto-resolved by preferring main's version
  5. Pre-merge commit hash is saved and user can rollback if a merge goes wrong
  6. Pre-merge dry-run detects conflicts before attempting the real merge, so the user knows upfront which branches will conflict
  7. Wave-aware merge: when wave N branches are merged, the tool signals Phase 3's execution pipeline to unblock wave N+1 plans that depended on them
**Plans:** 3 plans

Plans:
- [ ] 04-01-PLAN.md -- Merge infrastructure modules (dry-run, rollback, auto-resolve) and command skeleton
- [ ] 04-02-PLAN.md -- Core merge pipeline with conflict handling, review output, and summary
- [ ] 04-03-PLAN.md -- Wave signaling, post-merge testing, state updates, and execute integration

### Phase 5: Cleanup
**Goal**: User can remove all worktrees and branches for a completed phase cleanly
**Depends on**: Phase 4
**Requirements**: CLEN-01, CLEN-02
**Success Criteria** (what must be TRUE):
  1. User can run `gsd-ralph cleanup N` and all worktrees and branches for the phase are removed
  2. Tool only removes worktrees it created (registry-driven, not glob-based), preventing accidental deletion of unrelated worktrees
**Plans**: TBD

Plans:
- [ ] 05-01: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Project Initialization | 2/2 | Complete | 2026-02-13 |
| 2. Prompt Generation | 2/2 | Complete | 2026-02-18 |
| 3. Phase Execution | 2/2 | Complete    | 2026-02-18 |
| 4. Merge Orchestration | 0/3 | Not started | - |
| 5. Cleanup | 0/TBD | Not started | - |
