# Feature Research: v1.1 Stability & Safety

**Domain:** CLI safety guardrails, auto-push, merge UX, and post-command guidance for a Bash CLI developer tool
**Researched:** 2026-02-20
**Confidence:** HIGH

## Context

This research covers the four feature areas targeted for v1.1 of gsd-ralph, a Bash CLI tool that orchestrates autonomous coding agents via git worktrees. v1.0 shipped with 3,695 LOC Bash and full init/execute/merge/cleanup lifecycle. v1.1 focuses on making the tool safe and smooth for developers trying it for the first time.

**Existing features (already built):** init, generate, execute, merge, cleanup, status commands; git worktree isolation; wave-aware merge; registry-driven cleanup; terminal bell; dry-run conflict detection; review mode; rollback safety; auto-resolve of .planning/ conflicts.

**v1.1 scope:** Fix critical cleanup data-loss bug, safety guardrails, auto-push to remote, merge UX improvements, CLI next-step guidance.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that must exist for v1.1 to be considered safe for first-time users.

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| **Fix critical cleanup rm -rf bug** | Cleanup command currently registers `$(pwd)` (project root) as worktree_path in sequential mode. The `rm -rf` fallback on line 180 of cleanup.sh can delete the entire project. This caused real data loss (vibecheck project destroyed). | LOW | None -- standalone fix | Three-part fix: (1) Never use `rm -rf` as fallback for worktree removal. (2) Do not register the main working tree in the registry. (3) Add a safety check that refuses to remove any path matching `git rev-parse --show-toplevel`. Pattern from git itself: `git worktree remove` already refuses to remove the main worktree. Our tool should mirror this built-in safety. |
| **Project root protection guard** | Any CLI tool that runs `rm -rf` on user-provided or computed paths MUST validate against deleting critical directories. This is a fundamental safety expectation -- tools like `safe-rm` and GNU coreutils `--preserve-root` exist specifically for this. | LOW | None | Implement a `safe_remove_path()` function that: (1) resolves the path to an absolute canonical form, (2) checks it against `git rev-parse --show-toplevel`, `$HOME`, and `/`, (3) refuses to proceed if it matches any of these. Apply this to every `rm -rf` call in the codebase. |
| **Merge auto-switch to main** | Current merge command dies with "Not on main branch. Switch to main first: git checkout main" if user is on a phase branch. After `execute` puts the user on a phase branch and Ralph finishes, the very next command (`merge`) fails. This breaks the natural workflow. | LOW | None | Pattern from git ecosystem: `git switch` and `git checkout` handle branch transitions. The merge command should detect the current branch, and if it is a phase branch for the requested phase, automatically switch to main before merging. Print a clear message: "Switching from phase-3/feature to main before merge." |
| **Merge dirty-worktree handling** | Current merge command dies with "Working tree is not clean. Commit or stash changes before merging." Users commonly have uncommitted changes (STATE.md edits, notes). Git itself offers `--autostash` for this pattern. | MEDIUM | Auto-switch (should stash before switching too) | Two approaches: (1) Auto-stash: `git stash push -m "gsd-ralph: auto-stash before merge"`, merge, then `git stash pop`. (2) WIP commit: commit changes with a WIP message, merge, then soft-reset. Auto-stash is the established pattern (git merge --autostash, git rebase --autostash). Use auto-stash with clear messaging: "Stashing 3 uncommitted changes before merge..." and "Restoring stashed changes after merge." Handle stash-pop conflicts gracefully (warn user, keep stash). |
| **CLI next-step guidance** | After every command, users should know what to do next. Git itself does this ("hint: ..." messages). npm does it ("to start your app, run npm start"). GitHub CLI does it (progressive guidance through auth flow). First-time users of gsd-ralph currently get no workflow guidance. | LOW | None -- applies to all commands | Add a `print_next_step()` function called at the end of each command. Context-sensitive output: after `init` -> "Run: gsd-ralph execute 1"; after `execute N` -> "Ralph is ready. Run: ralph"; after merge -> "Run: gsd-ralph cleanup N"; after cleanup -> "Phase N complete. Run: gsd-ralph execute N+1". Use a distinct visual style (e.g., boxed or prefixed with "Next:") so it stands out from regular output. |
| **Auto-push to remote** | If a remote exists, branches should be pushed after `execute` (backup the work) and merged main should be pushed after `merge` (keep remote in sync). This is a safety net against local data loss -- the same scenario that destroyed the vibecheck project. | MEDIUM | Remote detection on init | Detect remote on init: `git remote -v`. If origin exists, enable auto-push. After `execute`: push the phase branch (`git push -u origin $branch_name`). After `merge`: push main (`git push origin main`). After cleanup: push deleted branch refs. Always use non-force push. If push fails (no remote, auth issue, diverged), warn but do not block the local operation. Push is a safety net, not a gate. |

