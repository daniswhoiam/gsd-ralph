# Feature Research: v2.1 Easy Install

**Domain:** Single-command installer for Claude Code CLI extension (gsd-ralph)
**Researched:** 2026-03-10
**Confidence:** HIGH

## Context

This research covers the feature landscape for gsd-ralph v2.1 -- making the existing gsd-ralph autopilot tool installable in any GSD project with a single command. v2.0 (shipped, 830 LOC Bash + 1,593 LOC tests) provides the core autopilot functionality (`--ralph` flag, loop engine, circuit breaker, permission tiers, worktree isolation). v2.1 focuses exclusively on the installation/distribution problem: getting all those components into a target repo reliably.

**Key ecosystem facts informing this research:**
- Claude Code plugin system (v1.0.33+) provides native install/uninstall via `/plugin install name@marketplace` with skills, hooks, commands, and settings bundled in a standardized directory structure
- GSD uses npx-based installation: `npx get-shit-done-cc --claude --global` copies commands, workflows, and templates to `~/.claude/`
- The ralph-loop-setup plugin (MarioGiancini) and flow-next plugin (gmickel) both use the Claude Code plugin marketplace for distribution, with `/plugin install` handling file placement
- gsd-ralph already has a proven pattern for non-destructive `settings.local.json` merge/unmerge via jq (in `ralph-launcher.sh` `_install_hook()` / `_remove_hook()`)
- gsd-ralph must install ~40 files across 5 directories: `scripts/`, `lib/`, `bin/`, `templates/`, `.claude/skills/`

---

## Feature Landscape

### Table Stakes (Users Expect These)

Features users assume exist. Missing any of these = the installer feels broken or untrustworthy.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Single-command install** | Every modern CLI tool installs in one command (GSD: `npx get-shit-done-cc`, Homebrew: `brew install`, Claude Code: `curl ... \| bash`). Multi-step manual setup is a non-starter. | MEDIUM | Primary approach: bash script (`./install.sh` or `bash <(curl -sL ...)`) that copies files from the gsd-ralph repo to the target project. Long-term: Claude Code plugin distribution. The bash script approach is simpler for v2.1 and does not require npm packaging. |
| **Prerequisite detection** | If Claude Code, GSD, jq, or git is missing, the installer must detect and report clearly with fix instructions. Every mature installer does this (rustup checks for cc, Homebrew checks for Xcode tools). Cryptic failures erode trust. | LOW | Check for: `claude` binary in PATH, GSD commands directory (`~/.claude/commands/gsd/` or `.claude/commands/gsd/`), `jq` binary, `git` binary, bash version >= 3.2. For each missing prerequisite, print the exact install command. Exit early on hard requirements. |
| **Idempotent re-runs** | Users re-run installers when unsure if the first run succeeded. Running twice must not break anything. Homebrew install issue #559 documents real user frustration when re-running creates errors. | MEDIUM | For each file: check if target exists and matches source (checksum or content comparison). If identical, skip with "already up to date" message. If different (user modified), warn but do not overwrite user-owned files. Use `mkdir -p` for directories. For settings.local.json, jq-merge is inherently idempotent (adding an already-present array element is a no-op with dedup). |
| **Non-destructive settings merge** | Users may already have `.claude/settings.local.json` with custom permissions, hooks, and tool allowlists. Overwriting loses their config. Claude Code's own settings system merges arrays from multiple scopes. | MEDIUM | Existing proven pattern: `_install_hook()` in ralph-launcher.sh uses jq to merge PreToolUse hook config into existing settings. Generalize this to also merge permission entries (`permissions.allow` array). On uninstall, reverse: remove only ralph-specific entries via `_remove_hook()` pattern. |
| **Post-install verification** | User needs proof the install worked. "Installation complete" alone is insufficient. GSD prints "Run `/gsd:help` to verify." Other tools run a version command. | LOW | After file copy: verify key files exist (`scripts/ralph-launcher.sh`, `bin/gsd-ralph`, `.claude/skills/gsd-ralph-autopilot/SKILL.md`), run `bin/gsd-ralph --version` to confirm executable, validate `.ralphrc` syntax with `scripts/validate-config.sh`. Print summary with next-step guidance. |
| **Clear success/failure output** | Colored output showing each step's status, with a summary at the end. Standard in npx create-react-app, GSD installer, Homebrew. Silent installers that succeed without feedback leave users uncertain. | LOW | Use ANSI color codes (green checkmarks for success, red X for failure, yellow for warnings). Print each file copied. Print total summary: "Installed N files. Run `gsd-ralph --version` to verify." Reuse existing `print_success`/`print_error` from `lib/common.sh` if sourcing is possible, or inline simple ANSI helpers. |
| **Uninstall command** | Symmetry with install. If you can add in one command, users expect to remove in one command. Prevents "how do I clean this up?" support burden. | LOW | Remove all files the installer created. Unmerge ralph-specific entries from settings.local.json (existing `_remove_hook()` pattern). Do NOT remove `.ralphrc` if user has customized it -- warn instead. Write a `.ralph/.installed-files` manifest during install to know exactly what to remove. |

