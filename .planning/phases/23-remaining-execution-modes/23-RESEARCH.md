# Phase 23: Remaining Execution Modes - Research

**Researched:** 2026-03-11
**Domain:** Benchmark execution modes (GSD, Ralph, gsd-ralph) conforming to the Phase 22 mode abstraction layer
**Confidence:** HIGH

## Summary

Phase 23 implements three new mode scripts under `benchmarks/harness/lib/modes/` -- `gsd.sh`, `ralph.sh`, and `gsd-ralph.sh` -- each conforming to the identical `mode_invoke(prompt, workdir, max_turns, time_cap_seconds)` contract established in Phase 22. The existing `bench-run.sh` orchestrator already handles dynamic mode sourcing (`source "$SCRIPT_DIR/lib/modes/${mode}.sh"`), so no changes to the orchestrator are needed. Each new mode script produces JSON on stdout, logs stderr to the workdir, and returns exit codes compatible with the existing pipeline (0=normal, 124=timeout, other=error).

The three modes have fundamentally different invocation mechanisms. MODE-02 (GSD/CC+GSD) is a human-in-the-loop methodology where `claude -p` is invoked with GSD planning artifacts pre-scaffolded in the worktree, producing a single N=1-2 data point with `human_interventions` documented. MODE-03 (Ralph/CC+Ralph) invokes the existing `ralph-launcher.sh` with its loop engine, STATE.md progress detection, and circuit breakers. MODE-04 (gsd-ralph/CC+gsd-ralph) invokes `claude -p` with the `--agent` flag pointing to a custom agent definition that replicates the `/gsd:ralph` slash command behavior -- an Agent-tool-based loop running inside a single Claude Code session.

The key architectural insight is that all three modes ultimately invoke `claude -p` with different configurations -- the variation is in what scaffolding is created beforehand (GSD plans, STATE.md), what flags are passed, and how the loop/iteration model works. The mode abstraction layer cleanly encapsulates these differences.

**Primary recommendation:** Implement the three mode scripts in order of increasing complexity: (1) gsd.sh (simplest -- just scaffolding + single `claude -p`), (2) ralph.sh (moderate -- invokes `ralph-launcher.sh` which manages its own loop), (3) gsd-ralph.sh (most complex -- requires custom agent JSON for `--agents` flag). Update `bench-run.sh` usage text to include the new modes. Each mode script should be < 80 lines.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MODE-02 | CC+GSD mode runs with GSD planning context as a human-in-the-loop methodology (N=1-2) | GSD scaffolding pattern documented below; challenge-specific PLAN.md generation; result JSON includes `human_interventions` field and methodology documentation |
| MODE-03 | CC+Ralph mode invokes `ralph-launcher.sh` with GSD scaffolding in the challenge worktree | `ralph-launcher.sh` invocation pattern documented; requires `.planning/`, `.ralph/`, STATE.md scaffolding in worktree; loop engine handles iterations internally |
| MODE-04 | CC+gsd-ralph mode invokes the Agent tool-based `/gsd:ralph` in headless mode | `--agents` CLI flag with inline JSON agent definition documented; replicates `/gsd:ralph` slash command's Agent-tool loop inside a `claude -p` session |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2.57 | Mode scripts | Same as all gsd-ralph and harness scripts |
| Claude Code CLI | 2.1.72+ | All mode invocations via `claude -p` | Same tool as CC mode; modes differ in flags/scaffolding |
| jq | 1.8.1 | JSON manipulation, agent definition, challenge loading | Already project dependency |
| GNU timeout | 9.10 | Time cap enforcement (wraps all `claude -p` calls) | Same as CC mode; available at `/opt/homebrew/bin/timeout` |
| ralph-launcher.sh | project | MODE-03 invocation target | Existing loop engine with STATE.md detection |
| assemble-context.sh | project | GSD context assembly for Ralph modes | Existing context builder |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| mktemp | macOS built-in | Temporary files for scaffolding artifacts | GSD and Ralph mode scaffolding |
| git | 2.x | Worktree state inspection | Commit counting, tag comparison |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `--agents` inline JSON for gsd-ralph | File-based `.claude/agents/` in worktree | Inline JSON is self-contained; file-based requires modifying the worktree state before run |
| `ralph-launcher.sh` for Ralph mode | Re-implementing the loop in the mode script | Launcher already handles loop, progress detection, circuit breakers; calling it directly avoids duplication |
| Pre-scaffolded PLAN.md for GSD mode | Generating plans dynamically | Pre-scaffolded is deterministic and faster; dynamic planning adds uncontrolled time |

