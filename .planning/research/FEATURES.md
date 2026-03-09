# Feature Research: v2.0 Autopilot Core

**Domain:** Autonomous CLI execution layer / autopilot integration for AI-driven development workflows
**Researched:** 2026-03-09
**Confidence:** HIGH

## Context

This research covers the feature landscape for gsd-ralph v2.0 -- a complete rewrite from standalone Bash CLI (v1.x, 9,693 LOC, 211 tests) to a thin integration layer that adds `--ralph` to any GSD command for autonomous execution. The architectural insight: GSD already handles planning/execution/verification; Ralph already handles autonomous coding; Claude Code now provides native worktree isolation (`--worktree`), headless mode (`claude -p`), and tool auto-approval (`--allowedTools`). gsd-ralph v2.0 just needs to bridge the gap by making Ralph act as the "user" for GSD commands.

**Key ecosystem facts informing this research:**
- Claude Code Agent SDK provides `canUseTool` callbacks for programmatic tool approval and `AskUserQuestion` interception (Python/TypeScript)
- Claude Code hooks system has 18 lifecycle events (PreToolUse, PostToolUse, Stop, Notification, SubagentStart, SessionEnd, etc.) with matcher-based filtering and JSON I/O
- Claude Code skills system supports YAML frontmatter, `context: fork` for subagent isolation, `allowed-tools` restriction, and `disable-model-invocation` for user-only triggers
- GitHub Copilot CLI shipped autopilot mode (GA Feb 2026) with `--max-autopilot-continues`, `--allow-all`, and permission prompts at mode entry
- Ralph (frankbria/ralph-claude-code) uses a Bash loop invoking `claude -p` with `--resume` for session continuity, dual-condition exit detection, and circuit breakers

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features that must exist for v2.0 to be considered a working autopilot layer. Missing any of these means the tool cannot replace manual GSD command execution.

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| **`--ralph` flag parsing on GSD commands** | Core product promise. Without this, the tool has no entry point. Users expect to type `gsd execute-phase 3 --ralph` and walk away. | LOW | GSD command interception mechanism | Two implementation paths: (1) GSD skill/hook that detects `--ralph` and wraps execution, or (2) shell wrapper/alias that intercepts `gsd` commands and adds autopilot behavior. The skill approach is more native to the GSD ecosystem. The wrapper approach is simpler but fragile to GSD updates. Recommend: GSD skill that accepts the phase number as `$ARGUMENTS` and orchestrates the autonomous execution. |
| **Auto-permission for Claude Code tool calls** | Autopilot mode that stops to ask "Allow Bash?" every 30 seconds is not autopilot. Users expect zero human interaction after launch. | LOW | Claude Code `--allowedTools` or `--dangerously-skip-permissions` | Claude Code's `-p` flag with `--allowedTools "Write,Read,Edit,Grep,Glob,Bash(*)"` handles this natively. No custom code needed -- just pass the right flags when invoking Claude. The `.ralphrc` already defines `ALLOWED_TOOLS`. For v2.0, read this config and pass it to `claude -p`. Do NOT use `--dangerously-skip-permissions` -- it removes all safety guardrails. `--allowedTools` is the correct pattern: explicit opt-in per tool. |
| **Session invocation via `claude -p`** | The tool must actually launch Claude Code in headless mode with the right prompt, context, and permissions. This is the core execution mechanism. | LOW | `--ralph` flag, tool permissions config | Invoke `claude -p "$PROMPT" --allowedTools "$TOOLS" --output-format json --max-turns $MAX_TURNS`. Stream output with `--output-format stream-json` if progress monitoring is needed. Use `--append-system-prompt` to inject GSD-specific context without replacing Claude Code's default system prompt. |
| **GSD context injection** | Claude needs to know about the project, the phase, the plans, and the GSD conventions. Without context, it produces generic code that does not follow GSD workflow. | MEDIUM | Phase/plan discovery, PROJECT.md, STATE.md | Assemble context from: `.planning/PROJECT.md` (always), `.planning/STATE.md` (current position), phase plans (the specific plans for this phase), and `.planning/ROADMAP.md` (dependency awareness). Inject via `--append-system-prompt` or by constructing the prompt with embedded context. The v1.x `generate_protocol_prompt_md` function did this -- v2.0 needs the same capability but lighter weight. |
| **Worktree isolation via Claude Code native** | Each autonomous execution must be isolated from the main branch. Users expect that autopilot work does not interfere with their current working tree. | LOW | Git repo with remote | Use `claude --worktree phase-N-slug -p "$PROMPT"`. Claude Code handles worktree creation, branch management, and cleanup natively as of v2.1.49. No custom worktree management needed -- this is the entire reason v1.x is being replaced. Worktrees are created at `.claude/worktrees/`. |
| **Execution completion detection** | The tool must know when the work is done. Users expect that the autopilot stops when the task is complete, not when it runs out of turns. | MEDIUM | Session output parsing | Two approaches: (1) Use `--max-turns N` as a hard limit and rely on Claude's own completion logic. (2) Parse `--output-format json` result for completion indicators. Claude Code already handles this internally -- when it determines the task is complete, it stops. The `--max-turns` flag is a safety net, not the primary mechanism. Ralph v1.x's dual-condition exit detection (heuristic + explicit signal) is overkill for v2.0 because Claude Code's agent loop already has completion logic. |
| **Terminal notification on completion** | User walked away. They need to know when to come back. Bell, desktop notification, or both. | LOW | Completion detection | `tput bel` for terminal bell (already in v1.x). Can add `osascript -e 'display notification "Phase 3 complete" with title "gsd-ralph"'` on macOS. Trigger on both success and failure -- the user needs to know either way. |

