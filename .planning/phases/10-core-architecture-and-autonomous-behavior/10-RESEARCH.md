# Phase 10: Core Architecture and Autonomous Behavior - Research

**Researched:** 2026-03-09
**Domain:** Claude Code headless mode, GSD skill architecture, autonomous agent behavior
**Confidence:** HIGH

## Summary

Phase 10 produces foundational artifacts -- not user-facing code -- that define what gsd-ralph does versus what GSD and Claude Code handle natively. The four deliverables are: (1) a SKILL.md with autonomous behavior rules, (2) a Ralph config schema extension in `.planning/config.json`, (3) GSD context assembly logic, and (4) architectural boundary documentation.

The critical discovery is that **GSD slash commands (like `/gsd:execute-phase`) cannot be directly invoked via `claude -p` headless mode**. The official Claude Code docs explicitly state: "User-invoked skills like `/commit` and built-in commands are only available in interactive mode. In `-p` mode, describe the task you want to accomplish instead." This means the context assembly logic must inject GSD workflow content (not slash command invocations) into the headless prompt via `--append-system-prompt` or `--append-system-prompt-file`. The GSD command files at `~/.claude/commands/gsd/` use `@file` references to load workflow markdown from `~/.claude/get-shit-done/workflows/` -- context assembly must replicate this loading pattern.

**Primary recommendation:** Build context assembly as a shell function (not a GSD tool extension) that reads STATE.md and the target phase plan, then outputs a combined context blob suitable for `--append-system-prompt-file`. Keep SKILL.md as a separate persistent file in `.claude/skills/gsd-ralph-autopilot/SKILL.md` for independent evolution.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Always pick the first option when GSD presents multi-option decisions (AskUserQuestion). GSD skills are designed with the recommended option first -- deterministic and debuggable.
- Auto-approve human-verify checkpoints with logging emphasis: write a brief rationale for WHY it was approved, AND create a git commit/tag at each checkpoint for incremental state review.
- Skip human-action steps and log them. Mark as skipped in the audit log with the action description. User reviews skipped actions post-run.
- Universal ruleset -- one set of autonomous behavior rules regardless of which GSD command Ralph is running. No command-aware conditional logic.
- Focused context: STATE.md (current position) + the specific phase plan being executed. Claude discovers PROJECT.md/REQUIREMENTS.md from CLAUDE.md if needed.
- Inject via `--append-system-prompt` flag on `claude -p`. Context appears as system instructions, cleanly separated from the user prompt (which is the GSD command).
- Essential settings only (3-5): `enabled` (bool), `max_turns` (int, default 50), `permission_tier` (default/auto-mode/yolo).
- Config lives inside `.planning/config.json` under a `"ralph"` key. Single source of truth, committed to repo, readable by GSD tools.
- Default `max_turns`: 50 per iteration.
- Schema validation: strict with warnings -- accept unknown keys but warn the user. Helps catch typos without breaking on new fields.
- "Coupling to GSD tools is fine -- duplicating GSD logic is not" -- this is the architectural principle.
- v1.x `.ralphrc` had 12 settings -- v2.0 intentionally slims to 3-5 essential settings.

### Claude's Discretion
- Context assembly implementation approach (shell function vs GSD tool extension)
- SKILL.md bundling strategy (bundled vs separate file) -- weigh maintainability
- Exact SKILL.md file format and structure
- Architectural boundary documentation format and location

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| AUTO-03 | System assembles GSD context (PROJECT.md, STATE.md, phase plans) into each iteration's prompt | Context assembly architecture: shell function reads STATE.md + phase plan, outputs combined blob for `--append-system-prompt-file`. Decision narrows scope to STATE.md + active phase plan only (focused context). |
| AUTO-04 | System injects autonomous behavior prompt that prevents AskUserQuestion and auto-approves checkpoints | SKILL.md as persistent file in `.claude/skills/gsd-ralph-autopilot/SKILL.md` with autonomous behavior rules. Separate from context assembly for independent evolution. Loaded automatically by Claude Code skill discovery. |
</phase_requirements>