## Architecture Patterns

### Recommended Project Structure
```
benchmarks/
  harness/
    lib/
      modes/
        cc.sh              # [EXISTS] CC mode (Phase 22)
        gsd.sh             # [NEW] CC+GSD mode
        ralph.sh           # [NEW] CC+Ralph mode
        gsd-ralph.sh       # [NEW] CC+gsd-ralph mode
    bench-run.sh           # [EXISTS] No changes needed (dynamic mode sourcing)
    lib/common.sh          # [EXISTS] May need modes list update in usage()
```

### Pattern 1: Mode Contract (Established in Phase 22)
**What:** Every mode script implements `mode_invoke(prompt, workdir, max_turns, time_cap_seconds)` with identical signature.
**When to use:** Every mode script.
**Contract:**
```bash
# All mode scripts MUST implement:
# mode_invoke(prompt, workdir, max_turns, time_cap_seconds)
#   - stdout: JSON from the mode's execution (claude -p --output-format json)
#   - stderr: redirected to workdir/.bench-stderr.log
#   - exit code: 0 = normal, 124 = timeout, other = error
#   - side effects: modifies files in workdir
mode_invoke() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap_seconds="$4"
    # ... mode-specific implementation
}
```

### Pattern 2: GSD Mode Scaffolding (MODE-02)
**What:** Before invoking `claude -p`, create lightweight GSD planning artifacts in the worktree so Claude has structured context. GSD mode is human-in-the-loop, so it records a single run with documentation.
**When to use:** gsd.sh mode script.
**Key design:**
- GSD mode creates a minimal `.planning/` directory with a single-task PLAN.md in the worktree
- The plan wraps the challenge prompt in GSD task structure
- `claude -p` is invoked with `--append-system-prompt` containing GSD context
- Result JSON should have `human_interventions: 0` (despite being "human-in-the-loop" methodology, the benchmark run is automated for measurement)
- The methodology difference is documented in the result, not in the execution path

```bash
# GSD mode: scaffold -> single claude -p invocation
mode_invoke() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap_seconds="$4"

    cd "$workdir"

    # Create GSD scaffolding
    _scaffold_gsd_context "$workdir" "$prompt"

    # Build enhanced prompt with GSD planning context
    local gsd_prompt
    gsd_prompt=$(_build_gsd_prompt "$prompt" "$workdir")

    # Same invocation as CC mode, but with GSD context
    timeout "$time_cap_seconds" \
        claude -p "$gsd_prompt" \
        --output-format json \
        --max-turns "$max_turns" \
        --permission-mode auto \
        --no-session-persistence \
        2>"$workdir/.bench-stderr.log"
}
```

### Pattern 3: Ralph Mode Invocation (MODE-03)
**What:** Scaffold GSD artifacts (STATE.md, .ralph/, PLAN.md), then invoke `ralph-launcher.sh` which manages its own loop, progress detection, and circuit breakers.
**When to use:** ralph.sh mode script.
**Key design:**
- Must create `.planning/STATE.md`, `.planning/config.json`, `.ralph/` directory, and plan files in the worktree
- `ralph-launcher.sh` expects to find these at `PROJECT_ROOT` (the worktree root, not the `benchmarks/taskctl/` subdirectory)
- The launcher manages iterations internally; `mode_invoke` wraps the whole launcher under `timeout`
- stdout from the launcher contains its own JSON output; the harness captures this
- The launcher uses `--output-format json` internally, so we get metrics

