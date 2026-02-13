# Requirements: gsd-ralph

**Defined:** 2026-02-13
**Core Value:** One command takes a GSD-planned phase and produces merged, working code

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Initialization

- [ ] **INIT-01**: User can initialize Ralph integration in any GSD project with `gsd-ralph init`
- [ ] **INIT-02**: Tool validates required dependencies are available (git, jq, python3, ralph) with actionable error messages
- [ ] **INIT-03**: Tool auto-detects project type (language, test command, build tool) and configures accordingly

### Execution

- [ ] **EXEC-01**: User can create one git worktree per plan for a given phase with `gsd-ralph execute N`
- [ ] **EXEC-02**: Tool generates context-specific PROMPT.md per worktree from templates
- [ ] **EXEC-03**: Tool extracts tasks from GSD XML plan format into fix_plan.md per worktree
- [ ] **EXEC-04**: Tool generates .ralphrc per worktree with project-specific configuration
- [ ] **EXEC-05**: Tool provides clear instructions for launching Ralph in each worktree
- [ ] **EXEC-06**: Tool triggers terminal bell when all plans complete or any plan fails
- [ ] **EXEC-07**: Tool handles GSD dual naming conventions (PLAN.md and NN-MM-PLAN.md)

### Peer Visibility

- [ ] **PEER-01**: Ralph instances have full read access to peer worktree contents (source, status, fix_plan)
- [ ] **PEER-02**: Generated PROMPT.md includes peer worktree paths and instructions for cross-worktree reads

### Merge

- [ ] **MERG-01**: User can auto-merge all completed branches for a phase in plan order with `gsd-ralph merge N`
- [ ] **MERG-02**: User can review each branch diff before merging with `--review` flag
- [ ] **MERG-03**: Tool detects merge conflicts and provides clear resolution guidance
- [ ] **MERG-04**: Tool auto-resolves .planning/ conflicts (prefer main's version)
- [ ] **MERG-05**: Tool saves pre-merge commit hash and offers rollback on failure

### Cleanup

- [ ] **CLEN-01**: User can remove all worktrees and branches for a completed phase with `gsd-ralph cleanup N`
- [ ] **CLEN-02**: Tool only removes tracked worktrees (registry-driven, not glob-based)

### Cross-Cutting

- [ ] **XCUT-01**: Tool works with any GSD project regardless of tech stack

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Status Monitoring

- **STAT-01**: User can view color-coded status overview of all worktrees for a phase
- **STAT-02**: Tool detects stale/dead agents via heartbeat verification
- **STAT-03**: Tool tracks agent PIDs to verify processes are alive
- **STAT-04**: User can auto-refresh status display with watch mode (`--watch`)

### Enhanced Execution

- **EEXC-01**: Tool supports dry-run mode (`--dry-run`) showing what would happen without acting
- **EEXC-02**: Tool enforces dependency graph (refuses Phase N if Phase N-1 incomplete)
- **EEXC-03**: Tool shows progress percentage (checked items in fix_plan.md)

### Enhanced Merge

- **EMRG-01**: Tool runs test suite on each branch before merging (pre-merge test run)
- **EMRG-02**: Tool generates merge report showing overlapping files between branches

### Advanced Orchestration

- **ADVO-01**: Tool launches Ralph as background processes with PID management
- **ADVO-02**: User can resume/retry failed plans without touching completed worktrees
- **ADVO-03**: Tool auto-chains phases (`execute --continue` starts next phase when current completes)
- **ADVO-04**: Tool generates structured execution log (EXECUTION_LOG.md with timing, commits, issues)
- **ADVO-05**: Single-command full lifecycle (`execute --auto` composes execute + monitor + merge + cleanup)
- **ADVO-06**: Tool auto-updates STATE.md after merge to reflect phase completion

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| GSD plugin integration | Standalone tool first; integration deferred |
| GUI / web dashboard | Target users are terminal-native; CLI is the right interface |
| OS-level notifications (macOS Notification Center) | Terminal bell is sufficient; no extra deps |
| Custom notification channels (Slack, email) | Terminal only for simplicity |
| Custom LLM provider support | Coupled to Ralph + Claude Code intentionally |
| Interactive plan editing | GSD owns planning; gsd-ralph reads plans, doesn't edit them |
| Task-level parallelism within a plan | Plans execute sequentially; parallelism is at the plan level |
| Agent-to-agent write communication | One-way read visibility only; no cross-worktree writes |
| Plugin/extension system | Premature abstraction; build monolithically first |
| Git hosting integration (PR creation, CI triggers) | Scope ends at local merge; user pushes when satisfied |
| Multi-repo support | Single git repo only |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| INIT-01 | — | Pending |
| INIT-02 | — | Pending |
| INIT-03 | — | Pending |
| EXEC-01 | — | Pending |
| EXEC-02 | — | Pending |
| EXEC-03 | — | Pending |
| EXEC-04 | — | Pending |
| EXEC-05 | — | Pending |
| EXEC-06 | — | Pending |
| EXEC-07 | — | Pending |
| PEER-01 | — | Pending |
| PEER-02 | — | Pending |
| MERG-01 | — | Pending |
| MERG-02 | — | Pending |
| MERG-03 | — | Pending |
| MERG-04 | — | Pending |
| MERG-05 | — | Pending |
| CLEN-01 | — | Pending |
| CLEN-02 | — | Pending |
| XCUT-01 | — | Pending |

**Coverage:**
- v1 requirements: 20 total
- Mapped to phases: 0
- Unmapped: 20

---
*Requirements defined: 2026-02-13*
*Last updated: 2026-02-13 after initial definition*
