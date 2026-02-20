# Architecture Research: v1.1 Safety & UX Integration

**Domain:** Bash CLI tool -- safety guardrails, UX improvements, and remote push integration
**Researched:** 2026-02-20
**Confidence:** HIGH (based on direct reading of the v1.0 codebase; all integration points verified against actual source)

## Current Architecture (v1.0 Baseline)

The existing system follows a command-dispatch pattern with shared libraries.

```
bin/gsd-ralph                    # Entry point: parse globals, dispatch to cmd_<name>
    |
    +-- lib/common.sh            # Output helpers, die(), ring_bell(), deps check
    +-- lib/config.sh            # detect_project_type() -> DETECTED_LANG, etc.
    |
    +-- lib/commands/
    |       init.sh              # cmd_init: create .ralph/, .ralphrc
    |       generate.sh          # cmd_generate: per-plan file generation
    |       execute.sh           # cmd_execute: branch, prompt, launch env
    |       merge.sh             # cmd_merge: dry-run, merge, test, signal
    |       cleanup.sh           # cmd_cleanup: registry-driven removal
    |       status.sh            # cmd_status: stub (not implemented)
    |
    +-- lib/discovery.sh         # find_phase_dir(), discover_plan_files()
    +-- lib/frontmatter.sh       # Plan file parsing
    +-- lib/prompt.sh            # Prompt/fix_plan generation
    +-- lib/strategy.sh          # Phase strategy analysis (waves, deps)
    +-- lib/templates.sh         # Template rendering
    |
    +-- lib/merge/
    |       dry_run.sh           # merge_dry_run(), merge_dry_run_conflicts()
    |       rollback.sh          # save/restore/record rollback points
    |       auto_resolve.sh      # Auto-resolve .planning/*, lock files
    |       review.sh            # Summary tables, conflict guidance
    |       signals.sh           # Wave/phase completion signals
    |       test_runner.sh       # Post-merge regression detection
    |
    +-- lib/cleanup/
            registry.sh          # Worktree registry CRUD (JSON via jq)
```

### Key Architectural Properties

1. **Global state via shell variables**: Commands set globals (PHASE_DIR, PLAN_FILES, STRATEGY_MODE, etc.) that downstream functions read. No return values for complex data.

2. **Source-on-demand**: Each command sources only the libraries it needs (execute.sh sources discovery.sh, prompt.sh, etc.). The entry point only sources common.sh and config.sh.

3. **JSON state files via jq**: Registry (.ralph/worktree-registry.json), rollback (.ralph/merge-rollback.json), and signals (.ralph/merge-signals/) use JSON manipulated by jq.

4. **Validation-then-action pattern**: Every command validates environment (git repo? .planning exists? .ralph exists?) before doing work. Validation errors exit early without side effects.

5. **EXIT trap for bell notification**: execute.sh and merge.sh use `trap 'ring_bell' EXIT` after significant work begins, cleared on success.

## v1.1 Integration Architecture

### System Overview: What Changes

```
bin/gsd-ralph                         # UNCHANGED (no modifications needed)
    |
    +-- lib/common.sh                 # MODIFY: add print_next_step()
    +-- lib/config.sh                 # UNCHANGED
    |
    +-- lib/safety.sh                 # NEW: path validation, rm-rf prevention
    +-- lib/git_remote.sh             # NEW: remote detection, push helpers
    +-- lib/guidance.sh               # NEW: next-step guidance engine
    |
    +-- lib/commands/
    |       init.sh                   # MODIFY: detect remote, next-step guidance
    |       execute.sh                # MODIFY: auto-push, next-step guidance
    |       merge.sh                  # MODIFY: auto-switch, stash, auto-push, guidance
    |       cleanup.sh                # MODIFY: safety guards, next-step guidance
    |       generate.sh               # MODIFY: next-step guidance (minor)
    |       status.sh                 # UNCHANGED (still stub)
    |
    +-- lib/cleanup/
            registry.sh               # MODIFY: remove rm-rf fallback, add safety check
```

