# Phase 5: Cleanup - Research

**Researched:** 2026-02-19
**Domain:** Git worktree lifecycle management, branch removal, registry-driven resource tracking in Bash
**Confidence:** HIGH

## Summary

Phase 5 implements `gsd-ralph cleanup N` -- a command that removes all worktrees and branches created for a given phase. The core technical challenge is **registry-driven tracking**: the tool must only remove worktrees and branches it created, not unrelated worktrees the user may have set up manually. This requires a worktree registry that records what was created during `execute` so that `cleanup` can safely enumerate and remove exactly those resources.

The existing codebase has a stub `cmd_cleanup()` in `lib/commands/cleanup.sh` and a reference implementation in `scripts/ralph-cleanup.sh`. The reference script uses **glob-based** discovery (`$PARENT_DIR/${REPO_NAME}-p${PHASE_NUM}-*`), which is precisely the pattern CLEN-02 forbids. The new implementation must replace this with a JSON registry file that records worktree paths and branch names at creation time, then reads that registry at cleanup time.

The implementation is straightforward: one new module (`lib/cleanup/registry.sh`) for the worktree registry, and the cleanup command itself in `lib/commands/cleanup.sh`. The registry file lives at `.ralph/worktree-registry.json` and is written by the execute command (or future parallel worktree creation), then consumed by cleanup. All git operations are well-understood (`git worktree remove`, `git branch -d/-D`, `git worktree prune`) and available in all relevant Git versions.

**Primary recommendation:** Use a JSON registry file at `.ralph/worktree-registry.json` that maps phase numbers to arrays of `{worktree_path, branch_name, created_at}` entries. The execute command writes entries at creation time; the cleanup command reads and removes them. Use `git worktree remove --force` for worktree removal and `git branch -d` (safe delete, only merged) with optional `--force` flag to allow `git branch -D` (force delete, even unmerged) for branch deletion.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CLEN-01 | User can remove all worktrees and branches for a completed phase with `gsd-ralph cleanup N` | Cleanup command reads worktree registry for phase N, iterates entries, calls `git worktree remove` and `git branch -d` for each, prunes stale references, removes signal/rollback files, prints summary |
| CLEN-02 | Tool only removes tracked worktrees (registry-driven, not glob-based) | JSON registry at `.ralph/worktree-registry.json` records worktree paths and branch names at creation time; cleanup reads only from this registry, never globs the filesystem |
</phase_requirements>

## Standard Stack

### Core

This phase uses no external libraries -- it is pure Bash + Git commands, consistent with the project's zero-dependency philosophy.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2+ | Script runtime | macOS system default, project constraint |
| Git | any modern | Worktree removal, branch deletion, pruning | `git worktree remove` available since Git 2.17 (April 2018) |
| jq | any | JSON registry manipulation | Already a project dependency, used throughout merge modules |

### Key Git Commands

| Command | Purpose | Notes |
|---------|---------|-------|
| `git worktree remove <path>` | Remove a worktree | Fails if worktree has uncommitted changes unless `--force` is used |
| `git worktree remove --force <path>` | Force-remove a dirty worktree | Needed when worktrees have uncommitted Ralph runtime files |
| `git worktree list --porcelain` | List all worktrees in machine-readable format | For validation: confirm worktree still exists before attempting removal |
| `git worktree prune` | Clean up stale worktree references | After removal, prunes any orphaned worktree metadata in `.git/worktrees/` |
| `git branch -d <branch>` | Delete a merged branch | Safe: refuses to delete unmerged branches |
| `git branch -D <branch>` | Force-delete a branch | Needed with `--force` flag for unmerged branches |
| `git show-ref --verify refs/heads/<branch>` | Check if branch exists | Before attempting deletion; prevents errors on already-deleted branches |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| JSON registry file | PHASES.md table parsing | JSON is structured and machine-readable; PHASES.md is human-readable markdown that would require fragile regex parsing |
| JSON registry file | `git worktree list` filtering | Git worktree list does not record which tool created the worktree; cannot distinguish gsd-ralph worktrees from user-created ones |
| JSON registry file | Glob pattern matching on paths | Exactly what CLEN-02 forbids: could match unrelated directories |
| `jq` for JSON | `python3 -c` inline JSON | jq is already a dependency and better suited for in-place JSON manipulation |

## Architecture Patterns

### Recommended Module Structure

```
lib/
  commands/
    cleanup.sh          # cmd_cleanup() entry point, argument parsing, orchestration
  cleanup/
    registry.sh         # Worktree registry: register, list, deregister, validate
```

