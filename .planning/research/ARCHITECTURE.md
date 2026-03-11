# Architecture: Benchmarking Suite Integration

**Domain:** Automated benchmarking harness for AI execution mode comparison
**Researched:** 2026-03-11
**Confidence:** HIGH (existing codebase inspected, Claude Code JSON output verified against official docs, PRD fully analyzed)

## The Integration Challenge

The benchmarking suite must invoke Claude Code across four distinct execution modes, capture identical metrics from each, and evaluate results against the same correctness checks -- all without modifying the core gsd-ralph scripts. Each mode has fundamentally different invocation mechanics:

1. **CC** -- Direct `claude -p` with a freeform prompt. No GSD artifacts.
2. **CC + GSD** -- `claude -p` with GSD context appended. Interactive GSD workflow, but run headless.
3. **CC + Ralph** -- `ralph-launcher.sh` driving a `claude -p` loop with STATE.md progress detection.
4. **CC + gsd-ralph** -- `claude -p` invoking `/gsd:ralph` which uses Agent tool internally.

The harness lives entirely in `benchmarks/` and depends on the existing gsd-ralph infrastructure only for modes 3 and 4. Modes 1 and 2 invoke Claude Code directly without any gsd-ralph components.

## System Overview

```
benchmarks/
├── taskctl/                     # Challenge project (Bash CLI)
│   ├── src/
│   │   ├── taskctl.sh           # Entry point
│   │   ├── commands/
│   │   │   ├── add.sh           # Working
│   │   │   ├── list.sh          # Working (ugly output)
│   │   │   └── done.sh          # Planted bug (off-by-one)
│   │   ├── storage.sh           # Working, no tests
│   │   └── format.sh            # Messy, needs refactor
│   ├── tests/
│   │   ├── test_add.bats        # 4 passing
│   │   └── test_list.bats       # 3 passing
│   ├── .taskctl.json            # Sample data
│   ├── CLAUDE.md                # Challenge project instructions
│   └── README.md
│
├── harness/                     # Automation scripts
│   ├── bench-reset.sh           # Reset to challenge starting state
│   ├── bench-run.sh             # Orchestrate a single benchmark run
│   ├── bench-eval.sh            # Run correctness checks
│   ├── bench-report.sh          # Aggregate results into report
│   └── lib/
│       ├── common.sh            # Shared constants, logging, jq helpers
│       ├── metrics.sh           # Metric extraction from JSON output
│       ├── modes/
│       │   ├── cc.sh            # CC mode invocation
│       │   ├── gsd.sh           # CC+GSD mode invocation
│       │   ├── ralph.sh         # CC+Ralph mode invocation
│       │   └── gsd-ralph.sh     # CC+gsd-ralph mode invocation
│       └── checks/
│           ├── fix-bug.sh       # Challenge 1 correctness checks
│           ├── add-feature.sh   # Challenge 2 correctness checks
│           ├── add-tests.sh     # Challenge 3 correctness checks
│           ├── refactor.sh      # Challenge 4 correctness checks
│           └── multi-file.sh    # Challenge 5 correctness checks
│
├── challenges/                  # Challenge definitions (declarative)
│   ├── fix-bug.json
│   ├── add-feature.json
│   ├── add-tests.json
│   ├── refactor.json
│   └── multi-file.json
│
├── results/                     # Raw result JSON files (gitignored)
│   └── {mode}-{challenge}-{timestamp}.json
│
├── REPORT.md                    # Generated comparison report
└── BENCHMARK-MILESTONE.md       # PRD (existing)
```

## Component Boundaries

