# Phase 14: Location-Independent Scripts - Research

**Researched:** 2026-03-10
**Domain:** Bash script path resolution and portability refactoring
**Confidence:** HIGH

## Summary

Phase 14 requires refactoring Ralph's `scripts/` subsystem so that scripts resolve each other through a configurable `RALPH_SCRIPTS_DIR` variable instead of hardcoded `$PROJECT_ROOT/scripts/` paths. In the dev repo, scripts live at `scripts/`; in an installed repo, they will live at `scripts/ralph/`. The refactor must be transparent to the existing 315-test suite.

The codebase has **two distinct subsystems** with different path resolution strategies. The `lib/` + `bin/` subsystem (the `gsd-ralph` CLI) already uses `$GSD_RALPH_HOME` for all internal references and is location-independent. The `scripts/` subsystem (ralph-launcher.sh, assemble-context.sh, validate-config.sh, ralph-hook.sh) uses hardcoded `$PROJECT_ROOT/scripts/` paths and is the target of this phase. The legacy ad-hoc scripts (ralph-execute.sh, ralph-merge.sh, ralph-cleanup.sh, ralph-status.sh, ralph-worktrees.sh) use `./scripts/` relative paths in display strings but are already marked DEPRECATED; they are not part of the v2.0 core path and their display-string references are cosmetic only.

**Primary recommendation:** Introduce `RALPH_SCRIPTS_DIR` at the top of `ralph-launcher.sh` with a self-detecting default, then propagate it to the three concrete path references (assemble-context.sh, validate-config.sh, ralph-hook.sh). Use the same `BASH_SOURCE` + directory resolution pattern already proven in `bin/gsd-ralph`. Keep backward compatibility: if `RALPH_SCRIPTS_DIR` is not set externally, auto-detect from the script's own location.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| PORT-01 | Ralph scripts work from both `scripts/` (dev repo) and `scripts/ralph/` (installed repo) | Auto-detection pattern via `BASH_SOURCE[0]` resolves script location regardless of parent directory name. Three hardcoded paths in ralph-launcher.sh need updating. |
| PORT-02 | All script-to-script references use configurable paths, not hardcoded locations | Replace `$PROJECT_ROOT/scripts/` with `$RALPH_SCRIPTS_DIR` in all three references. Export so subprocesses inherit. Allow external override. |
| PORT-03 | Existing 315 tests pass after portability refactor | Tests already use `$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh` for sourcing; auto-detection will resolve correctly. Tests that stub `CONTEXT_SCRIPT`/`VALIDATE_SCRIPT` directly are unaffected since they override the variable post-source. |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | Shell scripting | macOS system bash compatibility required |
| Bats | 1.x (vendored) | Test framework | Already in use, 315 tests |
| jq | any | JSON parsing | Already a dependency |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| coreutils (dirname, readlink) | system | Path resolution | Used for `BASH_SOURCE` directory detection |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `BASH_SOURCE` self-detection | `realpath` | `realpath` not available on stock macOS, `BASH_SOURCE` is portable |
| Single `RALPH_SCRIPTS_DIR` variable | Per-script variables | Over-engineering; one variable with one default covers all cases |

## Architecture Patterns

### Two-Subsystem Architecture (Current)

The codebase has two path resolution patterns:

```
bin/gsd-ralph              # Entry point - resolves GSD_RALPH_HOME via BASH_SOURCE
  -> lib/common.sh         # Sourced via $GSD_RALPH_HOME/lib/...
  -> lib/commands/*.sh      # Sourced via $GSD_RALPH_HOME/lib/commands/...
  -> templates/             # Referenced via $GSD_RALPH_HOME/templates/...

scripts/ralph-launcher.sh  # Entry point - uses $PROJECT_ROOT/scripts/...
  -> scripts/validate-config.sh    # HARDCODED: $PROJECT_ROOT/scripts/
  -> scripts/assemble-context.sh   # HARDCODED: $PROJECT_ROOT/scripts/
  -> scripts/ralph-hook.sh         # HARDCODED: $PROJECT_ROOT/scripts/
```

The `bin/gsd-ralph` pattern is the model. Phase 14 applies the same pattern to `scripts/ralph-launcher.sh`.

