# Architecture Research

**Domain:** Installer for gsd-ralph autopilot (v2.1 Easy Install)
**Researched:** 2026-03-10
**Confidence:** HIGH (official Claude Code docs verified, existing codebase inspected, GSD installer pattern confirmed)

## The Installation Challenge

gsd-ralph v2.0 lives in its own repo and works in that repo. To use it in another project, a user must manually copy scripts, skills, commands, hooks, and config -- knowing exactly what goes where. v2.1 must automate this with a single command, without breaking the target repo's existing Claude Code configuration.

Key constraints:
1. gsd-ralph is pure Bash (no npm package, no build step)
2. The target repo likely already has `.claude/settings.local.json` with user-specific permissions
3. Claude Code discovers skills/commands from `.claude/` in the project root
4. Hook scripts need executable paths that work from the target repo's root
5. GSD must already be installed (prerequisite, not something we install)

## System Overview: Installation Flow

```
┌─────────────────────────────────────────────────────────────────────┐
│                     Source: gsd-ralph repo                          │
│                                                                     │
│  scripts/                    .claude/skills/gsd-ralph-autopilot/    │
│  ├── ralph-launcher.sh       └── SKILL.md                          │
│  ├── assemble-context.sh                                            │
│  ├── validate-config.sh     .claude/commands/gsd/                   │
│  └── ralph-hook.sh          └── ralph.md                            │
│                                                                     │
│  bin/ralph-stop             templates/ralphrc.template               │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
                    install-ralph.sh
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                     Target: user's project repo                     │
│                                                                     │
│  scripts/ralph/                .claude/skills/gsd-ralph-autopilot/  │
│  ├── ralph-launcher.sh         └── SKILL.md                        │
│  ├── assemble-context.sh                                            │
│  ├── validate-config.sh       .claude/commands/gsd/                 │
│  ├── ralph-hook.sh            └── ralph.md                          │
│  └── ralph-stop                                                     │
│                               .claude/settings.local.json           │
│  .planning/config.json        (hooks merged, not overwritten)       │
│  (ralph section added)                                              │
└─────────────────────────────────────────────────────────────────────┘
```

## Decision 1: Distribution Mechanism

### Recommendation: Bash installer script fetched via curl from GitHub

**Why not npm/npx:**
- gsd-ralph is pure Bash. Wrapping it in an npm package adds a Node.js runtime dependency for zero benefit.
- GSD itself uses `npx get-shit-done-cc` because it includes Node.js tooling (`gsd-tools.cjs`). gsd-ralph has no Node code.

**Why not a Claude Code plugin:**
- Plugins namespace their skills (e.g., `/gsd-ralph:ralph` instead of `/gsd:ralph`). gsd-ralph's command is `gsd:ralph` -- it belongs in the GSD namespace, not a plugin namespace.
- Plugin hooks live in `hooks/hooks.json` inside the plugin directory. gsd-ralph's hook (`ralph-hook.sh`) is installed/removed dynamically during launcher execution via `_install_hook`/`_remove_hook`, not as a persistent plugin hook.
- Plugin skills are read-only copies in a cache. gsd-ralph's launcher references `$PROJECT_ROOT/scripts/ralph-hook.sh` with absolute paths -- it needs the scripts to be in a known, stable location in the project tree.
- The plugin system is designed for self-contained extensions. gsd-ralph is an integration layer that modifies `.planning/config.json` and reads GSD state files -- it's deeply coupled to the project's file structure.

**Why not git submodule:**
- Adds `.gitmodules` complexity to every target repo.
- Submodule paths don't match where files need to live (scripts in `scripts/ralph/`, skills in `.claude/skills/`).
- Updates require `git submodule update --remote` which many developers forget.

**The curl pattern works because:**
- Zero dependencies beyond `bash`, `curl`, and `jq` (which gsd-ralph already requires).
- Single command: `curl -fsSL https://raw.githubusercontent.com/.../install-ralph.sh | bash`
- The installer is a self-contained Bash script that copies files, merges config, and validates prerequisites.
- Follows established CLI tool installation patterns (Homebrew, rustup, nvm).
- Version pinning via git tags: `curl ... /v2.1.0/install-ralph.sh | bash`

**Confidence:** HIGH -- based on the constraints (pure Bash, GSD namespace coupling, dynamic hook install), no other distribution mechanism fits.

## Decision 2: Source File Acquisition

### Recommendation: GitHub release tarball extraction

The installer script should:
1. Download a tagged release tarball from GitHub (not clone the entire repo)
2. Extract only the files needed for installation
3. Clean up the tarball after extraction

