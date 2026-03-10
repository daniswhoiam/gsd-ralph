# Phase 11: Shell Launcher and Headless Invocation - Research

**Researched:** 2026-03-10
**Domain:** Claude Code headless mode CLI integration, bash loop execution, GSD skill/command authoring
**Confidence:** HIGH

## Summary

Phase 11 builds the working autopilot: a `/gsd:ralph` skill that the user invokes inside Claude Code, which assembles context, constructs a `claude -p` command with appropriate flags, and loops fresh headless instances until the GSD phase is complete. The Phase 10 deliverables (SKILL.md, config.json schema, assemble-context.sh, validate-config.sh) provide the foundation.

The critical technical challenge is the loop control: detecting when a headless iteration completes vs. needs continuation, and building the correct `claude -p` invocation with permission tier mapping. Claude Code's `--output-format json` provides structured output with `result`, `session_id`, `cost_usd`, `duration_ms`, and `num_turns` fields. Exit code 0 means success, non-zero means failure. The `--max-turns` flag exits with an error (non-zero) when the turn limit is reached, which the loop must distinguish from genuine task failures.

The `/gsd:ralph` skill lives in `~/.claude/commands/gsd/ralph.md` following the existing GSD command pattern. It is user-invocable (the user types `/gsd:ralph execute-phase 11`) and receives the GSD sub-command as `$ARGUMENTS`. Since GSD slash commands cannot be invoked in headless mode, the skill must translate the slash command argument into a natural language prompt for `claude -p`, injecting the GSD workflow content via `--append-system-prompt-file`.

**Primary recommendation:** Build a single GSD command file (`~/.claude/commands/gsd/ralph.md` or `.claude/commands/gsd/ralph.md`) that orchestrates the entire flow: parse arguments, read config, assemble context to a temp file, build the `claude -p` command with permission/worktree/max-turns flags, and loop execution with STATE.md-based completion detection.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Completion detection via STATE.md check: after each iteration, re-read STATE.md to determine if the phase advanced or work is complete
- No iteration cap: rely on max_turns per iteration (from config) and Phase 12's circuit breaker for runaway prevention
- Retry once on failure: if an iteration exits non-zero, retry once (fresh instance). If retry also fails, stop that step but move on to potential next work items if possible
- No cooldown between iterations: immediately launch next iteration after reassembling context from STATE.md
- Default tool whitelist: `Write,Read,Edit,Grep,Glob,Bash(*)` hardcoded. Not configurable per-project. Users who want different security posture use auto-mode or yolo tiers
- Yolo tier maps to `--dangerously-skip-permissions`
- Auto-mode tier: Claude's discretion on exact flag mapping
- Separate `/gsd:ralph` skill inside Claude Code: user types `/gsd:ralph execute-phase 11`
- Claude Code only: no standalone terminal script
- Slash command translation: translates GSD slash command argument into natural language prompt for `claude -p`
- `--dry-run`: shows the exact `claude -p` command with all flags, system prompt file path, and context file summary
- Worktree always on: every iteration runs via `--worktree`. No option to disable
- Claude Code handles worktree lifecycle: creation, branch management, merging are Claude Code's responsibility
- STATE.md check location: Claude's discretion (depends on worktree merge lifecycle)

