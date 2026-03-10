# Requirements: gsd-ralph

**Defined:** 2026-03-09
**Core Value:** Add `--ralph` to any GSD command and walk away -- Ralph drives, GSD works, code ships.

## v2.0 Requirements

Requirements for the Autopilot Core rewrite. Each maps to roadmap phases.

### Autopilot

- [x] **AUTO-01**: User can add `--ralph` to any GSD command to run it autonomously
- [x] **AUTO-02**: System loops fresh Claude Code instances (Ralph pattern), each picking up incomplete work from GSD state on disk
- [x] **AUTO-03**: System assembles GSD context (PROJECT.md, STATE.md, phase plans) into each iteration's prompt
- [x] **AUTO-04**: System injects autonomous behavior prompt that prevents AskUserQuestion and auto-approves checkpoints
- [x] **AUTO-05**: User can run `--dry-run` to preview the command without executing

### Permissions

- [x] **PERM-01**: Default mode uses `--allowedTools` with a scoped tool whitelist
- [x] **PERM-02**: User can opt into `--auto-mode` for Claude's risk-based auto-approval
- [x] **PERM-03**: User can opt into `--yolo` for `--dangerously-skip-permissions` full bypass

### Safety

- [x] **SAFE-01**: Each iteration runs in an isolated worktree via `--worktree`
- [x] **SAFE-02**: System enforces `--max-turns` ceiling per iteration
- [x] **SAFE-03**: Circuit breaker with wall-clock timeout and graceful stop mechanism
- [x] **SAFE-04**: PreToolUse hook blocks AskUserQuestion as defense-in-depth

### Observability

- [x] **OBSV-01**: System detects iteration completion/failure from exit code and output
- [x] **OBSV-02**: Terminal bell on loop completion or failure
- [x] **OBSV-03**: Real-time progress display by parsing stream-json output *(Deferred to v2.1 per user decision. Per-iteration summary satisfies v2.0 visibility intent)*
- [ ] **OBSV-04**: Auto-approved decisions logged to audit file for post-run review *(integration fix in Phase 13)*

## Future Requirements

Deferred to v2.1+. Tracked but not in current roadmap.

### Resilience

- **RESL-01**: Session resume on failure via `--resume` with persisted session_id
- **RESL-02**: Configurable max-turns per project in `.planning/config.json`

### Orchestration

- **ORCH-01**: Multi-phase orchestration (chain phase N completion into phase N+1)
- **ORCH-02**: Parallel plan execution within a phase via multiple worktrees
- **ORCH-03**: Intelligent AskUserQuestion response strategies (context-aware, requires Agent SDK)

### Compatibility

- **COMP-01**: GSD version compatibility check with warning on untested versions

## Out of Scope

| Feature | Reason |
|---------|--------|
| v1.x standalone CLI commands (init, generate, execute, merge, cleanup) | Superseded by GSD native commands |
| Custom worktree management | Claude Code handles this natively via `--worktree` |
| Custom LLM provider support | Coupled to Claude Code intentionally |
| GUI or web dashboard | CLI only, target users are terminal-native |
| Multi-repo support | Single git repo only |
| Using Ralph directly as dependency | Ralph is ~120 LOC with no extension points; implementing the pattern is cleaner |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| AUTO-01 | Phase 11 | Complete |
| AUTO-02 | Phase 11 | Complete |
| AUTO-03 | Phase 10 | Complete |
| AUTO-04 | Phase 10 | Complete |
| AUTO-05 | Phase 11 | Complete |
| PERM-01 | Phase 11 | Complete |
| PERM-02 | Phase 11 | Complete |
| PERM-03 | Phase 11 | Complete |
| SAFE-01 | Phase 11 | Complete |
| SAFE-02 | Phase 11 | Complete |
| SAFE-03 | Phase 12 | Complete |
| SAFE-04 | Phase 12 | Complete |
| OBSV-01 | Phase 11 | Complete |
| OBSV-02 | Phase 11 | Complete |
| OBSV-03 | Phase 12 | Complete |
| OBSV-04 | Phase 13 | Pending |

**Coverage:**
- v2.0 requirements: 16 total
- Mapped to phases: 16
- Complete: 15
- Unmapped: 0

---
*Requirements defined: 2026-03-09*
*Last updated: 2026-03-10 after Phase 12 Plan 02 completion*
