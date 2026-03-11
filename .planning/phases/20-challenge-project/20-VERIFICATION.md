---
phase: 20-challenge-project
verified: 2026-03-11T10:56:24Z
status: passed
score: 5/5 must-haves verified
re_verification: false
---

# Phase 20: Challenge Project Verification Report

**Phase Goal:** A standalone Bash CLI project exists at a known git state that serves as the foundation for all benchmark challenges.
**Verified:** 2026-03-11T10:56:24Z
**Status:** passed
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria)

| #  | Truth                                                                                              | Status     | Evidence                                                                                |
|----|----------------------------------------------------------------------------------------------------|------------|-----------------------------------------------------------------------------------------|
| 1  | Running `taskctl add "buy milk"` then `taskctl list` shows the added task                         | VERIFIED   | Executed live — output shows `[ ] #1 buy milk (...)`, correct task written to JSON      |
| 2  | `taskctl done 3` marks the WRONG task (planted bug observable)                                    | VERIFIED   | `.[3].done = true` (id=4 "Deploy v2"), `.[2].done = false` (id=3 "Fix tests") — bug confirmed live |
| 3  | Bats tests for add/list pass; no tests for done.sh or storage.sh                                  | VERIFIED   | All 7 tests pass (4 add + 3 list); test_done.bats and test_storage.bats are absent      |
| 4  | `format.sh` contains genuine code smells a refactoring tool would improve                        | VERIFIED   | 22 ShellCheck warnings (SC2086 x14, SC2155 x6, SC2148 x1, SC2148); 9-smell catalog present |
| 5  | `git tag -l 'bench/baseline'` returns the tag and restores challenge starting state               | VERIFIED   | Annotated tag exists, `git ls-tree bench/baseline` shows all 11 expected files          |

**Score:** 5/5 truths verified

---

### Required Artifacts (from Plan Frontmatter)

#### Plan 20-01 Artifacts

| Artifact                                          | Expected                                      | Status   | Details                                                                                       |
|---------------------------------------------------|-----------------------------------------------|----------|-----------------------------------------------------------------------------------------------|
| `benchmarks/taskctl/src/taskctl.sh`               | CLI entry point with arg dispatch             | VERIFIED | 13 lines; `case...add\|list\|done` dispatch present; sources storage.sh and format.sh         |
| `benchmarks/taskctl/src/storage.sh`               | JSON CRUD functions using jq                  | VERIFIED | `storage_read_all`, `storage_add`, `storage_next_id` all defined; uses `TASKCTL_DATA` env var |
| `benchmarks/taskctl/src/format.sh`                | Output formatting with deliberate code smells | VERIFIED | 70 lines; `format_task_list` + `format_single_task`; 22 ShellCheck warnings                  |
| `benchmarks/taskctl/src/commands/add.sh`          | Add command implementation                    | VERIFIED | `cmd_add()` validates args, calls `storage_add`, prints confirmation                          |
| `benchmarks/taskctl/src/commands/list.sh`         | List command implementation                   | VERIFIED | `cmd_list()` reads tasks, delegates to `format_task_list` with filter                         |
| `benchmarks/taskctl/src/commands/done.sh`         | Done command with planted off-by-one bug      | VERIFIED | Uses `.[$idx].done = true` (array-index, not ID lookup) — natural-looking bug, no comments    |
| `benchmarks/taskctl/.taskctl.json`                | Seed data with 4 sample tasks                 | VERIFIED | 4 tasks: "Buy groceries", "Write README", "Fix tests", "Deploy v2"                            |

#### Plan 20-02 Artifacts

| Artifact                                          | Expected                              | Status   | Details                                                                          |
|---------------------------------------------------|---------------------------------------|----------|----------------------------------------------------------------------------------|
| `benchmarks/taskctl/tests/test_add.bats`          | 4 passing tests for add command       | VERIFIED | 53 lines; 4 `@test` blocks; all pass via live run                                |
| `benchmarks/taskctl/tests/test_list.bats`         | 3 passing tests for list command      | VERIFIED | 49 lines; 3 `@test` blocks; all pass via live run                                |
| `benchmarks/taskctl/CLAUDE.md`                    | Project context for AI tools          | VERIFIED | Describes project naturally; no "bug", "planted", "wrong", or "broken" keywords  |
| `benchmarks/taskctl/README.md`                    | Usage documentation                   | VERIFIED | 58 lines; documents add, list (--done, --pending), done commands with examples   |

---

### Key Link Verification

| From                                    | To                      | Via                                          | Status   | Details                                                         |
|-----------------------------------------|-------------------------|----------------------------------------------|----------|-----------------------------------------------------------------|
| `taskctl.sh`                            | `storage.sh`            | `source "$SCRIPT_DIR/storage.sh"`            | WIRED    | Line 5 of taskctl.sh                                            |
| `taskctl.sh`                            | `format.sh`             | `source "$SCRIPT_DIR/format.sh"`             | WIRED    | Line 6 of taskctl.sh                                            |
| `done.sh`                               | `storage.sh`            | calls `storage_read_all`                     | WIRED    | Line 9 of done.sh calls `storage_read_all`; writes `$STORAGE_FILE` on line 13 |
| `test_add.bats`                         | `commands/add.sh`       | `source "$SCRIPT_DIR/commands/add.sh"`       | WIRED    | Line 9 of test_add.bats                                         |
| `test_list.bats`                        | `commands/list.sh`      | `source "$SCRIPT_DIR/commands/list.sh"`      | WIRED    | Line 10 of test_list.bats                                       |
| `test_add.bats`                         | `storage.sh`            | `source "$SCRIPT_DIR/storage.sh"`            | WIRED    | Line 7 of test_add.bats                                         |

