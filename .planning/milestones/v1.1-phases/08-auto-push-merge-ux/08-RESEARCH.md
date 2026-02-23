# Phase 8: Auto-Push & Merge UX - Research

**Researched:** 2026-02-23
**Domain:** Git remote operations, branch management, stash handling (Bash 3.2)
**Confidence:** HIGH

## Summary

Phase 8 adds two complementary features to gsd-ralph: (1) automatic push of branches/main to a remote after execute and merge operations, and (2) improved merge UX so that `gsd-ralph merge N` works regardless of the user's current branch or working tree state. Both features are non-destructive -- push failures produce warnings, not crashes, and auto-stash safely preserves uncommitted work.

The implementation domain is well-understood: `git remote`, `git push`, `git stash`, and `git checkout` are stable, mature git plumbing. The primary complexity is in error handling and state restoration -- ensuring that every code path (success, failure, rollback) correctly restores the user's working tree state. The .ralphrc configuration file already exists but is not currently read by any `lib/` module; a configuration reader must be added.

**Primary recommendation:** Build a shared `lib/push.sh` module for remote detection and push logic, extend the merge command's argument validation to handle branch switching and auto-stash, and add a `.ralphrc` configuration reader to `lib/config.sh` for the `AUTO_PUSH` toggle.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PUSH-01 | Init detects whether a remote exists and records the result for downstream commands | Use `git remote` to detect; store result in `.ralph/` state or check lazily at push time. See "Remote Detection" pattern. |
| PUSH-02 | Execute pushes the phase branch to remote after creation (non-fatal on failure) | Add `push_branch_to_remote` call after branch creation + initial commit in `execute.sh`. See "Push After Execute" pattern. |
| PUSH-03 | Merge pushes main to remote after successful merge (non-fatal on failure) | Add `push_branch_to_remote` call after successful merge + phase completion in `merge.sh`. See "Push After Merge" pattern. |
| PUSH-04 | Auto-push can be disabled via .ralphrc configuration | Read `AUTO_PUSH` from `.ralphrc` using shell `source`. See "Configuration Reading" pattern. |
| MRGX-01 | Merge auto-detects the main branch and switches to it when run from a phase branch | Replace the `die` in merge.sh's main-branch check with `git checkout main/master`. See "Auto-Switch to Main" pattern. |
| MRGX-02 | Merge auto-stashes dirty worktree state before branch switch using apply+drop pattern | Use `git stash push` before branch switch; track stash entry. See "Auto-Stash" pattern. |
| MRGX-03 | Auto-stash is restored after merge completes (success or rollback) | Use `git stash apply && git stash drop` (not `git stash pop`) after merge/rollback. See "Stash Restoration" pattern. |
</phase_requirements>

## Standard Stack

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| git remote | git 2.x+ | Detect remote existence | Built-in git; no dependencies |
| git push | git 2.x+ | Push branches to remote | Built-in git; standard workflow |
| git stash | git 2.x+ | Save/restore dirty working tree | Built-in git; safer than manual add/reset |
| git checkout | git 2.x+ | Switch branches | Built-in git; Bash 3.2 compatible (no `git switch`) |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| git symbolic-ref | git 2.x+ | Detect current branch name | Already used in merge.sh |
| git status --porcelain | git 2.x+ | Detect dirty working tree | Already used in merge.sh |
| source (bash builtin) | bash 3.2+ | Read .ralphrc configuration | Shell-native key=value config reading |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `git checkout` | `git switch` | `git switch` requires git 2.23+; not guaranteed on older macOS |
| `git stash push` | `git stash save` | `push` is modern but `save` is the Bash 3.2-era default; both work on git 2.x |
| Lazy remote detection | Store in `.ralph/remote-state.json` | Lazy check at push time is simpler and avoids stale state |
| `.ralphrc` source | Custom parser | `.ralphrc` is already a valid shell file with KEY="value" format; `source` is trivial |

## Architecture Patterns

### Recommended Module Structure

