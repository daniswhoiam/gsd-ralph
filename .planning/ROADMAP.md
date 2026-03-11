# Roadmap: gsd-ralph

## Milestones

- ✅ **v1.0 MVP** -- Phases 1-6 (shipped 2026-02-19)
- ✅ **v1.1 Stability & Safety** -- Phases 7-9 (shipped 2026-02-23)
- ✅ **v2.0 Autopilot Core** -- Phases 10-13 (shipped 2026-03-10)
- ✅ **v2.1 Easy Install** -- Phases 14-16 (shipped 2026-03-10)
- ⏸️ **v2.2 Ralph Visibility** -- Phases 17-19 (deferred to v2.3)
- 🚧 **v2.2 Execution Mode Benchmarking Suite** -- Phases 20-24 (in progress)

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

<details>
<summary>⏸️ v2.2 Ralph Visibility (Phases 17-19) -- DEFERRED to v2.3</summary>

- [ ] Phase 17: Tmux Pane Integration (0/0 plans)
- [ ] Phase 18: Control Terminal Status and Resilience (0/0 plans)
- [ ] Phase 19: iTerm2 Native Panes (0/0 plans)

Deferred to capture clean benchmark baseline before tmux launcher changes.

</details>

### v2.2 Execution Mode Benchmarking Suite (In Progress)

**Milestone Goal:** Build an automated benchmarking suite that runs standardized software engineering challenges across all 4 execution modes, captures structured metrics, and produces a comparison report.

- [ ] **Phase 20: Challenge Project** - Build the taskctl Bash CLI with planted defects, partial tests, and baseline git tag
- [ ] **Phase 21: Correctness Checks and Challenge Definitions** - Create behavioral evaluation logic, reference solutions, declarative challenge configs, and the after-delete tag
- [ ] **Phase 22: Harness Core and CC Mode** - Build the end-to-end benchmark pipeline (reset, run, eval, result JSON) validated with CC mode
- [ ] **Phase 23: Remaining Execution Modes** - Implement GSD, Ralph, and gsd-ralph mode invocation scripts behind the mode abstraction layer
- [ ] **Phase 24: Report Generator and Full Benchmark Runs** - Aggregate results into comparison report, calibrate via pilot runs, then execute the full matrix

## Phase Details

### Phase 20: Challenge Project
**Goal**: A standalone Bash CLI project exists at a known git state that serves as the foundation for all benchmark challenges
**Depends on**: Nothing (first phase of milestone)
**Requirements**: CHAL-01, CHAL-02, CHAL-03, CHAL-04
**Success Criteria** (what must be TRUE):
  1. Running `taskctl add "buy milk"` followed by `taskctl list` shows the added task in `benchmarks/taskctl/`
  2. Running `taskctl done <id>` marks the WRONG task as done (planted bug in done.sh is observable)
  3. Bats tests for add and list pass, while no tests exist for done.sh or storage.sh
  4. `format.sh` contains genuine code smells (long functions, duplicated logic, poor variable names) that a refactoring tool would meaningfully improve
  5. `git tag -l 'bench/baseline'` returns the tag, and checking out that tag restores the exact challenge starting state
**Plans**: 2 plans

Plans:
- [ ] 20-01-PLAN.md -- Build taskctl CLI source code with storage, commands, planted bug, and code smells
- [ ] 20-02-PLAN.md -- Create Bats tests for add/list, documentation, and bench/baseline git tag

### Phase 21: Correctness Checks and Challenge Definitions
**Goal**: Evaluation infrastructure is validated before any automated benchmark runs, ensuring correctness checks reliably distinguish passing from failing solutions
**Depends on**: Phase 20
**Requirements**: CHAL-05, CHAL-06, HARN-03, HARN-05
**Success Criteria** (what must be TRUE):
  1. Each of the 5 challenge correctness checks FAILS when run against the `bench/baseline` state (negative control)
  2. Each of the 5 challenge correctness checks PASSES when run against its reference solution (positive control)
  3. `bench/after-delete` git tag exists and checking it out shows a working delete command (Challenge 5 starting state)
  4. Each challenge has a declarative JSON definition file containing prompt text, starting tag, time cap, and check script reference
**Plans**: TBD

