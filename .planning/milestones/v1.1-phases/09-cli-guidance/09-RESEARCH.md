# Phase 9: CLI Guidance - Research

**Researched:** 2026-02-23
**Domain:** Bash CLI user experience / contextual output messaging
**Confidence:** HIGH

## Summary

Phase 9 adds contextual "what to do next" guidance to every gsd-ralph command exit point. This is a pure output-layer concern -- no new libraries, no new modules, no architectural changes. The work involves identifying every command exit path (success, partial success, failure, early-return), determining the context-appropriate next step for each, and adding a `print_guidance()` call at each location.

The codebase already has a partial precedent: `cmd_init` prints "Next steps:" with numbered instructions at completion (lines 100-103 of `lib/commands/init.sh`). Phase 9 formalizes and extends this pattern to all commands, making the guidance context-sensitive (different suggestions for merge success vs merge failure, for example).

**Primary recommendation:** Create a single `print_guidance()` helper in `lib/common.sh` that prints a visually distinct "Next:" line, then add calls at every command exit point with context-appropriate messages. No new files needed beyond the guidance helper and tests.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| GUID-01 | Every command outputs a next-step suggestion after completion | Exit path audit below identifies all 20+ exit points across 6 commands where guidance must be added |
| GUID-02 | Guidance is context-sensitive (accounts for current state, available next actions) | Exit path catalog maps each exit to its specific context and recommends the appropriate next-step message |
</phase_requirements>

## Standard Stack

### Core

No new libraries or dependencies required. This phase is implemented entirely with existing Bash infrastructure:

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| `print_guidance()` | `lib/common.sh` | Unified guidance output helper | Single formatting point; consistent visual treatment across all commands |
| `print_*()` functions | `lib/common.sh` | Existing output helpers | Already used by all commands; guidance extends this pattern |

### Supporting

None. No new dependencies.

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Single `print_guidance()` helper | Inline printf in each command | Inline approach duplicates formatting logic and makes visual changes harder; helper is better |
| Guidance at end of each command | Guidance library with state machine | Over-engineered for the scope; the exit paths are enumerable and static |

## Architecture Patterns

### Pattern 1: Guidance Helper Function

**What:** A `print_guidance()` function in `lib/common.sh` that formats the next-step message with a consistent visual prefix.

**When to use:** At every command exit point (success, partial success, failure, early-return).

**Example:**
```bash
# In lib/common.sh
print_guidance() {
    printf "\n${GREEN}  Next:${NC} %s\n" "$1"
}
```

**Rationale:** The `init` command already uses `print_info "Next steps:"` followed by raw `printf` lines. A dedicated helper standardizes this into a single-call pattern, making it easy to grep for coverage and consistent to read.

### Pattern 2: Inline Context-Sensitive Branching

**What:** Each command's exit logic already has the context available (success/failure, phase number, branch name, etc.) as local variables. Guidance messages use those variables directly -- no new state introspection needed.

**When to use:** At every branch of the command's exit flow.

**Example:**
```bash
# In merge success path:
if [[ $skip_count -eq 0 ]] && [[ $conflict_branch_count -eq 0 ]]; then
    print_guidance "Run: gsd-ralph cleanup $phase_num"
else
    print_guidance "Resolve conflicts, then re-run: gsd-ralph merge $phase_num"
fi
```

### Pattern 3: Replace init's Existing "Next Steps" Block

**What:** `cmd_init` (lines 100-103) already has hardcoded next-step output. Replace it with `print_guidance()` calls for consistency.

**Example:**
```bash
# Replace:
#   print_info "Next steps:"
#   printf "  1. Review .ralphrc configuration\n"
#   printf "  2. Plan your first phase with GSD\n"
#   printf "  3. Run: gsd-ralph execute 1\n"
# With:
print_guidance "Review .ralphrc, then run: gsd-ralph execute <phase>"
```

### Anti-Patterns to Avoid

- **Guidance that requires network or disk I/O to determine context:** The guidance should use only variables already in scope. Do not re-read STATE.md or query git to figure out what phase is next.
- **Multi-line guidance blocks:** Keep it to one line. The user needs a quick nudge, not a tutorial. The `init` command's 3-line block should be condensed.
- **Guidance on `--help` or `--version` exits:** These are informational lookups. Adding "Next:" after `--help` would be noise.
- **Guidance after `die()` calls:** `die()` calls `exit 1` for fatal errors. The error message itself is the guidance (fix the problem). Adding "Next:" after "Not inside a git repository" is redundant. However, `die()` messages that suggest a specific fix (like "Run 'gsd-ralph init' first") are already sufficient guidance.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Figuring out "what phase comes next" | Phase-graph introspection at runtime | Hardcoded suggestion with `<phase>` placeholder | The user knows which phase they're on; trying to auto-detect the next phase from ROADMAP.md is fragile and unnecessary |
| Terminal-width-aware formatting | Custom word-wrap logic | Fixed-width single-line messages | All messages fit in one line; wrapping is not needed |

