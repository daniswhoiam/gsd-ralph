# Architecture Research

**Domain:** Autopilot integration layer for GSD + Claude Code + Ralph
**Researched:** 2026-03-09
**Confidence:** HIGH (official docs verified, bug fix confirmed, codebase inspected)

## The Integration Challenge

GSD commands run inside a Claude Code session. When a GSD workflow calls `AskUserQuestion`, Claude Code presents it to the user as an interactive dialog. With `--ralph`, Ralph needs to answer instead. The fundamental questions:

1. How to intercept/auto-respond to `AskUserQuestion` calls
2. How to handle tool permission auto-approval
3. Where the "ralph wrapper" lives
4. What GSD components need extending vs wrapping

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    User's Terminal                               │
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │  /gsd:execute-phase 3 --ralph                           │    │
│  │                                                         │    │
│  │  GSD Workflow (execute-phase.md)                        │    │
│  │    │                                                    │    │
│  │    ├── gsd-tools.cjs init                               │    │
│  │    ├── gsd-tools.cjs phase-plan-index                   │    │
│  │    ├── Spawn gsd-executor subagents (Agent tool)        │    │
│  │    │     │                                              │    │
│  │    │     ├── Execute tasks (Bash, Read, Write, Edit)    │    │
│  │    │     ├── Hit checkpoint → AskUserQuestion  <── (A)  │    │
│  │    │     └── Return structured state                    │    │
│  │    │                                                    │    │
│  │    ├── Present checkpoint to user <── (B)               │    │
│  │    ├── AskUserQuestion (orchestrator level) <── (C)     │    │
│  │    └── Spawn continuation agent with response           │    │
│  │                                                         │    │
│  │  Claude Code Runtime                                    │    │
│  │    ├── Permission system <── (D)                        │    │
│  │    ├── Tool approval prompts <── (D)                    │    │
│  │    └── Hooks (PreToolUse, Notification, etc.)           │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘

Intercept points:
  (A) Executor subagent checkpoints: returned as structured state, NOT interactive
  (B) Orchestrator presents checkpoint: uses AskUserQuestion
  (C) Orchestrator-level decisions: uses AskUserQuestion
  (D) Claude Code permission prompts: separate from GSD checkpoints
