# Project Research Summary

**Project:** gsd-ralph v2.2 Benchmarking Suite
**Domain:** Automated benchmarking harness comparing 4 Claude Code execution modes on coding tasks
**Researched:** 2026-03-11
**Confidence:** HIGH

## Executive Summary

The v2.2 milestone adds a benchmarking suite to gsd-ralph that compares four execution modes — vanilla Claude Code (CC), CC with GSD planning context (CC+GSD), CC with Ralph's external loop engine (CC+Ralph), and CC with Agent-based gsd-ralph (CC+gsd-ralph) — on a purpose-built Bash CLI challenge project called `taskctl`. The benchmark's unique angle is that it holds the model constant and varies only the scaffolding, a comparison nobody in the existing benchmark landscape makes. This means differences in correctness, speed, and token usage directly measure the cost and benefit of each scaffolding approach, answering the question the entire gsd-ralph project is built around: does structured AI execution scaffolding produce better outcomes?

The stack requires zero new dependencies. Every capability needed — timing, statistical aggregation, JSON metrics, markdown/CSV report generation, and challenge evaluation — is available through the existing Bash + jq + Bats + ShellCheck stack already in the repo. The architecture is a clean five-component pipeline: challenge project (taskctl), reset harness, mode-specific invocation layer, correctness evaluation, and report generator. The harness lives entirely in `benchmarks/` and never modifies existing gsd-ralph scripts, making the production scripts the subjects under test rather than participants in the test infrastructure.

The most significant risks are methodological, not technical. LLM non-determinism at N=3 produces uninterpretable statistics; the CC+GSD interactive mode cannot be fairly automated alongside three autonomous modes; token counts are not directly comparable across modes with different context architectures; and correctness checks frequently reject valid alternative solutions. All four risks have concrete mitigations identified in research. Addressing them during the challenge design and harness phases — before any benchmark data is collected — avoids wasting expensive benchmark runs on invalid data.

## Key Findings

### Recommended Stack

See `.planning/research/STACK.md` for full details.

The benchmarking suite adds zero new runtime dependencies. jq 1.8.1 (already required) serves as the statistics engine: it natively computes mean, population stddev, and variance flagging, and generates all three output formats (JSON, markdown, CSV). Claude Code CLI's `--output-format json` flag provides `duration_ms`, `num_turns`, `total_cost_usd`, and `usage.input_tokens`/`usage.output_tokens` directly. Git tags (`bench/baseline`, `bench/after-delete`) manage challenge state in place of Docker or other isolation approaches. The deliberate choice to stay within the existing stack keeps the harness consistent with gsd-ralph conventions and eliminates developer environment setup.

**Core technologies:**
- Bash 3.2: Harness scripts — matches gsd-ralph's language, consistent patterns with existing scripts
- jq 1.8.1: Statistics engine + report generation — `sqrt`, `group_by`, `@csv` cover all needed math without external tools
- Claude Code CLI 2.1.72+: Benchmark execution + `--output-format json` metrics capture per run
- Bats 1.13.0 (vendored): Challenge project tests + correctness evaluation runner, already in `tests/bats/`
- Git 2.20+: Challenge state management via tags and harness-managed worktrees for run isolation
- ShellCheck 0.11.0: Code quality metric (warning delta) for the refactoring challenge, already installed

### Expected Features

See `.planning/research/FEATURES.md` for full details.

The benchmark's unique differentiation is measuring scaffolding impact on the same model, specifically: token efficiency (correctness per token), pass^k consistency (do ALL k runs succeed, not just one), and quality-adjusted speed. These go beyond what any existing benchmark tracks because no existing benchmark holds model constant while varying execution mode.

**Must have (table stakes):**
- `taskctl` challenge project at `bench/baseline` git tag — foundation; nothing else works without it
- Deterministic environment reset (`bench-reset.sh`) — without it, results are scientifically invalid
- Automated correctness evaluation (`bench-eval.sh`) with binary pass/fail checks — subjective scoring is unacceptable
- Structured JSON result capture per run — machine-readable, comparable, re-analyzable
- Multi-run statistical aggregation (`bench-report.sh`) — N=1 results are meaningless for non-deterministic models
- Wall-clock time measurement — universal efficiency signal
- Token efficiency metric (correctness/tokens) — the headline number showing scaffolding value
- Time caps per challenge — prevents runaway autonomous sessions from consuming unbounded API resources