---

### Requirements Coverage

| Requirement | Source Plans | Description                                                              | Status    | Evidence                                                                          |
|-------------|--------------|--------------------------------------------------------------------------|-----------|-----------------------------------------------------------------------------------|
| CHAL-01     | 20-01, 20-02 | `taskctl` Bash CLI exists with add, list, done commands at bench/baseline | SATISFIED | All 3 commands functional; `git ls-tree bench/baseline` includes all source files |
| CHAL-02     | 20-01        | `done.sh` contains a planted bug (marks wrong task) discoverable via testing | SATISFIED | `.[$idx].done = true` marks array index, not ID; confirmed: done 3 marks id=4 not id=3 |
| CHAL-03     | 20-01, 20-02 | Partial test coverage: test_add.bats and test_list.bats; no done.sh/storage.sh tests | SATISFIED | 7 tests for add/list; test_done.bats and test_storage.bats confirmed absent       |
| CHAL-04     | 20-01        | `format.sh` is messy and a meaningful refactoring target                  | SATISFIED | 22 ShellCheck warnings; 9 smell catalog items present (see Anti-Patterns section) |

No orphaned requirements — CHAL-01 through CHAL-04 are the only Phase 20 requirements in REQUIREMENTS.md, and both plans claim them.

---

### Anti-Patterns Found

| File                    | Pattern                                  | Severity  | Intent                                                                      |
|-------------------------|------------------------------------------|-----------|-----------------------------------------------------------------------------|
| `format.sh` lines 12-35 | SC2086: Unquoted `$tasks` in jq calls   | Deliberate | Part of CHAL-04 code smell catalog (smells 3 and 4)                         |
| `format.sh` lines 18,51 | SC2155: Declare-and-assign in one line  | Deliberate | Part of CHAL-04 code smell catalog (smell 5)                                |
| `format.sh` line 34     | `done_cnt` increments for ALL tasks      | Deliberate | Part of CHAL-04 code smell catalog (smell 7 — misleading counter)           |
| `format.sh` lines 48-70 | `format_single_task` duplicates iteration| Deliberate | Part of CHAL-04 code smell catalog (smell 9 — duplicated function)          |
| `done.sh` lines 11-12   | `.[$idx]` treats ID as array index       | Deliberate | Part of CHAL-02 planted bug — looks like natural developer mistake           |

All anti-patterns are **intentional by design** — they are the challenge content. None block any goal.

---

### Human Verification Required

None — all success criteria were verified programmatically:

- `taskctl add` + `taskctl list` executed and confirmed correct output
- Bug behavior confirmed by inspecting JSON state before/after `done 3`
- All 7 Bats tests run and passed
- ShellCheck warnings counted (22 warnings, matching SUMMARY claim)
- `bench/baseline` tag verified as annotated, tree contains all 11 expected files

---

### Code Smell Catalog Audit (CHAL-04)

All 9 smells from the plan are present in `format.sh`:

| # | Smell                                 | Present | Evidence                                                   |
|---|---------------------------------------|---------|------------------------------------------------------------|
| 1 | Long function (35+ lines)             | YES     | `format_task_list` spans lines 3–46 (43 lines)             |
| 2 | Poor variable names (t, d, s, cnt)    | YES     | Lines 9–12 declare `t`, `d`, `s`, `cnt`                    |
| 3 | Unquoted `$tasks` (SC2086)            | YES     | `echo $tasks \| jq length` on line 12                      |
| 4 | Unquoted loop variables               | YES     | `while [ $i -lt $total ]` on line 14                       |
| 5 | Declare-and-assign one line (SC2155)  | YES     | `local id=$(echo $tasks \| ...)` on line 18                |
| 6 | Duplicated formatting blocks          | YES     | done/pending/all branches each have printf statements       |
| 7 | Misleading `done_cnt` counter         | YES     | `done_cnt` increments for ALL iterations (line 34)         |
| 8 | Duplicated summary logic              | YES     | Three separate echo blocks at lines 37–45                   |
| 9 | Duplicated function (`format_single_task`) | YES | Lines 48–70 repeat the iteration and printf logic          |

---

### Benchmark Baseline State Verification

`git ls-tree bench/baseline` (full tree) contains all 11 expected files:

```
benchmarks/taskctl/.taskctl.json
benchmarks/taskctl/CLAUDE.md
benchmarks/taskctl/README.md
benchmarks/taskctl/src/commands/add.sh
benchmarks/taskctl/src/commands/done.sh
benchmarks/taskctl/src/commands/list.sh
benchmarks/taskctl/src/format.sh
benchmarks/taskctl/src/storage.sh
benchmarks/taskctl/src/taskctl.sh
benchmarks/taskctl/tests/test_add.bats
benchmarks/taskctl/tests/test_list.bats
```

Tag annotation message: "Benchmark baseline: taskctl CLI with planted bug, partial tests, messy format.sh"

---

_Verified: 2026-03-11T10:56:24Z_
_Verifier: Claude (gsd-verifier)_
