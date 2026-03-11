# Stack Research: v2.2 Benchmarking Suite

**Domain:** Automated benchmarking harness for AI-assisted software engineering
**Researched:** 2026-03-11
**Confidence:** HIGH (all tools verified on target system)

**Scope:** This document covers ONLY the stack additions/changes needed for the benchmarking suite (harness scripts, metrics capture, statistical aggregation, report generation, and the taskctl challenge project). The existing gsd-ralph runtime stack (Bash 3.2, Claude Code CLI, jq 1.8.1, Bats 1.13.0) is NOT re-researched here.

## Executive Summary

The benchmarking suite requires **zero new dependencies**. Every capability needed -- sub-second timing, floating-point math, statistical aggregation (mean, stddev), JSON metrics, CSV/markdown report generation, and challenge evaluation -- is already available through the existing Bash + jq stack plus macOS system utilities (`bc`, `date`, `awk`). This is the correct design: adding Python, Node.js, or external benchmarking frameworks would violate the project's "thin layer" constraint and introduce unnecessary complexity for what is fundamentally a shell scripting measurement problem.

The Claude Code CLI `--output-format json` flag provides structured result data including `total_cost_usd`, `duration_ms`, `num_turns`, and `session_id`, which covers the efficiency metrics the PRD requires. Quality metrics (correctness, regression, shellcheck deltas) are captured by running Bats tests and ShellCheck against the challenge project after each benchmark run.

**Key decision: jq is the statistics engine.** jq 1.8.1 natively supports `sqrt`, `add`, `length`, `group_by`, `@csv`, and `@tsv` -- sufficient for mean, population stddev, and high-variance flagging without any external tools. All statistical calculations, JSON aggregation, and report formatting happen in jq, keeping the entire pipeline in a single tool the project already depends on.

## Recommended Stack

### Core Technologies (EXISTING -- no additions needed)

| Technology | Version | Purpose in Benchmarks | Why Sufficient |
|------------|---------|----------------------|----------------|
| Bash | 3.2.57 (macOS system) | Harness scripts (reset, run, eval, report) | Same language as gsd-ralph itself; consistent patterns |
| jq | 1.8.1 | JSON metrics, statistical aggregation, report generation | Has `sqrt`, `group_by`, `@csv`, `@tsv`; can compute mean/stddev natively |
| Claude Code CLI | 2.1.72+ | Benchmark execution + metrics capture | `--output-format json` provides `duration_ms`, `num_turns`, `total_cost_usd`, `session_id` |
| Bats | 1.13.0 (vendored in tests/bats/) | Challenge project test framework + correctness evaluation | Already in repo; same framework for taskctl tests and gsd-ralph tests |
| Git | 2.20+ | Challenge state management (tags, checkout, reset) | `bench/baseline` and `bench/after-delete` tags for reproducible starting states |
| ShellCheck | 0.11.0 | Code quality metric (warning count delta) | Already installed; used for Bash linting in existing CI |

### System Utilities (macOS built-in -- no installation needed)

| Utility | Purpose in Benchmarks | Notes |
|---------|----------------------|-------|
| `/bin/date +%s` | Wall-clock timing (epoch seconds) | Matches existing `ralph-launcher.sh` timing pattern. Second precision is sufficient for 10-20 minute benchmark runs |
| `bc` | Floating-point division for derived metrics | `echo "scale=2; 95.0 / 245" \| bc` for token efficiency, time efficiency calculations |
| `awk` | Inline floating-point formatting | `awk '{printf "%.2f", $1/$2}'` as alternative to bc for simple divisions |
| `wc -l` | Line count for refactoring metrics | Measuring format.sh size before/after refactoring challenge |
| `diff` | Change measurement for refactoring challenge | `diff --stat` to verify >10 lines changed |
| `mktemp -d` | Temporary directories for benchmark isolation | Same pattern as existing Bats test helper |

### Bats Test Libraries (EXISTING -- already vendored)

| Library | Location | Purpose in Benchmarks |
|---------|----------|----------------------|
| bats-core | `tests/bats/` | Test runner for taskctl challenge tests |
| bats-assert | `tests/test_helper/bats-assert/` | `assert_success`, `assert_failure`, `assert_output` for correctness checks |
| bats-file | `tests/test_helper/bats-file/` | `assert_file_exists`, `assert_dir_exists` for file structure checks |
| bats-support | `tests/test_helper/bats-support/` | Foundation library required by bats-assert and bats-file |

## Claude Code CLI JSON Output Schema

The `--output-format json` flag (used with `-p` / `--print` mode) returns a structured result that the harness captures directly. This is how efficiency metrics flow from benchmark runs to result JSON files.