**Should have (competitive differentiators):**
- Pass^k reliability metric — consistency across all k runs matters more than best-case for production workflows
- Tool call analysis — reveals HOW modes differ, not just WHETHER they differ
- Quality-adjusted speed composite — `(correctness * regression) / wall_clock` penalizes both slowness and breakage
- ShellCheck quality delta — objective code quality signal for the refactoring challenge specifically
- Reproducible run identity — `run_id`, model version, git SHA in every result for longitudinal comparison

**Defer to v1.x / v2+:**
- Additional challenge projects (other languages, larger codebases)
- Cross-version benchmarking (gsd-ralph v2.2 vs v2.3 comparison)
- Longitudinal tracking dashboard
- CI/CD automated scheduling (cost-prohibitive for routine runs at 4 modes x 5 challenges x N runs)
- Community-contributed challenges

### Architecture Approach

See `.planning/research/ARCHITECTURE.md` for full details.

The harness uses five architectural patterns: a mode abstraction layer (each mode is one file in `harness/lib/modes/` with an identical function signature), declarative challenge definitions (JSON files, not Bash variables), harness-managed git worktrees for run isolation (not Claude's `--worktree` flag, which targets the wrong repo), defensive metric extraction with `// 0` jq fallbacks, and GSD scaffolding generation for Ralph/gsd-ralph modes. The challenge project is a standalone `taskctl` Bash CLI with planted defects, partial test coverage, and known-good git tags. Nothing in the existing gsd-ralph codebase is modified.

**Major components:**
1. `benchmarks/taskctl/` — Challenge project (standalone Bash CLI with planted bug in `done.sh`, missing tests, messy `format.sh`); tagged at `bench/baseline` and `bench/after-delete`
2. `benchmarks/harness/bench-reset.sh` — Creates isolated git worktree per run, validates checksums, clears `.ralph/` state, runs `git clean -fdx`
3. `benchmarks/harness/bench-run.sh` — Orchestrates: reset, scaffold, pre-metrics, invoke mode, post-metrics, eval, write result JSON
4. `benchmarks/harness/lib/modes/*.sh` — CC, GSD, Ralph, gsd-ralph invocation logic behind identical function contracts
5. `benchmarks/harness/bench-eval.sh` + `lib/checks/*.sh` — Per-challenge correctness evaluation returning structured pass/fail JSON
6. `benchmarks/harness/bench-report.sh` — Aggregates result JSONs, computes statistics, generates markdown/CSV/JSON report
7. `benchmarks/challenges/*.json` — Declarative challenge definitions (prompt, starting tag, time cap, check script reference)

### Critical Pitfalls

See `.planning/research/PITFALLS.md` for full details.

1. **Apples-to-oranges token comparison across modes** — Each mode has a different context architecture. CC+Ralph pays re-encoding costs every iteration; CC+gsd-ralph's orchestration tokens accumulate in the parent session; CC+GSD has no `--output-format json`. Mitigation: define "total token budget" as ALL tokens across all invocations per run, use JSONL session files as ground truth, report overhead vs task tokens separately.

2. **N=3 insufficient for stable LLM statistics** — With binary pass/fail checks worth 20-25% each, one check flipping produces a 20-25% correctness swing. At N=3, stddev becomes meaningless. Mitigation: increase to N=5 minimum; report median + IQR instead of mean + stddev; define a "reliability rate" (% of runs achieving >= 80% correctness) as the primary metric.

3. **CC+GSD mode cannot be fairly automated** — Auto-approving checkpoints removes the human judgment that defines CC+GSD's value proposition. Mitigation: run CC+GSD as a human-in-the-loop mode with N=1-2, document it as a separate methodology, group autonomous modes (CC, CC+Ralph, CC+gsd-ralph) separately in the report.

4. **Correctness checks rejecting valid alternative solutions** — Checks written around one expected approach fail valid implementations. Mitigation: write behavioral checks (does the feature work?) not structural checks (does this specific file exist?); create reference solutions; verify checks fail baseline AND pass reference solutions before running any benchmark.

5. **Git state contamination between runs** — `git checkout <tag>` alone does not clean untracked files or git reflog. An LLM that runs `git log` during a benchmark can see prior run commits. Mitigation: `git clean -fdx` + clear `.ralph/` state files + harness-managed worktrees per run + checksum verification.

6. **Measuring harness overhead instead of LLM performance** — CC+Ralph has 15-45 seconds of startup overhead (context assembly, circuit breaker init) that inflates its wall-clock time vs CC mode. Mitigation: instrument the inner `claude -p` invocation not the outer script wrapper; measure per-mode startup overhead baseline separately; run benchmarks in standalone `taskctl` repo not gsd-ralph's full repo.

## Implications for Roadmap

Architecture research explicitly recommends a five-phase build order. Feature research confirms challenge project is the foundation dependency. Pitfalls research adds cross-cutting requirements (pilot runs, behavioral checks, reset verification) that belong inside specific phases.

### Phase 1: Challenge Project (taskctl)

**Rationale:** Everything else depends on having a real, testable challenge project at a known git state. This is the most foundational dependency in the entire feature graph. No harness can be built or tested without a challenge project to run against.
**Delivers:** `benchmarks/taskctl/` with planted bug in `done.sh` (off-by-one on task ID), 7 passing Bats tests (add + list), messy `format.sh` as refactoring target, sample `.taskctl.json` data, `bench/baseline` git tag, CLAUDE.md and README.md.
**Addresses:** FEATURES.md P1 table-stakes foundation; Pitfall 3 (training data contamination) — design replaceability from day one (harness must not hardcode taskctl-specific paths); Pitfall 10 (refactoring quality) — design `format.sh` as a genuine, meaningful refactoring target.
**Avoids:** Hardcoding harness scripts to taskctl-specific paths (PITFALLS.md technical debt pattern: "never — abstract eval checks behind challenge-specific config files from day one").
**Research flag:** No further research needed. Standard Bash CLI with Bats tests; patterns well-established in existing repo.

### Phase 2: Correctness Checks + Challenge Definitions

**Rationale:** Evaluation must exist and be validated before automated runs. Running the harness against unchecked evaluation logic wastes expensive benchmark compute. This phase creates reference solutions, verifies negative controls (checks fail at baseline), positive controls (checks pass reference solutions), and creates the `bench/after-delete` tag for Challenge 5 — eliminating the chicken-and-egg dependency before Phase 3.
**Delivers:** `harness/lib/checks/*.sh` for all 5 challenges with behavioral (not structural) checks; `harness/bench-eval.sh` dispatcher; `challenges/*.json` declarative definitions; `bench/after-delete` tag (manual Challenge 2 completion); reference solutions for all 5 challenges.
**Addresses:** Pitfall 5 (correctness checks rejecting valid solutions) — behavioral checks, reference solutions, enumerate 3+ alternative valid approaches per challenge; Pitfall 10 (refactoring quality via line-count proxies) — multi-signal quality assessment for Challenge 4, drop "diff > 10 lines" requirement; FEATURES.md challenge design best practices (unambiguous criteria, negative test cases).
**Avoids:** Structural checks (file existence) vs behavioral checks (feature works); scheduling Challenge 5's `bench/after-delete` dependency as a runtime concern.
**Research flag:** No further research needed. Bats assertion patterns are well-understood; reference FEATURES.md challenge design best practices directly.

### Phase 3: Harness Core + CC Mode

**Rationale:** Build the minimum viable end-to-end pipeline with the simplest mode (direct `claude -p`) to validate the full architecture before adding complexity. If the pipeline has structural issues, fix them here with low API cost before multiplying by 4x modes.
**Delivers:** `bench-reset.sh` (git worktree + `git clean -fdx` + `.ralph/` state cleanup + checksum verification); `bench-run.sh` orchestrator; `harness/lib/common.sh`; `harness/lib/metrics.sh` with defensive jq extraction; `harness/lib/modes/cc.sh`; first valid result JSON files.
**Addresses:** Pitfall 8 (git state contamination) — full reset protocol including worktree isolation built in from the start; Pitfall 9 (measuring harness overhead) — instrument inner `claude -p` invocation, not outer wrapper; table-stakes features: bench-reset, JSON capture, time caps as safety valves.
**Avoids:** Using Claude's `--worktree` flag (ARCHITECTURE.md anti-pattern 2 — targets gsd-ralph repo not taskctl); relying on JSONL as primary metric source (ARCHITECTURE.md anti-pattern 4 — fragile across CLI versions).
**Research flag:** Claude Code JSON output field names have evolved across versions. ARCHITECTURE.md flags `usage.input_tokens`/`usage.output_tokens` as MEDIUM confidence. Implement defensive jq extraction (`// 0` fallbacks) from the start and validate against the current CLI version (2.1.72) before Phase 5.

### Phase 4: Remaining Modes (GSD, Ralph, gsd-ralph)

**Rationale:** Build the three additional modes in complexity order — GSD (adds context file assembly, no scaffolding), Ralph (adds GSD scaffolding + launcher integration), gsd-ralph (most complex: commands + skills + Agent tool). Each is incremental on the validated harness from Phase 3. Sub-ordering within Phase 4 is important: don't attempt gsd-ralph before Ralph is working.
**Delivers:** `harness/lib/modes/gsd.sh`, `ralph.sh`, `gsd-ralph.sh`; GSD scaffolding templates (minimal STATE.md, config.json, PLAN.md) for Ralph modes; methodology documentation for CC+GSD as human-in-the-loop mode.
**Addresses:** Pitfall 1 (asymmetric token comparison) — each mode script captures ALL tokens for that mode's invocation pattern, including orchestration overhead; Pitfall 7 (CC+GSD automation) — implement CC+GSD with explicit human-in-the-loop path and separate methodology documentation; FEATURES.md autonomy ratio measurement.
**Avoids:** Modifying `ralph-launcher.sh` for benchmarking (ARCHITECTURE.md anti-pattern 1 — the launcher is the thing being benchmarked); running benchmarks inside gsd-ralph's repo (PITFALLS.md technical debt — context assembly inflates Ralph/gsd-ralph token counts).
**Research flag:** The CC+gsd-ralph mode invocation (wrapping `/gsd:ralph` via Agent tool in headless `claude -p`) has MEDIUM confidence. The exact `--allowedTools` list and command discovery behavior need a validation pilot run before committing to the full design. Run one challenge with gsd-ralph mode early in Phase 4 before building the remaining two mode scripts.

### Phase 5: Report Generator + Full Benchmark Runs

**Rationale:** Report generation is the capstone. Running all 4 modes x 5 challenges x N runs is the longest step (potentially 20+ hours of API compute). Run pilot runs first to calibrate time caps, check variance thresholds, and validate per-mode token capture before committing to the full matrix. Do not skip pilots — PITFALLS.md rates "skipping pilot runs" as never acceptable.
**Delivers:** `bench-report.sh` with median/IQR aggregation, markdown comparison table, CSV output, and high-variance flagging; pilot run results (1-2 runs per challenge to calibrate time caps and N); full N=5 result matrix (100 result JSON files); `REPORT.md` comparison report with methodology notes.
**Addresses:** Pitfall 2 (N=3 insufficient) — use N=5, report median + IQR not mean + stddev; Pitfall 6 (vanity metrics) — apply "decision test" to each metric, suppress autonomy ratio (always 1.0 for autonomous modes), suppress commit count and raw lines-changed; FEATURES.md P2 features: quality-adjusted speed composite, pass^k reliability.
**Avoids:** Drawing conclusions from high-variance data; reporting decimal precision on ordinal correctness scores (which have discrete values 0/25/50/75/100%); including CC+GSD in the same statistical table as autonomous modes without explicit methodology disclaimer.
**Research flag:** Statistical methodology for small-N LLM benchmarks is nuanced. Review PITFALLS.md sections on median/IQR and reliability rate before finalizing report format. Calibrate the "high variance" threshold from pilot data rather than using the PRD's fixed 30%-of-mean threshold.

### Phase Ordering Rationale

- **Phases 1-2 are pure design/build phases** requiring zero benchmark runs and zero API costs. Getting challenge design and evaluation logic right before running anything avoids wasting compute on invalid data.
- **Phase 3 validates architecture with minimal investment** — one mode, a few trial runs. If the pipeline is broken (reset doesn't clean properly, JSON parsing fails, result schema is wrong), fix it at 1x cost not 4x.
- **Phase 4 builds modes in complexity order** — GSD (flag addition), Ralph (scaffolding + launcher), gsd-ralph (Agent tool orchestration). Each is testable independently.
- **Phase 5 runs the full matrix only after all infrastructure is validated** — prevents the expensive "discover the reset is broken after 40 runs" scenario that PITFALLS.md rates as HIGH recovery cost.
- **The `bench/after-delete` tag is created in Phase 2**, not Phase 5, eliminating the chicken-and-egg dependency identified in ARCHITECTURE.md where Challenge 5 requires Challenge 2 to have been completed.

### Research Flags

Phases likely needing deeper research or validation during planning:
- **Phase 4 (CC+gsd-ralph mode):** The exact invocation pattern for `/gsd:ralph` via Agent tool in headless `claude -p` needs a validation pilot. ARCHITECTURE.md notes medium confidence on Agent tool + headless behavior with `--allowedTools`.
- **Phase 5 (Statistical thresholds):** Calibrate the "high variance" threshold and N via pilot runs before setting in stone. PITFALLS.md recommends measuring baseline coefficient of variation before committing to thresholds.

Phases with standard patterns (skip research-phase):
- **Phase 1 (taskctl):** Standard Bash CLI with Bats tests. Well-documented patterns already in the repo.
- **Phase 2 (correctness checks):** Bats assertion patterns are well-understood. Reference FEATURES.md challenge design best practices directly.
- **Phase 3 (harness core + CC mode):** `claude -p --output-format json` with defensive jq extraction is well-documented in STACK.md and ARCHITECTURE.md.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools verified on target system (macOS 26.3.1); jq statistics tested locally; Claude Code CLI JSON fields cross-referenced against official docs and community sources |
| Features | MEDIUM-HIGH | Table stakes derived from SWE-bench/Aider/HumanEval analysis; differentiators are novel (no direct comparables); MVP scope is well-reasoned but actual signal differentiation depends on real run data |
| Architecture | HIGH | Existing codebase inspected; Claude Code JSON output verified against official docs; build order confirmed against FEATURES.md dependency graph; anti-patterns identified from real integration constraints |
| Pitfalls | HIGH | Grounded in post-mortems from SWE-bench, Aider, and METR; gsd-ralph codebase analyzed for mode-specific integration gotchas; statistical methodology from peer-reviewed sources |

**Overall confidence:** HIGH

### Gaps to Address

- **Claude Code `--output-format json` field evolution:** The `usage.input_tokens` / `usage.output_tokens` field names have evolved across CLI versions. ARCHITECTURE.md flags this as MEDIUM confidence. Mitigation: defensive jq extraction from Phase 3 onward; validate against current CLI version (2.1.72) before Phase 5.
- **CC+gsd-ralph headless invocation:** How `/gsd:ralph` behaves when invoked via `claude -p` in headless mode with the Agent tool is not fully documented. A Phase 4 pilot run is required before committing to the mode's invocation design.
- **N and variance calibration:** PITFALLS.md strongly recommends N=5 minimum and pilot-based variance threshold calibration. The PRD specifies N=3. Resolve this gap in Phase 5 planning — use pilot runs to justify the final N before committing to the full matrix.
- **CC+GSD methodology decision:** Whether CC+GSD results appear in the main comparison table or a separate section is an open design question. Research recommends separate methodology grouping; the PRD treats it as a parallel mode. Decide before Phase 4 implementation to avoid rework in the report template.

## Sources

### Primary (HIGH confidence)
- [Claude Code Headless Mode docs](https://code.claude.com/docs/en/headless) — `--output-format json` fields, `--max-turns`, `--no-session-persistence`
- [Claude Code CLI Reference](https://code.claude.com/docs/en/cli-reference) — all flags including `--allowedTools`, `--append-system-prompt-file`
- [jq 1.8 Manual](https://jqlang.github.io/jq/manual/) — `sqrt`, `group_by`, `@csv`, `round` built-ins
- [Anthropic: Demystifying Evals for AI Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents) — environment isolation, challenge design, pass@k vs pass^k
- [Anthropic: Measuring Agent Autonomy](https://www.anthropic.com/research/measuring-agent-autonomy) — autonomy ratio, intervention tracking
- Local system verification — all tools tested on macOS 26.3.1; jq statistics, Claude Code CLI JSON output, Bats vendored libraries
- Existing gsd-ralph codebase — `ralph-launcher.sh`, `assemble-context.sh`, `validate-config.sh`, `tests/test_helper/common.bash`

### Secondary (MEDIUM confidence)
- [Aider Polyglot Leaderboard](https://aider.chat/docs/leaderboards/) — cost-per-task, two-attempt methodology
- [SWE-bench Verified](https://epoch.ai/benchmarks/swe-bench-verified) — benchmark design, environment methodology
- [HumanEval / BigCodeBench](https://huggingface.co/blog/leaderboard-bigcodebench) — pass@k methodology, calibrated scoring
- [Claude Code CLI JSON output fields](https://introl.com/blog/claude-code-cli-comprehensive-guide-2025) — community-documented field names consistent with official docs
- [Runloop: SWE-bench Deep Dive](https://runloop.ai/blog/swe-bench-deep-dive-unmasking-the-limitations-of-a-popular-benchmark) — solution leakage, false positive rates
- [NAACL 2025: LLM Evaluation Should Not Ignore Non-Determinism](https://aclanthology.org/2025.naacl-long.211.pdf) — statistical methodology for small-sample LLM benchmarks
- [METR: Measuring the Impact of Early-2025 AI](https://metr.org/blog/2025-07-10-early-2025-ai-experienced-os-dev-study/) — contradictory evidence about AI agent capabilities in real coding tasks

### Tertiary (LOW confidence, used for context)
- [SWE-bench Illusion paper](https://arxiv.org/html/2506.12286v3) — memorization vs reasoning findings (needs validation against current models)
- [LLM Non-Determinism at temperature=0](https://arxiv.org/html/2408.04667v5) — statistical validity concerns at N=3

---
*Research completed: 2026-03-11*
*Ready for roadmap: yes*
