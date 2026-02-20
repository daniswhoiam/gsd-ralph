# Stack Research: v1.1 Stability & Safety

**Domain:** Bash CLI tool safety hardening, UX improvements
**Researched:** 2026-02-20
**Confidence:** HIGH

**Scope:** This document covers ONLY the stack additions/changes needed for v1.1 features. The existing v1.0 stack (Bash 3.2, git, jq, python3, bats-core, ShellCheck) is validated and unchanged. See `milestones/v1.0-REQUIREMENTS.md` and the git history for v1.0 stack decisions.

## Core Finding: No New Dependencies Required

All v1.1 features can be implemented using **existing tools already in the stack** (Bash 3.2 builtins, git, jq). No new binaries, libraries, or runtime dependencies are needed. This is the correct outcome for a stability milestone -- adding dependencies to a stability release would be contradictory.

## Feature-by-Feature Stack Requirements

### 1. Safety Guardrails (Cleanup Data-Loss Bug)

**The bug:** `execute.sh` line 160 calls `register_worktree "$phase_num" "$(pwd)" "$branch_name"` in sequential mode. In sequential mode, `$(pwd)` is the project root (not a worktree). When cleanup runs, `git worktree remove` fails on the main working tree, and the `rm -rf` fallback on line 180 of `cleanup.sh` deletes the entire project directory.

**Stack needed:** Pure Bash builtins only.

| Technique | Purpose | Why | Confidence |
|-----------|---------|-----|------------|
| `git rev-parse --show-toplevel` | Get canonical project root path | Already used elsewhere in the codebase. Returns the absolute path of the repo root | HIGH |
| `git rev-parse --git-dir` vs `--git-common-dir` | Detect main worktree vs linked worktree | If both return the same value, you are in the main worktree. If they differ, you are in a linked worktree. Available in git 2.13+ | HIGH |
| `[[ "$path1" -ef "$path2" ]]` | Inode-level path comparison | Compares filesystem inodes, ignoring symlinks, trailing slashes, and relative vs absolute differences. Works in Bash 3.2 on macOS. Verified on darwin24/arm64 | HIGH |
| `cd "$dir" && pwd -P` | Resolve symlinks to canonical path | Pure Bash builtin, no external tools. `-P` flag resolves symlinks. Use for path normalization before string comparison | HIGH |

**What NOT to use:**

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `realpath` | Not available on macOS by default (requires coreutils from Homebrew) | `cd "$dir" && pwd -P` or `[[ -ef ]]` |
| `readlink -f` | BSD `readlink` on macOS does not support `-f` flag | `cd "$dir" && pwd -P` for resolution |
| `rm -rf` as fallback for worktree removal | This is the root cause of the critical bug. Never use rm -rf on paths from a registry | `git worktree remove --force` only; if that fails, error out instead of falling back to rm -rf |

**Implementation pattern -- safe deletion guard:**

```bash
# Guard: refuse to remove the git toplevel directory
is_project_root() {
    local target_path="$1"
    local toplevel
    toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
    [[ "$target_path" -ef "$toplevel" ]]
}

# In cleanup: replace rm -rf fallback
if is_project_root "$wt_path"; then
    print_error "SAFETY: Refusing to remove project root directory: $wt_path"
    print_error "This entry was incorrectly registered. Skipping."
    continue
fi
# If git worktree remove fails and it's NOT the project root,
# still do NOT rm -rf. Just report the failure.
```

**Registration fix -- don't register main worktree:**

```bash
# In execute.sh: only register if we actually created a worktree
# Sequential mode creates a branch in the main worktree, not a separate worktree
local git_toplevel
git_toplevel=$(git rev-parse --show-toplevel)
if [[ "$(pwd)" -ef "$git_toplevel" ]]; then
    # Sequential mode: register with a sentinel value or skip registration
    register_worktree "$phase_num" "__MAIN_WORKTREE__" "$branch_name"
else
    register_worktree "$phase_num" "$(pwd)" "$branch_name"
fi
```

### 2. Auto-Push to Remote

**Stack needed:** git only (already in stack).

| Technique | Purpose | Why | Confidence |
|-----------|---------|-----|------------|
| `git remote` | Detect if a remote exists | Returns 0 with output if remotes configured, empty output if none. Already a standard git command | HIGH |
| `git push -u origin <branch>` | Push branch and set upstream | The `-u` flag sets up tracking. Available in all supported git versions. Use explicit remote name ("origin") rather than relying on config | HIGH |
| `git push origin <main-branch>` | Push merged results | Push after successful merge. Use the detected main branch name (main/master) | HIGH |
| `git config --get remote.origin.url` | Verify remote is reachable | Check remote URL exists before attempting push. Avoids cryptic errors | HIGH |

**What NOT to use:**

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `push.autoSetupRemote` config | Requires git 2.37+; modifying user's git config is invasive. The tool should not alter global or even local git configuration | Explicit `git push -u origin <branch>` with the branch name |
| `git push --all` | Pushes ALL local branches, not just the one we created. Dangerous side effect | Push only the specific branch by name |
| `git push --force` | Never force-push in an automation tool. Risk of data loss on remote | Standard `git push`; if it fails, report and let user resolve |

