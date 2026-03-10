---
phase: 11-shell-launcher-and-headless-invocation
verified: 2026-03-10T12:15:00Z
status: passed
score: 13/13 must-haves verified
must_haves:
  truths:
    - "User can invoke /gsd:ralph execute-phase 11 and it triggers the launcher script"
    - "Running --dry-run shows the exact claude -p command without executing it"
    - "Default tier produces --allowedTools with the hardcoded whitelist"
    - "Auto-mode tier produces --permission-mode auto"
    - "Yolo tier produces --dangerously-skip-permissions"
    - "Every command includes --worktree flag"
    - "Every command includes --max-turns from config (default 50)"
    - "System loops fresh claude -p instances until STATE.md shows phase complete"
    - "System detects iteration success from exit code 0 and failure from non-zero"
    - "System retries once on failure, then stops the failing step"
    - "System distinguishes max-turns exhaustion (progress made) from genuine failure (no progress)"
    - "Terminal bell sounds on loop completion or unrecoverable failure"
    - "Context is reassembled fresh before each iteration (never stale)"
  artifacts:
    - path: ".claude/commands/gsd/ralph.md"
      provides: "GSD command entry point for /gsd:ralph"
    - path: "scripts/ralph-launcher.sh"
      provides: "Complete launcher with all 9 functions (420 LOC)"
    - path: "tests/ralph-launcher.bats"
      provides: "33 tests for launcher core + loop engine"
    - path: "tests/ralph-permissions.bats"
      provides: "4 tests for permission tier flag mapping"
    - path: "tests/test_helper/ralph-helpers.bash"
      provides: "Test helpers for config, state, mocks"
  key_links:
    - from: ".claude/commands/gsd/ralph.md"
      to: "scripts/ralph-launcher.sh"
      via: "bash invocation"
    - from: "scripts/ralph-launcher.sh"
      to: "scripts/validate-config.sh"
      via: "source via VALIDATE_SCRIPT variable"
    - from: "scripts/ralph-launcher.sh"
      to: "scripts/assemble-context.sh"
      via: "bash invocation via CONTEXT_SCRIPT variable"
    - from: "scripts/ralph-launcher.sh"
      to: "claude -p"
      via: "env -u CLAUDECODE in build_claude_command"
---

# Phase 11: Shell Launcher and Headless Invocation Verification Report

**Phase Goal:** User can add `--ralph` to any GSD command and get autonomous execution with permission control, worktree isolation, and loop-based completion
**Verified:** 2026-03-10T12:15:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | User can invoke /gsd:ralph execute-phase 11 and it triggers the launcher script | VERIFIED | `.claude/commands/gsd/ralph.md` references `$ARGUMENTS`, calls `bash scripts/ralph-launcher.sh $ARGUMENTS` |
| 2 | Running --dry-run shows the exact claude -p command without executing it | VERIFIED | `dry_run_output()` at line 167 prints header, command, config summary. Tests #17-18 pass. Main guard checks `DRY_RUN=true` at line 409. |
| 3 | Default tier produces --allowedTools with the hardcoded whitelist | VERIFIED | `build_permission_flags()` case `default` at line 101. Test #34 passes. Whitelist includes Write,Read,Edit,Grep,Glob,Bash(*). |
| 4 | Auto-mode tier produces --permission-mode auto | VERIFIED | Case `auto-mode` at line 105. Test #35 passes. |
| 5 | Yolo tier produces --dangerously-skip-permissions | VERIFIED | Case `yolo` at line 108. Test #36 passes. |
| 6 | Every command includes --worktree flag | VERIFIED | `build_claude_command()` line 159 always appends `--worktree`. Test #11 passes. |
| 7 | Every command includes --max-turns from config (default 50) | VERIFIED | `build_claude_command()` line 157-158 uses `max_turns` arg. `DEFAULT_MAX_TURNS=50` at line 27. Test #12 passes. |
| 8 | System loops fresh claude -p instances until STATE.md shows phase complete | VERIFIED | `run_loop()` at line 300 with `while true` + `check_state_completion` break condition. Tests #27, #29 pass. |
| 9 | System detects iteration success from exit code 0 and failure from non-zero | VERIFIED | Lines 343-347 check `iter_exit -eq 0`, lines 350-368 handle non-zero. Tests #26, #28-30 pass. |
| 10 | System retries once on failure, then stops the failing step | VERIFIED | `consecutive_no_progress` counter at lines 361-368, threshold at 2. Tests #28, #30 show exactly 2 iterations before stop. |
| 11 | System distinguishes max-turns exhaustion from genuine failure | VERIFIED | State snapshot comparison at lines 352-358: if `pre_snapshot != post_snapshot`, continue (not retry). Test #29 passes (non-zero exit + progress = continue). |
| 12 | Terminal bell sounds on loop completion or unrecoverable failure | VERIFIED | `printf '\a'` at lines 338 (success) and 365 (failure). Tests #31, #32 pass. |
| 13 | Context is reassembled fresh before each iteration (never stale) | VERIFIED | `execute_iteration()` creates fresh temp context via `mktemp` at line 263, calls `assemble-context.sh` at line 267. Test #33 verifies >= 2 assemble calls. |

