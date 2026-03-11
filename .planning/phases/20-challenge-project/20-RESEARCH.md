# Phase 20: Challenge Project - Research

**Researched:** 2026-03-11
**Domain:** Bash CLI construction, Bats testing, planted defects, git tagging
**Confidence:** HIGH

## Summary

Phase 20 builds a standalone Bash CLI tool (`taskctl`) that serves as the challenge project for all benchmarks. This is a content-creation phase, not a software engineering challenge -- we are authoring the code that other modes will later operate on. The deliverables are pure Bash source files, Bats tests, a JSON data file, and a git tag.

The taskctl project must contain exactly the right mix of working code, planted bugs, missing test coverage, and messy code to create five distinct benchmark challenges. The critical design constraint is that each defect or gap must be realistic enough that an AI tool's approach to fixing it is meaningful to measure, but not so obscure that it becomes a trick question.

**Primary recommendation:** Build taskctl as a self-contained Bash CLI under `benchmarks/taskctl/` using jq for JSON storage, Bats for tests, and conventional Bash patterns from the parent gsd-ralph project. Tag the final state as `bench/baseline` with an annotated tag.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| CHAL-01 | `taskctl` Bash CLI exists with add, list, done commands at `bench/baseline` git tag | Standard stack (Bash 3.2, jq, Bats), architecture patterns, git tagging guidance |
| CHAL-02 | `done.sh` contains a planted bug (marks wrong task) discoverable through testing | Planted bug design section with off-by-one pattern |
| CHAL-03 | Partial test coverage exists (test_add.bats, test_list.bats) with no tests for done.sh or storage.sh | Bats test patterns, what to cover and what to deliberately omit |
| CHAL-04 | `format.sh` is messy and serves as a meaningful refactoring target | Code smell catalog with ShellCheck-detectable patterns |
</phase_requirements>

## Standard Stack

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2 | Shell scripting language | macOS system bash; project constraint |
| jq | 1.7+ | JSON storage CRUD | Installed on dev machine (1.8.1); standard for CLI JSON work |
| Bats-core | 1.13.0 | Test framework | Already bundled in gsd-ralph at `tests/bats/` |
| bats-assert | (bundled) | Test assertions | Already in `tests/test_helper/bats-assert/` |
| bats-support | (bundled) | Bats helper | Already in `tests/test_helper/bats-support/` |
| bats-file | (bundled) | File assertions | Already in `tests/test_helper/bats-file/` |
| ShellCheck | 0.11.0 | Static analysis | Installed; used for Challenge 4 metrics |
| Git | system | Version control + tagging | Tags mark benchmark starting states |

### Supporting
| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| mktemp | system | Temp dir for test isolation | Bats setup/teardown |
| date | system | Timestamp generation | Task creation timestamps |
| cat/printf | system | Output formatting | CLI display |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| jq for JSON | Plain text files | jq is more realistic; tests storage layer complexity |
| Bats for tests | shunit2 | Bats is already in the project; consistency matters |
| Single .json file | SQLite | Over-engineered for a task CLI; jq is simpler |

**No installation needed:** All tools are either already bundled in the project or installed on the development machine.

## Architecture Patterns

### Recommended Project Structure

This matches the structure defined in BENCHMARK-MILESTONE.md exactly:

```
benchmarks/taskctl/
├── src/
│   ├── taskctl.sh          # Entry point, arg dispatch
│   ├── commands/
│   │   ├── add.sh           # Add a task (working)
│   │   ├── list.sh          # List tasks (working but ugly output)
│   │   └── done.sh          # Mark task done (HAS PLANTED BUG)
│   ├── storage.sh           # JSON file storage (working, NO TESTS)
│   └── format.sh            # Output formatting (MESSY, needs refactor)
├── tests/
│   ├── test_add.bats        # 4 passing tests
│   └── test_list.bats       # 3 passing tests
├── .taskctl.json             # Sample data file (seed data)
├── CLAUDE.md                 # Project context for AI tools
└── README.md                 # Usage documentation
```

### Pattern 1: Bash CLI Dispatch Pattern

