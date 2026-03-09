# Project Research Summary

**Project:** gsd-ralph v2.0 Autopilot Integration Layer
**Domain:** Autonomous CLI execution layer bridging GSD planning workflows with Claude Code headless execution
**Researched:** 2026-03-09
**Confidence:** HIGH

## Executive Summary

gsd-ralph v2.0 is a complete architectural pivot from a standalone Bash CLI (v1.x, 9,693 LOC) to a thin integration layer (~200-400 LOC) that bridges GSD's interactive planning/execution workflows with Claude Code's headless automation capabilities. The core insight driving this rewrite: GSD already handles all planning, execution, verification, and state management; Claude Code now provides native worktree isolation, headless mode, and tool auto-approval. gsd-ralph v2.0 only needs to make Ralph act as the "user" for GSD commands -- auto-responding to checkpoints, auto-approving tool permissions, and orchestrating the `claude -p` invocation with the right context and flags.

The recommended approach uses three native mechanisms in a layered defense-in-depth pattern: (1) GSD's own `workflow.auto_advance` config to auto-approve checkpoints at the workflow level, (2) `claude -p` with `--allowedTools` for headless execution with scoped tool permissions, and (3) `--append-system-prompt` injection to prevent `AskUserQuestion` calls entirely. The implementation consists of a shell launcher script (`bin/gsd-ralph`), an autonomous behavior skill (`skills/ralph-mode/SKILL.md`), and an optional defense-in-depth hook for `AskUserQuestion` denial. No new runtime dependencies are required beyond what GSD and Claude Code already provide.

The primary risks are: (1) scope creep that reimplements GSD logic inside gsd-ralph, destroying the "thin layer" architecture, (2) agent nesting depth exceeding Claude Code's limits when gsd-ralph wraps `claude -p` around GSD workflows that themselves spawn subagents, and (3) runaway execution without circuit breakers burning API credits or making destructive changes while the user is away. All three are addressable through strict architectural boundaries, careful invocation design, and multi-layer safety limits implemented early in the build.

## Key Findings

### Recommended Stack

The v2.0 stack requires zero new dependencies. Everything runs on top of existing Claude Code CLI (2.1.63+), GSD tools (`gsd-tools.cjs`), Bash 3.2+, and jq 1.6+. The integration is built from four small components: a custom agent definition (~50 lines), a permission hook (~30 lines), a CLI wrapper (~100 lines), and hook registration config (~15 lines). See [STACK.md](./STACK.md) for full details.

**Core technologies:**
- **Claude Code CLI (`claude -p`):** Runtime environment for headless execution -- `-p` flag, `--allowedTools`, `--worktree`, `--max-turns`, `--output-format json`
- **Claude Code Custom Agents:** `.claude/agents/ralph-autopilot.md` with `permissionMode: bypassPermissions` for the primary permission bypass mechanism
- **GSD config system:** `workflow.auto_advance` flag already handles checkpoint auto-approval -- no custom checkpoint logic needed
- **Bash 3.2 + jq:** Hook scripts and wrapper; macOS system Bash compatibility required

**Critical version requirements:** Claude Code 2.1.63+ (custom agent support with `permissionMode`), jq 1.6+ (hook JSON parsing).

### Expected Features

See [FEATURES.md](./FEATURES.md) for full feature landscape and dependency graph.

**Must have (table stakes -- v2.0 launch):**
- `--ralph` flag entry point on GSD commands -- the single product promise
- Auto-permission for Claude Code tool calls via `--allowedTools` -- zero human interaction after launch
- Session invocation via `claude -p` with assembled GSD context
- Worktree isolation via `claude --worktree` -- zero custom code, just pass the flag
- Basic completion detection from exit code and JSON output
- Terminal notification (bell + macOS notification) on completion/failure
- Dry-run / preview mode showing the command that would be launched

**Should have (v2.0.x after core validation):**
- Session resume on failure via `--resume` with captured session_id
- Circuit breaker (timeout, commit-count cap, no-progress detection)
- Progress monitoring via stream-json parsing
- Configurable `--max-turns` per project

**Defer (v2.1+):**
- Multi-phase orchestration (chain phase N completion into phase N+1)
- Configurable response strategies for `AskUserQuestion` (requires Agent SDK, not Bash)
- Parallel plan execution within a phase (primary source of v1.x complexity)
- Agent teams integration (Claude Code feature still experimental)