| Component | Responsibility | New vs Existing | Depends On |
|-----------|---------------|-----------------|------------|
| `benchmarks/taskctl/` | Challenge project with planted defects and partial test coverage | **NEW** | Nothing -- standalone Bash CLI |
| `benchmarks/harness/bench-reset.sh` | Git tag checkout, state validation, temp cleanup | **NEW** | `taskctl/` (validates starting state) |
| `benchmarks/harness/bench-run.sh` | Orchestrate: reset, invoke mode, capture metrics, run eval | **NEW** | `bench-reset.sh`, mode scripts, `bench-eval.sh`, `metrics.sh` |
| `benchmarks/harness/bench-eval.sh` | Run challenge-specific correctness checks | **NEW** | Challenge check scripts |
| `benchmarks/harness/bench-report.sh` | Read result JSONs, aggregate stats, produce markdown table | **NEW** | `results/*.json` |
| `benchmarks/harness/lib/common.sh` | Logging, path constants, jq helpers, time formatting | **NEW** | `jq` |
| `benchmarks/harness/lib/metrics.sh` | Parse `claude -p` JSON output, extract tokens, tool calls, duration | **NEW** | `jq`, Claude Code JSON output format |
| `benchmarks/harness/lib/modes/*.sh` | Mode-specific invocation logic | **NEW** | `cc.sh`: Claude Code; `ralph.sh`: `ralph-launcher.sh` |
| `benchmarks/harness/lib/checks/*.sh` | Per-challenge correctness assertions | **NEW** | `taskctl/` test infrastructure (Bats) |
| `benchmarks/challenges/*.json` | Declarative challenge definitions (prompt, tag, time cap, check script) | **NEW** | Nothing |

**Nothing in the existing codebase is modified.** The benchmarks are a pure addition. Mode scripts reference existing ralph-launcher.sh and GSD patterns but do not change them.

## Integration Point 1: Mode Invocation

Each mode script in `harness/lib/modes/` encapsulates how to invoke that specific execution mode. All four produce the same output contract: a JSON file on stdout with the Claude Code session output, which `metrics.sh` parses.

### Mode: CC (vanilla Claude Code)

```bash
# harness/lib/modes/cc.sh
# Simplest mode: direct claude -p with just the challenge prompt
invoke_cc() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap="$4"

    cd "$workdir"
    timeout "${time_cap}s" \
        claude -p "$prompt" \
        --output-format json \
        --max-turns "$max_turns" \
        --allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)" \
        --no-session-persistence \
        2>/dev/null
}
```

**Key decisions:**
- `--no-session-persistence` prevents session files from polluting `~/.claude/` during benchmark runs.
- `--allowedTools` matches the same set Ralph uses (from `DEFAULT_ALLOWED_TOOLS` in ralph-launcher.sh) for fair comparison.
- `timeout` enforces the challenge time cap at the OS level.
- No `--worktree` -- the harness manages git state via `bench-reset.sh`.

### Mode: CC + GSD (GSD planning context)

```bash
# harness/lib/modes/gsd.sh
# Claude Code with GSD context appended, but no Ralph loop
invoke_gsd() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap="$4"
    local context_file="$5"  # Pre-assembled GSD context

    cd "$workdir"
    timeout "${time_cap}s" \
        claude -p "$prompt" \
        --output-format json \
        --max-turns "$max_turns" \
        --append-system-prompt-file "$context_file" \
        --allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)" \
        --no-session-persistence \
        2>/dev/null
}
```

**Key decisions:**
- The GSD context file is pre-assembled by the harness before invocation (using a simplified version of `assemble-context.sh` or a static challenge-specific context).
- This mode runs a single `claude -p` invocation, not a loop. It simulates what a human would do: invoke Claude Code with GSD project structure visible.
- The CLAUDE.md in the `taskctl/` project should reference GSD conventions so Claude discovers the planning structure.

### Mode: CC + Ralph (standalone launcher loop)

```bash
# harness/lib/modes/ralph.sh
# Ralph launcher loop -- multiple iterations until done or time cap
invoke_ralph() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap="$4"

    cd "$workdir"

    # Ralph uses its own timeout (circuit breaker), but we also wrap with
    # OS timeout as a safety net
    local timeout_minutes=$(( time_cap / 60 + 1 ))

    # Set ralph-specific config for this run
    export RALPH_SCRIPTS_DIR="$GSD_RALPH_ROOT/scripts"

    # Capture all output (ralph-launcher prints iteration summaries to
    # stderr, claude -p JSON to stdout). We need the final JSON from
    # the last iteration.
    timeout "${time_cap}s" \
        bash "$GSD_RALPH_ROOT/scripts/ralph-launcher.sh" \
        "execute-phase 1" \
        --tier default \
        2>"$BENCH_TMPDIR/ralph-stderr.log"
}
```