**Result fields available (verified via official docs and community reference):**

```json
{
  "type": "result",
  "subtype": "success",
  "result": "Response text...",
  "total_cost_usd": 0.0034,
  "is_error": false,
  "duration_ms": 2847,
  "duration_api_ms": 1923,
  "num_turns": 4,
  "session_id": "abc-123-def"
}
```

**Mapping to PRD metrics:**

| PRD Metric | Source | Extraction |
|------------|--------|------------|
| Wall-clock time (seconds) | Harness `date +%s` start/end | `$((end - start))` |
| Total tokens (input + output) | NOT directly in CLI JSON output | Parse from `stream-json` output or estimate from `total_cost_usd` |
| Tool calls count | NOT directly in CLI JSON output | Count from `stream-json` events or session transcript |
| Iterations (Ralph modes) | Harness loop counter | Already tracked in `ralph-launcher.sh` |
| Human interventions | Harness manual count | Always 0 for autonomous modes |
| Duration (ms) | `duration_ms` field | Direct extraction: `jq -r '.duration_ms'` |
| Cost (USD) | `total_cost_usd` field | Direct extraction: `jq -r '.total_cost_usd'` |
| Turns count | `num_turns` field | Direct extraction: `jq -r '.num_turns'` |

**Token and tool-call capture strategy:**

The `--output-format json` single-result mode does NOT include per-token breakdowns or tool-call counts in the top-level result. Two approaches:

1. **Use `--output-format stream-json`** to capture the full event stream, then post-process to count tool_use events and sum token usage from individual message events. This is more complex but gives exact numbers.

2. **Approximate from available fields.** Use `num_turns` as a proxy for tool calls (each turn typically involves 1-2 tool calls). Use `total_cost_usd` combined with known per-token pricing to back-calculate token counts. This is simpler but approximate.

**Recommendation:** Start with approach 2 (available fields) for the MVP. `num_turns`, `duration_ms`, and `total_cost_usd` are the three most meaningful efficiency metrics anyway. Add `stream-json` parsing later if exact token/tool-call counts prove necessary for the comparison narrative.

## Statistical Aggregation in jq

jq 1.8.1 can compute all required statistics natively. No external statistics library or Python/R needed.

**Verified working on this system:**

```bash
# Mean and population stddev in a single jq expression
echo '[10, 20, 30, 40, 50]' | jq '
  (add / length) as $mean |
  (map(. - $mean | . * .) | add / length | sqrt) as $stddev |
  {mean: $mean, stddev: ($stddev * 100 | round / 100), count: length}
'
# Output: {"mean": 30, "stddev": 14.14, "count": 5}
```

```bash
# Group results by mode, compute per-mode statistics
jq -s '
  group_by(.mode) | map({
    mode: .[0].mode,
    mean_score: ([.[].correctness_score] | add / length),
    mean_time: ([.[].wall_clock_seconds] | add / length),
    count: length
  })
' benchmarks/results/*.json
```

```bash
# High-variance flag (stddev > 30% of mean)
jq '
  (add / length) as $mean |
  (map(. - $mean | . * .) | add / length | sqrt) as $stddev |
  {mean: $mean, stddev: $stddev, high_variance: ($stddev > ($mean * 0.3))}
'
```

**Reusable jq function library** (to include in harness scripts):

```jq
def mean: add / length;
def variance: mean as $m | map(. - $m | . * .) | mean;
def stddev: variance | sqrt;
def round2: . * 100 | round / 100;
def high_variance: stddev as $sd | mean as $m | $sd > ($m * 0.3);
```

## Report Generation in jq

jq can produce all three output formats the PRD requires (markdown, CSV, JSON) from the same result data.

**Markdown table generation (verified):**

```bash
jq -r '
  "| Mode | Time (s) | Score | Cost ($) |",
  "|------|----------|-------|----------|",
  (.[] | "| \(.mode) | \(.mean_time | round) | \(.mean_score)% | $\(.mean_cost | round2) |")
'
```

**CSV generation (verified):**

```bash
jq -r '
  ["mode","challenge","time_s","score","cost_usd"],
  (.[] | [.mode, .challenge, .wall_clock_seconds, .correctness_score, .total_cost_usd])
  | @csv
'
```

**JSON aggregated report:** Native -- jq outputs JSON by default.

## Challenge Project Stack (taskctl)

The challenge project is deliberately simple. It uses the same stack as gsd-ralph itself.

| Component | Technology | Why |
|-----------|-----------|-----|
| Entry point | `taskctl.sh` (Bash) | Bash is gsd-ralph's native language; no framework mismatch |
| Storage | JSON flat file (`.taskctl.json`) | jq reads/writes it; familiar pattern from existing `ralph-launcher.sh` |
| Tests | Bats + bats-assert | Same framework already vendored in gsd-ralph; challenge tests and harness eval share the same runner |
| JSON manipulation | jq | Same tool used throughout gsd-ralph |