### Architecture Approach

The architecture follows a "Headless Delegation" pattern: a thin shell launcher sets GSD config flags, constructs a `claude -p` invocation with scoped permissions and system prompt injection, launches it in a worktree, and parses the JSON result on completion. The launcher does NOT modify GSD workflow files, does NOT write to `.planning/` files, and does NOT manage worktrees -- those responsibilities stay with GSD and Claude Code respectively. See [ARCHITECTURE.md](./ARCHITECTURE.md) for full component analysis and data flow.

**Major components:**
1. **`bin/gsd-ralph` (Shell Launcher):** Parses `--ralph` flag, sets `workflow.auto_advance`, constructs `claude -p` command with `--allowedTools` / `--worktree` / `--max-turns` / `--append-system-prompt`, launches headless session, parses JSON result
2. **`skills/ralph-mode/SKILL.md` (Autonomous Behavior Prompt):** System prompt instructions telling Claude to never call `AskUserQuestion`, auto-approve `human-verify`, auto-select first option for `decision`, skip `human-action`, and follow GSD conventions
3. **`hooks/deny-ask.sh` (Defense-in-Depth Hook):** Optional `PreToolUse` hook that denies `AskUserQuestion` with guidance feedback -- backup layer in case system prompt compliance fails
4. **Config extension (`.planning/config.json`):** Ralph-specific config fields (`ralph.enabled`, `ralph.allowed_tools`, `ralph.max_turns`, `ralph.worktree_prefix`)

### Critical Pitfalls

See [PITFALLS.md](./PITFALLS.md) for all 8 pitfalls with detailed prevention strategies.

1. **Reimplementing GSD logic** -- The strongest gravitational pull. gsd-ralph must call `gsd-tools.cjs` for ALL plan/phase/state data, never parse `.planning/` files directly. Verification: LOC stays under 500; `grep` for parse/discover/frontmatter patterns returns zero results.
2. **Agent nesting depth** -- `claude -p` invoking GSD workflows that spawn `Task()` subagents can exceed Claude Code's nesting limit. gsd-ralph must be the TOP-LEVEL invoker and pass GSD workflow context via `--append-system-prompt` / `@file` references so the Claude instance IS the GSD orchestrator, not a wrapper around one.
3. **Runaway execution without circuit breakers** -- No built-in token budget or timeout in `claude -p`. Implement multi-layer limits: `--max-turns` (hard ceiling), wall-clock `timeout` wrapper, and no-progress detection. Always use `--allowedTools` (not `--dangerously-skip-permissions`) and `--worktree` isolation.
4. **GSD update breaks gsd-ralph silently** -- Minimize GSD API surface (CLI commands only, not internal file paths). Pin GSD version, check at startup, warn on mismatch. Run compatibility tests against real `gsd-tools.cjs`.
5. **State corruption from concurrent access** -- gsd-ralph must NEVER write to `.planning/` files. Let GSD workflows handle all state mutations. Use worktree isolation so config changes are scoped.

## Implications for Roadmap

Based on combined research, here is the suggested phase structure. The ordering follows dependency chains from FEATURES.md and addresses pitfalls at the earliest possible point per PITFALLS.md.

### Phase 1: Core Architecture and Autonomous Behavior Prompt
**Rationale:** Everything depends on the architectural boundary (what gsd-ralph does vs. what GSD does) and the autonomous behavior rules. PITFALLS.md identifies this boundary as "the single most important architectural decision" -- getting it wrong means a rewrite. The SKILL.md prompt is the "brain" that all other components reference.
**Delivers:** `skills/ralph-mode/SKILL.md` with autonomous behavior rules; architectural boundary documentation; config schema extension for ralph-specific settings
**Addresses:** GSD context injection (FEATURES), auto-response rules for each checkpoint type
**Avoids:** Pitfall 1 (reimplementing GSD logic), Pitfall 5 (state corruption), Pitfall 7 (agent nesting)