### Claude's Discretion
- Auto-mode tier exact flag mapping (research Claude Code's permission model)
- STATE.md check location relative to worktree lifecycle
- Natural language prompt construction format for `claude -p`
- Internal script/skill structure and function organization
- Inter-iteration cleanup (temp files, context file regeneration)

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUTO-01 | User can add `--ralph` to any GSD command to run it autonomously | `/gsd:ralph` skill receives GSD command as `$ARGUMENTS`, translates to natural language prompt for `claude -p`. Skill pattern from GSD commands directory. |
| AUTO-02 | System loops fresh Claude Code instances, each picking up incomplete work from GSD state on disk | Loop with `claude -p` invocations. Exit code 0 = success, non-zero = failure. Re-read STATE.md between iterations for completion detection. `--output-format json` provides `result` and `num_turns` fields. |
| AUTO-05 | User can run `--dry-run` to preview the command without executing | Parse `--dry-run` from `$ARGUMENTS`, construct the full command string, print it with context file summary instead of executing. |
| PERM-01 | Default mode uses `--allowedTools` with a scoped tool whitelist | `--allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)"` hardcoded for default tier. Permission rule syntax documented. |
| PERM-02 | User can opt into `--auto-mode` for Claude's risk-based auto-approval | Maps to `--permission-mode auto`. Listed in CLI help as valid choice. Falls back to default with warning if unavailable. |
| PERM-03 | User can opt into `--yolo` for full bypass | Maps to `--dangerously-skip-permissions`. Well-documented flag. |
| SAFE-01 | Each iteration runs in an isolated worktree via `--worktree` | `--worktree` flag creates worktree at `<repo>/.claude/worktrees/<name>`. Auto-cleanup on no changes. Prompts on changes. In headless mode, cleanup is automatic. |
| SAFE-02 | System enforces `--max-turns` ceiling per iteration | `--max-turns N` flag. Exits with error when limit reached. Read from `config.json` `ralph.max_turns` (default 50). |
| OBSV-01 | System detects iteration completion/failure from exit code and output | Exit code 0 = success, non-zero = failure. JSON output with `--output-format json` provides `result` field for semantic analysis. |
| OBSV-02 | Terminal bell on loop completion or failure | `printf '\a'` for terminal bell. Emit on loop termination (all work complete or unrecoverable failure). |
</phase_requirements>

## Standard Stack

### Core

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| `/gsd:ralph` command | `.claude/commands/gsd/ralph.md` (project) or `~/.claude/commands/gsd/ralph.md` (user) | GSD skill entry point for autonomous execution | Follows GSD command pattern; `$ARGUMENTS` substitution; user-invocable |
| `assemble-context.sh` | `scripts/assemble-context.sh` | Build context blob for `--append-system-prompt-file` | Phase 10 deliverable; reads STATE.md + phase plans |
| `validate-config.sh` | `scripts/validate-config.sh` | Read and validate ralph config | Phase 10 deliverable; strict-with-warnings |
| `config.json` | `.planning/config.json` `"ralph"` key | Ralph settings (max_turns, permission_tier) | Phase 10 deliverable; single source of truth |
| SKILL.md | `.claude/skills/gsd-ralph-autopilot/SKILL.md` | Autonomous behavior rules | Phase 10 deliverable; auto-discovered by Claude Code |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| jq | any | Parse config.json, parse JSON output from `claude -p` | Config reading and output parsing |
| mktemp | system | Create temp files for context assembly output | Each iteration needs a fresh context file |
| Claude Code CLI | 2.1.72+ | `claude -p` with all flags | Headless invocation |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| GSD command file (`.claude/commands/gsd/ralph.md`) | Standalone bash script | Command file integrates with GSD slash command system; standalone script requires separate invocation |
| `--output-format json` for output parsing | `--output-format text` | JSON provides structured `result`, `session_id`, `num_turns` fields; text requires regex parsing |
| Re-reading STATE.md for completion detection | Parsing JSON `result` field for semantic completion | STATE.md is authoritative GSD state; JSON `result` content is natural language and fragile to parse |

## Architecture Patterns

### Recommended Project Structure

```
.claude/
  commands/
    gsd/
      ralph.md              # /gsd:ralph command (AUTO-01)
  skills/
    gsd-ralph-autopilot/
      SKILL.md              # Autonomous behavior rules (Phase 10)

scripts/
  assemble-context.sh       # Context assembly (Phase 10)
  validate-config.sh        # Config validation (Phase 10)
  ralph-launcher.sh         # Loop execution engine (new in Phase 11)

.planning/
  config.json               # ralph config under "ralph" key
```

### Pattern 1: GSD Command as Orchestrator

**What:** The `/gsd:ralph` command file acts as the user-facing entry point. When invoked, the hosting Claude Code instance (interactive session) reads the command, parses arguments, and executes the launcher script. The command file itself is a prompt that tells Claude what to do -- it is NOT a bash script. Claude Code processes the command and uses its Bash tool to execute the launcher.

**When to use:** Every time the user invokes `/gsd:ralph`.

**Key design insight:** GSD command files (`.claude/commands/gsd/*.md`) are markdown prompts with frontmatter. They tell Claude what to do. The actual execution logic lives in a bash script (`scripts/ralph-launcher.sh`) that the command instructs Claude to run. This separation keeps the command file declarative and the bash script testable.

**Example command file:**
```yaml
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

Run the ralph launcher script to execute this command autonomously:
bash scripts/ralph-launcher.sh $ARGUMENTS
</context>
```

### Pattern 2: Launcher Script with Loop Engine

**What:** A bash script that handles the core loop: assemble context, build `claude -p` command, execute, check STATE.md, repeat until done.

**When to use:** Called by the `/gsd:ralph` command.

**Loop flow:**
```
1. Parse arguments (GSD command, --dry-run, --tier override)
2. Read config.json for max_turns, permission_tier
3. Validate config
4. LOOP:
   a. Assemble context via assemble-context.sh -> temp file
   b. Build claude -p command with flags
   c. If --dry-run: print command and exit
   d. Execute claude -p
   e. Check exit code (0 = success, non-zero = failure)
   f. If failure: retry once with fresh context
   g. If retry fails: stop this step, try next work item if possible
   h. Re-read STATE.md to check completion
   i. If complete: bell notification, exit
   j. If incomplete: reassemble context, continue loop
```

**Example:**
```bash
#!/bin/bash
# scripts/ralph-launcher.sh -- Ralph autopilot loop engine
# Bash 3.2 compatible

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
STATE_FILE="$PROJECT_ROOT/.planning/STATE.md"
CONTEXT_SCRIPT="$PROJECT_ROOT/scripts/assemble-context.sh"

# Defaults
MAX_TURNS=50
PERMISSION_TIER="default"
DRY_RUN=false
GSD_COMMAND=""

# Parse arguments
parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --dry-run)  DRY_RUN=true; shift ;;
            --tier)     PERMISSION_TIER="$2"; shift 2 ;;
            *)          GSD_COMMAND="$GSD_COMMAND $1"; shift ;;
        esac
    done
    GSD_COMMAND=$(echo "$GSD_COMMAND" | sed 's/^ //')
}

# Read config
read_config() {
    if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
        local cfg_turns cfg_tier
        cfg_turns=$(jq -r '.ralph.max_turns // empty' "$CONFIG_FILE" 2>/dev/null)
        cfg_tier=$(jq -r '.ralph.permission_tier // empty' "$CONFIG_FILE" 2>/dev/null)
        [ -n "$cfg_turns" ] && MAX_TURNS="$cfg_turns"
        [ -n "$cfg_tier" ] && PERMISSION_TIER="$cfg_tier"
    fi
}

# Build permission flags based on tier
build_permission_flags() {
    case "$PERMISSION_TIER" in
        default)
            echo '--allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)"'
            ;;
        auto-mode)
            echo '--permission-mode auto'
            ;;
        yolo)
            echo '--dangerously-skip-permissions'
            ;;
    esac
}

# Translate GSD command to natural language prompt
build_prompt() {
    local cmd="$1"
    # Example: "execute-phase 11" -> natural language
    echo "Execute the GSD command: $cmd. Read STATE.md for current position and follow the plan instructions."
}
```

### Pattern 3: Permission Tier Mapping

**What:** Maps the config `permission_tier` value to Claude Code CLI flags.

**Mapping table (verified against Claude Code CLI v2.1.72):**

| Config Value | CLI Flags | Behavior |
|-------------|-----------|----------|
| `"default"` | `--allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)"` | Scoped whitelist; other tools prompt (but in headless mode, non-whitelisted tools are denied) |
| `"auto-mode"` | `--permission-mode auto` | Claude uses judgment; low-risk auto-approved, high-risk escalated. Listed as valid choice in `--permission-mode` options. |
| `"yolo"` | `--dangerously-skip-permissions` | All permission checks bypassed |

**Note on `auto` mode:** The `--permission-mode auto` value appears in the Claude Code CLI `--help` output as a valid choice. The permission modes documented are: `acceptEdits`, `bypassPermissions`, `default`, `dontAsk`, `plan`, `auto`. This is now a production feature in Claude Code 2.1.72.

### Pattern 4: Worktree Isolation in Headless Mode

**What:** Using `--worktree` with `claude -p` for isolated execution.

**Behavior (from official docs):**
- `--worktree [name]` creates a worktree at `<repo>/.claude/worktrees/<name>`
- If name omitted, Claude auto-generates a random name (e.g., "bright-running-fox")
- Worktree branches from the default remote branch
- Branch is named `worktree-<name>`
- **Cleanup in headless mode:** When no changes, worktree and branch are removed automatically. When changes exist, in non-interactive mode the behavior is that Claude handles it.

**STATE.md check location:** Since the worktree creates a copy of the repo, STATE.md exists in both locations. The loop runner checks STATE.md in the **main repo** (not the worktree), because:
1. The worktree is a temporary copy
2. GSD updates STATE.md as part of the execution workflow
3. After worktree merges back (or is cleaned up), the main STATE.md reflects the latest state
4. However, if changes haven't been merged yet, the worktree STATE.md is more current

**Recommendation:** Check STATE.md in the main working directory. The loop waits for the headless `claude -p` to complete (blocking call), and after completion, any worktree changes have either been merged or discarded. The main STATE.md is the authoritative source after each iteration.

### Pattern 5: Natural Language Prompt Construction

**What:** Translating GSD slash commands into natural language prompts for `claude -p`.

**Why:** GSD slash commands (like `/gsd:execute-phase 11`) are NOT available in headless (`-p`) mode. The official docs confirm: "User-invoked skills like /commit and built-in commands are only available in interactive mode."

**Translation examples:**

| GSD Slash Command | Natural Language Prompt |
|-------------------|------------------------|
| `execute-phase 11` | "You are executing Phase 11 of the GSD project plan. Read STATE.md for your current position. Follow the plan instructions for the active phase. Complete as many tasks as possible within the turn limit." |
| `verify-work 11` | "You are verifying the work completed in Phase 11. Read STATE.md for context. Check all success criteria and test results." |
| `plan-phase 11` | "You are planning Phase 11. Read STATE.md, the phase description from ROADMAP.md, and any existing CONTEXT.md or RESEARCH.md. Create plan files following GSD conventions." |

**The system prompt file** (via `--append-system-prompt-file`) provides the assembled context (STATE.md + phase plans). The user prompt (via `claude -p "..."`) provides the task instruction.

### Anti-Patterns to Avoid

- **Parsing JSON `result` field for completion:** The `result` field contains natural language. Attempting to parse it for "complete" or "done" is fragile. Use STATE.md instead -- it's the authoritative GSD state.
- **Running `claude -p` with slash commands:** `/gsd:execute-phase` will NOT work in headless mode. Always use natural language prompts.
- **Hardcoding worktree paths:** Let Claude Code manage worktree creation/cleanup via `--worktree`. Do not create or manage worktrees manually.
- **Nested Claude Code invocation:** Cannot run `claude -p` from inside a Claude Code session directly via the CLAUDECODE environment variable. The launcher script must `unset CLAUDECODE` before invoking the headless instance.
- **Using `--system-prompt` instead of `--append-system-prompt-file`:** The `--system-prompt` flag REPLACES the entire default system prompt, breaking Claude Code's built-in tool handling. Always use `--append-system-prompt-file` to ADD to defaults.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Worktree management | Custom git worktree creation/cleanup | `--worktree` flag on `claude -p` | Claude Code handles full lifecycle (create, branch, merge, cleanup) |
| Permission management | Custom permission logic | `--allowedTools`, `--permission-mode`, `--dangerously-skip-permissions` | Native CLI flags cover all three tiers |
| Context assembly | New context builder | `scripts/assemble-context.sh` (Phase 10) | Already built, tested, produces correct format |
| Config reading | New config parser | `scripts/validate-config.sh` + jq | Already built, validates, warns on unknown keys |
| GSD state management | Custom state tracker | Read STATE.md directly | GSD manages state; ralph just reads it |
| Session persistence | Custom session tracking | `--session-id` and `--resume` | Claude Code provides native session management |
| Autonomous behavior rules | Per-iteration prompt injection | SKILL.md auto-discovery | Phase 10 SKILL.md is auto-loaded by Claude Code |

**Key insight:** Phase 11's new code is strictly the loop engine and the `/gsd:ralph` command file. Everything else already exists.

## Common Pitfalls

### Pitfall 1: CLAUDECODE Environment Variable Blocking Nested Invocation
**What goes wrong:** Running `claude -p` from inside a Claude Code session fails with "Claude Code cannot be launched inside another Claude Code session."
**Why it happens:** Claude Code sets a `CLAUDECODE` environment variable that child processes inherit. The nested `claude` process detects it and refuses to start.
**How to avoid:** In the launcher script, explicitly unset the CLAUDECODE environment variable before invoking the headless instance: `unset CLAUDECODE; claude -p ...` or use `env -u CLAUDECODE claude -p ...`.
**Warning signs:** Error message mentioning "nested sessions" or "CLAUDECODE environment variable."

### Pitfall 2: Max-Turns Exit Confused With Task Failure
**What goes wrong:** The loop treats a max-turns exit (non-zero exit code) as a genuine failure and retries, when actually the task just needs more turns to complete.
**Why it happens:** `--max-turns` exits with a non-zero code when the limit is reached, same as a genuine error.
**How to avoid:** After a non-zero exit, check STATE.md for progress. If STATE.md shows advancement (different phase/plan/task position), the iteration made partial progress -- continue looping (not a retry). Only treat it as a failure-retry if STATE.md shows NO advancement.
**Warning signs:** Loop retrying when the previous iteration made clear progress.

### Pitfall 3: Stale Context Between Iterations
**What goes wrong:** Reusing the same context file across iterations causes the headless instance to see outdated STATE.md content.
**Why it happens:** Context is assembled once and cached. STATE.md changes during execution.
**How to avoid:** Reassemble context fresh before each iteration. Write to a new temp file or overwrite the existing one with fresh content from `assemble-context.sh`.
**Warning signs:** Headless instance executing already-completed tasks.

### Pitfall 4: Worktree Name Collisions
**What goes wrong:** Multiple iterations trying to use the same worktree name.
**Why it happens:** Using a fixed worktree name for all iterations.
**How to avoid:** Either (a) omit the worktree name (let Claude Code auto-generate) or (b) include an iteration counter in the name (e.g., `ralph-p11-iter-1`). Option (a) is simpler and recommended.
**Warning signs:** Git errors about existing worktrees or branches.

### Pitfall 5: Terminal Bell Not Reaching User
**What goes wrong:** `printf '\a'` doesn't produce an audible notification.
**Why it happens:** Terminal emulators may have bell disabled or set to visual-only.
**How to avoid:** Use both `printf '\a'` for terminal bell AND consider `tput bel` as fallback. Also print a clear text message alongside the bell. On macOS, `osascript -e 'display notification ...'` can supplement.
**Warning signs:** User doesn't notice completion.

### Pitfall 6: Infinite Loop With No Progress
**What goes wrong:** Loop keeps running but STATE.md never advances.
**Why it happens:** The headless instance cannot make progress (e.g., missing dependencies, broken plan, unclear instructions).
**How to avoid:** Phase 12 adds a circuit breaker. For Phase 11, the `--max-turns` ceiling prevents individual iterations from running forever, but the loop itself has no cap (by user decision). Document this as a known limitation that Phase 12 addresses.
**Warning signs:** Same STATE.md content across multiple consecutive iterations.

## Code Examples

### JSON Output Structure from `claude -p`

```json
// Source: Claude Code official docs (https://code.claude.com/docs/en/headless)
// With --output-format json:
{
  "type": "result",
  "result": "I have completed the tasks...",
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "cost_usd": 0.042,
  "duration_ms": 3200,
  "num_turns": 15
}
```

**Key fields for the loop:**
- `session_id`: Can be used with `--resume` for continuation (though we use fresh instances)
- `num_turns`: If equals `max_turns`, the iteration likely hit the ceiling (partial completion)
- `result`: Natural language summary (informational, not for programmatic parsing)
- Exit code: 0 = completed successfully, non-zero = error or max-turns hit

### Building the `claude -p` Command

```bash
# Source: Claude Code CLI reference (https://code.claude.com/docs/en/cli-usage)
build_claude_command() {
    local prompt="$1"
    local context_file="$2"
    local max_turns="$3"
    local permission_tier="$4"

    local cmd="claude -p"
    cmd="$cmd \"$prompt\""
    cmd="$cmd --append-system-prompt-file \"$context_file\""
    cmd="$cmd --max-turns $max_turns"
    cmd="$cmd --output-format json"
    cmd="$cmd --worktree"

    case "$permission_tier" in
        default)
            cmd="$cmd --allowedTools \"Write,Read,Edit,Grep,Glob,Bash(*)\""
            ;;
        auto-mode)
            cmd="$cmd --permission-mode auto"
            ;;
        yolo)
            cmd="$cmd --dangerously-skip-permissions"
            ;;
    esac

    echo "$cmd"
}
```

### Dry-Run Output Format

```bash
# Example dry-run output showing the exact command and context summary
dry_run_output() {
    local cmd="$1"
    local context_file="$2"

    echo "=== Ralph Dry Run ==="
    echo ""
    echo "Command:"
    echo "  $cmd"
    echo ""
    echo "Context file: $context_file"
    echo "Context summary:"
    # Show file names and line counts
    if [ -f "$context_file" ]; then
        local lines
        lines=$(wc -l < "$context_file" | tr -d ' ')
        echo "  $context_file ($lines lines)"
    fi
    echo ""
    echo "Config:"
    echo "  max_turns: $MAX_TURNS"
    echo "  permission_tier: $PERMISSION_TIER"
    echo "  worktree: always on"
    echo ""
    echo "To execute, run without --dry-run"
}
```

### STATE.md Completion Detection

```bash
# Source: project pattern from scripts/assemble-context.sh
check_state_completion() {
    local state_file="$1"
    local target_phase="$2"

    if [ ! -f "$state_file" ]; then
        echo "missing"
        return
    fi

    # Check if current phase has advanced beyond target
    local current_phase
    current_phase=$(grep -oE 'Phase: [0-9]+' "$state_file" | grep -oE '[0-9]+' | head -1)

    if [ -z "$current_phase" ]; then
        echo "unknown"
        return
    fi

    if [ "$current_phase" -gt "$target_phase" ]; then
        echo "complete"
    else
        # Check status field
        local status
        status=$(grep -oE 'Status: [A-Za-z]+' "$state_file" | head -1 | sed 's/Status: //')
        case "$status" in
            Complete*|complete*) echo "complete" ;;
            *)                  echo "incomplete" ;;
        esac
    fi
}
```

### Unsetting CLAUDECODE for Nested Invocation

```bash
# Source: Claude Code error message analysis
# CRITICAL: Must unset CLAUDECODE to allow nested claude -p invocation
execute_headless() {
    local cmd="$1"
    # Use env -u to unset CLAUDECODE for this invocation only
    env -u CLAUDECODE bash -c "$cmd"
    return $?
}
```

## State of the Art

| Old Approach (v1.x) | Current Approach (v2.0 Phase 11) | When Changed | Impact |
|---------------------|----------------------------------|--------------|--------|
| Standalone `ralph` CLI with subcommands | `/gsd:ralph` GSD command | v2.0 rewrite | User stays in Claude Code; no external tool |
| Manual worktree creation + merge scripts | `--worktree` on every `claude -p` call | Claude Code native feature | Eliminated custom worktree lifecycle code |
| `.ralphrc` with 12 settings | 3 settings from `config.json` `"ralph"` key | v2.0 rewrite | Simpler config; single source of truth |
| Custom PROMPT.md per plan | SKILL.md auto-discovery + `--append-system-prompt-file` | v2.0 rewrite | Claude Code native skill format |
| Human monitoring via `ralph-status.sh` | Loop with exit code + STATE.md checking | v2.0 rewrite | Fully automated loop control |
| Interactive `read -p "Press ENTER"` checkpoints | Autonomous via SKILL.md rules | v2.0 rewrite | No human interaction needed |

**Deprecated/outdated:**
- v1.x `bin/gsd-ralph` with init/execute/merge/cleanup subcommands -- superseded by GSD native commands
- `scripts/ralph-execute.sh`, `ralph-merge.sh`, `ralph-cleanup.sh`, `ralph-worktrees.sh`, `ralph-status.sh` -- legacy v1.x orchestration, no longer needed
- `.ralphrc` configuration file -- replaced by `config.json` `"ralph"` key

## Open Questions

1. **Worktree Merge Timing in Headless Mode**
   - What we know: `--worktree` creates an isolated copy. In interactive mode, Claude prompts about keeping/removing on exit.
   - What's unclear: In headless (`-p`) mode, does the worktree auto-merge changes back? Or does it leave uncommitted changes in the worktree for manual handling? The docs say "No changes: removed automatically. Changes or commits exist: Claude prompts you" -- but there's no prompting in headless mode.
   - Recommendation: Test empirically in Phase 11 implementation. The likely behavior is that in headless mode, if changes were committed, the worktree persists with commits on its branch. The loop should check if a branch with worktree commits exists and handle accordingly. Alternative: skip `--worktree` if it causes complications in headless mode and let the SKILL.md handle clean working patterns instead. This needs empirical validation.

2. **`--permission-mode auto` Interaction with `--allowedTools`**
   - What we know: Both flags exist and are valid. `auto` mode uses judgment-based approval. `--allowedTools` pre-approves specific tools.
   - What's unclear: Can they be combined? Does `--permission-mode auto` + `--allowedTools` mean "auto-approve these tools, use judgment for others"?
   - Recommendation: For the `auto-mode` tier, use `--permission-mode auto` alone (without `--allowedTools`). The auto mode is intended to be self-contained.

3. **GSD Command File Location (Project vs. User)**
   - What we know: GSD commands can live in `~/.claude/commands/gsd/` (user-level, all projects) or `.claude/commands/gsd/` (project-level, this project only).
   - What's unclear: Should `/gsd:ralph` be project-level (committed to gsd-ralph repo) or user-level (available everywhere)?
   - Recommendation: Project-level (`.claude/commands/gsd/ralph.md`) since it depends on project-specific scripts (`scripts/ralph-launcher.sh`, `scripts/assemble-context.sh`). Users can symlink or copy to user-level if they want global availability.

4. **Bash Script vs. Command-Only Approach**
   - What we know: GSD command files are markdown prompts that Claude processes. The command can either (a) contain all logic as instructions for Claude to follow, or (b) instruct Claude to run a bash script.
   - What's unclear: Whether the loop should be driven by Claude (the hosting interactive instance) or by a bash script that Claude invokes.
   - Recommendation: Use a bash script (`scripts/ralph-launcher.sh`) that the command instructs Claude to execute. Reasons: (1) bash scripts are testable with bats, (2) the loop is a deterministic algorithm, not an AI reasoning task, (3) bash handles process management (exit codes, signal handling) natively.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core (git submodule in `tests/bats/`) |
| Config file | `tests/bats/` submodule |
| Quick run command | `./tests/bats/bin/bats tests/<specific>.bats -x` |
| Full suite command | `make test` or `./tests/bats/bin/bats tests/*.bats` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTO-01 | `/gsd:ralph` command file exists with correct frontmatter and structure | smoke | `./tests/bats/bin/bats tests/ralph-launcher.bats -x` | No -- Wave 0 |
| AUTO-02 | Loop engine launches claude -p, checks STATE.md, and iterates | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -x` | No -- Wave 0 |
| AUTO-05 | `--dry-run` prints command without executing | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -x` | No -- Wave 0 |
| PERM-01 | Default tier produces correct `--allowedTools` flag | unit | `./tests/bats/bin/bats tests/ralph-permissions.bats -x` | No -- Wave 0 |
| PERM-02 | Auto-mode tier produces `--permission-mode auto` | unit | `./tests/bats/bin/bats tests/ralph-permissions.bats -x` | No -- Wave 0 |
| PERM-03 | Yolo tier produces `--dangerously-skip-permissions` | unit | `./tests/bats/bin/bats tests/ralph-permissions.bats -x` | No -- Wave 0 |
| SAFE-01 | Command includes `--worktree` flag | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -x` | No -- Wave 0 |
| SAFE-02 | Command includes `--max-turns` from config | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -x` | No -- Wave 0 |
| OBSV-01 | Exit code detection distinguishes success from failure | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -x` | No -- Wave 0 |
| OBSV-02 | Terminal bell emitted on loop completion | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -x` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-permissions.bats`
- **Per wave merge:** `make test` (full suite)
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/ralph-launcher.bats` -- covers AUTO-01, AUTO-02, AUTO-05, SAFE-01, SAFE-02, OBSV-01, OBSV-02 (launcher loop, dry-run, worktree flag, max-turns, exit detection, bell)
- [ ] `tests/ralph-permissions.bats` -- covers PERM-01, PERM-02, PERM-03 (permission tier flag mapping)
- [ ] Test helper updates in `tests/test_helper/ralph-helpers.bash` -- mock claude command, mock STATE.md progression

## Sources

### Primary (HIGH confidence)
- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-usage) -- all flags including `--max-turns`, `--append-system-prompt-file`, `--permission-mode`, `--allowedTools`, `--worktree`, `--output-format`, `--dangerously-skip-permissions`
- [Claude Code Headless Mode / Agent SDK CLI](https://code.claude.com/docs/en/headless) -- `-p` flag behavior, JSON output structure (`result`, `session_id`, `cost_usd`, `duration_ms`, `num_turns`), `--continue`/`--resume` patterns
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- command file format, frontmatter fields, `$ARGUMENTS` substitution, `allowed-tools`, `user-invocable`, skill vs command equivalence
- [Claude Code Permissions](https://code.claude.com/docs/en/permissions) -- permission modes (default, acceptEdits, plan, dontAsk, bypassPermissions, auto), `--allowedTools` syntax, tool restriction
- [Claude Code Worktrees](https://code.claude.com/docs/en/common-workflows) -- `--worktree` behavior, naming, cleanup rules, headless interactions
- Claude Code CLI v2.1.72 `--help` output -- verified `--permission-mode` choices include `auto`

### Secondary (MEDIUM confidence)
- [SFEIR Institute Headless Mode Cheatsheet](https://institute.sfeir.com/en/claude-code/claude-code-headless-mode-and-ci-cd/cheatsheet/) -- JSON output field structure, exit code conventions, max-turns behavior
- Phase 10 RESEARCH.md -- architectural decisions, permission tier mapping, SKILL.md design
- Phase 10 deliverables (assemble-context.sh, validate-config.sh) -- existing code reviewed for integration

### Tertiary (LOW confidence)
- Worktree cleanup behavior in headless mode -- official docs describe interactive behavior but headless cleanup semantics need empirical validation
- `--permission-mode auto` exact judgment criteria -- listed as valid but behavior details sparse in public docs

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- based on official Claude Code docs, existing Phase 10 deliverables, and CLI help verification
- Architecture: HIGH -- GSD command pattern well-established; loop engine is a deterministic algorithm with clear inputs/outputs
- Permission tier mapping: HIGH -- all three tiers verified against CLI help and official permissions docs
- Pitfalls: HIGH -- CLAUDECODE nesting verified empirically; max-turns exit behavior documented; context staleness is a known pattern
- Worktree headless behavior: MEDIUM -- interactive behavior well-documented, headless cleanup needs empirical validation
- Loop completion detection: MEDIUM -- STATE.md is authoritative but exact field format parsing needs robust handling

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (30 days -- Claude Code CLI flags are stable; core behavior unlikely to change)