## Standard Stack

### Core

| Component | Location | Purpose | Why Standard |
|-----------|----------|---------|--------------|
| SKILL.md | `.claude/skills/gsd-ralph-autopilot/SKILL.md` | Autonomous behavior rules | Claude Code native skill format; auto-discovered by skill loader |
| config.json extension | `.planning/config.json` `"ralph"` key | Ralph-specific settings | GSD established pattern; single source of truth |
| Context assembly | `bin/gsd-ralph-context.sh` or embedded function | Build `--append-system-prompt-file` content | Shell script; Bash 3.2 compatible; reads GSD artifacts |
| Architecture doc | `ARCHITECTURE.md` in project root or `.planning/` | Boundary documentation | Markdown; human and CI readable |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| jq | any | Parse config.json for validation | Config validation in shell scripts |
| Claude Code CLI | current | `--append-system-prompt`, `--append-system-prompt-file`, `--max-turns`, `--permission-mode`, `--allowedTools` | Headless invocation (Phase 11, but schema must anticipate these flags) |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Separate SKILL.md file | Bundle rules into context assembly blob | SKILL.md evolves independently of context; separate is more maintainable |
| Shell function for context assembly | GSD tool extension (gsd-tools.cjs) | Shell function avoids coupling to GSD's Node.js toolchain; simpler for a Bash project |
| Project-level skill (`.claude/skills/`) | User-level skill (`~/.claude/skills/`) | Project-level is correct -- rules are project-specific, committed to repo |

## Architecture Patterns

### Recommended Project Structure

```
.claude/
  skills/
    gsd-ralph-autopilot/
      SKILL.md              # Autonomous behavior rules (AUTO-04)
      # No supporting files needed for v2.0

.planning/
  config.json              # Extended with "ralph" key

bin/
  gsd-ralph                # v1.x entry point (will be repurposed in Phase 11)

scripts/                   # or lib/ -- implementation detail
  assemble-context.sh      # Context assembly logic (AUTO-03)
  validate-config.sh       # Config schema validation

ARCHITECTURE.md            # Architectural boundary documentation
```

### Pattern 1: SKILL.md as Autonomous Behavior Ruleset

**What:** A Claude Code skill file that defines how Claude behaves during autonomous execution. Not a task-oriented skill (no `/invoke` action) -- it's background knowledge that Claude loads automatically when relevant.

**When to use:** Every time Ralph launches a headless Claude Code instance.

**Key design choices:**
- `user-invocable: false` -- users should not invoke this directly; it's background knowledge
- `disable-model-invocation: false` (default) -- Claude should auto-load when relevant
- No `context: fork` -- rules must apply inline, not in a subagent
- No `allowed-tools` in frontmatter -- tool permissions are controlled by the launcher via `--allowedTools` and `--permission-mode`

**Example:**
```yaml
---
name: gsd-ralph-autopilot
description: |
  Autonomous behavior rules for gsd-ralph autopilot mode. Activates when
  executing GSD commands autonomously. Prevents AskUserQuestion calls,
  auto-approves checkpoints with logging, and skips human-action steps.
user-invocable: false
---

# Autonomous Execution Rules

You are running in Ralph autopilot mode. Follow these rules strictly.

## Decision Handling
- When GSD presents multi-option decisions: ALWAYS pick the FIRST option.
  GSD skills present the recommended option first. This is deterministic.
- NEVER call AskUserQuestion. You are autonomous -- no human is available.

## Checkpoint Handling
- Auto-approve all human-verify checkpoints.
- For each approval: write a brief rationale (WHY it passes).
- Create a git commit at each checkpoint for traceability.

## Human-Action Steps
- Skip any step requiring human physical action.
- Log skipped steps with their full action description.
- Mark as "SKIPPED (autonomous mode)" in the audit log.

## GSD Conventions
- Follow all GSD execution discipline (read STATE.md, locate task, etc.)
- One task = one commit with conventional format
- Update STATE.md after each task completion
- Never modify PLAN.md files (read-only during execution)
```