**Rationale:** The registry module is a utility that will be called by both `execute` (to register worktrees at creation time) and `cleanup` (to enumerate and deregister at removal time). Separating it from the cleanup command keeps responsibilities clean and makes the registry testable independently.

**Alternative:** Put everything in `lib/commands/cleanup.sh`. This would work for a smaller implementation, but the registry needs to be sourced by `execute.sh` as well. A separate module avoids circular dependencies and keeps each file focused.

### Pattern 1: Worktree Registry (CLEN-02)

**What:** A JSON file that tracks all worktrees and branches created by gsd-ralph, keyed by phase number.

**When to use:** Every `execute` call writes to the registry; every `cleanup` call reads from and removes entries.

```bash
# Registry file location
WORKTREE_REGISTRY=".ralph/worktree-registry.json"

# Initialize registry if it does not exist
init_registry() {
    if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
        echo '{}' > "$WORKTREE_REGISTRY"
    fi
}

# Register a worktree and branch for a phase.
# Args: phase_num, worktree_path, branch_name
register_worktree() {
    local phase_num="$1"
    local worktree_path="$2"
    local branch_name="$3"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    init_registry

    local tmp
    tmp=$(jq --arg phase "$phase_num" \
             --arg wt "$worktree_path" \
             --arg br "$branch_name" \
             --arg ts "$timestamp" \
        'if .[$phase] then
            .[$phase] += [{"worktree_path": $wt, "branch": $br, "created_at": $ts}]
         else
            .[$phase] = [{"worktree_path": $wt, "branch": $br, "created_at": $ts}]
         end' "$WORKTREE_REGISTRY")
    printf '%s\n' "$tmp" > "$WORKTREE_REGISTRY"
}

# List registered worktrees for a phase.
# Args: phase_num
# Output: JSON array of entries
list_registered_worktrees() {
    local phase_num="$1"

    if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
        echo '[]'
        return
    fi

    jq --arg phase "$phase_num" '.[$phase] // []' "$WORKTREE_REGISTRY"
}

# Deregister all worktrees for a phase (remove the phase key).
# Args: phase_num
deregister_phase() {
    local phase_num="$1"

    if [[ ! -f "$WORKTREE_REGISTRY" ]]; then
        return 0
    fi

    local tmp
    tmp=$(jq --arg phase "$phase_num" 'del(.[$phase])' "$WORKTREE_REGISTRY")
    printf '%s\n' "$tmp" > "$WORKTREE_REGISTRY"
}
```

### Pattern 2: Cleanup Pipeline (Core Loop)

**What:** Sequential removal of worktrees and branches with validation, error handling, and summary.

**When to use:** Every `gsd-ralph cleanup N` invocation.

```bash
cmd_cleanup() {
    local phase_num="$1"

    # 1. Validate environment (git repo, .ralph exists)
    # 2. Read registry for this phase
    # 3. If empty, report "nothing to clean" and exit
    # 4. Preview what will be removed (list worktrees and branches)
    # 5. Unless --force, prompt for confirmation
    # 6. For each registered entry:
    #    a. Remove worktree (git worktree remove [--force])
    #    b. Delete branch (git branch -d, or -D with --force)
    #    c. Track success/failure
    # 7. Run git worktree prune
    # 8. Clean up signal files (.ralph/merge-signals/phase-N-*)
    # 9. Clean up rollback file if it belongs to this phase
    # 10. Deregister phase from registry
    # 11. Print summary
}
```

### Pattern 3: Execute-Side Registration

**What:** The execute command registers the branch it creates in the worktree registry at creation time.

**When to use:** During `gsd-ralph execute N` when the branch is created.

```bash
# In lib/commands/execute.sh, after creating the branch:
# Source registry module
source "$GSD_RALPH_HOME/lib/cleanup/registry.sh"

# Register the execution branch
# For sequential mode, the "worktree" is the current working directory
# (execute creates a branch, not a separate worktree directory)
register_worktree "$phase_num" "$(pwd)" "$branch_name"
```

**Important distinction:** The current `execute` command creates a **branch** in the current repo (not a separate worktree directory). This is sequential mode -- a single branch for the whole phase. The registry still tracks this, with the worktree_path being the current working directory. In future parallel mode (using `ralph-worktrees.sh` patterns), actual separate worktree directories would be created and registered.

### Pattern 4: Confirmation Prompt

**What:** Ask user to confirm before destructive cleanup operation, with `--force` to skip.

**When to use:** Before removing any worktrees or branches.

```bash
# Unless --force, show what will be removed and ask for confirmation
if [[ "$force" != true ]]; then
    print_info "Will remove:"
    # ... list entries ...
    printf "\n"
    printf "Confirm removal? [y/N]: "
    read -r confirm
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        print_info "Aborted."
        return 0
    fi
fi
```