### Pattern 1: BASH_SOURCE Self-Detection (Proven in bin/gsd-ralph)
**What:** Script resolves its own directory from `BASH_SOURCE[0]`, then derives all sibling paths relative to that directory.
**When to use:** Any script that needs to find co-located files regardless of invocation path.
**Example (from bin/gsd-ralph lines 10-18):**
```bash
# Resolve script location (follows symlinks)
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
```

### Pattern 2: Environment Variable Override with Self-Detected Default
**What:** An environment variable provides the path, but if unset, auto-detects from `BASH_SOURCE`.
**When to use:** When the same code must work in both dev and installed contexts, and users need the option to override.
**Example (proposed for ralph-launcher.sh):**
```bash
# Allow override; auto-detect from script's own location if unset
if [ -z "${RALPH_SCRIPTS_DIR:-}" ]; then
    _RALPH_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
    while [ -L "$_RALPH_SCRIPT_SOURCE" ]; do
        _RALPH_SCRIPT_DIR="$(cd "$(dirname "$_RALPH_SCRIPT_SOURCE")" && pwd)"
        _RALPH_SCRIPT_SOURCE="$(readlink "$_RALPH_SCRIPT_SOURCE")"
        [[ "$_RALPH_SCRIPT_SOURCE" != /* ]] && _RALPH_SCRIPT_SOURCE="$_RALPH_SCRIPT_DIR/$_RALPH_SCRIPT_SOURCE"
    done
    RALPH_SCRIPTS_DIR="$(cd "$(dirname "$_RALPH_SCRIPT_SOURCE")" && pwd)"
fi
export RALPH_SCRIPTS_DIR
```

### Exact Hardcoded Paths to Replace

In `scripts/ralph-launcher.sh`, exactly three lines reference sibling scripts via `$PROJECT_ROOT/scripts/`:

| Line | Current Code | Replacement |
|------|-------------|-------------|
| 22 | `CONTEXT_SCRIPT="$PROJECT_ROOT/scripts/assemble-context.sh"` | `CONTEXT_SCRIPT="$RALPH_SCRIPTS_DIR/assemble-context.sh"` |
| 23 | `VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate-config.sh"` | `VALIDATE_SCRIPT="$RALPH_SCRIPTS_DIR/validate-config.sh"` |
| 346 | `local hook_script="$PROJECT_ROOT/scripts/ralph-hook.sh"` | `local hook_script="$RALPH_SCRIPTS_DIR/ralph-hook.sh"` |

**That is the complete set of functional path changes needed for PORT-01 and PORT-02.** All other `./scripts/` references in the codebase are either:
- In DEPRECATED legacy scripts (ralph-execute.sh, ralph-merge.sh, ralph-cleanup.sh, ralph-status.sh, ralph-worktrees.sh) -- display strings only
- Comments and usage documentation

### Anti-Patterns to Avoid
- **Changing `$PROJECT_ROOT` to mean something else:** `$PROJECT_ROOT` is the user's git project root. It must remain as-is for CONFIG_FILE, STATE_FILE, STOP_FILE, AUDIT_FILE, and other project-level paths. Only script-to-script sourcing paths should use `$RALPH_SCRIPTS_DIR`.
- **Adding a separate discovery mechanism:** Do not scan filesystem or use `which`/`type` to find scripts. `BASH_SOURCE` self-detection is simpler and deterministic.
- **Breaking the sourcing guard:** `ralph-launcher.sh` uses `if [ "${BASH_SOURCE[0]}" = "$0" ]; then` to guard its main block. When sourced by tests, `BASH_SOURCE[0]` is the launcher file, not `$0` (which is bats). This pattern must be preserved exactly.
- **Changing the `$0` check to `$BASH_SOURCE` check:** The current guard works. Do not modify it.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Symlink resolution | Custom readlink chain | Copy `bin/gsd-ralph`'s existing 7-line pattern | Already tested, handles relative symlinks |
| Cross-platform `realpath` | Conditional `realpath`/`grealpath` detection | `dirname` + `cd && pwd` pattern | `realpath` not on stock macOS; `dirname`+`cd` is universally portable |
| Script discovery | Path searching (`find`, `which`) | Self-detection from `BASH_SOURCE` | Deterministic, no ambiguity |

**Key insight:** The `bin/gsd-ralph` file already solves this exact problem for its subsystem. Copy the pattern, do not invent a new one.