**What:** Entry point script that parses the first argument and sources the appropriate command file.
**When to use:** Every CLI invocation goes through `taskctl.sh`.
**Example:**
```bash
#!/bin/bash
# taskctl.sh -- Entry point
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/storage.sh"
source "$SCRIPT_DIR/format.sh"

case "${1:-}" in
    add)  shift; source "$SCRIPT_DIR/commands/add.sh"; cmd_add "$@" ;;
    list) shift; source "$SCRIPT_DIR/commands/list.sh"; cmd_list "$@" ;;
    done) shift; source "$SCRIPT_DIR/commands/done.sh"; cmd_done "$@" ;;
    *)    echo "Usage: taskctl {add|list|done} [args]"; exit 1 ;;
esac
```

### Pattern 2: JSON Storage with jq

**What:** A `.taskctl.json` file stores tasks as a JSON array. `storage.sh` provides CRUD functions.
**When to use:** All command files call storage functions, never touch JSON directly.
**Example:**
```bash
# storage.sh -- JSON file storage layer
STORAGE_FILE="${TASKCTL_DATA:-.taskctl.json}"

storage_read_all() {
    if [[ -f "$STORAGE_FILE" ]]; then
        jq '.' "$STORAGE_FILE"
    else
        echo '[]'
    fi
}

storage_add() {
    local description="$1"
    local id
    id=$(storage_next_id)
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local tasks
    tasks=$(storage_read_all)
    echo "$tasks" | jq --arg desc "$description" --arg id "$id" --arg ts "$timestamp" \
        '. + [{"id": ($id | tonumber), "description": $desc, "done": false, "created": $ts}]' \
        > "$STORAGE_FILE"
}

storage_next_id() {
    local max_id
    max_id=$(storage_read_all | jq '[.[].id] | max // 0')
    echo $((max_id + 1))
}
```

### Pattern 3: Bats Test Pattern for taskctl

**What:** Each test file sources the command module and tests it in isolation using a temp data file.
**When to use:** For test_add.bats, test_list.bats.
**Example:**
```bash
#!/usr/bin/env bats
# tests/test_add.bats

setup() {
    TEST_DIR="$(mktemp -d)"
    export TASKCTL_DATA="$TEST_DIR/.taskctl.json"
    SCRIPT_DIR="$(cd "$BATS_TEST_DIRNAME/../src" && pwd)"
    source "$SCRIPT_DIR/storage.sh"
    source "$SCRIPT_DIR/format.sh"
    source "$SCRIPT_DIR/commands/add.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "add creates a new task" {
    run cmd_add "Buy milk"
    assert_success
    # Verify task exists in storage
    local count
    count=$(jq length "$TASKCTL_DATA")
    [[ "$count" -eq 1 ]]
}
```

### Anti-Patterns to Avoid

- **Over-engineering taskctl:** This is a benchmark fixture, not production software. Keep it simple enough that challenges are completable in 10-20 minutes.
- **Making the planted bug too obvious or too obscure:** An off-by-one error is ideal -- realistic, discoverable through testing, but not a trick question.
- **Making format.sh TOO broken:** It must still work. The smells are about style, not correctness. All existing tests must pass at baseline.
- **Hardcoding paths:** Use `TASKCTL_DATA` env var for the storage file path so tests can redirect to temp dirs.
- **Using Bash 4+ features:** Must remain Bash 3.2 compatible (macOS system bash). No associative arrays, no `${var,,}` lowercase syntax, no `mapfile`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| JSON storage | Custom text parsing | jq for all JSON ops | Edge cases with escaping, nested values, atomicity |
| Test assertions | Manual `[ "$output" = "..." ]` | bats-assert (`assert_output`, `assert_success`) | Consistent failure messages, partial matching |
| File existence checks | `[ -f "$file" ]` in tests | bats-file (`assert_file_exists`) | Better error output |
| Temp directory management | Manual mkdir/rm | `mktemp -d` in setup, `rm -rf` in teardown | Avoids test pollution |
| ISO timestamps | Custom date formatting | `date -u +%Y-%m-%dT%H:%M:%SZ` | Portable between macOS and Linux |

