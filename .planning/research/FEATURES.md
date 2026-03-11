# Feature Research

**Domain:** AI coding tool benchmarking suite (execution mode comparison)
**Researched:** 2026-03-11
**Confidence:** MEDIUM-HIGH

## Feature Landscape

### Table Stakes (Users Expect These)

Features that any credible benchmarking suite must have. Without these, results lack validity and the tool feels amateur.

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| Deterministic environment reset | SWE-bench, Aider, and all credible benchmarks isolate each trial. Anthropic's own eval guidance states "each trial should be isolated by starting from a clean environment." Without this, shared state (git history, leftover files) contaminates results. | LOW | Git tags (`bench/baseline`, `bench/after-delete`) | `bench-reset.sh` with git checkout + verification checksums. Must also clear `.taskctl.json` data files, temp dirs, any caches. Anthropic found Claude gained unfair advantage by examining git history from previous trials -- reset must address this. |
| Automated correctness evaluation | Pass/fail grading without human judgment is the foundation of HumanEval (pass@k), SWE-bench (test patches), and Aider (Exercism tests). Subjective scoring introduces unacceptable noise. | MEDIUM | Challenge project (`taskctl`) with test suite, challenge definitions with expected outcomes | `bench-eval.sh` running Bats tests + custom checks. Each challenge needs unambiguous pass/fail criteria -- Anthropic recommends "two domain experts would independently reach the same verdict." |
| Structured result capture (JSON) | Every benchmark from SWE-bench to BigCodeBench stores results in machine-readable format for aggregation, comparison, and re-analysis. | LOW | Result schema definition | PRD schema is solid. Capture timestamp, mode, challenge, all metrics. Write to `benchmarks/results/{mode}-{challenge}-{timestamp}.json`. |
| Multi-run statistical aggregation | LLMs are non-deterministic even at temperature=0 (batch size variability, prefix caching). Single-run results are scientifically meaningless. Industry standard is minimum 3 runs. | MEDIUM | Result JSON files from multiple runs | `bench-report.sh` computing mean, stddev. The PRD's "flag any result where stddev > 30% of mean" is a good threshold. Research confirms even "deterministic" settings produce variance. |
| Wall-clock time measurement | Universal metric across all AI benchmarks. The most basic efficiency signal. | LOW | Harness start/end timestamps | Use `date +%s` for epoch seconds. Measure from prompt submission to agent completion, not including reset time. |
| Correctness score (0-100%) | Pass@1 is the standard metric in HumanEval, BigCodeBench, and Aider. Binary pass/fail per check, aggregated to percentage. | LOW | `bench-eval.sh` check definitions | Weight all checks equally within a challenge. Don't introduce partial credit -- it adds subjectivity. |
| Regression score | SWE-bench explicitly checks that existing tests still pass after changes. Refactoring and bug-fix challenges are meaningless without regression detection. | LOW | Pre-existing Bats test suite in `taskctl` | Run `test_add.bats` + `test_list.bats` after every challenge. Report as percentage of pre-existing tests still passing. |
| Identical prompts across modes | Fair comparison requires the same task specification. SWE-bench gives the same issue description to every agent; Aider gives the same Exercism problem. | LOW | Prompt template system | Core prompt identical. Only wrapper differs (how to invoke CC vs CC+GSD vs CC+Ralph vs CC+gsd-ralph). The PRD handles this correctly. |
| Comparison report generation | The entire point is cross-mode comparison. Without a readable output, the suite is just a data pipeline. | MEDIUM | Aggregated results across all modes and challenges | Markdown table output. Include raw numbers and derived metrics. Flag high-variance results. |
| Time caps per challenge | Prevents runaway autonomous sessions from consuming infinite resources. Every serious agent benchmark has execution limits. | LOW | Harness timeout mechanism | PRD caps are reasonable (10-20 min). Implement via `timeout` command or wall-clock check in harness loop. Kill and record DNF (did not finish) with partial results. |

### Differentiators (Competitive Advantage)

