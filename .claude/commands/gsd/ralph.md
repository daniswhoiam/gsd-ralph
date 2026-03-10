---
name: gsd:ralph
description: Run a GSD command autonomously with Ralph autopilot
argument-hint: "<gsd-command> [--dry-run] [--tier default|auto-mode|yolo]"
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Bash
---

<objective>
Launch autonomous execution of a GSD command using Ralph autopilot.
Translates the GSD slash command into headless Claude Code invocations
with permission control, worktree isolation, and loop-based completion.
</objective>

<context>
Command: $ARGUMENTS

The user wants to run a GSD command autonomously. Ralph will:
1. Parse the command and flags (--dry-run, --tier)
2. Read config from .planning/config.json
3. Assemble GSD context (STATE.md + active phase plans)
4. Build a `claude -p` command with permission flags, worktree isolation, and max-turns
5. Execute in a loop until the phase is complete (or show a preview with --dry-run)
</context>

<instructions>
Run the Ralph launcher script from the project root:

```
bash scripts/ralph-launcher.sh $ARGUMENTS
```

The launcher handles everything: argument parsing, config reading, context assembly,
permission tier mapping, and command construction.

**What to expect:**
- With `--dry-run`: The script prints the exact `claude -p` command, context summary,
  and config values without executing anything. Relay this output to the user.
- Without `--dry-run`: The script launches headless Claude Code iterations in isolated
  worktrees until the GSD phase is complete.
- On error: The script prints error messages to stderr. Relay these to the user.

**Permission tiers:**
- `default` -- Scoped tool whitelist via --allowedTools
- `auto-mode` -- Claude risk-based auto-approval via --permission-mode auto
- `yolo` -- Full permission bypass via --dangerously-skip-permissions

**Examples:**
- `execute-phase 11` -- Execute phase 11 autonomously
- `execute-phase 11 --dry-run` -- Preview the command without running
- `execute-phase 11 --tier yolo` -- Execute with full permission bypass
- `verify-work 11 --dry-run` -- Preview verification command
</instructions>