**Key decisions:**
- Ralph mode requires a GSD project structure with STATE.md, ROADMAP.md, and phase plans. The harness must scaffold minimal GSD artifacts into the `taskctl/` working copy before invoking Ralph.
- The launcher's `--output-format json` flag (built into `build_claude_command`) means each iteration outputs JSON. The loop engine prints iteration summaries to stderr.
- Ralph's circuit breaker (`TIMEOUT_MINUTES`) is set to match the challenge time cap.
- `RALPH_SCRIPTS_DIR` is exported to point back to the gsd-ralph repo's scripts directory. This is the established pattern for location independence.

**GSD scaffolding needed for Ralph mode:**
```
taskctl/                         # Working copy (from bench-reset)
├── .planning/
│   ├── STATE.md                 # "Phase: 1, Status: Executing"
│   ├── config.json              # ralph section with time cap
│   └── phases/
│       └── 01-benchmark/
│           └── PLAN.md          # Contains the challenge prompt as a task
├── .claude/
│   └── skills/
│       └── gsd-ralph-autopilot/
│           └── SKILL.md         # Copied from gsd-ralph repo
└── src/, tests/, etc.           # The actual taskctl code
```

### Mode: CC + gsd-ralph (Agent-based)

```bash
# harness/lib/modes/gsd-ralph.sh
# Agent-based Ralph inside a Claude Code session
invoke_gsd_ralph() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap="$4"

    cd "$workdir"

    # This mode uses /gsd:ralph which invokes Agent tool internally.
    # We simulate it by prompting Claude to use the Agent tool with
    # gsd-ralph behavior.
    local wrapped_prompt="Use the /gsd:ralph command to: ${prompt}"

    timeout "${time_cap}s" \
        claude -p "$wrapped_prompt" \
        --output-format json \
        --max-turns "$max_turns" \
        --allowedTools "Write,Read,Edit,Grep,Glob,Bash(*),Agent" \
        --no-session-persistence \
        2>/dev/null
}
```

**Key decisions:**
- The gsd-ralph mode requires the command file at `.claude/commands/gsd/ralph.md` in the working directory so Claude discovers `/gsd:ralph`.
- This mode also needs GSD scaffolding (STATE.md, config.json, phase plans) because the Agent-based Ralph reads the same GSD state.
- Agent tool must be in `--allowedTools` for the subagent invocation to work.
- The SKILL.md must be present at `.claude/skills/gsd-ralph-autopilot/SKILL.md` for Claude to load autopilot behavior rules.

## Integration Point 2: Challenge Definitions

Challenges are defined as JSON files for machine-readability. The harness reads these to know what git tag to reset to, what prompt to use, and what time cap to enforce.

```json
{
    "name": "fix-bug",
    "display_name": "Fix the Bug",
    "starting_tag": "bench/baseline",
    "prompt": "The `taskctl done 3` command marks the wrong task as done. Find the bug and fix it.",
    "time_cap_seconds": 600,
    "max_turns": 30,
    "check_script": "fix-bug.sh",
    "measures": ["diagnostic_reasoning", "targeted_fix", "regression_avoidance"]
}
```

**Why JSON instead of Bash:**
- Challenge definitions are data, not logic. JSON is easier to read and validate.
- The harness scripts consume these with `jq`, which is already a project dependency.
- Adding a new challenge is declarative: create a JSON file and a check script.
- `bench-report.sh` can read challenge metadata for report headers without sourcing Bash.

**Challenge 5 exception:** The `multi-file` challenge uses `bench/after-delete` as its starting tag, which requires Challenge 2 to have been completed and tagged first. This is a one-time setup step, not a runtime dependency between benchmark runs.

## Integration Point 3: Correctness Evaluation

Each check script in `harness/lib/checks/` receives the path to the working directory and outputs structured pass/fail JSON. The checks are challenge-specific but follow a common contract.

### Check Script Contract

```bash
# Input: $1 = working directory (taskctl project root after Claude's changes)
# Output: JSON to stdout
# Exit code: 0 always (failures reported in JSON, not exit code)

# Example output:
{
    "challenge": "fix-bug",
    "checks": [
        {"name": "done_marks_correct_task", "passed": true, "detail": "taskctl done 3 marks task 3"},
        {"name": "existing_tests_pass", "passed": true, "detail": "7/7 tests pass"},
        {"name": "new_test_for_fix", "passed": false, "detail": "No new test found for done command"}
    ],
    "correctness_score": 67,
    "regression_score": 100,
    "tests_added": 0
}
```

### How Checks Work Per Challenge