### Differentiators (Competitive Advantage)

Features that go beyond basic installation and distinguish gsd-ralph's installer from alternatives.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **Claude Code plugin packaging** | The ecosystem-native distribution path. `/plugin install gsd-ralph@marketplace` gives users the familiar Claude Code UX: install, uninstall, enable/disable, auto-update, namespaced skills. Other Ralph tools (ralph-loop-setup, flow-next) already use this pattern. | MEDIUM | Requires: `.claude-plugin/plugin.json` manifest, restructuring files to match plugin directory layout (skills/, hooks/, commands/ at plugin root), hosting as GitHub repo with `marketplace.json`. Plugin system handles file placement, scope selection (user/project/local), and lifecycle. This wraps the same install logic. |
| **Upgrade-in-place** | `install.sh --upgrade` updates scripts, templates, and SKILL.md without touching user configuration (`.ralphrc`, custom hooks). GSD does "wipe and replace" for managed directories while preserving local modifications. Saves users from manual diffing on updates. | MEDIUM | Categorize files as "managed" (replaced on upgrade: scripts/, lib/, bin/, templates/, SKILL.md) vs "user-owned" (preserved: .ralphrc). On upgrade: replace all managed files, skip user-owned files, re-merge settings.local.json. Track installed version in `.ralph/.version` to detect upgrades. |
| **Dry-run mode** | `install.sh --dry-run` shows exactly what files would be installed and what config would be merged, without changing anything. Builds trust with cautious users. Matches existing `--dry-run` pattern in ralph-launcher. | LOW | Walk through all install steps, print what would happen (file paths, settings changes), skip actual writes. Easy to implement: wrap each write operation in an `if ! $DRY_RUN` guard. |
| **Version-pinned installation** | `install.sh --version 2.1.0` installs a specific tagged release. Important for teams needing consistent versions across repos. Plugin system supports version pinning natively. | LOW | For script-based install: download from GitHub tagged release. For plugin: version in plugin.json manifest. Tag each release on GitHub. |
| **GSD integration detection** | Auto-detect whether GSD is installed globally (`~/.claude/commands/gsd/`) vs locally (`.claude/commands/gsd/`), whether `.planning/` exists, and whether the project is a git repo. Adapt install behavior and messages accordingly. | LOW | Simple directory/file existence checks. If `.planning/` is missing, warn "This doesn't look like a GSD project. Run `/gsd:new-project` first." If no git repo, error "gsd-ralph requires a git repository." |
| **Install manifest for clean uninstall** | Write `.ralph/.installed-files` during install listing every file created/modified. Uninstall reads this manifest instead of hardcoding file paths. Handles version skew gracefully -- uninstall always removes exactly what was installed, even if the file list changed between versions. | LOW | Simple: write one filepath per line to manifest during install. On uninstall: read manifest, remove each file, remove empty directories. Append settings.local.json entries with markers for clean removal. |

### Anti-Features (Commonly Requested, Often Problematic)

