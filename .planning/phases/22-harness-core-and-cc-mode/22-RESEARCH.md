# Phase 22: Harness Core and CC Mode - Research

**Researched:** 2026-03-11
**Domain:** Benchmark harness pipeline (worktree isolation, metric capture, time-cap enforcement, CC mode invocation)
**Confidence:** HIGH

## Summary

Phase 22 builds the end-to-end benchmark pipeline that takes a mode name and challenge name as input and produces a structured JSON result file as output. The pipeline has six stages: (1) create an isolated git worktree from the challenge's starting tag, (2) optionally scaffold mode-specific artifacts, (3) capture pre-run metrics, (4) invoke the mode under a time cap, (5) run correctness evaluation via the existing bench-eval.sh, and (6) assemble and write the result JSON. This phase validates the entire architecture using only CC mode (the simplest: a single `claude -p` invocation), deferring the three more complex modes to Phase 23.

The infrastructure from Phases 20-21 is solid: 5 challenge JSON definitions with declarative schemas, 5 behavioral check scripts using the eval-based `check()` helper, reference solutions for positive controls, and `bench-eval.sh` as the evaluation driver. Phase 22 builds on top of this by adding the harness orchestration scripts (`bench-reset.sh`, `bench-run.sh`), the mode abstraction layer (`lib/modes/cc.sh`), metric extraction helpers, and a common library. The result JSON schema is well-defined in BENCHMARK-MILESTONE.md.

**Primary recommendation:** Build three scripts in dependency order: `bench-reset.sh` (worktree isolation + validation), `lib/modes/cc.sh` (CC mode invocation with `claude -p --output-format json`), then `bench-run.sh` (orchestrator that wires reset -> invoke -> eval -> result JSON). Use `git worktree add --detach` for per-run isolation, `timeout` for time cap enforcement, and defensive jq extraction with `// 0` fallbacks for all metric fields.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| HARN-01 | `bench-reset.sh` creates isolated git worktree per run with `git clean -fdx` and checksum verification | Git worktree verified working on this system with `bench/baseline` tag; `git worktree add --detach` creates correct file structure at `benchmarks/taskctl/` subdirectory |
| HARN-02 | `bench-run.sh` orchestrates the full pipeline: reset -> scaffold -> invoke -> capture metrics -> eval -> write result JSON | Architecture pattern documented below; 10-step data flow from prior research validated |
| HARN-04 | Mode abstraction layer (`lib/modes/*.sh`) provides identical function contracts across all modes | Function signature `mode_invoke(prompt, workdir, max_turns, time_cap_seconds)` with JSON on stdout; CC mode is the reference implementation |
| HARN-06 | Time caps per challenge are enforced by the harness as safety valves | GNU `timeout` available at `/opt/homebrew/bin/timeout`; challenge JSON has `time_cap_minutes` field; convert to seconds for `timeout` |
| HARN-07 | Each run produces a structured JSON result file in `benchmarks/results/` | Result schema from BENCHMARK-MILESTONE.md with 15 fields; `jq -n` assembles the file; filename pattern `{mode}-{challenge}-{run_id}.json` |
| MODE-01 | CC mode invokes `claude -p` directly with `--output-format json` | Claude Code CLI 2.1.72 verified; `--output-format json` returns `type`, `result`, `session_id`, `total_cost_usd`, `duration_ms`, `duration_api_ms`, `num_turns`, `is_error`, `subtype` fields |
| METR-01 | Wall-clock time, token counts (input + output), and correctness score captured per run | Wall-clock via `date +%s` start/end delta; token counts NOT in `--output-format json` top-level (see Token Strategy below); correctness from bench-eval.sh score parsing |
| STAT-03 | Every result includes reproducible identity: run_id, model version, CLI version, git SHA | `run_id` via UUID generation; `claude --version` for CLI version; `git rev-parse HEAD` for SHA; model version hardcoded or extracted from JSON output |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2.57 | Harness scripts | Same as all gsd-ralph scripts; Bash 3.2 compatibility required |
| jq | 1.8.1 | JSON parsing, metric extraction, result assembly | Already project dependency; has `sqrt`, `group_by` for future stats |
| Git | 2.x | Worktree isolation per run | `git worktree add --detach` verified on this system |
| GNU timeout | 9.10 | Time cap enforcement | Available at `/opt/homebrew/bin/timeout` via Homebrew coreutils |
| Claude Code CLI | 2.1.72 | CC mode execution | `claude -p --output-format json` for headless invocation |
| ShellCheck | 0.11.0 | Code quality delta metric | Optional; already installed |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Bats | 1.13.0 (vendored) | Challenge project tests run by check scripts | Already used by bench-eval.sh and check scripts from Phase 21 |
| bc | macOS built-in | Floating-point division for derived metrics | When computing correctness_score percentage from pass/fail counts |
| uuidgen | macOS built-in | Generate run_id for result identity | One call per bench-run.sh invocation |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `git worktree add` | `git archive \| tar x` | Worktree preserves full git state (tags, log); archive loses git metadata needed by check scripts that reference `bench/baseline` |
| GNU `timeout` | Bash `SIGALRM` trap | `timeout` is simpler and more reliable; trap-based approach has edge cases with subprocesses |
| `jq -n` for result JSON | `printf` with heredoc | jq handles escaping and type correctness; printf requires manual quoting |