**Key insight:** The taskctl project deliberately uses simple tools (jq, Bats) that are already in the project ecosystem. No new dependencies needed.

## Common Pitfalls

### Pitfall 1: Planted Bug That Is Too Easy to Spot

**What goes wrong:** If the bug is a syntax error or immediately visible `# BUG HERE` comment, the benchmark measures nothing interesting.
**Why it happens:** Temptation to make the defect obvious for testing convenience.
**How to avoid:** Use an off-by-one error in array indexing. jq uses 0-based indexing, but task IDs are 1-based. The bug in `done.sh` should use the task ID directly as a jq array index without adjusting (i.e., `jq ".[$id].done = true"` instead of `jq ".[($id - 1)].done = true"` or better, look up by ID field). This is a realistic, common mistake.
**Warning signs:** If you can see the bug by reading the function name or first line, it is too obvious.

### Pitfall 2: format.sh Smells That Break Functionality

**What goes wrong:** Code smells accidentally introduce bugs, causing tests to fail at baseline.
**Why it happens:** When writing intentionally messy code, it is easy to introduce actual defects.
**How to avoid:** Write format.sh clean first, verify all tests pass, THEN introduce smells (duplicate logic, long functions, poor names, unquoted variables) while re-verifying tests pass after each change.
**Warning signs:** Tests failing at the `bench/baseline` tag.

### Pitfall 3: Bats Test Loading Path Issues

**What goes wrong:** Tests cannot find source files because relative paths break.
**Why it happens:** Bats tests run from varying working directories. `BATS_TEST_DIRNAME` is the reliable anchor.
**How to avoid:** Always use `BATS_TEST_DIRNAME` to construct paths to source files. Never rely on `pwd` or relative paths in test files.
**Warning signs:** Tests pass locally but fail from a different working directory.

### Pitfall 4: jq Treating false as Falsy with // Operator

**What goes wrong:** `jq '.done // "not set"'` returns `"not set"` when done is `false`.
**Why it happens:** jq's `//` alternative operator treats `false` and `null` the same.
**How to avoid:** Use `== false` explicit checks: `jq 'if .done == false then ...'`. This is a known project gotcha (documented in MEMORY.md: "jq == false for JSON boolean handling").
**Warning signs:** Tasks showing as "not done" when they should show as done, or vice versa.

### Pitfall 5: Forgetting to Commit Everything Before Tagging

**What goes wrong:** The `bench/baseline` tag does not capture the complete project state.
**Why it happens:** New files not added to git, or unstaged changes at tag time.
**How to avoid:** Run `git status` and verify clean working tree before `git tag -a bench/baseline -m "..."`. The success criterion explicitly requires `git tag -l 'bench/baseline'` to return the tag.
**Warning signs:** Checking out the tag produces a different file set than expected.

### Pitfall 6: Sample Data File Mismatch

**What goes wrong:** `.taskctl.json` seed data has task IDs that don't match what the tests expect.
**Why it happens:** Tests create their own data via `cmd_add`, but if `.taskctl.json` has pre-existing entries, counts are off.
**How to avoid:** Tests should use `TASKCTL_DATA` env var pointing to a temp file (empty or created fresh). The `.taskctl.json` in the repo is for demo/manual use only.
**Warning signs:** Tests pass without seed data but fail with it, or vice versa.

## Code Examples

### Planted Bug in done.sh (CHAL-02)

The bug must be an off-by-one or incorrect lookup that marks the wrong task. The most realistic pattern:

```bash
# commands/done.sh -- Mark a task as done
# BUG: Uses array index instead of looking up by ID field
cmd_done() {
    local task_id="$1"
    local tasks
    tasks=$(storage_read_all)

    # WRONG: This treats task_id as a 0-based array index
    # So "done 3" marks the task at index 3 (which is the 4th task, not task with id=3)
    local updated
    updated=$(echo "$tasks" | jq --argjson idx "$task_id" \
        '.[$idx].done = true')

    echo "$updated" > "$STORAGE_FILE"
    echo "Task $task_id marked as done"
}
```

