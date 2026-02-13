# Feature Landscape

**Domain:** CLI tools that orchestrate autonomous coding agents with parallel worktree-based execution
**Researched:** 2026-02-13
**Overall confidence:** MEDIUM (training data only -- WebSearch/WebFetch unavailable for live verification)

## Competitive Landscape Context

This feature analysis draws from the following tools and patterns:

| Tool | Type | Relevance |
|------|------|-----------|
| **Claude Code** | Autonomous CLI coding agent | The underlying agent gsd-ralph wraps (via Ralph) |
| **Ralph** | Autonomous execution loop for Claude Code | Direct dependency -- loop management, circuit breakers, status reporting |
| **Aider** | AI pair-programming CLI | Alternative coding agent with strong git integration |
| **Claude Squad / tmux-based orchestrators** | Multi-agent session managers | Closest competitors for parallel execution orchestration |
| **Cursor Agent Mode** | IDE-integrated agent | Comparison point for UX, though not CLI |
| **OpenAI Codex CLI** | Terminal coding agent | Comparison point for sandboxing, autonomy levels |
| **GSD (Get Shit Done)** | Planning framework | The planning layer gsd-ralph bridges FROM |
| **GNU Parallel / xargs / make** | Traditional parallel execution | Patterns for job orchestration, dependency graphs |

The key insight: gsd-ralph occupies a unique niche. Most AI coding tools are either **single-agent** (aider, Claude Code, Codex CLI) or **multi-agent session managers** (claude-squad, tmux orchestrators). None bridge a **structured planning framework** into **parallel autonomous execution with worktree isolation and automated merge**. This is the differentiating position.

---

## Table Stakes

Features users expect. Missing = product feels incomplete or broken.

### Initialization and Setup

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Project init (`gsd-ralph init`)** | Users need a single command to set up Ralph integration in any GSD project | Medium | Must detect project type (language, test runner, build tool), generate .ralph/ configs, PROMPT.md template, .ralphrc. The existing templates show what this looks like for a TypeScript project; needs to be generalized. |
| **GSD plan discovery** | Core value prop requires reading GSD file layout | Low | Already implemented in scripts. Must handle both PLAN.md and NN-MM-PLAN.md naming conventions. Also needs to handle phase directory structure (.planning/phases/phase-N/). |
| **Validate prerequisites** | Users will be confused if Ralph, git, or GSD artifacts are missing | Low | Check: git repo, Ralph installed, .planning/ exists, phase is planned, no dirty working tree on main. Fail fast with actionable error messages. |

### Phase Execution Core

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Worktree creation per plan (`gsd-ralph execute N`)** | Parallel isolation is the core architectural decision | Medium | Create git branch + worktree per plan file. Copy/generate .ralph/ configs. Already working in ralph-worktrees.sh. |
| **Prompt generation per worktree** | Each Ralph instance needs context-specific instructions | Medium | Base PROMPT.md + phase overrides (scope lock, peer visibility, dependency info). Current approach appends to PROMPT.md -- clean but should be more structured. |
| **Task extraction from GSD XML** | Plans are in GSD XML format, Ralph needs fix_plan.md checklist | Low | Python one-liner in current scripts. Should be a proper parser (handle edge cases, malformed XML, nested tasks). |
| **Ralph instance launch** | Users expect `execute` to actually start the agents, not just create worktrees | Medium | Current scripts only CREATE worktrees and tell user to `cd && ralph` manually. For table stakes, the tool should launch Ralph processes (background or tmux/screen sessions). Without this, the tool is just "worktree setup" not "execution orchestration." |
| **Sequential merge ordering** | Plans within a phase may have implicit ordering dependencies | Low | Merge in plan number order (01 before 02). Current ralph-merge.sh does this. |

### Status and Monitoring

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Phase status overview (`gsd-ralph status N`)** | Users need to know what is running, complete, blocked, or failed | Low | Already implemented. Read status.json from each worktree, display color-coded table with summary. |
| **Terminal bell on completion/failure** | Explicitly in project requirements. Users run multiple terminals and need passive notification. | Low | `printf '\a'` when all plans complete or any plan fails/errors. Trivial to implement but critical for the hands-off workflow. |
| **Clear error reporting** | When Ralph fails, users need to know which plan, why, and what to do | Low | Surface Ralph's circuit breaker state, blocked reasons, last error. Current status.json has basic fields. |

