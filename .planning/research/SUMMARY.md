# Project Research Summary

**Project:** gsd-ralph
**Domain:** CLI orchestration tool for parallel autonomous coding agents via git worktrees
**Researched:** 2026-02-13
**Confidence:** MEDIUM (comprehensive codebase analysis and training data; no live external verification available)

## Executive Summary

gsd-ralph orchestrates parallel autonomous coding agents (Ralph/Claude Code) across isolated git worktrees to execute GSD-planned development phases. The research reveals this is a **bash-based process orchestrator with distributed system characteristics** masquerading as a simple CLI tool. The recommended architecture uses pure bash with structured project layout (no Node.js runtime dependency), git worktrees for filesystem isolation, and event-driven status monitoring.

The critical insight from research: this tool bridges two worlds—GSD's structured planning framework and Ralph's autonomous execution loop—and must manage the impedance mismatch between sequential plan dependencies and parallel worktree execution. The core technical challenges are **git lock contention from concurrent commits**, **merge order sensitivity** that can silently corrupt work, and **unreliable agent status reporting** that breaks automation. Success requires treating worktrees as first-class managed resources with a registry manifest, implementing retry loops around all git operations, and never trusting agent status without verification.

The path to a working tool is clear but narrow: build the worktree management layer with proper registry/cleanup from day one (avoid orphaned worktree debt), implement status monitoring with heartbeat verification before depending on it for automation, and make merge orchestration conservative with test-after-each-merge and rollback support. The existing proof-of-concept scripts validate the approach but reveal 14+ pitfalls that must be designed out, not patched later.

## Key Findings

### Recommended Stack

The foundational constraint "bash-based CLI for portability, same ecosystem as Ralph" drives all stack decisions. Building in Node.js would contradict the "no exotic dependencies" requirement and add installation friction. The existing scripts prove bash is sufficient.

**Core technologies:**
- **Bash 3.2+**: Script runtime targeting macOS default version (avoid bash 4+ features like associative arrays)
- **Git 2.20+**: Worktree management; stable `git worktree list --porcelain` for state inspection
- **jq 1.6+**: JSON parsing for status.json aggregation across worktrees
- **Python 3.8+**: XML task extraction from GSD plans (already used in existing scripts; ships with macOS)
- **bats-core 1.11+**: Test framework (dev dependency only; the standard for bash testing)
- **ShellCheck 0.10+**: Static analysis (dev dependency only; non-negotiable for bash projects)