```

## Component Responsibilities

| Component | Responsibility | Current Implementation |
|-----------|----------------|------------------------|
| GSD Workflows | Phase/plan orchestration, checkpoint handling, verification | Markdown workflow files in `~/.claude/get-shit-done/workflows/` |
| GSD Tools CLI | State management, config, roadmap updates | Node.js `gsd-tools.cjs` |
| Claude Code | Tool execution, permission system, hooks, subagents | Binary CLI (`claude`) |
| Ralph | Autonomous loop, session management, exit detection | Bash script (`ralph_loop.sh`) |
| gsd-ralph v2.0 | **Bridge: auto-answer + auto-permit + launch** | **To be built** |

## Integration Point Analysis

### Integration Point 1: AskUserQuestion Interception

**Current state (March 2026):**

The `AskUserQuestion` tool is Claude Code's internal tool for presenting structured questions to users. When GSD workflows call `AskUserQuestion`, Claude Code renders it as an interactive dialog and blocks until the user responds.

**Critical finding:** Claude Code's hook system does NOT natively support auto-responding to `AskUserQuestion`. A feature request (issue #12605) was filed Nov 2025 and closed as duplicate. The PreToolUse hook can detect `AskUserQuestion` calls and read the question data, but it cannot inject a response -- it can only `allow`, `deny`, or `ask`.

**Bug status:** A related bug (#12031) where PreToolUse hooks stripped AskUserQuestion result data was fixed in v2.0.76 (confirmed Jan 2026). PreToolUse hooks now correctly preserve AskUserQuestion results.

**Available approaches (ranked by feasibility):**

| Approach | Feasibility | Mechanism | Risk |
|----------|-------------|-----------|------|
| **A: GSD config `workflow.auto_advance`** | HIGH | GSD already has auto-mode that auto-approves checkpoints | Does not cover all AskUserQuestion uses (discovery, new-project, settings) |
| **B: Headless mode `-p` with `--allowedTools`** | HIGH | Running GSD command via `claude -p` bypasses interactive prompts entirely | AskUserQuestion calls fail silently in headless mode; subagent clarifications auto-deny |
| **C: Prompt engineering** | HIGH | System prompt tells Claude to never call AskUserQuestion, always proceed with defaults | Relies on model compliance; most robust when combined with A |
| **D: PreToolUse hook deny + context injection** | MEDIUM | Deny AskUserQuestion, inject auto-response via `permissionDecisionReason` | Model sees denial feedback, may not interpret as "use this answer" |
| **E: Custom Notification hook** | LOW | `elicitation_dialog` notification fires when AskUserQuestion presents | Cannot inject response, only detect it |

**Recommended approach: Combine A + B + C.**

1. **Set `workflow.auto_advance: true` and `workflow._auto_chain_active: true`** in config before launching. This makes GSD's execute-phase auto-approve `human-verify` checkpoints and auto-select first option for `decision` checkpoints.

2. **Use `claude -p` (headless mode)** with `--allowedTools` for the session. In headless mode, background subagents auto-deny any `AskUserQuestion` calls that are not pre-approved, and the session runs non-interactively.

3. **Inject system prompt via `--append-system-prompt`** telling the agent: "You are running in autonomous mode. Do not call AskUserQuestion. For checkpoints, auto-approve human-verify, auto-select first option for decisions, and skip human-action. Treat all verification as passed unless tests fail."

This triple-layered approach means:
- GSD's own auto-mode handles most checkpoint logic at the workflow level
- Headless mode prevents any interactive blocking at the Claude Code level
- System prompt guidance prevents the model from attempting AskUserQuestion at all

### Integration Point 2: Tool Permission Auto-Approval

**Current state:** Claude Code has multiple permission modes:

| Mode | Behavior | How to enable |
|------|----------|---------------|
| `default` | Prompts for each tool use | Default |
| `acceptEdits` | Auto-accepts file edits only | `--permission-mode acceptEdits` |
| `bypassPermissions` | Skips ALL permission checks | `--dangerously-skip-permissions` |
| Scoped `--allowedTools` | Auto-approve listed tools only | `--allowedTools "Bash,Read,Edit,Write"` |

**Recommended approach: `--allowedTools` with explicit list.**

Do NOT use `--dangerously-skip-permissions`. It provides no safety guardrails and community data shows 32% of users experienced unintended modifications.

Instead, use a carefully scoped allowlist:

```bash
claude -p "$PROMPT" \
  --allowedTools "Bash,Read,Write,Edit,Grep,Glob,Agent" \
  --max-turns 200
