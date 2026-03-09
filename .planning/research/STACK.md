# Stack Research: v2.0 Autopilot Integration Layer

**Domain:** Claude Code integration layer for autonomous GSD execution
**Researched:** 2026-03-09
**Confidence:** HIGH

**Scope:** This document covers ONLY the stack needed to build a thin integration layer that intercepts GSD's user interaction points and auto-responds via Ralph. The v1.x Bash CLI stack (9,693 LOC) is archived -- this is a complete architectural pivot. See `.planning/PROJECT.md` for rationale.

## Executive Summary

The v2.0 autopilot layer needs **zero new runtime dependencies** beyond what GSD and Claude Code already provide. The entire integration is achievable through three native Claude Code mechanisms: (1) a `PermissionRequest` hook to auto-allow tool calls, (2) a custom subagent with `permissionMode: "bypassPermissions"` for headless execution, and (3) the `--allowedTools` CLI flag for `-p` mode invocations. GSD's existing checkpoint system already supports auto-mode via `workflow.auto_advance` config. The integration is approximately 200-400 lines of code, not 9,693.

## Core Finding: Three Mechanism Layers

The integration layer operates at three distinct levels. Each handles a different type of user interaction that GSD currently requires.

### Layer 1: Tool Permission Auto-Approval

**Problem:** When GSD spawns executor subagents, those agents request permission for Bash, Write, Edit, etc. In interactive mode, the user clicks "Allow." In Ralph mode, nobody is there to click.

**Solution:** Claude Code's `--allowedTools` flag (for `-p` mode) or `permissionMode: "bypassPermissions"` (for subagent definitions).

**Verified mechanism (Claude Code v2.1.71, official docs):**

```bash
# Headless mode: auto-approve all tools
claude -p "Execute phase 3" \
  --allowedTools "Bash,Read,Write,Edit,Grep,Glob,Agent" \
  --model opus
```

Or in a custom agent definition (`.claude/agents/ralph-executor.md`):

```yaml
---
name: ralph-executor
description: Autonomous GSD executor. Runs phases without user interaction.
permissionMode: bypassPermissions
model: inherit
---
```

**Why `--allowedTools` over `--dangerously-skip-permissions`:** The `--allowedTools` flag provides granular control -- you can allow `Bash(git *)` but not `Bash(rm -rf *)`. The `--dangerously-skip-permissions` flag is a nuclear option that bypasses ALL permission checks including safety guardrails. For an automation layer, controlled auto-approval is safer.

**Why `permissionMode: bypassPermissions` is acceptable for the agent:** The subagent definition is scoped -- it only applies when Ralph is explicitly invoked. The user's interactive GSD sessions retain normal permission behavior. This matches the "add `--ralph` and walk away" mental model.

### Layer 2: GSD Checkpoint Auto-Response

**Problem:** GSD plans contain three checkpoint types that pause execution waiting for user input: `checkpoint:human-verify` (90%), `checkpoint:decision` (9%), `checkpoint:human-action` (1%).

**Solution:** GSD already has auto-advance built in. The `workflow.auto_advance` config flag causes:
- `human-verify` checkpoints to auto-approve
- `decision` checkpoints to auto-select the first option
- `human-action` checkpoints to still stop (auth gates cannot be automated)

**Verified mechanism (GSD checkpoints.md, execute-phase.md):**

```bash
# Set auto-advance in project config
node "$HOME/.claude/get-shit-done/bin/gsd-tools.cjs" config-set workflow.auto_advance true
```

Or via the ephemeral chain flag:

```bash
# Pass --auto flag to execute-phase
# This sets workflow._auto_chain_active = true
```

**What gsd-ralph v2.0 needs to do:** When `--ralph` is active, ensure `workflow.auto_advance` is `true` before launching GSD commands. Restore it after completion if the user had a different preference.

### Layer 3: Headless Invocation Wrapper

**Problem:** The user types `/gsd:execute-phase 3 --ralph` in interactive mode, or `gsd-ralph execute-phase 3` from the shell. Both need to translate into a headless Claude Code session that runs the GSD workflow autonomously.

**Solution:** A thin wrapper (Bash script or custom Claude Code agent) that:
1. Sets `workflow.auto_advance = true`
2. Launches `claude -p` with the GSD workflow prompt and `--allowedTools`
3. Monitors completion
4. Restores config

**Two implementation paths (choose one):**

| Approach | Mechanism | Pros | Cons |
|----------|-----------|------|------|
| **Bash wrapper** | Shell script calling `claude -p` | Simple, testable with bats-core, familiar from v1.x | External to Claude Code, requires parsing JSON output |
| **Custom agent** | `.claude/agents/ralph-autopilot.md` with `permissionMode: bypassPermissions` | Native integration, inherits project context, GSD skills auto-loaded | Less testable, new paradigm |