### Merge and Cleanup

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Auto-merge completed branches (`gsd-ralph merge N`)** | Explicitly in requirements. Default behavior should be auto-merge. | Medium | Merge each plan branch back to main in order. Handle the common STATE.md conflict. Already implemented in ralph-merge.sh. |
| **Review mode option (`gsd-ralph merge N --review`)** | Safety valve for reviewing before merge. Explicitly in requirements. | Low | Show diff for each branch, prompt for approval before merging. |
| **Conflict guidance** | Merge conflicts are common with parallel plans editing shared files | Low | Already implemented: show conflicted files, suggest resolution steps, note that STATE.md conflicts are common. |
| **Worktree and branch cleanup (`gsd-ralph cleanup N`)** | Dead worktrees waste disk space and clutter `git worktree list` | Low | Already implemented. Remove worktrees, delete merged branches, prune references. |

### Configuration

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Project-specific config (.ralphrc generation)** | Each project has different test commands, build tools, file structures | Low | Template-based generation. Current template is bayesian-it-specific; needs to be parameterized by project detection. |
| **Sensible defaults** | Users should not need to configure anything for the common case | Low | Auto-detect: language from package.json/Cargo.toml/etc., test command, build command. Only prompt for genuinely ambiguous choices. |

---

## Differentiators

Features that set gsd-ralph apart. Not expected, but valued. These create competitive advantage.

### Planning-Aware Intelligence

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **GSD dependency graph awareness** | Automatically check phase dependencies before execution. If Phase 3 depends on Phase 2, refuse to execute Phase 3 until Phase 2 is complete and merged. No other tool understands structured plan dependencies. | Medium | Read ROADMAP.md dependency declarations. Current PROMPT.md template mentions dependency checking, but the orchestrator itself should enforce this at the `execute` level. |
| **Automatic STATE.md updates** | After successful merge, update STATE.md to reflect phase completion. Close the loop between execution and planning state. | Low | Parse STATE.md, update phase status, last activity timestamp. Saves the human from manual bookkeeping. |
| **Phase chaining (`gsd-ralph execute --continue`)** | Execute Phase N, and when it completes and merges, automatically start Phase N+1 if planned. Full autopilot for sequential phases. | Medium | Combines execute + status-watch + merge + cleanup + next execute. Powerful for overnight runs. Requires robust error handling (stop chain on failure). |
| **Plan-level parallelism with plan-level isolation** | Each GSD plan gets its own worktree -- not just branch isolation, but filesystem isolation. Plans cannot accidentally interfere with each other's uncommitted files. | Low | Already the core architecture. This is genuinely differentiating vs. tools that just use branches. |

### Operational Excellence

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Completion detection with auto-merge** | Watch status.json across all worktrees. When all report "complete", automatically trigger merge without human intervention. This is the "one command" promise. | Medium | Poll-based or filesystem-watch-based. When all worktrees show complete status, bell + auto-merge. This closes the gap between "execute" and "merge" into a truly autonomous workflow. |
| **Structured execution log** | After a phase completes, generate a summary: which plans ran, how long each took, what was committed, any issues encountered. Stored in .planning/phases/phase-N/EXECUTION_LOG.md. | Medium | Aggregate status.json data, git log per branch, timing info. Valuable for retrospectives and improving future plans. |
| **Dry-run mode (`gsd-ralph execute N --dry-run`)** | Show what WOULD happen without creating worktrees or launching agents. Lists plans found, worktrees that would be created, prompts that would be generated. | Low | Minimal implementation cost, high value for debugging and confidence. |
| **Pre-merge test run** | Before merging, run the project's test suite on each branch to verify the work. Reject branches that fail tests. | Medium | `cd worktree && npm test` (or detected test command) before merge. Prevents merging broken code. Aider does lint/test integration well; this is similar. |
| **Resume/retry failed plans** | If a Ralph instance fails (circuit breaker, error), allow `gsd-ralph retry N-02` to restart just that plan's execution without touching other worktrees. | Medium | Reset status.json, optionally reset the branch to a clean state, relaunch Ralph. Important for long-running phases where one plan fails. |