Features that make this benchmark suite uniquely valuable beyond "yet another AI eval." These exploit the fact that this suite compares *execution modes* of the same underlying model, not different models -- a comparison nobody else is making.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| Token efficiency metric (correctness/tokens) | Cost-per-task-solved is emerging as the key metric (Aider tracks $/task, Artificial Analysis tracks $/task). But this suite can go deeper: same model, different scaffolding, so token differences directly measure scaffolding overhead. This is the headline metric for proving gsd-ralph's value. | LOW | Token counts from `claude --output-format json` | Formula: `correctness_score / total_tokens * 1000`. Also compute raw token cost using current API pricing. This directly answers "does GSD planning save tokens?" |
| Autonomy ratio measurement | Anthropic's own research measures auto-approval rates and interrupt frequency as key autonomy metrics. This suite uniquely compares forced-interactive (CC+GSD) vs fully-autonomous (CC+Ralph, CC+gsd-ralph) on identical tasks. Nobody else measures this. | MEDIUM | Human intervention counting (manual for CC, CC+GSD; zero for Ralph modes) | Define "human intervention" precisely: any manual input after initial prompt. CC mode may need follow-up prompts; CC+GSD has checkpoint approvals; Ralph modes should be zero. Log each intervention with timestamp. |
| Quality-adjusted speed composite | Raw speed is misleading (fast but wrong is worse than slow but correct). The PRD's formula `(Correctness * Regression) / wall_clock_seconds` penalizes both slowness and breakage. This is more useful than any single metric. | LOW | Correctness, regression, and time metrics | This derived metric is the single best number for comparing modes. A mode that's fast but introduces regressions will score poorly. |
| Challenge difficulty gradient | 5 challenges from simple (fix bug) to complex (multi-file integration) reveal where modes diverge. Simple tasks may show no difference; complex tasks should reveal whether planning scaffolding helps. This gradient design is more informative than uniform-difficulty suites. | HIGH (already in PRD) | All 5 challenge definitions + `taskctl` project | The PRD's ordering (fix bug -> add feature -> add tests -> refactor -> multi-file) is well-designed. The key insight: if modes only diverge on Challenge 5, that proves planning helps with complexity. If they diverge on Challenge 1, the scaffolding overhead matters even for simple tasks. |
| Pass^k reliability metric | Anthropic recommends tracking pass^k (all k trials succeed) alongside pass@k (any trial succeeds). Pass^k measures *consistency*, which matters more for production workflows than best-case performance. A mode that succeeds 3/3 times is more trustworthy than one that succeeds 1/3. | LOW | Multiple runs per mode/challenge combination | `pass_at_k = 1 if any run passes, 0 otherwise`. `pass_all_k = 1 if all runs pass, 0 otherwise`. Report both. High pass@k but low pass^k = inconsistent mode. |
| Tool call analysis | Number and type of tool calls reveals agent strategy. Does CC+Ralph make more file reads? Does CC+GSD make fewer edits because planning front-loads decisions? This is unique behavioral data about how scaffolding changes agent behavior. | MEDIUM | Tool call extraction from Claude JSON output | Parse `--output-format json` for tool call counts. Categorize: file reads, file writes, bash commands, search operations. Compare distributions across modes. |
| ShellCheck quality delta | Code quality measurement beyond "does it work." ShellCheck warnings before/after reveal whether a mode produces clean or sloppy code. Useful for the refactoring challenge especially. | LOW | ShellCheck installed, baseline warning count | Run `shellcheck src/**/*.sh` before and after. Delta = after - before. Negative = improved. Requires ShellCheck binary (available via Homebrew). |
| Commit hygiene scoring | Measures whether the agent produces clean, reviewable git history. Professional developers care about commit quality. Modes with planning may produce better commit messages. | LOW | Git log analysis after each run | Count commits, check for conventional commit format, measure commit message length. Simple heuristic scoring. |
| Reproducible run identity | Every run tagged with a unique ID, exact commit hash, exact model version, temperature setting, and timestamp. Enables re-running specific configurations months later. | LOW | Metadata capture in result JSON | Extend result schema with `run_id`, `model_version`, `temperature`, `git_sha`, `harness_version`. Critical for longitudinal comparison if the suite is used across gsd-ralph versions. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem valuable but would add complexity without proportional signal, or would undermine the benchmark's validity.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Partial credit scoring | "An agent that gets 80% of the way there should score higher than one that gets 0%" | Introduces subjectivity. Who decides what "80% done" means? SWE-bench and HumanEval both use binary pass/fail for good reason. Partial credit also makes aggregation ambiguous (is 50% partial on 5 checks better than 100% on 3 checks?). | Binary pass/fail per check, with enough granular checks (5-8 per challenge) that partial completion naturally produces a partial score through the number of checks passed. |
| LLM-as-judge evaluation | "Use Claude to evaluate Claude's code quality" | Circular dependency. The evaluator shares biases with the evaluatee. LLM judges also have poor reproducibility. Anthropic's eval guidance emphasizes objective, automated grading. | Automated checks (tests pass, ShellCheck, file diffs) for objective quality. Save code artifacts for optional human review later. |
| Cross-model benchmarking | "Also compare GPT-4, Gemini, etc." | Scope explosion. Different models need different invocation methods, pricing models, token counting. The PRD explicitly marks this as a non-goal. The scientific question is "does scaffolding help?" not "which model is best?" | Keep model constant (Claude). The variable is execution mode. Cross-model comparison is a future milestone if desired. |
| Real-time progress visualization | "Show live token counts, test results streaming during a run" | Adds complexity to the harness without improving result quality. Observer effect: monitoring overhead could affect performance of modes differently. | Write results to JSON after completion. Use `tail -f` on log files for basic monitoring during development. |
| Weighted challenge scoring | "Multi-file integration should count more than fix-a-bug" | Arbitrary weighting introduces bias toward the designer's assumptions about what matters. Different users value different capabilities. | Report per-challenge results separately. Let consumers weight as they see fit. Provide unweighted aggregate as default. |
| Automated benchmark scheduling (CI/CD) | "Run benchmarks nightly against main" | Each full benchmark run (4 modes x 5 challenges x 3 repeats = 60 runs) costs significant API tokens and takes hours. Nightly runs waste money when code hasn't changed. | Manual trigger via `bench-run.sh`. Run before/after significant changes. Store results with git SHA for version association. |
| Code diff quality analysis | "Measure elegance, readability, idiomatic style beyond ShellCheck" | Highly subjective. No reliable automated measure of code elegance exists. Even human reviewers disagree. | ShellCheck warnings (objective), line count changes (objective), and saved diffs for optional human review capture what can be measured reliably. |
| Interactive mode simulation for CC and CC+GSD | "Automate the human responses in interactive modes to make benchmarks fully unattended" | Scripted human responses are not human responses. The point of comparing interactive vs autonomous modes is measuring what human involvement costs and buys. Faking it defeats the purpose. | For CC and CC+GSD modes, require a human operator. Document the exact interventions made. Accept that these modes produce fewer data points per session. |
| Challenge project in multiple languages | "Test with Python, JavaScript, and Bash projects" | Multiplies challenge project creation effort by 3x. The benchmark measures scaffolding, not language capability. Since all modes use the same model, language shouldn't be a confounding variable. | Bash only (matches gsd-ralph's native language). If language-specific results are needed, that's a separate future benchmark. |