**Recommendation: Custom agent approach** because:
- The agent inherits the project's CLAUDE.md, skills, and MCP servers automatically
- `permissionMode: bypassPermissions` handles ALL tool permissions natively
- The agent can spawn GSD executor subagents directly (they inherit bypass permissions from parent if parent uses bypassPermissions)
- No JSON output parsing needed
- The user invokes it via `claude --agent ralph-autopilot` or `claude -p --agent ralph-autopilot "execute phase 3"`

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Claude Code CLI | 2.1.71+ | Runtime environment | IS the runtime. Everything runs inside Claude Code sessions. `-p` flag for headless, `--agent` for custom agent, `--allowedTools` for permission control |
| Claude Code Hooks | v2.0.10+ (hookSpecificOutput) | PermissionRequest auto-allow | The `PermissionRequest` hook fires when a permission dialog appears. Return `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` to auto-approve. Matcher filters by tool name |
| Claude Code Custom Agents | v2.1.63+ (Agent tool rename) | Ralph autopilot agent definition | `.claude/agents/ralph-autopilot.md` with `permissionMode: bypassPermissions`. Frontmatter controls tools, model, skills, hooks, and isolation |
| GSD config system | Current | Auto-advance toggle | `workflow.auto_advance` flag in `.planning/config.json`. Already implemented in GSD's checkpoint handling. No code needed |
| Bash 3.2 | 3.2+ | Wrapper scripts, hook scripts | macOS system Bash. Hook scripts must be Bash-compatible. Wrapper script (if needed) for CLI entry point |
| jq | 1.6+ | Hook JSON parsing | Hooks receive JSON on stdin. `jq` is the standard way to parse and emit JSON in shell hooks |

### Supporting Libraries

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| bats-core | 1.10+ | Testing hook scripts and wrapper | Test that hooks emit correct JSON, that the wrapper sets/restores config correctly |
| ShellCheck | 0.9+ | Linting hook scripts | All `.sh` files should pass ShellCheck. Existing dev dependency |
| GSD skills system | Current | Inject GSD workflow knowledge into Ralph agent | The `skills` frontmatter field in agent definitions loads skill content at startup. Ralph agent should load `gsd-executor-workflow` |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `claude --agent ralph-autopilot` | Test the custom agent interactively | Run the agent manually to verify it handles GSD workflows correctly |
| `claude -p --agent ralph-autopilot --output-format json` | Test headless agent execution | Verify the agent runs to completion and produces expected output |
| `echo '{"hook_event_name":"PermissionRequest",...}' \| bash hook.sh` | Test hook scripts manually | Verify hooks return correct JSON. See claude-code-hooks skill for patterns |

## Key Integration Points

### What gsd-ralph v2.0 Builds

| Component | Type | Lines (est.) | What It Does |
|-----------|------|------------|--------------|
| `.claude/agents/ralph-autopilot.md` | Custom agent | ~50 | Agent definition with `permissionMode: bypassPermissions`, system prompt for autonomous GSD execution |
| `.claude/hooks/ralph-auto-permit.sh` | Hook script | ~30 | `PermissionRequest` hook that auto-allows when invoked in Ralph context (checks `RALPH_MODE` env var or agent_type) |
| `bin/gsd-ralph` | Bash wrapper | ~100 | CLI entry point: `gsd-ralph execute-phase 3` translates to `claude -p --agent ralph-autopilot "execute phase 3"` |
| `.claude/settings.json` (hooks section) | Config | ~15 | Register the PermissionRequest hook |

**Total: ~200 lines of code.** Compare to v1.x: 9,693 lines.

### What GSD Already Handles (DO NOT BUILD)

| Capability | Where It Lives | Why Not Rebuild |
|------------|---------------|-----------------|
| Phase/plan discovery | `gsd-tools.cjs init execute-phase` | Reads ROADMAP.md, finds plans, groups waves |
| Checkpoint auto-advance | `execute-phase.md` step `checkpoint_handling` | Already reads `workflow.auto_advance` and auto-approves/auto-selects |
| Subagent spawning | `execute-phase.md` step `execute_waves` | Spawns `gsd-executor` subagents per plan |
| Worktree isolation | `isolation: worktree` in agent frontmatter | Claude Code creates/manages/cleans worktrees natively |
| Branch management | `execute-phase.md` step `handle_branching` | Creates phase branches, handles merging |
| Verification | `execute-phase.md` step `verify_phase_goal` | Spawns `gsd-verifier` subagent |
| State tracking | STATE.md, ROADMAP.md updates | `gsd-tools.cjs` handles all state mutations |
| SUMMARY.md creation | `execute-plan.md` | Executor subagent creates per-plan summaries |
| Progress reporting | `gsd-tools.cjs phase complete` | Marks phases complete, advances state |