**Installation:**
```bash
# Nothing to install. All tools already present on this system.
# Verify:
bash --version | head -1       # GNU bash, version 3.2.57
jq --version                   # jq-1.8.1
timeout --version | head -1    # timeout (GNU coreutils) 9.10
claude --version               # 2.1.72 (Claude Code)
uuidgen                        # generates UUID
```

## Architecture Patterns

### Recommended Project Structure
```
benchmarks/
  harness/
    bench-reset.sh              # Worktree creation + state validation
    bench-run.sh                # Orchestrator: reset -> invoke -> eval -> result
    bench-eval.sh               # [EXISTS] Correctness evaluation driver
    lib/
      common.sh                 # Constants, logging, jq helpers, path resolution
      metrics.sh                # Parse claude -p JSON output, extract metrics
      modes/
        cc.sh                   # CC mode: direct claude -p invocation
  challenges/
    *.json                      # [EXISTS] 5 challenge definitions
    checks/
      check-*.sh                # [EXISTS] 5 check scripts
  results/                      # Output directory for result JSON files (gitignored)
  BENCHMARK-MILESTONE.md        # [EXISTS] PRD
```

### Pattern 1: Mode Abstraction Layer
**What:** Each execution mode lives in a single file under `harness/lib/modes/`. All mode scripts export a function with an identical signature.
**When to use:** Every mode invocation goes through this contract.
**Contract:**
```bash
# harness/lib/modes/cc.sh
# All mode scripts must implement:
# mode_invoke(prompt, workdir, max_turns, time_cap_seconds)
#   - stdout: JSON from claude -p --output-format json (or equivalent)
#   - stderr: mode-specific logs (captured by orchestrator)
#   - exit code: 0 = normal completion, 124 = timeout, other = error
#   - side effects: modifies files in workdir
mode_invoke() {
    local prompt="$1"
    local workdir="$2"
    local max_turns="$3"
    local time_cap_seconds="$4"

    timeout "$time_cap_seconds" \
        claude -p "$prompt" \
        --output-format json \
        --max-turns "$max_turns" \
        --permission-mode auto \
        --no-session-persistence \
        2>"$workdir/.bench-stderr.log"
}
```

**Key decisions for CC mode:**
- `--permission-mode auto` (not `--dangerously-skip-permissions`) -- auto-approves tools while maintaining safety
- `--no-session-persistence` prevents session files from accumulating during benchmark runs
- `timeout` wraps the entire command; exit code 124 means time cap hit
- stderr redirected to a file in the workdir for post-run debugging
- No `--worktree` flag -- the harness manages worktree isolation, not Claude

### Pattern 2: Harness-Managed Git Worktree Isolation
**What:** Each benchmark run creates an isolated git worktree at a temp path, operates entirely within it, and cleans up after.
**When to use:** Every `bench-run.sh` invocation.
**Example:**
```bash
# bench-reset.sh
create_run_worktree() {
    local run_id="$1"
    local starting_tag="$2"
    local worktree_path="${BENCH_TMPDIR:-/tmp}/bench-run-${run_id}"

    # Create detached worktree at the challenge starting tag
    git -c advice.detachedHead=false worktree add --detach \
        "$worktree_path" "$starting_tag" 2>/dev/null

    local workdir="$worktree_path/benchmarks/taskctl"

    # Validate starting state
    if [[ ! -f "$workdir/src/taskctl.sh" ]]; then
        echo "ERROR: taskctl not found at tag $starting_tag" >&2
        return 1
    fi

    # Clean any untracked files (safety)
    git -C "$worktree_path" clean -fdx 2>/dev/null

    echo "$workdir"
}

cleanup_run_worktree() {
    local run_id="$1"
    local worktree_path="${BENCH_TMPDIR:-/tmp}/bench-run-${run_id}"
    git worktree remove --force "$worktree_path" 2>/dev/null || true
}
```