**Implementation pattern:**

```bash
has_remote() {
    local remote_count
    remote_count=$(git remote 2>/dev/null | wc -l | tr -d ' ')
    [[ "$remote_count" -gt 0 ]]
}

auto_push_branch() {
    local branch="$1"
    if ! has_remote; then
        print_verbose "No remote configured, skipping push"
        return 0
    fi
    if git push -u origin "$branch" 2>/dev/null; then
        print_success "Pushed $branch to origin"
    else
        print_warning "Failed to push $branch to origin (non-fatal)"
        # Non-fatal: push failure should not block local workflow
    fi
}
```

**Key design decision:** Push failures are **warnings, not errors**. The tool must work fully offline. Push is a convenience/safety-net feature, not a requirement. If the remote is unreachable, the user sees a warning but their local workflow proceeds uninterrupted.

### 3. Improved Merge UX (Auto-Switch, Stash Handling)

**Stack needed:** git only (already in stack).

| Technique | Purpose | Why | Confidence |
|-----------|---------|-----|------------|
| `git symbolic-ref --short HEAD` | Detect current branch | Already used in merge.sh line 169. Returns current branch name or fails if detached | HIGH |
| `git checkout <main-branch>` | Auto-switch to main | Replace the `die` on line 176 of merge.sh with an automatic checkout. Simple, well-understood | HIGH |
| `git status --porcelain` | Detect dirty working tree | Already used in merge.sh line 181. Returns non-empty if there are uncommitted changes | HIGH |
| `git stash push -m "gsd-ralph: auto-stash before merge"` | Auto-stash dirty changes | `git stash push -m` available since git 2.13+. The message makes the stash identifiable. Use `push` not deprecated `save` | HIGH |
| `git stash pop` | Restore stashed changes after merge | Restores the auto-stashed changes. If merge fails and we roll back, the stash is still available | HIGH |

**Stash strategy -- use `apply` + `drop`, not `pop`:**

Per best practices for scripted automation, prefer `git stash apply` followed by `git stash drop` over `git stash pop`. If `apply` fails (conflicts with merge results), the stash is preserved and the user can manually resolve. With `pop`, a conflict would leave the stash in a weird state.

```bash
auto_stash_if_dirty() {
    local porcelain
    porcelain=$(git status --porcelain 2>/dev/null)
    if [[ -z "$porcelain" ]]; then
        MERGE_AUTO_STASHED=false
        return 0
    fi
    print_info "Dirty working tree detected. Auto-stashing changes..."
    if git stash push -u -m "gsd-ralph: auto-stash before merge phase $1" >/dev/null 2>&1; then
        MERGE_AUTO_STASHED=true
        print_success "Changes stashed"
    else
        die "Failed to stash changes. Please commit or stash manually before merging."
    fi
}

auto_unstash_if_needed() {
    if [[ "${MERGE_AUTO_STASHED:-false}" != true ]]; then
        return 0
    fi
    print_info "Restoring auto-stashed changes..."
    if git stash apply >/dev/null 2>&1; then
        git stash drop >/dev/null 2>&1
        print_success "Stashed changes restored"
    else
        print_warning "Could not cleanly restore stashed changes."
        print_info "Your changes are preserved in: git stash list"
        print_info "Restore manually with: git stash pop"
    fi
}
```

**What NOT to use:**

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `git stash pop` | On conflict, leaves stash in ambiguous state; harder to recover in scripts | `git stash apply` then `git stash drop` on success |
| `git stash save` | Deprecated since git 2.16 in favor of `git stash push` | `git stash push -m "message"` |
| `git checkout -f` | Force-checkout discards uncommitted changes silently | `git stash push` first, then `git checkout` |
| `git reset --merge` after failed stash pop | Destructive; could lose merge results | Let user resolve manually; their stash is preserved |

### 4. CLI Guidance (Next-Step Instructions)

**Stack needed:** Pure Bash builtins only (printf, the existing color functions in common.sh).

| Technique | Purpose | Why | Confidence |
|-----------|---------|-----|------------|
| `print_info` / `print_success` (existing) | Output guidance messages | Already defined in lib/common.sh. Consistent styling | HIGH |
| Here-doc or multi-line printf | Print structured guidance blocks | Standard Bash. No new dependencies | HIGH |

**Implementation pattern -- guidance helper:**

```bash
# Add to lib/common.sh
print_next_step() {
    printf "\n${GREEN}Next step:${NC} %s\n" "$1"
}

print_guidance() {
    printf "\n${BLUE}%s${NC}\n" "---"
    local line
    for line in "$@"; do
        printf "  %s\n" "$line"
    done
    printf "${BLUE}%s${NC}\n" "---"
}
```

**Where to add guidance (by command):**

| Command | Current Ending | Add |
|---------|---------------|-----|
| `init` | "Initialized successfully" | "Next step: gsd-ralph execute <N>" |
| `execute` | "Run 'ralph' to start execution" | Keep, but also add "After Ralph finishes: gsd-ralph merge <N>" |
| `merge` | Summary table | "Next step: gsd-ralph cleanup <N>" or "Fix conflicts, then re-run merge" |
| `cleanup` | "Phase N cleanup complete" | "Phase N is fully cleaned up. Ready for next phase." |
| `status` | Status table | Contextual: if complete, suggest merge; if in-progress, suggest waiting |

