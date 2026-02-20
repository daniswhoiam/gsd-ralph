# Pitfalls Research

**Domain:** Adding safety guardrails, auto-push, merge UX, and CLI guidance to existing Bash CLI tool
**Researched:** 2026-02-20
**Confidence:** HIGH (grounded in actual codebase bugs, known incident, and verified Bash/Git documentation)

## Critical Pitfalls

### Pitfall 1: Incomplete rm-rf Guard Allows New Deletion Vectors

**What goes wrong:**
The fix for the known `rm -rf` data loss bug (cleanup.sh line 179-181) gets scoped too narrowly -- guarding only the exact code path that caused the vibecheck incident while leaving other `rm -rf` or `rm -f` calls unprotected. The codebase currently has multiple `rm` invocations: `rm -rf "$wt_path"` (cleanup.sh:180), `rm -f` for signal files (cleanup.sh:216), and `rm -f` for rollback files (cleanup.sh:224, rollback.sh:78). A fix that only patches cleanup.sh:180 without establishing a centralized path-safety function leaves the door open for future code to introduce new unguarded deletion paths.

**Why it happens:**
Developers fix the symptom (this specific `rm -rf` call) rather than the root cause (no centralized path validation before any destructive filesystem operation). Bash scripts tend to accumulate ad-hoc `rm` calls as features are added, and without a shared guard function, each new `rm` is a potential data-loss vector.

**How to avoid:**
Create a single `safe_remove()` function in `lib/common.sh` that ALL file/directory removal must go through. This function should:
1. Resolve the target path to an absolute path using `realpath` or `cd && pwd`
2. Compare against `git rev-parse --show-toplevel` -- refuse to delete if the path IS the git toplevel or a parent of it
3. Refuse to delete paths outside the git repo entirely (prevents `/`, `$HOME`, etc.)
4. Refuse to delete if the path is empty or unset (the `rm -rf ""` edge case that becomes `rm -rf .` on some shells)
5. Log what is being deleted (path and reason) before executing
Then grep the entire codebase for raw `rm` calls and replace them all with `safe_remove()`.

**Warning signs:**
- Any raw `rm -rf` or `rm -r` in the codebase outside of `safe_remove()`
- ShellCheck or grep audit showing unguarded deletion calls
- Test fixtures that mock `rm` rather than testing actual path validation logic

**Phase to address:**
First phase (safety guardrails). This is the highest-priority fix and the foundation that all other cleanup logic depends on.

---

### Pitfall 2: Auto-Push Runs Before Data Loss Guard Is in Place

**What goes wrong:**
If auto-push is implemented before the cleanup safety fix, there is a window where auto-push creates a false sense of security ("my branch is on the remote, I am safe") while the local `rm -rf` bug can still destroy the working tree, uncommitted work, and files outside the git repo. Auto-push protects against data loss from missing remote backups but does NOT protect against the cleanup command deleting the project directory itself.

**Why it happens:**
Auto-push and safety guardrails are both part of v1.1 and might be developed in parallel or in the wrong order. The auto-push feature feels more exciting to build and has clear UX benefits, so developers naturally gravitate toward it first.

**How to avoid:**
Enforce phase ordering: safety guardrails (rm-rf fix, path validation) MUST ship before or in the same phase as auto-push. The cleanup command should be fixed and tested before any new features that create a false safety impression. The roadmap should make this dependency explicit.

**Warning signs:**
- Auto-push code is being reviewed before the `safe_remove()` function exists
- Tests for auto-push pass but cleanup safety tests are not yet written
- STATE.md shows auto-push as "complete" while cleanup fix is still "in progress"

**Phase to address:**
Roadmap structure -- the safety guardrails phase must precede or be part of the same phase as auto-push. Never ship auto-push alone.

---

### Pitfall 3: Auto-Push with No Remote or Broken Auth Crashes the Workflow

**What goes wrong:**
Auto-push after `execute` or `merge` fails because: (a) no remote is configured (`git remote` returns empty), (b) the remote URL uses HTTPS but the user relies on an expired Personal Access Token or no credential helper, (c) SSH key is not loaded in the agent, or (d) the remote repo does not exist yet. The push failure causes the entire `execute` or `merge` command to exit non-zero (due to `set -e`), aborting the workflow even though the local git operations succeeded perfectly.