```
lib/
  push.sh              # NEW: Remote detection + push logic (shared by execute/merge)
  config.sh            # EXTEND: Add load_ralphrc() function
  commands/
    execute.sh         # MODIFY: Add push after branch creation + commit
    merge.sh           # MODIFY: Add auto-switch, auto-stash, push after merge
    init.sh            # MODIFY: Detect remote at init time (PUSH-01)
```

### Pattern 1: Remote Detection (PUSH-01)

**What:** Detect whether `origin` remote exists before attempting push.
**When to use:** Before any `git push` call.
**Example:**

```bash
# lib/push.sh

# Check if a pushable remote exists.
# Returns: 0 if remote "origin" exists, 1 if not
has_remote() {
    git remote get-url origin >/dev/null 2>&1
}
```

**Key detail:** `git remote get-url origin` is cleaner than parsing `git remote -v` output. It returns non-zero if origin does not exist. Available since git 2.7+ (2016), safe for any modern macOS.

### Pattern 2: Non-Fatal Push (PUSH-02, PUSH-03)

**What:** Push a branch to remote, treating failures as warnings.
**When to use:** After execute creates branch, after merge completes.
**Example:**

```bash
# lib/push.sh

# Push the current branch to origin. Non-fatal: warns on failure.
# Args: branch_name
# Returns: 0 always (warnings printed on failure)
push_branch_to_remote() {
    local branch_name="$1"

    # Check configuration
    if [[ "${AUTO_PUSH:-true}" == "false" ]]; then
        print_verbose "Auto-push disabled via configuration"
        return 0
    fi

    # Check remote exists
    if ! has_remote; then
        print_verbose "No remote 'origin' found, skipping push"
        return 0
    fi

    # Attempt push
    if git push -u origin "$branch_name" 2>/dev/null; then
        print_success "Pushed $branch_name to origin"
    else
        print_warning "Failed to push $branch_name to origin (non-fatal)"
    fi

    return 0
}
```

**Key detail:** Always return 0 -- push failures must never crash the command. Use `-u` (set upstream) so future pushes track automatically.

### Pattern 3: Auto-Switch to Main (MRGX-01)

**What:** When merge is run from a non-main branch, auto-detect main branch name and switch.
**When to use:** At the start of `cmd_merge()`.
**Example:**

```bash
# In cmd_merge(), replace the current die() with auto-switch:

local current_branch
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")

# Detect main branch name
local main_branch=""
if git show-ref --verify --quiet "refs/heads/main" 2>/dev/null; then
    main_branch="main"
elif git show-ref --verify --quiet "refs/heads/master" 2>/dev/null; then
    main_branch="master"
else
    die "Cannot find main or master branch"
fi

# Switch to main if not already on it
if [[ "$current_branch" != "$main_branch" ]]; then
    print_info "Currently on '$current_branch', switching to $main_branch..."
    # Auto-stash handled before this point (see Pattern 4)
    git checkout "$main_branch" >/dev/null 2>&1 || \
        die "Failed to switch to $main_branch"
    print_success "Switched to $main_branch"
fi
```

**Key detail:** Use `git show-ref --verify` to detect main branch by existence rather than assuming from current branch name. This handles the case where the user is on a completely unrelated branch.

### Pattern 4: Auto-Stash with apply+drop (MRGX-02, MRGX-03)

**What:** Save dirty working tree state before branch switch, restore after merge.
**When to use:** When merge detects uncommitted changes.
**Example:**

```bash
# Before branch switch or merge:
local did_stash=false

local porcelain
porcelain=$(git status --porcelain 2>/dev/null)
if [[ -n "$porcelain" ]]; then
    print_info "Stashing uncommitted changes..."
    if git stash push -m "gsd-ralph-merge-autostash" >/dev/null 2>&1; then
        did_stash=true
        print_success "Changes stashed"
    else
        die "Failed to stash changes. Commit or discard them manually."
    fi
fi

# ... do merge work ...

# After merge completes (success or rollback):
if [[ "$did_stash" == true ]]; then
    print_info "Restoring stashed changes..."
    if git stash apply >/dev/null 2>&1; then
        git stash drop >/dev/null 2>&1
        print_success "Stashed changes restored"
    else
        print_warning "Could not cleanly restore stashed changes."
        print_warning "Your changes are saved in 'git stash list'. Run: git stash pop"
    fi
fi
```

