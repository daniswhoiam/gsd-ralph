---
phase: 12-defense-in-depth-and-observability
verified: 2026-03-10T16:00:00Z
status: passed
score: 15/15 must-haves verified
re_verification: false
---

# Phase 12: Defense-in-Depth and Observability Verification Report

**Phase Goal:** The autopilot is hardened against runaway execution and provides real-time visibility into what is happening during autonomous runs
**Verified:** 2026-03-10T16:00:00Z
**Status:** passed
**Re-verification:** No -- initial verification

## Goal Achievement

### Observable Truths

#### Plan 12-01 Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Execution stops after configurable wall-clock timeout (default 30 minutes) | VERIFIED | `_check_circuit_breaker` at line 269 computes elapsed vs timeout_seconds, returns 1 on exceed. `run_loop` calls it at line 462 before each iteration. Default 30m at line 37. Config read at line 101. Tests 34-36 pass. |
| 2 | User can gracefully stop the loop by touching .ralph/.stop | VERIFIED | `_check_graceful_stop` at line 289 checks for file, removes it, returns 1. `run_loop` calls it at line 466. Tests 37-40 pass. |
| 3 | Terminal bell fires when circuit breaker or graceful stop triggers | VERIFIED | `printf '\a'` at lines 279 and 294. Tests 34-36, 37-40 verify behavior. |
| 4 | Each iteration prints a one-line progress summary with iteration number, per-iteration duration, total elapsed, STATE.md snapshot, and exit code | VERIFIED | Line 488: `"Ralph: Iter $iteration done ($(_format_duration $iter_duration)) | Total: $(_format_duration $total_duration) | $post_state | exit=$iter_exit"`. Test 44 passes. |
| 5 | Audit log is initialized (truncated) at the start of each run | VERIFIED | `_init_audit_log` at line 319 creates dir and truncates file. Called at line 456 in `run_loop`. Test 45 passes. |
| 6 | Post-run audit summary prints count of logged events (only if events exist) | VERIFIED | `_print_audit_summary` at line 327 checks `-s` (non-empty), counts lines, prints summary. Called via `_cleanup` trap. Tests 46-47 pass. |
| 7 | timeout_minutes config field is validated by validate-config.sh | VERIFIED | Lines 54-62 in validate-config.sh validate timeout_minutes. `known_keys` updated at line 65. Tests 71-72 pass. |
| 8 | User can run bin/ralph-stop as a convenience command to request graceful stop | VERIFIED | `bin/ralph-stop` exists, is executable (-rwxr-xr-x), touches `.ralph/.stop` and prints confirmation. |

#### Plan 12-02 Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 9 | AskUserQuestion tool calls are denied by the PreToolUse hook with a guidance message | VERIFIED | `scripts/ralph-hook.sh` line 17 checks tool_name, lines 28-34 output deny JSON with `permissionDecision: "deny"` and reason containing "blocked in autopilot mode". Tests 55-57 pass. |
| 10 | Non-AskUserQuestion tool calls are allowed through (hook exits silently) | VERIFIED | Line 39: `exit 0` with no output for non-matching tools. Tests 58-59 pass. |
| 11 | Denied AskUserQuestion calls are logged to .ralph/audit.log with timestamp and question text | VERIFIED | Lines 20-25 in ralph-hook.sh: extracts question, timestamps, appends to RALPH_AUDIT_FILE. Tests 60-61 pass. |
| 12 | Hook is automatically installed into .claude/settings.local.json before the first iteration | VERIFIED | `_install_hook` at line 338 merges hook config via jq. Called at line 457 before `while true`. Tests 48-50 pass. |
| 13 | Hook is automatically removed from .claude/settings.local.json on exit (including Ctrl+C) | VERIFIED | `_remove_hook` at line 365 removes ralph-hook entries via jq. `_cleanup` at line 380 calls `_remove_hook`. `trap _cleanup EXIT INT TERM` at line 458. Tests 51-54 pass. |
| 14 | Existing settings.local.json content is preserved during install and removal | VERIFIED | `_install_hook` reads existing content and merges. `_remove_hook` uses selective jq filter. Tests 49, 52 explicitly test preservation. |
| 15 | REQUIREMENTS.md traceability updated: OBSV-03 deferred, all Phase 12 requirements marked complete | VERIFIED | REQUIREMENTS.md shows SAFE-03, SAFE-04, OBSV-04 marked `[x]` Complete; OBSV-03 marked `[x]` with deferred note. Traceability table complete. Coverage: 16/16 complete. |