## Common Pitfalls

### Pitfall 1: BASH_SOURCE Behavior When Sourced vs. Executed
**What goes wrong:** `BASH_SOURCE[0]` returns different values when a script is executed directly vs. sourced by another script.
**Why it happens:** When `ralph-launcher.sh` is executed directly (production use), `BASH_SOURCE[0]` is the launcher's path. When sourced by bats tests, `BASH_SOURCE[0]` is still the launcher's path (correct), but `$0` is the bats binary.
**How to avoid:** The `RALPH_SCRIPTS_DIR` auto-detection always uses `BASH_SOURCE[0]` (which points to the launcher regardless of invocation mode). Tests that source the launcher will auto-detect correctly.
**Warning signs:** Tests fail with "No such file" errors for validate-config.sh or assemble-context.sh.

### Pitfall 2: Tests That Override Path Variables After Sourcing
**What goes wrong:** Some tests set `CONTEXT_SCRIPT` to a custom value after sourcing the launcher. If the auto-detection happens at source time (top-level), these test overrides still work. If auto-detection were lazy (inside functions), it could re-detect and override the test's stub.
**Why it happens:** Tests like `ralph-launcher.bats` source the launcher and then set `CONTEXT_SCRIPT="$TEST_TEMP_DIR/scripts/assemble-context.sh"` for isolation.
**How to avoid:** Keep `RALPH_SCRIPTS_DIR` detection and `CONTEXT_SCRIPT`/`VALIDATE_SCRIPT` assignment at top-level (not inside functions). This preserves the test pattern of overriding after source.
**Warning signs:** Tests that stub CONTEXT_SCRIPT start using the real script instead of the stub.

### Pitfall 3: Confusing PROJECT_ROOT with RALPH_SCRIPTS_DIR
**What goes wrong:** Replacing `$PROJECT_ROOT` globally instead of surgically replacing only the three script-path lines.
**Why it happens:** Overzealous search-and-replace.
**How to avoid:** `$PROJECT_ROOT` is used correctly for config.json, STATE.md, STOP_FILE, AUDIT_FILE, settings.local.json, and `.claude/` directory. Only the three `$PROJECT_ROOT/scripts/` lines (pointing to sibling scripts) should change.
**Warning signs:** Config file not found errors, STATE.md not found errors, audit log written to wrong location.

### Pitfall 4: Export Scope for RALPH_SCRIPTS_DIR
**What goes wrong:** Not exporting `RALPH_SCRIPTS_DIR`, so subprocesses (like `bash "$CONTEXT_SCRIPT"`) cannot see it if they ever need it.
**Why it happens:** Forgetting that `assemble-context.sh` is invoked via `bash "$CONTEXT_SCRIPT"` (separate process), not sourced.
**How to avoid:** Export `RALPH_SCRIPTS_DIR` after setting it. Currently the subprocesses do not need it (they are self-contained), but exporting is defensive and enables future scripts to use it.
**Warning signs:** Future scripts added to the `scripts/` directory fail to find siblings when invoked as subprocesses.

### Pitfall 5: Forgetting the _install_hook Path
**What goes wrong:** Updating lines 22-23 but missing line 346 inside `_install_hook()`.
**Why it happens:** The hook script path is set inside a function, not at the top of the file with the other path assignments.
**How to avoid:** Search for ALL occurrences of `$PROJECT_ROOT/scripts/` in the file (grep confirms exactly 3). Fix all three.
**Warning signs:** Hook installation points to wrong path in installed repos; `ralph-hook.sh` not found during autopilot execution.

## Code Examples

### Complete RALPH_SCRIPTS_DIR Implementation (proposed for ralph-launcher.sh)

Replace the current lines 19-23:
```bash
# --- File paths ---
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
STATE_FILE="$PROJECT_ROOT/.planning/STATE.md"
CONTEXT_SCRIPT="$PROJECT_ROOT/scripts/assemble-context.sh"
VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate-config.sh"
```

