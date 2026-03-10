# Phase 11: Shell Launcher and Headless Invocation - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

The working autopilot: user adds `--ralph` to a GSD command and gets autonomous execution with permission control, worktree isolation, and loop-based completion. Delivers a `/gsd:ralph` skill, loop execution logic, permission tier mapping, and `--dry-run` preview. Builds on Phase 10's SKILL.md, config schema, context assembly, and architectural boundaries.

</domain>

<decisions>
## Implementation Decisions

### Loop behavior
- Completion detection via **STATE.md check**: after each iteration, re-read STATE.md to determine if the phase advanced or work is complete. Semantically correct — GSD updates STATE.md on completion.
- **No iteration cap**: rely on `max_turns` per iteration (from config) and Phase 12's circuit breaker for runaway prevention. Keeps Phase 11 simpler.
- **Retry once on failure**: if an iteration exits non-zero, retry once (fresh instance picks up from GSD state). If retry also fails, stop that step but move on to potential next work items if it makes sense.
- **No cooldown between iterations**: immediately launch next iteration after reassembling context from STATE.md. Context assembly handles the "fresh perspective" naturally.

### Default tool whitelist
- **Broad access, hardcoded**: `Write,Read,Edit,Grep,Glob,Bash(*)` baked into the launcher. Not configurable per-project — users who want different security posture use auto-mode or yolo tiers instead.
- **Yolo tier**: maps to `--dangerously-skip-permissions` (direct Claude Code flag).
- **Auto-mode tier**: Claude's discretion on exact flag mapping — research during planning to find the best match in Claude Code's current permission model.

### CLI invocation design
- **Separate `/gsd:ralph` skill** inside Claude Code: user types `/gsd:ralph execute-phase 11`. The skill parses the GSD command, assembles context, builds the `claude -p` command, spawns headless instance, and loops.
- **Claude Code only**: no standalone terminal script. The user is already inside Claude Code when they invoke this.
- **Slash command translation**: the skill translates the GSD slash command argument (e.g., `execute-phase 11`) into a natural language prompt for `claude -p`, since GSD slash commands are unavailable in headless mode.
- **`--dry-run`**: shows the exact `claude -p` command with all flags, system prompt file path, and a context file summary (file names + line counts). User can copy-paste to run manually if desired.

### Worktree isolation
- **Always on**: every iteration runs in an isolated worktree via Claude Code's `--worktree` flag. No option to disable. Autonomous code changes never touch the main working directory.
- **Claude Code handles lifecycle**: worktree creation, branch management, and merging are all Claude Code's responsibility. No merge logic in gsd-ralph (that was v1.x's job, now archived).
- **STATE.md check location**: Claude's discretion — depends on how `--worktree` handles the merge lifecycle. Research needed to confirm whether to check main or the worktree branch.

### Claude's Discretion
- Auto-mode tier exact flag mapping (research Claude Code's permission model)
- STATE.md check location relative to worktree lifecycle
- Natural language prompt construction format for `claude -p`
- Internal script/skill structure and function organization
- Inter-iteration cleanup (temp files, context file regeneration)

</decisions>

<specifics>
## Specific Ideas

- The `/gsd:ralph` skill pattern: user types `/gsd:ralph execute-phase 11` — the skill is a separate GSD extension, not a modification to existing GSD skills. Keeps existing skills untouched.
- Dry-run output format should show the full command, flags, and a summary of context (file names + line counts) — not the full context contents.
- Failure retry logic: retry once, then stop the failing step but continue to next work items if possible. This balances "walk away" autonomy with avoiding spiral failures.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/assemble-context.sh`: Phase 10 deliverable — assembles STATE.md + active phase plans into context blob for `--append-system-prompt-file`. Ready to use.
- `scripts/validate-config.sh`: Phase 10 deliverable — validates ralph config with strict-with-warnings semantics. Source this for config reading.
- `.claude/skills/gsd-ralph-autopilot/SKILL.md`: Phase 10 deliverable — autonomous behavior rules. Claude Code loads this via skill discovery. No launcher action needed.
- `.planning/config.json`: Contains `ralph.enabled`, `ralph.max_turns`, `ralph.permission_tier` — launcher reads these.
- `.ralphrc` (v1.x reference): `ALLOWED_TOOLS="Write,Read,Edit,Grep,Glob,Bash(*)"` — confirmed as the default whitelist for v2.0.

### Established Patterns
- Bash 3.2 compatibility: no associative arrays, no `${var,,}`, `date -u +%Y-%m-%dT%H:%M:%SZ`
- GSD skills live in `~/.claude/get-shit-done/` — the `/gsd:ralph` skill will follow this pattern
- GSD tools via `gsd-tools.cjs` for state operations
- Context assembly outputs to stdout or file path argument

### Integration Points
- `claude -p` CLI: headless execution entry point with `--append-system-prompt-file`, `--allowedTools`, `--max-turns`, `--worktree`
- GSD skill system: new skill registered for `/gsd:ralph` command
- STATE.md: read between iterations to detect completion
- `.planning/config.json`: read for ralph settings (max_turns, permission_tier)

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 11-shell-launcher-and-headless-invocation*
*Context gathered: 2026-03-10*