**Challenge project Bats setup pattern** (mirror existing gsd-ralph test helper):

```bash
# benchmarks/taskctl/tests/test_helper/common.bash
_taskctl_setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
    PATH="$PROJECT_ROOT/src:$PATH"

    # Shared Bats libraries from main repo
    load "${PROJECT_ROOT}/../../tests/test_helper/bats-support/load"
    load "${PROJECT_ROOT}/../../tests/test_helper/bats-assert/load"

    TEST_TEMP_DIR="$(mktemp -d)"
    cp "$PROJECT_ROOT/.taskctl.json" "$TEST_TEMP_DIR/"
    cd "$TEST_TEMP_DIR" || return 1
}
```

**Key pattern:** The challenge project's tests reuse the Bats libraries already vendored in `tests/test_helper/`. No need to vendor them again inside `benchmarks/taskctl/`. Relative paths (`../../tests/test_helper/`) link back to the main repo's copies.

## Harness Script Integration Points

The harness scripts fit alongside existing scripts with consistent patterns.

| Harness Script | Existing Pattern It Follows | Key Integration |
|----------------|---------------------------|-----------------|
| `bench-reset.sh` | `create_test_repo()` in `tests/test_helper/common.bash` | Uses `git checkout`, `git clean -fd` for state reset |
| `bench-run.sh` | `ralph-launcher.sh` loop engine | Uses `date +%s` timing, `claude -p --output-format json`, captures JSON result |
| `bench-eval.sh` | `tests/test_helper/common.bash` + Bats assertions | Runs Bats tests against challenge project, counts pass/fail |
| `bench-report.sh` | `validate-config.sh` jq patterns | Uses `jq -s` to slurp all result files, `jq -r` for markdown/CSV output |

**Script location:** `benchmarks/harness/` as specified in the PRD deliverables.

## Timing Strategy

**Wall-clock timing:** Use `date +%s` (integer seconds) for benchmark run timing. This matches the existing pattern in `ralph-launcher.sh` (lines 291-505) and provides sufficient precision for 10-20 minute benchmark runs. The PRD specifies "wall-clock time (seconds)" -- second granularity is exactly what is needed.

**Why NOT sub-second timing:** macOS 26+ supports `date +%s%N` natively, but:
- Benchmark runs are 10-20 minutes; sub-second precision is noise
- Integer arithmetic in Bash is simpler and more portable
- Matches the existing `ralph-launcher.sh` pattern (no code divergence)
- The Claude CLI `duration_ms` field provides millisecond precision for the API call portion if needed

**Eval script timing** (seconds-granularity): Correctness evaluation scripts run Bats tests and ShellCheck, which typically complete in 1-5 seconds. If sub-second precision is needed for eval timing, use `duration_ms` from the Claude JSON output rather than adding a second timing mechanism.

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Python for statistics | Adds a runtime dependency for mean/stddev that jq handles natively. Every developer machine has different Python configs | jq `add/length` for mean, `map(.-$m\|.*.) \| add/length \| sqrt` for stddev |
| hyperfine | Designed for benchmarking CLI command startup time, not 10-20 minute AI sessions. Its calibration and warmup features are irrelevant | Custom harness with `date +%s` and `--output-format json` |
| GNU time (`gtime`) | Measures CPU time, memory, and I/O -- metrics not in the PRD. Wall-clock time from `date +%s` is what we need | `date +%s` start/end delta |
| pytest / Jest for challenge tests | Introducing a second test framework for the challenge project when Bats is already vendored. Adds setup complexity | Bats (same as gsd-ralph itself) |
| JSON Schema validation library | The result JSON schema is simple (15 fields, all primitives). jq can validate presence of required fields without a schema validator | `jq -e '.mode and .challenge and .correctness_score'` |
| Markdown templating engine | jq's string interpolation handles markdown table generation. No Jinja2, Handlebars, or envsubst needed | jq `-r` with inline markdown formatting |
| CSV library | jq's `@csv` filter handles CSV escaping correctly (quotes strings with commas, escapes quotes) | `jq -r '.[] \| [fields] \| @csv'` |
| Database (SQLite, etc.) | Result files are JSON files in a directory. `jq -s '.' results/*.json` aggregates them. At 4 modes x 5 challenges x 3 runs = 60 files, a database is overhead | Filesystem JSON files + `jq -s` for aggregation |
| R or gnuplot for charts | The PRD deliverable is a markdown comparison report, not a visual dashboard. Tables suffice | jq-generated markdown tables |
| Docker for isolation | Benchmark runs use git tags for state reset. Docker would add startup overhead and complicate Claude Code CLI access | `git checkout bench/baseline && git clean -fd` |
| GNU coreutils (brew install) | macOS system `date`, `bc`, `wc`, `diff`, `awk` all work for the benchmarking needs. No GNU-specific features required | macOS built-in utilities |

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| jq for statistics | Python `statistics` module | If statistical requirements grow beyond mean/stddev (e.g., confidence intervals, hypothesis testing). Unlikely for this project |
| jq `@csv` for CSV | Dedicated CSV tool (`csvkit`, `miller`) | If CSV post-processing is needed (filtering, joining). The benchmarks only need to write CSV, not query it |
| `date +%s` for timing | `SECONDS` Bash variable | `SECONDS` resets on subshell entry, making it unreliable for timing commands that spawn subshells. `date +%s` is explicit and reliable |
| Filesystem JSON files | SQLite via `sqlite3` CLI | If queries become complex (multi-dimensional grouping, window functions). At 60 result files, jq handles this fine |
| Bats for challenge tests | ShellSpec or BATS alternatives | Never for this project. Bats is already vendored and all 356 existing tests use it. Consistency matters more than features |
| `--output-format json` | `--output-format stream-json` | When exact per-message token counts and tool-call enumeration are required. Start with `json` (simpler); switch if needed |