With:
```bash
# --- Resolve scripts directory (location-independent) ---
if [ -z "${RALPH_SCRIPTS_DIR:-}" ]; then
    _RALPH_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
    while [ -L "$_RALPH_SCRIPT_SOURCE" ]; do
        _RALPH_SCRIPT_DIR="$(cd "$(dirname "$_RALPH_SCRIPT_SOURCE")" && pwd)"
        _RALPH_SCRIPT_SOURCE="$(readlink "$_RALPH_SCRIPT_SOURCE")"
        [[ "$_RALPH_SCRIPT_SOURCE" != /* ]] && _RALPH_SCRIPT_SOURCE="$_RALPH_SCRIPT_DIR/$_RALPH_SCRIPT_SOURCE"
    done
    RALPH_SCRIPTS_DIR="$(cd "$(dirname "$_RALPH_SCRIPT_SOURCE")" && pwd)"
fi
export RALPH_SCRIPTS_DIR

# --- File paths ---
CONFIG_FILE="$PROJECT_ROOT/.planning/config.json"
STATE_FILE="$PROJECT_ROOT/.planning/STATE.md"
CONTEXT_SCRIPT="$RALPH_SCRIPTS_DIR/assemble-context.sh"
VALIDATE_SCRIPT="$RALPH_SCRIPTS_DIR/validate-config.sh"
```

And in `_install_hook()` (line 346), replace:
```bash
local hook_script="$PROJECT_ROOT/scripts/ralph-hook.sh"
```
With:
```bash
local hook_script="$RALPH_SCRIPTS_DIR/ralph-hook.sh"
```

### Test for RALPH_SCRIPTS_DIR Override (new test)
```bash
@test "RALPH_SCRIPTS_DIR override causes scripts to load from custom path" {
    # Create custom scripts directory
    mkdir -p "$TEST_TEMP_DIR/custom-scripts"
    cp "$REAL_PROJECT_ROOT/scripts/validate-config.sh" "$TEST_TEMP_DIR/custom-scripts/"
    cp "$REAL_PROJECT_ROOT/scripts/assemble-context.sh" "$TEST_TEMP_DIR/custom-scripts/"
    cp "$REAL_PROJECT_ROOT/scripts/ralph-hook.sh" "$TEST_TEMP_DIR/custom-scripts/"

    # Set override before sourcing
    export RALPH_SCRIPTS_DIR="$TEST_TEMP_DIR/custom-scripts"
    source "$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh"

    # Verify paths resolve to custom location
    [ "$CONTEXT_SCRIPT" = "$TEST_TEMP_DIR/custom-scripts/assemble-context.sh" ]
    [ "$VALIDATE_SCRIPT" = "$TEST_TEMP_DIR/custom-scripts/validate-config.sh" ]
}
```