**Key detail:** Use `apply+drop` rather than `pop` so that if `apply` fails (due to conflicts with merged code), the stash entry is preserved and the user can manually resolve. The stash message `gsd-ralph-merge-autostash` makes it identifiable.

### Pattern 5: Configuration Reading (PUSH-04)

**What:** Read `.ralphrc` to check `AUTO_PUSH` setting.
**When to use:** Before any push attempt.
**Example:**

```bash
# lib/config.sh

# Load project .ralphrc configuration into shell variables.
# Only loads if .ralphrc exists. Silently returns if not found.
# Returns: 0 always
load_ralphrc() {
    local ralphrc_path=".ralphrc"
    if [[ -f "$ralphrc_path" ]]; then
        # Source in a subshell first to validate, then source for real
        # This prevents syntax errors in .ralphrc from crashing gsd-ralph
        if bash -n "$ralphrc_path" 2>/dev/null; then
            # shellcheck source=/dev/null
            source "$ralphrc_path"
        else
            print_warning ".ralphrc has syntax errors, skipping configuration load"
        fi
    fi
    return 0
}
```

**Key detail:** The `.ralphrc` is already a valid Bash file with `KEY="value"` format (generated by `init`). Sourcing it is the simplest approach. Validate syntax with `bash -n` before sourcing to prevent crashes from malformed config. The `AUTO_PUSH` variable defaults to `true` if not set -- push is opt-out, not opt-in.

### Anti-Patterns to Avoid

- **Hard-coding remote name:** Always use `origin` (git default) but check existence first. Do not assume remote exists.
- **Using `git stash pop`:** If `pop` fails, the stash entry is dropped AND the apply fails, losing user data. Use `apply+drop` instead.
- **Crashing on push failure:** Network issues, auth failures, and missing remotes are common. Push must never exit non-zero in a way that aborts the command.
- **Using `git switch`:** Requires git 2.23+. Use `git checkout` for Bash 3.2/older git compatibility.
- **Stashing when working tree is clean:** `git stash push` on a clean tree is a no-op but can create confusing output. Always check `git status --porcelain` first.
- **Forgetting to restore stash on error paths:** Every early-exit path after stashing MUST attempt stash restoration. Use a trap or ensure all code paths converge.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Remote existence detection | Custom URL parsing | `git remote get-url origin` | Handles all remote types (ssh, https, file) |
| Working tree state save/restore | Manual `git add`/`git reset` | `git stash push`/`git stash apply` | Handles untracked files, binary files, submodules |
| Main branch name detection | Hardcoded "main" | `git show-ref --verify refs/heads/main` | Works for both "main" and "master" repos |
| Configuration file parsing | Line-by-line parser | `source .ralphrc` | File is already valid Bash syntax |

**Key insight:** Every operation in this phase has a direct git plumbing command. No custom implementations are needed beyond the orchestration logic.

## Common Pitfalls

### Pitfall 1: Stash Leaks on Error Paths

**What goes wrong:** Changes are stashed but never restored because an early `die()` or `return` skips the restoration code.
**Why it happens:** Multiple exit points in the merge function, especially after rollback or conflict detection.
**How to avoid:** Track `did_stash` as a flag and ensure ALL exit paths (including `die()` calls) check and restore it. Consider a cleanup trap: `trap 'restore_stash_if_needed' EXIT`.
**Warning signs:** User reports "my changes disappeared" after a failed merge.

### Pitfall 2: Push to Wrong Branch

**What goes wrong:** After auto-switching from a phase branch to main, push sends main instead of the phase branch (or vice versa).
**Why it happens:** Push call uses wrong branch name variable, or push is called after checkout has already changed branches.
**How to avoid:** Explicitly name the branch in `git push origin <branch>` -- never rely on implicit current-branch push.
**Warning signs:** Remote shows unexpected branch pushes.