```bash
# Installer fetches the release tarball
TARBALL_URL="https://github.com/USER/gsd-ralph/archive/refs/tags/v${VERSION}.tar.gz"
curl -fsSL "$TARBALL_URL" | tar xz -C "$TMPDIR" --strip-components=1
```

**Why tarball over git clone:**
- Faster (no .git history, no submodules)
- Smaller download (tarball is just source files)
- No git dependency for the install step itself
- Clean: no leftover `.git` in temp directory

**Alternative considered: embed files in the installer script itself.** This would make the installer fully self-contained (no network fetch after initial curl) but makes the script enormous and hard to maintain. Reject.

## Decision 3: Target Directory Layout

### What gets installed where

| Source File | Target Location | Rationale |
|-------------|----------------|-----------|
| `scripts/ralph-launcher.sh` | `scripts/ralph/ralph-launcher.sh` | Namespaced under `ralph/` to avoid collisions with user's own scripts |
| `scripts/assemble-context.sh` | `scripts/ralph/assemble-context.sh` | Same namespace |
| `scripts/validate-config.sh` | `scripts/ralph/validate-config.sh` | Same namespace |
| `scripts/ralph-hook.sh` | `scripts/ralph/ralph-hook.sh` | Same namespace |
| `bin/ralph-stop` | `scripts/ralph/ralph-stop` | Flatten into scripts/ralph/ -- no separate bin/ in target |
| `.claude/skills/gsd-ralph-autopilot/SKILL.md` | `.claude/skills/gsd-ralph-autopilot/SKILL.md` | Claude Code discovers skills from `.claude/skills/` -- must be here |
| `.claude/commands/gsd/ralph.md` | `.claude/commands/gsd/ralph.md` | Claude Code discovers commands from `.claude/commands/` -- must be here |

### Critical: Path References Inside Scripts

The launcher currently uses `PROJECT_ROOT`-relative paths:

```bash
CONTEXT_SCRIPT="$PROJECT_ROOT/scripts/assemble-context.sh"
VALIDATE_SCRIPT="$PROJECT_ROOT/scripts/validate-config.sh"
```

These must change to `$PROJECT_ROOT/scripts/ralph/` in the installed versions. The installer should **not** sed-replace paths at install time. Instead, the source scripts should use a `RALPH_SCRIPTS_DIR` variable:

```bash
RALPH_SCRIPTS_DIR="${RALPH_SCRIPTS_DIR:-$PROJECT_ROOT/scripts/ralph}"
CONTEXT_SCRIPT="$RALPH_SCRIPTS_DIR/assemble-context.sh"
VALIDATE_SCRIPT="$RALPH_SCRIPTS_DIR/validate-config.sh"
```

This way the scripts work both in the gsd-ralph development repo (by setting `RALPH_SCRIPTS_DIR`) and in target repos (where the default `scripts/ralph/` is correct).

### The command file path update

The command file `.claude/commands/gsd/ralph.md` currently says:

```
bash scripts/ralph-launcher.sh $ARGUMENTS
```

The installed version must say:

```
bash scripts/ralph/ralph-launcher.sh $ARGUMENTS
```

The installer handles this substitution, or the source command file uses a path that works in both contexts.

## Decision 4: Settings Merge Strategy

### Recommendation: Deep merge with conflict detection, same pattern as existing `_install_hook`

The existing `_install_hook()` in `ralph-launcher.sh` already demonstrates the correct pattern for merging into `settings.local.json`:

```bash
# Read existing settings or start with empty object
local existing="{}"
if [ -f "$settings_file" ]; then
    existing=$(cat "$settings_file")
fi

# Merge hook config into existing settings
echo "$existing" | jq --arg cmd "$hook_script" '
    .hooks.PreToolUse = (.hooks.PreToolUse // []) + [{...}]
' > "$settings_file"
```

**For the installer, the same principle applies but is NOT needed for hooks.** The launcher already handles hook install/uninstall at runtime. The installer does NOT need to modify `settings.local.json` for hooks.

What the installer DOES need to handle:

1. **`.planning/config.json`**: Add `ralph` section if missing
2. **`.claude/settings.json`** (project, committable): Optionally add permission rules for ralph scripts (e.g., `Bash(bash scripts/ralph/*:*)`)

### Config.json merge

