# gsd-ralph

## What This Is

A standalone CLI tool that bridges GSD planning with Ralph autonomous execution. It provides a single-command workflow for turning planned phases into parallel autonomous execution with worktree isolation, progress monitoring, auto-merge, and cleanup — so the human stays in the loop for thinking and Ralph handles the doing.

## Core Value

One command takes a GSD-planned phase and produces merged, working code — no manual worktree setup, no hand-crafted prompts, no babysitting.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Initialize Ralph in any GSD project (create configs, GSD-aware prompts)
- [ ] Execute a full phase with one command (worktree creation, prompt generation, Ralph launch)
- [ ] Monitor status of all active worktrees for a phase
- [ ] Auto-merge completed branches when clean, flag conflicts
- [ ] Option to review branches before merging
- [ ] Terminal bell notifications when plans complete or fail
- [ ] Clean up worktrees and branches after phase completion
- [ ] Work with any GSD project (detect project stack, conventions)

### Out of Scope

- GSD plugin integration — standalone tool first, integration later
- Ralph plugin system — this wraps Ralph, doesn't extend it
- GUI or web dashboard — CLI only
- OS-level notifications (macOS Notification Center) — terminal bell is sufficient for v1
- Custom notification channels (Slack, email) — terminal only

## Context

- Extracted from bayesian-it where this workflow was developed as ad-hoc bash scripts
- Existing scripts (`scripts/`) serve as logic reference, not starting code — building clean
- GSD creates structured plans with phases, XML-format tasks, dependencies, and verification criteria
- Ralph is an autonomous Claude Code execution loop that works from PROMPT.md and fix_plan.md
- Templates (`templates/`) capture the prompt/config patterns that worked in bayesian-it
- The tool must understand both GSD's file layout (.planning/, ROADMAP.md, STATE.md, XML tasks, phase naming) and Ralph's conventions (.ralph/, PROMPT.md, fix_plan.md, .ralphrc)

## Constraints

- **Ecosystem**: Same tooling as GSD and Ralph — no exotic dependencies
- **Portability**: Must work on macOS (primary dev environment)
- **Non-invasive**: Works alongside existing GSD and Ralph installations, doesn't replace them
- **GSD dual naming**: Must handle both PLAN.md and NN-MM-PLAN.md conventions
- **Git worktrees**: Relies on git worktree for isolation — requires git repo

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Standalone CLI (not GSD/Ralph plugin) | Keeps tool independent, simpler to develop and test | — Pending |
| Auto-merge by default with review option | Optimizes for speed while preserving safety | — Pending |
| Terminal bell for notifications | Simplest approach, no extra deps, works everywhere | — Pending |
| Existing scripts as reference only | Clean architecture over incremental refactoring | — Pending |
| Same ecosystem as GSD/Ralph | Minimizes friction, no new runtime dependencies | — Pending |

---
*Last updated: 2025-02-13 after initialization*