```

This auto-approves the standard development tools while keeping the permission infrastructure active. The `Agent` tool permission allows spawning subagents (which GSD's execute-phase needs). The `--max-turns` flag provides a safety net against runaway loops.

**Important:** `PermissionRequest` hooks do NOT fire in headless mode (`-p`). Use `PreToolUse` hooks instead for any automated permission decisions.

### Integration Point 3: Where the Ralph Wrapper Lives

**Analysis of options:**

| Option | What it is | Pros | Cons |
|--------|-----------|------|------|
| **Shell script launcher** | `gsd-ralph` bash script that runs `claude -p` | Simple, portable, can set env vars and config | Separate from GSD command invocation |
| **Claude Code hook** | Hook that intercepts GSD command invocation | Runs within Claude Code context | Hooks cannot launch new Claude Code sessions |
| **GSD skill** | `.claude/skills/ralph-mode/SKILL.md` | Native GSD extension point, discoverable | Skills are invoked INSIDE a session, cannot configure session launch parameters |
| **GSD custom subagent** | `.claude/agents/ralph-executor.md` | Can define `permissionMode`, `hooks`, `allowed-tools` | Runs inside existing session, cannot set `-p` or `--allowedTools` for the session |
| **Wrapper skill + launcher script** | Skill provides prompts/behavior, script provides launch config | Best of both: native GSD integration + session control | Two components to maintain |

**Recommended: Wrapper skill + launcher script.**

The launcher script and skill work together:

1. **`bin/gsd-ralph`** -- Shell script that:
   - Reads `.planning/config.json` to set `workflow.auto_advance: true`
   - Constructs the `claude -p` command with appropriate flags
   - Passes the GSD command as the prompt
   - Handles worktree creation via `--worktree`
   - Manages session output

2. **`skills/ralph-mode/SKILL.md`** -- Autonomous behavior instructions that:
   - Instruct the model to never call AskUserQuestion
   - Define auto-approve rules for each checkpoint type
   - Specify default selections for decision checkpoints
   - Define error escalation rules

3. **Hook configuration** -- In `.claude/settings.json` or `.claude/settings.local.json`:
   - `PreToolUse` hook for `AskUserQuestion` that denies with guidance (defense-in-depth)

### Integration Point 4: GSD Extension vs Wrapping

**What to extend:**

| GSD Component | Extend or Wrap | How |
|---------------|----------------|-----|
| `config.json` | **Extend** | Add `ralph.enabled`, `ralph.auto_respond_strategy`, `ralph.allowed_tools` fields |
| `execute-phase.md` | **Wrap** (do not modify) | Launch via `claude -p` with ralph-mode system prompt; GSD's existing `--auto` flag handles most auto-advance logic |
| `execute-plan.md` | **No change** | Subagent executor already works autonomously for `autonomous: true` plans |
| `checkpoints.md` | **No change** | Auto-mode rules already define behavior for each checkpoint type |
| `plan-phase.md` | **Wrap** | Similar pattern: launch via `claude -p` with auto-advance |
| `transition.md` | **No change** | Already chains automatically when `--auto` flag is present |
| `new-project.md` / `new-milestone.md` | **Out of scope v2.0** | Heavy AskUserQuestion usage for discovery; requires intelligent response strategies (v2.1+) |
| `settings.md` | **Out of scope v2.0** | Interactive configuration; not needed for autonomous execution |

**What GSD already provides for autonomous execution:**

1. **`--auto` flag on execute-phase**: Sets `workflow._auto_chain_active: true`, auto-approves `human-verify` checkpoints, auto-selects first option for `decision` checkpoints, stops only on `human-action` (auth gates).

2. **`--no-transition` flag**: Prevents transition.md from running, useful when Ralph controls the pipeline.

3. **`--gaps-only` flag**: Executes only gap-closure plans, useful for automated re-runs after verification failures.

4. **`workflow.auto_advance` config**: Persistent version of `--auto` that applies to all executions.

## Recommended Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   gsd-ralph v2.0                                │
│                                                                 │
│  ┌──────────────────────┐  ┌────────────────────────────────┐  │
│  │  bin/gsd-ralph        │  │  skills/ralph-mode/            │  │
│  │  (Shell Entry Point)  │  │  SKILL.md                      │  │
│  │                       │  │  (Autonomous behavior rules)   │  │
│  │  - Parse --ralph      │  │                                │  │
│  │  - Set config flags   │  │  - No AskUserQuestion          │  │
│  │  - Build claude -p    │  │  - Auto-approve checkpoints    │  │
│  │  - Launch in worktree │  │  - Default selections          │  │
│  │  - Monitor/timeout    │  │  - Error escalation rules      │  │
│  └──────┬────────────────┘  └────────────────────────────────┘  │
│         │                                                       │
│         │  Invokes:                                             │
│         │  claude -p "$GSD_COMMAND"                             │
│         │    --allowedTools "Bash,Read,Write,Edit,..."          │
│         │    --worktree "ralph-phase-3"                         │
│         │    --append-system-prompt "@SKILL.md"                 │
│         │    --max-turns 200                                    │
│         │    --output-format json                               │
│         │                                                       │
│  ┌──────┴───────────────────────────────────────────────────┐  │
│  │  .claude/hooks/ (optional, defense-in-depth)              │  │
│  │                                                           │  │
│  │  PreToolUse: AskUserQuestion → deny + inject guidance     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Config extension (.planning/config.json)                 │  │
│  │                                                           │  │
│  │  ralph: {                                                 │  │
│  │    enabled: true,                                         │  │
│  │    allowed_tools: "Bash,Read,Write,Edit,Grep,Glob,Agent", │  │
│  │    max_turns: 200,                                        │  │
│  │    worktree_prefix: "ralph"                               │  │
│  │  }                                                        │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

## Recommended Project Structure

```
gsd-ralph/
├── bin/
│   └── gsd-ralph              # Shell launcher script (entry point)
├── skills/
│   └── ralph-mode/
│       └── SKILL.md            # Autonomous behavior prompt
├── hooks/
│   └── deny-ask.sh            # PreToolUse hook for AskUserQuestion
├── install.sh                  # Installer: copies skill + creates launcher
├── .planning/                  # GSD planning artifacts (existing)
└── tests/                      # Test suites
```

### Structure Rationale

- **`bin/gsd-ralph`:** Entry point that users invoke. Reads config, constructs `claude -p` invocation, manages worktrees. Thin -- under 200 lines.
- **`skills/ralph-mode/`:** Contains the autonomous behavior rules as a Claude Code skill. Installed to `~/.claude/skills/ralph-mode/` by the installer. This is the "brain" -- tells Claude how to behave in autonomous mode.
- **`hooks/`:** Optional hooks for defense-in-depth AskUserQuestion denial. Installed to project or user settings.
- **`install.sh`:** One-time setup that copies the skill and configures hooks.

## Architectural Patterns

### Pattern 1: Headless Delegation

**What:** Launch a Claude Code headless session (`claude -p`) that runs a GSD command with auto-mode flags, system prompt injection, and scoped tool permissions.

**When to use:** Every `--ralph` invocation. This is the core pattern.

**Trade-offs:**
- Pro: Clean separation -- no modification to GSD internals
- Pro: `claude -p` is the officially supported automation interface
- Pro: Works with Claude Code's native worktree isolation
- Con: Cannot intercept mid-session events from outside (fire-and-forget)
- Con: Context window is consumed by both system prompt and GSD workflow

**Example:**

```bash
#!/bin/bash
# bin/gsd-ralph -- simplified core pattern