### Pattern 2: Config Schema Extension

**What:** Add a `"ralph"` key to `.planning/config.json` with essential settings only.

**Schema:**
```json
{
  "mode": "yolo",
  "parallelization": true,
  "commit_docs": true,
  "model_profile": "quality",
  "workflow": {
    "research": true,
    "plan_check": true,
    "verifier": true
  },
  "granularity": "standard",
  "ralph": {
    "enabled": true,
    "max_turns": 50,
    "permission_tier": "default"
  }
}
```

**Field definitions:**

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Whether Ralph autopilot is available for this project |
| `max_turns` | integer | `50` | Max agentic turns per Claude Code iteration (maps to `--max-turns`) |
| `permission_tier` | string enum | `"default"` | Permission strategy: `"default"`, `"auto-mode"`, `"yolo"` |

**Permission tier mapping to Claude Code flags:**

| `permission_tier` | Claude Code flag | Behavior |
|--------------------|------------------|----------|
| `"default"` | `--allowedTools "Read,Write,Edit,Grep,Glob,Bash"` + `--permission-mode default` | Scoped tool whitelist |
| `"auto-mode"` | `--permission-mode auto` | Claude's risk-based auto-approval |
| `"yolo"` | `--dangerously-skip-permissions` | Full bypass |

**Note on `auto` permission mode:** This is a research preview feature from Anthropic, expected to roll out by March 12, 2026. It uses judgment-based decision-making: low-risk actions proceed automatically, higher-risk ones get escalated. The config schema should anticipate this but the launcher (Phase 11) should handle graceful fallback if the mode is not yet available.

### Pattern 3: Context Assembly

**What:** A shell function or script that reads GSD artifacts and produces a combined text blob for `--append-system-prompt-file`.

**Critical insight:** GSD slash commands (`/gsd:execute-phase 10`) are NOT available in `claude -p` headless mode. The official docs confirm: "User-invoked skills like /commit and built-in commands are only available in interactive mode." Therefore, context assembly must:

1. Read STATE.md to determine current position
2. Read the specific phase plan file(s) being executed
3. Combine into a system prompt supplement that tells Claude what to do

**The user prompt** (passed to `claude -p "..."`) should describe the task in natural language, not invoke a slash command. Example: `"Execute the tasks in the current GSD phase plan. Read STATE.md for your current position, then follow the plan instructions."`

**Context assembly output format:**
```
# Ralph Autopilot Context

## Current GSD State
[contents of STATE.md]

## Active Phase Plan
[contents of the specific plan file being executed]
```

**Implementation approach (shell function):**
```bash
#!/bin/bash
# assemble-context.sh -- Build context for --append-system-prompt-file
# Usage: assemble-context.sh [phase_number] [plan_number]

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
STATE_FILE="$PROJECT_ROOT/.planning/STATE.md"

# Read STATE.md
if [ ! -f "$STATE_FILE" ]; then
    echo "ERROR: STATE.md not found" >&2
    exit 1
fi

echo "# Ralph Autopilot Context"
echo ""
echo "## Current GSD State"
cat "$STATE_FILE"
echo ""

# Find and include phase plan
# Phase directory discovery follows GSD NN-slug format
PHASE_DIR=$(find "$PROJECT_ROOT/.planning/phases" -maxdepth 1 -type d -name "${1}-*" | head -1)
if [ -n "$PHASE_DIR" ] && [ -d "$PHASE_DIR" ]; then
    echo "## Active Phase Plan"
    # Include specific plan or all plans
    for plan in "$PHASE_DIR"/*-PLAN.md; do
        [ -f "$plan" ] && cat "$plan" && echo ""
    done
fi
```

### Pattern 4: Architectural Boundary Documentation

**What:** A clear document defining what gsd-ralph does and does NOT do.

