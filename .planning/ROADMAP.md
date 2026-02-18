# Roadmap: gsd-ralph

## Overview

gsd-ralph delivers a CLI tool that bridges GSD structured planning with Ralph autonomous execution. The roadmap moves from project initialization and CLI scaffolding, through prompt generation and worktree-based execution, to merge orchestration and cleanup -- each phase delivering a complete, testable CLI command. By Phase 5, a user can run the full lifecycle: init, execute, merge, cleanup.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Project Initialization** - CLI scaffolding, dependency validation, and project type detection
- [ ] **Phase 2: Prompt Generation** - Template system that produces PROMPT.md, fix_plan.md, and .ralphrc from GSD plans
- [ ] **Phase 3: Phase Execution** - Dependency-aware worktree creation, wave scheduling, peer visibility, and completion notifications
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
- [ ] 02-01-PLAN.md -- Discovery module, parameterized templates, and test fixtures
- [ ] 02-02-PLAN.md -- File generation pipeline and generate subcommand

### Phase 3: Phase Execution
**Goal**: User can execute a full GSD phase by creating isolated worktrees with dependency-aware scheduling that maximizes parallel execution
**Depends on**: Phase 2
**Requirements**: EXEC-01, EXEC-05, EXEC-06, PEER-01, PEER-02, WAVE-01, WAVE-02, WAVE-03

**Lesson from Phase 1**: Plans 01-01 (wave 1) and 01-02 (wave 2, depends_on 01-01) were executed in parallel worktrees despite the dependency. Plan 01-02 rebuilt Plan 01-01's files independently, producing divergent implementations and 12 merge conflicts. Wave/dependency metadata exists in plan frontmatter but was not enforced at execution time. The execution model must respect `wave` and `depends_on` while maximizing parallelism.

**Success Criteria** (what must be TRUE):
  1. User can run `gsd-ralph execute N` and get one git worktree per plan for that phase, each with generated PROMPT.md, fix_plan.md, and .ralphrc
  2. User receives clear instructions for launching Ralph in each created worktree
  3. Each Ralph instance has full read access to peer worktree contents (source, status, fix_plan) via paths included in its PROMPT.md
  4. User hears a terminal bell when all plans complete or any plan fails
  5. Execute reads `wave` and `depends_on` from plan frontmatter and builds a dependency graph
  6. Wave 1 plans launch immediately; later-wave plans launch only after their specific dependencies (not all prior waves) have completed and merged
  7. Each later-wave worktree is created from the post-merge main (containing dependency outputs), so agents never need to rebuild what a dependency already produced
  8. A dependency manifest is generated per worktree listing what upstream plans provide (from `files_modified` and `artifacts` in plan frontmatter), so agents understand what's already available vs. what they build
**Plans**: TBD

Plans:
- [ ] 03-01: TBD
- [ ] 03-02: TBD

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
| 1. Project Initialization | 2/2 | Complete | 2026-02-13 |
| 2. Prompt Generation | 0/2 | Ready | - |
| 3. Phase Execution | 0/TBD | Not started | - |
| 4. Merge Orchestration | 0/TBD | Not started | - |
| 5. Cleanup | 0/TBD | Not started | - |
