# gsd-ralph

## What This Is

A thin integration layer that enables any GSD command to run autonomously via Ralph. Adding `--ralph` to any GSD command makes Ralph handle all user input, permissions, and decisions automatically. Built on Claude Code's native worktree isolation and GSD's existing execution model. Hardened with circuit breakers, PreToolUse hooks, and audit logging.

## Core Value

Add `--ralph` to any GSD command and walk away — Ralph drives, GSD works, code ships.

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
- ✓ `--ralph` flag enables autonomous execution of any GSD command — v2.0
- ✓ Loop fresh Claude Code instances with STATE.md completion detection — v2.0
- ✓ Context assembly (PROJECT.md, STATE.md, phase plans) into iteration prompts — v2.0
- ✓ Autonomous behavior prompt (SKILL.md) prevents AskUserQuestion, auto-approves checkpoints — v2.0
- ✓ `--dry-run` preview of exact `claude -p` command — v2.0
- ✓ Three permission tiers: `--allowedTools` whitelist, `--auto-mode`, `--yolo` — v2.0
- ✓ Worktree isolation via `--worktree` — v2.0
- ✓ `--max-turns` ceiling per iteration — v2.0
- ✓ Circuit breaker with wall-clock timeout and graceful stop — v2.0
- ✓ PreToolUse hook blocks AskUserQuestion as defense-in-depth — v2.0
- ✓ Audit log for post-run review with unified paths — v2.0

### Active

<!-- v2.1 Easy Install — requirements defined in REQUIREMENTS.md -->

- [ ] One-command installation following Claude Code ecosystem patterns
- [ ] GSD prerequisite detection with helpful version guidance
- [ ] Full GSD + Ralph workflow functional after install

### Out of Scope

- Intelligent response strategies (context-aware checkpoint answers) — v2.1+
- Parallel plan execution via multiple worktrees — v2.1+
- Multi-phase orchestration (chain phase N → N+1) — v2.1+
- Session resume on failure via `--resume` — v2.1+
- Real-time progress display via stream-json parsing — v2.1+
- Custom LLM provider support — coupled to Claude Code intentionally
- GUI or web dashboard — CLI only, target users are terminal-native
- Multi-repo support — single git repo only
- v1.x standalone CLI features (init, generate, execute, merge, cleanup) — superseded by GSD native commands

## Context

v2.0 shipped as a complete rewrite. v1.x (9,693 LOC Bash, 211 tests) archived — it was a standalone CLI with its own lifecycle commands. The architectural insight: GSD already handles planning/execution/verification; Ralph already handles autonomous coding. gsd-ralph just needs to bridge the gap by making Ralph act as the "user" for GSD commands.

v2.0 is ~830 LOC Bash implementation + 1,593 LOC Bats tests = 2,424 total. 315 tests across 6 suites.

Key v2.0 components:
- `scripts/ralph-launcher.sh` (592 LOC) — core launcher with loop engine
- `scripts/assemble-context.sh` — GSD context assembly for prompts
- `scripts/validate-config.sh` — config validation with strict-with-warnings
- `scripts/ralph-hook.sh` — PreToolUse hook for AskUserQuestion denial
- `.claude/skills/gsd-ralph-autopilot/SKILL.md` — autonomous behavior rules

## Constraints

- **Thin layer**: Must not replicate logic that lives in GSD or Ralph
- **GSD-compatible**: Updates to GSD should flow through without breaking gsd-ralph
- **Portability**: Must work on macOS (primary dev environment)
- **Non-invasive**: Works alongside existing GSD and Ralph installations

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| v1.x: Standalone Bash CLI | Kept tool independent during exploration phase | ✓ Good — proved the concept, informed v2.0 design |
| v2.0: Rewrite as GSD integration layer | GSD + Claude Code now handle what v1.x built manually | ✓ Good — 92% LOC reduction (9,693 → 830) |
| v2.0: `--ralph` flag model | User mental model: same GSD commands, just add `--ralph` | ✓ Good — simple, composable |
| v2.0: Leverage Claude Code headless mode | `claude -p` + `--allowedTools` provides auto-permission | ✓ Good — no custom permission system needed |
| v2.0: Archive v1.x, don't salvage | Clean break avoids legacy patterns | ✓ Good — clean architecture |
| v2.0: Three permission tiers | Default/auto-mode/yolo covers safety spectrum | ✓ Good — flexible without complexity |
| v2.0: STATE.md snapshot for progress detection | Compare phase/plan/status before and after iteration | ✓ Good — simple, reliable |
| v2.0: jq == false for JSON boolean handling | `//` operator treats false as falsy in jq | ✓ Good — discovered via bug during Phase 13 |
| v2.0: Trap-based cleanup lifecycle | Single _cleanup trap handles all exit paths | ✓ Good — eliminated duplicate cleanup code |
| v2.0: settings.local.json merge/unmerge | Preserves existing hooks and permissions during install/remove | ✓ Good — non-destructive |

## Current Milestone: v2.1 Easy Install

**Goal:** Make gsd-ralph installable in any repo with a single command following current Claude Code ecosystem patterns.

**Target features:**
- One-command installer (npx or Claude Code native pattern — TBD from research)
- GSD prerequisite check with version info
- Copies all Ralph components (scripts, hooks, skills, config) to target repo
- Full GSD + Ralph workflow works immediately after install

---
*Last updated: 2026-03-10 after v2.1 milestone started*
