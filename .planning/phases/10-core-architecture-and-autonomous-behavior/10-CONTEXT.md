# Phase 10: Core Architecture and Autonomous Behavior - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Foundational artifacts that define what gsd-ralph does vs. what GSD/Claude Code do. Delivers: SKILL.md with autonomous behavior rules, config schema extension in `.planning/config.json`, GSD context assembly logic, and architectural boundary documentation. This phase produces no user-facing CLI — it creates the foundation that Phase 11's launcher will reference.

</domain>

<decisions>
## Implementation Decisions

### Autonomous response strategy
- Always pick the first option when GSD presents multi-option decisions (AskUserQuestion). GSD skills are designed with the recommended option first — deterministic and debuggable.
- Auto-approve human-verify checkpoints with logging emphasis: write a brief rationale for WHY it was approved, AND create a git commit/tag at each checkpoint for incremental state review.
- Skip human-action steps and log them. Mark as skipped in the audit log with the action description. User reviews skipped actions post-run.
- Universal ruleset — one set of autonomous behavior rules regardless of which GSD command Ralph is running. No command-aware conditional logic.

### Context injection depth
- Focused context: STATE.md (current position) + the specific phase plan being executed. Claude discovers PROJECT.md/REQUIREMENTS.md from CLAUDE.md if needed.
- Inject via `--append-system-prompt` flag on `claude -p`. Context appears as system instructions, cleanly separated from the user prompt (which is the GSD command).

### Context assembly location
- Claude's discretion: shell function in launcher script OR GSD tool extension — decided during research based on what's cleanest.
- Clarification: coupling to GSD tools is fine (gsd-ralph is intentionally coupled to GSD). Duplicating GSD logic is not. The thin-layer principle means "don't reimplement" not "don't depend on."

### SKILL.md vs context bundling
- Claude's discretion on whether SKILL.md behavior rules are bundled into the assembled context blob or kept as a separate persistent file. Consider maintainability — SKILL.md may evolve independently as GSD and this project develop.

### Configuration scope
- Essential settings only (3-5): `enabled` (bool), `max_turns` (int, default 50), `permission_tier` (default/auto-mode/yolo).
- Config lives inside `.planning/config.json` under a `"ralph"` key. Single source of truth, committed to repo, readable by GSD tools.
- Default `max_turns`: 50 per iteration.
- Schema validation: strict with warnings — accept unknown keys but warn the user. Helps catch typos without breaking on new fields.

### Claude's Discretion
- Context assembly implementation approach (shell function vs GSD tool extension)
- SKILL.md bundling strategy (bundled vs separate file) — weigh maintainability
- Exact SKILL.md file format and structure
- Architectural boundary documentation format and location

</decisions>

<specifics>
## Specific Ideas

- "Coupling to GSD tools is fine — duplicating GSD logic is not" — this is the architectural principle. gsd-ralph can call GSD tools/commands but must never reimplement roadmap parsing, state management, etc.
- Auto-approve checkpoints should create git snapshots (commit/tag) for post-run review traceability, not just log entries.
- v1.x `.ralphrc` had 12 settings — v2.0 intentionally slims to 3-5 essential settings. Don't carry forward v1.x config complexity.

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `.ralphrc`: v1.x Ralph config with ALLOWED_TOOLS, circuit breaker thresholds — reference for sensible defaults, not carried forward as-is
- `.ralph/AGENT.md`: v1.x agent instructions — reference for Bash 3.2 compatibility patterns (no associative arrays, no readarray)
- `.planning/config.json`: existing GSD config with mode, workflow, granularity fields — Ralph config will extend this under a `"ralph"` key

### Established Patterns
- GSD config is JSON in `.planning/config.json` — Ralph follows the same pattern
- GSD skills use `gsd-tools.cjs` for operations — context assembly could follow this if research supports it
- Bash 3.2+ compatibility required (macOS system bash): no `${var,,}`, no associative arrays, `date -u +%Y-%m-%dT%H:%M:%SZ`

### Integration Points
- `.planning/config.json` — Ralph config namespace (`"ralph": {...}`)
- `claude -p` with `--append-system-prompt` — context injection target
- GSD's STATE.md and phase plan files — read inputs for context assembly
- `.claude/` directory — potential home for SKILL.md if kept as separate persistent file

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 10-core-architecture-and-autonomous-behavior*
*Context gathered: 2026-03-09*