**Core principle:** gsd-ralph NEVER parses `.planning/` files directly or replicates GSD logic. It calls GSD tools/commands but must never reimplement roadmap parsing, state management, etc.

**Boundary rules:**
- gsd-ralph CAN: read STATE.md, read PLAN.md files, read config.json
- gsd-ralph CAN: call `gsd-tools.cjs` commands
- gsd-ralph CANNOT: parse ROADMAP.md to determine phase ordering
- gsd-ralph CANNOT: update STATE.md directly (GSD handles this)
- gsd-ralph CANNOT: generate plans, research, or summaries
- gsd-ralph CANNOT: manage worktrees (Claude Code handles this via `--worktree`)

### Anti-Patterns to Avoid

- **Replicating GSD state management:** Never write code to parse ROADMAP.md frontmatter, update progress percentages, or manage phase transitions. GSD does this.
- **Command-aware SKILL.md:** The user explicitly decided on a universal ruleset. Do NOT create conditional behavior based on which GSD command is running.
- **Over-engineering config:** v1.x had 12 settings and it was too many. Stick to 3 essential settings. Resist adding fields "just in case."
- **Bundling SKILL.md into context blob:** Keep SKILL.md separate. It may evolve independently as GSD and Claude Code evolve. Claude Code's native skill discovery handles loading.
- **Using `--system-prompt` instead of `--append-system-prompt`:** The `--system-prompt` flag REPLACES the entire default prompt, breaking Claude Code's built-in capabilities. Always use `--append-system-prompt` to ADD to the defaults.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Skill discovery/loading | Custom skill loader | Claude Code native skill discovery from `.claude/skills/` | Claude Code auto-discovers skills; handles prioritization, context budgets |
| JSON config parsing in bash | Custom JSON parser | `jq` | Reliable, widely available, handles edge cases |
| GSD state management | Custom state tracker | GSD's `gsd-tools.cjs state load` | GSD owns state; we just read it |
| Permission management | Custom permission logic | Claude Code's `--permission-mode` and `--allowedTools` | Native feature; handles all edge cases |
| Worktree management | Custom git worktree code | Claude Code's `--worktree` flag | v1.x built this; Claude Code now does it natively |

**Key insight:** The entire point of v2.0 is to stop building things that Claude Code and GSD already handle. Every custom solution should be questioned: "Does Claude Code or GSD already do this?"

## Common Pitfalls

### Pitfall 1: Slash Commands in Headless Mode
**What goes wrong:** Attempting to invoke `/gsd:execute-phase 10` via `claude -p "/gsd:execute-phase 10"` -- the slash command is silently ignored or treated as plain text.
**Why it happens:** Claude Code explicitly disables user-invoked skills/commands in `-p` mode. Only model-invoked skills (those with `user-invocable: false` or default settings) can be auto-loaded.
**How to avoid:** Pass the task as a natural language prompt to `claude -p`. Inject the GSD workflow content via `--append-system-prompt-file` so Claude has the instructions it needs.
**Warning signs:** Claude in headless mode responds with generic answers instead of following GSD workflow steps.

### Pitfall 2: Config Schema Creep
**What goes wrong:** Adding "useful" config fields beyond the essential 3-5, recreating v1.x's 12-setting complexity.
**Why it happens:** Each downstream phase (11, 12) discovers a setting it "needs." Without discipline, config grows.
**How to avoid:** Essential settings only in Phase 10. If Phase 11/12 need more, they extend -- but the schema designed here should be minimal.
**Warning signs:** More than 5 fields in the `ralph` config key.

### Pitfall 3: SKILL.md That's Too Detailed
**What goes wrong:** Writing a SKILL.md that tries to replicate GSD's entire execution protocol, creating maintenance burden when GSD evolves.
**Why it happens:** Trying to make Ralph "smart" about GSD internals.
**How to avoid:** SKILL.md should contain behavior rules (what to do about decisions, checkpoints, human-action steps), NOT workflow instructions. The workflow comes from the GSD command content injected via context assembly.
**Warning signs:** SKILL.md references specific GSD file formats, phase structures, or execution steps.