**Why not Claude's `--worktree` flag:** Claude's worktree is relative to the CWD's git repo (creates at `<repo>/.claude/worktrees/<name>`). The harness needs worktrees rooted at the `bench/baseline` tag state, which includes the full repo. The harness must control the worktree lifecycle for pre/post metric capture and cleanup.

**Verified:** `git worktree add --detach /tmp/test-bench-worktree bench/baseline` successfully creates a worktree with `benchmarks/taskctl/src/taskctl.sh` accessible. Cleanup via `git worktree remove` works.

### Pattern 3: Defensive Metric Extraction
**What:** All jq extractions use `// 0` or `// "unknown"` fallbacks. Never assume a JSON field exists.
**When to use:** Every metric extraction from claude -p JSON output.
**Example:**
```bash
# harness/lib/metrics.sh
extract_metrics() {
    local json_file="$1"

    # Validate JSON is parseable
    if ! jq empty "$json_file" 2>/dev/null; then
        echo '{"error": "invalid_json"}'
        return 1
    fi

    jq '{
        session_id: (.session_id // "unknown"),
        total_cost_usd: (.total_cost_usd // 0),
        duration_ms: (.duration_ms // 0),
        duration_api_ms: (.duration_api_ms // 0),
        num_turns: (.num_turns // 0),
        is_error: (.is_error // false),
        result_text: (.result // "")
    }' "$json_file"
}
```

### Pattern 4: Time Cap as Safety Valve with Partial Result Capture
**What:** Time caps terminate runs but always produce a result file (even for timed-out or failed runs).
**When to use:** Every bench-run.sh invocation.
**Example:**
```bash
# In bench-run.sh orchestrator
local invoke_exit=0
local json_output
json_output=$(mode_invoke "$prompt" "$workdir" "$max_turns" "$time_cap_seconds" 2>"$stderr_log") || invoke_exit=$?

local timed_out=false
if [[ $invoke_exit -eq 124 ]]; then
    timed_out=true
fi

# Always run evaluation, even on timeout (capture partial progress)
local eval_exit=0
local eval_output
eval_output=$(bash "$HARNESS_DIR/bench-eval.sh" "$challenge" "$workdir" 2>/dev/null) || eval_exit=$?
```

### Pattern 5: Orchestrator Data Flow (10-step pipeline)
**What:** `bench-run.sh` follows a strict linear pipeline.
**Steps:**
1. Parse arguments (`--mode cc --challenge fix-bug`)
2. Load challenge JSON definition
3. Generate run_id (`uuidgen | tr '[:upper:]' '[:lower:]'`)
4. Create isolated worktree via `bench-reset.sh`
5. Capture pre-run metrics (shellcheck count, test count, git SHA)
6. Invoke mode via `lib/modes/cc.sh`
7. Capture post-run metrics (wall-clock delta, claude JSON fields)
8. Run correctness evaluation via `bench-eval.sh`
9. Assemble result JSON via `jq -n`
10. Write to `results/{mode}-{challenge}-{run_id}.json`, cleanup worktree

### Anti-Patterns to Avoid
- **Modifying ralph-launcher.sh for benchmarking:** The launcher is being benchmarked. Changing it invalidates results. The harness wraps it externally.
- **Using Claude's `--worktree` flag:** Creates worktree in the wrong location (gsd-ralph repo, not challenge project state).
- **Sharing working directory across runs:** Second run starts from Claude's modified state, not baseline. Each run MUST get a fresh worktree.
- **Relying on JSONL session files for primary metrics:** `--no-session-persistence` prevents JSONL creation. Even without it, the path encoding is fragile across CLI versions.
- **Using `--dangerously-skip-permissions`:** `--permission-mode auto` is safer and sufficient for benchmark runs. Avoids writing to unauthorized locations.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Run isolation | Custom rsync/cp of challenge files | `git worktree add --detach` | Preserves full git state including tags and reflog; atomic create/delete; proven reliable |
| Time cap enforcement | Bash background process + sleep + kill | GNU `timeout` command | Handles signal propagation to child processes correctly; exit code 124 distinguishes timeout from error |
| UUID generation | `date +%s`-based IDs or random strings | `uuidgen` (macOS built-in) | Guaranteed unique; standard format; no collision risk across parallel runs |
| JSON assembly | `printf` with string interpolation | `jq -n --arg/--argjson` | Handles escaping, type correctness, nested structures; no quoting bugs |
| JSON validation | `grep` for field presence | `jq -e '.field'` or `jq empty` | Validates structure, not just string presence; catches malformed JSON |
| Floating-point math | Bash arithmetic `$((...))` | `bc` or jq | Bash has no floating-point support; integer-only leads to wrong results for percentages |