COMMAND="$1"  # e.g., "execute-phase 3"
WORKTREE_NAME="ralph-$(echo "$COMMAND" | tr ' ' '-')"

# Pre-configure GSD for auto-mode
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow.auto_advance true
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow._auto_chain_active true

# Build the prompt
PROMPT="/gsd:${COMMAND} --auto"

# Launch headless Claude Code session
claude -p "$PROMPT" \
  --allowedTools "Bash,Read,Write,Edit,Grep,Glob,Agent" \
  --append-system-prompt "$(cat ~/.claude/skills/ralph-mode/SKILL.md)" \
  --worktree "$WORKTREE_NAME" \
  --max-turns 200 \
  --output-format json
```

### Pattern 2: Config-Driven Behavior Switch

**What:** Use GSD's existing `config.json` to toggle autonomous behavior without modifying workflow files. GSD workflows already read config values like `workflow.auto_advance`.

**When to use:** To control GSD checkpoint behavior from outside.

**Trade-offs:**
- Pro: Zero modification to GSD workflows
- Pro: Persistent -- survives session restarts
- Con: Config changes affect all sessions in the project, not just Ralph

**Mitigation:** Use worktree isolation. Each Ralph session runs in its own worktree with its own `.planning/config.json`, so config changes are isolated.

### Pattern 3: System Prompt Layering

**What:** Use `--append-system-prompt` to inject autonomous behavior rules on top of Claude Code's default system prompt and GSD's workflow instructions.

**When to use:** To prevent AskUserQuestion calls and guide autonomous decision-making.

**Trade-offs:**
- Pro: Does not require hooks or config changes
- Pro: Model sees the instructions at highest priority
- Con: Consumes context window space
- Con: Model compliance is probabilistic (mitigated by defense-in-depth with hooks)

### Pattern 4: Defense-in-Depth AskUserQuestion Handling

**What:** Layer multiple mechanisms to ensure AskUserQuestion never blocks execution:

1. System prompt: "Never call AskUserQuestion"
2. GSD auto-mode: Auto-approves checkpoints at workflow level
3. PreToolUse hook: Denies AskUserQuestion with guidance feedback
4. Headless mode: Auto-denies interactive prompts

**When to use:** Critical for reliability. Any single layer might fail; all four together provide near-certainty.

## Data Flow

### Ralph Execution Flow

```
User: gsd-ralph execute-phase 3
    |
    v
[bin/gsd-ralph] Parse command, read config
    |
    ├── Set config: workflow.auto_advance = true
    ├── Set config: workflow._auto_chain_active = true
    |
    v
[claude -p] Headless session with:
    ├── Prompt: "/gsd:execute-phase 3 --auto"
    ├── System prompt: ralph-mode SKILL.md (appended)
    ├── Allowed tools: Bash,Read,Write,Edit,Grep,Glob,Agent
    ├── Worktree: ralph-execute-phase-3
    └── Max turns: 200
    |
    v