### Phase 2: Shell Launcher and Headless Invocation
**Rationale:** The launcher is the entry point that users interact with. It depends on the SKILL.md from Phase 1 and the config schema. This phase delivers the core `claude -p` invocation with all flags wired up. It is where the `--ralph` flag, `--allowedTools`, `--worktree`, and `--max-turns` come together.
**Delivers:** `bin/gsd-ralph` script with flag parsing, config reading, `claude -p` invocation, JSON output parsing, basic completion detection, terminal notification, dry-run mode
**Addresses:** `--ralph` flag parsing, auto-permission, session invocation, worktree isolation, completion detection, terminal notification, dry-run (all table-stakes features from FEATURES.md)
**Avoids:** Pitfall 3 (runaway execution -- `--max-turns` + `timeout`), Pitfall 6 (prompt injection -- `--allowedTools` + `--worktree`), Pitfall 8 (token waste -- `@file` references, not inline content)

### Phase 3: Defense-in-Depth Hooks and Safety
**Rationale:** The hook layer is optional but critical for reliability. Phase 2 delivers a working autopilot; Phase 3 hardens it. Circuit breaker patterns, `AskUserQuestion` denial hooks, and GSD version compatibility checking all belong here. These are not needed for basic function but prevent the failure modes identified in PITFALLS.md.
**Delivers:** `PreToolUse` hook for `AskUserQuestion` denial, GSD version compatibility check, circuit breaker wrapper (wall-clock timeout, no-progress detection), graceful stop mechanism (`.ralph/.stop` file), audit log of auto-approved decisions
**Addresses:** Circuit breaker (FEATURES v2.0.x), safety limits
**Avoids:** Pitfall 2 (blanket checkpoint approval -- audit trail), Pitfall 3 (runaway execution -- multi-layer circuit breaker), Pitfall 4 (GSD update breaks -- version check)

### Phase 4: Session Resilience and Progress Monitoring
**Rationale:** Session resume and progress monitoring depend on completion detection (Phase 2) and safety infrastructure (Phase 3). These are the v2.0.x features that turn a basic autopilot into a reliable one. Progress monitoring is especially important for user confidence when the user walks away.
**Delivers:** Session resume on failure (`--resume` with persisted session_id), progress monitoring via `--output-format stream-json` parsing, configurable `--max-turns` per project, structured completion report
**Addresses:** Session resume, progress monitoring, max-turns config (all FEATURES v2.0.x)
**Avoids:** Pitfall 3 (provides recovery path when circuit breaker triggers)

### Phase 5: Integration Testing and Installation
**Rationale:** End-to-end testing must happen after all components exist. The installer copies components to correct locations. This phase validates the full pipeline against real GSD workflows.
**Delivers:** End-to-end integration tests (full phase execution in worktree), `install.sh` installer, GSD compatibility test suite, documentation
**Addresses:** Validates all features work together
**Avoids:** Pitfall 4 (GSD compatibility -- tested against real GSD), Pitfall 7 (nesting depth -- verified end-to-end)

### Phase Ordering Rationale

- **Phase 1 before Phase 2:** The architectural boundary and SKILL.md must exist before the launcher can reference them. Every pitfall in the "Core architecture phase" category (Pitfalls 1, 4, 5, 7) must be addressed in design before code is written.
- **Phase 2 before Phase 3:** A working autopilot (even without defense-in-depth) is more valuable than hardened infrastructure without a product. Phase 2 delivers the MVP; Phase 3 hardens it.
- **Phase 3 before Phase 4:** Safety infrastructure (circuit breakers, version checking, audit logging) must exist before the session resilience and monitoring layer on top. A resumed session needs circuit breakers to prevent the same runaway scenario.
- **Phase 5 last:** Integration tests require all components. The installer is the final packaging step.
- **Why this grouping:** Phases 1-2 deliver the MVP (~200 LOC). Phases 3-4 harden it. Phase 5 validates it. This mirrors the FEATURES.md prioritization: P1 (launch) -> P2 (after validation) -> testing.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 1:** Needs verification of open questions from ARCHITECTURE.md -- specifically whether `claude -p "/gsd:execute-phase 3"` correctly triggers GSD skills in headless mode, and whether `--worktree` shares or copies `.planning/` files. These determine the invocation strategy.
- **Phase 2:** Needs validation of `--allowedTools` inheritance by subagents in headless mode. If subagents do NOT inherit, the hook-based permission approach becomes primary rather than defense-in-depth.
- **Phase 3:** Needs research on `PreToolUse` hook behavior for `AskUserQuestion` in headless mode -- the hook may not fire at all in `-p` mode (ARCHITECTURE.md notes `PermissionRequest` hooks do not fire in headless mode).