### Differentiators (Competitive Advantage)

Features that go beyond basic autopilot and make gsd-ralph the preferred way to run GSD autonomously. These are where the product competes with "just run `claude -p` yourself."

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| **Progress monitoring via hooks** | Unlike raw `claude -p`, gsd-ralph can show what Claude is doing: which files it is editing, which plan it is on, whether tests are passing. This is the difference between "fire and forget with anxiety" and "fire and forget with confidence." | MEDIUM | Claude Code hooks (PostToolUse, Stop), stream-json output | Two approaches: (1) Use `--output-format stream-json --verbose` and parse the stream for tool use events. (2) Register PostToolUse hooks that log activity to a file, and run a separate `tail -f` on that file. Approach (1) is simpler. Parse stream events for `tool_name`, `tool_input.file_path`, and `tool_result` to show a live activity feed. Copilot CLI shows "premium request consumption in real time" -- gsd-ralph should show task/plan progress. |
| **Session resume on failure** | If Claude hits an error, times out, or the process is killed, resume from where it left off instead of starting over. This is a major time and cost saver. | MEDIUM | Session ID capture, `--resume` flag | Capture `session_id` from `--output-format json` response. On failure/timeout, re-invoke with `claude -p "Continue from where you left off" --resume $SESSION_ID`. Ralph v1.x does this with `SESSION_CONTINUITY=true` and `--resume`. For v2.0, this is simpler: just persist the session_id in a state file (`.ralph/session.json` or `.planning/STATE.md`) and use `--continue` or `--resume $ID` on re-run. |
| **Circuit breaker / safety limits** | Prevent runaway execution that burns API credits or makes destructive changes in a loop. The user walked away -- the tool must be self-limiting. | MEDIUM | Session output monitoring, execution time tracking | Three layers: (1) `--max-turns N` as hard ceiling (Claude Code native). (2) Execution time limit via `timeout` command wrapping the claude invocation. (3) Post-execution check: if output indicates repeated failures or no progress, do not auto-retry. Ralph v1.x's circuit breaker (CB_NO_PROGRESS_THRESHOLD=3, CB_SAME_ERROR_THRESHOLD=5) is well-designed. Port the concept but simplify: track consecutive no-progress invocations, stop after threshold. |
| **Dry-run / preview mode** | Show what the autopilot would do without actually doing it: what context it would inject, what tools it would allow, what branch it would create. Reduces launch anxiety. | LOW | GSD context assembly, flag parsing | Assemble the full prompt and print it. Show the `claude` command that would be executed. Show the worktree name. Do not invoke Claude. v1.x had `--dry-run` on execute -- same concept, simpler implementation. |
| **Multi-phase orchestration** | Run multiple phases sequentially: "execute phase 3, merge, then execute phase 4." Not parallelism (that is v2.1+), but chaining. | HIGH | Completion detection, merge automation, phase ordering | This is where gsd-ralph transcends "just a wrapper." After phase N completes, auto-merge, auto-verify (run tests), and if passing, auto-launch phase N+1. Requires: reliable completion detection, merge conflict handling (at minimum, detect and stop), and test execution. Defer to v2.1+ unless completion detection is highly reliable. |
| **Configurable response strategy** | When Claude asks a clarifying question (AskUserQuestion), provide a configurable default response strategy instead of just "approve everything." | HIGH | Agent SDK canUseTool callback or hook-based interception | PROJECT.md explicitly lists "Intelligent response strategies" as v2.1+ scope. For v2.0, the strategy is simple: auto-approve all tool calls, auto-respond "proceed with your best judgment" to any AskUserQuestion. The Agent SDK `canUseTool` callback is the proper mechanism for this, but requires TypeScript/Python -- not Bash. For a Bash-only v2.0, use `--allowedTools` for tool approval and rely on Claude not asking questions in `-p` mode (which is the observed behavior -- Claude rarely uses AskUserQuestion in headless mode). |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems. Explicitly NOT building these.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Custom worktree management** | v1.x had a full worktree registry, custom creation/cleanup, and branch naming. Users may expect this pattern to continue. | Claude Code's `--worktree` flag handles creation, isolation, and cleanup natively. Custom management duplicates logic, creates conflicts with Claude Code's worktree tracking, and breaks when Claude Code changes its worktree implementation. This is THE reason v1.x is being replaced. | Use `claude --worktree <name>` exclusively. Let Claude Code own the worktree lifecycle. |
| **Standalone init/generate/execute/merge/cleanup commands** | v1.x users know this command structure. It maps to a familiar lifecycle. | These commands duplicate GSD's native lifecycle (plan-phase, execute-phase, verify-work). The v2.0 insight is that GSD already has these commands -- gsd-ralph should not reimplement them. Maintaining parallel command sets means double the maintenance and inevitable divergence. | One entry point: `--ralph` flag on existing GSD commands. GSD handles lifecycle; gsd-ralph handles autonomy. |
| **Real-time AskUserQuestion interception in Bash** | Users want the autopilot to handle any question Claude asks, not just tool permissions. | AskUserQuestion interception requires the Agent SDK (Python/TypeScript) with `canUseTool` callbacks. Building this in Bash would require parsing stream-json output for tool_use events, detecting AskUserQuestion tool calls, and somehow injecting responses -- which is architecturally fragile and races against Claude's execution. Claude Code in `-p` mode with `--allowedTools` rarely triggers AskUserQuestion because there is no interactive user to ask. | For v2.0: rely on `-p` mode's non-interactive behavior. For v2.1+: if AskUserQuestion interception is needed, build a thin TypeScript/Python wrapper using the Agent SDK. |
| **GUI dashboard or web interface** | "I want to see progress in a browser" or "show me a terminal UI with panels." | Target users are terminal-native developers. A GUI adds a runtime dependency (Node server, electron, etc.), deployment complexity, and maintenance burden for a niche audience. Copilot CLI and Claude Code are both terminal-first for a reason. | Terminal output with `--verbose` streaming. Optional `tail -f` on a log file for a second terminal pane. Desktop notifications for completion. |
| **Multi-repo support** | "I have a monorepo setup" or "I want to orchestrate across repos." | GSD operates within a single git repo. Claude Code's worktree isolation operates within a single repo. Multi-repo adds coordination complexity (cross-repo dependencies, merge ordering, divergent branch states) that is out of scope for a thin integration layer. | Single repo only. For multi-repo projects, run gsd-ralph separately in each repo. |
| **Custom LLM provider support** | "I want to use GPT-4 or Gemini instead of Claude." | gsd-ralph is specifically the bridge between GSD and Ralph/Claude Code. Claude Code only supports Anthropic models. Adding provider abstraction defeats the purpose and complicates the tool for zero real-world usage. | Coupled to Claude Code intentionally. If someone wants a different LLM, they need a different tool. |
| **Parallel plan execution within a phase** | "Run all plans in a wave simultaneously." | Parallel execution requires merge conflict management, resource coordination (API rate limits across N concurrent sessions), and progress aggregation across multiple worktrees. This is a significant complexity multiplier. v1.x attempted parallel worktrees and it was the primary source of merge conflicts. | Sequential execution for v2.0. Parallel execution is explicitly scoped to v2.1+ in PROJECT.md. Claude Code's agent teams feature may be a better foundation than custom parallel orchestration. |