[GSD execute-phase.md] Standard workflow runs:
    ├── init -> phase-plan-index -> discover plans
    ├── For each wave:
    │   ├── Spawn gsd-executor subagents (Agent tool)
    │   │   └── Execute tasks -> commit -> create SUMMARY.md
    │   ├── Auto-approve checkpoints (auto-mode active)
    │   └── Continue to next wave
    ├── Verify phase goal (gsd-verifier subagent)
    ├── Update roadmap
    └── Return result
    |
    v
[bin/gsd-ralph] Parse JSON output, report status
```

### Checkpoint Auto-Response Flow

```
GSD executor hits checkpoint task
    |
    v
Subagent returns structured state to orchestrator
(NOT interactive -- subagent cannot call AskUserQuestion)
    |
    v
Orchestrator receives checkpoint:
    |
    ├── auto_advance=true AND type=human-verify:
    │   -> Auto-approve, spawn continuation with "approved"
    │   -> Log "Auto-approved checkpoint"
    |
    ├── auto_advance=true AND type=decision:
    │   -> Auto-select first option
    │   -> Log "Auto-selected: [option]"
    |
    └── type=human-action:
        -> In non-ralph mode: present to user
        -> In ralph mode: system prompt says "skip, log as blocked"
        -> Orchestrator continues with remaining plans