### Pitfall 4: Context Assembly Reading Too Many Files
**What goes wrong:** Assembling context from PROJECT.md, REQUIREMENTS.md, ROADMAP.md, STATE.md, all plan files, research files, summaries -- blowing context budget.
**Why it happens:** Wanting to give Claude "maximum context."
**How to avoid:** User decided: focused context = STATE.md + active phase plan. Claude discovers PROJECT.md/REQUIREMENTS.md from CLAUDE.md if needed.
**Warning signs:** Context assembly function reads more than 2-3 files.

### Pitfall 5: Assuming `--permission-mode auto` Is Available
**What goes wrong:** Hardcoding `auto` mode as a config option but Claude Code doesn't support it yet (research preview, not GA).
**Why it happens:** The setting exists in the CLI `--help` but is a research preview.
**How to avoid:** Design the config schema to include `"auto-mode"` as a valid `permission_tier` value, but the launcher (Phase 11) should validate availability and fall back gracefully.
**Warning signs:** Errors about unknown permission mode at runtime.

## Code Examples

### SKILL.md File (Complete)

```yaml
# Source: Claude Code skills documentation (https://code.claude.com/docs/en/skills)
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
- Do not refactor or improve code that isn't part of the current task.
```

### Config Schema (config.json with ralph key)

```json
{
  "mode": "yolo",
  "parallelization": true,
  "commit_docs": true,
  "model_profile": "quality",
  "workflow": {
    "research": true,
    "plan_check": true,
    "verifier": true
  },
  "granularity": "standard",
  "ralph": {
    "enabled": true,
    "max_turns": 50,
    "permission_tier": "default"
  }
}
```

### Config Validation (Bash 3.2 compatible)

```bash
# Source: project patterns from .ralph/AGENT.md (Bash 3.2 compatibility)
validate_ralph_config() {
    local config_file="$1"
    local warnings=""

    # Check ralph key exists
    if ! jq -e '.ralph' "$config_file" >/dev/null 2>&1; then
        echo "WARNING: No 'ralph' key in config.json" >&2
        return 0  # Not an error -- Ralph may not be configured
    fi

    # Validate known fields
    local enabled
    enabled=$(jq -r '.ralph.enabled // "MISSING"' "$config_file")
    if [ "$enabled" != "true" ] && [ "$enabled" != "false" ] && [ "$enabled" != "MISSING" ]; then
        echo "WARNING: ralph.enabled should be true or false, got: $enabled" >&2
    fi

    local max_turns
    max_turns=$(jq -r '.ralph.max_turns // "MISSING"' "$config_file")
    if [ "$max_turns" != "MISSING" ]; then
        if ! echo "$max_turns" | grep -qE '^[0-9]+$'; then
            echo "WARNING: ralph.max_turns should be an integer, got: $max_turns" >&2
        fi
    fi

    local tier
    tier=$(jq -r '.ralph.permission_tier // "MISSING"' "$config_file")
    if [ "$tier" != "MISSING" ] && [ "$tier" != "default" ] && [ "$tier" != "auto-mode" ] && [ "$tier" != "yolo" ]; then
        echo "WARNING: ralph.permission_tier should be default|auto-mode|yolo, got: $tier" >&2
    fi

    # Warn on unknown keys (strict with warnings)
    local known_keys="enabled max_turns permission_tier"
    local actual_keys
    actual_keys=$(jq -r '.ralph | keys[]' "$config_file" 2>/dev/null)
    for key in $actual_keys; do
        case " $known_keys " in
            *" $key "*) ;;
            *) echo "WARNING: Unknown ralph config key: $key (typo?)" >&2 ;;
        esac
    done
}
```

### Context Assembly Script