## Feature Dependencies

```
[taskctl Challenge Project]
    |
    |--requires--> [Challenge Definitions (prompts + checks)]
    |                   |
    |                   |--requires--> [bench-eval.sh (correctness evaluation)]
    |                   |
    |                   |--requires--> [bench-reset.sh (environment isolation)]
    |
    |--enables--> [bench-run.sh (execution harness)]
                      |
                      |--requires--> [bench-eval.sh]
                      |--requires--> [bench-reset.sh]
                      |--requires--> [Result JSON schema]
                      |
                      |--enables--> [bench-report.sh (aggregation + comparison)]
                                        |
                                        |--requires--> [Result JSON files from multiple runs]
                                        |--requires--> [Statistical aggregation (mean, stddev)]
                                        |
                                        |--enables--> [Token efficiency analysis]
                                        |--enables--> [Quality-adjusted speed composite]
                                        |--enables--> [Pass@k / Pass^k reliability]
                                        |--enables--> [Tool call analysis]

[bench/baseline git tag] --requires--> [taskctl project at known state]
[bench/after-delete tag] --requires--> [Challenge 2 completed state]
```

### Dependency Notes

- **Challenge Project is the foundation:** Nothing else can be built or tested without `taskctl` at a tagged baseline. This must be Phase 1.
- **eval before run:** `bench-run.sh` invokes `bench-eval.sh` to score each run. Evaluation logic must exist before the harness.
- **reset before run:** `bench-reset.sh` must restore clean state before each trial. Without it, run results are contaminated.
- **run before report:** `bench-report.sh` reads result JSON files that `bench-run.sh` produces. No results, no report.
- **Challenge 5 depends on Challenge 2:** The multi-file integration challenge starts from `bench/after-delete`, which assumes the delete feature exists. This requires either a pre-built tag or a dependency on successfully completing Challenge 2.
- **Statistical metrics require multiple runs:** Pass^k, mean/stddev, and variance flagging all require 3+ runs per combination. Single runs only produce raw numbers.