---

## Feature Dependencies

```
[--ralph flag parsing]
    |
    +--requires--> [GSD context injection]
    |                  (flag triggers context assembly before Claude launch)
    |
    +--requires--> [Auto-permission config]
    |                  (reads .ralphrc or skill config for ALLOWED_TOOLS)
    |
    +--enables---> [Session invocation via claude -p]
                       (assembled context + permissions = launchable command)

[Session invocation via claude -p]
    |
    +--requires--> [Worktree isolation via --worktree]
    |                  (must isolate before execution starts)
    |
    +--enables---> [Execution completion detection]
    |                  (session output provides completion signal)
    |
    +--enables---> [Progress monitoring via hooks/stream]
                       (stream-json output feeds progress display)

[Execution completion detection]
    |
    +--enables---> [Terminal notification]
    |                  (fires on completion or failure)
    |
    +--enables---> [Session resume on failure]
    |                  (completion vs failure determines resume action)
    |
    +--enables---> [Circuit breaker]
    |                  (no-progress detection requires completion assessment)
    |
    +--enables---> [Multi-phase orchestration]
                       (phase N completion triggers phase N+1)

[Dry-run / preview] --independent-- (no runtime dependencies, can ship in any order)

[Configurable response strategy] --conflicts-- [Bash-only implementation]
    (Agent SDK canUseTool requires TypeScript/Python runtime)
```