**Key insight:** The harness is orchestration glue. Every non-trivial operation has a proven tool. The only custom logic is the pipeline wiring itself.

## Common Pitfalls

### Pitfall 1: Token Counts Not in `--output-format json` Top Level
**What goes wrong:** The `--output-format json` response from Claude Code CLI 2.1.72 does NOT include `usage.input_tokens` or `usage.output_tokens` at the top level. The available fields are: `type`, `subtype`, `result`, `session_id`, `total_cost_usd`, `is_error`, `duration_ms`, `duration_api_ms`, `num_turns`.
**Why it happens:** The CLI JSON output is a session-level summary, not a per-message breakdown. Token counts are available only via `--output-format stream-json` (streaming events) or JSONL session files.
**How to avoid:** For Phase 22, use `num_turns` as the primary efficiency proxy and `total_cost_usd` as the cost signal. These are directly available. Do NOT promise exact input/output token counts in the result schema. Instead, use `num_turns` and `total_cost_usd` as the efficiency metrics, and add `tokens_input`/`tokens_output` fields with value `null` or `0` with a note that they require stream-json parsing (deferred).
**Warning signs:** jq extraction returning 0 for token fields; result JSON showing 0 tokens but non-zero cost.

### Pitfall 2: `timeout` Exit Code Masking Claude's Exit Code
**What goes wrong:** When `timeout` kills `claude -p`, the exit code is 124 (timeout's signal code), not claude's exit code. If timeout does NOT fire, the exit code is claude's actual exit code. Code that checks for specific claude exit codes must first check for 124.
**Why it happens:** `timeout` replaces the child process's exit code with its own signal code.
**How to avoid:** Check for exit code 124 first (timeout), then handle other exit codes. Record `timed_out: true/false` in the result JSON.
**Warning signs:** Runs that hit time cap showing unexpected exit codes; timeout not being detected.

### Pitfall 3: Worktree Path Inside the Main Repo's .gitignore Scope
**What goes wrong:** If worktree paths are created inside the gsd-ralph repo directory (e.g., `benchmarks/.worktrees/`), they may be affected by the repo's `.gitignore` rules.
**Why it happens:** Git worktrees inherit the parent repo's `.gitignore`.
**How to avoid:** Create worktrees in `/tmp/` or a directory outside the repo. Use `BENCH_TMPDIR` environment variable defaulting to `/tmp`.
**Warning signs:** Files missing from worktree that should be there; git operations behaving unexpectedly.

### Pitfall 4: Check Scripts Expecting Repo-Relative Paths
**What goes wrong:** The existing check scripts from Phase 21 use paths like `$TASKCTL_DIR/../../tests/bats/bin/bats` to find the vendored Bats binary. In a worktree, these relative paths resolve differently if the worktree structure differs.
**Why it happens:** The check scripts assume they are running inside the main repo checkout. In a worktree at `/tmp/bench-run-xxx/`, the Bats binary is at `/tmp/bench-run-xxx/tests/bats/bin/bats`.
**How to avoid:** The worktree is a full checkout of the repo at the tag, so `$TASKCTL_DIR/../../tests/bats/bin/bats` resolves to `/tmp/bench-run-xxx/tests/bats/bin/bats`, which exists. Verify this resolution is correct. If not, pass BATS_BIN explicitly to bench-eval.sh.
**Warning signs:** "bats not found" errors when running in worktree; check scripts falling back to global bats.

### Pitfall 5: Claude Modifying Files Outside benchmarks/taskctl/ in the Worktree
**What goes wrong:** Claude has access to the entire worktree (the full repo at the tag state), not just `benchmarks/taskctl/`. It could modify files in `lib/`, `scripts/`, or other directories.
**Why it happens:** `claude -p` operates in whatever directory it's launched from. If launched from the worktree root, Claude can access everything.
**How to avoid:** `cd` into `benchmarks/taskctl/` before invoking `claude -p`. This makes the taskctl directory Claude's working directory, limiting its default scope. The `--add-dir` flag should NOT be used to expose parent directories.
**Warning signs:** Claude making changes outside `benchmarks/taskctl/`; git diff showing unexpected file modifications.

### Pitfall 6: bench-eval.sh Score Parsing
**What goes wrong:** The existing `bench-eval.sh` outputs human-readable text (`Score: 3/3 checks passed`), not structured JSON. The orchestrator needs to parse this to extract `correctness_score`.
**Why it happens:** bench-eval.sh was designed for human consumption in Phase 21, not machine consumption.
**How to avoid:** Parse the `Score: X/Y` line from bench-eval.sh output using grep/sed. Compute `correctness_score = (X/Y) * 100`. Or modify bench-eval.sh to optionally output JSON (add a `--json` flag). The simpler approach is parsing since the format is stable and well-defined.
**Warning signs:** Score extraction returning empty or wrong values; format changes in bench-eval.sh breaking the parser.

## Code Examples

Verified patterns from this project and official sources.

### Result JSON Assembly
```bash
# Assemble the complete result JSON using jq -n
# All --arg values are strings; --argjson for numbers/booleans
assemble_result() {
    jq -n \
        --arg mode "$mode" \
        --arg challenge "$challenge" \
        --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg run_id "$run_id" \
        --argjson wall_clock_seconds "$wall_clock" \
        --argjson tokens_input 0 \
        --argjson tokens_output 0 \
        --argjson num_turns "$num_turns" \
        --argjson iterations 1 \
        --argjson human_interventions 0 \
        --argjson correctness_score "$correctness_score" \
        --argjson regression_score "$regression_score" \
        --argjson tests_added "$tests_added" \
        --argjson shellcheck_warnings_delta "$shellcheck_delta" \
        --argjson commits "$commit_count" \
        --argjson conventional_commits "$conventional" \
        --argjson timed_out "$timed_out" \
        --arg session_id "$session_id" \
        --argjson total_cost_usd "$cost_usd" \
        --argjson duration_ms "$duration_ms" \
        --arg model_version "claude-opus-4-20250514" \
        --arg cli_version "$cli_version" \
        --arg git_sha "$git_sha" \
        '{
            mode: $mode,
            challenge: $challenge,
            timestamp: $timestamp,
            run_id: $run_id,
            wall_clock_seconds: $wall_clock_seconds,
            tokens_input: $tokens_input,
            tokens_output: $tokens_output,
            num_turns: $num_turns,
            iterations: $iterations,
            human_interventions: $human_interventions,
            correctness_score: $correctness_score,
            regression_score: $regression_score,
            tests_added: $tests_added,
            shellcheck_warnings_delta: $shellcheck_warnings_delta,
            commits: $commits,
            conventional_commits: $conventional_commits,
            timed_out: $timed_out,
            session_id: $session_id,
            total_cost_usd: $total_cost_usd,
            duration_ms: $duration_ms,
            model_version: $model_version,
            cli_version: $cli_version,
            git_sha: $git_sha
        }'
}
```

### Score Parsing from bench-eval.sh
```bash
# Parse "Score: X/Y checks passed" from bench-eval.sh output
parse_eval_score() {
    local eval_output="$1"
    local passed total

    # Extract "Score: X/Y" line
    local score_line
    score_line=$(echo "$eval_output" | grep -E '^Score: [0-9]+/[0-9]+')

    if [[ -z "$score_line" ]]; then
        echo "0"
        return
    fi

    passed=$(echo "$score_line" | grep -oE '[0-9]+' | head -1)
    total=$(echo "$score_line" | grep -oE '[0-9]+' | tail -1)

    if [[ "$total" -eq 0 ]]; then
        echo "0"
        return
    fi

    # Compute percentage (integer)
    echo $(( (passed * 100) / total ))
}
```

### Pre-Run ShellCheck Baseline
```bash
# Capture ShellCheck warning count before Claude makes changes
capture_shellcheck_baseline() {
    local workdir="$1"
    if command -v shellcheck >/dev/null 2>&1; then
        local count
        count=$(shellcheck -f json "$workdir/src/"*.sh "$workdir/src/commands/"*.sh 2>/dev/null | jq 'length' 2>/dev/null) || count=0
        echo "${count:-0}"
    else
        echo "null"
    fi
}
```

### Commit Counting and Conventional Commit Check
```bash
# Count commits made by Claude relative to the starting tag
count_commits() {
    local worktree_path="$1"
    local starting_tag="$2"
    git -C "$worktree_path" log --oneline "${starting_tag}..HEAD" 2>/dev/null | wc -l | tr -d ' '
}

# Check if all commits follow conventional commit format
check_conventional_commits() {
    local worktree_path="$1"
    local starting_tag="$2"
    local total bad
    total=$(git -C "$worktree_path" log --oneline "${starting_tag}..HEAD" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$total" -eq 0 ]]; then
        echo "true"
        return
    fi

    # Match conventional commit pattern: type(scope): message or type: message
    bad=$(git -C "$worktree_path" log --format='%s' "${starting_tag}..HEAD" 2>/dev/null \
        | grep -cvE '^(feat|fix|chore|docs|test|refactor|style|perf|build|ci)(\(.+\))?: .+' || echo 0)

    if [[ "$bad" -eq 0 ]]; then
        echo "true"
    else
        echo "false"
    fi
}
```

## Token Capture Strategy

**Problem:** The Claude Code CLI `--output-format json` does NOT include per-token breakdowns (`input_tokens`, `output_tokens`) in the result object. Available fields are `total_cost_usd`, `duration_ms`, `num_turns`, and `session_id`.

**Phase 22 approach (recommended):**
1. Capture `num_turns` and `total_cost_usd` as primary efficiency metrics -- these are directly available
2. Set `tokens_input` and `tokens_output` to `0` in the result JSON with a comment that exact token counts require `stream-json` parsing
3. Use `total_cost_usd` as the cost metric (directly comparable across modes since all use the same model)
4. Use `num_turns` as the interaction complexity metric

**Future enhancement (Phase 24 or later):**
- Switch to `--output-format stream-json` and pipe through a post-processor that counts `tool_use` events and sums token usage from individual message events
- This adds complexity but gives exact numbers

**Why this is acceptable for Phase 22:** The goal is proving the pipeline works end-to-end. `num_turns` and `total_cost_usd` are sufficient to demonstrate metric capture. The result schema captures the fields; the values can be refined later without changing the schema.

## Time Cap Enforcement Strategy

**Tool:** GNU `timeout` (available at `/opt/homebrew/bin/timeout`, version 9.10)

**Behavior:**
- `timeout Ns command` runs `command` with a time limit of N seconds
- If the command finishes within N seconds, exit code is the command's exit code
- If the time limit is exceeded, `timeout` sends SIGTERM (then SIGKILL after grace period), exit code is 124
- The challenge JSON has `time_cap_minutes`; convert to seconds: `time_cap_seconds=$((time_cap_minutes * 60))`

**Edge case -- timeout vs max-turns:**
- `--max-turns` limits conversation turns; exit is non-zero when limit reached
- `timeout` limits wall-clock time; exit code 124
- Both can trigger independently. The harness should:
  1. Check for exit code 124 first (timeout)
  2. Then check for non-zero (max-turns or error)
  3. Always run eval regardless (capture partial progress)

**Max turns setting for CC mode:**
- For challenges with 10-minute cap: `--max-turns 50` (generous; most challenges complete in < 20 turns)
- The challenge JSON does NOT have a `max_turns` field -- use a default from common.sh (e.g., 50)

## Reproducible Identity Fields (STAT-03)

Every result JSON must include fields that uniquely identify the run environment:

| Field | How to Capture | Example |
|-------|---------------|---------|
| `run_id` | `uuidgen \| tr '[:upper:]' '[:lower:]'` | `a3b4c5d6-e7f8-9012-3456-789abcdef012` |
| `model_version` | Hardcode or extract from stream-json | `claude-opus-4-20250514` |
| `cli_version` | `claude --version 2>/dev/null` | `2.1.72` |
| `git_sha` | `git rev-parse HEAD` (main repo, not worktree) | `9f31b9d` |
| `timestamp` | `date -u +%Y-%m-%dT%H:%M:%SZ` | `2026-03-11T10:00:00Z` |

**Note on model_version:** The `--output-format json` response does not include the model name. Options:
1. Hardcode to `claude-opus-4-20250514` (known current model for Claude Code)
2. Use `--output-format stream-json` to capture the model field from init events (more complex)
3. Set as a configurable default in common.sh

Recommendation: hardcode in common.sh with a `BENCH_MODEL_VERSION` variable. Update manually when the model changes.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `--worktree` for isolation | Harness-managed `git worktree add` | Phase 22 design | Full control over worktree lifecycle; worktree at correct tag state |
| Parse JSONL for token counts | Use `num_turns` + `total_cost_usd` from JSON | Phase 22 | Simpler extraction; JSONL parsing deferred as enhancement |
| `--dangerously-skip-permissions` | `--permission-mode auto` | Claude Code 2.1+ | Safer; auto-approves tools without bypassing all safety |
| Single shared working directory | Fresh worktree per run | Phase 22 design | Eliminates cross-run contamination; enables distinct run_id |

**Deprecated/outdated:**
- `--output-format json` field names have evolved: older versions used `cost_usd` not `total_cost_usd`. Use defensive extraction with fallbacks.
- The `--max-turns` flag documentation says "exits with an error when the limit is reached" -- this means non-zero exit code, same as what ralph-launcher.sh handles.

## Open Questions

1. **Exact model_version string**
   - What we know: Claude Code uses Claude Opus 4 (as of 2026-03-11)
   - What's unclear: The exact model string (e.g., `claude-opus-4-20250514` vs `claude-opus-4-6`) is not in the `--output-format json` response
   - Recommendation: Hardcode as configurable constant. Verify by running one actual `--output-format stream-json` test during Phase 22 implementation if feasible.

2. **Whether `--permission-mode auto` is sufficient for all challenge types**
   - What we know: auto mode auto-approves tool use. CC mode needs Read, Edit, Write, Bash, Grep, Glob.
   - What's unclear: Whether `auto` mode allows ALL these tools or just a subset
   - Recommendation: Use `--permission-mode auto` as primary. If it blocks tools, fall back to `--allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)"` which matches ralph-launcher.sh's DEFAULT_ALLOWED_TOOLS.

3. **Score parsing robustness from check scripts**
   - What we know: Check scripts output `Score: X/Y checks passed` on their last line
   - What's unclear: Whether any check script outputs additional text after the Score line that could confuse parsing
   - Recommendation: Use `grep -E '^Score:'` which anchors to line start. Test against all 5 check scripts during implementation.

## Sources

### Primary (HIGH confidence)
- Claude Code CLI 2.1.72 `--help` output -- all flags verified locally
- Claude Code CLI Reference (https://code.claude.com/docs/en/cli-reference) -- `--output-format`, `--max-turns`, `--permission-mode`, `--no-session-persistence`
- Claude Code headless docs (https://code.claude.com/docs/en/headless) -- `-p` mode usage, output formats
- Local git worktree verification -- `git worktree add --detach /tmp/test bench/baseline` tested successfully
- Existing gsd-ralph codebase -- `ralph-launcher.sh` patterns (build_claude_command, timeout handling, exit code interpretation)
- Prior milestone research -- `.planning/research/ARCHITECTURE.md`, `STACK.md`, `PITFALLS.md` (comprehensive domain research from Phase 20 planning)

### Secondary (MEDIUM confidence)
- Claude Code CLI JSON output fields (https://introl.com/blog/claude-code-cli-comprehensive-guide-2025) -- `total_cost_usd`, `duration_ms`, `duration_api_ms`, `num_turns`, `session_id`, `is_error`, `subtype` field names documented
- GNU timeout man page -- exit code 124 behavior, signal handling

### Tertiary (LOW confidence)
- Token count availability in `--output-format json` -- claimed by some sources but NOT verified in official docs. The official docs show `jq -r '.result'` examples but never show token extraction. Treat token fields as unavailable until verified.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools verified on target system, zero new dependencies
- Architecture: HIGH -- patterns derived from existing ralph-launcher.sh and prior milestone research; git worktree verified
- Pitfalls: HIGH -- grounded in codebase analysis, CLI verification, and prior research
- Token capture: MEDIUM -- `num_turns`/`total_cost_usd` are verified available; exact token counts are LOW confidence
- Time cap enforcement: HIGH -- GNU timeout tested, exit code 124 documented

**Research date:** 2026-03-11
**Valid until:** 2026-04-11 (stable tooling; main risk is Claude Code CLI version changes)