**Key insight:** The guidance messages are static per exit path. The only dynamic parts are variables already in scope (phase number, branch name). There is zero need for runtime state introspection.

## Common Pitfalls

### Pitfall 1: Missing Exit Paths

**What goes wrong:** A command has 5 exit paths but only 3 get guidance. The user hits an ungoverned path and sees no next step.
**Why it happens:** Complex commands like `merge` have many branches (success, partial merge, all conflicts, dry-run, rollback, test failure). Easy to miss one.
**How to avoid:** Use the exhaustive exit path catalog below as a checklist. Every path in the catalog must have a corresponding `print_guidance()` call. Add a test that greps for "Next:" in every command's output.
**Warning signs:** A bats test for a command exits without "Next:" in the output.

### Pitfall 2: Guidance After die()

**What goes wrong:** Adding `print_guidance()` before `die()` -- but `die()` calls `exit 1`, which triggers the EXIT trap in some commands. The guidance appears twice or in wrong order.
**Why it happens:** `execute` sets `trap 'ring_bell' EXIT`. If guidance is added before die, the trap still fires.
**How to avoid:** Do NOT add guidance to `die()` call sites. The die message IS the guidance for fatal errors. Only add guidance to normal completion paths (`return 0`, `return 1`, or the natural end of the function).

### Pitfall 3: Guidance Printed After ring_bell()

**What goes wrong:** `ring_bell()` is the last user-visible action in execute and merge. If guidance prints before the bell, the bell rings after the guidance text, which is correct. But if guidance prints after `ring_bell()`, the visual ordering is fine but the bell fires mid-output.
**How to avoid:** Place `print_guidance()` immediately before `ring_bell()` in execute and merge, or immediately after (the bell is non-visual, so ordering relative to it is not critical for the user, but before is cleaner).

### Pitfall 4: Inconsistent Formatting with Existing init Output

**What goes wrong:** `init` already has "Next steps:" output (3 lines). If Phase 9 adds a new `print_guidance()` call without removing the old block, the user sees both.
**How to avoid:** Replace the existing `init` next-steps block with the new `print_guidance()` pattern.

## Code Examples

### Guidance Helper (to add to lib/common.sh)

```bash
# Print a next-step guidance message.
# Visually distinct from other output -- helps user see what to do next.
# Args: message (the guidance text)
print_guidance() {
    printf "\n${GREEN}  Next:${NC} %s\n" "$1"
}
```

### Exit Path: Execute Success

```bash
# End of cmd_execute, after summary block:
print_guidance "Run 'ralph' to start autonomous execution"
ring_bell
```

### Exit Path: Merge Full Success

```bash
# In merge, when all branches merged and tests pass:
print_guidance "Run: gsd-ralph cleanup $phase_num"
```

### Exit Path: Merge Partial Success (Some Conflicts)

```bash
# In merge, when some branches had conflicts:
print_guidance "Resolve conflicts, then re-run: gsd-ralph merge $phase_num"
```

### Exit Path: Merge Rollback

```bash
# After rollback completes:
print_guidance "Fix the issue, then re-run: gsd-ralph merge $phase_num"
```

## Exhaustive Exit Path Catalog

This catalog maps every command exit path to its context and recommended guidance. This is the core deliverable of this research.

### cmd_init (lib/commands/init.sh)

| Exit Point | Context | Guidance |
|------------|---------|----------|
| Success (end of function) | Fresh initialization complete | `"Review .ralphrc, then run: gsd-ralph execute <phase>"` |
| Already initialized (no --force) | .ralph/ exists | `"To reinitialize: gsd-ralph init --force"` |

*Note: die() exits (not in git repo, no .planning/, dependency check failure) do NOT get guidance -- the error message is self-explanatory.*

### cmd_execute (lib/commands/execute.sh)

| Exit Point | Context | Guidance |
|------------|---------|----------|
| Dry-run complete (return 0) | Preview shown | `"To execute for real: gsd-ralph execute $phase_num"` |
| Success (end of function) | Branch created, files generated | `"Run 'ralph' to start autonomous execution"` (replaces existing print_success on line 255) |