### What Claude Code Already Handles (DO NOT BUILD)

| Capability | Mechanism | Notes |
|------------|-----------|-------|
| Tool permission prompts | `--allowedTools` or `permissionMode` | Replaces v1.x's `ALLOWED_TOOLS` in `.ralphrc` |
| Session management | `--continue`, `--resume` | Replaces v1.x's `SESSION_CONTINUITY` config |
| Worktree creation/cleanup | `--worktree` flag, `isolation: worktree` | Replaces v1.x's 487-line `merge.sh` and 274-line `cleanup.sh` |
| Model selection | `--model` flag or agent `model` field | Replaces v1.x's executor model config |
| Context management | Auto-compaction, subagent context isolation | Replaces v1.x's prompt size management |
| Circuit breaker (partial) | `--max-turns`, `--max-budget-usd` | Replaces v1.x's `CB_NO_PROGRESS_THRESHOLD` etc. |

## Implementation Architecture

### The PermissionRequest Hook (Detail)

The hook fires when Claude Code is about to show a permission dialog. In Ralph mode, it auto-allows everything.

```bash
#!/bin/bash
# .claude/hooks/ralph-auto-permit.sh
set -euo pipefail

INPUT="$(cat)"
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // empty')

# Only auto-permit in Ralph autopilot context
if [[ "$AGENT_TYPE" == "ralph-autopilot" ]] || [[ "${RALPH_MODE:-}" == "true" ]]; then
  jq -cn '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: {
        behavior: "allow"
      }
    }
  }'
  exit 0
fi

# Not in Ralph mode -- pass through to normal permission handling
exit 0
```

**Key detail:** The hook checks `agent_type` from the JSON input (available since v2.1.63). When the session is running as the `ralph-autopilot` agent, it auto-allows. Otherwise, normal interactive permission prompts appear. This means the hook is always installed but only activates in Ralph context.

**Known issue (2025-2026):** GitHub issue #19298 reports that `PermissionRequest` hook cannot deny permissions -- the interactive prompt still appears regardless. However, the `allow` behavior works correctly. For Ralph's use case (auto-allow, not deny), this bug does not apply. If the allow path also has issues, fall back to `permissionMode: bypassPermissions` on the agent definition, which is the recommended primary mechanism anyway.

### The Custom Agent (Detail)

```markdown
---
name: ralph-autopilot
description: Autonomous GSD phase executor. Runs complete phase workflows without user interaction. Use when the user wants autopilot mode for GSD commands.
permissionMode: bypassPermissions
model: inherit
skills:
  - gsd-executor-workflow
---

You are Ralph, an autonomous coding agent executing GSD workflows.

When invoked, you run GSD commands to completion without stopping for user input.

## Rules

1. Set `workflow.auto_advance` to `true` before starting execution
2. Execute the requested GSD workflow (execute-phase, execute-plan, etc.)
3. Handle all checkpoints autonomously (verify -> approve, decision -> first option)
4. Do NOT stop for human-action checkpoints -- log them and skip
5. Report completion status when done
6. Restore `workflow.auto_advance` to its previous value
```

### The CLI Wrapper (Detail)