### Test for Auto-Detection (new test)
```bash
@test "RALPH_SCRIPTS_DIR auto-detects from BASH_SOURCE when not set" {
    unset RALPH_SCRIPTS_DIR
    source "$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh"

    # Should auto-detect to the real scripts directory
    [ "$RALPH_SCRIPTS_DIR" = "$REAL_PROJECT_ROOT/scripts" ]
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `$PROJECT_ROOT/scripts/` hardcoded | `$RALPH_SCRIPTS_DIR` with auto-detect | Phase 14 (this phase) | Enables scripts to work from any directory |
| v1.x standalone CLI | v2.0 GSD integration layer | v2.0 (March 2026) | 92% code reduction; `lib/` already location-independent via `$GSD_RALPH_HOME` |

**Already location-independent (no changes needed):**
- `bin/gsd-ralph` -- uses `$GSD_RALPH_HOME` derived from `BASH_SOURCE`
- All `lib/` files -- sourced via `$GSD_RALPH_HOME/lib/...`
- All `templates/` -- referenced via `$GSD_RALPH_HOME/templates/...`

**Deprecated (cosmetic strings only, no functional paths):**
- `scripts/ralph-execute.sh` -- `./scripts/ralph-worktrees.sh` in execution line; DEPRECATED header
- `scripts/ralph-merge.sh` -- `./scripts/` in echo output
- `scripts/ralph-cleanup.sh` -- DEPRECATED header
- `scripts/ralph-status.sh` -- `./scripts/` in usage comment
- `scripts/ralph-worktrees.sh` -- `./scripts/` in echo output

## Open Questions

1. **Should deprecated legacy scripts also get RALPH_SCRIPTS_DIR?**
   - What we know: They are marked DEPRECATED and their `./scripts/` references are in display strings (echo output suggesting commands to run), not functional sourcing.
   - What's unclear: Whether Phase 15 installer will copy them at all.
   - Recommendation: Do NOT refactor deprecated scripts. They are out of scope for PORT-01/PORT-02. Phase 15 will determine which files to install. If legacy scripts are excluded from install, no work needed. If included, their display strings can be updated in Phase 15 when the install layout is known.

2. **Should tests be modified to explicitly test the installed layout (`scripts/ralph/`)?**
   - What we know: PORT-03 says existing 315 tests must pass "without modification." New tests for PORT-01 and PORT-04 (RALPH_SCRIPTS_DIR override) are additions.
   - What's unclear: Whether the planner should include tests that simulate the installed layout.
   - Recommendation: Add 2-3 new tests proving the override mechanism works (see Code Examples above). The 315 existing tests prove backward compatibility. A full installed-layout test belongs in Phase 16 (End-to-End Validation).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bats 1.x (vendored at tests/bats/) |
| Config file | None (bats uses convention, no config file) |
| Quick run command | `./tests/bats/bin/bats tests/ralph-launcher.bats` |
| Full suite command | `./tests/bats/bin/bats tests/*.bats` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| PORT-01 | Scripts work from both `scripts/` and `scripts/ralph/` | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "auto-detects"` | No -- Wave 0 |
| PORT-02 | All references use RALPH_SCRIPTS_DIR | unit | `./tests/bats/bin/bats tests/ralph-launcher.bats -f "RALPH_SCRIPTS_DIR"` | No -- Wave 0 |
| PORT-03 | All 315 existing tests pass without modification | regression | `./tests/bats/bin/bats tests/*.bats` | Yes (existing) |

### Sampling Rate
- **Per task commit:** `./tests/bats/bin/bats tests/ralph-launcher.bats tests/ralph-permissions.bats tests/ralph-hook.bats`
- **Per wave merge:** `./tests/bats/bin/bats tests/*.bats`
- **Phase gate:** Full suite green (315+ tests) before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] New tests for `RALPH_SCRIPTS_DIR` override behavior (in `tests/ralph-launcher.bats`)
- [ ] New tests for `RALPH_SCRIPTS_DIR` auto-detection (in `tests/ralph-launcher.bats`)
- [ ] New test for hook script path using `RALPH_SCRIPTS_DIR` (in `tests/ralph-launcher.bats`)

## Scope Sizing

This is a **small, surgical refactor**:

| What | Count | Complexity |
|------|-------|-----------|
| Files to modify | 1 (ralph-launcher.sh) | LOW -- 3 path references + ~10 lines of auto-detection |
| Files to add | 0 | N/A |
| Test files to modify | 1 (ralph-launcher.bats -- add new tests) | LOW -- 3-5 new test cases |
| Lines of new code | ~15 (auto-detection block) | LOW -- copied pattern from bin/gsd-ralph |
| Lines of changed code | 3 (path reference swaps) | LOW -- variable substitution |
| Risk areas | Test compatibility (Pitfall 2) | LOW -- tests override variables post-source |

**Estimated plan count:** 1 plan (single wave, sequential execution)

## Sources

### Primary (HIGH confidence)
- `scripts/ralph-launcher.sh` -- direct code inspection of hardcoded paths (lines 22, 23, 346)
- `bin/gsd-ralph` -- proven BASH_SOURCE self-detection pattern (lines 10-18)
- `tests/ralph-launcher.bats` -- test patterns showing variable override approach
- `tests/ralph-hook.bats` -- test patterns showing REAL_PROJECT_ROOT usage

### Secondary (MEDIUM confidence)
- Bash 3.2 reference manual -- `BASH_SOURCE` array behavior (confirmed: available in 3.2+)
- macOS system utilities -- `dirname`, `readlink`, `cd && pwd` all available on stock macOS

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- this is pure Bash, all tools already in use
- Architecture: HIGH -- pattern copied from existing working code (bin/gsd-ralph)
- Pitfalls: HIGH -- identified through direct code and test inspection
- Scope: HIGH -- grep confirmed exactly 3 functional path references to change

**Research date:** 2026-03-10
**Valid until:** Indefinite (Bash path resolution is stable; no external dependencies to version)
