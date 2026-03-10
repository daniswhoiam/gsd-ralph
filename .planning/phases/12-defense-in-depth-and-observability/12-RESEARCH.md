# Phase 12: Defense-in-Depth and Observability - Research

**Researched:** 2026-03-10
**Domain:** Bash process management, Claude Code hooks system, observability patterns
**Confidence:** HIGH

## Summary

Phase 12 adds four capabilities to the Ralph autopilot: a wall-clock circuit breaker with graceful stop, a PreToolUse hook that denies AskUserQuestion as defense-in-depth, per-iteration progress display, and audit logging for hook denials and skipped steps. All four integrate into the existing `ralph-launcher.sh` loop engine and follow established Bash 3.2 patterns.

The circuit breaker and progress display are straightforward Bash patterns with no external dependencies. The PreToolUse hook uses Claude Code's documented hooks system via `settings.local.json`, with well-documented JSON decision control for denying tool calls. The audit log is a plain-text timestamped file. All features build on Phase 11's `run_loop()` function and Phase 10's SKILL.md behavioral rules.

**Primary recommendation:** Implement circuit breaker + progress display as modifications to `run_loop()` in ralph-launcher.sh; implement hook as a standalone bash script at `scripts/ralph-hook.sh` that is auto-installed into `.claude/settings.local.json` by the launcher; implement audit logging as a shared utility used by both the hook script and the launcher.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Wall-clock timeout default: **30 minutes**. Configurable via `ralph.timeout_minutes` in `.planning/config.json`.
- Graceful stop mechanism: **`.ralph/.stop` file**. User touches this file; loop checks for it between iterations.
- **PreToolUse hook** denies AskUserQuestion calls as defense-in-depth (SKILL.md is the primary layer).
- Hook response: **deny with guidance** -- return a message like "AskUserQuestion is blocked in autopilot mode. Pick the first option or log the blocker and exit."
- Hook also **logs the denied question** to the audit file.
- Hook scope: **AskUserQuestion only**. Other tools are controlled by the permission tier.
- Hook script location: **`scripts/ralph-hook.sh`** -- alongside other Ralph scripts.
- Hook installation: **auto-install on launch**. ralph-launcher.sh writes the hook config to settings before spawning claude -p, removes it on exit. Zero user setup.
- **Summary per iteration** to stdout: iteration number, elapsed time (per-iteration + total), STATE.md status (phase/plan/status), exit code.
- Format: one-line summary after each iteration completes.
- Timing: show both per-iteration duration and total elapsed time.
- **OBSV-03 (real-time stream-json parsing) deferred to v2.1**.
- Audit scope: **hook denials + skipped steps**.
- Format: **plain text, human-readable**. Timestamped lines.
- Location: **`.ralph/audit.log`** -- single file.
- Post-run: **summary at end** -- print count of logged events. Only if there were logged events.
- Terminal bell on circuit breaker trigger (consistent with Phase 11's existing bell pattern).

### Claude's Discretion
- Circuit breaker trigger behavior (wait for current iteration vs kill immediately)
- Hook config format for auto-install/removal in settings
- Audit log retention strategy (overwrite vs append across runs)
- Convenience stop command implementation approach (script vs skill)
- Progress display exact format string

### Deferred Ideas (OUT OF SCOPE)
- OBSV-03 (real-time stream-json parsing) -- deferred to v2.1.
- ORCH-03 (intelligent AskUserQuestion response strategies) -- v2.1+.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SAFE-03 | Circuit breaker with wall-clock timeout and graceful stop mechanism | Bash timer patterns using `$SECONDS` or `date` arithmetic; `.ralph/.stop` sentinel file; config extension for `ralph.timeout_minutes` |
| SAFE-04 | PreToolUse hook blocks AskUserQuestion as defense-in-depth | Claude Code hooks system with `hookSpecificOutput.permissionDecision: "deny"`; matcher `"AskUserQuestion"`; auto-install in `settings.local.json` |
| OBSV-03 | Real-time progress display by parsing stream-json output | **DEFERRED to v2.1** per user decision. Per-iteration summary display satisfies v2.0 visibility intent |
| OBSV-04 | Auto-approved decisions logged to audit file for post-run review | Plain-text `.ralph/audit.log`; shared `audit_log()` function; post-run summary count |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | All implementation | macOS system bash compatibility requirement |
| jq | any | JSON parsing in hook script | Already a project dependency (used in validate-config.sh, read_config) |
| Claude Code hooks | current | PreToolUse hook for AskUserQuestion blocking | Native Claude Code feature, documented JSON decision control |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| bats-core | bundled | Test framework | All tests for new functions |
| bats-assert | bundled | Test assertions | Assertion helpers in test files |
| bats-file | bundled | File existence assertions | File creation/cleanup tests |
| shellcheck | any | Static analysis | Pre-commit validation of new scripts |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `$SECONDS` for timing | `date +%s` arithmetic | `$SECONDS` is simpler but resets on subshell; `date +%s` is portable and composable. Use `date` for wall-clock timeout, `$SECONDS` for per-iteration display |
| settings.local.json for hook | settings.json (project) | settings.local.json is gitignored, appropriate for runtime-only config that should not be committed |
| Plain text audit log | JSON audit log | Plain text is human-readable, grep-friendly, and matches user decision. JSON would add complexity without benefit |

**Installation:**
```bash
# No new dependencies -- all tools already available in the project
```

## Architecture Patterns

### Recommended Project Structure
```
scripts/
  ralph-launcher.sh      # Modified: circuit breaker, progress display, hook install/cleanup, audit summary
  ralph-hook.sh           # NEW: PreToolUse hook script for AskUserQuestion denial + audit logging
  validate-config.sh      # Modified: add timeout_minutes validation
.ralph/
  .stop                   # NEW: sentinel file for graceful stop (runtime only)
  audit.log               # NEW: audit log file (runtime only)
.claude/
  settings.local.json     # Modified at runtime: hook config injected on launch, removed on exit
tests/
  ralph-launcher.bats     # Extended: circuit breaker, progress, hook install/cleanup tests
  ralph-hook.bats          # NEW: hook script unit tests
  ralph-config.bats        # Extended: timeout_minutes validation tests
  test_helper/
    ralph-helpers.bash     # Extended: new helpers for audit log, stop file, hook config
```

### Pattern 1: Wall-Clock Circuit Breaker
**What:** Track elapsed time across loop iterations and terminate when timeout exceeded.
**When to use:** Every `run_loop()` invocation.

**Recommendation (Claude's discretion -- trigger behavior):** Wait for the current iteration to finish naturally, then check the timeout before starting the next iteration. Rationale: killing mid-iteration risks leaving worktrees in a dirty state and produces incomplete commits. The check between iterations is clean and predictable. The timeout check happens at the same point as the `.ralph/.stop` file check -- at the top of the while loop, before the next `execute_iteration()` call.

**Example:**
```bash
# Source: Bash built-in date arithmetic (Bash 3.2 compatible)
# Record start time before loop
LOOP_START_EPOCH=$(date +%s)

# Inside run_loop(), at top of while loop:
_check_circuit_breaker() {
    local timeout_minutes="$1"
    local start_epoch="$2"
    local current_epoch
    current_epoch=$(date +%s)
    local elapsed_seconds=$((current_epoch - start_epoch))
    local timeout_seconds=$((timeout_minutes * 60))

    if [ $elapsed_seconds -ge $timeout_seconds ]; then
        echo "Ralph: Circuit breaker triggered after ${timeout_minutes}m." >&2
        printf '\a'
        return 1
    fi
    return 0
}
```

### Pattern 2: Graceful Stop via Sentinel File
**What:** Check for `.ralph/.stop` file between iterations; if present, stop the loop cleanly.
**When to use:** Every iteration boundary in `run_loop()`.

**Example:**
```bash
# Source: Standard Bash file-existence check
_check_graceful_stop() {
    local stop_file="$1"
    if [ -f "$stop_file" ]; then
        rm -f "$stop_file"  # Clean up after detection
        echo "Ralph: Graceful stop requested via .ralph/.stop" >&2
        printf '\a'
        return 1
    fi
    return 0
}
```

### Pattern 3: PreToolUse Hook with JSON Decision Control
**What:** A bash script that reads JSON from stdin, checks if tool_name is AskUserQuestion, and outputs a deny decision with guidance.
**When to use:** Automatically installed by launcher for every ralph-launched Claude session.

**Example:**
```bash
#!/bin/bash
# scripts/ralph-hook.sh -- PreToolUse hook: deny AskUserQuestion in autopilot mode
# Source: Claude Code hooks reference (https://code.claude.com/docs/en/hooks)

set -euo pipefail

# Read JSON input from stdin
INPUT=$(cat)

TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

if [ "$TOOL_NAME" = "AskUserQuestion" ]; then
    # Extract the question text for audit logging
    QUESTION=$(echo "$INPUT" | jq -r '.tool_input.question // .tool_input.questions // "unknown"')
    TIMESTAMP=$(date -u +"%Y-%m-%d %H:%M:%S")

    # Log to audit file
    AUDIT_FILE="${RALPH_AUDIT_FILE:-.ralph/audit.log}"
    echo "[$TIMESTAMP] DENIED AskUserQuestion: \"$QUESTION\"" >> "$AUDIT_FILE"

    # Return deny decision with guidance
    jq -n '{
        hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason: "AskUserQuestion is blocked in autopilot mode. Pick the first option or log the blocker and exit."
        }
    }'
    exit 0
fi

# All other tools: allow (exit 0 with no output)
exit 0
```

### Pattern 4: Hook Auto-Install in settings.local.json
**What:** Launcher writes hook config to `.claude/settings.local.json` before spawning claude -p, and removes it on exit.
**When to use:** Every `run_loop()` invocation.

**Recommendation (Claude's discretion -- hook config format):** Use `.claude/settings.local.json` because it is gitignored and appropriate for runtime-only configuration. Merge with any existing content in the file (read, merge, write). Use a trap to ensure cleanup on exit.

**Example:**
```bash
# Source: Claude Code settings docs (https://code.claude.com/docs/en/hooks)
_install_hook() {
    local settings_file="$PROJECT_ROOT/.claude/settings.local.json"
    local hook_script="$PROJECT_ROOT/scripts/ralph-hook.sh"

    # Read existing settings or start with empty object
    local existing="{}"
    if [ -f "$settings_file" ]; then
        existing=$(cat "$settings_file")
    fi

    # Merge hook config into existing settings
    echo "$existing" | jq --arg cmd "\"$hook_script\"" '
        .hooks.PreToolUse = (.hooks.PreToolUse // []) + [{
            matcher: "AskUserQuestion",
            hooks: [{
                type: "command",
                command: $cmd
            }]
        }]
    ' > "$settings_file"
}

_remove_hook() {
    local settings_file="$PROJECT_ROOT/.claude/settings.local.json"
    if [ -f "$settings_file" ]; then
        # Remove ralph hook entries, preserve other config
        jq 'if .hooks.PreToolUse then
            .hooks.PreToolUse = [.hooks.PreToolUse[] | select(.hooks[0].command | test("ralph-hook") | not)]
            | if (.hooks.PreToolUse | length) == 0 then del(.hooks.PreToolUse) else . end
            | if (.hooks | length) == 0 then del(.hooks) else . end
        else . end' "$settings_file" > "$settings_file.tmp" && mv "$settings_file.tmp" "$settings_file"
    fi
}
```

### Pattern 5: Per-Iteration Progress Display
**What:** Print a one-line summary after each iteration with iteration number, timings, state, and exit code.
**When to use:** After each `execute_iteration()` call in `run_loop()`.

**Recommendation (Claude's discretion -- format string):**
```
Ralph: Iter 3 done (2m 14s) | Total: 8m 32s | Phase 11, Plan 2/2, Executing | exit=0
```

**Example:**
```bash
# Source: Bash arithmetic and date formatting
_format_duration() {
    local seconds="$1"
    local mins=$((seconds / 60))
    local secs=$((seconds % 60))
    if [ $mins -gt 0 ]; then
        echo "${mins}m ${secs}s"
    else
        echo "${secs}s"
    fi
}

# Inside run_loop(), after execute_iteration():
local iter_end_epoch
iter_end_epoch=$(date +%s)
local iter_duration=$((iter_end_epoch - iter_start_epoch))
local total_duration=$((iter_end_epoch - LOOP_START_EPOCH))
local post_snapshot
post_snapshot=$(_capture_state_snapshot "$STATE_FILE")
echo "Ralph: Iter $iteration done ($(_format_duration $iter_duration)) | Total: $(_format_duration $total_duration) | $post_snapshot | exit=$iter_exit"
```

### Pattern 6: Audit Logging
**What:** Timestamped plain-text log for hook denials and skipped steps.
**When to use:** Hook script writes denial entries; launcher writes post-run summary.

**Recommendation (Claude's discretion -- retention strategy):** Overwrite (truncate) at the start of each run. Rationale: each run produces its own context; appending creates confusion about which entries belong to which run. The log file path is `.ralph/audit.log`.

**Example:**
```bash
# Source: Standard Bash file I/O
_init_audit_log() {
    local audit_file="$1"
    mkdir -p "$(dirname "$audit_file")"
    : > "$audit_file"  # Truncate
}

_audit_log() {
    local audit_file="$1"
    local message="$2"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
    echo "[$timestamp] $message" >> "$audit_file"
}

_print_audit_summary() {
    local audit_file="$1"
    if [ -f "$audit_file" ] && [ -s "$audit_file" ]; then
        local count
        count=$(wc -l < "$audit_file" | tr -d ' ')
        echo "Audit: $count decisions logged. See $audit_file for details."
    fi
}
```

### Anti-Patterns to Avoid
- **Killing claude -p mid-execution:** Never `kill -9` the claude process. Always wait for the current iteration to complete, then refuse to start the next one. Mid-iteration kills leave worktrees dirty and produce corrupt state.
- **Hardcoding hook config paths:** Use `$PROJECT_ROOT` to compute paths. The `.claude/settings.local.json` path must be relative to the project root.
- **Polling .ralph/.stop with sleep:** Do not add a background watcher process. Check the stop file synchronously between iterations -- it is simple, race-free, and deterministic.
- **Writing JSON to audit.log:** The user explicitly chose plain text format. Keep it grep-friendly.
- **Modifying settings.json (committed):** Use settings.local.json (gitignored) for runtime hook installation. The committed settings.json should not change.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON decision output from hook | String concatenation of JSON | `jq -n` for constructing JSON | Shell string quoting of JSON is error-prone; jq handles escaping |
| JSON merging for settings.local.json | sed/awk manipulation | `jq` merge operations | JSON structure must be valid; jq ensures correctness |
| Time formatting | Complex printf/awk | Simple `$((seconds / 60))` arithmetic | Bash integer arithmetic is sufficient for min:sec display |
| Hook configuration schema | Custom JSON schema | Claude Code's documented format | Must match exactly what Claude Code expects |

**Key insight:** The hook system is the only part with external API constraints (Claude Code's JSON format). Everything else is standard Bash. Focus testing effort on the hook script's JSON output correctness.

## Common Pitfalls

### Pitfall 1: AskUserQuestion May Not Fire in Headless Mode
**What goes wrong:** In headless mode (`claude -p`), AskUserQuestion may auto-complete with empty answers rather than firing the tool normally. The PreToolUse hook might never trigger because the tool might not be called.
**Why it happens:** Claude Code's headless mode has no TTY, so AskUserQuestion behavior is undefined/inconsistent. There are open GitHub issues about this (issues #12672, #10400, #10229).
**How to avoid:** This hook is defense-in-depth, not the primary layer. The primary prevention is SKILL.md Rule 1 ("Never Ask Questions"). The hook catches edge cases where the model ignores the SKILL.md instruction. If the tool silently fails in headless mode, that is also acceptable -- the question is blocked either way.
**Warning signs:** During testing, if the hook script is never called in headless mode, that does not indicate a bug -- it means the tool is already being suppressed.
**Confidence:** MEDIUM -- behavior confirmed via multiple GitHub issues but not tested in this specific context.

### Pitfall 2: Hook Snapshot Timing
**What goes wrong:** Claude Code captures a snapshot of hooks at startup. Changes to settings files during a session don't take effect until the next session.
**Why it happens:** Security design -- prevents mid-session hook modifications without review.
**How to avoid:** The hook must be installed BEFORE `claude -p` is spawned. The launcher should write to `settings.local.json` before calling `execute_iteration()` for the first time. Since each iteration spawns a new `claude -p` process, the hook is re-read each time.
**Warning signs:** Hook never fires despite being in settings.local.json.
**Confidence:** HIGH -- documented in official hooks reference.

### Pitfall 3: Cleanup on Abnormal Exit
**What goes wrong:** If the launcher crashes or is killed (Ctrl+C), the hook config stays in settings.local.json, affecting subsequent interactive Claude sessions.
**Why it happens:** No cleanup handler was registered.
**How to avoid:** Use `trap` to register cleanup on EXIT, INT, TERM signals. The trap should call `_remove_hook()` and `_print_audit_summary()`.
**Warning signs:** User reports that AskUserQuestion is blocked during normal interactive Claude sessions.
**Confidence:** HIGH -- standard Bash trap pattern.

### Pitfall 4: settings.local.json Already Has Content
**What goes wrong:** Overwriting settings.local.json destroys existing user configuration (permissions, other hooks).
**Why it happens:** Naive implementation writes a fresh JSON object instead of merging.
**How to avoid:** Always read existing content first, merge the hook config in, and write back. Use `jq` for safe JSON merging. On cleanup, remove only the ralph-specific hook entry.
**Warning signs:** User loses custom Claude settings after running Ralph.
**Confidence:** HIGH -- the existing `.claude/settings.local.json` in this project already has permissions entries.

### Pitfall 5: Bash 3.2 Date Arithmetic
**What goes wrong:** Using GNU date flags like `date -d` or `date +%s%N` (nanoseconds) that don't exist on macOS system date.
**Why it happens:** Development/testing on Linux with GNU coreutils.
**How to avoid:** Use only `date +%s` (epoch seconds, available on macOS) and `date -u +"%Y-%m-%d %H:%M:%S"` (UTC timestamp). Both work on macOS Bash 3.2.
**Warning signs:** "illegal option" errors from date command.
**Confidence:** HIGH -- established project convention.

### Pitfall 6: jq Not Available
**What goes wrong:** Hook script fails because jq is not installed on the target system.
**Why it happens:** jq is not a macOS built-in.
**How to avoid:** The project already depends on jq (used in validate-config.sh, read_config). Document it as a prerequisite. The hook script can also use exit code 2 as a fallback (simpler, no jq needed), but jq is preferred for clean deny-with-reason JSON.
**Warning signs:** Hook silently allows AskUserQuestion because jq parsing failed.
**Confidence:** HIGH -- jq dependency already established in project.

## Code Examples

### Claude Code Hook Settings Format
```json
// Source: https://code.claude.com/docs/en/hooks
// Must go in .claude/settings.local.json (gitignored, runtime only)
{
  "permissions": {
    "allow": [
      "existing permission rules..."
    ]
  },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "/absolute/path/to/scripts/ralph-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### Hook Deny Decision JSON Format
```json
// Source: https://code.claude.com/docs/en/hooks#pretooluse-decision-control
// This is what the hook script prints to stdout to deny the tool call
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "AskUserQuestion is blocked in autopilot mode. Pick the first option or log the blocker and exit."
  }
}
```

### Hook Input JSON (What the Script Receives on stdin)
```json
// Source: https://code.claude.com/docs/en/hooks#pretooluse-input
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/path/to/project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "AskUserQuestion",
  "tool_input": {
    "question": "Which approach should I use?",
    "options": ["Option A", "Option B"]
  },
  "tool_use_id": "toolu_01ABC123..."
}
```

### Config Validation Extension
```bash
# Source: Existing validate-config.sh pattern
# Add to known_keys list and validate timeout_minutes
local timeout_min
timeout_min=$(jq -r '.ralph.timeout_minutes // "MISSING"' "$config_file")
if [ "$timeout_min" != "MISSING" ]; then
    if ! echo "$timeout_min" | grep -qE '^[0-9]+$'; then
        echo "WARNING: ralph.timeout_minutes should be a positive integer, got: $timeout_min" >&2
        has_warnings=1
    fi
fi
# Update known_keys to include timeout_minutes
local known_keys="enabled max_turns permission_tier timeout_minutes"
```

### Trap-Based Cleanup
```bash
# Source: Standard Bash trap pattern
_cleanup() {
    _remove_hook
    _print_audit_summary "$AUDIT_FILE"
    rm -f "$STOP_FILE"
}
trap _cleanup EXIT INT TERM
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Top-level `decision: "block"` for PreToolUse | `hookSpecificOutput.permissionDecision: "deny"` | Claude Code v2.0+ (2025) | Must use hookSpecificOutput, not top-level decision |
| PreToolUse strips AskUserQuestion data | Fixed in v2.0.76 | Jan 2026 | PreToolUse hooks work correctly with AskUserQuestion as of v2.0.76 |
| No hook support in skills | Hooks supported in skill/agent frontmatter | Claude Code v2.0+ | Alternative to settings.json, but settings.local.json is better for runtime injection |

**Deprecated/outdated:**
- Top-level `decision` and `reason` fields in PreToolUse output: Deprecated. Use `hookSpecificOutput.permissionDecision` and `hookSpecificOutput.permissionDecisionReason` instead.
- `"approve"` and `"block"` values: Deprecated aliases for `"allow"` and `"deny"`.

## Open Questions

1. **AskUserQuestion tool_input schema in headless mode**
   - What we know: The tool has `question` and `questions` fields based on GitHub issues. The exact schema is not in official docs.
   - What's unclear: Whether `tool_input.question` or `tool_input.questions` (plural) is the correct field name for extracting the question text for audit logging.
   - Recommendation: In the hook script, use `jq -r '.tool_input.question // .tool_input.questions // "unknown"'` to handle both variants. The exact field doesn't matter for the deny decision -- only for audit log quality.

2. **Convenience stop command approach**
   - What we know: User wants a bash command rather than raw `touch .ralph/.stop`.
   - What's unclear: Whether to implement as a standalone script (`bin/ralph-stop`) or a GSD skill.
   - Recommendation: Simple script at `bin/ralph-stop` that does `touch "$(git rev-parse --show-toplevel)/.ralph/.stop" && echo "Stop requested."`. A GSD skill adds complexity for a one-liner. Keep it simple.

3. **Hook command path: relative vs absolute**
   - What we know: Claude Code supports `$CLAUDE_PROJECT_DIR` for project-relative paths.
   - What's unclear: Whether `$CLAUDE_PROJECT_DIR` works reliably in all contexts including worktrees.
   - Recommendation: Use absolute path at install time (`$PROJECT_ROOT/scripts/ralph-hook.sh`). The launcher knows the project root and can write the absolute path into settings.local.json. This avoids any path resolution ambiguity.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | bats-core (bundled in tests/test_helper/bats/) |
| Config file | None (bats runs directly) |
| Quick run command | `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats` |
| Full suite command | `./tests/bats/bin/bats tests/` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SAFE-03 | Circuit breaker stops after timeout | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "circuit_breaker"` | Wave 0 |
| SAFE-03 | Graceful stop via .ralph/.stop | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "graceful_stop"` | Wave 0 |
| SAFE-03 | timeout_minutes config validation | unit | `./tests/bats/bin/bats tests/ralph-config.bats -f "timeout"` | Wave 0 |
| SAFE-04 | Hook denies AskUserQuestion | unit | `./tests/bats/bin/bats tests/ralph-hook.bats -f "deny"` | Wave 0 |
| SAFE-04 | Hook allows other tools | unit | `./tests/bats/bin/bats tests/ralph-hook.bats -f "allow"` | Wave 0 |
| SAFE-04 | Hook auto-install in settings.local.json | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "install_hook"` | Wave 0 |
| SAFE-04 | Hook auto-removal on exit | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "remove_hook"` | Wave 0 |
| OBSV-03 | Per-iteration progress line | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "progress"` | Wave 0 |
| OBSV-04 | Audit log written on denial | unit | `./tests/bats/bin/bats tests/ralph-hook.bats -f "audit"` | Wave 0 |
| OBSV-04 | Audit summary printed at end | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "audit_summary"` | Wave 0 |

### Sampling Rate
- **Per task commit:** `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats tests/ralph-config.bats`
- **Per wave merge:** `./tests/bats/bin/bats tests/`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/ralph-hook.bats` -- covers SAFE-04 hook deny/allow/audit behaviors (NEW file)
- [ ] `tests/test_helper/ralph-helpers.bash` -- add helpers: `create_mock_audit_log`, `create_mock_stop_file`, `create_mock_settings_local`
- [ ] Extend `tests/ralph-launcher.bats` -- add circuit breaker, graceful stop, progress display, hook install/cleanup tests
- [ ] Extend `tests/ralph-config.bats` -- add timeout_minutes validation tests

## Sources

### Primary (HIGH confidence)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - PreToolUse configuration, matcher patterns, JSON decision control format, exit code behaviors, settings file locations
- [Claude Code Headless/CLI Docs](https://code.claude.com/docs/en/headless) - claude -p usage, output formats, tool auto-approval
- [Claude Code Hook Configuration Blog](https://claude.com/blog/how-to-configure-hooks) - Settings file hierarchy, PreToolUse examples

### Secondary (MEDIUM confidence)
- [GitHub Issue #12031](https://github.com/anthropics/claude-code/issues/12031) - PreToolUse + AskUserQuestion bug fixed in v2.0.76 (Jan 2026)
- [GitHub Issue #15872](https://github.com/anthropics/claude-code/issues/15872) - AskUserQuestion hook support request; PermissionRequest fires for AskUserQuestion
- [GitHub Issue #12605](https://github.com/anthropics/claude-code/issues/12605) - AskUserQuestion hook support; PreToolUse can detect but cannot respond to AskUserQuestion

### Tertiary (LOW confidence)
- [GitHub Issue #12672](https://github.com/anthropics/claude-code/issues/12672) - AskUserQuestion auto-completes with empty answers in some modes; needs validation in our specific headless context
- [GitHub Issue #10400](https://github.com/anthropics/claude-code/issues/10400) - AskUserQuestion returns empty response with bypass permissions; may affect yolo tier behavior

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - all Bash 3.2, jq, established project patterns
- Architecture: HIGH - extending existing ralph-launcher.sh with well-understood patterns
- Hook system: HIGH - official Claude Code docs with verified JSON format
- AskUserQuestion in headless mode: MEDIUM - behavior documented via GitHub issues but not official docs; defense-in-depth means this is acceptable
- Pitfalls: HIGH - based on official docs, project conventions, and verified issues

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (hooks API is stable; project patterns established)
