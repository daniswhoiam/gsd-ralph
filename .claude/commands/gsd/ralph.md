---
name: gsd:ralph
description: Run a GSD command autonomously with Ralph autopilot
argument-hint: "<gsd-command> [args] [--tier default|auto-mode|yolo]"
allowed-tools:
  - Read
  - Bash
  - Agent
---

<objective>
Run a GSD command autonomously using Ralph autopilot mode.
Spawns Agent subagents for each iteration with fresh context windows.
Circuit breakers (timeout, stop file, stall detection) protect against runaway loops.

This command uses the Agent tool — it does NOT spawn `claude -p` or any child
process. All execution stays within the current Claude Code session, avoiding
sandbox restrictions entirely.
</objective>

<context>
Arguments: $ARGUMENTS

Config: .planning/config.json (ralph section)
State: .planning/STATE.md
Context script: scripts/assemble-context.sh
Autopilot rules: .claude/skills/gsd-ralph-autopilot/SKILL.md
</context>

<instructions>

## Step 1: Parse Arguments

From $ARGUMENTS, extract:
- `gsd_command`: The GSD skill name (first word, e.g., "plan-phase", "execute-phase")
- `gsd_args`: Remaining arguments for the GSD skill (e.g., "17", "11 --gaps")
- `--tier <value>`: Ralph permission tier override (logged but not used in Agent mode)
- `--dry-run`: Show config summary and exit without executing

Example: `plan-phase 17 --tier yolo` -> gsd_command="plan-phase", gsd_args="17", tier="yolo"
Example: `execute-phase 11` -> gsd_command="execute-phase", gsd_args="11"

## Step 2: Read Config and Pre-flight

Read Ralph config:
```bash
jq -r '.ralph // {}' .planning/config.json 2>/dev/null
```

Extract: `max_turns` (default 50), `timeout_minutes` (default 30), `enabled` (default true).

Pre-flight checks (stop on any failure):
1. `.planning/STATE.md` must exist
2. `scripts/assemble-context.sh` must exist
3. `enabled` must not be false

If `--dry-run`: Display config summary and the command that would run, then stop.

## Step 3: Assemble Context

```bash
bash scripts/assemble-context.sh /tmp/ralph-ctx-$$.txt && cat /tmp/ralph-ctx-$$.txt
```

Store the output as `assembled_context` for use in the agent prompt.

## Step 4: Read Autopilot Rules

Read `.claude/skills/gsd-ralph-autopilot/SKILL.md` and extract everything after the YAML frontmatter closing `---`. Store as `autopilot_rules`.

## Step 5: Display Start Banner

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► RALPH STARTING
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Command: /gsd:{gsd_command} {gsd_args} --ralph
Timeout: {timeout_minutes}m
Max iterations: 10

◆ Spawning agent...
```

## Step 6: Execution Loop

Initialize:
- `iteration = 0`
- `max_iterations = 10`
- Record current time for timeout tracking
- `consecutive_no_progress = 0`

### For each iteration:

**6a. Circuit breakers** (check ALL before each iteration):

1. **Timeout**: Estimate elapsed time. If approaching `timeout_minutes`, stop.
2. **Stop file**: `test -f .ralph/.stop` — if found, remove it and stop with message.
3. **Iteration cap**: If `iteration >= max_iterations`, stop.

If any breaker trips, skip to Step 7 with the appropriate reason.

**6b. Capture pre-iteration state snapshot:**
```bash
grep -E 'Phase:|Plan:|Status:' .planning/STATE.md 2>/dev/null | tr '\n' '|'
```

**6c. Re-assemble context (fresh each iteration):**
```bash
bash scripts/assemble-context.sh /tmp/ralph-ctx-$$.txt && cat /tmp/ralph-ctx-$$.txt
```

**6d. Spawn Agent subagent:**

Use the Agent tool:
- `subagent_type`: `"general-purpose"`
- `description`: `"Ralph iter {N}: {gsd_command}"`
- `prompt`: Fill the template below with actual values

**AGENT PROMPT TEMPLATE** (substitute all `{variables}`):

```
You are Ralph autopilot — an autonomous GSD agent executing without human supervision.

## YOUR TASK

Execute the GSD command: {gsd_command} {gsd_args} --ralph

Read the workflow file for this command and follow its instructions end-to-end:
- plan-phase: $HOME/.claude/get-shit-done/workflows/plan-phase.md
- execute-phase: $HOME/.claude/get-shit-done/workflows/execute-phase.md
- verify-work: $HOME/.claude/get-shit-done/workflows/verify-work.md
- discuss-phase: $HOME/.claude/get-shit-done/workflows/discuss-phase.md

Read the matching workflow file using the Read tool, then execute its process steps
using your available tools (Read, Write, Edit, Bash, Grep, Glob, Agent).
Do NOT use the Skill tool — it triggers permission prompts that block autonomous execution.

## AUTOPILOT RULES (MANDATORY)

{autopilot_rules}

## PROJECT CONTEXT

{assembled_context}

## EXECUTION RULES

1. NEVER use AskUserQuestion — no human is present to respond
2. At decision points with options, ALWAYS pick the FIRST option
3. Auto-approve all checkpoints with brief rationale
4. When the command completes, summarize what was accomplished
5. If blocked on something you cannot resolve, report the blocker and exit cleanly
6. Do NOT chain to the next workflow after completion — stop when this command finishes
7. The --ralph flag means within-workflow autonomy only, NOT cross-workflow chaining
```

**6e. After agent returns:**

Display iteration summary:
```
Ralph: Iter {N} complete | {brief_summary_from_agent}
```

Increment `iteration`.

**6f. Check completion:**

For plan-phase: check if PLAN.md files exist in the phase directory:
```bash
ls .planning/phases/*{phase_number}*/*-PLAN.md 2>/dev/null | head -5
```

For execute-phase/verify-work: check STATE.md status:
```bash
grep -E 'Status:' .planning/STATE.md | head -1
```

If the command's deliverables exist and/or status indicates completion: exit loop.

**6g. Progress detection:**

Capture post-iteration state:
```bash
grep -E 'Phase:|Plan:|Status:' .planning/STATE.md 2>/dev/null | tr '\n' '|'
```

Compare with pre-iteration snapshot (6b):
- Different -> progress made, reset `consecutive_no_progress = 0`
- Same -> increment `consecutive_no_progress`
- If `consecutive_no_progress >= 2` -> stop (stalled, no retry will help)

## Step 7: Report Results

**On success:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► RALPH COMPLETE ✓
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Command: /gsd:{gsd_command} {gsd_args}
Iterations: {N}
Result: Complete
```

**On failure/stop:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 GSD ► RALPH STOPPED
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Command: /gsd:{gsd_command} {gsd_args}
Iterations: {N}
Reason: {timeout | stalled | stop_file | max_iterations | error}

Continue manually:
/gsd:{gsd_command} {gsd_args}
```

</instructions>