```bash
# Ralph mode: scaffold -> invoke ralph-launcher.sh
mode_invoke() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap_seconds="$4"

    # Worktree root is 2 levels up from benchmarks/taskctl/
    local worktree_root
    worktree_root=$(cd "$workdir/../.." && pwd)

    # Create GSD + Ralph scaffolding in the worktree
    _scaffold_ralph_context "$worktree_root" "$workdir" "$prompt" "$max_turns"

    cd "$workdir"

    # Invoke ralph-launcher.sh from the worktree root context
    # The launcher manages its own loop and progress detection
    timeout "$time_cap_seconds" \
        env -u CLAUDECODE \
        bash "$RALPH_LAUNCHER" "execute-phase 1" \
        2>"$workdir/.bench-stderr.log"
}
```

### Pattern 4: gsd-ralph Mode via Agent Flag (MODE-04)
**What:** Invoke `claude -p` with `--agents` containing an inline JSON agent definition that replicates the `/gsd:ralph` slash command behavior.
**When to use:** gsd-ralph.sh mode script.
**Key design:**
- Uses `--agents` (plural) to define a custom ephemeral agent
- The agent definition includes the autopilot rules and GSD context as the system prompt
- Claude uses the Agent tool internally to delegate work (same as the slash command does)
- GSD scaffolding is pre-created in the worktree (same as Ralph mode)
- The main prompt tells Claude to use the custom agent

```bash
# gsd-ralph mode: scaffold -> invoke claude -p with custom agent
mode_invoke() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap_seconds="$4"

    local worktree_root
    worktree_root=$(cd "$workdir/../.." && pwd)

    # Create GSD scaffolding
    _scaffold_ralph_context "$worktree_root" "$workdir" "$prompt" "$max_turns"

    cd "$workdir"

    # Build agent JSON definition
    local agent_json
    agent_json=$(_build_gsd_ralph_agent "$worktree_root" "$prompt")

    timeout "$time_cap_seconds" \
        env -u CLAUDECODE \
        claude -p "Execute the GSD command: execute-phase 1 --ralph. Use the ralph-executor agent." \
        --agents "$agent_json" \
        --output-format json \
        --max-turns "$max_turns" \
        --permission-mode auto \
        --no-session-persistence \
        2>"$workdir/.bench-stderr.log"
}
```

### Pattern 5: Worktree Root vs Workdir Distinction
**What:** `workdir` is `benchmarks/taskctl/` inside the worktree. The worktree root is 2 levels up. Ralph and gsd-ralph modes need scaffolding at the worktree ROOT, while CC and GSD modes only need the workdir.
**When to use:** Ralph and gsd-ralph mode scripts.
**Critical:** `ralph-launcher.sh` uses `git rev-parse --show-toplevel` to find `PROJECT_ROOT`. In a detached worktree, this returns the worktree root. The scaffolding must be placed there.

### Anti-Patterns to Avoid
- **Modifying bench-run.sh for mode-specific logic:** The orchestrator should remain mode-agnostic. All mode differences live in the mode scripts.
- **Using `--worktree` flag in mode scripts:** The harness already manages worktree isolation. Claude's `--worktree` would create a nested worktree.
- **Running ralph-launcher.sh without `env -u CLAUDECODE`:** The launcher internally invokes `claude -p`, which detects the `CLAUDECODE` environment variable and refuses to start nested sessions. `env -u CLAUDECODE` is already used in the launcher's `build_claude_command()`.
- **Expecting exact JSON format from ralph-launcher.sh stdout:** The launcher's stdout is the JSON from its final `claude -p` iteration. Capture what comes; extract metrics defensively.
- **Creating full GSD project structure (all phases, all plans) for scaffolding:** Keep scaffolding minimal -- a single phase with a single plan containing the challenge prompt is sufficient.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ralph iteration loop | Custom loop in ralph.sh | `ralph-launcher.sh` (existing) | Already has progress detection, circuit breakers, retry logic, audit logging |
| Agent-based execution loop | Custom Agent tool calls in gsd-ralph.sh | `--agents` CLI flag with inline JSON | Claude Code natively handles agent delegation; custom loop replicates what the `/gsd:ralph` command does |
| GSD context assembly | Inline string concatenation | `assemble-context.sh` pattern (adapted) | Existing context builder handles STATE.md + plan discovery |
| Permission handling | Custom `--allowedTools` per mode | `--permission-mode auto` | Same as CC mode; consistent across all modes |
| Time cap enforcement | Mode-specific timeout | `timeout` wrapping `claude -p` | Same pattern as CC mode; consistent exit code behavior |

