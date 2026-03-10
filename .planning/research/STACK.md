# Stack Research: v2.1 Easy Install

**Domain:** Claude Code plugin/tool distribution and one-command installation
**Researched:** 2026-03-10
**Confidence:** HIGH (primary mechanism verified via official docs)

**Scope:** This document covers ONLY the stack additions/changes needed to make gsd-ralph installable in any repo with a single terminal command. The existing v2.0 runtime stack (Bash 3.2, Claude Code CLI, jq, bats-core) is NOT re-researched here. See the previous STACK.md in git history for v2.0 runtime decisions.

## Executive Summary

Claude Code now has a first-class **plugin system** (v1.0.33+, Feb 2026) that is the canonical way to distribute reusable skills, hooks, agents, and MCP servers. gsd-ralph should distribute as a **Claude Code plugin** rather than an npm package, shell installer, or manual copy. The plugin system handles discovery, installation, versioning, updates, and scope management natively. A parallel `npx` wrapper script provides the "single terminal command" UX for users who want to install without opening Claude Code first.

**The recommended approach: Plugin + npx bootstrap hybrid.**

1. **Primary distribution:** Claude Code plugin in a GitHub-hosted marketplace (`/plugin install gsd-ralph@gsd-ralph-marketplace`)
2. **One-command bootstrap:** `npx gsd-ralph-install` that (a) validates prerequisites, (b) installs the plugin via `claude plugin install`, and (c) copies non-plugin files (config template, launcher scripts)
3. **No new runtime dependencies.** The plugin system is built into Claude Code. The npx installer is a dev-time-only bootstrap.

## Three Distribution Approaches Evaluated

### Approach A: Claude Code Plugin (RECOMMENDED -- primary)

**What:** Package gsd-ralph as a Claude Code plugin with `.claude-plugin/plugin.json` manifest. Distribute via a GitHub-hosted marketplace. Users install with `/plugin install gsd-ralph@marketplace-name`.

**Evidence:** Official Claude Code plugin system launched with v1.0.33 (early 2026). Over 9,000 plugins now in the ecosystem. This IS the standard pattern -- verified via [official plugin docs](https://code.claude.com/docs/en/plugins), [marketplace docs](https://code.claude.com/docs/en/plugin-marketplaces), and the [official Anthropic marketplace repo](https://github.com/anthropics/claude-plugins-official).

**What the plugin bundles:**

| Component | Plugin Location | Purpose |
|-----------|----------------|---------|
| `skills/gsd-ralph-autopilot/SKILL.md` | `skills/` | Autonomous behavior rules (auto-loaded by Claude) |
| `commands/gsd/ralph.md` | `commands/` | `/gsd-ralph:ralph` slash command |
| `hooks/hooks.json` | `hooks/` | PreToolUse hook for AskUserQuestion denial |
| `scripts/ralph-launcher.sh` | `scripts/` | Core launcher with loop engine (592 LOC) |
| `scripts/assemble-context.sh` | `scripts/` | GSD context assembly |
| `scripts/validate-config.sh` | `scripts/` | Config validation |
| `scripts/ralph-hook.sh` | `scripts/` | PreToolUse hook script |
| `bin/ralph-stop` | `scripts/` | Graceful stop utility |
| `templates/*` | `templates/` | All .template files |
| `lib/**/*.sh` | `lib/` | Shared libraries and command handlers |

**Plugin manifest:**

```json
{
  "name": "gsd-ralph",
  "description": "Autonomous GSD execution with Ralph autopilot. Add --ralph to any GSD command and walk away.",
  "version": "2.1.0",
  "author": {
    "name": "daniswhoiam"
  },
  "homepage": "https://github.com/daniswhoiam/gsd-ralph",
  "repository": "https://github.com/daniswhoiam/gsd-ralph",
  "license": "MIT",
  "keywords": ["gsd", "ralph", "autopilot", "autonomous"]
}
```

**How hooks are bundled (critical detail):**

Plugin hooks go in `hooks/hooks.json` at the plugin root. Claude Code v2.1+ auto-discovers this file. Do NOT also declare hooks in `plugin.json` -- that causes a duplicate detection error.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "AskUserQuestion",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/ralph-hook.sh"
          }
        ]
      }
    ]
  }
}
```

**Key environment variable:** `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's cached installation directory. All script references in hooks and MCP configs MUST use this variable because plugins are copied to `~/.claude/plugins/cache/` on install.

**Installation scopes:**

| Scope | Settings File | Use Case |
|-------|--------------|----------|
| `user` (default) | `~/.claude/settings.json` | Personal install across all projects |
| `project` | `.claude/settings.json` | Shared via version control for team |
| `local` | `.claude/settings.local.json` | Project-specific, gitignored |

**Confidence:** HIGH -- verified from official Claude Code plugin docs (March 2026).

