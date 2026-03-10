---
name: gsd-ralph-autopilot
description: |
  Autonomous behavior rules for gsd-ralph autopilot mode. Activates when
  executing GSD commands autonomously without human supervision. Handles
  decision points, checkpoints, and human-action steps automatically.
  Scoped to within-workflow decisions only -- does NOT trigger cross-workflow auto-advance.
user-invocable: false
---

# Ralph Autopilot Mode

You are running in autonomous mode via gsd-ralph. No human is present to
answer questions or approve actions. Follow these rules strictly.

## Rule 1: Never Ask Questions
- NEVER use AskUserQuestion. There is no human to respond.
- When GSD presents multi-option decisions: ALWAYS pick the FIRST option.
  GSD skills present the recommended option first. This is deterministic
  and debuggable.
- If you encounter a situation where you genuinely cannot proceed without
  human input, log the blocker and EXIT cleanly. Do not loop.

## Rule 2: Auto-Approve Checkpoints
- When a GSD workflow reaches a human-verify checkpoint, auto-approve it.
- For each approval, write a brief rationale explaining WHY it passes.
- Create a git commit at each checkpoint for incremental state review.
  Use format: `chore(checkpoint): <description of what was verified>`

## Rule 3: Skip Human-Action Steps
- If a step requires physical human action (e.g., "open browser and verify"),
  skip it entirely.
- Log skipped steps with their full action description.
- Mark as "SKIPPED (autonomous mode)" in any audit or execution log.

## Rule 4: Follow GSD Conventions
- Read STATE.md at the start to establish current position.
- Follow plan instructions precisely. One task = one commit.
- Use conventional commit format (feat/fix/chore/docs/test).
- Never modify PLAN.md or RESEARCH.md files (they are read-only).
- Update STATE.md after completing tasks.

## Rule 5: Clean Exit
- When all tasks in the current scope are complete, exit cleanly.
- Do not invent additional work beyond what the plan specifies.
- Do not refactor or improve code that is not part of the current task.

## Rule 6: Scope Boundary -- Ralph vs Auto-Advance

`--ralph` grants within-workflow autonomy. It does NOT grant cross-workflow chaining.

**What `--ralph` authorizes (current workflow only):**
- Auto-approve checkpoints (Rule 2)
- Pick first/default option at decision points (Rule 1)
- Skip human-action steps (Rule 3)
- All of Rules 1-5 apply to the CURRENT GSD workflow invocation only

**What `--ralph` does NOT authorize:**
- `--ralph` does NOT imply `--auto` (GSD's cross-workflow chaining flag)
- `--ralph` does NOT permit auto-advancing from plan-phase to execute-phase to transition
- `--ralph` does NOT permit invoking the next GSD workflow after the current one completes

**Boundary rule:**
- When the current GSD workflow completes, Ralph STOPS. No chaining to the next workflow.
- `--auto` is a GSD orchestrator concept. Ralph must not set, read, or act on
  `workflow._auto_chain_active` or `workflow.auto_advance`.
- If both `--ralph` and `--auto` are present, they operate independently:
  Ralph handles within-workflow autonomy; GSD handles cross-workflow chaining.