### Pattern 5: Graceful Handling of Already-Removed Resources

**What:** Handle the case where a worktree or branch has already been manually removed.

**When to use:** During cleanup iteration, when a registered resource no longer exists.

```bash
# Worktree may have already been manually removed
if [[ -d "$worktree_path" ]]; then
    git worktree remove "$worktree_path" --force 2>/dev/null || {
        print_warning "Could not remove worktree: $worktree_path"
        # Fall back to rm -rf if git worktree remove fails
        rm -rf "$worktree_path" 2>/dev/null || true
    }
    print_success "Removed worktree: $(basename "$worktree_path")"
else
    print_verbose "Worktree already removed: $worktree_path"
fi

# Branch may have already been deleted
if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    if git branch -d "$branch_name" 2>/dev/null; then
        print_success "Deleted branch: $branch_name"
    else
        if [[ "$force" == true ]]; then
            git branch -D "$branch_name" 2>/dev/null
            print_success "Force-deleted branch: $branch_name"
        else
            print_warning "Branch not merged: $branch_name (use --force to delete anyway)"
        fi
    fi
else
    print_verbose "Branch already deleted: $branch_name"
fi
```

### Anti-Patterns to Avoid

- **Glob-based worktree discovery:** Never use `$PARENT_DIR/${REPO_NAME}-p${PHASE_NUM}-*` to find worktrees. This is the exact pattern CLEN-02 forbids. It could match user-created directories that happen to follow a similar naming convention.
- **Removing branches before worktrees:** Git refuses to delete a branch that is checked out in any worktree. Always remove the worktree first, then delete the branch.
- **Using `git branch -D` by default:** This force-deletes even unmerged branches. Default behavior should be safe (`git branch -d`), with `--force` required for `git branch -D`.
- **Ignoring git worktree prune:** After removing worktrees, stale references can linger in `.git/worktrees/`. Always run `git worktree prune` at the end.
- **Silent failure on missing registry:** If the registry file does not exist or has no entries for the phase, the command should report this clearly rather than succeeding silently.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Worktree existence check | Parse `git worktree list` with regex | Check if directory exists + `git worktree list --porcelain` | Directory check is simpler and sufficient; porcelain output is for validation only |
| Branch existence check | `git branch \| grep` | `git show-ref --verify --quiet refs/heads/$name` | Exit code based, no output parsing, already used throughout codebase |
| JSON registry manipulation | sed/awk on JSON, or custom line-based format | jq | Already a project dependency; correct JSON handling; handles arrays, nested objects |
| Worktree removal | `rm -rf` directly | `git worktree remove [--force]` then `rm -rf` as fallback | `git worktree remove` properly cleans up `.git/worktrees/` metadata; `rm -rf` is fallback only |
| Confirmation prompt | Custom read loop | Simple `read -r` with y/N pattern | Matches the reference script pattern; established UX convention |

**Key insight:** The cleanup command is conceptually simple (iterate, remove, report), but the **safety** comes from the registry. The registry is the only code that requires careful design -- everything else is straightforward git operations.

## Common Pitfalls

### Pitfall 1: Removing Branch Before Worktree

**What goes wrong:** `git branch -d <branch>` fails with "error: Cannot delete branch checked out at..." because the branch is still checked out in a worktree.
**Why it happens:** The worktree still exists and has the branch checked out.
**How to avoid:** Always remove the worktree first (`git worktree remove`), then delete the branch.
**Warning signs:** Error message from `git branch -d` mentioning "checked out at."

### Pitfall 2: Dirty Worktree Blocks Removal

**What goes wrong:** `git worktree remove <path>` fails because the worktree has uncommitted changes (Ralph runtime files like `.ralph_session`, `live.log`, `progress.json`).
**Why it happens:** Ralph leaves runtime state files that are not committed. These make the worktree "dirty" in git's view.
**How to avoid:** Use `git worktree remove --force` by default for cleanup, since these are ephemeral runtime files. Document this in the `--help` output.
**Warning signs:** "fatal: '<path>' contains modified or untracked files, use --force to delete it."

### Pitfall 3: Registry File Corruption

**What goes wrong:** Registry file becomes invalid JSON (e.g., interrupted write), making jq commands fail.
**Why it happens:** Process interrupted during a write to the registry file.
**How to avoid:** Validate registry JSON before processing. If invalid, warn the user and offer to recreate (empty) or fall back to listing branches by pattern as a recovery mechanism.
**Warning signs:** jq parse errors when reading the registry.

### Pitfall 4: Execute Does Not Register (Migration Gap)