Features that seem good but create problems for a CLI installer in this domain.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Interactive configuration wizard** | "Let me customize everything during install" | Adds complexity, slows install, creates untestable permutations across prompt choices. gsd-ralph's `.ralphrc` already has well-documented defaults that work for most projects. Interactive prompts also break non-interactive contexts (CI/CD, scripts). | Install with sensible defaults. Print "Edit `.ralphrc` to customize behavior." after install. User tweaks config after the fact. |
| **Auto-install prerequisites** | "Just install GSD and Claude Code for me too" | gsd-ralph should not own the install lifecycle of upstream dependencies. Version conflicts, permission issues, and breaking changes in GSD or Claude Code are not gsd-ralph's responsibility. Upstream tools have their own tested installers. | Detect missing prerequisites, print exact install commands with URLs, exit with clear error. Let user run upstream installers themselves. |
| **Global system-wide installation** | "Install gsd-ralph once for all my projects" | gsd-ralph needs per-repo files: `.ralphrc` (project-specific config), `scripts/` (executed in project context), SKILL.md (loaded per-project). A global install would still need per-repo initialization, creating a confusing "installed but not working" state. | Per-repo installation is correct. For "available everywhere" without per-repo files, the Claude Code plugin system (user-scope install) handles this -- but `.ralphrc` still needs per-repo init. |
| **Curl-pipe-bash installer** | "curl https://... \| bash" is the simplest possible install | Security concerns (MITM attacks, partial downloads, no integrity verification). Not the Claude Code ecosystem pattern. Requires hosting infrastructure. npm/plugin approaches provide safer distribution with caching and checksums. | Use bash install script that user downloads first (can inspect), or Claude Code plugin system (primary long-term), or npx package (secondary). |
| **GUI/web-based installer** | "Point and click to install" | Target users are terminal-native (PROJECT.md: "CLI only, target users are terminal-native"). GUI adds platform-specific complexity, runtime dependencies, and maintenance burden for zero value to the target audience. | CLI-only installation. The one-command pattern IS the UX for terminal-native users. |
| **Auto-update on every launch** | "Always run latest version automatically" | Breaks reproducibility. Updates during critical autonomous runs can introduce bugs mid-execution. Surprise behavior changes violate the principle of least astonishment. GSD's approach (wipe and replace on explicit `npx get-shit-done-cc`) is better. | Explicit `--upgrade` command. Plugin system's auto-update is opt-in and happens at Claude Code startup (not mid-run). Users control when updates happen. |
| **npm packaging for a Bash tool** | "Publish to npm so users can `npx gsd-ralph install`" | gsd-ralph is a Bash tool with zero Node.js dependencies. Publishing to npm adds a package.json, node_modules concern, npm registry dependency, and the conceptual mismatch of distributing Bash scripts via a JavaScript package manager. GSD does this because it needs cross-platform CLI argument parsing from npm packages. gsd-ralph does not. | Distribute via GitHub releases (bash script download) or Claude Code plugin system. Both are more natural for a Bash tool than npm. If npx is desired later, it can be a thin wrapper that downloads and runs the bash installer. |

---

## Feature Dependencies

```
[Prerequisite Detection]
    |
    v
[File Copy/Install Core]
    |
    +---> [Settings Merge (settings.local.json)]
    |         |
    |         +---> [Hook Registration (PreToolUse)]
    |         |
    |         +---> [Permission Entries (allow array)]
    |
    +---> [.ralphrc Generation (from template)]
    |
    +---> [SKILL.md Installation]
    |
    +---> [Install Manifest (.ralph/.installed-files)]
    |
    v
[Post-Install Verification]
    |
    v
[Success Output with Next Steps]

[Uninstall Command] --reads--> [Install Manifest]
                    --reverses--> [File Copy/Install Core]
                    --reverses--> [Settings Merge]

[Plugin Distribution] --wraps--> [File Copy/Install Core]
                      --wraps--> [Settings Merge]
                      --adds--> [plugin.json manifest]
                      --adds--> [marketplace.json entry]

[Upgrade-in-Place] --depends--> [File Copy/Install Core]
                   --reads--> [.ralph/.version]
                   --distinguishes--> [Managed vs User-owned files]

[Dry-Run Mode] --wraps--> [File Copy/Install Core]
               --wraps--> [Settings Merge]
               --independent (no runtime deps, can ship in any order)
```

### Dependency Notes