**Why it happens:**
`set -euo pipefail` (already present in `bin/gsd-ralph` line 7) means any failed `git push` propagates as a fatal error. Many developers test auto-push only in their own environment where SSH keys are loaded and remotes are configured, missing the first-time-user scenario where the repo was just `git init`-ed locally.

**How to avoid:**
1. Make auto-push best-effort, not mandatory. Detect remote existence with `git remote -v` before attempting push. If no remote exists, print a clear info message ("No remote configured. Skipping auto-push. Your work is safe locally.") and continue.
2. Wrap `git push` in a function that captures the exit code separately, outside of `set -e` context, using `if git push ...; then ... else ... fi` pattern.
3. On auth failure, catch the specific error and print guidance: "Push failed (authentication). Check your SSH key or Personal Access Token."
4. Never let a push failure abort a successful local operation. The user's branch/merge was created successfully -- losing that because push failed is worse than not pushing at all.

**Warning signs:**
- Auto-push tests only run in CI with pre-configured credentials
- No test case for "remote does not exist"
- No test case for "push authentication failure"
- `git push` called directly without error capture wrapper

**Phase to address:**
Auto-push implementation phase. Must be designed as best-effort from the start, not bolted on with error handling later.

---

### Pitfall 4: Auto-Push Force-Pushes or Overwrites Remote Branches

**What goes wrong:**
During auto-push after merge, the local main branch has been force-updated (via rollback `git reset --hard`), and the next push attempt gets a non-fast-forward rejection. A naive retry with `git push --force` overwrites the remote branch, potentially destroying other developers' work. Or: during execute, a branch name collision with a remote branch causes push to fail, and force-push overwrites the remote version.

**Why it happens:**
The rollback mechanism (rollback.sh:77) uses `git reset --hard`, which rewrites local history. If auto-push already pushed the pre-rollback state, the post-rollback state is behind the remote. Without careful handling, the "fix" is `--force`. Additionally, branch naming is deterministic (`phase-N/slug`), so if someone re-executes a phase, the branch name collides.

**How to avoid:**
1. NEVER use `git push --force` in auto-push. If push fails with non-fast-forward, print a warning and skip.
2. After rollback, detect that the remote is ahead and print explicit guidance: "Remote has the pre-rollback state. Use `git push --force-with-lease` manually if you want to update the remote."
3. Before auto-push of branches, check if the remote branch already exists with `git ls-remote --heads origin "$branch_name"`. If it does, compare with local and warn on divergence rather than silently overwriting.
4. Use `--force-with-lease` if force-push is ever needed, and never automate it -- always require explicit user action.

**Warning signs:**
- Any occurrence of `git push --force` or `git push -f` in the codebase
- Auto-push logic that does not check remote branch state before pushing
- No test for the "rollback then push" sequence

**Phase to address:**
Auto-push implementation phase. Force-push prevention must be a design constraint from the start.

---

### Pitfall 5: Merge Auto-Switch to Main Loses Uncommitted Work

**What goes wrong:**
The merge UX improvement auto-switches from the phase branch to main before merging. If the user has uncommitted changes on the phase branch (Ralph crashed mid-work, user made manual edits), the auto-switch either (a) fails because Git refuses to switch with a dirty worktree, or (b) succeeds but carries over uncommitted changes to main (Git allows this when changes do not conflict with the target branch), causing the merge to operate on a dirty state with unrelated modifications staged.

**Why it happens:**
The current merge command (merge.sh:176-177) explicitly dies if not on main and dies if the working tree is not clean (merge.sh:181-184). These are separate, sequential checks. An "auto-switch" feature would need to combine them: stash, switch, merge, pop stash. But `git stash pop` can itself fail with merge conflicts, and the state recovery from a failed stash pop mid-merge is extremely complex.