### Dependency Notes

- **`--ralph` flag is the root dependency**: Everything flows from the entry point. Without flag parsing, nothing else can trigger. Build this first.
- **GSD context injection is the most reusable piece**: The prompt assembly logic serves both the skill-based and wrapper-based approaches. It also serves dry-run mode. Build it early, test it independently.
- **Worktree isolation is zero-cost**: Claude Code handles it. The "implementation" is adding `--worktree` to the claude invocation. No custom code needed.
- **Completion detection gates all post-execution features**: Session resume, circuit breaker, multi-phase orchestration, and notifications all depend on knowing whether execution succeeded. Invest here.
- **Progress monitoring is optional but high-value**: Can ship v2.0 without it and add in v2.0.x. The user can always check the worktree manually.
- **Configurable response strategy conflicts with Bash**: If v2.0 stays Bash-only, this feature requires a TypeScript/Python companion. Defer to v2.1+ unless the team is willing to add a Node/Python runtime dependency.

---

## MVP Definition

### Launch With (v2.0)

Minimum viable autopilot -- what is needed to validate the concept of "add `--ralph` and walk away."

- [ ] **`--ralph` flag entry point** -- the single product entry point; without it, there is no product
- [ ] **GSD context injection** -- assemble phase/plan context into a prompt Claude can execute against
- [ ] **Auto-permission via `--allowedTools`** -- pass configured tool permissions to `claude -p` so execution is uninterrupted
- [ ] **Session invocation (`claude -p`)** -- actually launch Claude Code in headless mode with the assembled prompt
- [ ] **Worktree isolation (`--worktree`)** -- isolate autonomous work from the user's working tree; zero custom code, just pass the flag
- [ ] **Completion detection (basic)** -- detect success vs failure from claude's exit code and `--output-format json` result field
- [ ] **Terminal notification** -- bell on completion/failure so the user knows to come back
- [ ] **Dry-run mode** -- show what would be launched without launching; builds confidence and aids debugging

### Add After Validation (v2.0.x)

Features to add once the core autopilot loop is working reliably.

- [ ] **Session resume on failure** -- capture session_id, re-invoke with `--resume` on timeout/crash; trigger: users report lost work due to mid-execution failures
- [ ] **Circuit breaker** -- stop after N no-progress iterations; trigger: users report runaway API spend
- [ ] **Progress monitoring** -- parse stream-json or use PostToolUse hooks to show activity; trigger: users report anxiety about what Claude is doing
- [ ] **Max-turns configuration** -- expose `--max-turns` setting in .ralphrc for per-project tuning; trigger: users need different budgets for different project sizes

### Future Consideration (v2.1+)

Features to defer until v2.0 is proven and the team has usage data.