### cmd_generate (lib/commands/generate.sh)

| Exit Point | Context | Guidance |
|------------|---------|----------|
| Success (end of function) | Files generated to output dir | `"Review generated files in $output_dir"` |

### cmd_merge (lib/commands/merge.sh)

| Exit Point | Context | Guidance |
|------------|---------|----------|
| No unmerged branches found | Already merged or never executed | `"Run: gsd-ralph execute $phase_num  (if not yet executed)"` |
| Dry-run clean (return 0) | All branches clean | `"Ready to merge: gsd-ralph merge $phase_num"` |
| Dry-run conflicts (return 1) | Conflicts detected | `"Resolve conflicts before merging. See guidance above."` |
| All branches conflict (return 1) | Nothing mergeable | `"Resolve conflicts manually, then re-run: gsd-ralph merge $phase_num"` |
| Full success, all merged, tests pass | Phase complete | `"Run: gsd-ralph cleanup $phase_num"` |
| Partial success, some skipped/conflicted | Some merged, some not | `"Resolve remaining conflicts, then re-run: gsd-ralph merge $phase_num"` |
| Test regressions after merge | Tests fail post-merge | `"To undo: gsd-ralph merge $phase_num --rollback"` |
| Rollback success | Rolled back to pre-merge | `"Fix the issue, then re-run: gsd-ralph merge $phase_num"` |

### cmd_cleanup (lib/commands/cleanup.sh)

| Exit Point | Context | Guidance |
|------------|---------|----------|
| Nothing to clean | No worktrees/branches | No guidance needed (nothing happened) |
| Unregistered branches, no --force | Old branches found | `"Use --force to clean: gsd-ralph cleanup $phase_num --force"` |
| Unregistered branches, --force done | Cleaned up | `"Phase $phase_num fully cleaned up."` |
| Success (normal cleanup complete) | Worktrees/branches removed | `"Phase $phase_num fully cleaned up."` |
| Some branches skipped (unmerged) | Partial cleanup | `"Merge or force-delete remaining branches: gsd-ralph cleanup $phase_num --force"` |
| Aborted by user | User said no to confirmation | No guidance needed (user chose to abort) |

### cmd_status (lib/commands/status.sh)

| Exit Point | Context | Guidance |
|------------|---------|----------|
| Not yet implemented | Stub | No guidance needed (die message is sufficient) |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Ad-hoc "Next steps" in init only | No standard pattern | Pre-Phase 9 | Users of other commands get no guidance |
| After Phase 9: `print_guidance()` at every exit | Consistent, context-sensitive | Phase 9 | Every command tells user what to do next |

## Open Questions

1. **Should `print_guidance()` include the phase number in the prompt symbol?**
   - What we know: The existing init output uses `print_info "Next steps:"`. The new helper should be visually distinct from `[info]` prefixed lines.
   - What's unclear: Should it use a different prefix like `[next]` or just `Next:` with green color?
   - Recommendation: Use `Next:` with green color (matches `[ok]` color). This is planner's discretion to finalize.

2. **Should `die()` itself be modified to conditionally print guidance?**
   - What we know: Most `die()` messages are self-explanatory ("Not inside a git repository"). Some suggest a fix ("Run 'gsd-ralph init' first").
   - What's unclear: Whether there are die() messages that would benefit from a structured "Next:" line.
   - Recommendation: Do NOT modify `die()`. The existing die messages that suggest fixes already serve as guidance. Adding more would clutter fatal error output.

## Sources

### Primary (HIGH confidence)

- Direct codebase analysis of all 6 command files, `lib/common.sh`, `lib/push.sh`, `lib/config.sh`, `lib/merge/*.sh`
- `.planning/REQUIREMENTS.md` -- GUID-01 and GUID-02 requirement definitions
- `.planning/ROADMAP.md` -- Phase 9 success criteria

### Secondary (MEDIUM confidence)

- None needed. This phase is internal to the codebase and does not depend on external libraries.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - No external dependencies; pure Bash output additions to existing codebase
- Architecture: HIGH - Pattern is trivial (single helper function + calls at exit points); precedent exists in cmd_init
- Pitfalls: HIGH - Exit paths are fully enumerable from codebase analysis; catalog above is exhaustive

**Research date:** 2026-02-23
**Valid until:** No expiration -- findings are project-internal and do not depend on external ecosystem changes
