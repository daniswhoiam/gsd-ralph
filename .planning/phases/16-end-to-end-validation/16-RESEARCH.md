# Phase 16: End-to-End Validation - Research

**Researched:** 2026-03-10
**Domain:** Bats integration testing for Bash installer workflows
**Confidence:** HIGH

## Summary

Phase 16 is a verification phase -- it does not introduce new features. Its purpose is to prove the complete install-then-use workflow works end-to-end in realistic target repo scenarios. The existing test infrastructure (Bats 1.x vendored at `tests/bats/`, with bats-assert, bats-support, and bats-file helpers) is fully adequate. The existing `tests/installer.bats` (32 tests, 593 lines) already validates individual INST requirements at the unit/integration level. Phase 16 adds **higher-level scenario tests** that chain operations together: create a realistic target repo, run the full installer, then exercise the installed artifacts.

The project already has well-established patterns for test isolation (mktemp directories), test helpers (`common.bash`, `ralph-helpers.bash`), and GSD structure creation. Phase 16 needs a new test file (`tests/e2e-install.bats`) that uses these existing patterns to run multi-step workflow scenarios. The key technical challenge is simulating the "install-then-dry-run" scenario without requiring a live Claude Code environment -- the dry-run output from `ralph-launcher.sh` is the testable proxy.

**Primary recommendation:** Create a single `tests/e2e-install.bats` file with scenario-driven tests covering the four success criteria. Reuse existing test helpers; add minimal new helpers only for creating "existing .claude/ config" scenarios.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| (verification) | Test suite covers fresh GSD project, project with existing `.claude/` config, and non-GSD repo (error path) | Three distinct setup scenarios using existing `create_test_repo`, `create_gsd_structure`, and `create_ralph_config` helpers |
| (verification) | Install-then-dry-run test confirms `/gsd:ralph execute-phase` works in an installed repo | Chain `bash install.sh` then `bash scripts/ralph/ralph-launcher.sh execute-phase 1 --dry-run` in the temp dir |
| (verification) | Re-install idempotency test confirms no file changes on second run | Timestamp comparison pattern already proven in `installer.bats` tests 13-15 |
| (verification) | All tests run in isolated temporary directories (no side effects on dev repo) | Existing `_common_setup` creates `mktemp -d` with `_common_teardown` cleanup |
</phase_requirements>

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bats | 1.x (vendored at `tests/bats/`) | Test runner for Bash scripts | Already used across all 351 tests in this project |
| bats-assert | vendored at `tests/test_helper/bats-assert/` | Assertion helpers (assert_success, assert_failure, assert_output) | Standard companion to Bats |
| bats-support | vendored at `tests/test_helper/bats-support/` | Test output formatting | Standard companion to Bats |
| bats-file | vendored at `tests/test_helper/bats-file/` | File existence and permission assertions | Standard companion to Bats |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| jq | system | JSON manipulation in config merge verification | Already a prerequisite (INST-03) |
| cmp | POSIX | Byte-for-byte file comparison for idempotency | Already used in installer.bats |

### Alternatives Considered

None -- the testing stack is already established and no changes are needed for Phase 16.

**Installation:** No new dependencies. Everything is vendored.

## Architecture Patterns

### Recommended Test File Structure

```
tests/
  e2e-install.bats          # NEW: End-to-end install workflow scenarios
  installer.bats             # EXISTING: Unit/integration tests for installer functions
  test_helper/
    common.bash              # EXISTING: Shared setup/teardown
    ralph-helpers.bash       # EXISTING: Ralph-specific test fixtures
```

### Pattern 1: Scenario-Based Test Organization

**What:** Group tests by real-world scenario, not by code unit. Each scenario is a complete workflow with setup, action, and multi-assertion verification.
**When to use:** Integration/E2E tests where the value is in testing the chain of operations.
**Example:**

```bash
# Source: existing project patterns (installer.bats, ralph-launcher.bats)

# Scenario: Fresh GSD project install
@test "e2e: fresh GSD project -- install succeeds and all artifacts exist" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo","parallelization":true}'
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    # Verify complete artifact set
    assert [ -d "scripts/ralph" ]
    assert [ -f ".claude/commands/gsd/ralph.md" ]
    assert [ -f ".claude/skills/gsd-ralph-autopilot/SKILL.md" ]
    run jq -e '.ralph' .planning/config.json
    assert_success
}
```

### Pattern 2: Install-then-Execute Chaining

**What:** Run the installer, then execute the installed artifacts in the same temp directory to prove the install produced a working setup.
**When to use:** The "install-then-dry-run" success criterion.
**Example:**