### Pitfall 3: Stash Conflicts After Merge

**What goes wrong:** User had uncommitted changes that conflict with the newly-merged code. `git stash apply` fails.
**Why it happens:** The merge introduced changes to the same files the user was editing.
**How to avoid:** Use `apply+drop` pattern. If `apply` fails, warn the user and tell them to run `git stash pop` manually. Never silently drop the stash.
**Warning signs:** User reports lost uncommitted work.

### Pitfall 4: Detached HEAD After Auto-Switch Failure

**What goes wrong:** `git checkout main` fails (e.g., main was deleted), leaving the user on a detached HEAD or the original branch with stashed changes.
**Why it happens:** Unusual repository states, rebased/force-pushed main.
**How to avoid:** Check `git checkout` exit code. On failure, restore stash immediately and die with a clear message.
**Warning signs:** User reports being on detached HEAD after merge attempt.

### Pitfall 5: .ralphrc Not Read at the Right Time

**What goes wrong:** `AUTO_PUSH` variable is checked before `.ralphrc` is sourced, so push happens even when disabled.
**Why it happens:** `load_ralphrc()` is called too late in the command flow, or not called at all.
**How to avoid:** Call `load_ralphrc()` early in both `cmd_execute()` and `cmd_merge()`, before any push logic.
**Warning signs:** Auto-push happens despite `.ralphrc` containing `AUTO_PUSH=false`.

### Pitfall 6: Init Remote Detection Becomes Stale

**What goes wrong:** Remote is detected at `init` time but the user adds/removes a remote later.
**Why it happens:** Storing remote state at init and never re-checking.
**How to avoid:** Perform lazy detection at push time (check `has_remote()` before each push). The init-time detection (PUSH-01) can be informational only.
**Warning signs:** Push silently skipped despite remote existing, or push attempted despite remote removed.

## Code Examples

### Complete Push Module (lib/push.sh)

```bash
#!/bin/bash
# lib/push.sh -- Remote detection and push operations

# Check if a pushable remote "origin" exists.
# Returns: 0 if origin remote exists, 1 if not
has_remote() {
    git remote get-url origin >/dev/null 2>&1
}

# Push a branch to origin. Non-fatal: warns on failure, never exits.
# Respects AUTO_PUSH configuration (defaults to true).
# Args: branch_name
# Returns: 0 always
push_branch_to_remote() {
    local branch_name="$1"

    if [[ "${AUTO_PUSH:-true}" == "false" ]]; then
        print_verbose "Auto-push disabled via .ralphrc"
        return 0
    fi

    if ! has_remote; then
        print_verbose "No remote 'origin' configured, skipping push"
        return 0
    fi

    print_info "Pushing $branch_name to origin..."
    if git push -u origin "$branch_name" >/dev/null 2>&1; then
        print_success "Pushed $branch_name to origin"
    else
        print_warning "Could not push $branch_name to origin (network issue or auth failure)"
        print_warning "Branch is still available locally. Push manually with: git push origin $branch_name"
    fi

    return 0
}
```

### Auto-Stash Guard Pattern

```bash
# At the top of cmd_merge, after argument parsing:
local did_stash=false

# Check for dirty working tree -- stash instead of dying
local porcelain
porcelain=$(git status --porcelain 2>/dev/null)
if [[ -n "$porcelain" ]]; then
    print_info "Uncommitted changes detected, auto-stashing..."
    if git stash push -m "gsd-ralph-merge-autostash" >/dev/null 2>&1; then
        did_stash=true
        print_success "Changes stashed"
    else
        die "Failed to stash uncommitted changes"
    fi
fi

# ... merge logic ...

# At the end of cmd_merge (all exit paths):
if [[ "$did_stash" == true ]]; then
    print_info "Restoring auto-stashed changes..."
    if git stash apply >/dev/null 2>&1; then
        git stash drop >/dev/null 2>&1
        print_success "Stashed changes restored"
    else
        print_warning "Stash conflicts with merged changes. Your changes are safe in: git stash list"
        print_warning "Resolve with: git stash pop"
    fi
fi
```