```bash
# Add ralph section to .planning/config.json if it doesn't exist
if [ -f "$CONFIG_FILE" ]; then
    if ! jq -e '.ralph' "$CONFIG_FILE" >/dev/null 2>&1; then
        jq '. + {"ralph": {"enabled": true, "max_turns": 50, "permission_tier": "default", "timeout_minutes": 30}}' \
            "$CONFIG_FILE" > "$CONFIG_FILE.tmp" && mv "$CONFIG_FILE.tmp" "$CONFIG_FILE"
    else
        echo "ralph config already exists in $CONFIG_FILE, skipping"
    fi
fi
```

### Settings.json: Do NOT auto-modify

The installer should NOT modify `.claude/settings.json` or `.claude/settings.local.json`. Reasons:
- `settings.local.json` is user-specific and gitignored -- the installer should not assume what permissions a user wants
- `settings.json` is project-shared -- adding permissions there affects all collaborators
- The launcher already handles hook installation dynamically at runtime
- Permission rules are specific to the user's trust level

Instead, the installer should **print guidance** about what permissions to add if desired:

```
To allow Ralph scripts without prompting, add to .claude/settings.json:
  "Bash(bash scripts/ralph/*:*)"
```

## Decision 5: Prerequisite Detection

### Required prerequisites

| Prerequisite | Detection | Why Required |
|-------------|-----------|-------------|
| `bash` >= 3.2 | `bash --version` | All scripts are Bash |
| `jq` | `command -v jq` | Config parsing, hook JSON |
| `curl` | `command -v curl` | Fetching release tarball (install only) |
| `git` | `command -v git` | `git rev-parse --show-toplevel` in scripts |
| Claude Code | `command -v claude` | The runtime that executes everything |
| GSD | Check for `.claude/commands/gsd/` or `~/.claude/get-shit-done/` | gsd-ralph is a GSD integration layer |

### GSD detection strategy

GSD can be installed globally (`~/.claude/get-shit-done/`) or locally (`.claude/` in the project). The installer should check both:

```bash
gsd_found=false
if [ -d "$HOME/.claude/get-shit-done" ]; then
    gsd_found=true
elif [ -f ".claude/commands/gsd/new-project.md" ] || \
     ls .claude/commands/gsd/*.md >/dev/null 2>&1; then
    gsd_found=true
fi
```

If GSD is not found, the installer should warn (not fail) -- the user may install GSD after Ralph.

### Version detection is secondary

Claude Code and GSD don't have stable version APIs that are easy to parse. The installer should check for presence, not version. Version-specific issues should be documented, not enforced.

## Decision 6: Installer Script Structure

### Recommended structure

```
install-ralph.sh (single file, self-contained logic)
├── Prerequisite checks
├── Source acquisition (download + extract tarball)
├── File installation (copy to target locations)
├── Config merge (.planning/config.json ralph section)
├── Path fixup (command file script path)
├── Post-install validation (check files exist, are executable)
└── Next-steps guidance (permissions, usage)
```

### Uninstall support

The installer should also support `--uninstall`:

```bash
install-ralph.sh --uninstall
```

This removes:
- `scripts/ralph/` directory
- `.claude/skills/gsd-ralph-autopilot/`
- `.claude/commands/gsd/ralph.md`
- `ralph` key from `.planning/config.json`

It does NOT remove `.ralph/` (runtime state, audit logs -- user may want to keep).

### Idempotency

The installer must be safe to run multiple times:
- Check if files already exist before copying
- Use `--force` flag to overwrite existing files
- Default behavior: skip existing files with a warning

## Component Responsibilities

| Component | Responsibility | New vs Existing |
|-----------|---------------|-----------------|
| `install-ralph.sh` | Download, validate prereqs, copy files, merge config | **NEW** |
| `scripts/ralph/ralph-launcher.sh` | Core launcher (existing, with `RALPH_SCRIPTS_DIR` support) | **MODIFIED** (path variable) |
| `scripts/ralph/assemble-context.sh` | Context assembly (unchanged logic) | **COPIED** |
| `scripts/ralph/validate-config.sh` | Config validation (unchanged logic) | **COPIED** |
| `scripts/ralph/ralph-hook.sh` | PreToolUse hook (unchanged logic) | **COPIED** |
| `scripts/ralph/ralph-stop` | Graceful stop (unchanged logic) | **COPIED** |
| `.claude/skills/.../SKILL.md` | Autopilot behavior rules | **COPIED** |
| `.claude/commands/gsd/ralph.md` | `/gsd:ralph` command entry point | **MODIFIED** (script path) |

## Data Flow: Install