```bash
#!/bin/bash
# bin/gsd-ralph
# Thin wrapper: translates gsd-ralph commands to claude --agent invocations
set -euo pipefail

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  execute-phase)
    PHASE="${1:?Usage: gsd-ralph execute-phase <phase>}"
    exec claude -p \
      --agent ralph-autopilot \
      --allowedTools "Bash,Read,Write,Edit,Grep,Glob,Agent" \
      --output-format json \
      "Execute phase $PHASE using /gsd:execute-phase $PHASE"
    ;;
  *)
    echo "Usage: gsd-ralph execute-phase <N>"
    exit 1
    ;;
esac
```

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| Custom agent (`ralph-autopilot.md`) | Bash wrapper calling `claude -p` only | Agent inherits project context, skills, CLAUDE.md automatically. Wrapper would need to manually construct the full prompt with all GSD workflow context |
| `permissionMode: bypassPermissions` | `PermissionRequest` hook alone | The hook is a defense-in-depth layer. `bypassPermissions` on the agent is the primary mechanism -- it guarantees no permission prompts. The hook handles edge cases where the agent spawns subagents that might not inherit the mode |
| `--allowedTools` for `-p` mode | `--dangerously-skip-permissions` | `--allowedTools` lets you be specific. `--dangerously-skip-permissions` skips ALL checks including safety hooks. In practice, `bypassPermissions` on the agent achieves the same result more safely |
| GSD's `workflow.auto_advance` | Custom checkpoint interception | GSD already built this. Setting a config flag is 1 line vs building custom checkpoint detection/response logic |
| Single agent file | Multiple hooks + scripts + wrappers | Minimize surface area. One agent definition replaces most of v1.x's architecture |
| `model: inherit` on agent | Hardcoded model | User controls model via `--model` flag or Claude Code settings. Ralph should not force a model |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| v1.x `.ralphrc` config system | Superseded by Claude Code agent frontmatter. Tool permissions, session management, circuit breaker thresholds all have native equivalents | Agent definition frontmatter (`permissionMode`, `maxTurns`, `model`) |
| v1.x `execute.sh` (258 lines) | GSD's `execute-phase.md` workflow does everything this did, better | `/gsd:execute-phase` via the agent |
| v1.x `merge.sh` (487 lines) | GSD handles merging natively. Claude Code worktrees auto-clean | No equivalent needed -- GSD manages it |
| v1.x `cleanup.sh` (274 lines) | Claude Code `isolation: worktree` auto-cleans worktrees when agents finish | No equivalent needed |
| v1.x `generate.sh` (159 lines) | GSD's `plan-phase` creates all plan artifacts | `/gsd:plan-phase` |
| v1.x `init.sh` (102 lines) | GSD's `new-project` / `new-milestone` handles initialization | `/gsd:new-project` or `/gsd:new-milestone` |
| Custom worktree management | Claude Code added native worktree support (`--worktree` flag, `isolation: worktree`). Auto-creates, auto-cleans | Native worktree support |
| External process monitoring | v1.x polled Ralph processes for completion | Claude Code `-p` mode blocks until complete. `--output-format json` returns structured result |
| Custom circuit breaker | v1.x had `CB_NO_PROGRESS_THRESHOLD`, `CB_SAME_ERROR_THRESHOLD` | `--max-turns` and `--max-budget-usd` flags on `claude -p`. For deeper circuit breaking, implement as a `Stop` hook |

## Version Compatibility Matrix

| Requirement | Minimum | Current | Notes |
|-------------|---------|---------|-------|
| Claude Code | 2.1.63+ | 2.1.71 | Agent tool renamed from Task in 2.1.63. `permissionMode` field available. `isolation: worktree` available |
| Bash | 3.2+ | 3.2.57 | macOS system Bash. Hook scripts and wrapper only |
| jq | 1.6+ | (existing) | Hook JSON parsing |
| GSD | Current (Mar 2026) | Current | `workflow.auto_advance` config, `gsd-tools.cjs config-set/get`, execute-phase checkpoint handling |
| Git | 2.20+ | 2.53.0 | Worktree support (2.15+), well within range |

**No new dependencies to install.** Everything is already available in the development environment.

## Installation

```bash
# No new dependencies needed. Verify existing:
claude --version    # 2.1.63+ required
bash --version      # 3.2+ required
jq --version        # 1.6+ required

# The integration creates these files (no package installation):
# .claude/agents/ralph-autopilot.md     (custom agent definition)
# .claude/hooks/ralph-auto-permit.sh    (permission hook, optional)
# bin/gsd-ralph                         (CLI wrapper, optional)
```

## Sources

- [Claude Code headless mode docs](https://code.claude.com/docs/en/headless) -- `-p` flag, `--allowedTools`, `--output-format` (verified 2026-03-09, HIGH confidence)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) -- `PermissionRequest` event, `hookSpecificOutput` schema, decision control, exit codes (verified 2026-03-09, HIGH confidence)
- [Claude Code subagents docs](https://code.claude.com/docs/en/sub-agents) -- Custom agent creation, `permissionMode`, `isolation: worktree`, `skills` field, `--agent` flag, `--agents` JSON flag (verified 2026-03-09, HIGH confidence)
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) -- All CLI flags including `--agent`, `--worktree`, `--permission-mode`, `--model`, `--max-turns`, `--max-budget-usd` (verified 2026-03-09, HIGH confidence)
- [PermissionRequest hook bug #19298](https://github.com/anthropics/claude-code/issues/19298) -- `deny` behavior broken, `allow` works. Defense-in-depth only (verified 2026-03-09, MEDIUM confidence)
- GSD execute-phase.md workflow -- checkpoint_handling step, auto-advance logic, `workflow.auto_advance` and `workflow._auto_chain_active` config keys (verified from local file, HIGH confidence)
- GSD checkpoints.md reference -- checkpoint types (`human-verify`, `decision`, `human-action`), auto-mode bypass rules (verified from local file, HIGH confidence)
- Claude Code hooks skill (`~/.agents/skills/claude-code-hooks/SKILL.md`) -- Hook templates, decision control JSON schema, security practices (verified from local file, HIGH confidence)
- GSD executor agent (`~/.claude/agents/gsd-executor.md`) -- Agent frontmatter pattern, skill loading, tool specification (verified from local file, HIGH confidence)

---
*Stack research for: gsd-ralph v2.0 Autopilot Integration Layer*
*Researched: 2026-03-09*