- **Prerequisite Detection must come first:** All subsequent steps assume GSD, Claude Code, jq, and git are present. Fail fast with clear messages before touching any files.
- **File Copy is the core operation:** Everything else (settings merge, verification, manifest) depends on files being in place. Settings merge specifically requires hook scripts to already exist at their target paths before settings.local.json can reference them.
- **Install Manifest enables clean uninstall:** Without tracking what was installed, uninstall must hardcode file paths -- fragile across versions. Write the manifest as part of the install process, not as a separate step.
- **Plugin Distribution wraps Install Core:** The plugin is a packaging/distribution format. The actual install logic (file copy, config merge) is the same whether run from a bash script or via `/plugin install`. Build the script first, wrap in plugin format later.
- **Upgrade-in-Place requires version tracking:** Must compare installed version vs available version to decide what to update. A `.ralph/.version` file serves this purpose.
- **Dry-Run is independent:** Can be implemented at any time by wrapping write operations in conditionals. No dependencies on other features.

---

## MVP Definition

### Launch With (v2.1)

Minimum viable installer -- what's needed so users can install gsd-ralph in one command.

- [ ] **Prerequisite detection** -- Check for claude, GSD commands, jq, git, bash >= 3.2. Print actionable fix instructions for each missing prerequisite. Exit early on hard failures.
- [ ] **File copy/install core** -- Copy scripts/, lib/, bin/, templates/, and SKILL.md to target repo. Use `mkdir -p` for directories. Handle file permissions (`chmod +x` for scripts and bin entries). Idempotent: overwrite managed files, skip identical files with "already up to date."
- [ ] **Non-destructive settings.local.json merge** -- Add ralph hook config and permission entries to existing settings without overwriting other content. Generalize existing `_install_hook()` jq-merge pattern to also handle `permissions.allow` array.
- [ ] **.ralphrc generation** -- Copy `templates/ralphrc.template` to `.ralphrc` if not present. If `.ralphrc` already exists, skip (user-owned). Print message about customization.
- [ ] **Install manifest** -- Write `.ralph/.installed-files` listing every file created/modified. Enables clean uninstall.
- [ ] **Post-install verification** -- Verify key files exist, run `bin/gsd-ralph --version`, validate .ralphrc syntax. Print success summary with next-step guidance.
- [ ] **Uninstall command** -- Read install manifest, remove all listed files, unmerge settings.local.json entries, clean up empty directories. Warn about user-modified files.
- [ ] **Clear output** -- Colored step-by-step output with final summary.

### Add After Validation (v2.1.x)

Features to add once the install script is proven and users are installing successfully.

- [ ] **Claude Code plugin packaging** -- Structure gsd-ralph as a Claude Code plugin with `.claude-plugin/plugin.json`, publish to a GitHub marketplace repo. Trigger: when install script is stable and the team wants broader distribution.
- [ ] **Upgrade-in-place** -- `--upgrade` flag replacing managed files while preserving user config. Requires `.ralph/.version` tracking. Trigger: when v2.1.1 or v2.2 ships and users need to update.
- [ ] **Dry-run mode** -- `--dry-run` flag showing what would be installed without modifying anything. Trigger: user feedback requesting preview capability.
- [ ] **Version pinning** -- `--version X.Y.Z` flag installing from specific GitHub tagged release. Trigger: team usage requiring version consistency.

### Future Consideration (v2.2+)

Features to defer until the distribution pattern is established.

- [ ] **Marketplace submission** -- Submit plugin to Anthropic's claude-plugins-official. Requires plugin stability, documentation, and community validation.
- [ ] **Auto-update via plugin system** -- Leverage marketplace auto-update for automatic version updates at Claude Code startup.
- [ ] **Multi-repo batch installer** -- Install gsd-ralph across multiple repos in one command. Adds orchestration complexity for marginal value.

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| Prerequisite detection | HIGH | LOW | P1 |
| File copy/install core | HIGH | MEDIUM | P1 |
| Settings.local.json merge | HIGH | MEDIUM | P1 |
| .ralphrc generation | HIGH | LOW | P1 |
| Install manifest | MEDIUM | LOW | P1 |
| Post-install verification | HIGH | LOW | P1 |
| Uninstall command | MEDIUM | LOW | P1 |
| Clear output | MEDIUM | LOW | P1 |
| Plugin packaging | HIGH | MEDIUM | P2 |
| Upgrade-in-place | MEDIUM | MEDIUM | P2 |
| Dry-run mode | LOW | LOW | P2 |
| Version pinning | LOW | LOW | P3 |
| Marketplace submission | MEDIUM | LOW | P3 |

**Priority key:**
- P1: Must have for v2.1 launch
- P2: Should have, add in v2.1.x
- P3: Nice to have, future consideration

