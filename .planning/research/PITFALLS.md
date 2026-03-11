# Pitfalls Research

**Domain:** Adding AI coding benchmark suite to existing Bash CLI tool (gsd-ralph), comparing 4 execution modes with different invocation patterns
**Researched:** 2026-03-11
**Confidence:** HIGH (grounded in gsd-ralph codebase analysis of all 4 invocation modes, SWE-bench/LiveCodeBench post-mortems and criticism literature, AI benchmark methodology research from METR/Runloop/nilenso, Claude Code headless mode documentation, and statistical methodology for small-sample high-variance experiments)

## Critical Pitfalls

### Pitfall 1: Apples-to-Oranges Mode Comparison Due to Asymmetric Context Windows

**What goes wrong:**
The four modes have fundamentally different context architectures. CC mode gets a single `claude -p` invocation with one prompt. CC+GSD gets interactive checkpoints feeding incremental context. CC+Ralph loops fresh `claude -p` instances with STATE.md-driven context assembly between iterations. CC+gsd-ralph uses Agent tool subagents spawned within a parent session that itself has accumulated context. A benchmark that treats wall-clock time or token count as directly comparable across these modes produces misleading rankings because the modes are not doing the same amount of work per token.

For example, CC+Ralph's loop engine invokes `assemble-context.sh` fresh each iteration, paying re-encoding costs for PROJECT.md, STATE.md, and phase plans every time. CC+gsd-ralph's Agent subagents inherit no parent context but the parent session pays tokens for orchestration logic (circuit breakers, progress detection) that never appears in the subagent's token count. A raw "total tokens" comparison that only counts the innermost invocation will undercount CC+gsd-ralph and overcount CC+Ralph.

**Why it happens:**
The PRD specifies capturing `tokens_input` and `tokens_output` from "Claude CLI `--output-format json` usage field or session stats," but this field means different things per mode. For `claude -p` (CC and CC+Ralph), the JSON output includes session-level token stats. For CC+GSD (interactive), there is no `--output-format json` -- the human is driving. For CC+gsd-ralph (Agent tool), token usage is embedded in the parent session's JSONL logs, not in a standalone JSON output.

**How to avoid:**
1. Define a "total token budget" metric that counts ALL tokens consumed by all invocations within a benchmark run, not just the innermost one. For CC+Ralph, sum across all loop iterations. For CC+gsd-ralph, sum the parent session's total usage including orchestration overhead.
2. Use `~/.claude/projects/<project>/<session-id>.jsonl` files as the ground truth for token usage across all modes -- these are written consistently regardless of invocation mode.
3. Report tokens in two tiers: "task tokens" (tokens directly working on the challenge) and "overhead tokens" (context assembly, orchestration, progress detection). This makes the comparison honest.
4. For CC+GSD (interactive mode), instrument the session manually -- record the session ID and parse the JSONL after the run.

**Warning signs:**
- Token counts for CC+gsd-ralph are suspiciously lower than CC+Ralph (missing orchestration overhead)
- Token counts for CC+Ralph scale linearly with iteration count (context re-encoding cost not acknowledged)
- No plan for how to capture CC+GSD interactive session tokens
- Result schema has a single `tokens_input` field with no "overhead vs task" distinction

**Phase to address:**
Harness implementation phase. The `bench-run.sh` script must implement mode-aware token capture before any runs are executed. Retrofitting token capture after initial runs wastes those runs.

---

### Pitfall 2: LLM Non-Determinism Producing Uninterpretable Results at N=3

**What goes wrong:**
The PRD specifies 3 runs per mode-challenge combination for statistical validity and flagging results where stddev > 30% of mean as "high variance." With LLMs, 3 runs is far too few to produce stable statistics. Research consistently shows that running the same LLM stack multiple times can sway benchmark results by several percentage points. At N=3, a single outlier (one run where the LLM takes a wrong diagnostic path) moves the mean by 33% and the stddev becomes meaningless. The result: most mode-challenge cells get flagged as "high variance" and the entire comparison table becomes noise.

The correctness score is particularly vulnerable. It is binary per check (pass/fail), aggregated to 0-100%. With 4-5 checks per challenge, each worth 20-25%, a single check flipping between runs creates a 20-25% swing. At N=3, this means the stddev of correctness will routinely exceed 30% of mean for any non-trivial challenge.

**Why it happens:**
Claude Code does not expose a `--temperature` flag for the interactive or Agent tool modes. Even `claude -p` does not guarantee temperature 0 behavior. The PRD says "use `--temperature 0` where available, or document the default," but Claude Code CLI does not have a `--temperature` flag at all -- temperature is controlled server-side and is not user-configurable. All 4 modes will exhibit the same underlying non-determinism with no way to reduce it.