### New Components

| Component | File | Responsibility | Sourced By |
|-----------|------|----------------|------------|
| **Safety Guards** | `lib/safety.sh` | Path validation, rm-rf prevention, git-toplevel protection | cleanup.sh, any command doing file removal |
| **Git Remote** | `lib/git_remote.sh` | Remote detection, push-with-retry, push-after-action helpers | execute.sh, merge.sh, init.sh |
| **Guidance Engine** | `lib/guidance.sh` | Context-aware next-step messaging after each command completes | All commands |

### Modified Components

| Component | File | Changes | Reason |
|-----------|------|---------|--------|
| **Common** | `lib/common.sh` | Add `print_next_step()` formatting helper | Consistent next-step output styling |
| **Init** | `lib/commands/init.sh` | Detect and store remote info; print guidance | Remote awareness for auto-push |
| **Execute** | `lib/commands/execute.sh` | Push branch after commit; print guidance | Auto-push safety net |
| **Merge** | `lib/commands/merge.sh` | Auto-switch to main, stash/unstash dirty worktree, push after merge; print guidance | UX friction removal |
| **Cleanup** | `lib/commands/cleanup.sh` | Remove rm-rf fallback, add path safety checks; print guidance | Critical data-loss bug fix |
| **Registry** | `lib/cleanup/registry.sh` | Skip registration of main worktree path; validate paths before use | Prevent cleanup of project root |

## Detailed Component Designs

### Component 1: Safety Guards (`lib/safety.sh`)

**Purpose:** Centralized path validation to prevent destructive operations. This is the highest-priority component because it fixes a known data-loss bug.

**Functions:**

```bash
# Refuse to remove paths that match dangerous patterns.
# Returns 0 if safe, 1 if dangerous (with error message).
# Checks: is git toplevel? is home dir? is root? is parent of .git?
assert_safe_to_remove() {
    local target_path="$1"
    local git_toplevel
    git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null)

    # Resolve to absolute path for comparison
    local abs_path
    abs_path=$(cd "$target_path" 2>/dev/null && pwd) || abs_path="$target_path"

    # Block: git toplevel (project root)
    if [[ "$abs_path" == "$git_toplevel" ]]; then
        print_error "SAFETY: Refusing to remove project root: $abs_path"
        return 1
    fi

    # Block: home directory
    if [[ "$abs_path" == "$HOME" ]]; then
        print_error "SAFETY: Refusing to remove home directory"
        return 1
    fi

    # Block: filesystem root
    if [[ "$abs_path" == "/" ]]; then
        print_error "SAFETY: Refusing to remove filesystem root"
        return 1
    fi

    # Block: paths that don't look like worktrees (no .git file)
    if [[ -d "$abs_path" ]] && [[ ! -f "$abs_path/.git" ]]; then
        print_error "SAFETY: Path does not appear to be a git worktree (no .git file): $abs_path"
        return 1
    fi

    return 0
}

# Validate a path from the registry before using it.
# Returns 0 if valid, 1 if suspicious.
validate_registry_path() {
    local path="$1"

    # Must be absolute
    if [[ "$path" != /* ]]; then
        print_error "SAFETY: Registry path is not absolute: $path"
        return 1
    fi

    # Must not contain path traversal
    case "$path" in
        *..*)
            print_error "SAFETY: Registry path contains traversal: $path"
            return 1
            ;;
    esac

    return 0
}
```

**Integration points:**
- `cleanup.sh` line 174-183: Replace `rm -rf` fallback with `assert_safe_to_remove` guard
- `cleanup.sh` line 143: Add `validate_registry_path` before using registry paths
- `registry.sh` `register_worktree`: Skip registration when worktree_path equals git toplevel

### Component 2: Git Remote (`lib/git_remote.sh`)

**Purpose:** Detect remote availability and push branches/merges automatically. Acts as a data-loss safety net.

**Functions:**