---

## Competitor / Reference Installer Analysis

| Feature | GSD (npx installer) | ralph-loop-setup (plugin) | flow-next (plugin) | gsd-ralph v2.1 (planned) |
|---------|---------------------|---------------------------|--------------------|----|
| **Distribution** | npm package via npx | Claude Code plugin marketplace | Claude Code plugin marketplace | Bash install script (v2.1), plugin (v2.1.x) |
| **Install command** | `npx get-shit-done-cc --claude --local` | `/plugin install ralph-loop-setup` | `/plugin marketplace add gmickel/...` + `/flow-next:setup` | `./install.sh` or `bash <(curl -sL ...)` |
| **Non-interactive mode** | Yes (flags: `--claude --global`) | N/A (plugin install is non-interactive) | N/A | Yes (no prompts by default) |
| **Prerequisite check** | Implicit (npx handles Node) | Not documented | Not documented | Explicit: claude, GSD, jq, git, bash >= 3.2 |
| **Idempotency** | Yes (wipe and replace managed dirs) | Not documented | Not documented | Yes (check-before-write, skip identical) |
| **Uninstall** | Not documented | `/plugin uninstall` (native) | `/plugin uninstall` (native) | `./install.sh --uninstall` + manifest-based cleanup |
| **Settings merge** | Overwrites managed dirs only | Plugin system merges hooks | Plugin system merges hooks | jq-based non-destructive merge (proven pattern) |
| **Post-install verification** | User runs `/gsd:help` | User tests skill commands | User runs `/flow-next:setup` | Automated: file checks + version command + config validation |
| **Upgrade** | Re-run `npx get-shit-done-cc` | Plugin marketplace auto-update | Plugin marketplace auto-update | `--upgrade` flag (v2.1.x) |

### Key Insight from Analysis

The Claude Code plugin system is the RIGHT long-term distribution mechanism -- it provides install/uninstall/upgrade/enable/disable lifecycle management for free. However, gsd-ralph has unique requirements that make a pure plugin insufficient for v2.1:

1. **Per-repo `.ralphrc` configuration** -- Plugins install to user/project/local scope, but `.ralphrc` needs project-specific customization (PROJECT_NAME, ALLOWED_TOOLS). A plugin can install the template but cannot customize it per-project without a setup step.
2. **Bash scripts in `scripts/` and `lib/`** -- Plugin directory structure supports skills/, commands/, hooks/, and agents/. Arbitrary script directories are not standard plugin components. The scripts must be accessible at known paths for `ralph-launcher.sh` to source them.
3. **`bin/` executables in PATH** -- The `gsd-ralph` and `ralph-stop` binaries need to be in PATH or discoverable. Plugins don't handle PATH management.

The pragmatic v2.1 approach: build a bash install script first (handles all three issues natively), then wrap it as a plugin setup skill for v2.1.x (the plugin provides distribution and lifecycle; a setup command within the plugin handles per-repo initialization).

---

## What Files Need to Be Installed

Based on analysis of the existing gsd-ralph codebase (~40 files across 5 directories):

### Managed Files (replaced on upgrade, always overwritten)

