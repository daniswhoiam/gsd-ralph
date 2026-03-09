---
name: gsd-ralph-autopilot
description: |
  Autonomous behavior rules for gsd-ralph autopilot mode. Activates when
  executing GSD commands autonomously without human supervision. Handles
  decision points, checkpoints, and human-action steps automatically.
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