**Key insight:** Each mode script is a thin adapter that (1) scaffolds mode-specific artifacts in the worktree and (2) invokes `claude -p` with mode-specific flags. The heavy lifting is done by existing tools (`ralph-launcher.sh`, Agent tool, `timeout`).

## Common Pitfalls

### Pitfall 1: CLAUDECODE Environment Variable Blocking Nested Sessions
**What goes wrong:** `claude -p` detects the `CLAUDECODE` environment variable (set by the parent Claude Code session running the benchmark) and refuses to start, printing "Error: Claude Code cannot be launched inside another Claude Code session."
**Why it happens:** The harness is itself running inside Claude Code. Any child `claude -p` call inherits the environment.
**How to avoid:** Wrap all `claude -p` invocations with `env -u CLAUDECODE`. The existing `ralph-launcher.sh` already does this in `build_claude_command()`. For CC mode (cc.sh), this was not needed if running from a shell script, but for Ralph and gsd-ralph modes, it is critical.
**Warning signs:** Mode scripts failing immediately with the nested session error.

### Pitfall 2: ralph-launcher.sh Expects Full GSD Project Structure
**What goes wrong:** `ralph-launcher.sh` reads `.planning/config.json`, `.planning/STATE.md`, and runs `assemble-context.sh` which discovers phase directories. If these don't exist in the worktree, the launcher crashes.
**Why it happens:** The worktree is created from `bench/baseline` tag, which has `benchmarks/taskctl/` but no `.planning/` directory.
**How to avoid:** The ralph.sh mode script must scaffold a complete (but minimal) GSD project structure at the worktree root BEFORE invoking the launcher: `.planning/STATE.md`, `.planning/config.json`, `.planning/phases/01-challenge/01-01-PLAN.md`, `.ralph/` directory. Copy `assemble-context.sh` into the worktree's `scripts/` directory.
**Warning signs:** "STATE.md not found", "config.json not found", or "Context assembly failed" errors from the launcher.

### Pitfall 3: Worktree Root Detection in ralph-launcher.sh
**What goes wrong:** `ralph-launcher.sh` uses `git rev-parse --show-toplevel` to find `PROJECT_ROOT`. In a git worktree, this correctly returns the worktree root (e.g., `/tmp/bench-run-uuid/`), not the main repo root. But the launcher expects `.planning/` and `scripts/` to be there.
**Why it happens:** The launcher was designed for projects where GSD structure exists at the repo root. In the benchmark worktree, the challenge project is at `benchmarks/taskctl/` but the worktree root is higher.
**How to avoid:** Scaffold GSD artifacts at the worktree root, not at `benchmarks/taskctl/`. The launcher will find them via `git rev-parse --show-toplevel`.
**Warning signs:** Path resolution errors; files not found despite being created.

### Pitfall 4: GSD Mode Prompt Must Differ from Raw CC Mode
**What goes wrong:** If gsd.sh uses the same bare prompt as cc.sh, the mode produces identical results and provides no methodological differentiation.
**Why it happens:** The GSD methodology's value is in structured planning context, not just the prompt text.
**How to avoid:** gsd.sh must scaffold a PLAN.md with task structure, provide CLAUDE.md or system prompt with GSD conventions, and prepend planning context to the prompt. The prompt should reference the plan: "Follow the plan in .planning/ to complete this challenge."
**Warning signs:** GSD mode results statistically indistinguishable from CC mode.

### Pitfall 5: ralph-launcher.sh JSON Output Capture
**What goes wrong:** `ralph-launcher.sh` runs a loop of `claude -p` iterations. Its stdout contains logging output ("Ralph: Iter N done..."), not just JSON. The harness expects JSON on stdout from `mode_invoke`.
**Why it happens:** The launcher mixes human-readable progress messages with the claude -p JSON output. The `execute_iteration()` function runs `bash -c "$cmd"` which produces JSON, but `run_loop()` adds its own echo statements.
**How to avoid:** Two approaches: (a) Redirect launcher's stderr-style output to a separate file and capture only the last `claude -p` JSON output, or (b) accept that Ralph mode may not produce clean JSON on stdout and handle it in the mode script by capturing the launcher's output and extracting the JSON portion. The simplest approach: run `ralph-launcher.sh` with its stdout captured, then extract the last valid JSON object from the output.
**Warning signs:** jq parse errors on the mode_invoke output; mixed text/JSON in the capture file.

