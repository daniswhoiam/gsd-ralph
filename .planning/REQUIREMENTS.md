# Requirements: gsd-ralph

**Defined:** 2026-03-11
**Core Value:** Add `--ralph` to any GSD command and walk away -- Ralph drives, GSD works, code ships.

## v2.2 Requirements

Requirements for Execution Mode Benchmarking Suite milestone. Each maps to roadmap phases.

### Challenge Project

- [x] **CHAL-01**: `taskctl` Bash CLI exists with add, list, done commands at `bench/baseline` git tag
- [x] **CHAL-02**: `done.sh` contains a planted bug (marks wrong task) discoverable through testing
- [x] **CHAL-03**: Partial test coverage exists (test_add.bats, test_list.bats) with no tests for done.sh or storage.sh
- [x] **CHAL-04**: `format.sh` is messy and serves as a meaningful refactoring target
- [x] **CHAL-05**: `bench/after-delete` git tag exists with working delete command (for Challenge 5)
- [x] **CHAL-06**: Reference solutions exist for all 5 challenges as correctness check validation controls

### Harness Infrastructure

- [x] **HARN-01**: `bench-reset.sh` creates isolated git worktree per run with `git clean -fdx` and checksum verification
- [x] **HARN-02**: `bench-run.sh` orchestrates the full pipeline: reset -> scaffold -> invoke -> capture metrics -> eval -> write result JSON
- [x] **HARN-03**: `bench-eval.sh` runs behavioral (not structural) correctness checks per challenge
- [x] **HARN-04**: Mode abstraction layer (`lib/modes/*.sh`) provides identical function contracts across all modes
- [x] **HARN-05**: Challenge definitions are declarative JSON files with prompt, starting tag, time cap, and check reference
- [x] **HARN-06**: Time caps per challenge are enforced by the harness as safety valves
- [x] **HARN-07**: Each run produces a structured JSON result file in `benchmarks/results/`

### Execution Modes

- [x] **MODE-01**: CC mode invokes `claude -p` directly with `--output-format json`
- [ ] **MODE-02**: CC+GSD mode runs with GSD planning context as a human-in-the-loop methodology (N=1-2)
- [ ] **MODE-03**: CC+Ralph mode invokes `ralph-launcher.sh` with GSD scaffolding in the challenge worktree
- [ ] **MODE-04**: CC+gsd-ralph mode invokes the Agent tool-based `/gsd:ralph` in headless mode

### Metrics & Reporting

- [x] **METR-01**: Wall-clock time, turn count, cost (USD), and correctness score captured per run (token counts unavailable from `--output-format json`; `num_turns` and `total_cost_usd` serve as efficiency proxies)
- [ ] **METR-02**: Token efficiency metric computed as correctness / total_tokens * 1000
- [ ] **METR-03**: Pass^k reliability metric tracks whether ALL k runs achieve >= 80% correctness
- [ ] **METR-04**: Quality-adjusted speed computed as (correctness * regression_score) / wall_clock_seconds
- [ ] **METR-05**: ShellCheck warning delta captured for refactoring challenge (Challenge 4)
- [ ] **METR-06**: `bench-report.sh` generates markdown comparison table with mode x challenge matrix
- [ ] **METR-07**: Report uses median/IQR statistics with high-variance flagging for unreliable cells
- [ ] **METR-08**: CC+GSD results appear in a separate methodology section, not the main autonomous comparison

### Statistical Validity

- [ ] **STAT-01**: Pilot runs (N=2 per mode/challenge) calibrate time caps and variance thresholds before full matrix
- [ ] **STAT-02**: Final sample size N is determined from pilot variance data (minimum N=3, target N=5)
- [x] **STAT-03**: Every result includes reproducible identity: run_id, model version, CLI version, git SHA

## Future Requirements

Deferred to future milestones. Tracked but not in current roadmap.

### Additional Challenge Projects

- **CHAL-F01**: Challenge projects in other languages (Python, TypeScript)
- **CHAL-F02**: Larger codebase challenges (multi-module, 1000+ LOC)

### Longitudinal Tracking

- **LONG-01**: Cross-version benchmarking (gsd-ralph v2.2 vs v2.3+ comparison)
- **LONG-02**: Longitudinal tracking dashboard with historical trend visualization
- **LONG-03**: CI/CD automated benchmark scheduling

### Community

- **COMM-01**: Community-contributed challenge definitions
- **COMM-02**: Public benchmark result database

## Out of Scope

| Feature | Reason |
|---------|--------|
| Different LLM model comparison | Always Claude Opus; measures scaffolding, not models |
| GSD vs other planning frameworks | Out of scope; measures gsd-ralph modes only |
| Public blog post | Downstream deliverable, not part of this milestone |
| Performance optimization of gsd-ralph | Measures current state, does not optimize |
| Parallel challenge execution | Sequential for isolation and reproducibility |
| Ralph Visibility (tmux/iTerm2) | Deferred to v2.3 to capture clean baseline |
| CSV/JSON export formats for report | Defer to future; markdown report is primary deliverable |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| CHAL-01 | Phase 20 | Complete |
| CHAL-02 | Phase 20 | Complete |
| CHAL-03 | Phase 20 | Complete |
| CHAL-04 | Phase 20 | Complete |
| CHAL-05 | Phase 21 | Complete |
| CHAL-06 | Phase 21 | Complete |
| HARN-01 | Phase 22 | Complete |
| HARN-02 | Phase 22 | Complete |
| HARN-03 | Phase 21 | Complete |
| HARN-04 | Phase 22 | Complete |
| HARN-05 | Phase 21 | Complete |
| HARN-06 | Phase 22 | Complete |
| HARN-07 | Phase 22 | Complete |
| MODE-01 | Phase 22 | Complete |
| MODE-02 | Phase 23 | Pending |
| MODE-03 | Phase 23 | Pending |
| MODE-04 | Phase 23 | Pending |
| METR-01 | Phase 22 | Complete |
| METR-02 | Phase 24 | Pending |
| METR-03 | Phase 24 | Pending |
| METR-04 | Phase 24 | Pending |
| METR-05 | Phase 24 | Pending |
| METR-06 | Phase 24 | Pending |
| METR-07 | Phase 24 | Pending |
| METR-08 | Phase 24 | Pending |
| STAT-01 | Phase 24 | Pending |
| STAT-02 | Phase 24 | Pending |
| STAT-03 | Phase 22 | Complete |

**Coverage:**
- v2.2 requirements: 28 total
- Mapped to phases: 28
- Unmapped: 0

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after roadmap creation (traceability populated)*