### Configuration Loading

```bash
# In lib/config.sh, add:

load_ralphrc() {
    local ralphrc_path=".ralphrc"
    if [[ -f "$ralphrc_path" ]]; then
        if bash -n "$ralphrc_path" 2>/dev/null; then
            source "$ralphrc_path"
        else
            print_warning ".ralphrc has syntax errors, using defaults"
        fi
    fi
    # Set defaults for any missing values
    AUTO_PUSH="${AUTO_PUSH:-true}"
    return 0
}
```

### .ralphrc Template Addition

```bash
# Add to templates/ralphrc.template:

# =============================================================================
# AUTO-PUSH SETTINGS
# =============================================================================

# Automatically push branches to remote after execute and merge.
# Set to false to disable. Requires a configured 'origin' remote.
AUTO_PUSH=true
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `git stash save` | `git stash push` | git 2.13 (2017) | `push` supports `--message`, pathspec; `save` deprecated but still works |
| `git checkout` | `git switch` / `git restore` | git 2.23 (2019) | For Bash 3.2 compat, `git checkout` is still correct choice |
| Manual merge from main only | Auto-switch to main from any branch | This phase | Removes friction for users who forget to checkout main |

**Deprecated/outdated:**
- `git stash save`: Still works but `git stash push` is the modern replacement. Since git 2.13+ is standard on macOS (Xcode CLT ships 2.30+), `push` is safe to use.
- `git remote show origin`: Heavier than `git remote get-url origin` (makes network call). Use `get-url` for existence check.

## Open Questions

1. **Should PUSH-01 record remote state persistently?**
   - What we know: The requirement says "records the result for downstream commands." Currently, lazy detection at push time is simpler and avoids stale state.
   - What's unclear: Whether the intent is a persisted JSON record or just in-memory state passed to push functions.
   - Recommendation: Implement lazy detection (`has_remote()` called at push time) and add an informational message during `init` that reports remote status. No persistent file needed -- this satisfies the spirit of PUSH-01 while avoiding staleness.

2. **Should auto-stash work during rollback?**
   - What we know: MRGX-03 says "restored after merge completes (success or rollback)." The rollback path in `rollback_merge()` does `git reset --hard` which would obliterate the stash-restored changes.
   - What's unclear: Whether stash should be restored before or after rollback, or whether rollback should skip stash restoration.
   - Recommendation: Restore stash after rollback. The `git reset --hard` only affects committed state; stash apply adds uncommitted changes on top. This matches user expectation: "my uncommitted changes should survive the operation."

3. **Should `git stash push` include `--include-untracked`?**
   - What we know: `git stash push` by default only stashes tracked modified files. Untracked files would be left behind during checkout.
   - What's unclear: Whether users commonly have untracked files when running merge.
   - Recommendation: Use `--include-untracked` to be safe. Untracked files left behind during branch switch can cause "would be overwritten" errors.

## Sources

### Primary (HIGH confidence)
- Codebase analysis: `lib/commands/merge.sh`, `lib/commands/execute.sh`, `lib/commands/init.sh`, `lib/config.sh`, `lib/merge/rollback.sh` -- direct inspection of current implementation
- Codebase analysis: `tests/merge.bats`, `tests/execute.bats` -- existing test patterns and assertions
- Codebase analysis: `.ralphrc`, `templates/ralphrc.template` -- configuration format and conventions
- Git documentation: `git-remote`, `git-push`, `git-stash`, `git-checkout` -- stable, well-documented commands

### Secondary (MEDIUM confidence)
- Codebase analysis: `scripts/ralph-merge.sh` (legacy) -- shows prior art for auto-switching to main (`git checkout main 2>/dev/null || git checkout master`)
- Bash 3.2 compatibility: Confirmed via `bash --version` on target system (3.2.57)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All git plumbing commands, no external dependencies
- Architecture: HIGH - Clear modification points in existing modules; patterns proven in legacy scripts
- Pitfalls: HIGH - Error handling patterns well-understood from existing merge/rollback code

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (stable domain, git APIs do not change frequently)
