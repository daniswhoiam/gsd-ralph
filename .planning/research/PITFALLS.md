# Pitfalls Research

**Domain:** Adding one-command installer to existing Bash CLI tool that copies files into other repos
**Researched:** 2026-03-10
**Confidence:** HIGH (grounded in existing gsd-ralph codebase analysis, Claude Code official documentation for settings/hooks merge behavior, Bash 3.2 macOS compatibility research, real-world oh-my-bash/npm installer post-mortems, and Claude Code plugin system documentation)

## Critical Pitfalls

### Pitfall 1: Destroying User's Existing settings.local.json Content

**What goes wrong:**
The installer overwrites `.claude/settings.local.json` with Ralph's required configuration (PreToolUse hook, permissions), destroying the user's existing permissions, hooks, env vars, or MCP server configurations. Since `settings.local.json` is gitignored and unique to each developer, there is no backup -- the user loses their custom tool allowances, project-specific environment variables, and any other hooks they have configured.

The existing codebase already has a proven merge/unmerge pattern in `ralph-launcher.sh` (lines 342-383) using jq's `*` merge operator. But the installer context is different from the launcher context: the launcher installs/removes a single hook at runtime with trap-based cleanup, while the installer must merge multiple configuration sections (hooks, permissions, possibly env) at install time and provide a clean uninstall that reverses only Ralph's additions.

**Why it happens:**
The simplest installer implementation is `cp settings.local.json $TARGET/.claude/settings.local.json`. Developers test on fresh repos where the file does not exist, so the overwrite path is never exercised. Even developers who know about jq merge may use `jq -s '.[0] * .[1]'` which does deep merge for objects but REPLACES arrays rather than concatenating them -- destroying existing permissions entries.

Claude Code's own merge behavior is array concatenation with deduplication (confirmed in official docs: "Arrays concatenate and deduplicate across scopes"). An installer that replaces instead of concatenates violates user expectations set by Claude Code's own behavior.

