# Phase 4: Merge Orchestration - Context

**Gathered:** 2026-02-19
**Status:** Ready for planning

<domain>
## Phase Boundary

CLI command (`gsd-ralph merge N`) that merges completed execution branches back into main with safety guarantees, conflict handling, rollback capability, and wave-aware sequencing. Merge exists as a standalone command AND is called automatically by execute when a plan completes. Sequential mode only for now — parallel worktree merge support is deferred.

</domain>

<decisions>
## Implementation Decisions

### Conflict resolution flow
- Merges are automated by Ralph as part of the execution loop — minimal human involvement
- Conflict resolution strategy should be informed by best practices from research
- When a real conflict can't be auto-resolved, skip that branch and continue with remaining plans
- Report unmerged branches at the end with clear information about what conflicted
- Auto-resolve .planning/ file conflicts by preferring main's version
- Also auto-resolve common generated files (lock files, build artifacts, .gitignore) — anything typically regenerated

### Review mode experience
- Review is post-merge, not pre-merge — show a summary of what was merged after completion
- Default: summary table showing each branch status (merged/skipped/conflicted), files changed count, commit count
- Optional flag to also show full git diffs for each merged branch
- No interactive approval flow — merges are automatic

### Rollback behavior
- Always save rollback point — every merge saves the pre-merge SHA automatically
- Rollback scope, invocation method, and expiry are Claude's discretion based on research

### Wave merge signaling
- Ralph should understand to proceed to wave N+1 after merging wave N — seamless within the execution loop
- Follow GSD's dependency-driven execution model for wave transitions
- The specific signaling mechanism is Claude's discretion based on research
- After successful merge of all branches for a phase, auto-update STATE.md and ROADMAP.md to mark phase complete

### Post-merge testing
- Always run the project's test suite after merging
- Do NOT stop the flow if regressions existed before this phase/wave — only halt on regressions introduced by the merged code

### Standalone command
- `gsd-ralph merge N` exists as its own command
- Execute always calls merge when a plan completes (opt-out may come in a later version)
- Manual invocation merges completed branches for the phase

### Claude's Discretion
- Merge timing (per-branch immediate vs per-wave batch)
- Manual merge: whether to merge all completed branches or allow picking
- Rollback scope (entire phase vs per-branch)
- Rollback invocation (subcommand flag vs separate command)
- Rollback expiry conditions
- Wave signaling mechanism (file-based, direct invocation, or other)

</decisions>

<specifics>
## Specific Ideas

- "The whole point is to reduce human involvement" — merges should be as automated as possible
- Execute→merge→next-wave flow should be seamless, not requiring manual intervention between steps
- Test regressions should be evaluated intelligently — pre-existing failures should not block the merge flow

</specifics>

<deferred>
## Deferred Ideas

- Parallel worktree merge support — build when parallel execution mode is implemented
- Opt-out flag for automatic merge during execute — future version
- Pre-merge interactive approval flow — not needed given automated approach

</deferred>

---

*Phase: 04-merge-orchestration*
*Context gathered: 2026-02-19*