**How to avoid:**
1. Increase to N=5 minimum, ideally N=7. The marginal cost of 2-4 extra runs per cell is far less than the cost of collecting data that cannot support any conclusion. With 4 modes x 5 challenges x 5 runs = 100 runs total (vs 60 at N=3).
2. Report median and IQR (interquartile range) instead of mean and stddev. Median is robust to single outliers, IQR captures spread without assuming normality.
3. For correctness, report the distribution of scores across runs (e.g., "3/5 runs scored 100%, 1 scored 75%, 1 scored 50%") rather than mean +/- stddev. The shape of the distribution matters more than the central tendency.
4. Use a "reliability rate" metric: percentage of runs achieving >= 80% correctness. This captures what matters (how often does this mode succeed?) better than average correctness.
5. Adjust the "high variance" threshold: 30% of mean is too strict for LLM benchmarks. Use coefficient of variation (CV) thresholds calibrated against a pilot run: run Challenge 1 across all modes 10 times first, measure the baseline CV, then set thresholds relative to that baseline.

**Warning signs:**
- Most cells in the comparison table are flagged "high variance"
- Correctness scores cluster at discrete values (0%, 25%, 50%, 75%, 100%) with no values between -- this is the granularity problem, not real variance
- A mode "wins" based on mean correctness differences smaller than the stddev
- No pilot run to calibrate expected variance before committing to full benchmark

**Phase to address:**
Challenge design phase AND reporting phase. The challenge design must consider check granularity (more fine-grained checks reduce per-check swing). The reporting script must implement robust statistics. Run a pilot before committing to the full matrix.

---

### Pitfall 3: Challenge Project Contamination in Training Data

**What goes wrong:**
The `taskctl` challenge project will be committed to the gsd-ralph repository. If gsd-ralph is public (or becomes public), future Claude model updates will train on this exact code. The benchmark then measures memorization, not problem-solving. Even before public exposure, if Claude's training data includes GitHub repos, the challenge code, bug patterns, and even the correctness checks could leak into the model's training distribution. The "planted bug in done.sh" becomes a pattern the model has seen before, making Challenge 1 trivially easy for future model versions.

This is the same contamination problem that has made SWE-bench Verified unreliable. Research shows models achieve up to 76% accuracy on SWE-bench file-path identification tasks through memorization rather than reasoning, with substantial performance drops on external benchmarks.

**Why it happens:**
It is the natural instinct to version-control everything in the same repo for convenience. The PRD places the challenge project at `benchmarks/taskctl/` inside gsd-ralph. Developers do not think about their own repo as a future training data source.

**How to avoid:**
1. Accept that contamination is inevitable for a project of this scope and design benchmarks to be disposable. Build the harness and evaluation infrastructure to be reusable, but expect to swap challenge projects periodically.
2. Use the `bench/baseline` git tag approach (already in the PRD) but go further: make challenge generation semi-automated. Write a script that can create new challenge variants (different bug locations, different missing features) from a template, so you can generate fresh challenges when you suspect contamination.
3. Include a "canary check" in the evaluation: add one check that requires reading a value from the specific git commit hash or timestamp. If the model produces the right answer without reading the file, contamination is confirmed.
4. For the initial benchmark, accept this limitation and document it. The benchmark measures "current Claude on never-before-seen code." Future runs with the same challenges are "Claude on potentially-seen code" and must be interpreted accordingly.

**Warning signs:**
- Correctness scores increase across model versions without changes to the challenge
- The model produces fixes without reading the buggy file first (checking tool call logs)
- Challenge 1 (fix bug) becomes near-100% across all modes -- the diagnostic task becomes trivial
- Model names the specific bug before examining the code

**Phase to address:**
Challenge project phase. The taskctl project should be designed with replaceability in mind. The harness scripts should work with any challenge project, not be hardcoded to taskctl's specific file structure.

---

### Pitfall 4: Time Cap Confounding Correctness Measurements

**What goes wrong:**
The PRD specifies time caps per challenge (10-20 minutes). When a mode hits the time cap, it gets a partial correctness score based on whatever state the code is in at timeout. This conflates two different failure modes: "the mode is slow but would eventually succeed" vs "the mode is stuck and would never succeed." A mode that methodically works through a problem but takes 12 minutes on a 10-minute-capped challenge scores lower than a mode that quickly produces a half-correct solution in 5 minutes, even though the first mode would have scored 100% given 15 minutes.

The CC+Ralph and CC+gsd-ralph modes are particularly vulnerable because they have startup overhead (context assembly, circuit breaker initialization) that the raw CC mode does not. Ralph's loop engine also has inter-iteration overhead (state snapshot, progress detection) that consumes wall-clock time without producing code changes.

**Why it happens:**
Time caps are necessary to prevent runaway sessions (a legitimate concern with autonomous modes), but using them as a scoring boundary rather than just a safety valve creates a measurement artifact. The PRD's derived metric "Time efficiency = Correctness / wall-clock seconds" further amplifies this: a mode that times out at 10 minutes with 75% correctness scores lower than one that finishes at 5 minutes with 80% correctness, even if the timeout mode was on track for 100%.

**How to avoid:**
1. Separate time caps from scoring. Record the time cap as metadata ("timed out: yes/no") but score correctness based on final state regardless. A mode that achieves 100% correctness in 18 minutes on a 15-minute-capped challenge should be recorded as "100% correctness, 18 minutes, exceeded cap."
2. Use generous time caps (2-3x the expected completion time from pilot runs) that function as safety valves, not performance boundaries. If pilot runs show Challenge 1 takes 3-7 minutes, set the cap at 20 minutes, not 10.
3. Report "completion rate within cap" as a separate metric from correctness. This captures the autonomy reliability dimension without contaminating the quality dimension.
4. For the "time efficiency" derived metric, only include runs that completed within the cap. Timed-out runs should be excluded from efficiency calculations and reported separately.