**Project structure:**
- `bin/gsd-ralph` entry point with subcommand dispatch
- `lib/*.sh` for shared functions (config, git, templates, process management, notifications)
- `lib/commands/*.sh` for subcommands (init, execute, status, merge, cleanup)
- `templates/*.template` for prompt generation (already exist; use sed-based variable substitution)
- `tests/*.bats` for comprehensive test coverage (critical given bash's fragility)

**Template rendering:** Sed-based substitution on `{{VARIABLE}}` placeholders. Avoids envsubst dependency and keeps templates as standalone files.

**Process management:** Start with foreground mode (user opens terminals manually, matching existing behavior). Background mode with PID tracking is a later enhancement.

### Expected Features

Research reveals gsd-ralph occupies a unique niche: no competitor bridges structured planning into parallel autonomous execution with worktree isolation. Most AI coding tools are single-agent (aider, Claude Code) or simple multi-session managers. None understand GSD planning dependencies.

**Must have (table stakes):**
- **Project init** (`gsd-ralph init`) — detect project type, generate .ralph/ configs, PROMPT.md template, .ralphrc
- **Phase execution** (`gsd-ralph execute N`) — discover GSD plans, create worktrees, generate prompts, launch Ralph instances
- **Status monitoring** (`gsd-ralph status N`) — color-coded overview reading status.json from each worktree
- **Terminal bell on completion/failure** — passive notification (trivial but explicitly required)
- **Auto-merge** (`gsd-ralph merge N`) — sequential merge in plan order with conflict guidance; default behavior
- **Review mode** (`gsd-ralph merge N --review`) — safety valve; show diff and prompt for approval
- **Cleanup** (`gsd-ralph cleanup N`) — remove worktrees, delete merged branches, prune references

**Should have (competitive differentiators):**
- **GSD dependency graph awareness** — refuse to execute Phase N if Phase N-1 incomplete; no other tool understands structured dependencies
- **Plan-level worktree isolation** — not just branch isolation but filesystem isolation preventing accidental interference
- **Completion detection with auto-merge** — watch status.json across worktrees, auto-trigger merge when all complete
- **Pre-merge test run** — run test suite on each branch before merging; reject failing branches
- **Dry-run mode** (`--dry-run`) — show what would happen without creating worktrees; minimal cost, high value
- **Structured execution log** — generate summary after phase completes (which plans, timing, commits, issues) in EXECUTION_LOG.md

**Defer (v2+):**
- **Phase chaining** (`--continue`) — auto-execute Phase N+1 when Phase N completes; requires robust error handling
- **Single-command full lifecycle** (`--auto`) — composes execute + monitor + merge + cleanup; the north star but requires all pieces solid first
- **Watch mode** (`status --watch`) — auto-refresh display; quality-of-life enhancement
- **Resume/retry** — restart failed plans without touching completed worktrees; error recovery is important but can ship after core flow works

**Critical gap in existing scripts:** They only CREATE worktrees and instruct user to `cd && ralph` manually. True execution orchestration requires launching Ralph processes (even if just via background spawn or tmux). This is the difference between "worktree setup tool" and "execution orchestrator."

### Architecture Approach

The architecture is a **pipeline-with-feedback**: linear flow from plan parsing through execution, with a monitoring loop feeding status back to the user. The system has distributed characteristics (multiple autonomous agents, shared state via git, concurrent filesystem access) but should be implemented as a **single-process orchestrator** spawning Ralph as child processes.

**Major components:**
1. **GSD Plan Parser** — read `.planning/` structure, parse XML tasks, handle dual naming conventions (PLAN.md vs NN-MM-PLAN.md); outputs normalized TaskGraph
2. **Worktree Manager** — create/list/remove git worktrees with clean branch naming; maintains worktree registry manifest (the source of truth)
3. **Prompt Generator** — transform TaskGraph into PROMPT.md, fix_plan.md, .ralphrc per worktree using templates
4. **Ralph Launcher** — spawn Ralph processes, manage PIDs, capture output streams
5. **Status Monitor** — track progress across worktrees, aggregate status, detect completion/failure; implements heartbeat verification
6. **Merge Orchestrator** — auto-merge branches in dependency order, pre-check merge-ability, handle conflicts, preserve rollback points
7. **Notification System** — terminal bell + stdout messages on events (completion, conflict, failure)

**Critical patterns:**
- **Command pattern for CLI subcommands** — each subcommand (init, execute, status, merge, cleanup) is independent module; thin entry point dispatches
- **Event emitter for cross-component communication** — Status Monitor, Notification System, Merge Orchestrator subscribe to events (task:started, task:completed, merge:conflict, etc.) rather than direct coupling
- **Dependency-aware task scheduler** — topological sort respecting dependency graph; independent tasks run in parallel up to concurrency limit
- **Idempotent operations with state recovery** — every operation checks current state before acting; users will re-run after failures
- **Git operations through abstraction layer** — all git commands via GitOperations interface; enables dry-run, logging, testing, consistent error handling

**Shared state:** `.planning/.gsd-ralph-state.json` as single source of truth for session recovery. Every component reads/writes through StateManager abstraction.

**Build order (by dependency layer):**
- Layer 0: Git Operations, State Manager, Event Bus (no dependencies; pure utilities)
- Layer 1: Plan Parser, Worktree Manager (depend on Layer 0)
- Layer 2: Prompt Generator, Task Scheduler (depend on Layer 1)
- Layer 3: Ralph Launcher, Status Monitor (depend on Layer 2; where complexity lives)
- Layer 4: Merge Orchestrator, Notification System (depend on Layer 3)
- Layer 5: CLI Entry Point and Command Handlers (compose all components)

### Critical Pitfalls

Research identified 14 pitfalls spanning critical (data loss/corruption), moderate (fragility/operational pain), and minor (portability/edge cases). The top 5 that would kill the project if not designed out:

1. **Git lock file contention from concurrent worktree operations** — Multiple worktrees share `.git` directory; parallel commits contend for `.git/index.lock`. Prevention: retry loops with exponential backoff around all git operations; avoid `git gc` during execution; sequential merges. Phase 1 concern.

2. **Merge order sensitivity creates silent data loss** — Sequential merge order matters enormously; later merges can silently overwrite earlier merges if both touched same files. Prevention: run full test suite after EACH merge (not just at end); use `git merge --no-commit --no-ff` for pre-inspection; merge to temp integration branch first. Merge phase concern.

3. **Orphaned worktrees and branches after crashes** — Worktrees placed in `$PARENT_DIR` as sibling directories; invisible to `.gitignore`, no auto-cleanup. Prevention: worktree registry manifest tracking creation time, expected branch, owning phase; `--force-clean` flag; `git worktree prune` on startup. Phase 1 concern.

4. **Status.json as unreliable agent status reporting** — Autonomous agents crash without updating status; status.json can be stale. Prevention: heartbeat mechanism with `last_heartbeat` timestamp; verify "complete" status against actual git state (commits ahead, recent commit, fix_plan.md checked); PID tracking; run_id to distinguish current vs stale runs. Status monitoring phase concern.

5. **.planning/ directory divergence across worktrees** — Each worktree gets a copy of `.planning/` at creation; when agents update STATE.md, creates N divergent versions. Prevention: treat `.planning/` as read-only in worktrees; agents report status via status.json only; orchestrator updates STATE.md; merge strategy always prefers main's version for planning files. Phase 1 and merge phase concern.

**Additional moderate pitfalls:**
- **Template variable substitution fragility** — bash heredocs with `$VARIABLE` break on special chars, spaces; regex XML parsing fails on edge cases. Use proper template engine (sed with delimiters) and XML parser.
- **No rollback mechanism for failed merges** — partial merges leave main in inconsistent state. Record pre-merge commit hash; offer rollback; use integration branch pattern.
- **Cross-worktree file reads are fragile** — absolute paths to peer worktrees baked into PROMPT.md; paths become dangling if worktree recreated. Use centralized status registry instead.
- **Process lifecycle blindness** — no supervision of agent processes; hung/dead agents undetected. Track PIDs; watchdog for hung processes (stale last_activity).
- **GSD naming convention edge cases** — glob `*-PLAN.md` matches non-plan files; plan numbering from array index not filename. Use strict regex `[0-9][0-9]-[0-9][0-9]-PLAN.md`; extract actual numbers from filenames.

## Implications for Roadmap

Based on combined research, the recommended phase structure balances dependency ordering (build foundation before features), risk mitigation (address critical pitfalls early), and incremental value delivery (each phase should produce working functionality).

### Phase 1: Foundation — Worktree Management with Registry

**Rationale:** Everything depends on reliable worktree creation/cleanup. Critical pitfalls #1, #3, #5, and #10 cluster here. Build the registry manifest pattern from day one; retrofitting is painful. This phase produces no user-visible features but prevents cascading technical debt.

**Delivers:**
- Git Operations abstraction layer with retry loops for lock contention
- Worktree Manager with registry manifest (`.gsd-ralph-state.json`)
- Clean worktree lifecycle: create, track, cleanup with orphan detection
- Strict GSD plan discovery (regex-based, extracts actual plan numbers)
- `.planning/` treated as read-only in worktrees

**Addresses (from FEATURES.md):**
- GSD plan discovery (table stakes)
- Validate prerequisites (table stakes)

**Avoids (from PITFALLS.md):**
- P1: Git lock contention (retry loops)
- P3: Orphaned worktrees (registry manifest)
- P5: .planning/ divergence (read-only design)
- P10: Naming edge cases (strict regex)
- P13: Environment assumptions (dependency validation)

**Stack elements:** Bash 3.2+, Git 2.20+, Python 3 for XML parsing

**Architecture components:** Git Operations, Worktree Manager, State Manager

**Research flag:** Standard patterns (git worktree mechanics well-documented). No additional research needed.

---

### Phase 2: Prompt Generation and Template System

**Rationale:** Depends on Phase 1 (needs worktree paths, TaskGraph from plan parser). Addresses pitfall #6 (template fragility). Must be solid before agents launch because broken prompts = broken execution, and you only discover it after wasting agent time.

**Delivers:**
- GSD Plan Parser outputting normalized TaskGraph
- Sed-based template rendering with `{{VARIABLE}}` substitution
- Proper XML task extraction (not regex-based)
- Generated per-worktree: PROMPT.md, fix_plan.md, .ralphrc
- Template validation (check substitution worked, fix_plan.md has tasks)

**Addresses (from FEATURES.md):**
- Task extraction from GSD XML (table stakes)
- Prompt generation per worktree (table stakes)
- Project-specific config (.ralphrc generation) (table stakes)

**Avoids (from PITFALLS.md):**
- P6: Template fragility (proper template engine, XML parser)

**Stack elements:** Templates from `templates/*.template`, sed for substitution, Python 3 xml.etree for parsing

**Architecture components:** Plan Parser, Prompt Generator

**Research flag:** Standard patterns (template rendering, XML parsing well-understood). No additional research needed.

---

### Phase 3: Project Initialization and Configuration

**Rationale:** Depends on Phases 1 and 2 (uses Worktree Manager, Prompt Generator). This is the user's entry point; should come early for testability but after core infrastructure exists. Low risk, high value.

**Delivers:**
- `gsd-ralph init` command
- Auto-detect project type (language from package.json/Cargo.toml, test command, build tool)
- Generate .ralph/ directory structure
- Sensible defaults (minimal user prompts)
- Dependency pre-flight check (git, jq, python3, ralph available)

**Addresses (from FEATURES.md):**
- Project init (table stakes)
- Validate prerequisites (table stakes)
- Sensible defaults (table stakes)

**Avoids (from PITFALLS.md):**
- P13: Hardcoded environment assumptions (startup validation)

**Stack elements:** Bash, jq for package.json parsing

**Architecture components:** CLI entry point, init command handler

**Research flag:** Standard patterns (project detection common in CLI tools). No additional research needed.

---

### Phase 4: Status Monitoring with Heartbeat Verification

**Rationale:** Depends on Phase 1 (reads state registry). Must be built BEFORE execution/merge automation because critical pitfall #4 (unreliable status) breaks downstream features. This phase makes status trustworthy enough to act on.

**Delivers:**
- `gsd-ralph status N` command
- Read status.json from each worktree
- Color-coded terminal output with summary table
- Heartbeat verification (detect stale/dead agents)
- PID tracking (verify process still alive)
- Verify "complete" status against git state (commits exist, recent, fix_plan.md checked)
- Run_id to distinguish current vs stale sessions

**Addresses (from FEATURES.md):**
- Phase status overview (table stakes)
- Clear error reporting (table stakes)

**Avoids (from PITFALLS.md):**
- P4: Unreliable agent status (heartbeat, PID tracking, git state verification)

**Stack elements:** jq for status.json parsing, bash process checking

**Architecture components:** Status Monitor, Event Bus

**Research flag:** Standard patterns (process monitoring, JSON aggregation). No additional research needed.

---

### Phase 5: Execution Orchestration (Core Workflow)

**Rationale:** Depends on Phases 1-4 (needs worktrees, prompts, status monitoring). This is the core value delivery: actually running the parallel agents. Start with manual terminal launch (matching existing scripts) to reduce scope; background process management is a later enhancement.

**Delivers:**
- `gsd-ralph execute N` command
- Discover plans for phase, create worktrees (Phase 1)
- Generate prompts per worktree (Phase 2)
- Instructions for user to launch Ralph in each worktree (manual for now)
- Terminal bell on completion (detected via status monitoring)
- Idempotent execution (skip existing worktrees or offer recreate)

**Addresses (from FEATURES.md):**
- Worktree creation per plan (table stakes)
- Ralph instance launch (table stakes — though manual for v1)
- Terminal bell on completion (table stakes)

**Avoids (from PITFALLS.md):**
- P14: No idempotency (check state before acting)

**Stack elements:** Bash, tput for terminal bell

**Architecture components:** Task Scheduler, Ralph Launcher (manual mode), Notification System

**Research flag:** Standard patterns (process orchestration). No additional research needed.

---

### Phase 6: Merge Orchestration with Safety Guarantees

**Rationale:** Depends on Phase 4 (status monitoring tells us what's ready to merge). Critical pitfall #2 (merge order sensitivity) and #7 (no rollback) cluster here. This is the highest-risk phase architecturally — must be conservative.

**Delivers:**
- `gsd-ralph merge N` command
- Sequential merge in plan order (dependency-respecting)
- Pre-merge commit hash saved for rollback
- Dry-run merge check (--no-commit --no-ff, then abort) before actual merge
- Conflict detection and clear guidance
- Auto-handle STATE.md conflicts (always prefer main's version)
- Cleanup of Ralph session state (.ralph/*.json, .call_count, etc.) before merge
- Review mode (`--review`) with diff preview and approval prompts

**Addresses (from FEATURES.md):**
- Auto-merge completed branches (table stakes)
- Sequential merge ordering (table stakes)
- Review mode option (table stakes)
- Conflict guidance (table stakes)

**Avoids (from PITFALLS.md):**
- P2: Merge order sensitivity (sequential, dependency-aware)
- P5: .planning/ divergence (STATE.md conflict resolution strategy)
- P7: No rollback (save pre-merge commit hash, offer reset)
- P12: Ralph session contamination (clean .ralph/ before merge)

**Stack elements:** Git merge operations

**Architecture components:** Merge Orchestrator, conflict detector

**Research flag:** Standard patterns (git merge mechanics well-documented). No additional research needed.

---

### Phase 7: Cleanup and Housekeeping

**Rationale:** Depends on Phase 6 (only cleanup after merge). Low complexity, completes the workflow lifecycle.

**Delivers:**
- `gsd-ralph cleanup N` command
- Remove merged worktrees
- Delete merged branches
- Prune git references
- Update registry to mark phase cleaned
- Safety: refuse to cleanup if merge incomplete or conflicts exist

**Addresses (from FEATURES.md):**
- Worktree and branch cleanup (table stakes)

**Avoids (from PITFALLS.md):**
- P3: Orphaned worktrees (proper cleanup, registry-driven)

**Stack elements:** Git worktree remove, branch delete

**Architecture components:** Worktree Manager, State Manager

**Research flag:** Standard patterns (cleanup straightforward). No additional research needed.

---

### Phase 8: Enhanced Features (Post-MVP)

**Rationale:** After core workflow (Phases 1-7) is solid, add differentiating features. These require all pieces working together.

**Delivers:**
- Pre-merge test run (run test suite on each branch before merging)
- Dry-run mode (`--dry-run` for execute and merge)
- Progress percentage (count checked items in fix_plan.md)
- Watch mode (`status --watch` with auto-refresh)
- Dependency graph enforcement (check phase dependencies before execute)
- STATE.md auto-updates (orchestrator updates STATE.md after merge, not agents)

**Addresses (from FEATURES.md):**
- Pre-merge test run (differentiator)
- Dry-run mode (differentiator)
- Progress percentage (differentiator)
- Watch mode (differentiator)
- GSD dependency graph awareness (differentiator)

**Avoids (from PITFALLS.md):**
- P11: node_modules in worktrees (post-worktree-creation hook to npm install)

**Stack elements:** Test command detection from .ralphrc, npm/cargo/etc

**Architecture components:** All (compose existing components)

**Research flag:** Testing integration may need project-specific research for different ecosystems (npm, cargo, go test, pytest, etc.). Consider `/gsd:research-phase` if supporting many project types.

---

### Phase 9: Advanced Orchestration (Future)

**Rationale:** Depends on all prior phases. High complexity, high value, but not needed for launch.

**Delivers:**
- Background process management (Ralph Launcher spawns and monitors processes, not manual terminal)
- Resume/retry failed plans (restart specific plan without touching others)
- Phase chaining (`execute --continue` auto-starts next phase when current completes)
- Structured execution log (EXECUTION_LOG.md with timing, commits, issues)
- Single-command full lifecycle (`execute --auto` composes everything)

**Addresses (from FEATURES.md):**
- Completion detection with auto-merge (differentiator)
- Resume/retry failed plans (differentiator)
- Phase chaining (differentiator)
- Structured execution log (differentiator)
- Single-command full lifecycle (differentiator — north star)

**Avoids (from PITFALLS.md):**
- P9: Process lifecycle blindness (supervisor mode, PID tracking, watchdog for hung processes)

**Stack elements:** Bash background processes, PID management

**Architecture components:** Ralph Launcher (full implementation), orchestration layer composing all commands

**Research flag:** Process supervision patterns may need research for robustness (signal handling, orphan cleanup, tmux/screen integration). Consider `/gsd:research-phase` for this phase.

---

### Phase Ordering Rationale

**Why this order:**

1. **Foundation first (Phases 1-2):** Worktree management and prompt generation are prerequisites for everything else. Critical pitfalls cluster in Phase 1; fixing them later is expensive.

2. **Init early (Phase 3):** User entry point should come early for end-to-end testing, but after infrastructure exists.

3. **Status before automation (Phase 4):** Merge and execution automation depend on trustworthy status. Building these features before status is reliable creates cascading bugs.

4. **Execution delivers value (Phase 5):** First phase that produces visible end-user value. Keeping it manual (terminal launch) reduces scope while proving the workflow.

5. **Merge is high-risk (Phase 6):** Most architectural complexity and critical pitfalls. Build after status is reliable and execution is proven. Conservative implementation with safety guarantees.

6. **Cleanup completes cycle (Phase 7):** Simple finale to core workflow. Users can now run full lifecycle manually.

7. **Enhancements build on solid base (Phase 8):** Add competitive features after core workflow is stable and tested.

8. **Advanced orchestration last (Phase 9):** Highest complexity, integrates all components, future-facing. Not MVP but natural evolution.

**Grouping rationale:**

- **Phases 1-2:** Infrastructure (no user-facing features; pure foundation)
- **Phases 3-7:** Core workflow (init, execute, status, merge, cleanup — MVP)
- **Phase 8:** Enhanced features (differentiators, operational excellence)
- **Phase 9:** Advanced orchestration (automation, north star features)

**How this avoids pitfalls:**

- Registry manifest in Phase 1 prevents orphaned worktree debt
- Template system in Phase 2 prevents prompt corruption discovered late
- Heartbeat verification in Phase 4 prevents unreliable status breaking automation
- Conservative merge in Phase 6 prevents silent data loss
- Deferred background process management (Phase 9) avoids complexity before basics work

### Research Flags

**Phases with standard patterns (skip research-phase):**
- **Phase 1-7:** Git worktree mechanics, bash CLI patterns, template rendering, merge strategies all well-documented. Codebase analysis and training data sufficient.

**Phases potentially needing research during planning:**
- **Phase 8:** Testing integration across different project types (npm, cargo, go test, pytest, make test, etc.). If supporting broad ecosystem, consider `/gsd:research-phase` focused on test command detection and execution patterns. Otherwise, start with npm (PROJECT.md context) and add others as needed.
- **Phase 9:** Process supervision in bash (signal handling, orphan cleanup, tmux/screen integration, PID lifecycle). Training data covers basics but robust implementation for production use may warrant targeted research. Consider `/gsd:research-phase` if user feedback indicates need for bulletproof process management.

**Research NOT needed:**
- Alternative architectures (Node.js vs bash decision is settled by constraints)
- Alternative VCS (git worktree is the correct primitive for this problem)
- Alternative agent frameworks (coupled to Ralph is intentional, not a limitation)

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Bash decision driven by explicit constraints; existing scripts validate approach; version requirements conservative and tested |
| Features | HIGH | Derived directly from project requirements and codebase analysis; competitive landscape from training data (MEDIUM confidence on latest features of competitors, but core differentiation is clear) |
| Architecture | MEDIUM | Component boundaries and patterns well-established in training data; specific integration points (Ralph process monitoring, cross-worktree coordination) untested in this exact composition |
| Pitfalls | HIGH | Codebase analysis reveals actual issues in existing scripts; distributed systems coordination problems well-documented in training data |

**Overall confidence:** MEDIUM-HIGH

Strong confidence in stack, features, and identified pitfalls due to direct codebase analysis. Moderate confidence in architecture integration points because the specific composition (bash orchestrator + git worktrees + autonomous agents + GSD planning) is novel. Training data covers constituent patterns but not this exact assembly.

### Gaps to Address

**During planning/execution:**

1. **Ralph's actual status.json schema:** The existing scripts read status.json but the full schema isn't documented in analyzed code. During Phase 4 implementation, verify exact fields Ralph writes (last_activity, status values, error reporting format). May need to inspect Ralph's codebase or run experiments.

2. **Git worktree scale limits:** Training data says worktrees share objects (efficient), but real-world performance testing with 20+ parallel worktrees hasn't been validated. During Phase 1 testing, benchmark worktree creation/cleanup time and disk usage. May need to add worktree count warnings or stagger creation.

3. **Cross-platform portability edge cases:** Analysis focused on macOS (primary platform per PROJECT.md). Bash 3.2 compatibility checklist is theoretical. During Phase 1, test on actual macOS bash 3.2 and Linux bash 4+. ShellCheck will catch some issues but not all runtime differences.

4. **Test command detection heuristics:** Phase 8 assumes common patterns (npm test, cargo test, etc.). During Phase 8 planning, catalog actual test commands across different ecosystems. May need user override mechanism if auto-detection fails.

5. **Merge conflict resolution patterns:** Pitfall #2 describes merge order sensitivity, but optimal merge ordering strategy when plans have complex file overlap is unsolved. During Phase 6, consider: topological sort by file dependencies? Manual ordering hints in PLAN.md? Start with simple sequential-by-number and observe real conflicts.

6. **Agent hang detection thresholds:** Phase 9 watchdog needs to distinguish "hung agent" from "agent working on complex task." Heartbeat interval and staleness threshold are unknowns. Gather data during Phases 5-7 manual execution to calibrate.

**Not blocking for MVP, address if needed:**

- Exact competitor feature sets (training data cutoff ~Jan 2025; competitors may have added parallel execution). Validation would require web research.
- Ralph's internal circuit breaker logic details (mentioned in templates but not analyzed). Important for status interpretation but can be learned from Ralph's status.json output during testing.
- Performance characteristics of large GSD projects (50+ tasks per phase, deeply nested dependencies). Phase 1-7 should handle this architecturally but stress testing isn't planned yet.

## Sources

### Primary (HIGH confidence)
- `/Users/daniswhoiam/Projects/gsd-ralph/FOUNDATIONAL_DOCUMENT.md` — project vision, constraints, no Node.js requirement
- `/Users/daniswhoiam/Projects/gsd-ralph/.planning/PROJECT.md` — requirements, out-of-scope decisions
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-execute.sh` — execution orchestration, manual launch pattern
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-merge.sh` — merge implementation, conflict handling
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-status.sh` — status monitoring, status.json reading
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-worktrees.sh` — worktree creation, plan discovery, prompt generation
- `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-cleanup.sh` — cleanup implementation
- `/Users/daniswhoiam/Projects/gsd-ralph/templates/*.template` — actual templates used in production (PROMPT.md, AGENT.md, fix_plan.md, ralphrc, WORKFLOW.md)

### Secondary (MEDIUM confidence)
- Training data: bats-core testing framework ecosystem (version numbers should be verified against official repos before development)
- Training data: ShellCheck static analysis capabilities
- Training data: bash version compatibility (3.2 vs 4+ differences well-documented but should be tested on actual systems)
- Training data: git worktree mechanics (shared object store, worktree limits, performance characteristics)
- Training data: CLI orchestration patterns (command pattern, event-driven architecture, process supervision)

### Tertiary (LOW confidence, needs validation)
- Training data: competitor tool feature sets (aider, Claude Code, claude-squad, Cursor, OpenAI Codex CLI) — cutoff ~Jan 2025, may be outdated
- Training data: Ralph's internal status reporting implementation details (inferred from status.json reading in scripts, but not verified against Ralph's actual codebase)

---
*Research completed: 2026-02-13*
*Ready for roadmap: yes*
