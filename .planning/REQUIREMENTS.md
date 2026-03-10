# Requirements: gsd-ralph

**Defined:** 2026-03-10
**Core Value:** Add `--ralph` to any GSD command and walk away — Ralph drives, GSD works, code ships.

## v2.2 Requirements

Requirements for Ralph Visibility milestone. Each maps to roadmap phases.

### Tmux Visibility

- [ ] **TMUX-01**: Ralph launches Claude in a managed tmux pane with full streaming text output
- [ ] **TMUX-02**: User can watch Claude's tool calls, agent spawns, and file writes in the tmux pane
- [ ] **TMUX-03**: tmux pane is automatically created before iteration and cleaned up on completion/failure
- [ ] **TMUX-04**: When iTerm2 is detected, use native split panes instead of tmux sessions

### Control Terminal

- [ ] **CTRL-01**: Control terminal shows iteration count, elapsed time, and STATE.md snapshot between iterations
- [ ] **CTRL-02**: Loop engine, circuit breakers, and completion detection remain in the control terminal unchanged

### Resilience

- [ ] **RSLN-01**: When tmux is not available, fall back silently to current headless behavior with a warning
- [ ] **RSLN-02**: If the tmux pane is closed mid-execution, Ralph continues running without crashing

## Future Requirements

Deferred to v2.3+. Tracked but not in current roadmap.

### Stream-JSON Progress

- **STRM-01**: Parse Claude Code stream-json events for structured progress display
- **STRM-02**: Surface progress summaries in the control terminal (agent spawns, file writes, task counts)

### Other Deferred

- **ORCH-01**: Multi-phase orchestration (chain phase N → N+1)
- **RESM-01**: Session resume on failure via `--resume`
- **LIFE-01**: Uninstall/upgrade lifecycle (manifest-based removal, in-place upgrade)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Parallel plan execution via multiple worktrees | Complexity, defer to v2.3+ |
| Intelligent response strategies | Complexity, defer to v2.3+ |
| GUI or web dashboard | CLI only, target users are terminal-native |
| Custom LLM provider support | Coupled to Claude Code intentionally |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| TMUX-01 | — | Pending |
| TMUX-02 | — | Pending |
| TMUX-03 | — | Pending |
| TMUX-04 | — | Pending |
| CTRL-01 | — | Pending |
| CTRL-02 | — | Pending |
| RSLN-01 | — | Pending |
| RSLN-02 | — | Pending |

**Coverage:**
- v2.2 requirements: 8 total
- Mapped to phases: 0
- Unmapped: 8 ⚠️

---
*Requirements defined: 2026-03-10*
*Last updated: 2026-03-10 after initial definition*