**Warning signs:**
- Multiple runs per challenge hit the time cap
- One mode consistently times out while others do not (signals the cap is too tight for that mode's overhead, not that the mode is worse)
- Time caps were set without pilot runs to calibrate expected durations
- The "fastest" mode wins on time efficiency despite lower correctness

**Phase to address:**
Challenge design phase (set initial caps) and harness implementation phase (implement cap as safety valve, not scoring boundary). Calibrate caps during pilot runs before the full benchmark matrix.

---

### Pitfall 5: Correctness Checks That Reject Valid Alternative Solutions

**What goes wrong:**
The correctness checks in `bench-eval.sh` are designed around one expected implementation approach. But LLMs frequently produce correct solutions that differ from what the check expects. For example, Challenge 2 ("add delete command") checks for `test_delete.bats` with "at least 2 tests." If the model adds delete tests to an existing test file, or names the file `test_delete_command.bats`, or implements delete as a subcommand of a broader `manage` command, the correctness check fails despite the solution being functionally correct.

This is the single most common failure mode in AI coding benchmarks. Research on SWE-bench found that 63.75% of fixes flagged as failures were "suspicious" -- either passing despite being wrong, or failing despite being correct. The evaluation was the bottleneck, not the model.

**Why it happens:**
Writing correctness checks is deceptively easy. You think about how YOU would solve the problem, then write checks for that approach. The checks encode implementation assumptions (file names, function signatures, test structure) rather than behavioral contracts (does `taskctl delete 1` actually remove task 1?).

**How to avoid:**
1. Write behavioral checks, not structural checks. Instead of "does `test_delete.bats` exist?", check "does running `bats tests/` include at least 2 passing tests that exercise delete functionality?" Use grep on test output, not file existence.
2. For each challenge, enumerate at least 3 alternative valid solutions and verify the checks accept all of them. Have someone other than the check author attempt the challenge manually to discover unexpected-but-valid approaches.
3. Separate checks into "hard requirements" (behavioral -- the feature works) and "soft requirements" (structural -- specific file names, patterns). Score hard requirements as pass/fail, soft requirements as bonus points.
4. For the refactoring challenge (Challenge 4), behavioral checks are especially critical. The check "diff > 10 lines changed" could fail if the model makes a small but highly impactful refactor (renaming variables, extracting one function). Use multiple quality signals: ShellCheck warnings delta, function count, cyclomatic complexity, line count -- require improvement in ANY of these, not a specific one.
5. Run the correctness checks against the baseline code to verify they fail before the challenge (sanity check), and against a manually-created reference solution to verify they pass (positive control).

**Warning signs:**
- Correctness checks reference specific file names, function names, or variable names
- A mode scores 0% on a challenge but manual inspection shows it produced working code
- The same mode scores 100% and 0% on the same challenge across runs (suggesting the check is fragile, not the mode)
- No reference solution exists for any challenge
- Checks were never tested against known-good solutions

**Phase to address:**
Challenge design phase (write behavioral checks) and evaluation phase (validate checks against reference solutions). This should be the most heavily tested component of the entire benchmark suite.

---

### Pitfall 6: Vanity Metrics That Look Informative but Measure Noise

**What goes wrong:**
The PRD defines several derived metrics that compound measurement error from their component metrics, producing numbers that look precise but carry no signal. The worst offender is "Token efficiency = Correctness score / total tokens x 1000." This divides a coarse ordinal variable (correctness: 0%, 25%, 50%, 75%, 100%) by a noisy continuous variable (token count) and multiplies by an arbitrary constant (1000). The result is a number like 2.22 that implies precision to two decimal places but is meaningless: changing one correctness check from pass to fail changes the metric by 40%.

"Quality-adjusted speed = (Correctness x Regression) / wall-clock seconds" is similarly problematic. Since regression score will be 100% for most successful runs (the whole point is NOT breaking existing tests), this metric collapses to "Correctness / time" for passing runs and "0 / time" for failing runs -- a binary rather than the continuous gradient the formula implies.

"Autonomy ratio = 1 - (human interventions / tool calls)" will be exactly 1.0 for all autonomous modes (CC+Ralph, CC+gsd-ralph) and close to 1.0 for CC+GSD (where human interventions are checkpoint approvals, not tool calls). This metric differentiates nothing.

**Why it happens:**
It is tempting to define many derived metrics because they make the benchmark look rigorous. Each individual metric seems reasonable in isolation. The problem only appears when you ask "what decision would a different value of this metric change?" -- and the answer is "none."

**How to avoid:**
1. Apply the "decision test" to every metric before implementing it: "If mode A scores X and mode B scores Y on this metric, what would I conclude and what would I do differently?" If the answer is "nothing," drop the metric.
2. Focus on 3-4 primary metrics that directly answer the benchmark's question ("which mode produces better outcomes?"):
   - **Correctness rate**: Percentage of runs achieving >= 80% correctness (reliability)
   - **Median wall-clock time**: For successful runs only (speed)
   - **Total tokens consumed**: Across all invocations per run (cost)
   - **Regression rate**: Percentage of runs with 0 test regressions (safety)
3. Report derived metrics as supplementary context, not primary findings. Label them explicitly as "derived -- interpret with caution."
4. Do not report precision beyond what the data supports. Correctness is ordinal (0/25/50/75/100), not continuous. Token counts are noisy. Report ranges and categories, not decimal values.

**Warning signs:**
- The report has more derived metrics than primary metrics
- Two modes are "ranked" based on a derived metric difference smaller than the measurement noise
- The autonomy ratio is 1.0 for all autonomous modes (metric adds no information)
- Token efficiency numbers are quoted to decimal places despite correctness being 0/25/50/75/100

**Phase to address:**
Reporting phase. The `bench-report.sh` script should implement the decision test and suppress uninformative metrics. However, the result schema design (harness phase) should capture the raw data to compute any metric later.

---

### Pitfall 7: Interactive Mode (CC+GSD) Cannot Be Fairly Automated

**What goes wrong:**
CC+GSD mode is defined as "Claude Code with GSD planning workflow. Human-interactive checkpoints." The benchmark harness needs to run this mode automatically for fair comparison, but the entire value proposition of CC+GSD is human judgment at checkpoints. If the harness auto-approves checkpoints (simulating a human who always says "yes"), it removes the human intelligence that makes CC+GSD different from CC. If the harness does NOT auto-approve, it requires a human to sit through every CC+GSD run, making N=5 repetitions per challenge prohibitively expensive and introducing human inconsistency as a confound.

This is not a minor implementation detail -- it is a fundamental design conflict. The benchmark claims to compare "4 execution modes," but one mode is definitionally non-automatable.

**Why it happens:**
The PRD treats CC+GSD as a parallel mode alongside three autonomous modes, but it is categorically different. The other three modes run without human input by design. CC+GSD runs WITH human input by design. Benchmarking them on the same footing requires either removing CC+GSD's defining characteristic (human checkpoints) or accepting that CC+GSD results have different methodology.

**How to avoid:**
1. Accept the asymmetry and document it explicitly. CC+GSD runs are "human-in-the-loop benchmarks" with different methodology than the three autonomous modes. Do not attempt to automate CC+GSD checkpoints.
2. Run CC+GSD with N=1 or N=2 (human effort constraint) and flag the lower sample size in reporting. Use CC+GSD as a qualitative baseline ("a competent human with GSD achieves this"), not a statistically comparable data point.
3. For CC+GSD runs, additionally capture qualitative observations: what the human decided at each checkpoint, whether the human corrected the model's direction, how much of the outcome was human judgment vs model execution. This is data the autonomous modes cannot provide and is CC+GSD's actual value.
4. Consider a "simulated human" approach for CC+GSD: run it with `--ralph` flag (which auto-approves checkpoints). Acknowledge that "CC+GSD with auto-approval" is really a third autonomous mode, not true CC+GSD. Report it separately from manual CC+GSD if both are run.
5. In the comparison report, group results: "Autonomous modes (CC, CC+Ralph, CC+gsd-ralph)" vs "Human-assisted mode (CC+GSD)" with explicit methodology differences noted.

**Warning signs:**
- CC+GSD runs use auto-approved checkpoints without acknowledging this changes the mode's behavior
- CC+GSD has the same N as autonomous modes despite requiring human effort per run
- The report ranks CC+GSD alongside autonomous modes without noting the methodology difference
- No qualitative data captured from CC+GSD runs (the most valuable output is lost)

**Phase to address:**
Harness design phase. The `bench-run.sh` script must have mode-specific invocation logic that handles CC+GSD differently. The reporting template must accommodate asymmetric methodology.

---

### Pitfall 8: Git State Contamination Between Benchmark Runs

**What goes wrong:**
The benchmark runs modify files in the challenge project (that is the whole point -- the LLM fixes bugs, adds features, etc.). If `bench-reset.sh` does not perfectly restore the starting state, residual changes from a previous run leak into the next run. This is especially dangerous for Challenge 5 ("Multi-File Feature"), which starts from `bench/after-delete` (Challenge 2 completed). If the reset does not perfectly reproduce the post-Challenge-2 state, Challenge 5 results are contaminated.

Subtler contamination vectors: the LLM may create files not tracked by git (temp files, `.bak` files, editor configs, `.shellcheck` caches). `git checkout bench/baseline` only restores tracked files -- untracked files from a previous run persist and may influence the LLM's behavior (it reads directory listings and discovers unexpected files).

Even subtler: if the LLM committed during a previous run, git reflog and branch names persist across resets. A subsequent run's LLM could `git log` and see the previous run's commits, learning from a prior attempt's approach.

**Why it happens:**
`git checkout <tag>` is the obvious reset mechanism, and it works for tracked files. Developers forget about untracked files, gitignored files, and git metadata (reflog, stashes, branches) because they do not affect the working tree directly. But an LLM that uses `git log`, `ls`, or `find` as diagnostic tools WILL encounter this residual state.

**How to avoid:**
1. Use `git clean -fdx` after `git checkout <tag>` to remove ALL untracked and gitignored files. This is safe because the challenge project is disposable.
2. Delete all non-tag branches before each run: `git branch | grep -v '^\*' | xargs git branch -D`. The LLM should only see the clean tag history.
3. Clear git reflog: `git reflog expire --expire=now --all && git gc --prune=now`. This prevents the LLM from discovering previous run attempts via reflog.
4. Run each benchmark in an isolated worktree or a fresh clone of the challenge project. This is the nuclear option but provides guaranteed isolation. `git worktree add /tmp/bench-run-$TIMESTAMP bench/baseline` creates a clean copy per run.
5. The `bench-reset.sh` script should include a verification step: compute checksums of all files and compare against a stored manifest for the tag. If ANY file differs, the reset failed.
6. For Challenge 5's `bench/after-delete` starting state, include a pre-built reference commit at that tag rather than depending on Challenge 2's output. The "after-delete" state should be a fixed, committed tag, not derived from a previous run.

**Warning signs:**
- Reset script uses only `git checkout <tag>` without `git clean`
- Challenge 5's starting state is generated dynamically from Challenge 2 output
- LLM tool call logs show it reading files or git history from a previous run
- Successive runs on the same challenge show decreasing time (LLM finding prior solutions in git history)
- `.taskctl.json` or other data files persist across resets with stale data

**Phase to address:**
Harness implementation phase (bench-reset.sh). This is foundational infrastructure -- every run depends on clean reset. Test the reset script by running a challenge, resetting, and verifying byte-for-byte identical state to a fresh clone at the same tag.

---

### Pitfall 9: Measuring Harness Overhead Instead of Mode Performance

**What goes wrong:**
Each mode has different amounts of infrastructure between "start the timer" and "LLM begins working on the challenge." CC mode: near-zero overhead. CC+GSD: checkpoint display overhead. CC+Ralph: `assemble-context.sh` execution, config validation, circuit breaker initialization, STATE.md parsing, worktree setup. CC+gsd-ralph: Agent tool spawning, autopilot rules loading, context assembly, circuit breaker checks.

If the timer starts at "harness launches mode" and ends at "harness regains control," the wall-clock time for Ralph and gsd-ralph modes includes 15-45 seconds of startup that has nothing to do with the LLM's coding ability. For short challenges (10-minute cap), this overhead represents 2.5-7.5% of the total time -- enough to swing rankings on the "time efficiency" metric.

Token overhead is worse. CC+Ralph's `assemble-context.sh` injects PROJECT.md, STATE.md, ROADMAP.md, and phase plans into every iteration's prompt. This is the same project context every time, consuming thousands of tokens per iteration that have nothing to do with the challenge. If the benchmark project is gsd-ralph itself, this context is enormous. If the benchmark runs in a minimal challenge project, this context is small but still non-zero.

**Why it happens:**
The harness measures what is easy to measure (start-to-end timestamps) rather than what is meaningful to measure (LLM working time). Separating infrastructure overhead from productive work requires instrumenting the mode internals, which is harder than wrapping the whole thing in a timer.

**How to avoid:**
1. Instrument the inner loop, not just the outer wrapper. For CC+Ralph, record the timestamp when `claude -p` is actually invoked (not when `ralph-launcher.sh` starts) and when it returns (not when cleanup finishes).
2. For token overhead, subtract a known "infrastructure token cost" that is measured once by running each mode's startup with an empty/trivial prompt. This gives a per-mode overhead baseline.
3. Run all modes against the SAME minimal project structure. Do not benchmark CC+Ralph inside gsd-ralph's actual repo (which has ~1,100 LOC, 356 tests, and extensive .planning/ content that all gets assembled into context). Use the `taskctl` challenge project as a standalone repo with minimal planning artifacts.
4. Report both "gross time" (including overhead) and "net time" (LLM working time only). Gross time is relevant for "how long do I actually wait?" Net time is relevant for "which mode uses LLM time more efficiently?"

**Warning signs:**
- CC+Ralph is consistently 30-60 seconds slower than CC on easy challenges (that is startup overhead, not mode inferiority)
- Token counts for CC+Ralph include thousands of tokens that are identical across all challenges (context assembly boilerplate)
- The benchmark runs inside gsd-ralph's repo rather than a standalone challenge repo
- No distinction between gross and net time in the results

**Phase to address:**
Harness implementation phase. The `bench-run.sh` script must implement mode-aware instrumentation. The challenge project phase must create a standalone repo with minimal infrastructure overhead.

---

### Pitfall 10: Evaluating Refactoring Quality with Line-Count Proxies

**What goes wrong:**
Challenge 4 (Refactor with Behavior Preservation) uses "diff > 10 lines changed" and "cyclomatic complexity reduced or line count reduced" as quality signals. These are weak proxies that reward noisy refactors over meaningful ones. An LLM that adds blank lines, reorders functions, and changes variable names produces a large diff with no quality improvement. An LLM that extracts one critical helper function, reducing 30 lines to 5, produces a small diff with high quality improvement.

Worse, "line count reduced" incentivizes deleting comments and collapsing logic into one-liners -- the opposite of clarity. ShellCheck warning count is the only signal that correlates with actual quality, but ShellCheck focuses on correctness and portability, not readability or maintainability.

**Why it happens:**
Refactoring quality is genuinely hard to measure automatically. Line count and diff size are easy to compute. The temptation is to use what is measurable rather than what is meaningful. Academic benchmarks have the same problem -- SWE-bench measures test passage, not code quality.

**How to avoid:**
1. Drop the "diff > 10 lines changed" requirement entirely. It rewards noise. Replace with "file was modified" (binary check that refactoring was attempted).
2. Use multiple quality signals with an OR condition: ShellCheck warnings reduced OR function count changed (extraction/inlining) OR average function length reduced OR comments-to-code ratio improved. Improvement in ANY one signal counts.
3. Add a manual quality review step for the refactoring challenge specifically. Have a human rate the before/after on a 1-5 scale for readability. This is acceptable because Challenge 4 is one challenge out of five, and human review adds the most value here.
4. Include a negative check: the refactor must NOT add new functionality (no new functions that were not present before, no new test cases). This catches LLMs that "refactor" by adding features.
5. Consider using `shellcheck --format json` for machine-readable output that can be diffed automatically.

**Warning signs:**
- High correctness scores on Challenge 4 despite the refactored code being less readable (human inspection)
- LLMs "refactoring" by reformatting whitespace or reordering functions (large diff, no quality change)
- LLMs deleting comments to reduce line count
- Refactoring challenge correctness score has zero variance across runs (the metric is too easy to game)

**Phase to address:**
Challenge design phase (define quality signals) and evaluation phase (implement multi-signal quality assessment). Consider deferring the refactoring challenge to a later version of the benchmark if quality measurement proves intractable.

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcoding `taskctl` file paths in `bench-eval.sh` | Fast to write correctness checks | Cannot reuse harness with a different challenge project; must rewrite eval for every new project | Never -- abstract eval checks behind challenge-specific config files from day one |
| Storing results as flat JSON files in `benchmarks/results/` | Simple, no database needed | File naming conventions become load-bearing, aggregation requires scanning/globbing, no indexing | Acceptable for v1 if file naming is strictly enforced and `bench-report.sh` validates file structure |
| Using `git checkout` as the only reset mechanism | Works for tracked files | Untracked files persist, git history leaks between runs, contamination goes undetected | Never -- must be paired with `git clean -fdx` and state verification at minimum |
| Running benchmarks inside the gsd-ralph repo | No setup required, everything is co-located | Context assembly includes gsd-ralph project files in Ralph/gsd-ralph mode prompts; token counts reflect gsd-ralph overhead, not challenge-specific work | Never -- benchmark challenge project must be a separate git repo |
| Capturing tokens only from `--output-format json` | Clean API, one source of truth per invocation | Misses orchestration tokens (gsd-ralph parent session), inter-iteration tokens (Ralph context assembly), and interactive session tokens (CC+GSD) | Only acceptable for CC mode where single invocation = total usage |
| Skipping pilot runs and going straight to full N=5 matrix | Saves time upfront | Discover that time caps are wrong, checks are fragile, or variance is too high after wasting 100 runs | Never -- always run 1-2 pilot runs per challenge to calibrate |

## Integration Gotchas

Common mistakes when connecting the benchmark to existing gsd-ralph infrastructure.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `ralph-launcher.sh` loop engine | Treating the launcher as a black box and timing only the outer script | Instrument the inner `run_iteration()` function to emit timestamps before and after `claude -p` invocation; parse these from audit log or stdout |
| `assemble-context.sh` context | Letting context assembly inject the FULL gsd-ralph project context into benchmark prompts | Run benchmarks in a standalone `taskctl` repo where `assemble-context.sh` only finds minimal `.planning/` content; OR bypass context assembly and inject challenge-specific prompts directly |
| `.planning/STATE.md` completion detection | Assuming STATE.md will be updated by the LLM during benchmark challenges | The taskctl challenge project has no GSD workflow state; completion must be detected by the harness (timeout or eval script), not by STATE.md parsing |
| `settings.local.json` permissions | Running benchmarks with different permission tiers across modes (Ralph uses `--allowedTools` whitelist; gsd-ralph uses Agent tool permissions; CC uses whatever the user has configured) | Lock down permissions identically across all modes: same tool set, same Bash command restrictions; document exact permission config in benchmark manifest |
| `.ralph/.circuit_breaker_*` state files | Circuit breaker state files from previous runs affecting subsequent runs | Clear ALL `.ralph/` state files in `bench-reset.sh`: `.circuit_breaker_history`, `.circuit_breaker_state`, `.exit_signals`, `.loop_start_sha`, `progress.json` |
| Agent tool subagent context | Assuming Agent tool subagents get a clean context window | Agent subagents DO get fresh context, but the parent session accumulates state; for CC+gsd-ralph benchmarks, each challenge must be a fresh parent session, not sequential challenges in one session |
| `--output-format json` parsing | Using `jq` to parse `claude -p` JSON output without handling the case where the output is not valid JSON (model error, timeout, rate limit) | Wrap JSON parsing in validation: check exit code of `claude -p`, verify output is valid JSON with `jq empty`, handle empty/malformed output gracefully with a "run failed" result |

## Performance Traps

Patterns that work at small scale but fail as usage grows.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Sequential benchmark execution | Full matrix takes 4 modes x 5 challenges x 5 runs x 15 min avg = 25 hours | Parallelize across modes (each mode can run independently); consider running on separate machines to avoid API rate limiting interference | At N > 3 runs per cell; sequential execution becomes the bottleneck |
| API rate limiting across parallel runs | Multiple simultaneous `claude -p` invocations hit Anthropic rate limits; some runs fail or are throttled, producing artificially high wall-clock times | Serialize runs within a mode, parallelize across modes with staggered start times; log and flag any rate-limit errors in results | When running 2+ modes in parallel on the same API key |
| Result file accumulation | `benchmarks/results/` grows to hundreds of files; `bench-report.sh` globbing becomes slow; filename parsing becomes fragile | Use a structured directory hierarchy: `results/{mode}/{challenge}/{run-N}.json`; implement a results index file that `bench-report.sh` reads instead of globbing | At > 50 result files; globbing becomes unreliable with special characters in filenames |
| JSONL log parsing for token counts | Parsing `~/.claude/projects/*/` JSONL files to extract token usage works for one session but scales poorly across hundreds of benchmark sessions | Build a session-to-run mapping at invocation time (record session ID in result JSON); parse only the relevant JSONL file per run, not the entire projects directory | At > 20 benchmark sessions; directory scanning becomes slow |

## Security Mistakes

Domain-specific security issues beyond general web security.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Running benchmarks with `--tier yolo` (unrestricted Bash access) | LLM executes arbitrary commands on the host machine during benchmark; potential for `rm -rf`, network access, credential exfiltration | Use `--tier default` with explicit `--allowedTools` whitelist for all benchmark runs; challenge prompts do not require network access or dangerous commands |
| Benchmark challenge project containing real credentials or API keys | LLM encounters and potentially logs/outputs credentials during benchmark run | Use only synthetic data in `taskctl` project; `.taskctl.json` sample data must contain no real information; audit CLAUDE.md and README.md for accidental credential inclusion |
| Storing benchmark results with embedded prompt content | Prompt content in result JSON files may contain project-specific information that should not be shared | Result schema should store prompt hash/ID, not full prompt text; keep prompts in separate challenge definition files |
| Running untrusted LLM output as part of correctness checks | If `bench-eval.sh` runs code that the LLM modified (e.g., sourcing modified `taskctl.sh`), the LLM could inject malicious code that the eval script executes | Run correctness checks in a sandboxed subshell; never `source` LLM-modified files in the eval script; use `bats` test runner (which has its own process isolation) for behavioral checks |

## UX Pitfalls

Common user experience mistakes in this domain.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Report only shows numbers without interpretation | User sees "CC: 85%, Ralph: 72%" but does not know if the difference is statistically significant or within noise | Include confidence intervals and a "is this difference meaningful?" column; use language like "CC and Ralph performed similarly" when differences are within variance |
| No progress indicator during long benchmark runs | User starts 25-hour benchmark suite and sees no output for hours; unclear if it is running or stuck | Print per-run status: "Running: ralph / fix-bug / run 3/5 ... [elapsed: 4m32s]"; emit a heartbeat every 60 seconds during each run |
| Report format does not support incremental results | User cannot see partial results until entire matrix completes | Generate report from whatever results exist; support `bench-report.sh --partial` that shows completed cells and blank cells for pending runs |
| Benchmark failure crashes entire suite | One failed run (API error, timeout, malformed output) stops all subsequent runs | Wrap each run in error handling; log failures to result JSON with `"status": "error"` and continue; report failed runs as "N/A" in comparison table |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Challenge project (taskctl):** Often missing the `bench/after-delete` tag for Challenge 5 -- verify this tag exists and contains a working delete command with tests
- [ ] **Correctness checks:** Often tested only against expected solutions -- verify each check FAILS against the unmodified baseline (negative control) AND passes against a manually-created reference solution (positive control)
- [ ] **Reset script:** Often only does `git checkout` -- verify it also runs `git clean -fdx`, clears untracked files, removes `.ralph/` state files, and verifies checksums match the tag
- [ ] **Token capture:** Often works for `claude -p` JSON output -- verify it also captures tokens for interactive sessions (CC+GSD) and Agent tool subagent sessions (CC+gsd-ralph)
- [ ] **Time measurement:** Often captures wall-clock start/end -- verify it also records mode-specific overhead (context assembly time, circuit breaker initialization) separately from LLM working time
- [ ] **Statistical reporting:** Often reports mean and stddev -- verify it handles N < 3 gracefully, reports median/IQR for robustness, and flags cells where variance exceeds interpretability
- [ ] **Benchmark isolation:** Often runs in gsd-ralph repo -- verify the challenge project is a standalone git repo with its own `.planning/` minimal content, not inheriting gsd-ralph's project context
- [ ] **Challenge independence:** Often assumes challenges can run in any order -- verify that Challenge 5 depends on a fixed `bench/after-delete` tag, not on Challenge 2 being run first in the same session

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Training data contamination | LOW | Swap challenge project: create a new taskctl variant with different bug locations and missing features; reuse all harness infrastructure unchanged |
| Correctness checks reject valid solutions | MEDIUM | Review all "failed" runs manually; update checks to accept the valid alternative; re-score affected runs without re-running them (results JSON has enough data to re-evaluate) |
| Time caps too tight, many timeouts | LOW | Increase caps based on observed data; re-run only the timed-out runs; merge with existing results |
| Git state contamination between runs | HIGH | All results from the contaminated sequence are suspect; must re-run from scratch with fixed reset script; no way to know which runs were affected |
| Token capture missed orchestration overhead | MEDIUM | Parse JSONL logs retroactively if session IDs were recorded; if session IDs were not recorded, re-run with fixed instrumentation |
| Report draws conclusions from noise | LOW | Re-generate report with adjusted statistical methodology; no re-running needed if raw data is sound |
| CC+GSD automated without acknowledging methodology difference | MEDIUM | Re-label CC+GSD results as "CC+GSD (auto-approved checkpoints)"; add methodology disclaimer to report; optionally re-run with actual human for N=1 |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| Apples-to-oranges token comparison (P1) | Harness implementation | Run one challenge across all 4 modes; verify token capture includes orchestration overhead for each |
| N=3 insufficient for stable statistics (P2) | Challenge design + Reporting | Pilot run of 10 iterations on one challenge; measure baseline CV; calibrate N and variance thresholds |
| Training data contamination (P3) | Challenge project design | Include canary check; document contamination risk in report methodology section |
| Time cap confounding correctness (P4) | Challenge design + Harness | Pilot run to calibrate caps at 2-3x observed completion time; implement cap as safety valve, not scoring boundary |
| Correctness checks rejecting valid solutions (P5) | Challenge design | Create reference solutions for all challenges; verify checks pass reference AND fail baseline; enumerate 3 alternative approaches |
| Vanity metrics (P6) | Reporting | Apply "decision test" to each metric; suppress metrics that differentiate nothing; report primary metrics only |
| CC+GSD cannot be automated fairly (P7) | Harness design | Document methodology difference; implement CC+GSD with separate invocation path; group results by methodology |
| Git state contamination (P8) | Harness implementation (bench-reset.sh) | After reset, verify byte-for-byte match against fresh clone at same tag; include `git clean -fdx` in reset |
| Measuring harness overhead (P9) | Harness implementation | Instrument inner invocation, not outer wrapper; measure per-mode startup overhead baseline with trivial prompt |
| Refactoring quality via line-count (P10) | Challenge design | Use multi-signal quality assessment; include manual review for refactoring challenge; drop "diff > 10 lines" requirement |

## Sources

- [SWE-bench Deep Dive: Unmasking the Limitations of a Popular Benchmark](https://runloop.ai/blog/swe-bench-deep-dive-unmasking-the-limitations-of-a-popular-benchmark) -- Solution leakage, weak test coverage, false positive rates
- [Why SWE-bench Verified no longer measures frontier coding capabilities](https://openai.com/index/why-we-no-longer-evaluate-swe-bench-verified/) -- Benchmark saturation and contamination
- [The SWE-Bench Illusion: When State-of-the-Art LLMs Remember Instead of Reason](https://arxiv.org/html/2506.12286v3) -- Memorization vs reasoning in benchmarks
- [What are popular AI coding benchmarks actually measuring?](https://blog.nilenso.com/blog/2025/09/25/swe-benchmarks/) -- Gap between benchmark performance and real-world capability
- [Why Most LLM Benchmarks Are Misleading](https://dasroot.net/posts/2026/02/llm-benchmark-misleading-accurate-evaluation/) -- Data leakage, overfitting, hallucination in specialized domains
- [What we learned running the industry's first AI code review benchmark](https://devinterrupted.substack.com/p/what-we-learned-running-the-industrys) -- Orchestration debt, reproducibility, signal-to-noise ratio
- [The importance of Agent Harness in 2026](https://www.philschmid.de/agent-harness-2026) -- Durability, the bitter lesson, harness architecture
- [LLMs Are Not Deterministic](https://dev.to/marcosomma/llms-are-not-deterministic-and-making-them-reliable-is-expensive-in-both-the-bad-way-and-the-good-5bo4) -- Fundamental non-determinism in LLMs
- [AI benchmarks hampered by bad science](https://www.theregister.com/2025/11/07/measuring_ai_models_hampered_by/) -- Only 16% of benchmarks use rigorous scientific methods
- [Run Claude Code programmatically](https://code.claude.com/docs/en/headless) -- Official Claude Code CLI documentation for headless mode
- [Measuring the Impact of Early-2025 AI on Experienced Open-Source Developer Productivity](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) -- Contradictory evidence about AI agent capabilities
- [Terminal-Bench: Benchmarking Agents on Hard, Realistic Tasks in Command Line Interfaces](https://arxiv.org/html/2601.11868v1) -- CLI-specific benchmark challenges and pitfalls

---
*Pitfalls research for: AI coding benchmark suite (gsd-ralph v2.2)*
*Researched: 2026-03-11*