### Developer Experience

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Single-command full lifecycle** | `gsd-ralph execute N --auto` does: create worktrees, launch agents, monitor, bell on completion, auto-merge, cleanup. The true "one command" promise. | High | Composes all subcommands. Requires robust process management, error handling, and graceful degradation. This is the north star feature. |
| **Progress percentage** | Show "Phase 2: 60% complete (3/5 tasks done across 2 plans)" instead of just status labels. | Low | Count checked items in fix_plan.md per worktree, aggregate. Simple but gives much better feedback than "running" vs "complete." |
| **Colorized, structured CLI output** | Already present in existing scripts. Professional, scannable terminal output. | Low | Continue the pattern from existing scripts (color codes, box drawing, clear sections). Table-format for status. |
| **Watch mode (`gsd-ralph status N --watch`)** | Auto-refresh status display every N seconds. Useful when monitoring a running phase. | Low | `watch`-style polling with clear-and-redraw. More pleasant than repeatedly running `status`. |

---

## Anti-Features

Features to explicitly NOT build. These are scope traps or actively harmful.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **GUI / web dashboard** | Massive scope increase. Target users are terminal-native developers. CLI is the right interface for this workflow. The value is in automation, not visualization. | Keep CLI-only. The status command with color coding and watch mode is sufficient. |
| **Custom LLM provider support** | gsd-ralph wraps Ralph which wraps Claude Code. Adding OpenAI/Gemini/etc. support would require abstracting away the agent layer, which is the wrong abstraction. | Stay coupled to Ralph + Claude Code. This is the power, not a limitation. |
| **OS-level notifications (macOS Notification Center, Slack, email)** | Extra dependencies, platform-specific code, configuration complexity. Explicitly out of scope in PROJECT.md. | Terminal bell (`\a`) is universal and zero-dependency. Can always be added later if there is demand. |
| **Interactive plan editing** | GSD owns planning. gsd-ralph should READ plans, not WRITE or EDIT them. Blurring this boundary makes both tools worse. | Read-only access to .planning/. If a plan needs changes, the human uses GSD commands. |
| **Task-level parallelism within a single plan** | Plans are designed to be executed sequentially (tasks may depend on previous tasks). Parallelizing within a plan breaks the task ordering contract. | Parallelism is at the PLAN level (multiple plans per phase), not the TASK level within a plan. This is already the correct architecture. |
| **Agent-to-agent communication** | Tempting to have worktree agents coordinate in real-time. In practice this creates race conditions, complex state machines, and debugging nightmares. | One-way visibility only: agents can READ peer status (via status.json), but never WRITE to peer worktrees. The orchestrator handles coordination. |
| **Plugin/extension system** | Premature abstraction. The tool needs to do one thing well first. A plugin system adds API surface that constrains future changes. | Build monolithically. Extract plugins later only if clear extension points emerge from usage patterns. |
| **Git hosting integration (GitHub PR creation, CI triggers)** | Scope creep into CI/CD territory. The merge step should merge locally. Pushing and PR creation is a separate concern the developer handles. | End the workflow at local merge. The developer pushes when they are satisfied. |
| **Multi-repo support** | gsd-ralph operates within a single git repository. Multi-repo orchestration is a fundamentally different problem (monorepo vs. polyrepo). | Single-repo only. One .planning/ directory, one set of worktrees. |
| **Fancy TUI (ncurses, ink, blessed)** | Adds heavy dependencies, limits portability, harder to script/pipe. The terminal output should be simple text with ANSI colors. | Printf-based output with ANSI escape codes. Works everywhere, easy to grep/redirect. |

---

## Feature Dependencies

```
gsd-ralph init
    |
    v
gsd-ralph execute N
    |--- Depends on: init (project configured)
    |--- Depends on: Phase N planned (GSD plan files exist)
    |--- Depends on: Phase N-1 merged (if dependency declared)
    |--- Creates: worktrees, branches, .ralph/ configs
    |--- Launches: Ralph instances
    |
    v
gsd-ralph status N
    |--- Depends on: execute N (worktrees exist)
    |--- Reads: status.json from each worktree
    |
    v
gsd-ralph merge N
    |--- Depends on: execute N (worktrees exist with commits)
    |--- Depends on: all plans complete (or user override)
    |--- Optional: --review flag for manual review
    |--- Optional: pre-merge test run
    |
    v
gsd-ralph cleanup N
    |--- Depends on: merge N (branches merged)
    |--- Removes: worktrees, branches, prunes references

Cross-cutting:
  - Terminal bell: triggered by status changes (completion, failure) -- woven into execute/status
  - Dry-run: applies to execute and merge
  - Watch mode: applies to status
  - Resume/retry: branches from execute (reruns a specific plan)
  - Phase chaining: composes execute + status + merge + cleanup in sequence
```

