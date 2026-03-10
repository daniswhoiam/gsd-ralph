# Phase 12: Defense-in-Depth and Observability - Context

**Gathered:** 2026-03-10
**Status:** Ready for planning

<domain>
## Phase Boundary

Hardening the autopilot against runaway execution and providing visibility into autonomous runs. Delivers: circuit breaker with wall-clock timeout + graceful stop, PreToolUse hook that denies AskUserQuestion as defense-in-depth, per-iteration progress display, and audit logging of hook denials/skipped steps. Builds on Phase 11's loop execution engine and Phase 10's SKILL.md behavioral rules.

</domain>

<decisions>
## Implementation Decisions

### Circuit breaker
- Wall-clock timeout default: **30 minutes**. Configurable via `ralph.timeout_minutes` in `.planning/config.json`.
- Graceful stop mechanism: **`.ralph/.stop` file**. User touches this file; loop checks for it between iterations.
- Research needed: a convenience bash command or GSD skill so users don't have to remember the file path. Investigate lightweight wrapper (e.g., `ralph-stop` script or `/gsd:ralph-stop` skill).
- On trigger behavior: **Claude's discretion** — decide based on what's cleanest for bash process management (wait for current iteration vs kill immediately).
- Terminal bell on circuit breaker trigger (consistent with Phase 11's existing bell pattern).

### AskUserQuestion hook
- **PreToolUse hook** denies AskUserQuestion calls as defense-in-depth (SKILL.md is the primary layer).
- Hook response: **deny with guidance** — return a message like "AskUserQuestion is blocked in autopilot mode. Pick the first option or log the blocker and exit."
- Hook also **logs the denied question** to the audit file (see audit logging below).
- Hook scope: **AskUserQuestion only**. Other tools are controlled by the permission tier.
- Hook script location: **`scripts/ralph-hook.sh`** — alongside other Ralph scripts.
- Hook installation: **auto-install on launch**. ralph-launcher.sh writes the hook config to settings before spawning claude -p, removes it on exit. Zero user setup.
- Research flag from STATE.md: "Validate PreToolUse hook behavior for AskUserQuestion in headless mode" — must be answered during research.

### Progress display
- **Summary per iteration** to stdout: iteration number, elapsed time (per-iteration + total), STATE.md status (phase/plan/status), exit code.
- Format: one-line summary after each iteration completes.
- Timing: show both per-iteration duration and total elapsed time (e.g., "Iteration 3 complete (2m 14s) | Total: 8m 32s").
- **OBSV-03 (real-time stream-json parsing) deferred to v2.1**. Summary per iteration satisfies the visibility intent for v2.0. Stream-json parsing is complex (async bash parsing, partial JSON handling) for marginal benefit at this stage.

### Audit logging
- Audit scope: **hook denials + skipped steps**. AskUserQuestion attempts blocked by hook (with question text) and human-action steps skipped by SKILL.md.
- Format: **plain text, human-readable**. Timestamped lines like: `[2026-03-10 14:32:07] DENIED AskUserQuestion: "Which approach for X?"`
- Location: **`.ralph/audit.log`** — single file, overwritten or appended per run.
- Post-run: **summary at end** — print "Audit: N decisions logged. See .ralph/audit.log for details." Only if there were logged events. Non-intrusive.

### Claude's Discretion
- Circuit breaker trigger behavior (wait for current iteration vs kill immediately)
- Hook config format for auto-install/removal in settings
- Audit log retention strategy (overwrite vs append across runs)
- Convenience stop command implementation approach (script vs skill)
- Progress display exact format string

</decisions>

<specifics>
## Specific Ideas

- "In the spirit of Ralph" — user expressed interest in Ralph reasoning about AskUserQuestion answers rather than just blocking. This is v2.1+ scope (ORCH-03: intelligent response strategies). For v2.0, deny-with-guidance is the lightweight version.
- Convenience stop mechanism: user wants a bash command rather than raw `touch .ralph/.stop`. Research whether a simple script or GSD skill is better.
- OBSV-03 explicitly deferred to v2.1 — update REQUIREMENTS.md traceability to reflect this.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `scripts/ralph-launcher.sh`: Contains `run_loop()` — the iteration loop that needs circuit breaker integration. Also has `_capture_state_snapshot()` for progress detection.
- `scripts/assemble-context.sh`: Context assembly called per-iteration — circuit breaker check can happen before this call.
- `scripts/validate-config.sh`: Config validation — extend for `ralph.timeout_minutes`.
- `.claude/skills/gsd-ralph-autopilot/SKILL.md`: Primary AskUserQuestion prevention layer. Hook is defense-in-depth.

### Established Patterns
- Bash 3.2 compatibility: no associative arrays, no `${var,,}`, `date -u +%Y-%m-%dT%H:%M:%SZ`
- Terminal bell via `printf '\a'` on completion/failure (Phase 11)
- Config in `.planning/config.json` under `"ralph"` key with strict-with-warnings validation
- Guard pattern: `if [ "${BASH_SOURCE[0]}" = "$0" ]` for testable scripts

### Integration Points
- `run_loop()` in ralph-launcher.sh: circuit breaker check + progress display added to the loop
- `.claude/settings.json` or `.claude/settings.local.json`: hook auto-install target
- `.ralph/audit.log`: new file for audit logging (created by hook + launcher)
- `.ralph/.stop`: new sentinel file for graceful stop

</code_context>

<deferred>
## Deferred Ideas

- OBSV-03 (real-time stream-json parsing) — deferred to v2.1. Summary per iteration is sufficient for v2.0.
- ORCH-03 (intelligent AskUserQuestion response strategies) — v2.1+. User expressed interest in Ralph reasoning about questions rather than blocking. Requires Agent SDK or more sophisticated prompt engineering.

</deferred>

---

*Phase: 12-defense-in-depth-and-observability*
*Context gathered: 2026-03-10*
