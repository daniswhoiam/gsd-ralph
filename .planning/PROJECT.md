# gsd-ralph

## What This Is

A standalone Bash CLI tool that bridges GSD structured planning with Ralph autonomous execution. Provides a complete lifecycle (init, generate, execute, merge, cleanup) for turning GSD-planned phases into working, merged code — with branch isolation, protocol-driven prompts, wave-aware merging, registry-driven cleanup, safety guardrails, auto-push, and context-sensitive CLI guidance.

## Core Value

One command takes a GSD-planned phase and produces merged, working code — no manual worktree setup, no hand-crafted prompts, no babysitting.

## Requirements

### Validated

- ✓ Initialize Ralph in any GSD project (create configs, GSD-aware prompts) — v1.0
- ✓ Execute a full phase with one command (branch creation, prompt generation, Ralph launch) — v1.0
- ✓ Generate context-specific PROMPT.md, fix_plan.md, and .ralphrc from templates — v1.0
- ✓ Handle GSD dual naming conventions (PLAN.md and NN-MM-PLAN.md) — v1.0
- ✓ Auto-merge completed branches in plan order with dry-run conflict detection — v1.0
- ✓ Wave-aware merge signaling to unblock dependent plans — v1.0
- ✓ Review mode for branch inspection before merging — v1.0
- ✓ Pre-merge rollback safety with commit hash preservation — v1.0
- ✓ Auto-resolve .planning/ conflicts (prefer main's version) — v1.0
- ✓ Registry-driven cleanup of worktrees and branches — v1.0
- ✓ Terminal bell notifications on completion/failure — v1.0
- ✓ Works with any GSD project regardless of tech stack — v1.0
- ✓ Cleanup never uses rm -rf fallback; all deletions via safe_remove() guard — v1.1
- ✓ Registry sentinel prevents main worktree registration as removable — v1.1
- ✓ Auto-push branches to remote after execute and merge (non-fatal, configurable) — v1.1
- ✓ Merge auto-switches to main and auto-stashes/restores dirty worktree — v1.1
- ✓ Every command outputs context-sensitive next-step guidance — v1.1

### Active

(No active milestone — ready for next milestone planning)

### Out of Scope

- GSD plugin integration — standalone tool first, integration later
- GUI or web dashboard — CLI only, target users are terminal-native
- OS-level notifications (macOS Notification Center) — terminal bell is sufficient
- Custom notification channels (Slack, email) — terminal only for simplicity
- Custom LLM provider support — coupled to Ralph + Claude Code intentionally
- Interactive plan editing — GSD owns planning; gsd-ralph reads plans, doesn't edit them
- Plugin/extension system — premature abstraction; build monolithically first
- Git hosting integration (PR creation, CI triggers) — scope ends at local merge
- Multi-repo support — single git repo only
- Interactive conflict resolution — user should resolve manually with git tools
- Force-push to remote — conflicts with safety-first philosophy
- Auto-commit dirty changes — violates user intent
- Auto-cleanup after merge — keep as explicit command
- Multi-remote push — single origin is sufficient
- Trash/quarantine instead of delete — simple refusal to delete is safer
- Verbosity tiers (--quiet/--verbose) — premature; ship one good default first

## Context

Shipped v1.1 with 9,693 LOC total (Bash + Bats tests), 211 tests.
Tech stack: Bash 3.2, bats-core, ShellCheck, jq, python3.
v1.0 built in 7 days across 6 phases with 13 plans (78 commits).
v1.1 built in 1 day across 3 phases with 9 plans (37 commits).
Extracted from bayesian-it where this workflow was developed as ad-hoc scripts.

Known v2 candidates from deferred requirements: status monitoring (STAT-01-04), peer visibility (PEER-01-02), enhanced execution (EEXC-01-03), enhanced merge (EMRG-01-02), advanced orchestration (ADVO-01-06). See `milestones/v1.0-REQUIREMENTS.md` for full list.

## Constraints

- **Bash 3.2**: macOS system bash — no associative arrays, no readarray, no nameref
- **Portability**: Must work on macOS (primary dev environment)
- **Non-invasive**: Works alongside existing GSD and Ralph installations
- **GSD dual naming**: Handles both PLAN.md and NN-MM-PLAN.md conventions
- **Git worktrees**: Relies on git worktree for isolation — requires git repo

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Standalone Bash CLI (not Node.js/plugin) | Keeps tool independent, simpler to develop and test, same ecosystem as GSD/Ralph | ✓ Good — 9,693 LOC Bash works well |
| Auto-merge by default with review option | Optimizes for speed while preserving safety | ✓ Good — --review flag provides safety valve |
| Terminal bell for notifications | Simplest approach, no extra deps, works everywhere | ✓ Good — printf '\a' is POSIX-standard |
| Existing scripts as reference only | Clean architecture over incremental refactoring | ✓ Good — avoided legacy patterns |
| Sequential execution default (not parallel) | Learned from Phase 1 merge conflicts; simpler mental model | ✓ Good — zero conflicts in Phases 3-6 |
| Dependency-graph execution model | Maximizes parallelism when opted in; later-wave plans launch when specific deps merge | ✓ Good — architecture ready for parallel when needed |
| Later-wave worktrees from post-merge main | Simpler than speculative execution with mid-flight rebase | ✓ Good — eliminates entire class of merge conflicts |
| git merge-tree --write-tree for dry-run | Zero-risk conflict detection without touching working tree | ✓ Good — works with Git 2.38+ fallback |
| Registry-driven cleanup | Only removes what it created; prevents orphans | ✓ Good — fire-and-forget registration pattern |
| EXIT trap for failure notification | Bell fires after significant work, not on trivial validation errors | ✓ Good — right granularity |
| cd+pwd -P for path resolution | No readlink -f for Bash 3.2 compat | ✓ Good — portable across macOS |
| Inode-level [[ -ef ]] for path comparison | Handles symlinks correctly in safety guards | ✓ Good — catches all path equivalences |
| Failed worktree removals as warnings | Not rm -rf escalation; safety over convenience | ✓ Good — eliminated data-loss vector |
| Push failures always return 0 | Push is convenience, never crashes the command | ✓ Good — non-blocking UX |
| apply+drop stash pattern | Preserves stash entry on conflict failure (pop would lose it) | ✓ Good — safer than pop |
| No guidance after die() or --help | Error messages and usage text are self-explanatory | ✓ Good — avoids noise |

---
*Last updated: 2026-02-23 after v1.1 milestone*