### Differentiators (Competitive Advantage)

Features that go beyond expectations and make v1.1 feel polished.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| **Contextual next-step chain** | Not just "run X next" but awareness of the full workflow state. If phase N-1 is merged, suggest "execute N". If execute N is done but not merged, suggest "merge N". If cleanup is pending, suggest it. Scan the actual state rather than just echoing the command sequence. | MEDIUM | CLI guidance (basic), registry, merge signals | Query the worktree registry and merge signal files to determine actual state. This turns next-step guidance from a static script into an intelligent assistant. No other worktree orchestration tool does this. |
| **Auto-push with opt-out** | Enable auto-push by default when a remote exists, with a config flag to disable it (`auto_push=false` in .ralphrc or .ralph/config.json). Most tools (gh, npm) make push explicit. gsd-ralph making it automatic-but-configurable is a differentiator for safety-first workflows. | LOW | Auto-push (basic) | Store config in .ralph/config.json (already have registry JSON precedent). Check `auto_push` setting before every push. Default: true if remote exists. |
| **Stash restore failure recovery** | When auto-stash before merge results in conflicts on restore, provide clear recovery guidance: show the conflicted files, explain that the stash is preserved, and give the exact commands to resolve. Most tools that auto-stash leave users confused when pop fails. | LOW | Dirty-worktree handling | Git's own autostash reports "Applying autostash resulted in conflicts." We should go further: list the conflicted files, suggest `git stash show` to see what was stashed, and suggest `git checkout --theirs`/`--ours` patterns. |
| **Safety audit trail** | Log every destructive operation (worktree removal, branch deletion, rm commands) to `.ralph/logs/safety-audit.log` with timestamps and paths. If something goes wrong, there is a forensic trail. | LOW | Project root protection | Append-only log file. Pattern: `[2026-02-20T12:00:00Z] REMOVE_WORKTREE path=/tmp/worktree-phase-3 branch=phase-3/feature status=success`. Trivial to implement, high value for debugging and trust-building. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but should NOT be built for v1.1.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Force-push to remote** | "My remote is behind, just force push" | Force-push on main destroys shared history. gsd-ralph should never offer this because it targets the main branch specifically. Non-fast-forward failures should be surfaced to the user to resolve manually. | Warn on push failure. Suggest `git pull --rebase origin main` before retrying. Never offer `--force`. |
| **Auto-commit dirty changes before merge** | "Just commit my stuff so merge can proceed" | Creating junk commits ("WIP", "temp") pollutes git history. These commits end up on main after merge and are hard to clean up. | Auto-stash is the correct pattern. Changes are preserved without creating commits. If the user wants to commit, they should do so explicitly with a meaningful message. |
| **Interactive conflict resolution during merge** | "Let me fix conflicts inline" | gsd-ralph's merge is designed to be automated (auto-resolve known patterns, skip unresolvable). Adding interactive resolution makes the tool require human babysitting, which defeats the autonomous purpose. | Report conflicts clearly with guidance, let the user resolve manually using their preferred editor/tool, then re-run merge. |
| **Auto-cleanup after merge** | "Just clean up automatically when merge succeeds" | Users may want to inspect merged results, check tests, or review the branches before they disappear. Auto-cleanup removes the safety net. | Print next-step guidance: "Merge complete. Run: gsd-ralph cleanup N when ready." Let the user control when cleanup happens. |
| **Push to non-origin remotes** | "I have multiple remotes, push to all of them" | Multi-remote push adds complexity (which remotes? in what order? what if one fails?). The common case is a single origin. | Push to origin only. If users need multi-remote, they can configure git push mirrors or run manual pushes. |
| **Automatic branch protection rules** | "Set up branch protection on the remote" | Requires GitHub/GitLab API integration, auth tokens, and hosting-specific logic. Way out of scope. | Document recommended branch protection settings in README. Keep the tool local-only. |