```bash
# Check if a push-capable remote exists.
# Caches result for the session in GSD_RALPH_REMOTE.
# Returns 0 if remote available, 1 if not.
has_push_remote() {
    if [[ -n "${GSD_RALPH_REMOTE:-}" ]]; then
        [[ "$GSD_RALPH_REMOTE" != "none" ]]
        return $?
    fi

    local remote
    remote=$(git remote 2>/dev/null | head -1)
    if [[ -n "$remote" ]]; then
        GSD_RALPH_REMOTE="$remote"
        return 0
    else
        GSD_RALPH_REMOTE="none"
        return 1
    fi
}

# Push a branch to the remote. Non-blocking: warns on failure, does not die.
# Args: branch_name
# Returns: 0 on success, 1 on failure (with warning)
push_branch() {
    local branch="$1"
    if ! has_push_remote; then
        print_verbose "No remote configured, skipping push"
        return 0
    fi

    if git push "$GSD_RALPH_REMOTE" "$branch" 2>/dev/null; then
        print_success "Pushed $branch to $GSD_RALPH_REMOTE"
        return 0
    else
        print_warning "Failed to push $branch to $GSD_RALPH_REMOTE (network issue?)"
        return 1
    fi
}

# Push current branch (typically main after merge).
# Returns: 0 on success, 1 on failure (with warning)
push_current_branch() {
    local current
    current=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [[ -n "$current" ]]; then
        push_branch "$current"
    fi
}
```

**Integration points:**
- `execute.sh` after Step 11 (commit): Call `push_branch "$branch_name"`
- `merge.sh` after Phase 5 (wave signaling): Call `push_current_branch`
- `init.sh` after Step 4 (deps): Call `has_push_remote` and report status

**Design decision -- push is advisory, not mandatory:**
Push failures warn but do not block the workflow. The user may be offline, the remote may be temporarily unavailable, or they may not have push access. The tool should never fail because a remote is unreachable. This matches the existing pattern where `ring_bell` is best-effort notification.

### Component 3: Guidance Engine (`lib/guidance.sh`)

**Purpose:** After each command completes, tell the user exactly what to do next. Context-aware: the guidance depends on what just happened and what state the project is in.

**Functions:**

```bash
# Print next-step guidance after a command completes.
# Args: command_name, phase_num, [extra context vars...]
# Uses the command name to select the appropriate guidance block.
print_guidance() {
    local command="$1"
    local phase_num="${2:-}"

    printf "\n"
    print_info "Next steps:"

    case "$command" in
        init)
            printf "  1. Review .ralphrc configuration\n"
            printf "  2. Plan your first phase with GSD\n"
            printf "  3. Run: gsd-ralph execute 1\n"
            ;;
        execute)
            printf "  1. Run 'ralph' in this terminal to start autonomous execution\n"
            printf "  2. Wait for Ralph to complete all tasks\n"
            printf "  3. Run: gsd-ralph merge %s\n" "$phase_num"
            ;;
        merge)
            printf "  1. Verify the merged code works as expected\n"
            printf "  2. Run: gsd-ralph cleanup %s\n" "$phase_num"
            local next_phase=$((phase_num + 1))
            printf "  3. Next phase: gsd-ralph execute %s\n" "$next_phase"
            ;;
        merge_partial)
            printf "  1. Resolve conflicts in the listed branches manually\n"
            printf "  2. Re-run: gsd-ralph merge %s\n" "$phase_num"
            ;;
        merge_rollback)
            printf "  1. Investigate the issue on the phase branch\n"
            printf "  2. Re-run: gsd-ralph merge %s\n" "$phase_num"
            ;;
        cleanup)
            local next_phase=$((phase_num + 1))
            printf "  1. Run: gsd-ralph execute %s\n" "$next_phase"
            ;;
        generate)
            printf "  1. Review generated files in .ralph/generated/\n"
            printf "  2. Run: gsd-ralph execute %s\n" "$phase_num"
            ;;
    esac
}
```