**How to avoid:**
1. Check for dirty worktree BEFORE attempting any branch switch. If dirty: offer two options -- (a) auto-stash and switch, or (b) abort with guidance to commit or stash manually.
2. If auto-stash is used, prefer `git stash push -m "gsd-ralph: auto-stash before merge"` with a recognizable message.
3. After merge completes, attempt `git stash pop`. If pop conflicts, do NOT abort -- leave the stash in place and print: "Your stashed changes conflict with the merge. Run `git stash pop` manually and resolve."
4. NEVER silently discard uncommitted work. Every code path that touches the working tree must account for dirty state.
5. Consider whether auto-switch should only be offered when the worktree is clean, and dirty-worktree handling is a separate prompt.

**Warning signs:**
- Auto-switch implementation that does not check `git status --porcelain` first
- Missing test case for "dirty worktree + auto-switch + stash pop conflict"
- Stash operations without a recognizable message prefix (makes debugging hard)

**Phase to address:**
Merge UX phase. This is the most complex UX improvement and needs careful state-machine design.

---

### Pitfall 6: Registry Path Stored as Relative, Resolved Differently Across Commands

**What goes wrong:**
The worktree registry (registry.sh) stores `worktree_path` as whatever is passed to `register_worktree()`. Currently, `execute.sh:160` passes `$(pwd)` which is an absolute path, but it is the PROJECT ROOT (not a worktree directory) in sequential mode. If the safety fix changes this to store the actual worktree path, but `cleanup.sh` still reads the old-format registry entries, the path mismatch causes cleanup to target wrong directories or fail silently.

**Why it happens:**
The registry was designed for parallel-worktree mode (where each plan gets its own worktree directory) but sequential mode reuses the main working tree. This impedance mismatch means the registry entry for sequential mode has always been semantically wrong -- `worktree_path` is the project root, not a separate worktree. Fixing this without a migration strategy breaks existing registries.

**How to avoid:**
1. Add a `mode` field to registry entries: `"sequential"` or `"parallel"`. Sequential entries should NOT have worktree removal attempted -- only branch cleanup.
2. When reading registry entries, always resolve paths to absolute before comparison. Use `realpath` or `cd "$path" && pwd` with existence checks.
3. Add a registry version migration: if `version: 1` entries exist without a `mode` field, treat them as sequential (safe default -- do not attempt directory removal).
4. Validate that the path in the registry actually IS a git worktree (not the main working tree) before attempting removal: `git worktree list --porcelain | grep "worktree $path"`.

**Warning signs:**
- Tests only test parallel-mode registry entries
- No migration path for existing v1 registries
- Path comparison using string equality instead of resolved absolute paths

**Phase to address:**
Safety guardrails phase (fixing the cleanup bug requires fixing the registry semantics).

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Inline `rm` calls without guard function | Faster to write | Every new `rm` is a potential data-loss bug | Never -- always use `safe_remove()` after v1.1 |
| Auto-push with bare `git push` (no error wrapper) | Simple implementation | Crashes workflow on auth failure, confusing error messages | Never -- always wrap with error capture |
| Storing `$(pwd)` as worktree path in sequential mode | Works for the happy path | Cleanup targets project root, causes data loss | Never -- distinguish sequential vs parallel mode |
| Using `git stash` without checking pop result | Simpler auto-switch code | Silent data loss when stash pop conflicts | Only for truly disposable changes (generated files) |
| Hardcoding "main" / "master" detection | Works for most repos | Fails for repos with custom default branch names (e.g., "develop", "trunk") | Only during MVP; replace with `git symbolic-ref refs/remotes/origin/HEAD` detection |
| Adding CLI guidance as hardcoded strings in each command | Fast to implement | Guidance becomes stale when commands change, inconsistencies across commands | Only during initial implementation; extract to guidance module later |

## Integration Gotchas

Common mistakes when connecting to external services and systems.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Git remote (auto-push) | Assuming remote always exists | Check `git remote -v` first; skip gracefully if empty |
| Git remote (auth) | Assuming credentials are always available | Catch auth errors specifically; provide SSH vs HTTPS guidance |
| Git credential manager | Expecting first push to always work | Known bug: first push fails with some credential managers; implement single retry |
| Git worktree subsystem | Using `rm -rf` as fallback when `git worktree remove` fails | Never fall back to raw `rm`; diagnose why `git worktree remove` failed instead |
| Existing worktree registry (v1 format) | Assuming all entries have new fields | Version-check and migrate; default safely for unknown entries |
| Ralph execution environment | Auto-pushing while Ralph is still committing on the branch | Only auto-push after explicit completion signal, never during execution |