Phases with standard patterns (skip research-phase):
- **Phase 4:** Session resume (`--resume` flag) and stream-json parsing are well-documented Claude Code features with established patterns.
- **Phase 5:** Standard bats-core testing patterns; installer is a simple file-copy script.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All technologies verified against official Claude Code docs (v2.1.71). Zero new dependencies. Version requirements confirmed. |
| Features | HIGH | Feature landscape grounded in competitor analysis (Ralph, Copilot CLI), GSD codebase inspection, and Claude Code API verification. MVP scope is clear and minimal. |
| Architecture | HIGH | Architecture verified against Claude Code hooks reference, headless mode docs, and GSD workflow source code. 5 open questions identified but none block Phase 1-2. |
| Pitfalls | HIGH | Pitfalls grounded in v1.x failure history (9,693 LOC rewrite), documented GSD issues (#668, #686), and Claude Code safety literature (32% unintended modification rate with `--dangerously-skip-permissions`). |

**Overall confidence:** HIGH

### Gaps to Address

- **Headless mode + GSD skill invocation:** Does `claude -p "/gsd:execute-phase 3"` trigger GSD skills? If not, the prompt must include workflow content directly via `@file` references. Validate in Phase 1 planning.
- **Worktree `.planning/` isolation:** When `claude --worktree` creates a worktree, are `.planning/` files shared or copied? This determines whether config changes leak across sessions. Validate in Phase 1 planning.
- **Subagent `--allowedTools` inheritance:** Do subagents spawned via the `Agent` tool inherit `--allowedTools` from the parent headless session? If not, Phase 3 hooks become critical. Validate in Phase 2 planning.
- **`PreToolUse` hook behavior in headless mode:** If `PreToolUse` hooks do not fire for `AskUserQuestion` in `-p` mode, the defense-in-depth hook in Phase 3 provides no value. Validate before Phase 3 planning.
- **Session continuation context preservation:** Does `claude -p --continue` preserve `--append-system-prompt` content and auto-mode config? If not, resumed sessions may lose autonomous behavior. Validate in Phase 4 planning.

## Sources

### Primary (HIGH confidence)
- [Claude Code headless mode docs](https://code.claude.com/docs/en/headless) -- `-p` flag, `--allowedTools`, `--output-format`, `--append-system-prompt`
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) -- `PermissionRequest` and `PreToolUse` events, decision control JSON schema
- [Claude Code subagents docs](https://code.claude.com/docs/en/sub-agents) -- Custom agents, `permissionMode`, `isolation: worktree`, `skills` field
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) -- All CLI flags
- [Claude Code skills docs](https://code.claude.com/docs/en/skills) -- Skill format, frontmatter, invocation control
- GSD codebase (local inspection) -- `execute-phase.md`, `execute-plan.md`, `checkpoints.md`, `gsd-tools.cjs`

### Secondary (MEDIUM confidence)
- [AskUserQuestion hook feature request #12605](https://github.com/anthropics/claude-code/issues/12605) -- Confirmed limitation: hooks cannot auto-respond to AskUserQuestion
- [PreToolUse AskUserQuestion bug #12031](https://github.com/anthropics/claude-code/issues/12031) -- Fixed in v2.0.76
- [PermissionRequest hook bug #19298](https://github.com/anthropics/claude-code/issues/19298) -- `deny` broken, `allow` works
- [GSD issue #686](https://github.com/gsd-build/get-shit-done/issues/686) -- Auto-advance chain freezing from agent nesting
- [GSD issue #668](https://github.com/gsd-build/get-shit-done/issues/668) -- Auto-advance chain dropping commits
- [Ralph for Claude Code](https://github.com/frankbria/ralph-claude-code) -- Reference implementation patterns
- [GitHub Copilot CLI autopilot docs](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/autopilot) -- Competitor feature analysis
- [Claude Code `--dangerously-skip-permissions` guide](https://www.ksred.com/claude-code-dangerously-skip-permissions-when-to-use-it-and-when-you-absolutely-shouldnt/) -- 32% unintended modification rate

### Tertiary (LOW confidence)
- [Claude Code context buffer management](https://claudefa.st/blog/guide/mechanics/context-buffer-management) -- 33K-45K reserved buffer; needs validation against current Claude Code version

---
*Research completed: 2026-03-09*
*Ready for roadmap: yes*