**What goes wrong:** User runs `cleanup` but the registry is empty because `execute` was run before the registry feature existed.
**Why it happens:** The registry is a new feature in Phase 5. Earlier executions did not write to it.
**How to avoid:** When the registry has no entries for a phase but branches exist (detected by pattern), print a helpful message: "No tracked worktrees found for phase N. Branches matching phase-N/* exist but were not registered. Use --force to clean up untracked branches for this phase."
**Warning signs:** User reports "cleanup says nothing to clean, but branches still exist."

### Pitfall 5: Stale Worktree References in .git/worktrees/

**What goes wrong:** After removing worktree directories (especially via `rm -rf` fallback), git still thinks worktrees exist.
**Why it happens:** `.git/worktrees/<name>` metadata directories are not cleaned up by filesystem removal.
**How to avoid:** Always call `git worktree prune` after all removals. This cleans up stale worktree metadata.
**Warning signs:** `git worktree list` shows entries for removed directories.

### Pitfall 6: Bash 3.2 read -r and Prompt

**What goes wrong:** Interactive prompt does not work correctly on macOS default Bash.
**Why it happens:** Bash 3.2 `read` has minor quirks with certain terminal modes.
**How to avoid:** Use the simple `read -r confirm` pattern (no -p flag for prompt -- use printf before read for Bash 3.2 compatibility). The reference script `scripts/ralph-cleanup.sh` uses `read -p` which works but printf + read is more portable.
**Warning signs:** Prompt text not appearing, or prompt appearing on stderr.

## Code Examples

Verified patterns from the existing codebase and Git documentation.

### Worktree Removal with Fallback (from reference script)

```bash
# Source: scripts/ralph-cleanup.sh
git worktree remove "$wt" --force 2>/dev/null || rm -rf "$wt"
```

### Safe Branch Deletion (from reference script)

```bash
# Source: scripts/ralph-cleanup.sh
if git branch -d "$BRANCH" 2>/dev/null; then
    echo "  Branch deleted"
else
    echo "  Branch not deleted (may not be merged)"
    echo "  To force delete: git branch -D $BRANCH"
fi
```

### Branch Existence Check (from merge.sh)

```bash
# Source: lib/commands/merge.sh
if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
    # Branch exists
fi
```

### Git Worktree List Porcelain Format

```
# Output of `git worktree list --porcelain`:
worktree /path/to/main
HEAD abc123...
branch refs/heads/main

worktree /path/to/worktree
HEAD def456...
branch refs/heads/feature-branch
```

Each worktree block is separated by a blank line. The `worktree` line gives the absolute path. The `branch` line gives the full ref. This format is machine-parseable and stable across git versions.

### Merge Signal Cleanup

```bash
# Remove signal files for a phase
rm -f .ralph/merge-signals/phase-${phase_num}-*
```

### Rollback File Cleanup

```bash
# Remove rollback file if it belongs to this phase
if [[ -f ".ralph/merge-rollback.json" ]]; then
    local rollback_phase
    rollback_phase=$(jq -r '.phase' ".ralph/merge-rollback.json" 2>/dev/null)
    if [[ "$rollback_phase" == "$phase_num" ]]; then
        rm -f ".ralph/merge-rollback.json"
    fi
fi
```

### jq Registry Operations

```bash
# Count entries for a phase
jq --arg phase "$phase_num" '.[$phase] // [] | length' "$WORKTREE_REGISTRY"

# Get worktree path of entry i
jq -r --arg phase "$phase_num" '.[$phase][$i].worktree_path' "$WORKTREE_REGISTRY"

# Get branch name of entry i
jq -r --arg phase "$phase_num" '.[$phase][$i].branch' "$WORKTREE_REGISTRY"

# Remove phase from registry
jq --arg phase "$phase_num" 'del(.[$phase])' "$WORKTREE_REGISTRY"
```

### Confirmation Pattern (Bash 3.2 Compatible)

```bash
# printf for prompt text, read -r for input (no -p flag for portability)
printf "Confirm removal? [y/N]: "
read -r confirm
if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
    print_info "Aborted."
    return 0
fi
```

## Integration Points

### Execute Command Must Register

The `execute` command (`lib/commands/execute.sh`) must be modified to register the branch it creates:

```bash
# After line 154 (git checkout -b "$branch_name"):
source "$GSD_RALPH_HOME/lib/cleanup/registry.sh"
register_worktree "$phase_num" "$(pwd)" "$branch_name"
```

For sequential mode, the "worktree_path" is the current working directory (the branch is created in-place, not in a separate directory). This is semantically correct: cleanup needs to know which branch to delete, and the path serves as a reference to the execution context.