Plans:
- [ ] 21-01: TBD
- [ ] 21-02: TBD

### Phase 22: Harness Core and CC Mode
**Goal**: The full benchmark pipeline runs end-to-end for a single mode (CC), producing valid structured result JSON files that prove the architecture works before scaling to additional modes
**Depends on**: Phase 21
**Requirements**: HARN-01, HARN-02, HARN-04, HARN-06, HARN-07, MODE-01, METR-01, STAT-03
**Success Criteria** (what must be TRUE):
  1. Running `bench-run.sh --mode cc --challenge fix-bug` produces a JSON result file in `benchmarks/results/` with wall-clock time, token counts, correctness score, and reproducible identity fields
  2. Each benchmark run executes in an isolated git worktree that is created fresh and cleaned with `git clean -fdx`
  3. Time caps terminate a run that exceeds the challenge limit, recording partial results rather than hanging indefinitely
  4. The mode abstraction layer (`lib/modes/cc.sh`) invokes `claude -p` with `--output-format json` and extracts metrics defensively with jq fallbacks
  5. A second run of the same challenge produces a separate result file with a distinct run_id, proving isolation between runs
**Plans**: TBD

Plans:
- [ ] 22-01: TBD
- [ ] 22-02: TBD
- [ ] 22-03: TBD

### Phase 23: Remaining Execution Modes
**Goal**: All 4 execution modes can be invoked through the harness with identical interfaces, each producing comparable result JSON
**Depends on**: Phase 22
**Requirements**: MODE-02, MODE-03, MODE-04
**Success Criteria** (what must be TRUE):
  1. Running `bench-run.sh --mode gsd --challenge fix-bug` produces a valid result JSON with CC+GSD methodology documentation noting its human-in-the-loop nature
  2. Running `bench-run.sh --mode ralph --challenge fix-bug` invokes `ralph-launcher.sh` with GSD scaffolding generated in the challenge worktree and produces a valid result JSON
  3. Running `bench-run.sh --mode gsd-ralph --challenge fix-bug` invokes the Agent tool-based `/gsd:ralph` in headless mode and produces a valid result JSON
  4. All mode scripts conform to the same function contract defined in Phase 22's mode abstraction layer
**Plans**: TBD

Plans:
- [ ] 23-01: TBD
- [ ] 23-02: TBD

### Phase 24: Report Generator and Full Benchmark Runs
**Goal**: A markdown comparison report shows how all 4 execution modes perform across all 5 challenges, backed by statistically valid data from pilot-calibrated full benchmark runs
**Depends on**: Phase 23
**Requirements**: METR-02, METR-03, METR-04, METR-05, METR-06, METR-07, METR-08, STAT-01, STAT-02
**Success Criteria** (what must be TRUE):
  1. Pilot runs (N=2 per mode/challenge) complete and their variance data determines final sample size N and calibrated time caps
  2. `bench-report.sh` generates a markdown table with modes as columns and challenges as rows, showing median correctness, token efficiency, and quality-adjusted speed per cell
  3. High-variance cells (coefficient of variation exceeding pilot-calibrated threshold) are flagged in the report rather than presented as reliable
  4. CC+GSD results appear in a separate methodology section, not in the main autonomous mode comparison table
  5. The report includes token efficiency (correctness/tokens*1000), pass^k reliability, quality-adjusted speed, and ShellCheck delta for Challenge 4
**Plans**: TBD

Plans:
- [ ] 24-01: TBD
- [ ] 24-02: TBD
- [ ] 24-03: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 20 -> 21 -> 22 -> 23 -> 24

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
| 17. Tmux Pane Integration | v2.3 | 0/0 | Deferred | - |
| 18. Control Terminal Status | v2.3 | 0/0 | Deferred | - |
| 19. iTerm2 Native Panes | v2.3 | 0/0 | Deferred | - |
| 20. Challenge Project | 1/2 | In Progress|  | - |
| 21. Correctness Checks and Challenge Definitions | v2.2 | 0/? | Not started | - |
| 22. Harness Core and CC Mode | v2.2 | 0/? | Not started | - |
| 23. Remaining Execution Modes | v2.2 | 0/? | Not started | - |
| 24. Report Generator and Full Benchmark Runs | v2.2 | 0/? | Not started | - |