**Integration points:**
- Replace ad-hoc "Next steps" blocks in init.sh (lines 90-93), execute.sh (lines 243-246)
- Add guidance calls at end of merge.sh, cleanup.sh, generate.sh
- Different guidance for merge success vs partial merge vs rollback

### Component 4: Merge UX Improvements (in `lib/commands/merge.sh`)

**Purpose:** Remove two friction points: (1) user must manually switch to main before merging, (2) dirty worktree blocks merge with no remedy.

**Change 1: Auto-switch to main branch**

Replace the current hard-fail at merge.sh lines 168-177:

```bash
# CURRENT (v1.0): Dies if not on main
local current_branch
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$current_branch" != "main" ]] && [[ "$current_branch" != "master" ]]; then
    die "Not on main branch. Switch to main first: git checkout main"
fi
```

With auto-switching:

```bash
# NEW (v1.1): Auto-switch to main
local current_branch
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
local main_branch=""
for candidate in main master; do
    if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
        main_branch="$candidate"
        break
    fi
done

if [[ -z "$main_branch" ]]; then
    die "No main or master branch found."
fi

if [[ "$current_branch" != "$main_branch" ]]; then
    print_info "Currently on '$current_branch', switching to '$main_branch'..."
    # Handle dirty worktree before switching (see Change 2)
    handle_dirty_worktree
    git checkout "$main_branch" 2>/dev/null || \
        die "Failed to switch to $main_branch. Check for uncommitted changes."
    print_success "Switched to $main_branch"
fi
```

**Change 2: Stash/unstash for dirty worktree**

Add a helper function within merge.sh or in a shared location:

```bash
# Stash uncommitted changes if worktree is dirty.
# Sets MERGE_STASHED=true if a stash was created.
MERGE_STASHED=false

handle_dirty_worktree() {
    local porcelain
    porcelain=$(git status --porcelain 2>/dev/null)
    if [[ -z "$porcelain" ]]; then
        return 0  # Clean, nothing to do
    fi

    print_info "Stashing uncommitted changes..."
    if git stash push -m "gsd-ralph merge: auto-stash" 2>/dev/null; then
        MERGE_STASHED=true
        print_success "Stashed uncommitted changes (will restore after merge)"
    else
        die "Failed to stash changes. Commit or discard manually before merging."
    fi
}

# Restore stashed changes after merge completes.
restore_stash() {
    if [[ "$MERGE_STASHED" == true ]]; then
        print_info "Restoring stashed changes..."
        if git stash pop 2>/dev/null; then
            print_success "Restored stashed changes"
        else
            print_warning "Could not auto-restore stash. Run 'git stash pop' manually."
        fi
        MERGE_STASHED=false
    fi
}
```

**Integration:** Call `restore_stash` at the end of cmd_merge, just before the final return. Also call it in error paths (before die calls after work has started) to avoid losing stashed changes.

### Component 5: Registry Safety (in `lib/cleanup/registry.sh`)

**Purpose:** Prevent the project root from being registered as a worktree path.

**Changes to `register_worktree()`:**

```bash
register_worktree() {
    local phase_num="$1"
    local worktree_path="$2"
    local branch_name="$3"

    # SAFETY: Never register the main working tree
    local git_toplevel
    git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null)
    local abs_wt_path
    abs_wt_path=$(cd "$worktree_path" 2>/dev/null && pwd) || abs_wt_path="$worktree_path"

    if [[ "$abs_wt_path" == "$git_toplevel" ]]; then
        print_verbose "Skipping registry for main working tree (safety guard)"
        return 0
    fi

    # ... rest of existing function unchanged
}
```

**Changes to cleanup.sh worktree removal (line 174-183):**

Replace the `rm -rf` fallback entirely:

```bash
# BEFORE (v1.0 -- DANGEROUS):
# rm -rf "$wt_path" 2>/dev/null || true

# AFTER (v1.1):
if assert_safe_to_remove "$wt_path"; then
    print_warning "git worktree remove failed. Worktree may need manual cleanup: $wt_path"
else
    print_error "SAFETY: Blocked removal of $wt_path -- not a valid worktree"
fi
```