### Merge Signals and Rollback Files

Cleanup should also remove phase-specific artifacts from the merge pipeline:
- `.ralph/merge-signals/phase-N-*` -- Wave and phase completion signals
- `.ralph/merge-rollback.json` -- Only if it belongs to the phase being cleaned up

These are small files, but leaving them after cleanup creates confusion if the phase is re-executed.

### Future: Parallel Mode Registration

When parallel worktree execution is implemented (using patterns from `scripts/ralph-worktrees.sh`), the worktree creation code will call `register_worktree()` for each worktree directory it creates. The cleanup command will then have multiple entries per phase to iterate over. The registry design already supports this (array of entries per phase).

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Glob-based worktree discovery | Registry-driven tracking | This phase | Prevents accidental deletion of unrelated worktrees |
| `rm -rf` for worktree removal | `git worktree remove --force` with `rm -rf` fallback | Git 2.17 (2018) | Proper cleanup of `.git/worktrees/` metadata |
| Manual branch deletion | Automated safe delete with force option | This phase | Prevents deletion of unmerged branches unless explicitly requested |

**Deprecated/outdated:**
- `scripts/ralph-cleanup.sh` glob-based pattern: The reference script works but violates CLEN-02. It is suitable only as a logic reference, not as implementation guidance.

## Open Questions

1. **Interactive prompt in non-interactive mode**
   - What we know: The cleanup command needs a confirmation prompt before destructive operations. The `--force` flag skips the prompt.
   - What's unclear: Should the command detect non-interactive terminals (piped input, CI) and auto-skip or auto-refuse?
   - Recommendation: When stdin is not a terminal (`! [[ -t 0 ]]`), require `--force` and exit with an error if not provided. This prevents accidental cleanup in scripts without explicit opt-in.

2. **Registry schema versioning**
   - What we know: The registry is a new file. The initial schema is straightforward.
   - What's unclear: Will the schema need to evolve? Should we include a version field?
   - Recommendation: Include a `"version": 1` field at the top level. This costs nothing and provides a migration path if the schema changes. LOW risk -- the schema is simple and unlikely to change significantly.

3. **Cleanup after failed merge (unmerged branches)**
   - What we know: `git branch -d` refuses to delete unmerged branches. The `--force` flag is needed for `git branch -D`.
   - What's unclear: Should cleanup default to safe (refuse unmerged) or force (always delete)?
   - Recommendation: Default to safe (`git branch -d`). With `--force`, use `git branch -D`. Print clear guidance when a branch is not deleted: "Branch 'X' has unmerged changes. Use 'gsd-ralph cleanup N --force' to delete anyway."

## Sources

### Primary (HIGH confidence)
- [Git worktree documentation](https://git-scm.com/docs/git-worktree) - `remove`, `list --porcelain`, `prune` commands and options
- [Git branch documentation](https://git-scm.com/docs/git-branch) - `-d` (safe delete) vs `-D` (force delete), error conditions
- Existing codebase analysis: `lib/commands/cleanup.sh` (stub), `lib/commands/execute.sh` (branch creation patterns), `lib/commands/merge.sh` (branch discovery), `lib/merge/signals.sh` (signal files to clean), `lib/merge/rollback.sh` (rollback file to clean), `lib/discovery.sh` (worktree path computation), `lib/common.sh` (output functions)
- Reference implementation: `scripts/ralph-cleanup.sh` (logic reference for removal flow and user interaction)
- Reference implementation: `scripts/ralph-worktrees.sh` (logic reference for worktree creation patterns)
- Git version installed: 2.53.0 (verified on target system)

### Secondary (MEDIUM confidence)
- Existing test patterns: `tests/init.bats`, `tests/common.bats`, `tests/test_helper/common.bash` (bats-core test infrastructure, test helper patterns, temp directory isolation)

### Tertiary (LOW confidence)
- None -- all findings verified through official documentation, existing codebase analysis, or direct command testing.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Pure Bash + Git + jq, all tools already used throughout the project. All Git commands verified in official docs and confirmed available on target system (Git 2.53.0).
- Architecture: HIGH - Module structure follows established patterns (lib/commands/ for entry points, lib/<domain>/ for utilities). Registry pattern is the simplest reliable approach for tracking created resources.
- Pitfalls: HIGH - Derived from documented Git behaviors (worktree dirty check, branch checked-out protection), existing project learnings (Bash 3.2 compatibility, Ralph runtime files), and analysis of the reference implementation's limitations.
- Integration: HIGH - Execute command modification is minimal (2-3 lines). Registry module interface is clean and testable.

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (stable domain -- Git worktree/branch APIs change infrequently)