## Version Compatibility

| Requirement | Minimum | Current (verified) | Notes |
|-------------|---------|-------------------|-------|
| Bash | 3.2+ | 3.2.57 | macOS system Bash. All harness scripts use Bash 3.2-compatible syntax |
| jq | 1.6+ | 1.8.1 | `sqrt` available since jq 1.5. `@csv` since 1.5. `group_by` since 1.4. All features needed are well-established |
| Claude Code CLI | 2.0+ | 2.1.72 | `--output-format json` with `duration_ms`, `num_turns`, `total_cost_usd` fields |
| Git | 2.20+ | (system) | Tag checkout, clean, reset operations for challenge state management |
| ShellCheck | 0.7+ | 0.11.0 | Warning count comparison. JSON output (`-f json`) available since 0.7 |
| Bats | 1.5+ | 1.13.0 | `setup_file`/`teardown_file` (used in challenge tests) requires 1.5+. Already vendored at 1.13.0 |
| bc | Any | macOS built-in | POSIX standard. Used only for floating-point division |

**No new dependencies to install.** Every tool is either already vendored in the repo (Bats, bats-assert, bats-file, bats-support) or pre-installed on macOS (Bash, bc, date, awk, wc, diff) or already required by gsd-ralph (jq, Git, Claude Code CLI, ShellCheck).

## Installation

```bash
# Nothing to install. All tools already present.
# Verify with:
bash --version | head -1       # GNU bash, version 3.2.57
jq --version                   # jq-1.8.1
shellcheck --version | head -3 # ShellCheck 0.11.0
git --version                  # git version 2.x
echo '1' | bc                  # 1 (bc available)

# Bats (vendored, not global):
./tests/bats/bin/bats --version # Bats 1.13.0
```

## Sources

- [Claude Code CLI Reference (official docs)](https://code.claude.com/docs/en/cli-reference) -- `--output-format json` flag, `--max-turns`, `--print` mode documentation (verified 2026-03-11, HIGH confidence)
- [Claude Code CLI JSON output fields](https://introl.com/blog/claude-code-cli-comprehensive-guide-2025) -- `total_cost_usd`, `duration_ms`, `duration_api_ms`, `num_turns`, `session_id`, `is_error` fields documented (verified 2026-03-11, MEDIUM confidence -- community source, consistent with official docs)
- [jq 1.8 Manual](https://jqlang.github.io/jq/manual/) -- `sqrt`, `add`, `length`, `group_by`, `@csv`, `@tsv`, `round` built-in functions (verified 2026-03-11, HIGH confidence)
- Local system verification -- all tools tested directly on target macOS 26.3.1 system: `date +%s`, `bc`, `awk`, `jq` statistics, `jq` markdown/CSV generation (verified 2026-03-11, HIGH confidence)
- Existing codebase patterns -- `ralph-launcher.sh` timing (lines 291-505), `validate-config.sh` jq usage, `tests/test_helper/common.bash` Bats setup (verified 2026-03-11, HIGH confidence)
- [Bats-core documentation](https://bats-core.readthedocs.io/) -- `setup_file`, `teardown_file`, `load` patterns for challenge project tests (verified via vendored version, HIGH confidence)

---
*Stack research for: gsd-ralph v2.2 Benchmarking Suite*
*Researched: 2026-03-11*