---

## Feature Dependencies

```
[Fix cleanup rm -rf bug]
    |
    +--requires--> [Project root protection guard]
    |                  (the guard is the fix's core mechanism)
    |
    +--enables---> [Auto-push to remote]
                       (safe to push only after cleanup is safe)

[Merge auto-switch to main]
    |
    +--enhances--> [Merge dirty-worktree handling]
    |                  (switch may also need stash if tree is dirty)
    |
    +--enhances--> [Auto-push to remote]
                       (push main after merge, which now auto-switches)

[CLI next-step guidance]
    |
    +--enhanced-by--> [Contextual next-step chain]
                          (static hints first, then state-aware hints)

[Auto-push to remote]
    |
    +--enhanced-by--> [Auto-push with opt-out config]
                          (basic push first, then configurable)
```

### Dependency Notes

- **Project root protection guard is a prerequisite for the cleanup fix:** The cleanup fix IS the application of the protection guard to the specific buggy code path. Build the guard function first, then apply it.
- **Auto-switch should handle dirty worktrees:** If the user is on a phase branch with uncommitted changes, the switch to main needs stash handling too. Build auto-switch first (it can fail-fast on dirty tree initially), then add stash handling to both switch and merge.
- **CLI guidance is independent but compounds with everything:** Each feature that gets built should include its own next-step hint. Guidance is not a separate phase -- it is woven into every other feature.
- **Auto-push depends on safe cleanup:** If cleanup can destroy the project, pushing beforehand does not help (push happens after merge, not after cleanup). But safe cleanup means push is the final safety net, not the only one.

---

## v1.1 Build Priorities

### Must Have (P1) -- Ship-Blocking

These fix real safety issues or fundamental UX friction. Without these, v1.1 should not ship.

- [x] **Fix cleanup rm -rf bug** -- Prevents data loss. Caused actual destruction.
- [x] **Project root protection guard** -- Fundamental safety. The guard function applied everywhere.
- [x] **Merge auto-switch to main** -- Without this, the workflow is broken after execute.
- [x] **Merge dirty-worktree handling** -- Without this, users hit a wall after any incidental edit.
- [x] **CLI next-step guidance (basic)** -- First-time users need to know what comes next.

### Should Have (P2) -- High Value, Ship Without If Needed

These make v1.1 feel complete and trustworthy.

- [ ] **Auto-push to remote** -- Safety net against local data loss. Important but the tool works without it.
- [ ] **Contextual next-step chain** -- Elevates guidance from static to intelligent. Depends on P1 guidance.

### Nice to Have (P3) -- Polish

- [ ] **Auto-push opt-out config** -- Only needed if auto-push is built.
- [ ] **Stash restore failure recovery** -- Edge case handling for auto-stash.
- [ ] **Safety audit trail** -- Trust-building forensics. Low effort, can be added anytime.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Risk if Skipped | Priority |
|---------|------------|---------------------|-----------------|----------|
| Fix cleanup rm-rf bug | CRITICAL | LOW | Data loss (proven) | P1 |
| Project root protection guard | CRITICAL | LOW | Data loss (systemic) | P1 |
| Merge auto-switch to main | HIGH | LOW | Broken workflow | P1 |
| Merge dirty-worktree handling | HIGH | MEDIUM | Blocked workflow | P1 |
| CLI next-step guidance | HIGH | LOW | Poor first-time experience | P1 |
| Auto-push to remote | MEDIUM | MEDIUM | No remote backup | P2 |
| Contextual next-step chain | MEDIUM | MEDIUM | Static hints only | P2 |
| Auto-push opt-out config | LOW | LOW | No customization | P3 |
| Stash restore failure recovery | LOW | LOW | Confusing edge case | P3 |
| Safety audit trail | LOW | LOW | No forensics | P3 |