## Security Mistakes

Domain-specific security issues for a CLI tool that manipulates git repos and filesystems.

| Mistake | Risk | Prevention |
|---------|------|------------|
| `rm -rf "$path"` where `$path` is unset or empty | On some shells, this becomes `rm -rf .` or `rm -rf /` -- deleting current directory or entire filesystem | Always validate `$path` is non-empty and within expected bounds before deletion |
| Storing PAT in git remote URL (`https://user:token@github.com/...`) | Token visible in `.git/config`, in `git remote -v` output, in process list | Use credential helpers; never embed tokens in URLs programmatically |
| `git push --force` in automated scripts | Overwrites remote history, destroys other developers' work | Never automate force-push; use `--force-with-lease` only with explicit user consent |
| Phase branch names derived from unsanitized user input | If phase directory names contain shell metacharacters, branch operations could be injected | Validate phase directory names against `^[0-9][0-9]-[a-zA-Z0-9_-]+$` before use in git commands |
| Signal and rollback files written to `.ralph/` without permission checks | Malicious `.ralph/` files could alter merge behavior if someone commits crafted JSON | Validate JSON structure before trusting rollback/signal files; reject unexpected fields |

## UX Pitfalls

Common user experience mistakes when adding guidance and improving CLI flow.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Every command prints "next step" guidance | Information overload; users stop reading output ("banner blindness") | Show next-step guidance only on terminal commands in a workflow (execute, merge, cleanup), not on status or help |
| Guidance is too verbose (multi-line instructions) | Users skim and miss the actual command they need to run | One line: the command to run. One line: why. No more. |
| Guidance assumes linear workflow (always "run merge next") | Confuses users who skip steps or run commands out of order | Detect current state and give context-aware guidance (e.g., "branch exists but no commits yet -- run ralph to start") |
| Auto-stash warning message is technical ("stash@{0}: WIP on...") | Non-git-experts do not understand what happened to their changes | Translate: "Your uncommitted changes were saved. They will be restored after the merge." |
| Verbose mode shows too much git internals | Users enable --verbose for slightly more info, get flooded with git plumbing output | Tier verbosity: default (progress + guidance), --verbose (git commands being run), --debug (full git output) |
| Success messages obscure warnings | "Phase 3 merge complete!" printed after warnings about skipped branches | Print summary table last with clear status per branch, then the overall result, then guidance |
| Auto-push failure message is alarming | "ERROR: Push failed!" makes users think their merge was lost | Use INFO level: "Push to remote skipped (no remote configured). Your merge is safe locally." |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Cleanup safety fix:** Guard added for `rm -rf` in cleanup.sh -- but grep the ENTIRE codebase for other raw `rm` calls that need the same guard
- [ ] **Auto-push after execute:** Pushes the branch -- but does NOT push after each Ralph commit. Only the initial branch creation is pushed. If Ralph crashes before pushing, work is only local
- [ ] **Auto-push after merge:** Pushes main -- but does NOT handle the case where another developer pushed to main between the merge and the push (non-fast-forward)
- [ ] **Merge auto-switch:** Switches to main and merges -- but does NOT switch back to the original branch afterward (user expects to be back where they started)
- [ ] **Stash handling:** Stashes before switch -- but does NOT handle the case where the stash ref is lost if a `git stash clear` runs between stash-push and stash-pop
- [ ] **CLI guidance:** "Run merge next" guidance added -- but does NOT account for multi-wave phases where the user needs to wait for wave N before merging
- [ ] **Path validation:** Validates that path is not git toplevel -- but does NOT handle symlinks (a symlink to the git root would pass the string comparison but delete the real directory)
- [ ] **Registry migration:** New format handles sequential vs parallel mode -- but old v1 registry entries from v1.0 users would not have the new fields and could cause parse errors in the new code

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| `rm -rf` deletes project directory | HIGH (if no remote) / LOW (if pushed) | Restore from remote: `git clone`. Restore uncommitted work: not possible. This is why auto-push matters. |
| Auto-push force-overwrites remote branch | MEDIUM | Use `git reflog` on the remote (if accessible) or contact hosting provider for branch restore. GitHub retains force-pushed refs for ~90 days. |
| Stash pop conflicts during auto-switch | LOW | Stash is preserved on conflict. Run `git stash show -p` to see changes, resolve manually, then `git stash drop`. |
| Registry has stale/wrong paths | LOW | Delete `.ralph/worktree-registry.json` and run `git worktree prune`. Manual cleanup of branches with `git branch -d`. |
| Push fails mid-workflow | LOW | Local state is fine. Fix credentials/remote config and run `git push` manually. |
| Merge auto-switch leaves user on wrong branch | LOW | Run `git checkout <original-branch>` manually. |
| Verbose output floods terminal | LOW | Redirect output: `gsd-ralph merge 3 2>&1 | less`. Or use default (non-verbose) mode. |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Incomplete rm-rf guard (Pitfall 1) | Safety Guardrails (Phase 1) | `grep -rn "rm -rf\|rm -r " lib/ bin/ scripts/` returns zero results outside `safe_remove()` |
| Auto-push before safety fix (Pitfall 2) | Roadmap ordering | Safety guardrails phase is listed before auto-push phase in ROADMAP.md |
| Auto-push crashes on no remote (Pitfall 3) | Auto-Push (Phase 2) | Bats test: `test_auto_push_no_remote_skips_gracefully` passes |
| Auto-push force-overwrites remote (Pitfall 4) | Auto-Push (Phase 2) | `grep -rn "push --force\|push -f" lib/` returns zero results |
| Merge auto-switch loses work (Pitfall 5) | Merge UX (Phase 3) | Bats test: `test_merge_auto_switch_dirty_worktree_stashes_and_restores` passes |
| Registry path mismatch (Pitfall 6) | Safety Guardrails (Phase 1) | Registry entries from sequential mode do not trigger worktree directory removal |
| CLI guidance noise (UX Pitfalls) | CLI Guidance (Phase 4) | Manual review: each command outputs at most 2 lines of guidance after completion |
| Hardcoded main/master detection | Merge UX (Phase 3) | Bats test: repo with `trunk` as default branch works correctly |