### Approach B: npx Bootstrap Installer (RECOMMENDED -- complement)

**What:** A minimal npm package (`gsd-ralph-install` or `create-gsd-ralph`) that validates prerequisites and installs the plugin programmatically.

**Why needed alongside the plugin:** The plugin system requires Claude Code to already be running. The npx approach gives users a one-command install from any terminal without needing to be inside a Claude Code session. It also handles prerequisite checking that the plugin system does not provide.

**What the npx installer does:**

1. Check prerequisites: `claude --version` (v1.0.33+), `jq --version`, `bash --version`, GSD presence (`~/.claude/get-shit-done/`)
2. Run `claude plugin marketplace add daniswhoiam/gsd-ralph` (adds the marketplace)
3. Run `claude plugin install gsd-ralph@gsd-ralph --scope user` (installs the plugin)
4. Copy non-plugin files to target repo if in a git repo (`.planning/config.json` template with `ralph.enabled: true`)
5. Print success message with next-step guidance

**Implementation technology:**

| Technology | Version | Purpose | Why |
|------------|---------|---------|-----|
| Node.js | 18+ | npx runtime | Already required by Claude Code; no new dependency |
| `package.json` "bin" field | npm standard | CLI entry point | `"bin": { "gsd-ralph-install": "./cli.js" }` makes it `npx gsd-ralph-install`-able |

**The installer script is ~80-120 lines of JavaScript.** It shells out to `claude plugin` commands. No framework needed.

```javascript
#!/usr/bin/env node
// cli.js -- gsd-ralph installer
const { execSync } = require('child_process');
// ... prerequisite checks, plugin install, config copy
```

**Package structure:**

```
gsd-ralph-install/
  package.json    # name: "gsd-ralph-install", bin: "./cli.js"
  cli.js          # Installer script
  README.md
```

**Confidence:** HIGH -- `npx` + `package.json` "bin" field is the most established npm pattern for one-command CLIs. Verified via [npm docs](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/) and widespread usage (create-react-app, create-next-app, etc.).

### Approach C: Vercel `npx skills add` (NOT RECOMMENDED)