When tasks are `[{id:1}, {id:2}, {id:3}]`, running `taskctl done 3` marks `tasks[3]` which is out of bounds or marks the wrong task. The correct fix would look up by `.id` field: `jq '(.[] | select(.id == $id)).done = true'`.

### Code Smells for format.sh (CHAL-04)

The smells should be ShellCheck-detectable and genuinely improvable:

```bash
# format.sh -- Output formatting (deliberately messy)

# Smell 1: Single massive function instead of small helpers
format_task_list() {
    local tasks="$1"
    local filter="${2:-all}"
    local cnt=0
    local total=0
    local done_cnt=0
    local t=""
    local d=""
    local s=""
    # Smell 2: Poor variable names (t, d, s, cnt)
    total=$(echo $tasks | jq length)  # Smell 3: Unquoted variable (SC2086)
    local i=0
    while [ $i -lt $total ]; do  # Smell 4: Unquoted $i and $total
        t=$(echo $tasks | jq -r ".[$i].description")
        d=$(echo $tasks | jq -r ".[$i].done")
        s=$(echo $tasks | jq -r ".[$i].created")
        local id=$(echo $tasks | jq -r ".[$i].id")  # Smell 5: local in loop
        if [ "$filter" = "done" ] && [ "$d" = "true" ]; then
            # Smell 6: Duplicated formatting logic (copy-pasted blocks)
            printf "[%s] #%s %s (%s)\n" "x" "$id" "$t" "$s"
            cnt=$((cnt + 1))
        elif [ "$filter" = "pending" ] && [ "$d" = "false" ]; then
            printf "[%s] #%s %s (%s)\n" " " "$id" "$t" "$s"
            cnt=$((cnt + 1))
        elif [ "$filter" = "all" ]; then
            if [ "$d" = "true" ]; then
                printf "[%s] #%s %s (%s)\n" "x" "$id" "$t" "$s"
            else
                printf "[%s] #%s %s (%s)\n" " " "$id" "$t" "$s"
            fi
            cnt=$((cnt + 1))
        fi
        i=$((i + 1))
        done_cnt=$((done_cnt + 1))  # Smell 7: Misleading counter (counts all, not done)
    done
    # Smell 8: Duplicated summary logic
    if [ "$filter" = "done" ]; then
        echo ""
        echo "$cnt done tasks"
    elif [ "$filter" = "pending" ]; then
        echo ""
        echo "$cnt pending tasks"
    else
        echo ""
        echo "$cnt total tasks"
    fi
}

# Smell 9: Second function that duplicates logic from format_task_list
format_single_task() {
    local tasks="$1"
    local task_id="$2"
    local total=$(echo $tasks | jq length)
    local i=0
    while [ $i -lt $total ]; do
        local id=$(echo $tasks | jq -r ".[$i].id")
        if [ "$id" = "$task_id" ]; then
            local t=$(echo $tasks | jq -r ".[$i].description")
            local d=$(echo $tasks | jq -r ".[$i].done")
            local s=$(echo $tasks | jq -r ".[$i].created")
            if [ "$d" = "true" ]; then
                printf "[x] #%s %s (%s)\n" "$id" "$t" "$s"
            else
                printf "[ ] #%s %s (%s)\n" "$id" "$t" "$s"
            fi
            return 0
        fi
        i=$((i + 1))
    done
    echo "Task $task_id not found"
    return 1
}
```

**ShellCheck warnings this will produce:**
- SC2086: Unquoted variables (`$tasks`, `$i`, `$total`)
- SC2155: Declare and assign separately (`local id=$(...)`)
- Duplicated code blocks (not ShellCheck but visible to refactoring)
- Poor variable names (`t`, `d`, `s`, `cnt`)
- Misleading counter (`done_cnt` increments for all tasks)

### Git Tagging for bench/baseline

```bash
# After all files are committed and tests pass:
git tag -a bench/baseline -m "Benchmark baseline: taskctl CLI with planted bug, partial tests, messy format.sh"
```

