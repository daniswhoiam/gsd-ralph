# gsd-ralph

## What This Is

A thin integration layer that enables any GSD command to run autonomously via Ralph. Instead of a standalone CLI with its own lifecycle, gsd-ralph acts as an autopilot mode for GSD — adding `--ralph` to any GSD command makes Ralph handle all user input, permissions, and decisions automatically. Leverages Claude Code's native worktree isolation and GSD's existing execution model.

## Core Value

Add `--ralph` to any GSD command and walk away — Ralph drives, GSD works, code ships.

## Current Milestone: v2.0 Autopilot Core

**Goal:** Complete rewrite from standalone CLI to thin GSD autopilot layer

**Target features:**
- `--ralph` flag on any GSD command for autonomous execution
- Auto-response to GSD's AskUserQuestion checkpoints
- Auto-permission for Claude Code tool calls
- Uses Claude Code's native worktree isolation (no custom worktree management)

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

- [ ] `--ralph` flag enables autonomous execution of any GSD command
- [ ] Auto-respond to AskUserQuestion checkpoints during GSD workflows
- [ ] Auto-permit Claude Code tool calls in Ralph mode
- [ ] Use Claude Code's native worktree isolation instead of custom worktree management

### Out of Scope

- Intelligent response strategies (context-aware checkpoint answers) — v2.1+
- Parallel plan execution via multiple worktrees — v2.1+
- Custom LLM provider support — coupled to Ralph + Claude Code intentionally
- GUI or web dashboard — CLI only, target users are terminal-native
- Multi-repo support — single git repo only
- v1.x standalone CLI features (init, generate, execute, merge, cleanup) — superseded by GSD native commands

## Context

v2.0 is a complete rewrite. v1.x (9,693 LOC Bash, 211 tests) archived — it was a standalone CLI with its own lifecycle commands. The architectural insight: GSD already handles planning/execution/verification; Ralph already handles autonomous coding. gsd-ralph just needs to bridge the gap by making Ralph act as the "user" for GSD commands.

Reference implementations: gsd-skill-creator (Tibsfox) shows how to extend GSD via skills/hooks/agents without duplicating logic.

Claude Code capabilities that make v1.x architecture obsolete:
- Native worktree isolation (`--worktree`, `isolation: "worktree"` on subagents)
- Headless mode (`claude -p` with `--allowedTools` for auto-approval)
- Built-in GSD skill/hook/command extension points

## Constraints

- **Thin layer**: Must not replicate logic that lives in GSD or Ralph
- **GSD-compatible**: Updates to GSD should flow through without breaking gsd-ralph
- **Portability**: Must work on macOS (primary dev environment)
- **Non-invasive**: Works alongside existing GSD and Ralph installations

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| v1.x: Standalone Bash CLI | Kept tool independent during exploration phase | ⚠️ Revisit — v2.0 pivots to thin integration layer |
| v2.0: Rewrite as GSD integration layer | GSD + Claude Code now handle what v1.x built manually (worktrees, execution, merging) | — Pending |
| v2.0: `--ralph` flag model | User mental model: same GSD commands, just add `--ralph` for autopilot | — Pending |
| v2.0: Leverage Claude Code headless mode | `claude -p` + `--allowedTools` provides auto-permission foundation | — Pending |
| v2.0: Archive v1.x, don't salvage | Clean break avoids legacy patterns dragging into new architecture | — Pending |

---
*Last updated: 2026-03-09 after v2.0 milestone start*