```bash
#!/bin/bash
# assemble-context.sh -- Build context for --append-system-prompt-file
# Source: project architecture decisions from CONTEXT.md

set -euo pipefail

PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
STATE_FILE="$PROJECT_ROOT/.planning/STATE.md"
OUTPUT_FILE="${1:-/dev/stdout}"

# Validate STATE.md exists
if [ ! -f "$STATE_FILE" ]; then
    printf "ERROR: %s not found\n" "$STATE_FILE" >&2
    exit 1
fi

{
    printf "# Ralph Autopilot Context\n\n"
    printf "## Current GSD State\n\n"
    cat "$STATE_FILE"
    printf "\n\n"

    # Find active phase plan from STATE.md
    # Extract phase number from STATE.md "Phase: N of M" line
    phase_num=$(grep -oE 'Phase: [0-9]+' "$STATE_FILE" | grep -oE '[0-9]+' | head -1)

    if [ -n "$phase_num" ]; then
        # Find phase directory (GSD NN-slug format)
        phase_dir=$(find "$PROJECT_ROOT/.planning/phases" -maxdepth 1 -type d -name "${phase_num}-*" 2>/dev/null | head -1)

        if [ -n "$phase_dir" ] && [ -d "$phase_dir" ]; then
            printf "## Active Phase Plans\n\n"
            for plan_file in "$phase_dir"/*-PLAN.md; do
                if [ -f "$plan_file" ]; then
                    printf "### %s\n\n" "$(basename "$plan_file")"
                    cat "$plan_file"
                    printf "\n\n"
                fi
            done
        fi
    fi
} > "$OUTPUT_FILE"
```

## State of the Art

| Old Approach (v1.x) | Current Approach (v2.0) | When Changed | Impact |
|---------------------|------------------------|--------------|--------|
| `.ralphrc` with 12 settings | `config.json` `"ralph"` key with 3 settings | v2.0 rewrite | 75% fewer config options; single source of truth |
| Custom PROMPT.md per phase | SKILL.md + context assembly | v2.0 rewrite | Claude Code native skill format; auto-discovered |
| Custom worktree management | Claude Code `--worktree` flag | Claude Code native feature | Eliminated ~500 LOC of worktree code |
| Standalone CLI entry point | `--ralph` flag on GSD commands | v2.0 architectural pivot | From standalone tool to thin integration layer |
| Custom permission/approval logic | Claude Code `--permission-mode` + `--allowedTools` | Claude Code native feature | Eliminated custom permission code |
| GSD command invocation via slash commands | Natural language prompt + system prompt injection | Claude Code headless mode limitation | Slash commands unavailable in `-p` mode |

**Deprecated/outdated:**
- `.ralphrc` configuration file: replaced by `config.json` `"ralph"` key
- `.ralph/PROMPT.md`: replaced by SKILL.md + context assembly
- v1.x `bin/gsd-ralph` CLI with init/generate/execute/merge/cleanup subcommands: superseded by GSD native commands
- `--auto-mode` as Claude Code flag name: the actual flag is `--permission-mode auto` (research preview, March 2026)

## Open Questions

1. **GSD Skill Auto-Loading in Headless Mode**
   - What we know: Skills with `user-invocable: false` have their descriptions loaded into context. Full content loads "when invoked" by Claude. In headless mode, Claude can auto-load skills.
   - What's unclear: Will Claude reliably auto-load the `gsd-ralph-autopilot` skill during headless execution? The description-matching heuristic may not trigger if the prompt doesn't match keywords.
   - Recommendation: Design SKILL.md description to match common Ralph/autopilot/autonomous keywords. Also consider injecting SKILL.md content directly into the `--append-system-prompt-file` blob as a safety net (belt-and-suspenders). The separate file still exists for interactive use.

2. **`--permission-mode auto` Availability**
   - What we know: Listed in CLI help as a valid choice. Anthropic announced it as a research preview for March 12, 2026.
   - What's unclear: Whether it will be generally available when Phase 11's launcher needs it.
   - Recommendation: Include `"auto-mode"` in the config schema enum. Phase 11 launcher validates availability and falls back to `"default"` with a warning.