## Data Flow Changes

### v1.0 Execute Flow
```
cmd_execute
    -> validate environment
    -> discover plans
    -> create branch
    -> register_worktree($(pwd), branch)    # BUG: registers project root
    -> generate prompts
    -> commit
    -> print summary
```

### v1.1 Execute Flow
```
cmd_execute
    -> validate environment
    -> discover plans
    -> create branch
    -> register_worktree($(pwd), branch)    # FIXED: skips main worktree
    -> generate prompts
    -> commit
    -> push_branch(branch)                  # NEW: auto-push
    -> print summary
    -> print_guidance("execute", phase)     # NEW: next steps
```

### v1.0 Merge Flow
```
cmd_merge
    -> validate: must be on main             # FRICTION: manual switch required
    -> validate: clean worktree              # FRICTION: manual stash required
    -> dry-run preflight
    -> save rollback
    -> merge branches
    -> post-merge tests
    -> wave signaling
    -> print summary
```

### v1.1 Merge Flow
```
cmd_merge
    -> detect main branch                    # NEW: find main/master
    -> auto-switch to main                   # NEW: handles being on phase branch
    -> handle_dirty_worktree (stash)         # NEW: auto-stash
    -> dry-run preflight
    -> save rollback
    -> merge branches
    -> post-merge tests
    -> wave signaling
    -> push_current_branch                   # NEW: auto-push merged main
    -> print summary
    -> restore_stash                         # NEW: pop stash
    -> print_guidance("merge", phase)        # NEW: next steps
```

### v1.0 Cleanup Flow
```
cmd_cleanup
    -> read registry
    -> for each entry:
        -> git worktree remove
        -> if fail: rm -rf (DANGEROUS)       # BUG: can delete project root
        -> git branch -d
    -> prune
    -> deregister
```

### v1.1 Cleanup Flow
```
cmd_cleanup
    -> read registry
    -> for each entry:
        -> validate_registry_path(path)      # NEW: path validation
        -> assert_safe_to_remove(path)       # NEW: safety check
        -> git worktree remove
        -> if fail: warn (no rm -rf)         # FIXED: no fallback deletion
        -> git branch -d
    -> prune
    -> deregister
    -> print_guidance("cleanup", phase)      # NEW: next steps
```

## Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| safety.sh <-> cleanup.sh | Direct function call (source safety.sh, call assert_safe_to_remove) | Safety module is stateless -- pure validation |
| git_remote.sh <-> execute.sh | Direct function call (source git_remote.sh, call push_branch) | Push is fire-and-forget; failure is warning only |
| git_remote.sh <-> merge.sh | Direct function call (call push_current_branch) | Same as execute |
| guidance.sh <-> all commands | Direct function call (call print_guidance at end) | Guidance is output-only, no side effects |
| merge.sh stash <-> merge.sh main flow | Global variable MERGE_STASHED | Follows existing pattern (MERGE_BRANCHES, etc.) |

## Anti-Patterns to Avoid

### Anti-Pattern 1: Conditional Safety Based on Mode

**What people do:** Only apply safety checks in non-force mode, bypass them with --force.
**Why it is wrong:** The --force flag should force-delete *unmerged branches*. It should never bypass path safety checks. A user passing --force still does not want their project root deleted.
**Do this instead:** Safety checks (assert_safe_to_remove) are unconditional. They fire regardless of --force. The --force flag only controls git branch deletion (-d vs -D) and confirmation prompts.

### Anti-Pattern 2: Push as a Blocking Prerequisite

**What people do:** Make the workflow fail if push to remote fails.
**Why it is wrong:** The user may be offline, on a plane, behind a VPN, or the remote may be temporarily down. The core workflow (branch, execute, merge, cleanup) must work locally.
**Do this instead:** Push is advisory. Success: print green message. Failure: print yellow warning. Never die() on push failure. The user can push manually later.