### Pitfall 6: Agent Tool Not Available in `-p` Mode by Default
**What goes wrong:** The `--agents` flag defines subagent definitions that Claude CAN delegate to using the Agent tool. But the Agent tool must be available to the session for delegation to occur.
**Why it happens:** In `-p` mode with `--permission-mode auto`, the Agent tool should be available by default. But if `--allowedTools` is used restrictively, Agent might be excluded.
**How to avoid:** Use `--permission-mode auto` (which enables all tools including Agent) rather than `--allowedTools` for gsd-ralph mode. Verify Agent tool availability.
**Warning signs:** Claude not delegating to the defined subagent; executing everything in the main context instead.

### Pitfall 7: bench-run.sh Usage Text and Require Statements
**What goes wrong:** The usage function in `bench-run.sh` lists only `cc` as an available mode. New modes work (dynamic sourcing handles it) but the help text is misleading. Also, `require_command claude` is called unconditionally, but Ralph mode additionally needs `ralph-launcher.sh` to be accessible.
**Why it happens:** The usage text was written for Phase 22 which only had CC mode.
**How to avoid:** Update the usage text to list all four modes. Mode-specific prerequisite validation can happen inside each mode script rather than in bench-run.sh.
**Warning signs:** Users confused by help text; Ralph mode failing because launcher is not in PATH.

## Code Examples

Verified patterns from the project codebase and official documentation.

### GSD Mode Scaffolding
```bash
# Create minimal GSD planning artifacts in the worktree
_scaffold_gsd_context() {
    local workdir="$1"
    local challenge_prompt="$2"

    local worktree_root
    worktree_root=$(cd "$workdir/../.." && pwd)

    # Create minimal .planning directory at worktree root
    mkdir -p "$worktree_root/.planning/phases/01-challenge"

    # Create a minimal PLAN.md wrapping the challenge prompt
    cat > "$worktree_root/.planning/phases/01-challenge/01-01-PLAN.md" << PLANEOF
# Plan 01-01: Challenge Task

<task id="1">
<title>Complete the challenge</title>
<details>

## Objective

${challenge_prompt}

## Approach

1. Read and understand the existing codebase
2. Implement the required changes
3. Write or update tests as needed
4. Verify all existing tests still pass
5. Commit changes with conventional commit messages

## Verification

- All existing tests pass
- New functionality works as described
- Code follows project conventions

</details>
</task>
PLANEOF
}
```

### Ralph Mode Launcher Invocation
```bash
# Scaffold full Ralph context and invoke the launcher
_scaffold_ralph_context() {
    local worktree_root="$1"
    local workdir="$2"
    local challenge_prompt="$3"
    local max_turns="$4"

    # Create GSD scaffolding (reuse gsd helper)
    _scaffold_gsd_context "$workdir" "$challenge_prompt"

    # Create STATE.md for ralph-launcher progress detection
    cat > "$worktree_root/.planning/STATE.md" << 'STATEEOF'
---
status: in_progress
---

# Project State

## Current Position

Phase: 1 of 1
Plan: 1 of 1
Status: Executing
Last activity: Benchmark run started
STATEEOF

    # Create minimal config.json for Ralph
    cat > "$worktree_root/.planning/config.json" << CFGEOF
{
  "ralph": {
    "enabled": true,
    "max_turns": ${max_turns},
    "permission_tier": "auto-mode",
    "timeout_minutes": 30
  }
}
CFGEOF

    # Create .ralph directory (required by ralph-launcher.sh)
    mkdir -p "$worktree_root/.ralph"
}
```