No new tools needed. This is purely adding `printf` statements at the end of each command.

## Version Compatibility Matrix

All techniques above are verified against the project's minimum requirements:

| Requirement | Minimum | Verified | Notes |
|-------------|---------|----------|-------|
| Bash | 3.2 | 3.2.57 on darwin24 | `[[ -ef ]]`, `pwd -P`, `local`, arrays all work |
| Git | 2.20+ | 2.53.0 on test system | `git stash push -m` (2.13+), `rev-parse --git-common-dir` (2.13+), `worktree` (2.15+) all well within range |
| jq | 1.6+ | (existing) | No new jq usage needed for v1.1 features |
| python3 | 3.8+ | (existing) | Not needed for any v1.1 features |

**Git version floor remains 2.20+.** The newest git feature used across v1.0 and v1.1 is `git merge-tree --write-tree` (git 2.38+, with fallback). The stash and rev-parse features needed for v1.1 are available since git 2.13+, well within range.

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Path comparison | `[[ -ef ]]` operator | String comparison of resolved paths | `-ef` handles symlinks, mount points, and trailing slashes automatically at the inode level. More robust than any string comparison |
| Path resolution | `cd "$dir" && pwd -P` | `realpath` / `readlink -f` | `realpath` not on macOS by default; `readlink -f` not on BSD. `pwd -P` is a Bash builtin, zero dependencies |
| Auto-stash | `git stash push -m` + `apply`/`drop` | Require clean worktree (current behavior) | Current behavior is hostile UX. Auto-stash is standard in tools like `git rebase` and `git pull`. Safe with `apply`+`drop` pattern |
| Auto-push | Explicit `git push -u origin <branch>` | Set `push.autoSetupRemote` in git config | Modifying user's git config is invasive. Explicit push is transparent and predictable |
| Cleanup safety | Remove `rm -rf` fallback entirely | Add path guards but keep `rm -rf` | The `rm -rf` fallback is the root cause of the data loss. Removing it entirely is the correct fix. If `git worktree remove` fails, the correct response is to report the error, not to escalate to a more destructive operation |

## What NOT to Add for v1.1

| Technology | Why Not |
|------------|---------|
| **safe-rm** (npm/pip package) | External dependency for a problem solvable with 5 lines of Bash. Over-engineering |
| **trash-cli** / **trash** | macOS Trash integration is overkill for worktree cleanup. We should not rm -rf at all |
| **bashup/realpaths** (external Bash library) | Nice library but adds a vendored dependency. `[[ -ef ]]` and `pwd -P` are builtins that solve the same problem |
| **GNU coreutils** (for realpath) | Requiring Homebrew coreutils for a single function is unacceptable dependency creep |
| **Any git config modifications** | The tool should not alter the user's git configuration (global or local). All git behavior should be controlled via explicit flags in git commands |
| **Interactive prompts beyond y/N** | Keep UX simple. No `select` menus, no multi-choice prompts. The existing y/N confirmation pattern in cleanup is sufficient |
| **External logging frameworks** | printf to stdout/stderr with the existing color functions is sufficient for CLI guidance |

## Installation

No changes to installation process. v1.1 uses the same dependencies as v1.0:

```bash
# No new dependencies to install
# Verify existing stack:
git --version    # 2.20+ required
jq --version     # 1.6+ required
bash --version   # 3.2+ required (macOS default)
```

## Sources

- Git official documentation: `git-stash` -- https://git-scm.com/docs/git-stash (verified `push -m` since 2.13+)
- Git official documentation: `git-rev-parse` -- https://git-scm.com/docs/git-rev-parse (verified `--git-common-dir`, `--show-toplevel`)
- Git official documentation: `git-push` -- https://git-scm.com/docs/git-push (verified `-u` flag behavior)
- Git official documentation: `push.autoSetupRemote` -- introduced in git 2.37.0 (July 2022), https://github.com/git/git/commit/05d57750c66e4b58233787954c06b8f714bbee75
- Bash 3.2 path comparison: `[[ -ef ]]` operator verified on macOS Bash 3.2.57 (arm64-apple-darwin24) -- HIGH confidence
- Git stash scripting best practices: prefer `apply`+`drop` over `pop` in automation -- https://git-scm.com/book/en/v2/Git-Tools-Stashing-and-Cleaning, https://hostman.com/tutorials/best-practices-for-using-the-git-stash-command/
- macOS path resolution without realpath: `cd && pwd -P` pattern -- https://www.baeldung.com/linux/bash-expand-relative-path
- Codebase analysis: `lib/commands/cleanup.sh` line 180 (rm -rf fallback), `lib/commands/execute.sh` line 160 ($(pwd) registration), `lib/commands/merge.sh` lines 168-177 (branch check), lines 180-184 (clean tree check)

---
*Stack research for: gsd-ralph v1.1 Stability & Safety*
*Researched: 2026-02-20*