**Score:** 13/13 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `.claude/commands/gsd/ralph.md` | GSD command entry point with $ARGUMENTS and ralph-launcher.sh reference | VERIFIED | 58 lines, correct frontmatter (name, description, argument-hint, allowed-tools), references $ARGUMENTS, delegates to launcher |
| `scripts/ralph-launcher.sh` | Complete launcher >= 180 LOC with 9 functions | VERIFIED | 420 LOC. All 9 functions: parse_args, read_config, build_permission_flags, build_prompt, build_claude_command, dry_run_output, check_state_completion, execute_iteration, run_loop (+ internal _capture_state_snapshot). Guarded main with BASH_SOURCE[0] check. |
| `tests/ralph-launcher.bats` | Tests for core + loop, >= 100 lines | VERIFIED | 588 lines, 33 @test blocks covering arg parsing, config, prompt, command building, dry-run, completion detection, iteration execution, retry, progress, bell, fresh context |
| `tests/ralph-permissions.bats` | Tests for permission tiers, >= 30 lines | VERIFIED | 61 lines, 4 @test blocks covering default/auto-mode/yolo/invalid tiers |
| `tests/test_helper/ralph-helpers.bash` | Shared test helpers | VERIFIED | 131 lines. Includes: get_real_project_root, create_ralph_config, create_ralph_config_raw, create_mock_state, create_mock_claude_command, create_context_file, create_mock_state_advanced, create_mock_assemble_context |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `.claude/commands/gsd/ralph.md` | `scripts/ralph-launcher.sh` | bash invocation | WIRED | Line 35: `bash scripts/ralph-launcher.sh $ARGUMENTS` |
| `scripts/ralph-launcher.sh` | `scripts/validate-config.sh` | source via variable | WIRED | Line 23: `VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate-config.sh"`, Line 38: `source "$VALIDATE_SCRIPT"`. Dependency exists (76 LOC, Phase 10). |
| `scripts/ralph-launcher.sh` | `scripts/assemble-context.sh` | bash invocation | WIRED | Line 22: `CONTEXT_SCRIPT="$PROJECT_ROOT/scripts/assemble-context.sh"`, Line 267: `bash "$CONTEXT_SCRIPT" "$context_file"`. Dependency exists (2093 bytes, Phase 10). |
| `scripts/ralph-launcher.sh` | `claude -p` | env -u CLAUDECODE | WIRED | Line 155: `env -u CLAUDECODE claude -p`. Line 283: `bash -c "$cmd"` executes the built command. |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| AUTO-01 | 11-01 | User can add `--ralph` to any GSD command to run it autonomously | SATISFIED | `/gsd:ralph` command file delegates to launcher; launcher accepts any GSD command string |
| AUTO-02 | 11-02 | System loops fresh Claude Code instances, each picking up incomplete work from GSD state on disk | SATISFIED | `run_loop()` iterates `execute_iteration()` calls until STATE.md completion; fresh context each iteration |
| AUTO-05 | 11-01 | User can run `--dry-run` to preview the command without executing | SATISFIED | `dry_run_output()` prints complete command and config summary. Main guard short-circuits on DRY_RUN=true |
| PERM-01 | 11-01 | Default mode uses `--allowedTools` with a scoped tool whitelist | SATISFIED | `build_permission_flags()` default case outputs `--allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)"` |
| PERM-02 | 11-01 | User can opt into `--auto-mode` for Claude's risk-based auto-approval | SATISFIED | `build_permission_flags()` auto-mode case outputs `--permission-mode auto` |
| PERM-03 | 11-01 | User can opt into `--yolo` for `--dangerously-skip-permissions` full bypass | SATISFIED | `build_permission_flags()` yolo case outputs `--dangerously-skip-permissions` |
| SAFE-01 | 11-01 | Each iteration runs in an isolated worktree via `--worktree` | SATISFIED | `build_claude_command()` always appends `--worktree` flag (line 159) |
| SAFE-02 | 11-01 | System enforces `--max-turns` ceiling per iteration | SATISFIED | `build_claude_command()` always includes `--max-turns N` (line 157-158); default 50, configurable via config.json |
| OBSV-01 | 11-02 | System detects iteration completion/failure from exit code and output | SATISFIED | `run_loop()` captures exit code from `execute_iteration()`, routes to success/progress/retry/failure paths |
| OBSV-02 | 11-02 | Terminal bell on loop completion or failure | SATISFIED | `printf '\a'` on both success (line 338) and unrecoverable failure (line 365) |