3. **Context Budget for SKILL.md**
   - What we know: Skill descriptions are loaded into context at 2% of context window budget. If too many skills exist, some are excluded.
   - What's unclear: Whether the user's existing 27 skills (in `~/.claude/skills/`) might crowd out the Ralph skill.
   - Recommendation: Keep SKILL.md description concise. The belt-and-suspenders approach (also injecting via system prompt) handles this edge case.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | bats-core 1.13.0 (git submodules in `tests/`) |
| Config file | `tests/bats/` submodule |
| Quick run command | `./tests/bats/bin/bats tests/<specific>.bats` |
| Full suite command | `make test` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| AUTO-03 | Context assembly produces valid output with STATE.md + plan content | unit | `./tests/bats/bin/bats tests/context-assembly.bats -x` | No -- Wave 0 |
| AUTO-04 | SKILL.md exists and contains required autonomous behavior rules | unit | `./tests/bats/bin/bats tests/skill-validation.bats -x` | No -- Wave 0 |
| CONFIG | Config validation accepts valid ralph config, warns on unknown keys | unit | `./tests/bats/bin/bats tests/ralph-config.bats -x` | No -- Wave 0 |
| ARCH | Architecture doc exists and documents boundary rules | smoke | `test -f ARCHITECTURE.md && grep -q "NEVER" ARCHITECTURE.md` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `./tests/bats/bin/bats tests/<relevant>.bats`
- **Per wave merge:** `make test`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/context-assembly.bats` -- covers AUTO-03 (context assembly output format, error handling)
- [ ] `tests/skill-validation.bats` -- covers AUTO-04 (SKILL.md content validation, frontmatter checks)
- [ ] `tests/ralph-config.bats` -- covers config schema (valid/invalid config, unknown key warnings)
- [ ] `tests/test_helper/ralph-helpers.bash` -- shared test fixtures (mock STATE.md, config.json)

## Sources

### Primary (HIGH confidence)
- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference) -- all flags including `--max-turns`, `--append-system-prompt`, `--permission-mode`, `--allowedTools`, `--worktree`
- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- SKILL.md format, frontmatter fields, auto-discovery, `user-invocable`, `disable-model-invocation`
- [Claude Code Headless Mode](https://code.claude.com/docs/en/headless) -- `-p` flag behavior, slash command limitation ("User-invoked skills are only available in interactive mode")
- [Claude Code Permissions](https://code.claude.com/docs/en/permissions) -- permission modes (default, acceptEdits, plan, dontAsk, bypassPermissions), rule syntax
- [Claude Code Hooks](https://code.claude.com/docs/en/hooks) -- PreToolUse hooks for Phase 12 AskUserQuestion denial (referenced for architecture awareness)

### Secondary (MEDIUM confidence)
- [Claude Code Auto Mode Announcement](https://www.startuphub.ai/ai-news/startup-news/2026/claude-code-auto-mode-simplifies-dev-workflow) -- `--permission-mode auto` research preview, expected March 12, 2026
- [ClaudeLog --max-turns FAQ](https://claudelog.com/faqs/what-is-max-turns-in-claude-code/) -- default behavior: no limit by default, but 10 in some headless contexts

### Tertiary (LOW confidence)
- `--permission-mode auto` exact behavior and GA date -- only research preview announced; needs validation when Phase 11 implements launcher

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- based on official Claude Code docs and existing project patterns
- Architecture: HIGH -- decisions are locked in CONTEXT.md; research confirms they align with Claude Code capabilities
- Pitfalls: HIGH -- slash command limitation verified against official docs; config anti-patterns from v1.x experience
- Context assembly: MEDIUM -- the general approach is sound but the exact interaction between SKILL.md auto-loading and headless mode needs Phase 11 validation

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (30 days -- Claude Code evolves rapidly but core features are stable)