**What:** The Vercel Labs [skills CLI](https://github.com/vercel-labs/skills) (`npx skills add owner/repo`) installs skills across multiple coding agents.

**Why not:** It only handles skills (`SKILL.md` files). gsd-ralph needs to distribute hooks, scripts, templates, and settings -- not just skills. The skills CLI cannot install hooks, cannot bundle shell scripts, and cannot manage `settings.local.json` merging. It solves a different problem (cross-agent skill portability) that gsd-ralph does not need.

**When it would be appropriate:** If gsd-ralph were skills-only with no hooks, no scripts, and no config. It is not.

**Confidence:** HIGH -- verified from [skills CLI docs](https://github.com/vercel-labs/skills) and [npm page](https://www.npmjs.com/package/skills). The limitations are clear from the feature set.

## Recommended Stack

### Core Technologies (NEW for v2.1)

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Claude Code Plugin System | v1.0.33+ | Distribution, installation, versioning, updates | THE standard way to distribute Claude Code extensions in 2026. Handles discovery, scoped installation, caching, and auto-updates natively. 9,000+ plugins use this pattern |
| Plugin marketplace (GitHub) | N/A | Plugin catalog | `.claude-plugin/marketplace.json` in the gsd-ralph repo. Users add once, install/update plugins from it. Free, no registry needed |
| npm package (installer only) | npm registry | One-command bootstrap | `npx gsd-ralph-install` for users who want to install from terminal without opening Claude Code first. Dev-time only, not a runtime dependency |
| Node.js | 18+ | npx installer runtime | Already required by Claude Code. No new dependency. The installer is ~100 lines using only `child_process` and `fs` builtins |

### Supporting Libraries (NEW for v2.1)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| None | N/A | N/A | The installer uses only Node.js builtins (`child_process`, `fs`, `path`). No external dependencies. This keeps `npx` execution instant |

### Development Tools (NEW for v2.1)

| Tool | Purpose | Notes |
|------|---------|-------|
| `claude --plugin-dir ./` | Test plugin locally during development | Loads plugin from working directory without installing. Restart to pick up changes |
| `claude plugin validate .` | Validate plugin manifest | Checks JSON syntax, required fields, directory structure |
| `npm pack --dry-run` | Verify npm package contents | Ensure only cli.js and package.json are included in the installer package |
| bats-core | Test installer prerequisites check | Mock `claude --version` output, test failure paths |

## What the Plugin Approach Changes in gsd-ralph

### Repository Structure Changes

The gsd-ralph repo needs to serve dual purposes: (1) development/testing workspace, and (2) Claude Code plugin source.

**Current structure (v2.0):**
```
gsd-ralph/
  bin/gsd-ralph          # CLI entry (legacy v1.x subcommands)
  bin/ralph-stop         # Graceful stop
  scripts/*.sh           # Core scripts
  lib/**/*.sh            # Libraries
  templates/             # Templates
  tests/                 # Bats tests
  .claude/commands/      # Slash command
  .claude/skills/        # Skills
  .claude/settings.local.json
```

**Required additions for v2.1:**
```
gsd-ralph/
  .claude-plugin/
    plugin.json          # NEW: Plugin manifest
    marketplace.json     # NEW: Marketplace catalog (self-referencing)
  hooks/
    hooks.json           # NEW: Plugin hooks config (moved from settings.local.json)
  skills/                # MOVED: from .claude/skills/ to plugin root
    gsd-ralph-autopilot/
      SKILL.md
  commands/              # MOVED: from .claude/commands/ to plugin root
    gsd/
      ralph.md
  installer/             # NEW: npx installer package
    package.json
    cli.js
  # ... existing scripts/, lib/, templates/, tests/ unchanged
```

**Key insight:** The plugin system looks for `skills/`, `commands/`, and `hooks/` at the plugin root -- NOT inside `.claude/`. During development, use `claude --plugin-dir .` to load the repo as a plugin. For distribution, the marketplace points to the repo as a plugin source.

### settings.local.json Handling

**Current state:** gsd-ralph v2.0 writes its PreToolUse hook and permissions into `.claude/settings.local.json` in the target project.

**Plugin approach:** Hooks defined in `hooks/hooks.json` within the plugin are automatically registered when the plugin is installed. No more manual `settings.local.json` manipulation. The plugin system handles merge/unmerge natively.

**Migration concern:** Projects that installed v2.0 manually will have hooks in `settings.local.json`. The v2.1 installer should detect and clean these up to avoid duplicate hooks.

### `${CLAUDE_PLUGIN_ROOT}` Path Resolution

**Current state:** Scripts reference `$GSD_RALPH_HOME` which is resolved from the CLI binary's location.

**Plugin state:** Scripts are copied to `~/.claude/plugins/cache/<plugin-hash>/`. References must use `${CLAUDE_PLUGIN_ROOT}` in hooks and can use `${CLAUDE_SKILL_DIR}` in skills.

**Impact on scripts:** `ralph-launcher.sh` currently resolves `GSD_RALPH_HOME` from `BASH_SOURCE[0]`. Inside a plugin, this resolves to the cache directory automatically. No changes needed to the script's self-location logic -- it already follows symlinks and resolves the real path.

## What NOT to Add

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| Homebrew formula | Unnecessary complexity for a Claude Code-native tool. Users already have Claude Code installed via npm or native installer | Plugin system + npx installer |
| curl pipe to bash installer | Security concerns, no prerequisite checking, not idempotent | npx installer with proper checks |
| Docker container | gsd-ralph is a thin integration layer, not a service. Docker adds massive overhead for a few shell scripts | Direct plugin installation |
| npm runtime dependencies in installer | Every dependency slows `npx` startup and adds supply chain risk | Node.js builtins only (`child_process`, `fs`, `path`) |
| Custom update mechanism | Claude Code plugins have auto-update built in (marketplace-level). Bumping `version` in `plugin.json` triggers updates for all users | Plugin version field + marketplace auto-update |
| Monorepo package manager (pnpm, yarn) | Only one package (the installer). No workspace complexity needed | Simple npm with single package.json |
| TypeScript for installer | 100 lines of code. TypeScript adds build step, tsconfig, compilation. Not worth it | Plain JavaScript (CommonJS for maximum compatibility) |
| Vercel `npx skills add` | Only installs skills. Cannot distribute hooks, scripts, templates, or settings | Claude Code plugin system |
| Official Anthropic marketplace submission | Adds review/approval delay. gsd-ralph is a niche tool for GSD users, not a general-purpose plugin | Self-hosted marketplace in the gsd-ralph repo |

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| Claude Code plugin | Manual file copy script | Never. The plugin system is the standard and handles versioning, updates, scope, and cleanup natively |
| Self-hosted GitHub marketplace | Official Anthropic marketplace | If gsd-ralph grows to broader adoption and wants official distribution. Submit via [claude.ai/settings/plugins/submit](https://claude.ai/settings/plugins/submit) |
| npx bootstrap installer | No installer (plugin-only) | If all users are comfortable running `/plugin marketplace add` and `/plugin install` inside Claude Code. The npx wrapper adds convenience, not necessity |
| CommonJS (require) in installer | ESM (import) in installer | If targeting Node.js 22+ only. CommonJS works on Node.js 14+ and has no `.mjs` extension confusion |
| Single repo (plugin + installer) | Separate repos (plugin vs installer) | Never. Keeping everything in one repo avoids version synchronization issues |

## Version Compatibility

| Requirement | Minimum | Current | Notes |
|-------------|---------|---------|-------|
| Claude Code | 1.0.33+ | (latest) | Plugin system requires v1.0.33. `/plugin` command, `claude plugin install` CLI |
| Node.js | 18+ | (varies) | Required by Claude Code itself. npx installer uses only builtins |
| npm/npx | 9+ | (varies) | Ships with Node.js 18+. `npx` executes the installer without global install |
| Git | 2.20+ | (varies) | Required for marketplace cloning. Well within range on any modern system |
| GSD | Current | Current | gsd-ralph cannot function without GSD. Installer checks for `~/.claude/get-shit-done/` |
| Bash | 3.2+ | (varies) | macOS system Bash. Runtime requirement (unchanged from v2.0) |
| jq | 1.6+ | (varies) | Runtime requirement for hook scripts (unchanged from v2.0) |

**No new runtime dependencies.** The plugin system is built into Claude Code. The npm installer package is execution-time only (downloaded by npx, runs once, not retained).

## Installation Flow (User Perspective)

### Path 1: npx one-command install (RECOMMENDED for new users)

```bash
# From any terminal:
npx gsd-ralph-install

# Output:
# Checking prerequisites...
#   Claude Code v2.3.1 ... OK
#   GSD framework ... OK
#   jq 1.7 ... OK
#   Bash 3.2.57 ... OK
# Adding gsd-ralph marketplace...
# Installing gsd-ralph plugin (user scope)...
# Done! gsd-ralph installed.
#
# Next steps:
#   1. Open Claude Code in your project: claude
#   2. Run: /gsd-ralph:ralph execute-phase <N>
#   3. Or use --dry-run to preview: /gsd-ralph:ralph execute-phase <N> --dry-run
```

### Path 2: Plugin install from within Claude Code

```
# Inside Claude Code session:
/plugin marketplace add daniswhoiam/gsd-ralph
/plugin install gsd-ralph@gsd-ralph

# Done. Restart Claude Code to activate hooks.
```

### Path 3: Team project setup (committed to repo)

```bash
# In .claude/settings.json (committed to repo):
{
  "extraKnownMarketplaces": {
    "gsd-ralph": {
      "source": {
        "source": "github",
        "repo": "daniswhoiam/gsd-ralph"
      }
    }
  },
  "enabledPlugins": {
    "gsd-ralph@gsd-ralph": true
  }
}

# Team members get prompted to install when they trust the project folder.
```

## Sources

- [Claude Code Plugin System (official docs)](https://code.claude.com/docs/en/plugins) -- Plugin creation, manifest format, directory structure, `--plugin-dir` testing, component types (verified 2026-03-10, HIGH confidence)
- [Claude Code Plugin Marketplace (official docs)](https://code.claude.com/docs/en/plugin-marketplaces) -- marketplace.json schema, distribution options (GitHub, npm, git), version management, team configuration (verified 2026-03-10, HIGH confidence)
- [Discover and Install Plugins (official docs)](https://code.claude.com/docs/en/discover-plugins) -- Installation scopes, `/plugin install` command, marketplace add/update, team marketplace setup via `extraKnownMarketplaces` (verified 2026-03-10, HIGH confidence)
- [Plugins Reference (official docs)](https://code.claude.com/docs/en/plugins-reference) -- Complete plugin.json schema, `${CLAUDE_PLUGIN_ROOT}` variable, hooks/hooks.json format, plugin caching behavior, CLI commands, debugging tools (verified 2026-03-10, HIGH confidence)
- [Claude Code Skills (official docs)](https://code.claude.com/docs/en/skills) -- Skills merged with commands as of v2.1.3, `SKILL.md` format, `${CLAUDE_SKILL_DIR}` variable, Agent Skills open standard (verified 2026-03-10, HIGH confidence)
- [Anthropic Official Marketplace (GitHub)](https://github.com/anthropics/claude-plugins-official) -- 9.7k stars, reference implementation for marketplace structure, `plugins/` and `external_plugins/` directory pattern (verified 2026-03-10, HIGH confidence)
- [Vercel Skills CLI (GitHub)](https://github.com/vercel-labs/skills) -- Skills-only installer, does NOT handle hooks/scripts/settings. Evaluated and rejected for gsd-ralph's needs (verified 2026-03-10, HIGH confidence)
- [npm package.json bin field (official docs)](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/) -- How npx resolves and runs CLI binaries from npm packages (verified 2026-03-10, HIGH confidence)
- [npx create-* pattern](https://www.alexchantastic.com/building-an-npm-create-package) -- Convention for npm init/create packages. Informed installer naming decision (verified 2026-03-10, MEDIUM confidence)

---
*Stack research for: gsd-ralph v2.1 Easy Install*
*Researched: 2026-03-10*