### Anti-Pattern 3: Stash Without Pop

**What people do:** Stash changes at the start of merge but forget to pop on error paths.
**Why it is wrong:** User's uncommitted work silently disappears. They may not realize it is in the stash.
**Do this instead:** Use an EXIT trap or ensure every exit path (including die() calls after stashing) calls restore_stash(). Consider wrapping the merge body in a subshell or using trap to guarantee stash restoration.

### Anti-Pattern 4: Guidance That Assumes Linear Workflow

**What people do:** Always print "next: execute N+1" after merge, even when the merge partially failed.
**Why it is wrong:** If some branches had conflicts, the next step is to resolve conflicts and re-merge, not to move on.
**Do this instead:** Branch the guidance based on merge outcome: full success -> cleanup, partial -> resolve + re-merge, rollback -> investigate + re-merge.

## Build Order (Dependency-Driven)

The features have these dependency relationships:

```
                    lib/safety.sh (no deps)
                         |
                         v
          lib/cleanup/registry.sh (uses safety.sh)
                         |
                         v
          lib/commands/cleanup.sh (uses safety.sh + registry.sh)
                         |
    +--------------------+--------------------+
    |                                         |
    v                                         v
lib/git_remote.sh (no deps)          lib/guidance.sh (no deps)
    |                                         |
    v                                         v
lib/commands/execute.sh               All command files
lib/commands/merge.sh                 (add guidance calls)
lib/commands/init.sh
    |
    v
merge UX: auto-switch + stash
(in lib/commands/merge.sh, uses git_remote.sh)
```

**Recommended build order:**

| Order | Component | Rationale |
|-------|-----------|-----------|
| 1 | `lib/safety.sh` + cleanup bug fix | Fixes critical data-loss bug. No dependencies on other new code. Highest priority. |
| 2 | `lib/cleanup/registry.sh` safety guard | Prevents root registration. Pairs with safety.sh. |
| 3 | `lib/git_remote.sh` | Independent module. No dependencies on safety or guidance. |
| 4 | Merge UX (auto-switch + stash) | Depends on nothing new, but changes the most complex command. Benefits from git_remote.sh being ready for auto-push integration. |
| 5 | Auto-push integration | Wires git_remote.sh into execute.sh and merge.sh. Straightforward once git_remote.sh exists. |
| 6 | `lib/guidance.sh` + all command integration | Touches every command file but is pure output -- no logic changes. Best done last when all other behavior is finalized, so guidance text is accurate. |

**Build order rationale:** Safety first (fixes real data loss), then independent new capabilities (remote, merge UX), then cross-cutting concerns last (guidance touches everything so it should be added when behavior is stable).

## Testing Strategy

| Component | Test Approach |
|-----------|---------------|
| `lib/safety.sh` | Unit tests: assert_safe_to_remove with git toplevel, home, root, valid worktree, non-worktree |
| `lib/cleanup/registry.sh` | Unit test: register_worktree skips when path == toplevel |
| `lib/commands/cleanup.sh` | Integration test: verify rm-rf fallback is gone; verify worktree removal uses safety checks |
| `lib/git_remote.sh` | Unit tests: has_push_remote with/without remote; push_branch with mock git |
| Merge auto-switch | Integration test: start on phase branch, run merge, verify it switches to main |
| Merge stash/unstash | Integration test: dirty worktree, run merge, verify stash created and popped |
| Auto-push | Integration test with a local bare remote: verify push after execute and merge |
| Guidance | Snapshot tests: verify each command prints expected guidance text |

## Sources

- Direct code reading of v1.0 codebase (all files listed above)
- STATE.md pending todos documenting the cleanup data-loss bug, merge UX friction, auto-push requirement, and CLI guidance requirement
- PROJECT.md v1.1 milestone description
- Git documentation: `git stash push -m`, `git worktree remove`, `git remote`

---
*Architecture research for: gsd-ralph v1.1 safety and UX integration*
*Researched: 2026-02-20*
