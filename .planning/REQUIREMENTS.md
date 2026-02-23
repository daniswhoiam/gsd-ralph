# Requirements: gsd-ralph

**Defined:** 2026-02-20
**Core Value:** One command takes a GSD-planned phase and produces merged, working code — no manual worktree setup, no hand-crafted prompts, no babysitting.

## v1.1 Requirements

Requirements for v1.1 Stability & Safety. Each maps to roadmap phases.

### Safety Guardrails

- [x] **SAFE-01**: Cleanup command never uses rm -rf as fallback for failed worktree removal
- [x] **SAFE-02**: All file/directory deletions go through a safe_remove() guard that refuses to remove git toplevel, HOME, or /
- [x] **SAFE-03**: Registry distinguishes worktree-mode vs in-place execution, preventing main working tree from being registered as removable
- [x] **SAFE-04**: All existing rm calls across the codebase are audited and routed through safe_remove()

### Auto-Push

- [ ] **PUSH-01**: Init detects whether a remote exists and records the result for downstream commands
- [ ] **PUSH-02**: Execute pushes the phase branch to remote after creation (non-fatal on failure)
- [ ] **PUSH-03**: Merge pushes main to remote after successful merge (non-fatal on failure)
- [ ] **PUSH-04**: Auto-push can be disabled via .ralphrc configuration

### Merge UX

- [ ] **MRGX-01**: Merge auto-detects the main branch and switches to it when run from a phase branch
- [ ] **MRGX-02**: Merge auto-stashes dirty worktree state before branch switch using apply+drop pattern
- [ ] **MRGX-03**: Auto-stash is restored after merge completes (success or rollback)

### CLI Guidance

- [ ] **GUID-01**: Every command outputs a next-step suggestion after completion
- [ ] **GUID-02**: Guidance is context-sensitive (accounts for current state, available next actions)

## Future Requirements

### Status Monitoring (deferred from v1.0)

- **STAT-01**: User can check execution progress of active phase
- **STAT-02**: User can see which plans are complete vs pending
- **STAT-03**: User can see merge readiness status
- **STAT-04**: User can see overall phase health

### Peer Visibility (deferred from v1.0)

- **PEER-01**: User can see what other branches/worktrees exist
- **PEER-02**: User can see cross-plan dependencies

## Out of Scope

| Feature | Reason |
|---------|--------|
| Interactive conflict resolution | Adds complexity; user should resolve manually with git tools |
| Force-push to remote | Dangerous; conflicts with safety-first philosophy |
| Auto-commit dirty changes | Violates user intent; only push what user explicitly committed |
| Auto-cleanup after merge | Cleanup bug must be fixed first; keep as explicit command |
| Multi-remote push | Single origin is sufficient; multi-remote adds edge cases |
| Trash/quarantine instead of delete | Disk usage grows unbounded; simple refusal to delete is safer |
| Verbosity tiers (--quiet/--verbose) | Premature; ship one good default first |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| SAFE-01 | Phase 7 | Complete |
| SAFE-02 | Phase 7 | Complete |
| SAFE-03 | Phase 7 | Complete |
| SAFE-04 | Phase 7 | Complete |
| PUSH-01 | Phase 8 | Pending |
| PUSH-02 | Phase 8 | Pending |
| PUSH-03 | Phase 8 | Pending |
| PUSH-04 | Phase 8 | Pending |
| MRGX-01 | Phase 8 | Pending |
| MRGX-02 | Phase 8 | Pending |
| MRGX-03 | Phase 8 | Pending |
| GUID-01 | Phase 9 | Pending |
| GUID-02 | Phase 9 | Pending |

**Coverage:**
- v1.1 requirements: 13 total
- Mapped to phases: 13
- Unmapped: 0

---
*Requirements defined: 2026-02-20*
*Last updated: 2026-02-20 after roadmap creation*
