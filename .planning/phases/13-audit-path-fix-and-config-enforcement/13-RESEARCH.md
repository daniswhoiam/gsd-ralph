# Phase 13: Audit Path Fix and Config Enforcement - Research

**Researched:** 2026-03-10
**Domain:** Bash shell scripting -- environment variable propagation, config validation, integration bug fix
**Confidence:** HIGH

## Summary

Phase 13 addresses two specific tech debt items identified in the v2.0 milestone audit: (1) the split audit log caused by `RALPH_AUDIT_FILE` not being exported to the `claude -p` subprocess, and (2) the `ralph.enabled` config field being validated but never checked by the launcher.

Both fixes are narrow, well-scoped changes to existing files (`scripts/ralph-launcher.sh` and its test suite). The audit path fix requires exporting `RALPH_AUDIT_FILE` with an absolute path before `claude -p` invocation so the PreToolUse hook (running inside Claude Code's process) writes to the same file that `_print_audit_summary` reads. The config enforcement fix requires adding an early-exit check in the launcher's main block after `read_config` when `ralph.enabled` is `false`.

**Primary recommendation:** Export `RALPH_AUDIT_FILE` as an absolute path before the `claude -p` subprocess launch, and add a `ralph.enabled` check in both `read_config` and the main execution block.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| OBSV-04 (integration fix) | Auto-approved decisions logged to audit file for post-run review -- audit path must be unified between launcher and hook | Audit path fix via `export RALPH_AUDIT_FILE` with absolute path; config enforcement via early-exit on `ralph.enabled=false` |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | Shell scripting | macOS system bash compatibility requirement |
| jq | 1.6+ | JSON parsing | Already used throughout for config parsing |
| Bats | 1.x | Test framework | Already used for all project tests |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| bats-support | bundled | Test assertion helpers | Already in test_helper/ |
| bats-assert | bundled | Output assertions | Already in test_helper/ |
| bats-file | bundled | File existence assertions | Already in test_helper/ |

No new dependencies needed. All changes use existing project tooling.

## Architecture Patterns

### Relevant Project Structure
```
scripts/
  ralph-launcher.sh    # Main file to modify (export AUDIT_FILE + enabled check)
  ralph-hook.sh        # Reads RALPH_AUDIT_FILE env var (no changes needed)
  validate-config.sh   # Already validates ralph.enabled (no changes needed)
tests/
  ralph-launcher.bats  # Add new tests for enabled check + audit export
  ralph-hook.bats      # Existing tests already use exported RALPH_AUDIT_FILE
  test_helper/
    ralph-helpers.bash # May need helper for enabled=false config
```

### Pattern 1: Environment Variable Export for Subprocess Propagation
**What:** The `AUDIT_FILE` variable on line 39 of `ralph-launcher.sh` is a plain shell variable, not exported. The `ralph-hook.sh` script uses `${RALPH_AUDIT_FILE:-.ralph/audit.log}` (line 23) to find the audit log. When `claude -p` runs in a worktree, the hook's CWD is the worktree, so the relative fallback `.ralph/audit.log` writes to the worktree path instead of the project root.

**The fix:** Export `RALPH_AUDIT_FILE` with an absolute path before the `run_loop` function launches `claude -p`. The variable already uses `$PROJECT_ROOT` to build an absolute path (`$PROJECT_ROOT/.ralph/audit.log`), so exporting it is sufficient.

**Where to apply:**
- In `run_loop()`, after `_init_audit_log "$AUDIT_FILE"` on line 456, add: `export RALPH_AUDIT_FILE="$AUDIT_FILE"`
- This ensures the env var is available to all child processes including `bash -c "$cmd"` in `execute_iteration`

**Example:**
```bash
# In run_loop(), after _init_audit_log:
_init_audit_log "$AUDIT_FILE"
export RALPH_AUDIT_FILE="$AUDIT_FILE"  # Make absolute path available to hook subprocess
```

**Why this works:** Claude Code hooks documentation confirms: "Handlers run in the current directory with Claude Code's environment." The `claude -p` process inherits exported env vars from the launcher, and the hook subprocess inherits from `claude -p`. The hook already reads `RALPH_AUDIT_FILE` via the `${RALPH_AUDIT_FILE:-.ralph/audit.log}` pattern.

### Pattern 2: Early-Exit Config Check
**What:** `ralph.enabled` is validated by `validate-config.sh` (ensures boolean type) but `ralph-launcher.sh` never reads or checks it. Setting `enabled: false` has no effect.

**The fix:** Read `ralph.enabled` in `read_config()` and check it in the main execution block before `run_loop`.

**Where to apply:**
- Add a new variable `RALPH_ENABLED=true` in the defaults section
- Read `ralph.enabled` from config in `read_config()`
- Check `RALPH_ENABLED` after `read_config` and before `run_loop` in the main block
- Exit with code 0 and a clear message when disabled

**Example:**
```bash
# New default variable
RALPH_ENABLED=true

# In read_config():
local cfg_enabled
cfg_enabled=$(jq -r '.ralph.enabled // empty' "$CONFIG_FILE" 2>/dev/null)
if [ "$cfg_enabled" = "false" ]; then
    RALPH_ENABLED=false
fi

# In main execution block, after read_config:
if [ "$RALPH_ENABLED" = "false" ]; then
    echo "Ralph is disabled (ralph.enabled=false in config.json). Exiting."
    exit 0
fi
```

### Anti-Patterns to Avoid
- **Modifying ralph-hook.sh to hardcode the path:** The hook should remain a generic script that reads the env var. Hardcoding a path would break test isolation.
- **Checking enabled inside run_loop:** The check should happen as early as possible, before any side effects (hook installation, audit file creation). Put it in the main block.
- **Using AUDIT_FILE directly as the env var name:** The hook already uses `RALPH_AUDIT_FILE` (with the `RALPH_` prefix). Keep the internal variable `AUDIT_FILE` and export as `RALPH_AUDIT_FILE`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Audit path resolution | Custom path resolution logic in the hook | `export RALPH_AUDIT_FILE="$AUDIT_FILE"` from launcher | The launcher already computes the absolute path; just share it |
| Config boolean parsing | String comparison with "true"/"false"/"yes"/"no" | `jq -r '.ralph.enabled // empty'` + check for "false" | jq already handles JSON boolean to string conversion |

## Common Pitfalls

### Pitfall 1: Exporting at the Wrong Scope
**What goes wrong:** Exporting `RALPH_AUDIT_FILE` at the top of the script (near line 39) would work for direct execution but would also export it during `source ralph-launcher.sh` in tests, potentially leaking state between test runs.
**Why it happens:** The variable is defined in the global scope at script load time.
**How to avoid:** Export inside `run_loop()` right after `_init_audit_log`, which is only called during actual execution, not during sourcing.
**Warning signs:** Tests that set `AUDIT_FILE` in setup() start seeing unexpected values in `RALPH_AUDIT_FILE`.

### Pitfall 2: Config Check Placement
**What goes wrong:** If the enabled check runs before `read_config()`, it will always see the default value (`true`) and never actually disable.
**Why it happens:** `read_config()` is what populates `RALPH_ENABLED` from the config file.
**How to avoid:** Place the check after both `read_config` and `parse_args` in the main block.
**Warning signs:** Setting `ralph.enabled: false` has no effect.

### Pitfall 3: Exit Code on Disabled
**What goes wrong:** Using `exit 1` when disabled would make CI/CD pipelines fail when ralph is intentionally disabled.
**Why it happens:** Confusion between "error" and "intentionally not running."
**How to avoid:** Exit with code 0 and a clear informational message. This is not an error condition.
**Warning signs:** CI failures when ralph is disabled.

### Pitfall 4: Test Isolation with Exported Variables
**What goes wrong:** Tests that source `ralph-launcher.sh` may pollute the environment with an exported `RALPH_AUDIT_FILE` that persists across test functions.
**Why it happens:** `export` in a sourced file affects the current shell.
**How to avoid:** Tests already use `TEST_TEMP_DIR` isolation. The export happens inside `run_loop()` which runs in a subshell via `run run_loop ...` in Bats tests. Existing test patterns handle this correctly.
**Warning signs:** Audit file appearing in unexpected locations during test runs.

## Code Examples

### Fix 1: Export RALPH_AUDIT_FILE in run_loop

```bash
# In run_loop(), after _init_audit_log (around line 456-457):
_init_audit_log "$AUDIT_FILE"
export RALPH_AUDIT_FILE="$AUDIT_FILE"
_install_hook
trap _cleanup EXIT INT TERM
```

Source: Analysis of `scripts/ralph-launcher.sh` lines 39, 456, and `scripts/ralph-hook.sh` line 23.

### Fix 2: Read and Check ralph.enabled

```bash
# New default (near line 33, after existing defaults):
RALPH_ENABLED=true

# In read_config() (after existing field reads):
local cfg_enabled
cfg_enabled=$(jq -r '.ralph.enabled // empty' "$CONFIG_FILE" 2>/dev/null)
if [ "$cfg_enabled" = "false" ]; then
    RALPH_ENABLED=false
fi

# In main block (after read_config, before GSD_COMMAND check):
read_config

if [ "$RALPH_ENABLED" = "false" ]; then
    echo "Ralph is disabled (ralph.enabled=false in config.json). Exiting."
    exit 0
fi
```

Source: Analysis of `scripts/ralph-launcher.sh` `read_config()` function and `scripts/validate-config.sh` `validate_ralph_config()` function.

### Test Pattern: Config Enforcement

```bash
@test "read_config sets RALPH_ENABLED to false when config says false" {
    create_ralph_config false 50 "default"
    PROJECT_ROOT="$TEST_TEMP_DIR"
    CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
    RALPH_ENABLED=true
    read_config
    [ "$RALPH_ENABLED" = "false" ]
}

@test "launcher exits early with message when ralph.enabled is false" {
    create_ralph_config false 50 "default"
    # Run the launcher script directly (not sourced)
    run bash "$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh" execute-phase 11
    assert_success  # exit 0, not error
    assert_output --partial "disabled"
}
```

Source: Existing test patterns in `tests/ralph-launcher.bats` and `tests/test_helper/ralph-helpers.bash`.

### Test Pattern: Audit File Export

```bash
@test "run_loop exports RALPH_AUDIT_FILE with absolute path" {
    create_mock_state_advanced 11 2 "Complete"
    create_mock_assemble_context 0

    # Mock claude that checks for RALPH_AUDIT_FILE env var
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<MOCKEOF
#!/bin/bash
echo "AUDIT_FILE_VALUE=\$RALPH_AUDIT_FILE" >> "$TEST_TEMP_DIR/env-capture.log"
echo '{"type":"result","result":"done","num_turns":5}'
exit 0
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"

    PROJECT_ROOT="$TEST_TEMP_DIR"
    STATE_FILE="$TEST_TEMP_DIR/.planning/STATE.md"
    CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"
    STOP_FILE="$TEST_TEMP_DIR/.ralph/.stop"
    AUDIT_FILE="$TEST_TEMP_DIR/.ralph/audit.log"
    MAX_TURNS=50
    PERMISSION_TIER="default"
    TIMEOUT_MINUTES=30

    run run_loop "execute-phase 11"
    assert_success

    # Verify RALPH_AUDIT_FILE was exported to subprocess
    run cat "$TEST_TEMP_DIR/env-capture.log"
    assert_output --partial "AUDIT_FILE_VALUE=$TEST_TEMP_DIR/.ralph/audit.log"
}
```

Source: Existing mock claude pattern in `tests/ralph-launcher.bats`.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| AUDIT_FILE as shell variable | RALPH_AUDIT_FILE exported env var | Phase 13 (this fix) | Unified audit log across worktree boundary |
| ralph.enabled validated but unchecked | ralph.enabled enforced at launcher startup | Phase 13 (this fix) | Config field becomes functional |

**No deprecated/outdated patterns** -- this phase fixes integration bugs, not API changes.

## Open Questions

1. **Hook CWD with --worktree**
   - What we know: Official docs say "Handlers run in the current directory with Claude Code's environment." When `--worktree` is active, the CWD is the worktree directory.
   - What's unclear: Whether the hook's CWD is always the worktree root or could be a subdirectory within it.
   - Recommendation: This is irrelevant because the fix uses an absolute path via `RALPH_AUDIT_FILE`, so CWD doesn't matter. No action needed.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bats 1.x (bats-core) |
| Config file | tests/bats/ (bundled binary) |
| Quick run command | `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats` |
| Full suite command | `./tests/bats/bin/bats tests/*.bats` |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| OBSV-04a | RALPH_AUDIT_FILE exported to claude subprocess | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "exports RALPH_AUDIT_FILE"` | Wave 0 |
| OBSV-04b | Hook writes audit to same file launcher reads | unit | `./tests/bats/bin/bats tests/ralph-hook.bats -f "audit"` | Exists (lines 57-71) |
| OBSV-04c | ralph.enabled=false causes early exit | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "disabled\|enabled"` | Wave 0 |
| OBSV-04d | ralph.enabled=true (or missing) does not block | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "enabled"` | Wave 0 |

### Sampling Rate
- **Per task commit:** `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-hook.bats`
- **Per wave merge:** `./tests/bats/bin/bats tests/*.bats`
- **Phase gate:** Full suite green before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New tests in `tests/ralph-launcher.bats` for RALPH_AUDIT_FILE export verification
- [ ] New tests in `tests/ralph-launcher.bats` for ralph.enabled enforcement (true, false, missing)

Existing test infrastructure (`ralph-helpers.bash` with `create_ralph_config`) already supports creating configs with `enabled: true/false`.

## Sources

### Primary (HIGH confidence)
- `scripts/ralph-launcher.sh` -- Direct source code analysis, lines 39 (AUDIT_FILE), 456 (_init_audit_log), 382 (_print_audit_summary)
- `scripts/ralph-hook.sh` -- Direct source code analysis, line 23 (RALPH_AUDIT_FILE fallback)
- `scripts/validate-config.sh` -- Direct source code analysis, lines 29-34 (enabled validation)
- `.planning/v2.0-MILESTONE-AUDIT.md` -- Audit findings defining the scope of this phase
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) -- Confirms hook subprocess environment inheritance

### Secondary (MEDIUM confidence)
- `tests/ralph-launcher.bats` -- Existing test patterns for mock claude, config, and run_loop testing
- `tests/ralph-hook.bats` -- Existing test patterns for RALPH_AUDIT_FILE env var usage

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies, pure Bash changes to existing files
- Architecture: HIGH -- exact line numbers identified, fix is 2-3 lines of production code
- Pitfalls: HIGH -- failure modes are well-understood from audit and direct code reading

**Research date:** 2026-03-10
**Valid until:** 2026-04-10 (stable -- Bash scripting patterns don't change)
