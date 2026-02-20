# Project Research Summary

**Project:** gsd-ralph v1.1 Stability & Safety
**Domain:** Bash CLI tool safety hardening and UX improvements for a git worktree orchestration tool
**Researched:** 2026-02-20
**Confidence:** HIGH (grounded in direct codebase analysis, known production incident, and verified Git/Bash documentation)

## Executive Summary

gsd-ralph v1.1 is a stability and safety milestone, not a feature release. The research reveals a single confirmed critical bug (cleanup's `rm -rf` fallback deleted the vibecheck project directory in a real incident) and three UX friction points that block first-time users from completing the init-execute-merge-cleanup workflow without hitting walls. The recommended approach is to fix the data-loss bug first as a prerequisite, then add UX improvements in dependency order, and treat push as a non-blocking safety net throughout.

The critical insight from research: the cleanup bug is three separate problems compounding into one catastrophic outcome. In sequential mode, `execute.sh` registers `$(pwd)` (the project root) as a worktree path. When cleanup runs, `git worktree remove` fails on the main working tree. The `rm -rf` fallback then deletes the entire project directory. The fix requires patching all three root causes: stop registering the main worktree, remove the `rm -rf` fallback entirely (not just guard it), and add a centralized `assert_safe_to_remove()` guard that future code must route through. All v1.1 features are implementable with zero new dependencies -- the existing Bash 3.2, git, and jq stack is sufficient.

The UX improvements address a broken first-time user flow: after `execute` puts the user on a phase branch, the `merge` command immediately dies because the user is not on main. If they have any uncommitted edits (common), it dies again on the clean worktree check. After finally merging, there is no guidance on what to do next. Each of these friction points is a one-to-ten line fix, but they compound to make the tool feel hostile to new users. The recommended build order (safety first, then independent capabilities, then cross-cutting UX) ensures that auto-push never creates a false sense of security before the cleanup destruction risk is eliminated.

## Key Findings

### Recommended Stack

All v1.1 features are implementable with the existing v1.0 stack. No new dependencies are required. This is the correct outcome for a stability milestone -- adding dependencies to a stability release would be contradictory. See STACK.md for complete feature-by-feature analysis.

**Core technologies (unchanged from v1.0):**
- **Bash 3.2+**: All safety patterns use builtins (`[[ -ef ]]`, `pwd -P`); no new external tools
- **Git 2.20+**: Stash push (2.13+), `rev-parse --git-common-dir` (2.13+), worktree (2.15+) all well within range
- **jq 1.6+**: Auto-push config opt-out reads `.ralph/config.json` via jq; no new jq features

**Key technique decisions:**
- Use `[[ "$path" -ef "$toplevel" ]]` for inode-level path comparison (handles symlinks, mount points, trailing slashes) -- not string comparison
- Use `cd "$dir" && pwd -P` for path resolution -- not `realpath` (not on macOS by default) or `readlink -f` (BSD does not support `-f`)
- Use `git stash push -m` + `apply`/`drop` -- not `git stash pop` (pop leaves stash in ambiguous state on conflict in scripts)
- Remove `rm -rf` fallback entirely -- not just guard it; if `git worktree remove` fails, report the error

**What not to add:** No safe-rm, trash-cli, realpath, bashup/realpaths, GNU coreutils, or interactive prompts beyond y/N. All problems are solvable with existing builtins.

### Expected Features

v1.1 targets two categories: critical safety fixes (P1, must ship) and UX improvements (P1-P2, should ship). See FEATURES.md for full prioritization matrix.

**Must have -- P1, ship-blocking:**
- **Fix cleanup rm-rf bug** -- Caused confirmed data loss. Three-part fix: remove rm-rf fallback, skip main worktree registration, add safety guard. CRITICAL.
- **Project root protection guard** -- Centralized `safe_remove_path()` applied to all rm operations. Prerequisite for the cleanup fix.
- **Merge auto-switch to main** -- Without this, workflow is broken after `execute` leaves user on a phase branch.
- **Merge dirty-worktree handling** -- Auto-stash before switch/merge, restore after. Without this, users hit a wall on any incidental edit.
- **CLI next-step guidance** -- Static `print_next_step()` after each command. First-time users need to know what comes next.

**Should have -- P2, high value:**
- **Auto-push to remote** -- Safety net against local data loss (same scenario as vibecheck incident). Non-blocking on failure.
- **Contextual next-step chain** -- State-aware guidance reading registry and merge signals, not just static strings.

**Nice to have -- P3, polish:**
- Auto-push opt-out config (`.ralph/config.json` flag)
- Stash restore failure recovery guidance
- Safety audit trail (`.ralph/logs/safety-audit.log`)

**Anti-features (do not build):**
- Force-push to remote (never automate; destroys shared history)
- Auto-commit dirty changes before merge (pollutes git history)
- Interactive conflict resolution during merge (defeats autonomous purpose)
- Auto-cleanup after merge (removes the safety net before user can inspect)

### Architecture Approach

v1.1 adds three new library modules to the existing command-dispatch architecture and modifies five existing files. The entry point (`bin/gsd-ralph`) is unchanged. See ARCHITECTURE.md for complete component designs with verified integration points.

**New components (new files):**
1. **`lib/safety.sh`** -- Centralized path validation (`assert_safe_to_remove`, `validate_registry_path`). Stateless, pure validation. Highest priority -- fixes the data-loss bug.
2. **`lib/git_remote.sh`** -- Remote detection and push helpers (`has_push_remote`, `push_branch`, `push_current_branch`). Push is advisory, not mandatory; failures warn but never die().
3. **`lib/guidance.sh`** -- Context-aware next-step messaging after each command (`print_guidance` dispatching by command name + outcome).

**Modified components (existing files):**
4. **`lib/common.sh`** -- Add `print_next_step()` formatting helper for consistent styling
5. **`lib/commands/cleanup.sh`** -- Remove rm-rf fallback, add `validate_registry_path` + `assert_safe_to_remove` before removal
6. **`lib/cleanup/registry.sh`** -- Skip `register_worktree()` when path equals git toplevel (prevents root registration)
7. **`lib/commands/execute.sh`** -- Push branch after commit; print guidance
8. **`lib/commands/merge.sh`** -- Auto-switch to main, stash/unstash dirty worktree, push after merge, print guidance

**Key data flow changes:**
- v1.0 cleanup: `rm -rf "$wt_path"` fallback on worktree remove failure
- v1.1 cleanup: `validate_registry_path` -> `assert_safe_to_remove` -> `git worktree remove` -> warn on failure (no rm fallback)
- v1.0 merge: Die if not on main; die if dirty worktree
- v1.1 merge: Detect main branch -> auto-switch -> stash if dirty -> merge -> push -> restore stash -> guidance

**Anti-patterns to avoid:**
- Conditional safety (bypass `assert_safe_to_remove` with `--force`): safety checks are unconditional
- Push as a blocking prerequisite: push failures warn, never die()
- Stash without pop on error paths: every die() after stashing must call `restore_stash()` first

### Critical Pitfalls

Research identified 6 critical pitfalls specific to v1.1's implementation scope. See PITFALLS.md for full analysis including moderate pitfalls, UX pitfalls, and recovery strategies.

1. **Incomplete rm-rf guard creates new deletion vectors** -- Fixing only cleanup.sh:180 while leaving other raw `rm` calls unguarded perpetuates the systemic risk. Prevention: create a single `safe_remove()` function and audit the entire codebase for unguarded `rm` calls. Warning sign: any raw `rm -rf` outside `safe_remove()`.

2. **Auto-push before safety fix creates false sense of security** -- Auto-push protects against missing remote backups but NOT against cleanup deleting the project directory. Prevention: safety guardrails must ship before or in the same phase as auto-push. Never ship auto-push alone.

3. **Auto-push crashes workflow via set -euo pipefail** -- `bin/gsd-ralph` has `set -euo pipefail`. A bare `git push` failure propagates as a fatal error. Prevention: always wrap `git push` in `if git push ...; then ... else ... fi`. Push must be best-effort from the start, not retrofitted.

4. **Auto-push force-overwrites remote branches** -- Rollback uses `git reset --hard` which rewrites local history; post-rollback push is non-fast-forward. Prevention: never use `git push --force` in auto-push. On non-fast-forward rejection, warn and let user resolve manually.

5. **Merge auto-switch silently carries uncommitted work to main** -- Git allows checkout with a dirty worktree when changes do not conflict with the target branch. Prevention: always check `git status --porcelain` BEFORE switching branches; stash first.

6. **Registry path mismatch after sequential/parallel mode fix** -- Old v1 registry entries from v1.0 users won't have the new `mode` field; new code could parse them incorrectly. Prevention: add a `mode` field (`"sequential"` or `"parallel"`) and implement registry migration (default to sequential = safe for unknown entries).

## Implications for Roadmap

The research strongly suggests a three-phase structure for v1.1, driven by dependency ordering (safety is prerequisite to everything), risk mitigation (data loss bug is confirmed, must fix first), and implementation complexity (guidance touches all files, so add last when behavior is stable).

### Phase 1: Safety Guardrails and Cleanup Bug Fix

**Rationale:** This is the highest-priority work. The rm-rf data loss bug is a known production incident. The registry path mismatch is the root cause enabling the bug. All other v1.1 features depend on the cleanup path being safe. Building auto-push before this fix creates a false sense of security. This phase has no dependencies on other new v1.1 code.

**Delivers:**
- `lib/safety.sh` with `assert_safe_to_remove()` and `validate_registry_path()`
- `lib/cleanup/registry.sh` updated to skip main worktree registration and add `mode` field
- `lib/commands/cleanup.sh` with rm-rf fallback removed, safety guards added
- Registry migration for existing v1 entries (default mode=sequential, no directory removal)
- Full audit of all `rm` calls in the codebase; no raw rm-rf remaining

**Addresses (from FEATURES.md):**
- Fix cleanup rm-rf bug (P1)
- Project root protection guard (P1)

**Avoids (from PITFALLS.md):**
- Pitfall 1: Incomplete guard (audit entire codebase)
- Pitfall 6: Registry path mismatch (mode field + migration)

**Research flag:** Standard patterns. Git's own `git worktree remove` implements this same safety. No additional research needed.

---

### Phase 2: Auto-Push and Merge UX Improvements

**Rationale:** After cleanup is safe, auto-push is the next priority because it provides remote backup (the other failure mode in the vibecheck incident). Merge UX improvements ship in this phase because they share the same dependency (git_remote.sh) and address the second most impactful friction point in the user workflow. Auto-push must be designed as best-effort from day one per Pitfall 3.

**Delivers:**
- `lib/git_remote.sh` with `has_push_remote()`, `push_branch()`, `push_current_branch()`
- `lib/commands/execute.sh` updated: push branch after commit
- `lib/commands/merge.sh` updated: auto-switch to main, stash/unstash, push after merge
- `lib/commands/init.sh` updated: detect remote, report status
- Auto-push opt-out via `.ralph/config.json` (P3, low effort)
- Stash restore failure recovery guidance (P3, low effort)

**Addresses (from FEATURES.md):**
- Merge auto-switch to main (P1)
- Merge dirty-worktree handling (P1)
- Auto-push to remote (P2)
- Auto-push opt-out config (P3)
- Stash restore failure recovery (P3)

**Avoids (from PITFALLS.md):**
- Pitfall 2: Auto-push before safety fix (Phase 1 is prerequisite)
- Pitfall 3: Workflow crash on push failure (best-effort design, never die() on push)
- Pitfall 4: Force-push (explicit prohibition; no --force in codebase)
- Pitfall 5: Silent uncommitted work loss (check porcelain before switch)

**Research flag:** Standard patterns. Git stash and push behavior well-documented. Stash apply/drop preference over pop is the established automation pattern. No additional research needed.

---

### Phase 3: CLI Guidance and Polish

**Rationale:** Guidance touches every command file and produces only output changes -- no logic changes. This makes it safest to add last, when all other behavior (including exact merge outcomes that determine guidance text) is finalized. Adding guidance before merge UX is stable would require updating guidance text again anyway. This phase also includes P3 polish items not already shipped in Phase 2.

**Delivers:**
- `lib/guidance.sh` with `print_guidance()` dispatching by command + outcome
- `lib/common.sh` updated: add `print_next_step()` helper
- All command files updated: `print_guidance()` calls at end of each command
- Outcome-branched guidance (merge success vs partial merge vs rollback -- different next steps)
- Safety audit trail in `.ralph/logs/safety-audit.log` (P3)
- Contextual next-step chain (state-aware, queries registry) (P2)

**Addresses (from FEATURES.md):**
- CLI next-step guidance (P1 -- basic static guidance)
- Contextual next-step chain (P2 -- state-aware guidance)
- Safety audit trail (P3)

**Avoids (from PITFALLS.md):**
- UX Pitfall: Guidance assumes linear workflow (branch by merge outcome)
- UX Pitfall: Verbose guidance causing banner blindness (max 2-3 lines per command)
- UX Pitfall: Technical stash messages (translate to plain English)

**Research flag:** Standard patterns. CLI UX guidance well-established (git hints, npm, gh CLI patterns). No additional research needed.

---

### Phase Ordering Rationale

- **Safety first (Phase 1):** The rm-rf bug is a confirmed production incident. Until cleanup is safe, the tool should not be used in production. All other v1.1 work is lower priority than eliminating the data-loss risk.

- **Functionality before cross-cutting concerns (Phases 2 before 3):** Auto-push and merge UX are behavior changes. Guidance is output-only. Guidance text depends on what the behavior actually does. Adding guidance before behavior is finalized creates rework.

- **Independent modules first within each phase:** Within each phase, build library modules (safety.sh, git_remote.sh, guidance.sh) before the command files that use them. No circular dependencies.

- **How this avoids pitfalls:** Safety guardrails (Phase 1) prevent the auto-push false-security pitfall (Pitfall 2) by construction -- auto-push physically cannot ship before safety guardrails in this ordering.

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Safety Guardrails):** Git worktree remove safety, bash path comparison, inode comparison all well-documented. Codebase analysis sufficient.
- **Phase 2 (Auto-Push + Merge UX):** Git stash, push, and checkout mechanics well-documented. Best-effort push pattern is standard in automation tools.
- **Phase 3 (Guidance):** CLI UX patterns well-established. No niche domain knowledge needed.