```bash
# Source: ralph-launcher.sh dry_run_output() at line 196-218

@test "e2e: installed ralph-launcher.sh produces valid dry-run output" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo"}'
    cd "$TEST_TEMP_DIR"

    # Step 1: Install
    bash "$INSTALLER"

    # Step 2: Create minimal phase structure for dry-run
    mkdir -p .planning/phases/1-test-phase
    cat > .planning/phases/1-test-phase/1-01-PLAN.md <<'EOF'
    ---
    phase: 1
    plan: 1
    ---
    # Test Plan
    EOF

    # Step 3: Run the INSTALLED launcher (not the source one)
    run bash scripts/ralph/ralph-launcher.sh execute-phase 1 --dry-run
    assert_success
    assert_output --partial "Ralph Dry Run"
    assert_output --partial "max_turns"
}
```

### Pattern 3: Timestamp-Based Idempotency Verification

**What:** Record file modification times before re-install, sleep 1 second, re-install, verify timestamps unchanged.
**When to use:** Proving no-op behavior on second run.
**Example:**

```bash
# Source: installer.bats test "re-run when files match skips all copies"

@test "e2e: full re-install produces zero file changes" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo"}'
    cd "$TEST_TEMP_DIR"

    bash "$INSTALLER"

    # Record all timestamps
    local ts_launcher ts_context ts_validate ts_hook ts_cmd ts_skill
    ts_launcher=$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")
    # ... more timestamps ...

    sleep 1
    run bash "$INSTALLER"
    assert_success

    # ALL timestamps must be unchanged
    assert_equal "$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")" "$ts_launcher"
    # ... more comparisons ...
}
```

### Pattern 4: Pre-existing .claude/ Directory Handling

**What:** Create a target repo that already has .claude/settings.local.json and/or other .claude/ files to verify the installer does not clobber them.
**When to use:** Testing the "project with existing .claude/ config" scenario.
**Example:**

```bash
@test "e2e: existing .claude/ files preserved during install" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo"}'
    cd "$TEST_TEMP_DIR"

    # Pre-existing .claude/ content
    mkdir -p .claude
    echo '{"permissions":{"allow":["Read"]}}' > .claude/settings.local.json
    mkdir -p .claude/commands
    echo "# existing command" > .claude/commands/existing.md

    run bash "$INSTALLER"
    assert_success

    # Pre-existing files must survive
    assert [ -f ".claude/settings.local.json" ]
    assert [ -f ".claude/commands/existing.md" ]
    run cat .claude/settings.local.json
    assert_output --partial "Read"
}
```

### Anti-Patterns to Avoid

- **Testing against the dev repo:** All tests MUST use temp directories. Never run the installer in the gsd-ralph repo itself (the self-install guard catches this, but tests should not rely on it).
- **Testing implementation details:** E2E tests should verify observable outcomes (files exist, commands work, output correct), not internal function behavior (that is installer.bats territory).
- **Requiring live Claude Code:** The dry-run path is the testable proxy. Never attempt to invoke `claude -p` in tests.
- **Fragile output matching:** Use `assert_output --partial` not exact string matching. The installer may adjust formatting.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Temp dir isolation | Custom cleanup logic | `_common_setup` / `_common_teardown` from `common.bash` | Already handles mktemp creation and rm -rf cleanup reliably |
| GSD structure creation | Manual mkdir/echo commands | `create_test_repo`, `create_gsd_structure`, `create_ralph_config_raw` from helpers | Proven in 32 existing installer tests |
| Assertion library | Custom string comparison | bats-assert (`assert_success`, `assert_output --partial`, etc.) | Consistent with all other tests in project |
| File existence checks | `test -f` with manual error messages | bats-file (`assert_file_exists`) or Bats `assert [ -f ... ]` | Better error messages on failure |

**Key insight:** Phase 16 should introduce zero new testing infrastructure. The existing helpers are complete for the scenarios needed. At most, a helper to create "pre-existing .claude/ files" may be useful, and it belongs in `ralph-helpers.bash`.

## Common Pitfalls

### Pitfall 1: Path Resolution in Temp Dirs

**What goes wrong:** The installer uses `BASH_SOURCE[0]` to resolve `GSD_RALPH_REPO` (source repo root). When running from a temp dir, the installer must be invoked via an absolute path to the gsd-ralph repo's `install.sh`.
**Why it happens:** Tests that `cd` to temp dir and run a relative path to the installer would break path resolution.
**How to avoid:** Always use `$INSTALLER` which is set to `$REAL_PROJECT_ROOT/install.sh` (absolute path) in the setup function.
**Warning signs:** Tests fail with "file not found" errors when copying source scripts.