### gsd-ralph Agent JSON Definition
```bash
# Build inline agent JSON for --agents flag
_build_gsd_ralph_agent() {
    local worktree_root="$1"
    local challenge_prompt="$2"

    # Read autopilot rules if available
    local autopilot_rules=""
    local skill_file="$BENCH_REPO_ROOT/.claude/skills/gsd-ralph-autopilot/SKILL.md"
    if [[ -f "$skill_file" ]]; then
        # Extract content after YAML frontmatter
        autopilot_rules=$(sed -n '/^---$/,/^---$/!p' "$skill_file" | tail -n +1)
    fi

    # Build agent JSON using jq for proper escaping
    jq -n \
        --arg prompt "You are Ralph autopilot executing a benchmark challenge autonomously. Complete the following task: ${challenge_prompt}. Work in the benchmarks/taskctl/ directory. ${autopilot_rules}" \
        --arg desc "Ralph autonomous executor for benchmark challenges" \
        '{
            "ralph-executor": {
                "description": $desc,
                "prompt": $prompt,
                "permissionMode": "bypassPermissions"
            }
        }'
}
```

### Mode Script Source Guard (Common Pattern)
```bash
#!/bin/bash
# harness/lib/modes/gsd.sh -- CC+GSD mode
# Sourced by bench-run.sh. Do NOT execute directly.
#
# Mode Contract: (identical to cc.sh)
# mode_invoke(prompt, workdir, max_turns, time_cap_seconds)
set -euo pipefail

# Source guard
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: gsd.sh must be sourced, not executed directly." >&2
    exit 1
fi
```

## Mode-Specific Design Details

### MODE-02: CC+GSD (gsd.sh)

**Invocation:** Single `claude -p` call with GSD planning context scaffolded.

**What makes it different from CC mode:**
1. A `.planning/` directory with PLAN.md exists in the worktree BEFORE Claude starts
2. The prompt references the plan and instructs Claude to follow it
3. The system prompt includes GSD conventions (conventional commits, task-by-task execution)

**Scaffolding needed:**
- `.planning/phases/01-challenge/01-01-PLAN.md` -- wraps challenge prompt in task structure
- Optional: `.planning/CLAUDE.md` or `--append-system-prompt` with GSD methodology guidance

**Human-in-the-loop note:** The requirement says "human-in-the-loop methodology (N=1-2)". In the benchmarking context, this means the GSD mode conceptually represents how a human would use GSD planning with CC. The automated run simulates this by pre-creating the planning artifacts a human would create. The result JSON should document this methodology distinction but `human_interventions` remains 0 for automated measurement consistency.

**JSON stdout:** Standard `claude -p --output-format json` output. Same extraction as CC mode.

### MODE-03: CC+Ralph (ralph.sh)

**Invocation:** `ralph-launcher.sh execute-phase 1` wrapping the challenge in GSD's execution model.

**What makes it different:**
1. Full GSD + Ralph scaffolding (STATE.md, config.json, .ralph/, PLAN.md)
2. Multi-iteration loop (the launcher calls `claude -p` multiple times until STATE.md shows completion)
3. Circuit breakers (wall-clock timeout, stall detection) managed by the launcher
4. Progress detection via STATE.md snapshots

**Scaffolding needed:**
- Everything from GSD mode PLUS:
- `.planning/STATE.md` with phase/plan/status fields the launcher can parse
- `.planning/config.json` with ralph section
- `.ralph/` directory
- `scripts/assemble-context.sh` accessible from the worktree (or symlinked)
- `scripts/validate-config.sh` accessible (or make validation non-fatal)

**Critical path issue -- assemble-context.sh:**
The launcher calls `scripts/assemble-context.sh` which must exist in the worktree. Two approaches:
1. Copy it into the worktree at `scripts/assemble-context.sh`
2. Set `CONTEXT_SCRIPT` environment variable to point to the main repo's copy

Approach 1 is simpler and self-contained.

**JSON stdout challenge:**
`ralph-launcher.sh` mixes progress logging with `claude -p` JSON output on stdout. The mode script should capture all stdout and extract the final JSON blob. Alternative: pipe launcher stdout to a file, then output the last valid JSON from that file.

**RALPH_SCRIPTS_DIR:**
The launcher uses `RALPH_SCRIPTS_DIR` to find sibling scripts. Set this to the directory containing `assemble-context.sh` in the worktree, or set it to the main repo's scripts directory.

### MODE-04: CC+gsd-ralph (gsd-ralph.sh)

**Invocation:** Single `claude -p` call with `--agents` defining an inline agent that replicates `/gsd:ralph` behavior.

