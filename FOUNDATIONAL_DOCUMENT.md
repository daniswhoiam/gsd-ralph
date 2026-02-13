# gsd-ralph: GSD + Ralph Synthesis Tool

## What This Is

A CLI tool that bridges GSD (Get Shit Done) planning with Ralph autonomous execution. It provides a unified workflow for going from planned phases to parallel autonomous execution with worktree isolation, progress monitoring, and automated merge orchestration.

## The Problem

GSD creates structured plans with phases, tasks in XML format, dependencies, and verification criteria. Ralph is an autonomous Claude Code execution loop. Currently, connecting them requires:

- Manual worktree creation per plan
- Hand-crafting PROMPT.md files that teach Ralph about GSD conventions
- Custom task extraction from GSD's XML plan format into Ralph's fix_plan.md
- Manual monitoring and merge orchestration
- Understanding both systems' naming conventions and file layouts

This integration was built ad-hoc in the bayesian-it project. It works, but it's project-specific and fragile.

## The Solution

A standalone tool (`gsd-ralph`) that automates the entire GSD-to-Ralph pipeline:

1. **`gsd-ralph init`** — Set up Ralph in any GSD project (creates .ralph/, .ralphrc, GSD-aware PROMPT.md)
2. **`gsd-ralph execute N`** — Full phase execution orchestration (plan discovery, worktree creation, Ralph instructions)
3. **`gsd-ralph status N`** — Monitor all worktrees for a phase
4. **`gsd-ralph merge N`** — Merge completed branches with conflict guidance
5. **`gsd-ralph cleanup N`** — Remove worktrees and branches

## Key Design Principles

- **GSD-native**: Understands GSD file layout (.planning/, ROADMAP.md, STATE.md, XML task format, phase naming conventions)
- **Ralph-native**: Generates proper .ralph/ configs, PROMPT.md with status reporting, fix_plan.md task extraction
- **Project-agnostic**: Works with any GSD project, not just bayesian-it — detects project stack, test commands, etc.
- **Minimal config**: Sensible defaults, only ask what's necessary
- **Worktree-based isolation**: Each plan gets its own git worktree for parallel execution without conflicts

## Current State

Extracted from bayesian-it where it was developed as bash scripts:
- `ralph-execute.sh` — Phase execution orchestrator
- `ralph-worktrees.sh` — Worktree creation with GSD plan discovery
- `ralph-status.sh` — Progress monitoring
- `ralph-merge.sh` — Branch merging with conflict handling
- `ralph-cleanup.sh` — Worktree removal
- Template files for PROMPT.md, AGENT.md, .ralphrc, fix_plan.md

## Target Users

Developers using both GSD for planning and Ralph for autonomous execution who want a single command to go from "phase planned" to "code merged."

## Constraints

- Must work alongside existing GSD and Ralph installations (not replace them)
- Bash-based CLI for portability (same environment as Ralph)
- No additional runtime dependencies beyond what GSD and Ralph already require
- Must handle GSD's dual naming conventions (PLAN.md vs NN-MM-PLAN.md)

## Open Questions

- Should this be a GSD plugin, a Ralph plugin, or a standalone tool?
- Should it eventually replace the manual `ralph-setup` step for GSD projects?
- How to handle project-specific customization of PROMPT.md templates?
- Should it integrate with GSD's skill system (/gsd:execute-phase)?