```
User runs:
  curl -fsSL https://.../install-ralph.sh | bash
      │
      ▼
  [1] Check prerequisites (bash, jq, git, claude, GSD)
      │
      ▼
  [2] Detect project root (git rev-parse --show-toplevel)
      │
      ▼
  [3] Download release tarball to temp dir
      │
      ▼
  [4] Create target directories:
      scripts/ralph/
      .claude/skills/gsd-ralph-autopilot/
      .claude/commands/gsd/
      │
      ▼
  [5] Copy files from tarball to target locations
      Set executable permissions on scripts
      │
      ▼
  [6] Merge ralph config into .planning/config.json
      (add ralph section if missing, skip if present)
      │
      ▼
  [7] Post-install validation:
      - All files exist and are executable
      - config.json has ralph section
      - SKILL.md is in place
      │
      ▼
  [8] Print success + next steps:
      - How to run: /gsd:ralph execute-phase N
      - Permission guidance
      - How to uninstall
```

## Data Flow: Runtime (unchanged from v2.0)

```
User: /gsd:ralph execute-phase 3
      │
      ▼
  Claude Code reads .claude/commands/gsd/ralph.md
      │
      ▼
  bash scripts/ralph/ralph-launcher.sh execute-phase 3
      │
      ├──▶ source scripts/ralph/validate-config.sh
      ├──▶ read .planning/config.json (ralph section)
      ├──▶ _install_hook() → merge into .claude/settings.local.json
      ├──▶ bash scripts/ralph/assemble-context.sh → temp file
      ├──▶ build_claude_command() → claude -p "..." flags
      ├──▶ loop: execute iterations until phase complete
      └──▶ _cleanup() → _remove_hook(), audit summary
```

## Architectural Patterns

### Pattern 1: Namespaced Installation Directory

**What:** All Ralph scripts install to `scripts/ralph/` in the target repo, not directly to `scripts/`.
**When:** Always -- this is the installed layout.
**Trade-offs:**
- Pro: No collision with user's existing `scripts/` files
- Pro: Easy to identify Ralph files for uninstall
- Pro: Simple glob for permission rules: `Bash(bash scripts/ralph/*:*)`
- Con: Existing gsd-ralph dev repo uses `scripts/` directly -- requires path indirection

### Pattern 2: Runtime Hook Injection (existing, preserved)

**What:** The launcher installs the PreToolUse hook into `settings.local.json` at start and removes it at exit (via trap).
**When:** Every Ralph execution.
**Trade-offs:**
- Pro: Hook only active during Ralph runs -- no interference with normal usage
- Pro: Clean uninstall -- trap guarantees removal even on error
- Con: If the process is killed with SIGKILL, the hook persists until next run
- This pattern is carried over from v2.0. The installer does NOT change this behavior.

### Pattern 3: Config Section Merge (additive only)

**What:** The installer adds a `ralph` section to `.planning/config.json` only if one doesn't exist.
**When:** During installation.
**Trade-offs:**
- Pro: Never overwrites user's existing Ralph config
- Pro: Idempotent -- safe to run multiple times
- Con: If defaults change between versions, existing installs keep old defaults

### Pattern 4: Self-Referencing Path Variable

**What:** Scripts use `RALPH_SCRIPTS_DIR` to locate sibling scripts instead of hardcoded paths.
**When:** In all ralph scripts that reference other ralph scripts.
**Trade-offs:**
- Pro: Works in both dev repo (`scripts/`) and installed location (`scripts/ralph/`)
- Pro: Users could install to a custom location by setting the env var
- Con: One more variable to understand

## Anti-Patterns

### Anti-Pattern 1: Modifying settings.local.json at Install Time

**What people do:** Pre-configure hooks and permissions in settings.local.json during installation.
**Why it's wrong:** `settings.local.json` is user-specific and gitignored. The launcher already handles hook injection at runtime. Installing persistent hooks means they're active even when Ralph isn't running, which could interfere with normal Claude Code usage (e.g., denying AskUserQuestion when the user is actually present).
**Do this instead:** Let the launcher manage hooks dynamically. Print permission guidance for users to add voluntarily.

### Anti-Pattern 2: Installing as a Claude Code Plugin

**What people do:** Package gsd-ralph as a plugin for easy `/plugin install`.
**Why it's wrong:** Plugin skills are namespaced (`/gsd-ralph:ralph` instead of `/gsd:ralph`), breaking the GSD integration. Plugin files are cached copies that can't reference project-root paths. The dynamic hook install/uninstall pattern doesn't fit plugin hooks, which are static.
**Do this instead:** Use a standalone installer that places files directly in the project tree.

### Anti-Pattern 3: Git Submodule for Distribution