Use annotated tag (`-a`) because:
- Stores tagger, date, message metadata
- `git tag -l 'bench/baseline'` returns it reliably
- `git checkout bench/baseline` restores exact state
- Annotated tags are the standard for marking release/milestone points

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| sstephenson/bats (archived) | bats-core/bats-core 1.13.0 | 2018+ | Active maintenance, new features |
| Text file task storage | JSON with jq | N/A | Structured data, queryable |
| Manual test assertions | bats-assert library | bats-core adoption | Better error messages |

**Deprecated/outdated:**
- `sstephenson/bats`: Archived. Use `bats-core/bats-core` (already in project).
- `date -Iseconds`: Not portable to macOS Bash 3.2. Use `date -u +%Y-%m-%dT%H:%M:%SZ`.

## Design Decisions for the Challenge Project

### Planted Bug Strategy (CHAL-02)

**Decision:** Off-by-one via array index vs. ID lookup.

The bug in `done.sh` should use the task ID as a jq array index rather than looking up the task by its `.id` field. This is realistic because:
1. It is a genuine mistake a developer would make (confusing array position with ID)
2. It is discoverable by running `taskctl done 3` and observing which task gets marked
3. It requires understanding the data model to fix correctly
4. The fix is straightforward once diagnosed

### Partial Test Coverage Strategy (CHAL-03)

**Decision:** Tests for add and list, but NOT for done or storage.

- `test_add.bats` (4 tests): add single task, add multiple tasks, add with special characters, verify storage format
- `test_list.bats` (3 tests): list all tasks, list with --done filter, list empty state
- No `test_done.bats`: The planted bug would be caught by tests, so omitting tests is narratively consistent
- No `test_storage.bats`: This is Challenge 3's target

### Code Smell Strategy (CHAL-04)

**Decision:** Concentrate smells in `format.sh` only. Other files should be clean.

Smells to include:
1. **Long function** (format_task_list > 40 lines)
2. **Duplicated logic** (printf blocks copy-pasted with minor variations)
3. **Poor variable names** (t, d, s, cnt instead of description, is_done, created_at, count)
4. **Unquoted variables** (SC2086 warnings from ShellCheck)
5. **Declare-and-assign** (SC2155 warnings)
6. **Misleading counter** (done_cnt that counts all tasks)
7. **Duplicated function** (format_single_task repeats format_task_list logic)

This gives a refactoring tool 7+ distinct improvements to make, which is "meaningful" per the requirements.

### Sample Data Strategy

**Decision:** Ship `.taskctl.json` with 3-5 seed tasks for manual demo.

```json
[
  {"id": 1, "description": "Buy groceries", "done": false, "created": "2026-03-01T10:00:00Z"},
  {"id": 2, "description": "Write README", "done": true, "created": "2026-03-01T11:00:00Z"},
  {"id": 3, "description": "Fix tests", "done": false, "created": "2026-03-02T09:00:00Z"},
  {"id": 4, "description": "Deploy v2", "done": false, "created": "2026-03-02T14:00:00Z"}
]
```

With this data, `taskctl done 3` (the planted bug) would attempt `jq '.[3]'` which is task 4 ("Deploy v2"), not task 3 ("Fix tests"). This makes the bug observable.

### CLAUDE.md for taskctl

The challenge project needs its own CLAUDE.md to give AI tools context about the project. This should describe:
- What taskctl does
- How to run it
- How to run tests
- Known issues (deliberately vague -- should NOT reveal the bug)

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bats-core 1.13.0 (bundled at tests/bats/) |
| Config file | None needed -- Bats uses command-line invocation |
| Quick run command | `./tests/bats/bin/bats benchmarks/taskctl/tests/` |
| Full suite command | `./tests/bats/bin/bats benchmarks/taskctl/tests/` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CHAL-01 | taskctl add + list work correctly | integration | `./tests/bats/bin/bats benchmarks/taskctl/tests/test_add.bats benchmarks/taskctl/tests/test_list.bats` | Wave 0 (created by this phase) |
| CHAL-02 | done.sh marks wrong task (planted bug is observable) | manual + smoke | `cd benchmarks/taskctl && src/taskctl.sh done 3` then verify wrong task marked | Manual verification |
| CHAL-03 | Partial coverage: add/list tests pass, no done/storage tests | smoke | `ls benchmarks/taskctl/tests/test_done.bats 2>/dev/null && echo "FAIL: test_done should not exist" \|\| echo "PASS"` | Wave 0 |
| CHAL-04 | format.sh has ShellCheck warnings | smoke | `shellcheck benchmarks/taskctl/src/format.sh 2>&1 \| grep -c 'SC[0-9]'` (expect > 0) | N/A (static analysis) |