---

## Implementation Patterns (From Research)

### Pattern: Project Root Protection Guard

Based on git's own worktree safety (refuses to remove main worktree) and `safe-rm` patterns. HIGH confidence.

```bash
# Safety function: refuse to remove critical paths
safe_remove_path() {
    local target="$1"

    # Resolve to absolute path
    local abs_target
    abs_target=$(cd "$target" 2>/dev/null && pwd) || abs_target="$target"

    # Get git toplevel
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null) || git_root=""

    # Check against protected paths
    if [[ "$abs_target" == "/" ]]; then
        print_error "SAFETY: Refusing to remove root directory"
        return 1
    fi
    if [[ -n "$git_root" && "$abs_target" == "$git_root" ]]; then
        print_error "SAFETY: Refusing to remove git repository root: $abs_target"
        return 1
    fi
    if [[ "$abs_target" == "$HOME" ]]; then
        print_error "SAFETY: Refusing to remove home directory"
        return 1
    fi

    return 0  # Safe to proceed
}
```

### Pattern: Auto-Stash Before Merge

Based on git's built-in `merge.autoStash` and `--autostash` flag. HIGH confidence.

```bash
# Stash if working tree is dirty, merge, then restore
local did_stash=false
local porcelain
porcelain=$(git status --porcelain 2>/dev/null)
if [[ -n "$porcelain" ]]; then
    git stash push -m "gsd-ralph: auto-stash before merge (phase $phase_num)"
    did_stash=true
    print_info "Stashed uncommitted changes before merge"
fi

# ... perform merge ...

if [[ "$did_stash" == true ]]; then
    if git stash pop 2>/dev/null; then
        print_info "Restored stashed changes"
    else
        print_warning "Could not restore stashed changes (conflicts)."
        print_info "Your changes are preserved in: git stash list"
        print_info "To restore manually: git stash pop"
    fi
fi
```

### Pattern: Auto-Switch to Main

Based on git switch behavior and the established workflow pattern. HIGH confidence.

```bash
local current_branch
current_branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
local main_branch=""

if [[ "$current_branch" == "main" ]]; then
    main_branch="main"
elif [[ "$current_branch" == "master" ]]; then
    main_branch="master"
else
    # Check if current branch is a phase branch for the requested phase
    if [[ "$current_branch" == phase-${phase_num}/* ]] || \
       [[ "$current_branch" == phase/${phase_num}/* ]]; then
        # Auto-switch to main
        for candidate in main master; do
            if git show-ref --verify --quiet "refs/heads/$candidate" 2>/dev/null; then
                main_branch="$candidate"
                break
            fi
        done
        if [[ -z "$main_branch" ]]; then
            die "Cannot find main or master branch to switch to."
        fi
        print_info "Switching from '$current_branch' to '$main_branch' before merge"
        git checkout "$main_branch" 2>/dev/null || \
            die "Failed to switch to $main_branch. Resolve any issues and retry."
    else
        die "Not on main branch (currently on '$current_branch'). Switch to main first: git checkout main"
    fi
fi
```

### Pattern: Next-Step Guidance

Based on git hints, npm post-install messages, and GitHub CLI progressive disclosure. HIGH confidence.

```bash
print_next_step() {
    local message="$1"
    printf "\n${GREEN}Next:${NC} %s\n" "$message"
}

# After init:
print_next_step "gsd-ralph execute 1"

# After execute:
print_next_step "Run 'ralph' to start autonomous execution"

# After merge:
print_next_step "gsd-ralph cleanup $phase_num"

# After cleanup (check if next phase exists):
if find_phase_dir "$((phase_num + 1))" 2>/dev/null; then
    print_next_step "gsd-ralph execute $((phase_num + 1))"
else
    print_next_step "All phases complete. Push to remote: git push origin main"
fi
```