```

## Anti-Patterns

### Anti-Pattern 1: Modifying GSD Workflow Files

**What people do:** Fork or patch `execute-phase.md`, `execute-plan.md`, etc. to add Ralph-specific logic.

**Why it's wrong:** GSD updates frequently. Any modification creates a maintenance burden and breaks when GSD updates. The project constraint explicitly states "GSD-compatible: Updates to GSD should flow through without breaking gsd-ralph."

**Do this instead:** Use config flags, system prompt injection, and hooks. GSD's existing `--auto` mode and `workflow.auto_advance` config already handle 95% of the automation needs.

### Anti-Pattern 2: Using `--dangerously-skip-permissions`

**What people do:** Use the nuclear option to avoid all permission prompts.

**Why it's wrong:** No safety guardrails. 32% of users report unintended modifications. The flag exists for sandboxed CI/CD environments, not for development machines.

**Do this instead:** Use `--allowedTools` with an explicit list. This auto-approves the tools Ralph needs while keeping the permission infrastructure active for everything else.

### Anti-Pattern 3: Trying to Programmatically Input to AskUserQuestion

**What people do:** Try to pipe input to the Claude Code process, use OS-level automation (AppleScript, xdotool), or hack the terminal to auto-respond.

**Why it's wrong:** Fragile, platform-dependent, breaks on Claude Code updates, and Claude Code's internal tool handling does not expose an input API.

**Do this instead:** Prevent AskUserQuestion from being called in the first place (system prompt + auto-mode), and use headless mode (`-p`) where interactive prompts fail gracefully.

### Anti-Pattern 4: Running Ralph in the Main Worktree

**What people do:** Execute autonomous sessions in the user's main working directory.

**Why it's wrong:** File conflicts with user's in-progress work, no rollback safety, merge conflicts if user is also editing.

**Do this instead:** Use `--worktree` flag for every Ralph session. Claude Code's native worktree isolation creates a clean git worktree, and cleanup is automatic when the session ends.

### Anti-Pattern 5: Custom Worktree Management

**What people do:** Implement worktree creation, tracking, and cleanup in shell scripts (as v1.x did).

**Why it's wrong:** Claude Code natively supports `--worktree` (since Feb 2026) and subagent `isolation: "worktree"`. Custom management duplicates this and diverges from upstream behavior.

**Do this instead:** Use `claude -p --worktree "name"` for session-level isolation and let Claude Code handle worktree lifecycle.

## Integration Points Summary

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Claude Code CLI | `claude -p` with flags | Primary interface; all interaction through CLI flags |
| GSD Tools CLI | `node gsd-tools.cjs` | Config management, state queries; called from launch script |
| Git | Native via Claude Code worktree | No custom git management needed |
| Ralph (upstream) | Optional; provides loop/monitor | gsd-ralph can work standalone or integrate with Ralph's loop |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Launch script <-> Claude Code | CLI flags + JSON output | Fire-and-wait; parse JSON result |
| SKILL.md <-> GSD workflows | System prompt injection | Skill content is appended to system prompt |
| Config <-> GSD workflows | `config.json` reads | GSD workflows read config at init; set before launch |
| Hooks <-> Claude Code | stdin JSON / exit codes | PreToolUse for AskUserQuestion denial |
| Worktree <-> Main repo | Git worktree branching | Isolated; merged back manually or via GSD commands |

## Build Order Recommendation

Based on dependency analysis:

| Phase | Component | Depends On | Why This Order |
|-------|-----------|------------|----------------|
| 1 | **SKILL.md autonomous behavior prompt** | Nothing | Core brain; everything else references this |
| 2 | **Config extension** | SKILL.md design | Needs to know what config fields the skill references |
| 3 | **Launch script (`bin/gsd-ralph`)** | SKILL.md + Config | Assembles the `claude -p` invocation using both |
| 4 | **PreToolUse hook for AskUserQuestion** | Launch script | Defense-in-depth; launch script works without it |
| 5 | **Installer** | All above | Copies components to correct locations |
| 6 | **Integration tests** | All above | End-to-end verification of full pipeline |

## Open Questions

1. **`--worktree` + GSD `.planning/` isolation:** When Claude Code creates a worktree, does `.planning/` get its own copy or is it shared? Need to verify. If shared, config changes in the worktree affect the main repo. If copied, Ralph's config changes are isolated but state updates need merging.

2. **Headless mode + `/gsd:` skill invocation:** Does `claude -p "/gsd:execute-phase 3"` correctly trigger the GSD skill? The docs say user-invoked skills like `/commit` are "only available in interactive mode." Need to verify that GSD workflow skills work in `-p` mode, or if the prompt needs to be phrased differently (e.g., including the workflow content directly instead of the slash command).

3. **Session continuation:** If a Ralph session hits `--max-turns` or a `human-action` checkpoint, can `claude -p --continue` resume it? The docs confirm `--continue` works with `-p`, but need to verify it preserves the auto-mode context.

4. **Subagent tool inheritance in headless mode:** When `claude -p --allowedTools "Bash,Read,Write,Edit,Agent"` spawns a subagent via `Agent`, does the subagent inherit the `--allowedTools` list? The docs say subagents inherit the parent's permissions but need to verify for headless mode.

5. **Ralph upstream integration:** How tightly should gsd-ralph integrate with Ralph's loop/monitor scripts? The v2.0 architecture can work standalone (single `claude -p` invocation), but Ralph provides rate limiting, circuit breaking, and session continuity that may be valuable for long-running autonomous executions.

## Sources

- [Claude Code Hooks Guide](https://code.claude.com/docs/en/hooks-guide) - Official hook documentation (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - Full event schemas and JSON formats (HIGH confidence)
- [Claude Code Headless Mode / Agent SDK](https://code.claude.com/docs/en/headless) - `-p` flag, `--allowedTools` (HIGH confidence)
- [Claude Code Skills](https://code.claude.com/docs/en/skills) - Skill format, frontmatter, invocation control (HIGH confidence)
- [Claude Code Subagents](https://code.claude.com/docs/en/sub-agents) - Custom agents, isolation, hooks (HIGH confidence)
- [AskUserQuestion Hook Feature Request (#12605)](https://github.com/anthropics/claude-code/issues/12605) - Confirmed limitation (HIGH confidence)
- [PreToolUse AskUserQuestion Bug (#12031)](https://github.com/anthropics/claude-code/issues/12031) - Fixed in v2.0.76 (HIGH confidence)
- [Claude Code Worktree Support](https://www.threads.com/@boris_cherny/post/DVAAnexgRUj) - `--worktree` flag announcement (HIGH confidence)
- [Ralph Claude Code](https://github.com/frankbria/ralph-claude-code) - Ralph loop implementation (MEDIUM confidence)
- GSD `execute-phase.md` - Codebase inspection (HIGH confidence)
- GSD `execute-plan.md` - Codebase inspection (HIGH confidence)
- GSD `checkpoints.md` - Codebase inspection (HIGH confidence)

---
*Architecture research for: gsd-ralph v2.0 autopilot integration layer*
*Researched: 2026-03-09*