### Sampling Rate
- **Per task commit:** `./tests/bats/bin/bats benchmarks/taskctl/tests/`
- **Per wave merge:** Same (single wave phase)
- **Phase gate:** All test_add.bats and test_list.bats tests green; planted bug observable; ShellCheck warnings present in format.sh; `git tag -l 'bench/baseline'` returns tag

### Wave 0 Gaps
- [ ] `benchmarks/taskctl/tests/test_add.bats` -- created as part of this phase (4 tests)
- [ ] `benchmarks/taskctl/tests/test_list.bats` -- created as part of this phase (3 tests)
- [ ] Bats helper setup for taskctl tests (load paths pointing to project bats-core)

Note: The taskctl Bats tests are part of the DELIVERABLE, not pre-existing infrastructure. They are written as part of CHAL-03 to provide partial coverage.

## Open Questions

1. **Bats load path for taskctl tests**
   - What we know: The parent project has bats-core at `tests/bats/` and helpers at `tests/test_helper/`. The taskctl tests live at `benchmarks/taskctl/tests/`.
   - What's unclear: Whether taskctl tests should reference the parent project's Bats installation or have their own copy.
   - Recommendation: Reference the parent project's Bats via relative paths (`../../../tests/bats/bin/bats`). The taskctl project is not meant to be standalone -- it lives inside gsd-ralph. Alternatively, add a simple `run_tests.sh` wrapper that resolves the path.

2. **TASKCTL_DATA environment variable scope**
   - What we know: Tests need to use temp files; the CLI needs a default location.
   - What's unclear: Whether `TASKCTL_DATA` should default to `$PWD/.taskctl.json` or be relative to the script.
   - Recommendation: Default to `$PWD/.taskctl.json` (current working directory). This matches user expectation (`cd` into project, run commands). Tests override via env var.

## Sources

### Primary (HIGH confidence)
- Project codebase: `tests/common.bats`, `tests/test_helper/common.bash` -- established Bats patterns
- Project codebase: `lib/common.sh` -- Bash style conventions (Bash 3.2, set -euo pipefail, color output)
- `benchmarks/BENCHMARK-MILESTONE.md` -- canonical project structure and challenge definitions
- `.planning/REQUIREMENTS.md` -- CHAL-01 through CHAL-04 requirement definitions
- System tools verified: jq 1.8.1, ShellCheck 0.11.0, Bash 3.2.57, Bats 1.13.0 (bundled)

### Secondary (MEDIUM confidence)
- [Bats-core documentation](https://bats-core.readthedocs.io/en/stable/writing-tests.html) -- setup/teardown, load, assertions
- [Bats-core GitHub](https://github.com/bats-core/bats-core) -- current version, features
- [jq documentation](https://jqlang.org/) -- JSON manipulation patterns
- [Git tagging (Atlassian)](https://www.atlassian.com/git/tutorials/inspecting-a-repository/git-tag) -- annotated vs lightweight tags
- [ShellCheck wiki](https://www.shellcheck.net/wiki/) -- SC2086, SC2155, SC2034 warning catalog

### Tertiary (LOW confidence)
- None -- all findings verified against project codebase or official documentation.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already installed/bundled in the project
- Architecture: HIGH -- structure defined in BENCHMARK-MILESTONE.md, patterns match existing project conventions
- Pitfalls: HIGH -- derived from project learnings (jq false handling, Bash 3.2 compat) and Bats documentation
- Planted bug design: HIGH -- off-by-one via index-vs-ID is a well-understood pattern
- Code smell design: HIGH -- ShellCheck warnings are deterministic and verifiable

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable domain; no fast-moving dependencies)