### Pitfall 2: Git Repo Requirement for Dry-Run

**What goes wrong:** `ralph-launcher.sh` uses `git rev-parse --show-toplevel` to detect PROJECT_ROOT. If the temp dir is not a git repo, this falls back to `pwd`. `assemble-context.sh` also requires STATE.md to exist.
**Why it happens:** The dry-run test chain needs a fully initialized test environment (git repo + GSD structure + STATE.md + phase plans).
**How to avoid:** Always call `create_test_repo` (which runs `git init`) before testing the installed launcher. Also create STATE.md with a parseable "Phase: N" line.
**Warning signs:** Dry-run output says "WARNING: Context script not found" or "STATE.md not found".

### Pitfall 3: macOS stat -f vs. Linux stat -c

**What goes wrong:** The timestamp comparison tests use `stat -f "%m"` which is macOS-specific. If someone runs tests on Linux, they would fail.
**Why it happens:** macOS uses BSD stat, Linux uses GNU stat.
**How to avoid:** This project explicitly targets macOS (Bash 3.2 compatibility constraint). The existing installer.bats already uses `stat -f "%m"` and this is acceptable. Maintain consistency.
**Warning signs:** stat errors about "illegal option" on non-macOS systems.

### Pitfall 4: Overlap with Existing installer.bats Tests

**What goes wrong:** E2E tests duplicate individual installer.bats assertions, creating maintenance burden without additional coverage.
**Why it happens:** Natural tendency to re-verify every artifact in every test.
**How to avoid:** E2E tests should verify the CHAIN works, not re-test individual operations. Focus on: "Did the full workflow succeed?" and "Does the installed artifact actually work?" Keep individual file checks in installer.bats.
**Warning signs:** E2E test file grows beyond 200 lines, mirrors installer.bats structure.

### Pitfall 5: assemble-context.sh Requires Specific STATE.md Format

**What goes wrong:** The dry-run chain fails at context assembly because STATE.md lacks the expected "Phase: N of M" line format.
**Why it happens:** `assemble-context.sh` uses `grep -oE 'Phase: [0-9]+'` to extract the phase number.
**How to avoid:** Use `create_mock_state_advanced` from ralph-helpers.bash which creates a properly formatted STATE.md, OR use `create_gsd_structure` which creates a minimal STATE.md. For dry-run tests, the STATE.md must have a phase number that matches an existing phase directory.
**Warning signs:** Dry-run output lacks "Active Phase Plans" section.

## Code Examples

Verified patterns from existing project codebase:

### E2E Test Setup Pattern (from installer.bats)

```bash
# Source: tests/installer.bats lines 1-15
setup() {
    load 'test_helper/common'
    load 'test_helper/ralph-helpers'
    _common_setup
    REAL_PROJECT_ROOT="$(get_real_project_root)"
    INSTALLER="$REAL_PROJECT_ROOT/install.sh"
}

teardown() {
    _common_teardown
}
```

### Full GSD Project Creation for Dry-Run Testing

```bash
# Source: tests/test_helper/common.bash + ralph-helpers.bash, combined pattern
# Creates a temp dir with git repo, GSD structure, config, and phase plans

create_full_gsd_project() {
    create_test_repo
    create_gsd_structure            # creates .planning/phases, ROADMAP.md, STATE.md
    create_ralph_config_raw '{"mode":"yolo","parallelization":true}'
    cd "$TEST_TEMP_DIR"

    # Create a phase directory with a plan (for dry-run context assembly)
    mkdir -p .planning/phases/1-test-phase
    cat > .planning/phases/1-test-phase/1-01-PLAN.md <<'PLAN'
---
phase: 1
plan: 1
---
# Test Plan
## Tasks
- Task 1: Example
PLAN
}
```

### Installed Launcher Invocation (Dry-Run)

```bash
# Source: scripts/ralph-launcher.sh lines 553-596 (main guard + dry-run path)
# The installed launcher at scripts/ralph/ralph-launcher.sh must:
# 1. Resolve RALPH_SCRIPTS_DIR to scripts/ralph/ via BASH_SOURCE
# 2. Find CONFIG_FILE at .planning/config.json
# 3. Source validate-config.sh from RALPH_SCRIPTS_DIR
# 4. Execute assemble-context.sh from RALPH_SCRIPTS_DIR
# 5. Produce dry-run output with command preview and config summary

# Test assertion pattern:
run bash scripts/ralph/ralph-launcher.sh execute-phase 1 --dry-run
assert_success
assert_output --partial "Ralph Dry Run"
assert_output --partial "execute-phase"
assert_output --partial "max_turns: 50"
assert_output --partial "permission_tier: default"
```