| Source Path | Target Path | Purpose |
|-------------|-------------|---------|
| `scripts/ralph-launcher.sh` | `scripts/ralph-launcher.sh` | Core loop engine (592 LOC) |
| `scripts/assemble-context.sh` | `scripts/assemble-context.sh` | GSD context assembly |
| `scripts/validate-config.sh` | `scripts/validate-config.sh` | Config validation |
| `scripts/ralph-hook.sh` | `scripts/ralph-hook.sh` | PreToolUse hook for AskUserQuestion denial |
| `scripts/ralph-execute.sh` | `scripts/ralph-execute.sh` | Phase execution setup |
| `scripts/ralph-merge.sh` | `scripts/ralph-merge.sh` | Branch merge logic |
| `scripts/ralph-status.sh` | `scripts/ralph-status.sh` | Phase status display |
| `scripts/ralph-worktrees.sh` | `scripts/ralph-worktrees.sh` | Worktree isolation |
| `scripts/ralph-cleanup.sh` | `scripts/ralph-cleanup.sh` | Worktree/branch cleanup |
| `lib/common.sh` | `lib/common.sh` | Shared utilities |
| `lib/config.sh` | `lib/config.sh` | Configuration loading |
| `lib/discovery.sh` | `lib/discovery.sh` | Plan/phase discovery |
| `lib/frontmatter.sh` | `lib/frontmatter.sh` | YAML frontmatter parsing |
| `lib/prompt.sh` | `lib/prompt.sh` | Prompt generation |
| `lib/push.sh` | `lib/push.sh` | Git push utilities |
| `lib/safety.sh` | `lib/safety.sh` | Safe file operations |
| `lib/strategy.sh` | `lib/strategy.sh` | Execution strategy |
| `lib/templates.sh` | `lib/templates.sh` | Template expansion |
| `lib/commands/*.sh` | `lib/commands/*.sh` | Command implementations (6 files) |
| `lib/merge/*.sh` | `lib/merge/*.sh` | Merge utilities (6 files) |
| `lib/cleanup/registry.sh` | `lib/cleanup/registry.sh` | Cleanup registry |
| `bin/gsd-ralph` | `bin/gsd-ralph` | CLI entry point |
| `bin/ralph-stop` | `bin/ralph-stop` | Graceful stop command |
| `templates/*.template` | `templates/*.template` | Prompt/config templates (7 files) |
| `.claude/skills/gsd-ralph-autopilot/SKILL.md` | `.claude/skills/gsd-ralph-autopilot/SKILL.md` | Autonomous behavior rules |

### User-Owned Files (created if missing, never overwritten on upgrade)

| File | Purpose | Default Source |
|------|---------|----------------|
| `.ralphrc` | Project-level Ralph configuration | `templates/ralphrc.template` |

### Merged Files (non-destructively updated)

| File | What Gets Merged | Merge Strategy |
|------|------------------|----------------|
| `.claude/settings.local.json` | PreToolUse hook for ralph-hook.sh, permission allow entries for ralph scripts | jq-based array merge: add ralph-specific entries to existing arrays, do not replace. Existing `_install_hook()` / `_remove_hook()` patterns from ralph-launcher.sh. |

### Metadata Files (created by installer, managed by installer)

| File | Purpose |
|------|---------|
| `.ralph/.installed-files` | Manifest of all files installed (for clean uninstall) |
| `.ralph/.version` | Installed version (for upgrade detection) |

---

## Sources

- [Claude Code Plugin Documentation](https://code.claude.com/docs/en/plugins) -- Plugin structure, manifest format, installation mechanism, migration from standalone (HIGH confidence)
- [Claude Code Discover and Install Plugins](https://code.claude.com/docs/en/discover-plugins) -- Marketplace workflow, installation scopes, team configuration, auto-update (HIGH confidence)
- [GSD get-shit-done-cc npm package](https://www.npmjs.com/package/get-shit-done-cc) -- npx installer pattern, file structure, non-interactive flags (HIGH confidence)
- [GSD GitHub repository](https://github.com/gsd-build/get-shit-done) -- Installation flow, directory structure, wipe-and-replace strategy (MEDIUM confidence)
- [ralph-loop-setup plugin](https://github.com/MarioGiancini/ralph-loop-setup) -- Plugin-based Ralph installer, skill structure, files created (MEDIUM confidence)
- [gmickel-claude-marketplace flow-next](https://github.com/gmickel/gmickel-claude-marketplace) -- Plugin marketplace distribution, Ralph autonomous mode packaging (MEDIUM confidence)
- [Homebrew install idempotency issue #559](https://github.com/Homebrew/install/issues/559) -- User frustration with non-idempotent installers (HIGH confidence)
- [Idempotent Bash scripts by Fatih Arslan](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/) -- Guard clauses, state checks, mkdir -p patterns (HIGH confidence)
- [Shopify CLI error handling principles](https://shopify.github.io/cli/cli/error_handling.html) -- Error types (AbortError, BugError), user-facing error UX (MEDIUM confidence)
- [Claude Code settings merge behavior](https://www.eesel.ai/blog/settings-json-claude-code) -- Settings scopes, merge semantics, local vs project vs user (MEDIUM confidence)
- [anthropics/claude-plugins-official](https://github.com/anthropics/claude-plugins-official) -- Official marketplace structure and plugin listing format (HIGH confidence)

---
*Feature research for: gsd-ralph v2.1 Easy Install*
*Researched: 2026-03-10*