**Score:** 15/15 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `scripts/ralph-launcher.sh` | _check_circuit_breaker, _check_graceful_stop, _format_duration, _init_audit_log, _print_audit_summary, _install_hook, _remove_hook, _cleanup functions; run_loop updated | VERIFIED | 580 lines, all 8 new functions present, run_loop integrates all features |
| `scripts/ralph-hook.sh` | PreToolUse hook denying AskUserQuestion with guidance and audit logging | VERIFIED | 40 lines, executable, deny JSON output, audit logging, allow-through for other tools |
| `scripts/validate-config.sh` | timeout_minutes validation in validate_ralph_config | VERIFIED | Lines 54-65: timeout_minutes validation and known_keys update |
| `bin/ralph-stop` | Convenience command to touch .ralph/.stop | VERIFIED | 8 lines, executable, touches sentinel file, prints confirmation |
| `tests/ralph-launcher.bats` | Tests for circuit breaker, graceful stop, progress display, audit init/summary, hook install/remove | VERIFIED | 54 tests total (33 Phase 11 + 16 Plan 12-01 + 7 Plan 12-02), all passing |
| `tests/ralph-hook.bats` | Tests for hook deny/allow/audit behaviors | VERIFIED | 7 tests covering deny, allow, and audit behaviors, all passing |
| `tests/ralph-config.bats` | Tests for timeout_minutes validation | VERIFIED | 11 tests total (9 existing + 2 Phase 12), all passing |
| `tests/test_helper/ralph-helpers.bash` | create_mock_stop_file, create_mock_audit_log, create_mock_settings_local helpers | VERIFIED | All 3 helpers present at lines 135, 143, 156 |
| `.planning/config.json` | timeout_minutes: 30 in ralph key | VERIFIED | `"timeout_minutes": 30` present in ralph config object |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `ralph-launcher.sh:run_loop` | `_check_circuit_breaker` | function call at top of while loop | WIRED | Line 462: `if ! _check_circuit_breaker "$TIMEOUT_MINUTES" "$loop_start_epoch"` |
| `ralph-launcher.sh:run_loop` | `_check_graceful_stop` | function call at top of while loop | WIRED | Line 466: `if ! _check_graceful_stop "$STOP_FILE"` |
| `ralph-launcher.sh:run_loop` | `_format_duration` | function call after execute_iteration | WIRED | Line 488: used in progress display string |
| `validate-config.sh` | `.planning/config.json` | jq validation of timeout_minutes | WIRED | Line 56: `jq -r '.ralph.timeout_minutes // "MISSING"'` |
| `ralph-launcher.sh:run_loop` | `_install_hook` | function call before while loop | WIRED | Line 457: `_install_hook` |
| `ralph-launcher.sh:_install_hook` | `.claude/settings.local.json` | jq merge writing hook config | WIRED | Lines 339-360: reads/merges/writes settings file |
| `ralph-hook.sh` | `.ralph/audit.log` | echo append on AskUserQuestion denial | WIRED | Line 25: `echo "..." >> "$AUDIT_LOG"` |
| `ralph-launcher.sh:_cleanup` | `_remove_hook` | trap EXIT INT TERM | WIRED | Line 458: `trap _cleanup EXIT INT TERM`; Line 381: `_cleanup` calls `_remove_hook` |

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| SAFE-03 | 12-01 | Circuit breaker with wall-clock timeout and graceful stop mechanism | SATISFIED | `_check_circuit_breaker` with configurable timeout, `_check_graceful_stop` with sentinel file, `bin/ralph-stop` convenience command |
| SAFE-04 | 12-02 | PreToolUse hook blocks AskUserQuestion as defense-in-depth | SATISFIED | `scripts/ralph-hook.sh` denies AskUserQuestion with guidance, auto-installed/removed by launcher |
| OBSV-03 | 12-01 | Real-time progress display (deferred to v2.1; per-iteration summary satisfies v2.0) | SATISFIED | Per-iteration progress line with iteration count, duration, state snapshot, exit code. REQUIREMENTS.md notes deferral with rationale. |
| OBSV-04 | 12-01, 12-02 | Auto-approved decisions logged to audit file for post-run review | SATISFIED | Audit log lifecycle in launcher (_init_audit_log, _print_audit_summary), hook writes denied questions to audit file with timestamps |

**No orphaned requirements found.** All 4 requirement IDs from plans (SAFE-03, SAFE-04, OBSV-03, OBSV-04) are accounted for in REQUIREMENTS.md traceability table as Phase 12 with Status: Complete.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| - | - | None found | - | - |

No TODOs, FIXMEs, placeholders, stub returns, or console-only implementations detected in any Phase 12 artifacts.

### Human Verification Required

### 1. Circuit Breaker Real-Time Behavior

**Test:** Run `ralph-launcher.sh execute-phase N` with `timeout_minutes: 1` in config.json and observe that it terminates after 1 minute.
**Expected:** Loop exits with "Circuit breaker: wall-clock timeout (1m) exceeded" message and terminal bell.
**Why human:** Real wall-clock timing behavior cannot be fully verified in unit tests without actual clock passage.

### 2. Graceful Stop During Live Run

**Test:** Start a ralph-launcher.sh execution, then run `bin/ralph-stop` from another terminal.
**Expected:** Current iteration completes, then loop exits with "Graceful stop" message and terminal bell. The .ralph/.stop file is removed.
**Why human:** Requires concurrent process interaction that cannot be tested in bats unit tests.

### 3. Hook Integration with Live Claude Code

**Test:** Run ralph-launcher.sh with a real Claude Code instance and verify that AskUserQuestion is actually blocked by the hook.
**Expected:** If Claude attempts AskUserQuestion, it receives the deny response with guidance message. The attempt is logged in .ralph/audit.log.
**Why human:** Requires actual Claude Code runtime to verify hook is correctly invoked by Claude's PreToolUse mechanism.

### 4. settings.local.json Preservation in Real Environment

**Test:** Verify that existing `.claude/settings.local.json` permissions and other settings survive a full install/remove cycle during a live run.
**Expected:** After ralph-launcher.sh exits, settings.local.json has all original content restored with no ralph hook entries remaining.
**Why human:** Real settings.local.json may have complex nested structures not covered by test mocks.

### Gaps Summary

No gaps found. All 15 observable truths verified. All 9 artifacts pass three-level verification (exists, substantive, wired). All 8 key links wired. All 4 requirements satisfied. 72/72 tests pass with zero regressions. No anti-patterns detected.

---

_Verified: 2026-03-10T16:00:00Z_
_Verifier: Claude (gsd-verifier)_