**What people do:** Add gsd-ralph as a git submodule for easy updates.
**Why it's wrong:** Submodule paths don't match where Claude Code discovers files. A submodule at `vendor/gsd-ralph/.claude/skills/` is NOT discoverable -- skills must be at `.claude/skills/` in the project root. You'd need symlinks, which add fragility.
**Do this instead:** Copy files to their canonical locations during install. Use `--force` for updates.

### Anti-Pattern 4: Sed-Replacing Paths at Install Time

**What people do:** Copy scripts verbatim, then use `sed` to replace hardcoded paths.
**Why it's wrong:** Fragile. If the path string appears in comments, log messages, or error strings, sed breaks them. If the format changes, the sed pattern breaks silently.
**Do this instead:** Use an environment variable (`RALPH_SCRIPTS_DIR`) that scripts read at runtime. No string replacement needed.

## Integration Points

### Claude Code Discovery

| Component | Discovery Mechanism | Location Requirement | Notes |
|-----------|---------------------|---------------------|-------|
| Skills | Automatic from `.claude/skills/<name>/SKILL.md` | Must be at project root `.claude/skills/` | Claude loads description into context; full content on invocation |
| Commands | Automatic from `.claude/commands/<path>.md` | Must be at project root `.claude/commands/` | File at `gsd/ralph.md` becomes `/gsd:ralph` |
| Hooks | Configured in settings JSON files | Referenced by absolute or relative path in settings | Launcher handles dynamically -- NOT installed statically |

**Confidence:** HIGH -- verified against official Claude Code docs (code.claude.com/docs/en/skills, code.claude.com/docs/en/hooks).

### GSD Integration

| Integration Point | How It Works | What Installer Does |
|-------------------|-------------|-------------------|
| `.planning/config.json` | Ralph reads `ralph` section for settings | Adds section if missing |
| `.planning/STATE.md` | Launcher reads to detect progress | Nothing -- exists from GSD |
| `.planning/phases/` | Context assembly reads plan files | Nothing -- exists from GSD |
| GSD commands | User invokes `/gsd:execute-phase N --ralph` | Installs the command file that handles `--ralph` |

### Existing File Boundaries

| File | Owned By | Installer Touches? |
|------|----------|-------------------|
| `.claude/settings.json` | Project team | NO -- print guidance only |
| `.claude/settings.local.json` | Individual user | NO -- launcher handles at runtime |
| `.planning/config.json` | GSD + ralph | YES -- adds ralph section |
| `.planning/STATE.md` | GSD | NO |
| `.planning/ROADMAP.md` | GSD | NO |
| `.gitignore` | Project | MAYBE -- add `.ralph/` if not present |

## Build Order (Suggested Phase Structure)

### Phase 1: Make scripts location-independent

**Prerequisite for everything else.** Modify existing scripts to use `RALPH_SCRIPTS_DIR` instead of hardcoded paths. This is a refactor of existing code, not new functionality. Must pass all existing tests.

**Components modified:**
- `scripts/ralph-launcher.sh` (path references)
- `scripts/assemble-context.sh` (if it references siblings)
- `.claude/commands/gsd/ralph.md` (script path)

**Tests:** All 315 existing tests must still pass. Add tests for `RALPH_SCRIPTS_DIR` override.

### Phase 2: Core installer script

Write `install-ralph.sh` with:
- Prerequisite detection
- Tarball download and extraction
- File copy to target locations
- Config merge
- Post-install validation
- `--uninstall` support
- Idempotency (skip existing, `--force` to overwrite)

**Dependencies:** Phase 1 (scripts must be location-independent before they can be installed elsewhere)

### Phase 3: Testing and polish

- Test install into a fresh GSD project
- Test install into a project with existing `.claude/` configuration
- Test uninstall
- Test idempotent re-install
- Test `--force` upgrade
- End-to-end: install then run `/gsd:ralph execute-phase N --dry-run`

**Dependencies:** Phase 2

## Sources

- [Claude Code Skills Documentation](https://code.claude.com/docs/en/skills) -- skill discovery, frontmatter, locations
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) -- hook configuration, settings file locations, PreToolUse format
- [Claude Code Plugins](https://code.claude.com/docs/en/plugins) -- plugin structure, why it doesn't fit
- [Claude Code Plugin Discovery](https://code.claude.com/docs/en/discover-plugins) -- marketplace installation, scoping
- [GSD Installation (npm)](https://github.com/gsd-build/get-shit-done) -- npx installer pattern reference
- Existing gsd-ralph codebase -- `ralph-launcher.sh` `_install_hook`/`_remove_hook` patterns, `ARCHITECTURE.md`

---
*Architecture research for: gsd-ralph v2.1 Easy Install*
*Researched: 2026-03-10*