## MVP Definition

### Launch With (v1 -- this milestone)

The minimum viable benchmark suite that produces credible cross-mode comparison data.

- [ ] **taskctl challenge project** at tagged `bench/baseline` -- the test subject; everything depends on this
- [ ] **5 challenge definitions** with prompts and automated checks -- defines what is measured
- [ ] **bench-reset.sh** -- environment isolation; without it, results are invalid
- [ ] **bench-eval.sh** -- automated pass/fail grading; without it, evaluation is manual
- [ ] **bench-run.sh** with mode-specific invocation -- the execution engine
- [ ] **Structured JSON results** with wall-clock time, correctness, regression, token counts -- raw data capture
- [ ] **bench-report.sh** with markdown comparison table -- the deliverable output
- [ ] **Mean/stddev aggregation** across repeated runs -- statistical minimum for non-deterministic outputs
- [ ] **Token efficiency derived metric** -- the headline number proving (or disproving) gsd-ralph's value
- [ ] **Time caps** per challenge -- prevents runaway sessions

### Add After Validation (v1.x -- if benchmark reveals interesting signals)

Features to add once the core suite is running and producing data.

- [ ] **Pass^k reliability metric** -- add when 3+ runs per combination are available; reveals consistency differences
- [ ] **Tool call analysis** -- add when investigating WHY modes differ; requires parsing Claude JSON output
- [ ] **Quality-adjusted speed composite** -- add to report when basic metrics show modes differ in both speed and quality
- [ ] **Commit hygiene scoring** -- add if early results show modes produce different commit patterns
- [ ] **Autonomy ratio tracking** -- add formal measurement once interactive mode benchmarks include documented human interventions

### Future Consideration (v2+ -- separate milestone)

Features to defer until the benchmarking approach is validated and results are published.

- [ ] **Additional challenge projects** (different languages, larger codebases) -- only if Bash-only results feel too narrow
- [ ] **Cross-version benchmarking** (compare gsd-ralph v2.2 vs v2.3) -- requires stable suite first
- [ ] **Challenge difficulty calibration** -- adjust challenge complexity based on observed pass rates (if everything passes trivially or everything fails)
- [ ] **Longitudinal tracking dashboard** -- only if benchmarks become a regular practice
- [ ] **Community-contributed challenges** -- only if the suite is open-sourced and others adopt it

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority | Rationale |
|---------|------------|---------------------|----------|-----------|
| taskctl challenge project | HIGH | HIGH | P1 | Foundation. Nothing works without it. |
| bench-reset.sh | HIGH | LOW | P1 | Environment isolation is non-negotiable for validity. |
| bench-eval.sh + challenge checks | HIGH | MEDIUM | P1 | Automated evaluation is the core of any benchmark. |
| bench-run.sh mode harness | HIGH | HIGH | P1 | The execution engine. Complex because 4 modes have different invocation patterns. |
| JSON result capture | HIGH | LOW | P1 | Simple file writes. Schema from PRD is ready. |
| bench-report.sh | HIGH | MEDIUM | P1 | The deliverable. Without the report, benchmarks produce data but no insight. |
| Statistical aggregation | MEDIUM | LOW | P1 | Mean/stddev is straightforward math. Critical for credibility. |
| Token efficiency metric | HIGH | LOW | P1 | The headline metric. Division of existing captured values. |
| Time caps | MEDIUM | LOW | P1 | Safety mechanism. Simple `timeout` wrapper. |
| ShellCheck quality delta | MEDIUM | LOW | P2 | Easy to add, provides code quality signal. |
| Pass^k reliability | MEDIUM | LOW | P2 | Simple boolean per run; aggregation is straightforward. |
| Tool call analysis | MEDIUM | MEDIUM | P2 | Requires JSON parsing; valuable for understanding WHY modes differ. |
| Quality-adjusted speed | MEDIUM | LOW | P2 | Derived from existing metrics. Add to report. |
| Commit hygiene | LOW | LOW | P3 | Nice signal but unlikely to differentiate modes meaningfully. |
| Reproducible run identity | MEDIUM | LOW | P2 | Metadata capture is cheap; enables future re-analysis. |

**Priority key:**
- P1: Must have for this milestone's success criteria
- P2: Should have, add when core harness is working
- P3: Nice to have, include if time permits

## Competitor Feature Analysis