**Challenge 1 (fix-bug):**
1. Set up test data: create `.taskctl.json` with known tasks
2. Run `taskctl done 3` and verify task 3 (not 2 or 4) is marked done
3. Run all existing Bats tests, count passes/failures
4. Check git log for new test files or modified test files covering `done`

**Challenge 2 (add-feature):**
1. Run `taskctl delete 1` with test data, verify task 1 removed from storage
2. Run `taskctl delete 999`, verify error output
3. Check for `test_delete.bats` with at least 2 tests
4. Run all Bats tests (existing + new)

**Challenge 3 (add-tests):**
1. Check for `test_storage.bats` file existence
2. Count test functions in the file (at least 5)
3. Run the tests, verify all pass
4. Verify `storage.sh` is unmodified (compare against `bench/baseline` version)

**Challenge 4 (refactor):**
1. Run all existing Bats tests, verify zero regressions
2. Diff `format.sh` against `bench/baseline` version, verify > 10 lines changed
3. Count ShellCheck warnings before and after
4. Verify no new exported functions (behavior preservation)

**Challenge 5 (multi-file):**
1. Run `taskctl add --priority high "X"`, verify priority stored
2. Run `taskctl add "Y"`, verify default priority is `low`
3. Run `taskctl list --sort priority`, verify ordering
4. Check for at least 3 new tests for priority features
5. Run all tests, verify existing tests still pass
6. Count files changed (must be >= 3)

### ShellCheck Integration

ShellCheck provides machine-readable JSON output for code quality measurement:

```bash
# Count warnings before (from bench/baseline)
shellcheck -f json src/*.sh src/commands/*.sh 2>/dev/null | jq 'length'

# Count warnings after Claude's changes
shellcheck -f json src/*.sh src/commands/*.sh 2>/dev/null | jq 'length'

# Delta = after - before
```

ShellCheck is an optional dependency for the benchmarks. If not installed, quality metrics are reported as `null` in results.

## Integration Point 4: Metrics Capture

### Claude Code JSON Output Fields

When invoked with `--output-format json`, `claude -p` returns:

```json
{
    "type": "result",
    "result": "I have completed the tasks...",
    "session_id": "550e8400-e29b-41d4-a716-446655440000",
    "cost_usd": 0.042,
    "duration_ms": 3200,
    "num_turns": 15,
    "usage": {
        "input_tokens": 45000,
        "output_tokens": 12000
    }
}
```

**Confidence:** MEDIUM -- The `usage` field with `input_tokens`/`output_tokens` is documented in the official headless docs and consistent with the session JSONL structure (`~/.claude/projects/.../*.jsonl`), but the exact top-level JSON fields have evolved across Claude Code versions. The harness should defensively check for field existence with `jq -r '.usage.input_tokens // "unknown"'`.

**Fields available from JSON output:**
| PRD Metric | JSON Field | Extraction |
|-----------|-----------|------------|
| Wall-clock time | Harness timestamps (more reliable than `duration_ms`) | `$(date +%s)` before/after |
| Total tokens (input) | `.usage.input_tokens` | `jq -r '.usage.input_tokens // 0'` |
| Total tokens (output) | `.usage.output_tokens` | `jq -r '.usage.output_tokens // 0'` |
| Tool calls count | Not in JSON output | Parse session JSONL or use `--output-format stream-json` |
| Iterations (Ralph only) | Harness counter / ralph stderr log | Parse "Iter N" lines from stderr |
| Human interventions | Always 0 for headless modes | Hardcoded |
| Cost | `.cost_usd` | `jq -r '.cost_usd // 0'` |
| Num turns | `.num_turns` | `jq -r '.num_turns // 0'` |

### Tool Call Counting Strategy

Tool calls are NOT present in the `--output-format json` response. Two options:

**Option A (recommended): Parse session JSONL files.**
Claude Code writes session transcripts to `~/.claude/projects/<encoded-path>/sessions/<session-id>.jsonl`. Each line is a JSON object. Tool use events have `"type": "tool_use"` in content blocks. The `session_id` from the JSON output identifies which JSONL file to parse.

```bash
# Extract tool call count from session JSONL
session_id=$(jq -r '.session_id' "$result_json")
encoded_path=$(echo "$workdir" | sed 's|[^a-zA-Z0-9]|-|g')
jsonl_file="$HOME/.claude/projects/${encoded_path}/sessions/${session_id}.jsonl"

if [ -f "$jsonl_file" ]; then
    tool_calls=$(grep -c '"type":"tool_use"' "$jsonl_file" || echo 0)
fi
```