- [ ] **Multi-phase orchestration** -- chain phase execution automatically; defer because it requires highly reliable completion detection and merge automation
- [ ] **Configurable response strategies** -- context-aware answers to AskUserQuestion; defer because it requires Agent SDK (TypeScript/Python) and is a significant complexity jump
- [ ] **Parallel plan execution** -- multiple worktrees within a phase; defer because it was the primary source of v1.x complexity and merge conflicts
- [ ] **Agent teams integration** -- use Claude Code's agent teams for coordinated multi-agent work; defer because the feature is still experimental and disabled by default

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority | Phase |
|---------|------------|---------------------|----------|-------|
| `--ralph` flag parsing | HIGH | LOW | P1 | v2.0 |
| GSD context injection | HIGH | MEDIUM | P1 | v2.0 |
| Auto-permission (`--allowedTools`) | HIGH | LOW | P1 | v2.0 |
| Session invocation (`claude -p`) | HIGH | LOW | P1 | v2.0 |
| Worktree isolation (`--worktree`) | HIGH | LOW | P1 | v2.0 |
| Completion detection (basic) | HIGH | MEDIUM | P1 | v2.0 |
| Terminal notification | MEDIUM | LOW | P1 | v2.0 |
| Dry-run mode | MEDIUM | LOW | P1 | v2.0 |
| Session resume | HIGH | MEDIUM | P2 | v2.0.x |
| Circuit breaker | HIGH | MEDIUM | P2 | v2.0.x |
| Progress monitoring | MEDIUM | MEDIUM | P2 | v2.0.x |
| Max-turns config | LOW | LOW | P2 | v2.0.x |
| Multi-phase orchestration | HIGH | HIGH | P3 | v2.1+ |
| Response strategies | MEDIUM | HIGH | P3 | v2.1+ |
| Parallel execution | HIGH | HIGH | P3 | v2.1+ |
| Agent teams integration | MEDIUM | HIGH | P3 | v2.1+ |

**Priority key:**
- P1: Must have for v2.0 launch
- P2: Should have, add when core is proven
- P3: Nice to have, future consideration

---

## Competitor / Reference Feature Analysis

| Feature | Ralph (frankbria) | Copilot CLI Autopilot | Claude Code Headless | gsd-ralph v2.0 |
|---------|-------------------|-----------------------|----------------------|-----------------|
| **Entry point** | `ralph` command runs loop | `--autopilot` flag | `claude -p` flag | `--ralph` flag on GSD commands |
| **Permission model** | `.ralphrc` ALLOWED_TOOLS | `--allow-all` at mode entry | `--allowedTools` explicit list | Read `.ralphrc`, pass to `--allowedTools` |
| **Execution model** | Bash loop re-invoking `claude -p` with `--resume` | Agent continues N steps autonomously | Single invocation, agent loop internal | Single `claude -p` invocation per phase (not a re-invocation loop) |
| **Completion detection** | Dual-condition: heuristic + EXIT_SIGNAL | Agent determines completion or `--max-autopilot-continues` | Agent determines completion or `--max-turns` | Claude Code's internal completion + exit code + `--max-turns` safety net |
| **Worktree isolation** | None (works in current directory) | None | `--worktree` flag | `--worktree` flag (Claude Code native) |
| **Progress monitoring** | `.ralph/fix_plan.md` checkbox tracking, `ralph_monitor.sh` dashboard | Premium request count display | `--output-format stream-json` | Stream-json parsing (v2.0.x) |
| **Session resume** | `--resume $SESSION_ID` across loop iterations | Not documented | `--resume $SESSION_ID` or `--continue` | Capture session_id, `--resume` on re-run (v2.0.x) |
| **Circuit breaker** | CB_NO_PROGRESS_THRESHOLD, CB_SAME_ERROR_THRESHOLD, cooldown | `--max-autopilot-continues` | `--max-turns` | `--max-turns` + post-execution no-progress check (v2.0.x) |
| **Planning context** | `.ralph/PROMPT.md` + `.ralph/fix_plan.md` | User prompt + codebase analysis | User prompt + CLAUDE.md | GSD phase plans + PROJECT.md + STATE.md assembled into prompt |
| **Notification** | Terminal bell on completion | Not documented | Not built-in | Terminal bell + macOS notification (v2.0) |

### Key Insight from Comparison

Ralph v1.x and gsd-ralph v1.x both built custom execution loops (Bash while-loops invoking `claude -p` repeatedly). Copilot CLI's autopilot and Claude Code's agent loop now handle this internally -- the agent continues autonomously for N turns without needing external re-invocation. The v2.0 architecture should NOT re-implement the execution loop. Instead, it should:

