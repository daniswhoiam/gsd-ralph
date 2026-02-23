---
phase: 09-cli-guidance
verified: 2026-02-23T12:00:00Z
status: passed
score: 22/22 must-haves verified
re_verification: false
---

# Phase 9: CLI Guidance Verification Report

**Phase Goal:** Every command tells the user what to do next
**Verified:** 2026-02-23T12:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (Plan 09-01)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | After gsd-ralph init succeeds, output contains a Next: line suggesting the next command | VERIFIED | `lib/commands/init.sh:101` — `print_guidance "Review .ralphrc, then run: gsd-ralph execute <phase>"` |
| 2 | After gsd-ralph init finds existing .ralph/, output contains a Next: line about reinitializing | VERIFIED | `lib/commands/init.sh:47` — `print_guidance "To reinitialize: gsd-ralph init --force"` |
| 3 | After gsd-ralph execute N completes (success or dry-run), output contains a context-appropriate Next: line | VERIFIED | `lib/commands/execute.sh:156` (dry-run) and `:255` (success) |
| 4 | After gsd-ralph generate N completes, output contains a Next: line about reviewing generated files | VERIFIED | `lib/commands/generate.sh:158` — `print_guidance "Review generated files in $output_dir"` |
| 5 | After gsd-ralph merge N completes (any outcome), output contains a context-appropriate Next: line | VERIFIED | `lib/commands/merge.sh` has 7 guidance calls covering all merge exit paths |
| 6 | After gsd-ralph cleanup N completes (any outcome), output contains a context-appropriate Next: line | VERIFIED | `lib/commands/cleanup.sh` has 4 guidance calls at relevant exit paths |
| 7 | After gsd-ralph merge N --rollback succeeds, output contains a Next: line | VERIFIED | `lib/merge/rollback.sh:97` — `print_guidance "Fix the issue, then re-run: gsd-ralph merge $phase_num"` |
| 8 | No guidance appears after die() calls or --help output | VERIFIED | Grep of all 7 files shows zero print_guidance calls following die(); --help path (usage()) contains no print_guidance |

### Observable Truths (Plan 09-02)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 9 | A test verifies gsd-ralph init success output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "init success shows guidance" — passes |
| 10 | A test verifies gsd-ralph init already-initialized output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "init already initialized shows guidance" — passes |
| 11 | A test verifies gsd-ralph execute --dry-run output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "execute dry-run shows guidance" — passes |
| 12 | A test verifies gsd-ralph execute success output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "execute success shows guidance" — passes |
| 13 | A test verifies gsd-ralph generate success output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "generate success shows guidance" — passes |
| 14 | A test verifies gsd-ralph merge with no unmerged branches output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "merge no unmerged branches shows guidance" — passes |
| 15 | A test verifies gsd-ralph merge full success output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "merge full success shows guidance" — passes |
| 16 | A test verifies gsd-ralph cleanup success output contains 'Next:' | VERIFIED | `tests/guidance.bats` test "cleanup success shows guidance" — passes |
| 17 | A test verifies guidance is context-sensitive (different messages for different outcomes) | VERIFIED | `tests/guidance.bats` test "guidance is context-sensitive across commands" — passes (init guidance != generate guidance) |

**Score:** 17/17 truths verified (across both plans)

---

## Required Artifacts

### Plan 09-01 Artifacts

| Artifact | Expected | Exists | Substantive | Wired | Status |
|----------|----------|--------|-------------|-------|--------|
| `lib/common.sh` | print_guidance() helper function | Yes | 1 definition, body outputs `\n${GREEN}  Next:${NC} %s\n` | Sourced from `bin/gsd-ralph` line 21 | VERIFIED |
| `lib/commands/init.sh` | Guidance at init exit points | Yes | 2 calls (line 47, 101) | Sourced via entry point | VERIFIED |
| `lib/commands/execute.sh` | Guidance at execute exit points | Yes | 2 calls (line 156, 255) | Sourced via entry point | VERIFIED |
| `lib/commands/generate.sh` | Guidance at generate exit point | Yes | 1 call (line 158) | Sourced via entry point | VERIFIED |
| `lib/commands/merge.sh` | Guidance at all merge exit points | Yes | 7 calls (lines 238, 297, 300, 313, 393, 428, 437) | Sourced via entry point | VERIFIED |
| `lib/commands/cleanup.sh` | Guidance at cleanup exit points | Yes | 4 calls (lines 129, 133, 268, 270) | Sourced via entry point | VERIFIED |
| `lib/merge/rollback.sh` | Guidance after rollback success | Yes | 1 call (line 97) | Called from merge.sh line 185 | VERIFIED |

### Plan 09-02 Artifacts

| Artifact | Expected | Exists | Substantive | Wired | Status |
|----------|----------|--------|-------------|-------|--------|
| `tests/guidance.bats` | Comprehensive guidance output tests for all commands (min 80 lines) | Yes | 273 lines, 14 tests | Sources common.sh line 56, calls gsd-ralph commands | VERIFIED |

---

## Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `lib/common.sh` | all command files | print_guidance() function sourced through common.sh via bin/gsd-ralph | WIRED | `bin/gsd-ralph:21` sources common.sh before dispatching to command files; all 7 files use print_guidance |
| `lib/commands/merge.sh` | `lib/merge/rollback.sh` | rollback_merge() called from cmd_merge when --rollback flag set | WIRED | `merge.sh:144` parses `--rollback` flag, `merge.sh:185` calls `rollback_merge "$phase_num"` |
| `tests/guidance.bats` | `lib/common.sh` | Sources common.sh which provides print_guidance() | WIRED | `guidance.bats:56` — `source "$PROJECT_ROOT/lib/common.sh"` |
| `tests/guidance.bats` | `lib/commands/*.sh` | Calls gsd-ralph commands and checks output for Next: | WIRED | 13 `assert_output --partial "Next:"` assertions across 11 command-calling tests |

---

## Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| GUID-01 | 09-01, 09-02 | Every command outputs a next-step suggestion after completion | SATISFIED | print_guidance() present in all 5 active commands + rollback (18 total calls); 14 tests confirm output contains "Next:"; 211/211 tests pass |
| GUID-02 | 09-01, 09-02 | Guidance is context-sensitive (accounts for current state, available next actions) | SATISFIED | merge.sh has 7 distinct messages for 7 different outcomes; cleanup.sh has conditional logic for full vs partial cleanup; test "guidance is context-sensitive across commands" passes — init and generate produce different guidance lines |

Both GUID-01 and GUID-02 are marked complete in REQUIREMENTS.md. Both requirements are claimed in both plan frontmatters. No orphaned requirements found.

---

## Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | — |

No TODOs, FIXMEs, placeholders, or empty implementations found in any of the 7 modified files.

---

## Human Verification Required

None. All observable behaviors verified programmatically:

- `print_guidance()` function body inspected directly
- All 18 call sites confirmed with grep
- 14 bats tests confirm runtime output contains "Next:" with context-specific keywords
- Full 211-test suite passes with zero failures

---

## Gaps Summary

No gaps. Phase goal achieved.

All 7 required files have substantive, wired implementations. The `tests/guidance.bats` file has 273 lines and 14 tests covering every specified exit path. The full test suite (211 tests) passes with zero regressions.

The phase goal — "Every command tells the user what to do next" — is achieved. Every non-die, non-help exit path in init, execute, generate, merge, cleanup, and rollback calls `print_guidance()` with a context-appropriate message. The old 4-line "Next steps:" block in init.sh has been replaced by a single `print_guidance` call.

---

_Verified: 2026-02-23T12:00:00Z_
_Verifier: Claude (gsd-verifier)_