These are not direct competitors (nobody benchmarks execution modes of the same tool), but established AI coding benchmarks whose designs inform this suite.

| Feature | SWE-bench | Aider Polyglot | HumanEval | Render Blog Eval | Our Approach |
|---------|-----------|----------------|-----------|-------------------|--------------|
| Challenge source | Real GitHub issues (2,294 tasks) | Exercism exercises (225 tasks) | Synthetic functions (164 tasks) | Production codebases (2 repos) | Custom Bash CLI project (5 challenges) |
| Evaluation method | Patch application + test suite | Exercism test suite pass/fail | Unit test pass@k | Subjective 0-10 scoring | Bats test suite + custom checks |
| Environment isolation | Docker containers per trial | Fresh git checkout | Stateless function execution | Manual setup | Git tag checkout + checksum verification |
| Statistical handling | Single run (cost prohibitive at scale) | Single run per model | Multiple samples for pass@k | Single subjective run | 3+ runs with mean/stddev/variance flagging |
| Cost tracking | Not tracked | $/task from API pricing | Not tracked | Subscription pricing noted | Token counts + derived cost efficiency |
| Multi-file tasks | Yes (average 4.1 files in SWE-bench Pro) | No (single file per exercise) | No (single function) | Yes (production repos) | Yes (Challenge 5 spans 3+ files) |
| Measures scaffolding | No (measures model capability) | No (measures model + edit format) | No (measures model capability) | Partially (compares tools) | Yes (same model, different scaffolding -- core differentiator) |
| Difficulty gradient | Mixed difficulty, no explicit ordering | Uniform Exercism difficulty | Uniform function difficulty | Two difficulty levels (vibe vs production) | 5 levels, explicitly ordered simple to complex |
| Autonomy measurement | Not measured (all autonomous) | Not measured (all autonomous) | Not applicable | Subjective "follow-up prompts needed" | Formal intervention counting with interactive/autonomous distinction |

### Key Takeaways from Competitor Analysis

1. **SWE-bench's strength is realism** (real issues from real repos), but its weakness is cost and reproducibility (single runs). Our suite trades realism for tight control -- same model, same project, different scaffolding.

2. **Aider's strength is multi-language coverage and cost tracking** ($/task). We should adopt cost tracking but skip multi-language (our variable is mode, not language).

3. **HumanEval's strength is statistical rigor** (pass@k across multiple samples). We adopt this with pass@k and pass^k.

4. **Render's weakness is subjective scoring** (0-10 human ratings). We avoid this entirely with automated checks.

5. **Nobody measures scaffolding impact.** Every existing benchmark compares models or tools. We compare execution modes of the same model+tool combination. This is our unique contribution.

## Metrics That Differentiate vs. Metrics That Are Noise

Based on research into what actually varies across execution modes.

### High Signal (likely to differentiate modes)

| Metric | Why It Differentiates | Expected Pattern |
|--------|----------------------|------------------|
| **Token efficiency** (correctness/tokens) | Planning scaffolding (GSD) front-loads context, potentially reducing exploration tokens. Autonomous modes (Ralph) may loop more. | CC+GSD and CC+gsd-ralph should use fewer total tokens per correct solution than CC alone. Ralph may use more tokens due to looping but achieve higher correctness. |
| **Wall-clock time** | Interactive modes block on human input. Autonomous modes run continuously but may loop. | CC and CC+GSD will be slowest (human bottleneck). CC+Ralph should be fastest (no human, no planning overhead). CC+gsd-ralph is between. |
| **Correctness on complex tasks** (Challenge 4, 5) | Planning helps decompose complex tasks. Simple tasks may not benefit from structure. | Expect modes to converge on Challenges 1-3 but diverge on 4-5. If GSD planning helps, CC+GSD and CC+gsd-ralph should outperform on multi-file work. |
| **Regression score** | Planning modes should be more careful about preserving existing behavior. Unstructured prompting may cause collateral damage. | CC (no structure) may have lower regression scores. GSD modes should preserve existing tests more consistently. |
| **Pass^k consistency** | Autonomous modes with circuit breakers may be more consistent. Ad-hoc prompting has higher variance. | Ralph modes should show lower variance (circuit breakers, structured loops). CC should show highest variance. |

### Low Signal (unlikely to differentiate, or too noisy to interpret)