1. Assemble the right prompt with GSD context
2. Launch `claude -p` once with proper flags (`--worktree`, `--allowedTools`, `--max-turns`)
3. Wait for completion
4. React to the result (notify, resume, chain)

This is fundamentally simpler than v1.x's architecture and is the correct approach because Claude Code's internal agent loop handles iteration, tool use, and completion detection better than any external Bash wrapper can.

---

## Implementation Approach Notes

### GSD Skill vs. Shell Wrapper

The `--ralph` flag can be implemented via two approaches:

**Approach A: GSD Skill (Recommended)**
Create `.claude/skills/ralph/SKILL.md` with:
- `name: ralph`
- `disable-model-invocation: true` (user-only trigger)
- `context: fork` (runs in subagent for isolation)
- Skill content: instructions for autonomous phase execution

Pro: Native to GSD ecosystem, inherits GSD's context management, auto-discovered.
Con: Skill system was designed for Claude's use, not for wrapping external commands.

**Approach B: Shell Wrapper**
A Bash script (or function) that:
1. Parses `--ralph` from the GSD command arguments
2. Assembles context from `.planning/`
3. Invokes `claude --worktree <name> -p "$PROMPT" --allowedTools "$TOOLS"`

Pro: Simple, testable, independent of GSD's internal skill system.
Con: Not integrated into GSD's extension points, requires separate installation.

**Approach C: GSD Hook (Hybrid)**
Register hooks in `.claude/settings.json` that trigger on specific GSD events:
- `PreToolUse` matcher on GSD skill invocations
- `Stop` hook to handle post-execution

Pro: Hooks are the official extension mechanism.
Con: Hooks are reactive (fire on events), not proactive (cannot initiate execution).

**Recommendation: Start with Approach B (Shell Wrapper) for v2.0 MVP.** It is the simplest to build, test, and debug. Migrate to Approach A (GSD Skill) once the core logic is proven. The shell wrapper can be encapsulated as a skill later without changing the core logic.

### Prompt Assembly Strategy

The prompt for `claude -p` must include:
1. **Role**: "You are executing GSD phase N autonomously. Follow GSD conventions."
2. **Project context**: PROJECT.md content (what the project is, constraints)
3. **Phase plans**: The specific plan files for this phase, in dependency order
4. **State**: Current STATE.md (what has been done, what remains)
5. **Verification**: How to verify completion (test commands, build commands)
6. **Conventions**: GSD commit format, branch naming, file organization

This prompt replaces v1.x's `PROTOCOL-PROMPT.md.template` with a dynamically assembled equivalent. The key difference: v1.x generated a file that Ralph read; v2.0 passes the prompt directly to `claude -p`.

---

## Sources

- [Claude Code headless mode documentation](https://code.claude.com/docs/en/headless) -- HIGH confidence, official docs
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) -- HIGH confidence, official docs
- [Claude Code skills documentation](https://code.claude.com/docs/en/skills) -- HIGH confidence, official docs
- [Claude Agent SDK: Handle approvals and user input](https://platform.claude.com/docs/en/agent-sdk/user-input) -- HIGH confidence, official docs
- [Claude Code agent teams](https://code.claude.com/docs/en/agent-teams) -- HIGH confidence, official docs
- [GitHub Copilot CLI autopilot documentation](https://docs.github.com/en/copilot/concepts/agents/copilot-cli/autopilot) -- HIGH confidence, official docs
- [Ralph for Claude Code (frankbria/ralph-claude-code)](https://github.com/frankbria/ralph-claude-code) -- MEDIUM confidence, community project
- [GSD (get-shit-done)](https://github.com/gsd-build/get-shit-done) -- MEDIUM confidence, project README
- [gsd-skill-creator (Tibsfox)](https://github.com/Tibsfox/gsd-skill-creator) -- MEDIUM confidence, reference implementation
- [ClaudeLog: What is --max-turns](https://claudelog.com/faqs/what-is-max-turns-in-claude-code/) -- MEDIUM confidence, community documentation
- [ClaudeLog: AskUserQuestion tool](https://claudelog.com/faqs/what-is-ask-user-question-tool-in-claude-code/) -- MEDIUM confidence, community documentation

---
*Feature research for: gsd-ralph v2.0 Autopilot Core*
*Researched: 2026-03-09*