**What makes it different:**
1. Uses Claude Code's Agent tool for internal delegation
2. The custom agent has the autopilot rules as its system prompt
3. Claude delegates the challenge work to the agent, which executes in a subagent context
4. Single `claude -p` process (no external loop); the agent loop happens inside Claude's session

**Scaffolding needed:**
- Same GSD scaffolding as GSD mode (minimal)
- Agent JSON definition passed via `--agents` flag

**Key design choice -- `--agent` vs `--agents`:**
- `--agent <name>` transforms the MAIN session into an existing agent (must be defined in `.claude/agents/` or similar)
- `--agents <json>` defines EPHEMERAL agents that Claude can delegate to during the session
- For benchmarking, `--agents` with inline JSON is preferred because it is self-contained and does not require modifying the worktree's `.claude/` directory.

Alternative approach: Use `--agent` (singular) to run the entire session AS the ralph agent. This is simpler and may be more appropriate since we want the ENTIRE session to behave as Ralph, not just delegate to it.

**Recommended approach:** Use `--agent gsd-ralph` if we place an agent definition file in the worktree's `.claude/agents/gsd-ralph.md`, OR use `--agents` with inline JSON and instruct the main prompt to delegate. The `--agent` approach (singular) that transforms the main session is simpler for benchmarking.

**Simplest implementation using --append-system-prompt:**
Since the goal is to run with Agent-tool-based autonomy in headless mode, the simplest approach that matches the `/gsd:ralph` behavior is:
1. Scaffold GSD artifacts in worktree
2. Invoke `claude -p` with `--append-system-prompt` containing the autopilot rules + GSD context
3. The prompt tells Claude to "execute the challenge using GSD methodology, spawning Agent subagents as needed for complex sub-tasks"
4. `--permission-mode auto` enables Agent tool access

This avoids the complexity of `--agents` JSON while still enabling Agent-tool-based execution. The key differentiator from Ralph mode is that this runs as a single `claude -p` session (no external loop).

**JSON stdout:** Standard `claude -p --output-format json` output. Same extraction as CC mode.

## bench-run.sh Updates

The existing `bench-run.sh` needs only cosmetic updates:

1. **Usage text:** Change `echo "Modes: cc"` to `echo "Modes: cc, gsd, ralph, gsd-ralph"`
2. **Mode validation:** Already handled by the file existence check (`if [[ ! -f "$mode_script" ]]`)
3. **Metric extraction:** Already defensive with jq fallbacks; works for all modes
4. **Result JSON fields:** `iterations` should be populated differently per mode (1 for cc/gsd, N for ralph/gsd-ralph), but this can be handled in the mode scripts by writing to a temp file that bench-run.sh reads, OR by accepting that `iterations` stays at 1 for the orchestrator's single invocation

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `/gsd:ralph` only works interactively | `--agents` flag enables Agent-based execution in `-p` mode | Claude Code 2.1+ | Enables MODE-04 benchmarking |
| `--agent` transforms main session | `--agents` defines ephemeral agents for delegation | Claude Code 2.1+ | Cleaner separation for benchmarking |
| Each mode needs custom metric extraction | Single metric extraction pipeline with defensive jq | Phase 22 | All modes produce compatible result JSON |

## Open Questions

1. **ralph-launcher.sh stdout format for metric extraction**
   - What we know: The launcher mixes progress logging ("Ralph: Iter N done...") with `claude -p` JSON output on stdout
   - What's unclear: Whether the final JSON output is cleanly separable from the progress messages, or whether the JSON from individual iterations gets interleaved
   - Recommendation: Capture all launcher output to a file, then use `jq` to find the last valid JSON object. If this is too brittle, modify the mode script to capture only the last iteration's `claude -p` output by redirecting launcher progress to stderr.

2. **Whether `--agent` (singular) or `--agents` (plural) is better for MODE-04**
   - What we know: `--agent` transforms the session; `--agents` defines ephemeral agents for delegation
   - What's unclear: Whether `--agent` with an inline-created agent file works more reliably in `-p` mode than `--agents` with JSON
   - Recommendation: Start with the simpler `--append-system-prompt` approach (see MODE-04 design details). If that doesn't produce Agent-tool-based behavior distinct from CC mode, try `--agents` with inline JSON.