**Option B: Use `num_turns` as proxy.** Each turn typically involves one or more tool calls. `num_turns` is available directly in the JSON output. Less precise but simpler. Given that the benchmark compares modes (not absolute tool call efficiency), `num_turns` may be sufficient.

**Recommendation:** Start with `num_turns` as the metric (Option B). Add JSONL parsing (Option A) in a later phase if more granular tool call data is needed. The JSONL path encoding has changed across Claude Code versions and is fragile to rely on.

### Ralph-Specific Metrics

For the `ralph` mode, the launcher prints iteration summaries to stderr:
```
Ralph: Iter 1 done (2m 15s) | Total: 2m 15s | phase:1|plan:1|status:Executing | exit=0
Ralph: Iter 2 done (1m 30s) | Total: 3m 45s | phase:1|plan:1|status:Complete | exit=0
```

The harness captures stderr to a log file and parses iteration count:
```bash
iterations=$(grep -c "^Ralph: Iter" "$stderr_log")
```

For `gsd-ralph` mode (Agent-based), iteration count is not applicable (single invocation with subagent).

## Data Flow: End-to-End Benchmark Run

```
bench-run.sh cc fix-bug
│
├─[1] Read challenge definition
│     jq '.starting_tag' challenges/fix-bug.json
│     → "bench/baseline"
│
├─[2] Reset working copy
│     bench-reset.sh fix-bug
│     ├── git checkout bench/baseline (in taskctl/)
│     ├── Verify file checksums
│     └── Return 0 (ready) or 1 (contaminated)
│
├─[3] Prepare mode-specific scaffolding
│     For CC mode: nothing extra
│     For GSD mode: assemble context file
│     For Ralph mode: scaffold .planning/, .claude/ into taskctl/
│     For gsd-ralph mode: scaffold .planning/, .claude/, commands
│
├─[4] Capture pre-run metrics
│     ├── shellcheck_before=$(shellcheck -f json src/*.sh | jq 'length')
│     ├── test_count_before=$(count existing tests)
│     └── start_epoch=$(date +%s)
│
├─[5] Invoke mode
│     source harness/lib/modes/cc.sh
│     json_output=$(invoke_cc "$prompt" "$workdir" "$max_turns" "$time_cap")
│     exit_code=$?
│
├─[6] Capture post-run metrics
│     ├── end_epoch=$(date +%s)
│     ├── wall_clock=$((end_epoch - start_epoch))
│     ├── tokens_in=$(echo "$json_output" | jq '.usage.input_tokens // 0')
│     ├── tokens_out=$(echo "$json_output" | jq '.usage.output_tokens // 0')
│     ├── num_turns=$(echo "$json_output" | jq '.num_turns // 0')
│     └── cost=$(echo "$json_output" | jq '.cost_usd // 0')
│
├─[7] Run correctness evaluation
│     eval_output=$(bench-eval.sh fix-bug "$workdir")
│     ├── correctness_score=$(echo "$eval_output" | jq '.correctness_score')
│     ├── regression_score=$(echo "$eval_output" | jq '.regression_score')
│     └── tests_added=$(echo "$eval_output" | jq '.tests_added')
│
├─[8] Capture code quality
│     ├── shellcheck_after=$(shellcheck -f json src/*.sh | jq 'length')
│     ├── shellcheck_delta=$((shellcheck_after - shellcheck_before))
│     ├── commits=$(git -C "$workdir" log --oneline bench/baseline..HEAD | wc -l)
│     └── conventional=$(check commit message format)
│
├─[9] Assemble result JSON
│     jq -n --arg mode "cc" --arg challenge "fix-bug" ... > result.json
│
└─[10] Write result file
      mv result.json results/cc-fix-bug-$(date +%s).json
```

## Data Flow: Report Generation