## Internal Feature Ordering (Build Sequence)

These features should be built in roughly this order, where earlier features are prerequisites for later ones:

1. **Project detection / init** -- everything else needs project config
2. **Plan discovery and task extraction** -- execute depends on reading GSD plans
3. **Worktree creation** -- the core isolation mechanism
4. **Prompt generation** -- each worktree needs proper Ralph instructions
5. **Ralph launch** -- actually starting the agents
6. **Status monitoring** -- observing running agents
7. **Terminal bell** -- passive notification layer on status
8. **Auto-merge** -- consuming completed work
9. **Review mode** -- safety variant of merge
10. **Cleanup** -- housekeeping after merge
11. **Dry-run** -- confidence tool (can be built alongside execute)
12. **Pre-merge test run** -- quality gate before merge
13. **Progress percentage** -- enhanced monitoring
14. **Watch mode** -- enhanced monitoring UX
15. **Resume/retry** -- error recovery
16. **Dependency graph enforcement** -- planning-aware intelligence
17. **STATE.md auto-updates** -- closing the planning loop
18. **Phase chaining** -- full autopilot
19. **Execution log** -- retrospective support
20. **Single-command full lifecycle** -- the north star composition

---

## MVP Recommendation

Prioritize for MVP (the smallest thing that delivers the core "one command" promise):

1. **`gsd-ralph init`** -- Project setup with auto-detection (table stakes)
2. **`gsd-ralph execute N`** -- Plan discovery + worktree creation + prompt generation + Ralph launch (table stakes)
3. **`gsd-ralph status N`** -- Color-coded status overview (table stakes)
4. **Terminal bell on completion** -- Passive notification (table stakes, trivial)
5. **`gsd-ralph merge N`** -- Auto-merge with conflict guidance (table stakes)
6. **`gsd-ralph cleanup N`** -- Worktree and branch removal (table stakes)

Defer to post-MVP:

- **Phase chaining**: Requires all core commands to be solid first
- **Execution log generation**: Nice-to-have, not core value
- **Pre-merge test run**: Valuable but Ralph should already be running tests during execution
- **Watch mode**: Quality-of-life, not essential when `status` works
- **Resume/retry**: Error recovery is important but can ship after initial flow works end-to-end
- **Single-command full lifecycle**: The north star, but it is literally the composition of all other commands; build the pieces first

The critical gap in the current scripts is **Ralph instance launch**. The existing `ralph-execute.sh` creates worktrees but tells the user to manually `cd && ralph` in multiple terminals. Closing this gap (launching Ralph processes, even if just via `tmux` or background processes) is what turns this from "a worktree setup tool" into "an execution orchestrator."

---

## Confidence Notes

| Area | Confidence | Notes |
|------|------------|-------|
| Table stakes features | HIGH | Derived directly from project requirements (PROJECT.md, FOUNDATIONAL_DOCUMENT.md) and existing script analysis |
| Differentiators | MEDIUM | Based on training data knowledge of competitor tools (aider, Claude Code, claude-squad). Could not verify latest features via web. |
| Anti-features | HIGH | Directly informed by PROJECT.md "Out of Scope" section and architectural principles in FOUNDATIONAL_DOCUMENT.md |
| Feature dependencies | HIGH | Derived from code analysis of existing scripts and logical ordering |
| Competitive landscape | MEDIUM | Based on training data (cutoff ~May 2025). Tools like claude-squad, aider, and Claude Code may have added parallel execution features since then. |

## Sources

- `/Users/daniswhoiam/Projects/gsd-ralph/FOUNDATIONAL_DOCUMENT.md` -- Project vision and constraints
- `/Users/daniswhoiam/Projects/gsd-ralph/.planning/PROJECT.md` -- Requirements and out-of-scope decisions
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-execute.sh` -- Current execution orchestration
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-merge.sh` -- Current merge implementation
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-status.sh` -- Current status monitoring
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-worktrees.sh` -- Current worktree creation
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-cleanup.sh` -- Current cleanup implementation
- `/Users/daniswhoiam/Projects/gsd-ralph/templates/PROMPT.md.template` -- Ralph prompt patterns
- `/Users/daniswhoiam/Projects/gsd-ralph/templates/ralphrc.template` -- Ralph configuration patterns
- Training data knowledge of: aider (github.com/Aider-AI/aider), Claude Code (docs.anthropic.com), claude-squad, OpenAI Codex CLI, Cursor agent mode -- **not verified against current versions**