3. **Whether scripts/assemble-context.sh can run outside the main repo**
   - What we know: The script uses `git rev-parse --show-toplevel` for `PROJECT_ROOT` which works in worktrees
   - What's unclear: Whether it handles the scaffolded `.planning/` directory correctly when STATE.md has different format than the main project's STATE.md
   - Recommendation: Copy assemble-context.sh into the worktree and test. If format issues arise, create a simplified version that just reads the scaffolded STATE.md.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bats 1.13.0 (vendored at tests/bats/) |
| Config file | None (Bats uses CLI args) |
| Quick run command | `./tests/bats/bin/bats tests/` |
| Full suite command | `./tests/bats/bin/bats tests/` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MODE-02 | `bench-run.sh --mode gsd --challenge fix-bug` produces valid result JSON | integration (live) | Manual: `bash benchmarks/harness/bench-run.sh --mode gsd --challenge fix-bug` | N/A (live execution) |
| MODE-03 | `bench-run.sh --mode ralph --challenge fix-bug` invokes ralph-launcher.sh | integration (live) | Manual: `bash benchmarks/harness/bench-run.sh --mode ralph --challenge fix-bug` | N/A (live execution) |
| MODE-04 | `bench-run.sh --mode gsd-ralph --challenge fix-bug` invokes Agent-tool-based gsd:ralph | integration (live) | Manual: `bash benchmarks/harness/bench-run.sh --mode gsd-ralph --challenge fix-bug` | N/A (live execution) |

### Sampling Rate
- **Per task commit:** Bash syntax check: `bash -n benchmarks/harness/lib/modes/{gsd,ralph,gsd-ralph}.sh`
- **Per wave merge:** Bash syntax check for all mode scripts
- **Phase gate:** Full live execution of all three modes against at least one challenge

### Wave 0 Gaps
None -- existing test infrastructure covers syntax verification. Live execution testing is inherently manual (requires Claude CLI invocation with API calls).

## Sources

### Primary (HIGH confidence)
- Claude Code CLI `--help` output (2026-03-11) -- `--agent`, `--agents`, `--permission-mode`, `-p` flags verified
- Claude Code official docs: [Create custom subagents](https://code.claude.com/docs/en/sub-agents) -- `--agents` JSON format, ephemeral agent definitions, permission modes, tool inheritance
- Claude Code official docs: [Run Claude Code programmatically](https://code.claude.com/docs/en/headless) -- `-p` mode, `--output-format json`, `--append-system-prompt`, `--allowedTools`
- Existing codebase: `benchmarks/harness/lib/modes/cc.sh` -- mode contract reference implementation
- Existing codebase: `scripts/ralph-launcher.sh` -- loop engine, scaffolding requirements, `env -u CLAUDECODE` pattern
- Existing codebase: `.claude/commands/gsd/ralph.md` -- `/gsd:ralph` slash command definition with Agent tool-based execution pattern
- Existing codebase: `.claude/skills/gsd-ralph-autopilot/SKILL.md` -- autopilot rules for autonomous execution
- Existing codebase: `benchmarks/harness/bench-run.sh` -- dynamic mode sourcing at lines 104-109

### Secondary (MEDIUM confidence)
- Claude Code subagent documentation -- `--agents` JSON field names (`description`, `prompt`, `tools`, `permissionMode`, `maxTurns`)
- `ralph-launcher.sh` stdout format -- based on code reading, not live execution testing

### Tertiary (LOW confidence)
- Whether `--agent` (singular) can reference a file created at runtime in the worktree's `.claude/agents/` -- not tested, based on documentation inference

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools same as Phase 22; no new dependencies
- Architecture (GSD mode): HIGH -- simple extension of CC mode with scaffolding
- Architecture (Ralph mode): MEDIUM -- launcher integration has multiple scaffolding requirements that need live validation
- Architecture (gsd-ralph mode): MEDIUM -- `--agents` flag usage in `-p` mode not tested live; documentation supports it
- Pitfalls: HIGH -- based on actual codebase analysis of ralph-launcher.sh, bench-run.sh, and CLI behavior

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable tooling; main risk is Claude Code CLI changes to `--agents` flag)