## Sources

- Actual codebase analysis: `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/cleanup.sh` lines 174-183 (the rm-rf fallback)
- Actual codebase analysis: `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/merge.sh` lines 168-184 (branch and worktree validation)
- Actual codebase analysis: `/Users/daniswhoiam/Projects/gsd-ralph/lib/cleanup/registry.sh` (registry format and storage)
- Known incident documented in `.planning/STATE.md` (vibecheck project data loss)
- [Git Worktree Documentation](https://git-scm.com/docs/git-worktree) -- worktree remove safety behavior
- [Git Push Documentation](https://git-scm.com/docs/git-push) -- fast-forward rules, force-push behavior
- [Git Stash Documentation](https://git-scm.com/docs/git-stash) -- stash pop conflict behavior, stash not dropped on conflict
- [Bash Scripting Best Practices for Reliable Automation](https://oneuptime.com/blog/post/2026-02-13-bash-best-practices/view) -- set -euo pipefail implications
- [How to write better Bash than ChatGPT](https://www.simplermachines.com/how-to-write-better-bash-than-chatgpt/) -- variable quoting, error handling
- [shell-safe-rm](https://github.com/kaelzhang/shell-safe-rm) -- safe-rm wrapper patterns
- [Destructive Command Guard](https://github.com/Dicklesworthstone/destructive_command_guard) -- automated destructive command prevention
- [Git auto-push upstream handling](https://betterdev.blog/git-branch-first-push-without-errors/) -- push.autoSetupRemote configuration
- [Git stash merge conflicts](https://labex.io/tutorials/git-how-to-resolve-stash-merge-conflicts-418260) -- stash pop edge cases
- [Resolving Merge Conflict after Git Stash Pop](https://jdhao.github.io/2019/12/03/git_stash_merge_conflict_handling/) -- stash not removed on conflict behavior
- [The CLI's Essential Verbose Option](https://dojofive.com/blog/the-clis-essential-verbose-option/) -- verbosity level design patterns

---
*Pitfalls research for: gsd-ralph v1.1 Stability and Safety milestone*
*Researched: 2026-02-20*