```
bench-report.sh --format markdown
│
├─[1] Discover result files
│     ls results/*.json
│
├─[2] Group by mode x challenge
│     jq '{mode, challenge}' each file
│
├─[3] Aggregate per group (mean, stddev)
│     For each group with N >= 3 results:
│     ├── mean_wall_clock, stddev_wall_clock
│     ├── mean_correctness, stddev_correctness
│     ├── mean_tokens, stddev_tokens
│     └── Flag if stddev > 30% of mean
│
├─[4] Compute derived metrics
│     ├── token_efficiency = correctness / total_tokens * 1000
│     ├── time_efficiency = correctness / wall_clock
│     └── quality_adjusted_speed = (correctness * regression) / wall_clock
│
└─[5] Generate REPORT.md
      ├── Summary table (all modes x all challenges)
      ├── Per-challenge detail sections
      ├── Statistical notes (high variance flags)
      └── Raw data reference (results/ directory)
```

## Architectural Patterns

### Pattern 1: Mode Abstraction Layer

**What:** Each execution mode is encapsulated in a single Bash file under `harness/lib/modes/`. All mode scripts export a single function (`invoke_<mode>`) with an identical signature.

**Why:** The harness (`bench-run.sh`) does not contain mode-specific logic. Adding a fifth mode means adding one file, not modifying the orchestrator.

**Contract:**
```bash
# All mode scripts must implement:
invoke_<mode>(prompt, workdir, max_turns, time_cap_seconds)
# Returns: JSON on stdout (from claude -p --output-format json)
# Side effects: modifies files in workdir (Claude's changes)
```

### Pattern 2: Declarative Challenge Definitions

**What:** Challenge parameters live in JSON files, not Bash variables or function arguments. The harness reads `challenges/<name>.json` to get prompt, git tag, time cap, and check script reference.

**Why:** Separates data from logic. A challenge definition can be validated with `jq`, displayed in reports, and extended with new fields without touching harness code.

### Pattern 3: Working Copy Isolation via Git Tags

**What:** Each benchmark run starts with `git checkout <tag>` in the `taskctl/` directory. The harness never modifies the `taskctl/` source tree permanently -- all runs start from a tagged state.

**Why:** Reproducibility. Every run of `cc fix-bug` starts from the identical file state. No leftover changes from previous runs can contaminate results.