**Areas NOT needing research:**
- Whether to keep Bash (settled by v1.0 constraints)
- Alternative path safety libraries (bash builtins solve the problem)
- Alternative stash strategies (git stash push + apply/drop is the documented best practice)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | No new dependencies; all techniques verified against Bash 3.2 on darwin24/arm64 and git 2.20+ minimums |
| Features | HIGH | Derived from known production incident + direct codebase analysis; priorities clear and well-justified |
| Architecture | HIGH | Integration points verified against actual source line numbers (cleanup.sh:180, merge.sh:168-177, execute.sh:160, registry.sh); not theoretical |
| Pitfalls | HIGH | Grounded in real incident (vibecheck data loss), confirmed bugs in codebase, and verified git documentation for edge cases |

**Overall confidence:** HIGH

All four research files are grounded in the actual v1.0 codebase (reading specific files and line numbers) and a known production incident. This is not theoretical research -- it is post-mortem + forward-looking safety analysis. The recommendations are specific, actionable, and technically verifiable.

### Gaps to Address

1. **Registry migration testing:** The recommendation to add a `mode` field and migrate old entries is sound, but there is no inventory of how many v1.0 registries exist with the old format. During Phase 1 implementation, test against a registry written by v1.0 code to verify migration logic works correctly.

2. **Stash pop vs apply/drop edge case coverage:** STACK.md recommends `apply`+`drop` over `pop`. FEATURES.md implementation pattern uses `stash pop`. These are inconsistent. Resolution: use `apply`+`drop` in the final implementation (the safer option documented in STACK.md), confirm during Phase 2.

