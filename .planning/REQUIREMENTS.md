# Requirements: gsd-ralph

**Defined:** 2026-03-11
**Core Value:** Add `--ralph` to any GSD command and walk away -- Ralph drives, GSD works, code ships.

## v2.2 Requirements

Requirements for Execution Mode Benchmarking Suite milestone. Each maps to roadmap phases.

### Challenge Project

- [ ] **CHAL-01**: `taskctl` Bash CLI exists with add, list, done commands at `bench/baseline` git tag
- [ ] **CHAL-02**: `done.sh` contains a planted bug (marks wrong task) discoverable through testing
- [ ] **CHAL-03**: Partial test coverage exists (test_add.bats, test_list.bats) with no tests for done.sh or storage.sh
- [ ] **CHAL-04**: `format.sh` is messy and serves as a meaningful refactoring target
- [ ] **CHAL-05**: `bench/after-delete` git tag exists with working delete command (for Challenge 5)
- [ ] **CHAL-06**: Reference solutions exist for all 5 challenges as correctness check validation controls

### Harness Infrastructure

- [ ] **HARN-01**: `bench-reset.sh` creates isolated git worktree per run with `git clean -fdx` and checksum verification
- [ ] **HARN-02**: `bench-run.sh` orchestrates the full pipeline: reset -> scaffold -> invoke -> capture metrics -> eval -> write result JSON
- [ ] **HARN-03**: `bench-eval.sh` runs behavioral (not structural) correctness checks per challenge
- [ ] **HARN-04**: Mode abstraction layer (`lib/modes/*.sh`) provides identical function contracts across all modes
- [ ] **HARN-05**: Challenge definitions are declarative JSON files with prompt, starting tag, time cap, and check reference
- [ ] **HARN-06**: Time caps per challenge are enforced by the harness as safety valves
- [ ] **HARN-07**: Each run produces a structured JSON result file in `benchmarks/results/`

### Execution Modes

- [ ] **MODE-01**: CC mode invokes `claude -p` directly with `--output-format json`
- [ ] **MODE-02**: CC+GSD mode runs with GSD planning context as a human-in-the-loop methodology (N=1-2)
- [ ] **MODE-03**: CC+Ralph mode invokes `ralph-launcher.sh` with GSD scaffolding in the challenge worktree
- [ ] **MODE-04**: CC+gsd-ralph mode invokes the Agent tool-based `/gsd:ralph` in headless mode

### Metrics & Reporting

- [ ] **METR-01**: Wall-clock time, token counts (input + output), and correctness score captured per run
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
- [ ] **STAT-03**: Every result includes reproducible identity: run_id, model version, CLI version, git SHA

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
| CHAL-01 | TBD | Pending |
| CHAL-02 | TBD | Pending |
| CHAL-03 | TBD | Pending |
| CHAL-04 | TBD | Pending |
| CHAL-05 | TBD | Pending |
| CHAL-06 | TBD | Pending |
| HARN-01 | TBD | Pending |
| HARN-02 | TBD | Pending |
| HARN-03 | TBD | Pending |
| HARN-04 | TBD | Pending |
| HARN-05 | TBD | Pending |
| HARN-06 | TBD | Pending |
| HARN-07 | TBD | Pending |
| MODE-01 | TBD | Pending |
| MODE-02 | TBD | Pending |
| MODE-03 | TBD | Pending |
| MODE-04 | TBD | Pending |
| METR-01 | TBD | Pending |
| METR-02 | TBD | Pending |
| METR-03 | TBD | Pending |
| METR-04 | TBD | Pending |
| METR-05 | TBD | Pending |
| METR-06 | TBD | Pending |
| METR-07 | TBD | Pending |
| METR-08 | TBD | Pending |
| STAT-01 | TBD | Pending |
| STAT-02 | TBD | Pending |
| STAT-03 | TBD | Pending |

**Coverage:**
- v2.2 requirements: 28 total
- Mapped to phases: 0
- Unmapped: 28

---
*Requirements defined: 2026-03-11*
*Last updated: 2026-03-11 after initial definition*