**How to avoid:**
1. Use jq to read existing settings, then merge Ralph's additions per-key:
   - `permissions.allow`: Concatenate arrays, deduplicate (match Claude Code's own merge behavior)
   - `hooks.PreToolUse`: Append Ralph's hook entry to existing array, do not replace
   - `env`: Merge objects (Ralph's keys override only if they conflict, which they should not)
2. Create a backup before modifying: `cp settings.local.json settings.local.json.pre-ralph`
3. Record exactly what Ralph added in a manifest file (`.claude/ralph-manifest.json`) so the uninstaller knows what to remove
4. Test the installer against settings.local.json files with: empty object, existing permissions only, existing hooks only, existing permissions AND hooks AND env, and malformed JSON
5. Port the existing `_install_hook` / `_remove_hook` pattern from `ralph-launcher.sh` but expand it to handle all sections (not just hooks)

**Warning signs:**
- Installer uses `cp` or `>` redirection to write settings.local.json
- Installer tests only run against empty/nonexistent target directories
- No backup file created before settings modification
- jq merge uses `*` (object merge, replaces arrays) instead of per-key array concatenation
- No manifest tracking what was added by Ralph

**Phase to address:**
Core install/uninstall phase (first implementation). This is the highest-risk pitfall because data loss is immediate and irreversible for gitignored files. Must be designed and tested before any other installer work.

---

### Pitfall 2: Hardcoded Absolute Paths in Installed Files

**What goes wrong:**
Ralph's installed files contain absolute paths specific to the source installation (e.g., `/Users/daniswhoiam/Projects/gsd-ralph/scripts/ralph-hook.sh`) that break when installed into a different repo at a different location. The existing `settings.local.json` in gsd-ralph's own repo already shows this pattern -- it has entries like `Bash(GSD_RALPH_HOME=/Users/daniswhoiam/Projects/gsd-ralph PATH="..." gsd-ralph merge:*)` which are machine-specific.

The existing `_install_hook()` function uses `"$PROJECT_ROOT/scripts/ralph-hook.sh"` as the hook command path. When this runs within gsd-ralph's own repo, PROJECT_ROOT resolves to the gsd-ralph source directory. But in an installed target repo, the scripts live in a different location. The hook command path must point to where the scripts were COPIED TO, not where they came FROM.

**Why it happens:**
During development, the source repo and the installed location are the same. Developers test `_install_hook` in the gsd-ralph repo itself, where `$PROJECT_ROOT` correctly resolves. The bug only appears when installing into a DIFFERENT repo. Additionally, Bash 3.2 on macOS lacks `realpath` (requires coreutils via Homebrew), so portable path resolution requires the `cd "$(dirname ...)" && pwd` pattern.

**How to avoid:**
1. All installed file paths must be relative to the TARGET repo root, never the source repo
2. Use `$(cd "$(dirname "$0")" && pwd)` for portable path resolution (works on Bash 3.2 without `realpath`)
3. Never use `readlink -f` (not available on macOS without GNU coreutils)
4. Template hook command paths at install time: read the target repo root via `git rev-parse --show-toplevel`, substitute into settings entries
5. Test the installer by installing into a DIFFERENT directory than the source repo and verifying all paths resolve correctly
6. For the ralph-hook.sh command path in settings.local.json: use the target repo's copy (`$TARGET_ROOT/scripts/ralph-hook.sh`), not the source path

**Warning signs:**
- Installed settings.local.json contains paths from the developer's machine
- Hook commands fail with "No such file or directory" in target repos
- Tests only run the installer against the source repo itself
- Code uses `realpath` or `readlink -f` without a fallback
- Paths contain the gsd-ralph source directory rather than the target directory

**Phase to address:**
Core install phase. Path resolution must be correct from the first implementation. Regression tests should install into a temp directory and verify all paths point to the target, not the source.

---

### Pitfall 3: No Uninstall or Broken Uninstall Leaves Orphaned Config

**What goes wrong:**
The installer copies files and merges settings, but there is no uninstaller (or the uninstaller is incomplete). Users who want to remove Ralph must manually: (1) delete copied scripts from `scripts/`, (2) delete the SKILL.md from `.claude/skills/`, (3) delete the slash command from `.claude/commands/`, (4) manually edit `settings.local.json` to remove Ralph's hooks and permissions entries, (5) delete `.ralph/` directory, (6) remove `.ralphrc`. Missing any of these leaves orphaned configuration that can cause confusing behavior -- e.g., a PreToolUse hook pointing to a deleted script causes every Claude Code session to error.

The existing `_remove_hook()` in ralph-launcher.sh is a model for clean removal: it removes only the ralph-specific hook entry, cleans up empty containers, and preserves everything else. But the installer scope is much broader than a single hook.

**Why it happens:**
Installers are exciting to build. Uninstallers are boring and easy to forget. The "just delete the files" approach seems adequate until users discover that `settings.local.json` still references deleted scripts. The uninstall problem is also harder because the uninstaller must know exactly what the installer added -- which varies based on what existed before installation.

**How to avoid:**
1. Write the uninstaller BEFORE the installer. This forces you to define the manifest of what gets installed
2. Create a manifest file during installation (`.claude/ralph-manifest.json` or `.ralph/install-manifest.json`) that records every file copied and every settings.local.json entry added
3. The uninstaller reads the manifest and reverses each operation:
   - Delete files listed in manifest
   - Remove permissions entries that were added (by value match, not index)
   - Remove hook entries (using the existing `_remove_hook` pattern of matching on `ralph-hook` in the command string)
   - Clean up empty containers (empty hooks object, etc.)
4. Test the full cycle: install, verify working, uninstall, verify clean. The target repo should be identical to pre-install state (except the backup file)
5. Ship the uninstaller as `gsd-ralph uninstall` command in the target repo, not just as a script in the source repo

**Warning signs:**
- No `uninstall` command exists
- Uninstaller deletes files but does not clean settings.local.json
- No manifest tracking what was installed
- After uninstall, `jq '.hooks' .claude/settings.local.json` still shows ralph entries
- Claude Code sessions error with "hook script not found" after uninstall

**Phase to address:**
Same phase as install -- install and uninstall must be designed together. The manifest format should be defined first, then install writes to it and uninstall reads from it.

---

### Pitfall 4: Version Drift Between Source Repo and Installed Copies

**What goes wrong:**
User installs gsd-ralph v2.1.0 into their project. Two weeks later, gsd-ralph v2.1.1 fixes a bug in `ralph-hook.sh`. The user's project still has the v2.1.0 copy of the hook script. There is no mechanism to detect the mismatch, notify the user, or update the installed files. Over time, installed copies diverge from the source, accumulating bugs that were already fixed upstream.

This is especially dangerous for the PreToolUse hook (`ralph-hook.sh`) and SKILL.md, because bugs in these files can cause Ralph to ask questions (breaking autopilot) or skip important safety rules.

**Why it happens:**
Copy-based installation creates independent copies that are not linked to the source. Unlike symlinks or package managers that can track versions, copied files have no inherent version tracking. The installer "works" at install time, so there is no obvious moment to check for updates.

**How to avoid:**
1. Embed a version marker in every installed file (e.g., a comment `# gsd-ralph v2.1.0` at the top of each script, or a `ralph-version` field in settings entries)
2. Record the installed version in the manifest file
3. Provide an `upgrade` command that: reads the manifest to find installed version, compares with current source version, shows a diff of what changed, and asks before overwriting
4. At runtime (when `--ralph` is invoked), compare the installed version marker against the source version and warn if mismatched
5. Consider whether symlinks to the source repo would work instead of copies (tradeoff: simpler updates but creates a dependency on the source repo existing at that path)
6. If using copies: the `upgrade` command should be a first-class feature, not an afterthought

**Warning signs:**
- No version marker in installed files
- No `upgrade` or `update` command
- Users report bugs that were already fixed in a newer source version
- No way to check what version is installed in a target repo
- The installer always overwrites without checking if the target has a newer version

**Phase to address:**
Version management phase (should be part of the install/uninstall design but may be a separate plan). The version marker format must be decided during install design so it is present from the first installation.

---

### Pitfall 5: Installer Assumes Specific Repo Structure That Does Not Exist

**What goes wrong:**
The installer assumes the target repo has `.claude/` directory, or has `.planning/` directory, or has a specific git branching setup. When these assumptions fail, the installer either errors cryptically or silently creates a broken installation. For example: (1) repo has no `.claude/` directory at all (never used Claude Code project settings), (2) repo has `.claude/settings.json` but no `settings.local.json`, (3) repo has `.claude/skills/` with existing skills that conflict with Ralph's skill name, (4) repo has no `.planning/` directory (GSD not initialized), (5) repo is not a git repository at all.

**Why it happens:**
The installer is developed against the gsd-ralph repo itself, which has all these directories. Developers do not test against bare repos, non-GSD repos, or repos with unusual Claude Code configurations. The "happy path" works perfectly; edge cases are discovered by users.

**How to avoid:**
1. Check prerequisites explicitly at the start of installation:
   - Is this a git repository? (`git rev-parse --show-toplevel`)
   - Is GSD installed? (check `~/.claude/get-shit-done/VERSION`)
   - Is GSD initialized in this repo? (check `.planning/` exists, or run `gsd-tools.cjs config-get` and check exit code)
   - Does `.claude/` exist? (create it if not -- this is safe)
2. Create directories as needed (`mkdir -p`) rather than assuming they exist
3. Handle skill name conflicts: check if `.claude/skills/gsd-ralph-autopilot/` already exists before copying. If it does, compare versions and prompt user
4. Provide clear error messages for each prerequisite failure with actionable remediation:
   - "GSD not found. Install GSD first: [instructions]"
   - "GSD not initialized in this repo. Run /gsd:new-project first."
   - Not a git repo: "This directory is not a git repository. gsd-ralph requires git."
5. Test against: empty git repo, GSD-initialized repo, repo with existing Claude Code settings, repo with conflicting skill names

**Warning signs:**
- Installer uses `cp` without `mkdir -p` for parent directories
- No prerequisite checks before starting installation
- Error messages are raw shell errors ("No such file or directory") instead of helpful guidance
- Installer was only tested against repos with GSD already initialized
- No handling for existing files at target paths

**Phase to address:**
Prerequisite detection phase (should be the FIRST thing the installer does, before any file operations). This maps naturally to "GSD prerequisite detection with helpful version guidance" from PROJECT.md requirements.

---

### Pitfall 6: jq Dependency Not Detected or Wrong Version

**What goes wrong:**
The installer (and all of gsd-ralph's runtime scripts) depends on `jq` for JSON manipulation. If jq is not installed, the installer fails with a cryptic "command not found" error. If an old version of jq is installed (pre-1.5), certain jq features used in the codebase may not be available. On macOS, jq is NOT pre-installed -- it requires Homebrew (`brew install jq`) or a manual binary download.

The existing `validate-config.sh` and `ralph-launcher.sh` both use jq extensively. The `_install_hook()` function that merges settings.local.json is entirely jq-based. If jq is missing, the entire tool is non-functional.

**Why it happens:**
Developers who use gsd-ralph already have jq installed (it is a common developer tool). The missing-jq scenario only occurs for new users who are installing gsd-ralph for the first time -- exactly the users the v2.1 Easy Install milestone targets. The installer developer's machine has jq, so the dependency is invisible.

**How to avoid:**
1. Check for jq at the very start of the installer: `command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required..."; exit 1; }`
2. Check jq version: `jq --version` returns `jq-1.7.1` format; parse and verify >= 1.5
3. Provide actionable installation instructions in the error message:
   - macOS: `brew install jq` or direct binary download from jqlang.org
   - General: link to https://jqlang.org/download/
4. Consider whether the installer itself can avoid jq for the initial bootstrap (use grep/sed for simple JSON manipulation) and only require jq for runtime
5. Document jq as a prerequisite in the installer's help output and README

**Warning signs:**
- Installer does not check for jq before using it
- Error messages from missing jq are raw shell errors
- No version check for jq (old versions may lack features used)
- Installation instructions do not mention jq as a prerequisite

**Phase to address:**
Prerequisite detection phase. jq detection should be bundled with GSD detection as part of the initial prerequisite check.

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Copy files without a manifest | Simpler installer, fewer moving parts | No way to cleanly uninstall or upgrade; orphaned files accumulate | Never -- manifest should exist from day one |
| Overwrite settings.local.json instead of merging | Much simpler implementation (no jq merge logic) | Destroys user customizations; violates Claude Code's own merge-not-replace convention | Never -- the existing `_install_hook` pattern proves merge is feasible |
| Hardcode source repo path as install source | Works on developer's machine immediately | Breaks for any other user; cannot distribute the installer | During initial prototyping only; must be parameterized before shipping |
| Skip uninstaller for v2.1.0 | Ship faster, defer to v2.1.1 | Users who try and dislike Ralph cannot cleanly remove it; bad first impression | Only if the install manifest is still created (uninstaller can be added later if manifest exists) |
| Use symlinks instead of copies | Simpler versioning (always points to latest) | Breaks if source repo moves or is deleted; creates hard dependency on source location; cannot distribute to users without the source repo | Only for the developer's own repos; not for distributed installation |
| Check prerequisites with best-effort (warn but continue) | More forgiving installer | Broken installations that fail at runtime instead of install time; harder to debug | Never for critical prerequisites (GSD, jq, git); acceptable for optional features |

## Integration Gotchas

Common mistakes when connecting the installer to Claude Code, GSD, and the target repo.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Claude Code settings.local.json | Using jq `*` (deep merge) which replaces arrays | Use per-key concatenation: `.permissions.allow = (.permissions.allow // []) + [new_entries] \| unique` |
| Claude Code settings.local.json | Not gitignoring the file in target repo | Verify `.gitignore` includes `.claude/settings.local.json` (Claude Code convention); warn if not |
| Claude Code hooks | Registering hook with relative path | Use absolute path resolved at install time via `$(cd "$(dirname ...)" && pwd)` |
| Claude Code hooks merge | Assuming Claude Code concatenates hooks from settings.json and settings.local.json | This IS correct behavior per official docs -- but the installer must not DUPLICATE hooks by adding to settings.local.json what is already in settings.json |
| GSD prerequisite | Checking for GSD binary in PATH | GSD is a Claude Code extension, not a PATH binary. Check for `~/.claude/get-shit-done/VERSION` file existence |
| GSD initialization | Assuming .planning/ means GSD is initialized | Check for `.planning/config.json` specifically; `.planning/` alone might be leftover from a previous project |
| Target repo .gitignore | Not adding `.ralph/` and `.ralphrc` to .gitignore | These are local runtime files that should never be committed; installer should add to .gitignore if not present |
| Claude Code plugin system | Building a standalone installer when Claude Code has a native plugin system | Evaluate whether Ralph should be a Claude Code plugin (`plugin.json` + marketplace) rather than a copy-based installer. Plugins get automatic installation, namespacing, and settings merging for free |

## Performance Traps

Patterns that work in testing but fail in real-world usage.

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Installer copies ALL files from gsd-ralph repo (including tests, docs, planning) | Slow install, cluttered target repo, confusion about what files belong to Ralph vs the project | Maintain an explicit file manifest of what to copy; never use `cp -r` on the entire repo | Always -- this is a correctness issue, not just performance |
| Installer runs jq on large settings.local.json | Slow on repos with many permissions (100+ entries) | This is unlikely to be a problem in practice; jq handles large files well | Probably never -- but test with a realistic large settings file |
| Version check on every `--ralph` invocation | Adds latency to every command start | Cache version check result; only re-check if source repo mtime changed or once per day | Projects where `--ralph` is invoked frequently (rapid iteration) |

## Security Mistakes

Domain-specific security issues for a CLI installer that modifies other repos.

| Mistake | Risk | Prevention |
|---------|------|------------|
| Installer runs with elevated permissions unnecessarily | Could modify system files, other repos, or global config unintentionally | Never require sudo; all operations should be within target repo directory; verify target path is within a git repo before modifying |
| npx-based installer executes remote code | Supply chain attack via compromised npm package; user pipes unknown code to their shell | If using npx: pin exact version, verify package integrity; prefer local script-based installation over npx for a tool this small |
| curl-pipe-bash installer pattern | Man-in-the-middle attack; partial download executes incomplete script; no integrity verification | Avoid curl-pipe-bash entirely; use git clone + local script instead. If a remote install is needed, download script first, then execute separately |
| Installer modifies files outside target repo | Could corrupt user's global Claude Code settings (`~/.claude/settings.json`) or GSD installation | Validate that ALL file operations target the repo directory only; use `git rev-parse --show-toplevel` as the root boundary |
| Installed hook script is world-writable | Other users/processes on shared machines could modify the hook to inject malicious behavior | Set installed scripts to `chmod 755` (owner rwx, others rx); verify permissions after copy |
| settings.local.json backup contains sensitive env vars | Backup file might be committed to git if .gitignore is not configured | Place backup in `.ralph/` directory (which should be gitignored); or use `.claude/settings.local.json.pre-ralph` and verify it is gitignored |

## UX Pitfalls

Common user experience mistakes when building CLI installers.

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| Silent installation with no output | User does not know what was installed, where, or if it succeeded | Print each file copied and each settings entry added; end with a summary and "next steps" guidance |
| No dry-run mode | User cannot preview what the installer will do before committing | Implement `--dry-run` that prints all operations without executing them; existing codebase already has dry-run patterns in ralph-launcher.sh |
| Installer modifies files without asking | User loses trust when their config files change unexpectedly | Show what will be modified, ask for confirmation (unless `--yes` flag); create backups before modifying |
| Error messages reference installer internals | "jq: error (at .claude/settings.local.json:1): null is not an object" | Translate errors: "settings.local.json contains invalid JSON. Back up your file and re-run." |
| No verification after installation | User has to manually check if everything was installed correctly | Run a post-install verification: check all files exist, settings entries are present, hook script is executable, GSD is accessible |
| Upgrade destroys user's settings modifications made after install | User added extra permissions after install; upgrade overwrites them | Upgrade should only update Ralph's own entries (identified by manifest or markers), not re-merge the entire settings block |
| No guidance on what to do after install | User has Ralph installed but does not know how to use it | Print "Installation complete. Try: /gsd:ralph to execute a phase autonomously" |

## "Looks Done But Isn't" Checklist

Things that appear complete but are missing critical pieces.

- [ ] **Install copies files:** All scripts are in the target repo -- but are they executable? (`chmod +x` after copy)
- [ ] **Settings merge works:** Ralph's hooks and permissions are in settings.local.json -- but did it preserve the user's EXISTING entries? Test against non-empty settings files
- [ ] **Uninstall removes files:** Scripts are deleted -- but are settings.local.json entries also cleaned? And are empty containers (empty hooks object) removed?
- [ ] **Paths are correct:** Hook scripts are registered in settings.local.json -- but do the paths point to the TARGET repo, not the SOURCE repo? Install into a different directory and test
- [ ] **Prerequisite detection:** GSD check passes -- but does it verify the RIGHT GSD version? And does it detect jq, git, and bash version?
- [ ] **Version tracking:** Installer records version -- but can `upgrade` detect when installed version differs from source version? And does it handle downgrades (installing older over newer)?
- [ ] **gitignore entries:** `.ralph/` and `.ralphrc` are gitignored -- but is `settings.local.json` also gitignored? And the backup file?
- [ ] **Idempotent install:** Running install twice works -- but does it duplicate entries in settings.local.json? (Two copies of the same hook, two copies of the same permission)
- [ ] **Cross-machine install:** Works on developer's machine -- but does it work when the source repo is at a different path? When the target repo is on a different filesystem?

## Recovery Strategies

When pitfalls occur despite prevention, how to recover.

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| settings.local.json overwritten (Pitfall 1) | HIGH if no backup; LOW if backup exists | Restore from `.claude/settings.local.json.pre-ralph` backup; if no backup, user must recreate from memory or git stash |
| Hardcoded paths in installed files (Pitfall 2) | LOW | Re-run installer with correct path resolution; or manually edit settings.local.json to fix paths |
| Orphaned config after failed uninstall (Pitfall 3) | LOW-MEDIUM | Manually remove: ralph entries from settings.local.json, scripts/ copies, .claude/skills/gsd-ralph-autopilot/, .claude/commands/gsd/ralph.md, .ralph/, .ralphrc |
| Version drift causing bugs (Pitfall 4) | LOW | Re-run installer (upgrade mode) to copy latest files; or manually copy changed files from source |
| Install into wrong repo structure (Pitfall 5) | LOW | Uninstall, fix prerequisites, re-install |
| Missing jq causes install failure (Pitfall 6) | LOW | Install jq (`brew install jq`), re-run installer |

## Pitfall-to-Phase Mapping

How roadmap phases should address these pitfalls.

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| settings.local.json destruction (Pitfall 1) | Install/Uninstall core implementation | Test: install into repo with existing settings; verify all pre-existing entries preserved; verify backup created |
| Hardcoded absolute paths (Pitfall 2) | Install/Uninstall core implementation | Test: install into temp dir at different path than source; verify all paths in settings.local.json point to temp dir |
| No/broken uninstall (Pitfall 3) | Install/Uninstall core implementation (design together) | Test: install then uninstall; diff target repo against pre-install state; only `.ralph/install-manifest.json` and backup may remain |
| Version drift (Pitfall 4) | Version management / Upgrade support | Test: install v2.1.0, modify source to v2.1.1, run upgrade; verify changed files updated, unchanged files untouched |
| Assumed repo structure (Pitfall 5) | Prerequisite detection (first phase) | Test: run installer against empty git repo, non-git directory, repo without .planning/; verify clear error messages for each |
| Missing jq (Pitfall 6) | Prerequisite detection (first phase) | Test: run installer in environment without jq on PATH; verify helpful error message with install instructions |

## Claude Code Plugin System Consideration

**Important architectural decision that affects all pitfalls above:**

Claude Code now has a native plugin system (`.claude-plugin/plugin.json` manifest, marketplace distribution, automatic hook/settings merging). If gsd-ralph is packaged as a Claude Code plugin rather than a copy-based installer, many of these pitfalls become non-issues:

| Pitfall | Plugin System Mitigation |
|---------|-------------------------|
| settings.local.json destruction | Plugins have their own `hooks/hooks.json` and `settings.json`; Claude Code merges them automatically |
| Hardcoded paths | Plugin paths are resolved by Claude Code's plugin loader relative to the plugin directory |
| Uninstall | `/plugin uninstall` handles cleanup automatically |
| Version drift | Marketplace-based plugins can be updated via `/plugin update` |
| Repo structure assumptions | Plugin installation is managed by Claude Code, not by custom scripts |

**However**, the plugin system has tradeoffs:
- Skill names are namespaced (`/gsd-ralph:execute-phase` not `/gsd:ralph`)
- Plugin hooks use `hooks/hooks.json` format, not settings.local.json entries
- Requires Claude Code 1.0.33+
- Plugin distribution requires a marketplace (own GitHub repo or Anthropic's official marketplace)
- The `--ralph` flag integration with GSD commands may not fit the plugin model cleanly

**Recommendation:** Evaluate the plugin system as a FIRST step in the v2.1 roadmap. If it fits, use it. If not, build the copy-based installer with the pitfall mitigations above. The plugin system research should happen before any installer code is written.

## Sources

- [Claude Code settings merge behavior (official docs)](https://code.claude.com/docs/en/settings) -- Confirmed arrays concatenate and deduplicate across scopes; priority order; env object merge behavior. HIGH confidence
- [Claude Code hooks reference (official docs)](https://code.claude.com/docs/en/hooks) -- PreToolUse hook JSON schema; settings.json hook configuration format; matcher patterns. HIGH confidence
- [Claude Code plugin system (official docs)](https://code.claude.com/docs/en/plugins) -- Plugin manifest structure; hooks/hooks.json format; settings.json for plugins; marketplace distribution. HIGH confidence
- [oh-my-bash .bashrc overwrite issue #115](https://github.com/ohmybash/oh-my-bash/issues/115) -- Real-world example of installer destroying user's existing shell config. MEDIUM confidence
- [oh-my-bash backup overwrite issue #267](https://github.com/ohmybash/oh-my-bash/issues/267) -- Backup file itself getting overwritten on reinstall. MEDIUM confidence
- [macOS realpath unavailability](https://github.com/facebook/react-native/issues/34146) -- `realpath` not available on macOS by default; `cd "$(dirname ...)" && pwd` pattern required for Bash 3.2 compatibility. HIGH confidence
- [jq official site](https://jqlang.org/) -- jq has zero runtime dependencies; pre-built macOS ARM64 binaries available since v1.7. HIGH confidence
- [npm supply chain attacks 2025-2026](https://snyk.io/articles/npm-security-best-practices-shai-hulud-attack/) -- 454K malicious packages in 2025; rationale for avoiding npx-based installers for small tools. MEDIUM confidence
- [curl-pipe-bash security analysis](https://www.kicksecure.com/wiki/Dev/curl_bash_pipe) -- Risks of piping remote scripts to bash; partial download vulnerability. MEDIUM confidence
- [Project permissions merging issue #17017](https://github.com/anthropics/claude-code/issues/17017) -- Reported bug where project-level permissions replace global permissions instead of merging. MEDIUM confidence (may be fixed)
- gsd-ralph `ralph-launcher.sh` lines 342-383 -- Existing `_install_hook()` and `_remove_hook()` implementation proving jq-based merge/unmerge pattern. HIGH confidence
- gsd-ralph `tests/ralph-launcher.bats` lines 834-904 -- Existing test coverage for hook install/remove lifecycle including preservation of existing settings. HIGH confidence
- gsd-ralph `PROJECT.md` -- v2.1 requirements, architectural constraints, existing decisions about settings.local.json merge/unmerge. HIGH confidence

---
*Pitfalls research for: Adding one-command installer to existing Bash CLI tool that copies files into other repos*
*Researched: 2026-03-10*