**All 10 Phase 11 requirements satisfied. No orphaned requirements found.**

Cross-check: REQUIREMENTS.md maps exactly AUTO-01, AUTO-02, AUTO-05, PERM-01, PERM-02, PERM-03, SAFE-01, SAFE-02, OBSV-01, OBSV-02 to Phase 11. All 10 accounted for in plans (Plan 01: AUTO-01, AUTO-05, PERM-01-03, SAFE-01-02; Plan 02: AUTO-02, OBSV-01-02).

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| -- | -- | No TODO/FIXME/PLACEHOLDER found | -- | -- |
| -- | -- | No placeholder content found | -- | -- |
| -- | -- | No empty implementations found | -- | -- |

No anti-patterns detected. Clean implementation across all Phase 11 files.

### Test Results

- **Phase 11 tests:** 37/37 pass (33 ralph-launcher.bats + 4 ralph-permissions.bats)
- **Full suite:** 280/280 pass (no regressions)
- **Documented commits:** 5/5 verified (8883d35, 060fbbc, 2837612, e7be66e, e3f7ada)

### Human Verification Required

#### 1. Headless Worktree Lifecycle

**Test:** Run `bash scripts/ralph-launcher.sh execute-phase 11` on a test project with a real Claude Code installation.
**Expected:** Claude Code creates an isolated worktree, executes the GSD command, and cleans up the worktree after completion.
**Why human:** `--worktree` behavior depends on Claude Code runtime. Tests mock the `claude` command; cannot verify real worktree creation/cleanup programmatically.

#### 2. SKILL.md Auto-Loading in Headless Mode

**Test:** Execute a real headless iteration and verify that SKILL.md autonomous behavior rules (no AskUserQuestion, auto-approve checkpoints) are active.
**Expected:** The headless Claude instance follows SKILL.md directives without prompting the user.
**Why human:** Requires a live `claude -p` invocation to confirm SKILL.md is loaded via `--append-system-prompt-file` context assembly.

#### 3. End-to-End Loop Completion

**Test:** Run `bash scripts/ralph-launcher.sh execute-phase N` on a real project where work is already partially complete.
**Expected:** The system loops multiple iterations, detects STATE.md advancement, and emits a terminal bell when done.
**Why human:** Full loop behavior with real Claude Code instances, STATE.md progression, and multi-iteration completion cannot be simulated in unit tests.

### Gaps Summary

No gaps found. All 13 observable truths verified with concrete code evidence. All 10 requirements satisfied. All 5 artifacts substantive and wired. All 4 key links connected. All 37 tests pass. Full suite of 280 tests shows no regressions. No anti-patterns detected.

---

_Verified: 2026-03-10T12:15:00Z_
_Verifier: Claude (gsd-verifier)_