### Non-GSD Repo Error Path

```bash
# Source: install.sh lines 71-83 (check_prerequisites GSD detection)
# A directory without .planning/ should fail with a helpful error

@test "e2e: non-GSD repo (no .planning/) -- installer fails with guidance" {
    # create_test_repo gives us git but NOT GSD structure
    create_test_repo
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_failure
    assert_output --partial "GSD"
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| No installer tests | 32 unit/integration tests in installer.bats | Phase 15 (2026-03-10) | Phase 16 can focus on workflow chains, not unit coverage |
| Manual test repo setup | `create_test_repo` + `create_gsd_structure` helpers | Early project history | Consistent, reliable test isolation |

**Deprecated/outdated:**
- Nothing deprecated. Test patterns are stable and well-established.

## Open Questions

1. **How deep should dry-run validation go?**
   - What we know: The `--dry-run` flag produces structured output with command preview, config values, and context info. It exits 0 on success.
   - What's unclear: Should E2E tests verify the entire dry-run output structure, or just that it succeeds with key markers?
   - Recommendation: Verify success + key markers (`"Ralph Dry Run"`, `"max_turns"`, `"execute-phase"`). Do not match full output -- it would create fragile tests.

2. **Should E2E tests also verify that `assemble-context.sh` correctly reads plan files?**
   - What we know: `assemble-context.sh` reads STATE.md and phase plan files. It is already tested in `context-assembly.bats`.
   - What's unclear: Whether the E2E dry-run should also check context assembly output.
   - Recommendation: Verify `"Context lines:"` appears in dry-run output (meaning context was assembled). Do not deep-verify context contents -- that is context-assembly.bats territory.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Bats 1.x (vendored at tests/bats/) |
| Config file | None (bats uses convention) |
| Quick run command | `./tests/bats/bin/bats tests/e2e-install.bats` |
| Full suite command | `./tests/bats/bin/bats tests/*.bats` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| SC-1a | Fresh GSD project install succeeds | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "fresh GSD"` | No -- Wave 0 |
| SC-1b | Project with existing .claude/ config install succeeds | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "existing .claude"` | No -- Wave 0 |
| SC-1c | Non-GSD repo install fails with guidance | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "non-GSD"` | No -- Wave 0 |
| SC-2 | Install-then-dry-run produces valid output | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "dry-run"` | No -- Wave 0 |
| SC-3 | Re-install idempotency (no file changes) | e2e | `./tests/bats/bin/bats tests/e2e-install.bats -f "idempotent"` | No -- Wave 0 |
| SC-4 | Tests run in isolated temp dirs | structural | Verified by _common_setup pattern in all tests | Inherent |

### Sampling Rate

- **Per task commit:** `./tests/bats/bin/bats tests/e2e-install.bats`
- **Per wave merge:** `./tests/bats/bin/bats tests/*.bats`
- **Phase gate:** Full suite green (351 existing + new E2E tests, 0 failures)

### Wave 0 Gaps

- [ ] `tests/e2e-install.bats` -- covers SC-1 through SC-4 (the only new file needed)

No framework install needed. No new fixtures needed. No shared helpers needed beyond what exists.

## Sources

### Primary (HIGH confidence)

- Project codebase -- `install.sh` (273 lines), `tests/installer.bats` (593 lines, 32 tests), `tests/test_helper/common.bash`, `tests/test_helper/ralph-helpers.bash`
- Project codebase -- `scripts/ralph-launcher.sh` (600+ lines), `scripts/assemble-context.sh` (61 lines)
- Phase 15 verification report -- `15-VERIFICATION.md` confirming all 8 INST requirements satisfied
- Phase 15 validation strategy -- `15-VALIDATION.md` confirming test infrastructure and patterns

### Secondary (MEDIUM confidence)

- Bats documentation (vendored version matches project usage patterns)

### Tertiary (LOW confidence)

- None

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - no changes to existing stack; all tools vendored and proven across 351 tests
- Architecture: HIGH - follows established project patterns exactly; no new infrastructure
- Pitfalls: HIGH - identified from direct code reading of install.sh and ralph-launcher.sh

**Research date:** 2026-03-10
**Valid until:** Indefinitely (verification phase of stable codebase; no external dependencies)