**Implementation detail:** The harness does NOT use `--worktree` (Claude's git worktree flag). Instead, it operates on a clean checkout of the `taskctl/` directory. This is because:
- Git worktrees created by `claude -p --worktree` are at `<repo>/.claude/worktrees/<name>`, which is inside the gsd-ralph repo, not the taskctl project.
- The harness needs full control over the working directory lifecycle (create, validate, destroy).
- A simpler approach: `git checkout <tag>` in the taskctl directory, or `git worktree add` managed by the harness itself.

**Recommended: harness-managed worktree per run.**
```bash
# bench-reset.sh creates an isolated worktree for each run
worktree_path="$BENCH_TMPDIR/run-${mode}-${challenge}-${timestamp}"
git -C "$TASKCTL_ROOT" worktree add "$worktree_path" "$starting_tag" --detach
```

This lets the harness run multiple challenges concurrently without conflicts, and cleanup is simply `git worktree remove`.

### Pattern 4: Defensive Metric Extraction

**What:** All jq extractions use `// 0` or `// "unknown"` fallbacks. Never assume a JSON field exists.

**Why:** Claude Code's JSON output structure has evolved. Fields may be added, renamed, or nested differently across versions. The harness must produce results even if some metrics are unavailable.

```bash
# Safe extraction pattern
tokens_in=$(echo "$json" | jq -r '.usage.input_tokens // .input_tokens // 0')
```

### Pattern 5: GSD Scaffolding for Ralph Modes

**What:** Modes 3 (Ralph) and 4 (gsd-ralph) require GSD project structure. The harness generates minimal GSD artifacts (STATE.md, config.json, PLAN.md) that frame the challenge prompt within GSD conventions.

**Why:** Ralph mode reads STATE.md for progress detection. Without GSD scaffolding, the launcher would fail at startup. The scaffolding is minimal -- just enough to satisfy the launcher's prerequisites.

**The scaffolding is challenge-specific.** Each challenge has its own PLAN.md content that wraps the challenge prompt in GSD task format:

```markdown
# Phase 1: Benchmark Challenge

## Tasks

### Task 1: [Challenge prompt here]
- [ ] [The actual challenge prompt from challenges/<name>.json]

## Success Criteria
- All correctness checks pass
```

## Anti-Patterns

### Anti-Pattern 1: Modifying ralph-launcher.sh for Benchmarking

**What goes wrong:** Adding benchmark-specific flags or metric hooks to the production launcher.
**Why it's wrong:** The launcher is the thing being benchmarked. Modifying it to support benchmarking changes its behavior, invalidating the results.
**Do this instead:** The harness wraps the launcher externally. It captures stdout/stderr, measures wall clock time from outside, and parses JSON output after the fact.

### Anti-Pattern 2: Using Claude Code's Worktree Flag for Isolation

**What goes wrong:** Passing `--worktree` to `claude -p` inside the harness.
**Why it's wrong:** Claude's worktree is relative to the CWD's git repo, not the challenge project. If running from the gsd-ralph repo, the worktree is created at `gsd-ralph/.claude/worktrees/<name>`, not inside `taskctl/`. Additionally, the harness needs to control the worktree lifecycle for pre/post metric capture.
**Do this instead:** Use harness-managed `git worktree add` with the taskctl repo as the source.

### Anti-Pattern 3: Sharing Working Directory Across Runs

**What goes wrong:** Running `bench-run.sh cc fix-bug` twice without resetting between runs.
**Why it's wrong:** The second run starts from Claude's modified state, not the baseline. Results are not comparable.
**Do this instead:** `bench-run.sh` always calls `bench-reset.sh` first. The reset step is mandatory, not optional.

### Anti-Pattern 4: Relying on Session JSONL for Primary Metrics

**What goes wrong:** Parsing `~/.claude/projects/<path>/sessions/<id>.jsonl` for token counts.
**Why it's wrong:** The encoded path format has changed across Claude Code versions. The JSONL structure is internal and undocumented. Files may not exist if `--no-session-persistence` is used.
**Do this instead:** Use the `--output-format json` response for primary metrics (tokens, turns, cost). Reserve JSONL parsing as an optional secondary source.

## Git Tag Management

The challenge project requires two git tags:

| Tag | State | Created When |
|-----|-------|-------------|
| `bench/baseline` | taskctl with planted bug, ugly format, missing tests | After initial taskctl build |
| `bench/after-delete` | taskctl with `delete` command added (Challenge 2 complete) | After manually completing Challenge 2 |

**Creating `bench/after-delete`:** This is a chicken-and-egg problem. Challenge 5 starts from a state where Challenge 2 is already done. The tag must be created manually (or by running Challenge 2 once and tagging the result). This is a one-time setup step documented in the harness README.

**Tag scope:** Tags are on the gsd-ralph repo (since taskctl lives inside it), not a separate repo. The harness uses `git checkout <tag> -- benchmarks/taskctl/` to reset only the challenge project, not the entire gsd-ralph repo.

Wait -- this is wrong. `git checkout <tag> -- benchmarks/taskctl/` would check out the taskctl directory at that tag's state. But if the benchmarks are still being built when the tag is created, the tag won't have the final harness code.

**Corrected approach:** The `bench/baseline` and `bench/after-delete` tags capture the state of `benchmarks/taskctl/` only. The harness operates on a temporary copy:

```bash
# bench-reset.sh
workdir=$(mktemp -d)
git show "bench/baseline:benchmarks/taskctl" | ... # Doesn't work for directories

# Better: use git archive
git archive "$starting_tag" -- benchmarks/taskctl/ | tar x -C "$workdir" --strip-components=2
```

**Recommended approach:** Use `git worktree add` from the main repo at the specified tag, then operate within the `benchmarks/taskctl/` subdirectory of that worktree. This preserves the full git state while isolating the working copy.

```bash
# bench-reset.sh
run_worktree="$BENCH_TMPDIR/run-${run_id}"
git worktree add "$run_worktree" "$starting_tag" --detach 2>/dev/null
workdir="$run_worktree/benchmarks/taskctl"
# Validate
if [ ! -f "$workdir/src/taskctl.sh" ]; then
    echo "ERROR: taskctl not found at tag $starting_tag" >&2
    return 1
fi
```

## Build Order (Suggested Phase Structure)

### Phase 1: Challenge Project (`taskctl`)

Build the Bash CLI tool with all its planted defects and partial tests. Tag as `bench/baseline`. This is the foundation that everything else tests against.

**Deliverables:**
- Complete `taskctl` source (src/, commands/, storage, format)
- Bats tests for add and list
- Planted bug in done.sh (off-by-one on task ID)
- Sample data file
- `bench/baseline` git tag
- CLAUDE.md and README.md for the project

**Dependencies:** None. This is a standalone Bash CLI.

**Why first:** Everything else depends on having a real challenge project to benchmark against. The checks, harness, and modes all operate on taskctl.

### Phase 2: Correctness Checks + Evaluation Script

Build `bench-eval.sh` and all five check scripts in `harness/lib/checks/`. These must work before the harness can produce meaningful results.

**Deliverables:**
- `harness/lib/checks/fix-bug.sh` through `multi-file.sh`
- `harness/bench-eval.sh` (dispatcher)
- Challenge definition JSON files in `challenges/`
- `harness/lib/common.sh` (shared utilities)

**Dependencies:** Phase 1 (needs taskctl to validate checks against)

**Why second:** Correctness checks are the foundation of trustworthy results. You need to manually verify that the checks pass/fail correctly before automating runs. Run checks against the baseline (should produce expected failures) and against a hand-fixed version (should pass).

**Includes `bench/after-delete` tag creation:** Manually complete Challenge 2 (add delete command) on a branch, tag it, and verify Challenge 5's checks work against that state.

### Phase 3: Harness Core + CC Mode

Build `bench-reset.sh`, `bench-run.sh`, `harness/lib/metrics.sh`, and the CC mode script. This is the minimum viable harness -- one mode producing real results.

**Deliverables:**
- `harness/bench-reset.sh` (git worktree management, state validation)
- `harness/bench-run.sh` (orchestrator)
- `harness/lib/metrics.sh` (JSON output parsing)
- `harness/lib/modes/cc.sh`
- Result JSON files in `results/`

**Dependencies:** Phase 2 (needs eval + checks)

**Why third:** The CC mode is the simplest invocation (direct `claude -p`). Getting end-to-end flow working with one mode validates the entire harness architecture before adding more complex modes.

### Phase 4: Remaining Modes (GSD, Ralph, gsd-ralph)

Add the three remaining mode scripts. Each builds on the harness infrastructure from Phase 3.

**Deliverables:**
- `harness/lib/modes/gsd.sh` (GSD context assembly)
- `harness/lib/modes/ralph.sh` (launcher integration + GSD scaffolding)
- `harness/lib/modes/gsd-ralph.sh` (Agent-based + GSD/command scaffolding)
- GSD scaffolding templates for Ralph modes

**Dependencies:** Phase 3 (needs working harness)

**Sub-ordering within Phase 4:**
1. `gsd.sh` first -- adds context file assembly, no GSD scaffolding needed
2. `ralph.sh` second -- adds GSD scaffolding and launcher integration
3. `gsd-ralph.sh` third -- most complex, needs commands + skills + scaffolding

### Phase 5: Report Generator + Full Benchmark Runs

Build `bench-report.sh`, run all 4 modes x 5 challenges x 3 repetitions, and generate the comparison report.

**Deliverables:**
- `harness/bench-report.sh` (aggregation, markdown generation)
- At least 60 result JSON files (4 modes x 5 challenges x 3 runs)
- `REPORT.md` (generated comparison report)
- Statistical validity checks (stddev flags)

**Dependencies:** Phase 4 (needs all modes)

**Why last:** The report is the capstone. Running all benchmarks is the longest step (60 runs x ~10-20 min each = ~10-20 hours of compute). Report generation is fast; data collection is slow.

## Sources

- [Claude Code Headless Mode / Agent SDK CLI](https://code.claude.com/docs/en/headless) -- `--output-format json` fields, `--no-session-persistence`, `--max-turns`
- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference) -- all flags including `--allowedTools`, `--worktree`, `--append-system-prompt-file`
- [Claude Code Session File Format](https://kentgigger.com/posts/claude-code-conversation-history) -- JSONL structure, token usage per turn
- [ShellCheck Integration](https://github.com/koalaman/shellcheck/blob/master/shellcheck.1.md) -- `-f json` for machine-readable output
- Existing gsd-ralph codebase: `ralph-launcher.sh` (loop engine, `build_claude_command`, `--output-format json`), `assemble-context.sh`, `ralph-hook.sh`, `test_helper/ralph-helpers.bash` (mock patterns)

---
*Architecture research for: gsd-ralph v2.2 Execution Mode Benchmarking Suite*
*Researched: 2026-03-11*