| Metric | Why It's Noise | Keep or Drop |
|--------|----------------|--------------|
| **Commit count** | Varies wildly based on agent style, not mode quality. Some agents commit per file, others commit once. | DROP from primary metrics. Capture but don't report prominently. |
| **Lines of code changed** | More code is not better or worse. Depends on task. A minimal fix is better for Challenge 1; more code is expected for Challenge 2. | DROP as a comparison metric. Use only as a sanity check (refactoring challenge should show meaningful diff). |
| **ShellCheck delta on non-refactoring challenges** | For bug fixes and feature additions, ShellCheck changes are incidental. Only meaningful for Challenge 4 (refactor). | KEEP for Challenge 4 only. Drop for others. |
| **Conventional commit compliance** | Style choice, not quality signal. Easy to add to prompts but doesn't measure capability. | DROP from primary comparison. Interesting trivia at best. |
| **Raw tool call count** | More tool calls could mean thorough investigation or aimless flailing. Count alone doesn't distinguish. | KEEP but analyze patterns (read vs write ratio) rather than raw count. |

## Challenge Design Best Practices (from Research)

Based on analysis of SWE-bench, Aider, HumanEval, and Anthropic's eval guidance.

### 1. Unambiguous Success Criteria
Anthropic: "A good task is one where two domain experts would independently reach the same pass/fail verdict." Every check in the PRD is binary and automatable. Maintain this rigor.

### 2. Test Both Positive and Negative Cases
Anthropic: "Testing both when behaviors should occur and when they shouldn't." Challenge 2's "delete 999 prints error" is a good negative test. Ensure each challenge has at least one negative case.

### 3. Prevent Git History Contamination
Anthropic discovered Claude examined git history from previous trials to gain unfair advantage. `bench-reset.sh` must not just checkout the tag but also clear any stale branches, stashes, or reflog entries that could leak information between runs.

### 4. Verify Starting State
SWE-bench verifies environment before each run. `bench-reset.sh` should checksum key files against known-good values to detect contamination.

### 5. Reference Solutions Prove Solvability
Anthropic: "Create reference solutions proving each task is solvable." Build and verify a human solution for each challenge. Store in `benchmarks/challenges/{name}/reference/` but exclude from the working directory during runs.

### 6. Time Caps Must Produce Partial Results
When a run hits the time cap, capture whatever metrics are available (tokens used, tool calls made, partial correctness). A DNF with 80% correctness is more informative than a binary "timeout."

### 7. Challenge Independence
Challenges 1-4 all start from `bench/baseline` independently. Challenge 5 starts from `bench/after-delete`. This means Challenges 1-4 can run in any order, but Challenge 5 requires a pre-built tag. Ensure `bench/after-delete` is committed to the repo, not dynamically generated.

## Sources

- [SWE-bench Verified](https://epoch.ai/benchmarks/swe-bench-verified) -- benchmark design, environment methodology
- [SWE-bench Pro paper](https://arxiv.org/abs/2509.16941) -- long-horizon task design, multi-file complexity
- [Aider Polyglot Leaderboard](https://aider.chat/docs/leaderboards/) -- metrics tracked, cost-per-task, two-attempt methodology
- [HumanEval / BigCodeBench](https://huggingface.co/blog/leaderboard-bigcodebench) -- pass@k methodology, calibrated scoring
- [Anthropic: Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) -- environment isolation, challenge design, pass@k vs pass^k
- [Anthropic: Measuring Agent Autonomy](https://www.anthropic.com/research/measuring-agent-autonomy) -- autonomy ratio, intervention tracking
- [Render Blog: AI Coding Agents Benchmark](https://render.com/blog/ai-coding-agents-benchmark) -- practical evaluation methodology for coding tools
- [LLM Non-Determinism at temperature=0](https://arxiv.org/html/2408.04667v5) -- statistical validity concerns
- [Towards Reproducible LLM Evaluation](https://arxiv.org/html/2410.03492v2) -- uncertainty quantification in benchmarks
- [NAACL 2025: LLM Evaluation Should Not Ignore Non-Determinism](https://aclanthology.org/2025.naacl-long.211.pdf) -- statistical methodology for LLM benchmarks
- [Failing Fast: AI Coding Benchmarks](https://failingfast.io/ai-coding-guide/benchmarks/) -- $/task metric, benchmark limitations
- [AI Coding Benchmark: Claude Code vs Cursor](https://aimultiple.com/ai-coding-benchmark) -- tool comparison methodology

---
*Feature research for: AI coding tool benchmarking suite (execution mode comparison)*
*Researched: 2026-03-11*
