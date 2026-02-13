# Roadmap: gsd-ralph

## Overview

gsd-ralph delivers a CLI tool that bridges GSD structured planning with Ralph autonomous execution. The roadmap moves from project initialization and CLI scaffolding, through prompt generation and worktree-based execution, to merge orchestration and cleanup -- each phase delivering a complete, testable CLI command. By Phase 5, a user can run the full lifecycle: init, execute, merge, cleanup.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Project Initialization** - CLI scaffolding, dependency validation, and project type detection
- [ ] **Phase 2: Prompt Generation** - Template system that produces PROMPT.md, fix_plan.md, and .ralphrc from GSD plans
- [ ] **Phase 3: Phase Execution** - Worktree creation, peer visibility, Ralph launch instructions, and completion notifications
- [ ] **Phase 4: Merge Orchestration** - Auto-merge in plan order with review mode, conflict handling, and rollback safety
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
- [ ] 01-01-PLAN.md -- CLI skeleton, shared libraries, and bats-core test infrastructure
- [ ] 01-02-PLAN.md -- Init command implementation with integration tests

### Phase 2: Prompt Generation
**Goal**: Tool can parse GSD plans and generate complete, correct per-worktree files from templates
**Depends on**: Phase 1
**Requirements**: EXEC-02, EXEC-03, EXEC-04, EXEC-07
**Success Criteria** (what must be TRUE):
  1. Tool generates a context-specific PROMPT.md for each plan that includes project context, plan-specific tasks, and conventions
  2. Tool extracts tasks from GSD XML plan format into a correctly structured fix_plan.md with checkable items
  3. Tool generates a .ralphrc per worktree with project-specific configuration (test command, build tool, working directory)
  4. Tool handles both PLAN.md and NN-MM-PLAN.md naming conventions without errors
**Plans**: TBD

Plans:
- [ ] 02-01: TBD
- [ ] 02-02: TBD

### Phase 3: Phase Execution
**Goal**: User can execute a full GSD phase by creating isolated worktrees with generated prompts and peer visibility
**Depends on**: Phase 2
**Requirements**: EXEC-01, EXEC-05, EXEC-06, PEER-01, PEER-02
**Success Criteria** (what must be TRUE):
  1. User can run `gsd-ralph execute N` and get one git worktree per plan for that phase, each with generated PROMPT.md, fix_plan.md, and .ralphrc
  2. User receives clear instructions for launching Ralph in each created worktree
  3. Each Ralph instance has full read access to peer worktree contents (source, status, fix_plan) via paths included in its PROMPT.md
  4. User hears a terminal bell when all plans complete or any plan fails
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

### Phase 4: Merge Orchestration
**Goal**: User can merge all completed branches for a phase with safety guarantees and conflict resolution
**Depends on**: Phase 3
**Requirements**: MERG-01, MERG-02, MERG-03, MERG-04, MERG-05
**Success Criteria** (what must be TRUE):
  1. User can run `gsd-ralph merge N` and all completed branches for the phase are merged into main in plan order
  2. User can run `gsd-ralph merge N --review` to see a diff for each branch and approve or skip before merging
  3. When a merge conflict occurs, the user sees clear guidance on which files conflict and how to resolve them
  4. Conflicts in .planning/ files are auto-resolved by preferring main's version
  5. Pre-merge commit hash is saved and user can rollback if a merge goes wrong
**Plans**: TBD

Plans:
- [ ] 04-01: TBD
- [ ] 04-02: TBD

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
| 1. Project Initialization | 0/2 | Planned | - |
| 2. Prompt Generation | 0/TBD | Not started | - |
| 3. Phase Execution | 0/TBD | Not started | - |
| 4. Merge Orchestration | 0/TBD | Not started | - |
| 5. Cleanup | 0/TBD | Not started | - |