3. **Auto-push timing relative to Ralph's commits:** PITFALLS.md warns not to auto-push while Ralph is still committing on the branch. The Phase 2 design pushes after `execute` completes (initial branch setup), not continuously during Ralph's work. This is the correct interpretation, but should be made explicit in implementation.

4. **Hardcoded main/master detection:** PITFALLS.md flags that custom default branch names (e.g., `trunk`, `develop`) will fail. The Phase 2 auto-switch implementation already handles this via `git show-ref --verify` loop over candidates. This is sufficient for v1.1 but should be noted as a known limitation if users have non-standard branch names.

## Sources

### Primary (HIGH confidence)
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/cleanup.sh` -- Lines 174-183: confirmed rm-rf fallback bug
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/merge.sh` -- Lines 168-184: branch check and clean-worktree requirement
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/commands/execute.sh` -- Line 160: $(pwd) registration bug in sequential mode
- `/Users/daniswhoiam/Projects/gsd-ralph/lib/cleanup/registry.sh` -- Registry structure and CRUD
- `.planning/STATE.md` -- Known incident: vibecheck project data loss from cleanup command
- [Git stash documentation](https://git-scm.com/docs/git-stash) -- apply+drop over pop in scripted automation
- [Git rev-parse documentation](https://git-scm.com/docs/git-rev-parse) -- --show-toplevel, --git-common-dir
- [Git push documentation](https://git-scm.com/docs/git-push) -- fast-forward rules, force-push behavior
- [Git worktree documentation](https://git-scm.com/docs/git-worktree) -- main worktree cannot be removed

### Secondary (MEDIUM confidence)
- [safe-rm patterns](https://github.com/kaelzhang/shell-safe-rm) -- path blacklisting approach
- [Git autostash patterns](https://www.eficode.com/blog/git-autostash) -- autostash configuration and behavior
- [CLI UX best practices](https://evilmartians.com/chronicles/cli-ux-best-practices-3-patterns-for-improving-progress-displays) -- next-step guidance patterns
- [Bash scripting for reliable automation](https://oneuptime.com/blog/post/2026-02-13-bash-best-practices/view) -- set -euo pipefail implications

### Tertiary (LOW confidence, verify during implementation)
- Exact behavior of `git stash apply` on conflict (stash is preserved -- should be verified in test environment)
- First-push credential manager retry behavior (known to be flaky with some credential managers)

---
*Research completed: 2026-02-20*
*Ready for roadmap: yes*