### Pattern: Auto-Push to Remote

Based on standard git push patterns and the principle that push is a safety net, not a gate. MEDIUM confidence (behavior when push fails needs testing).

```bash
auto_push_if_configured() {
    local branch="$1"
    local action="$2"  # "execute" or "merge" -- for logging

    # Check if remote exists
    if ! git remote get-url origin >/dev/null 2>&1; then
        print_verbose "No remote 'origin' found, skipping auto-push"
        return 0
    fi

    # Check config opt-out
    if [[ -f ".ralph/config.json" ]]; then
        local auto_push
        auto_push=$(jq -r '.auto_push // true' ".ralph/config.json" 2>/dev/null)
        if [[ "$auto_push" == "false" ]]; then
            print_verbose "Auto-push disabled in config"
            return 0
        fi
    fi

    # Push (non-blocking on failure)
    if git push origin "$branch" 2>/dev/null; then
        print_success "Pushed $branch to origin"
    else
        print_warning "Could not push $branch to origin (non-fatal)"
        print_info "Push manually when ready: git push origin $branch"
    fi
}
```

---

## Competitor Feature Analysis

| Feature | git (native) | lazygit | gh CLI | gsd-ralph v1.1 Approach |
|---------|-------------|---------|--------|-------------------------|
| Root protection | `git worktree remove` refuses main worktree | N/A | N/A | `safe_remove_path()` guard on all rm operations |
| Auto-stash | `--autostash` flag on merge/rebase | Auto-stash on branch switch | N/A | Auto-stash before auto-switch and merge |
| Auto-push | Manual only | Single-key push (`P`) | `gh pr merge --auto` | Auto-push after execute and merge, configurable |
| Branch auto-switch | Manual `git switch` | Single-key switch | N/A | Auto-detect phase branch, switch to main for merge |
| Next-step hints | `hint:` messages since Git 2.28+ | Visual workflow (no hints needed) | Progressive auth flow guidance | `print_next_step()` after every command |
| Dirty-tree handling | Error + message | Auto-stash + visual diff | N/A | Auto-stash with conflict recovery guidance |

---

## Sources

### Authoritative (HIGH confidence)
- [Git worktree documentation](https://git-scm.com/docs/git-worktree) -- Main worktree cannot be removed (built-in safety)
- [Git stash documentation](https://git-scm.com/docs/git-stash) -- Stash patterns and autostash behavior
- [Git merge documentation](https://git-scm.com/docs/git-merge) -- `--autostash` flag behavior
- [Git switch documentation](https://git-scm.com/docs/git-switch) -- Branch switching with `-m` flag for dirty worktrees
- [Git push documentation](https://git-scm.com/docs/git-push) -- Push behavior, non-fast-forward rejection

### Codebase Analysis (HIGH confidence)
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/cleanup.sh` -- Lines 174-183: the rm -rf fallback bug
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/merge.sh` -- Lines 167-177: the hard-coded main branch check
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/merge.sh` -- Lines 180-184: the clean worktree requirement
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/execute.sh` -- Line 160: `register_worktree` with `$(pwd)` as worktree_path
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/cleanup/registry.sh` -- Registry structure and worktree tracking

### Web Research (MEDIUM confidence)
- [safe-rm project](https://github.com/kaelzhang/shell-safe-rm) -- Drop-in rm replacement with path blacklisting
- [Git autostash patterns](https://www.eficode.com/blog/git-autostash) -- Autostash configuration and behavior
- [Git worktree gotchas](https://musteresel.github.io/posts/2018/01/git-worktree-gotcha-removed-directory.html) -- Worktree removal edge cases
- [CLI UX progress patterns](https://evilmartians.com/chronicles/cli-ux-best-practices-3-patterns-for-improving-progress-displays) -- CLI UX best practices

---
*Feature research for: gsd-ralph v1.1 Stability & Safety*
*Researched: 2026-02-20*
