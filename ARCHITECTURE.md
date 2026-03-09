# gsd-ralph v2.0 Architecture

Thin integration layer bridging GSD planning with Ralph autonomous execution via Claude Code headless mode.

## Core Principle

> "Coupling to GSD tools is fine -- duplicating GSD logic is not."

gsd-ralph reads GSD artifacts and calls GSD tools. It never reimplements roadmap parsing, state management, plan generation, or any logic that GSD already owns.

## What gsd-ralph Does

These are the responsibilities gsd-ralph owns:

- **Read STATE.md** to determine current execution position (phase, plan)
- **Read PLAN.md files** to provide task context to Claude Code
- **Read config.json** for Ralph-specific settings (`ralph` key)
- **Call gsd-tools.cjs** commands for state operations (coupled, not duplicated)
- **Assemble GSD context** for `--append-system-prompt-file` injection
- **Launch headless Claude Code** instances with appropriate permissions and max-turns
- **Detect iteration completion/failure** from Claude Code exit codes
- **Loop fresh instances** for incomplete work until the phase is done

## What gsd-ralph NEVER Does

These boundaries are non-negotiable:

- **NEVER parse ROADMAP.md** to determine phase ordering -- GSD does this
- **NEVER update STATE.md directly** -- GSD handles state transitions
- **NEVER generate plans, research, or summaries** -- GSD does this
- **NEVER manage worktrees** -- Claude Code handles this via `--worktree`
- **NEVER replicate permission logic** -- Claude Code's `--permission-mode` and `--allowedTools` handle this
- **NEVER invoke GSD slash commands in headless mode** -- they are unavailable; use natural language prompts + system prompt injection instead

## Component Boundaries

| Component | Owns | Delegates To |
|-----------|------|--------------|
| SKILL.md | Autonomous behavior rules (decisions, checkpoints, human-action) | Claude Code skill discovery for loading |
| config.json `ralph` key | `enabled`, `max_turns`, `permission_tier` settings | GSD config infrastructure for storage |
| Context assembly | Reading STATE.md + plan files, formatting output | GSD for state content; Claude Code for prompt injection |
| Launcher (Phase 11) | Invoking `claude -p` with correct flags | Claude Code for execution; GSD for workflow |

## Anti-Patterns

Avoid these mistakes -- most are lessons from v1.x:

1. **Replicating GSD state management** -- Never write code to parse ROADMAP.md frontmatter, update progress percentages, or manage phase transitions. GSD does this.

2. **Command-aware SKILL.md** -- The behavior ruleset is universal. Do NOT create conditional logic based on which GSD command is running.

3. **Over-engineering config** -- v1.x had 12 settings and it was too many. Stick to 3-5 essential settings. Resist adding fields "just in case."

4. **Bundling SKILL.md into context blob** -- Keep SKILL.md separate. It evolves independently as GSD and Claude Code evolve. Claude Code's native skill discovery handles loading.

5. **Using `--system-prompt` instead of `--append-system-prompt`** -- The `--system-prompt` flag REPLACES the entire default prompt, breaking Claude Code's built-in capabilities. Always use `--append-system-prompt` or `--append-system-prompt-file` to ADD to the defaults.

6. **Context assembly reading too many files** -- Focused context only: STATE.md + active phase plans. Claude discovers PROJECT.md and REQUIREMENTS.md from CLAUDE.md if needed.

## Dependency Direction

```
gsd-ralph --> GSD (reads artifacts, calls tools)
gsd-ralph --> Claude Code (launches instances, uses CLI flags)

GSD --> (nothing from gsd-ralph)
Claude Code --> (nothing from gsd-ralph)
```

gsd-ralph depends on GSD and Claude Code, never the reverse. Updates to GSD or Claude Code should flow through without breaking gsd-ralph, because gsd-ralph only reads well-defined artifacts (STATE.md, PLAN.md, config.json) and calls documented CLI flags.

---

*Architecture defined: 2026-03-09*
*Target: ~200-400 LOC (thin integration layer)*
