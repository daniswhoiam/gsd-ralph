# Project Research Summary

**Project:** gsd-ralph v2.1 Easy Install
**Domain:** CLI tool distribution/installation for Claude Code extension
**Researched:** 2026-03-10
**Confidence:** HIGH

## Executive Summary

gsd-ralph v2.1 needs to solve one problem: getting ~40 Bash files from the gsd-ralph repo into any GSD project with a single command. The four research streams agree on the core installer mechanics -- prerequisite detection, idempotent file copy, non-destructive settings merge, install manifest for clean uninstall -- but disagree sharply on the distribution mechanism. The Stack researcher recommends the Claude Code plugin system as primary distribution. The Architecture researcher argues plugins break GSD integration due to command namespacing (`/gsd-ralph:ralph` instead of `/gsd:ralph`) and because plugin files live in a read-only cache rather than in the project tree where ralph-launcher.sh expects them. The Features researcher favors a bash install script as the v2.1 mechanism with plugins deferred to v2.1.x. The Pitfalls researcher recommends evaluating the plugin system first before committing to either approach.

**The recommendation: Build a bash installer script as the v2.1 distribution mechanism. Defer plugin packaging to v2.2+.** The namespacing conflict is the deciding factor. gsd-ralph's command MUST be `/gsd:ralph` to integrate with the GSD command namespace -- this is a hard requirement from the existing v2.0 architecture and user mental model. Claude Code plugins namespace their commands under the plugin name, producing `/gsd-ralph:ralph` instead. Additionally, the dynamic hook injection pattern (install hook at ralph start, remove at ralph exit via trap) does not fit the plugin model where hooks are static and always active. These are not theoretical concerns; they are architectural incompatibilities confirmed by both the Architecture and Pitfalls researchers against official Claude Code plugin documentation. The bash installer approach has zero new dependencies, works with the existing Bash 3.2 requirement, and follows patterns proven by the existing `_install_hook`/`_remove_hook` code.

The primary risks are: (1) destroying user's existing `settings.local.json` content during install, (2) hardcoded absolute paths that break when scripts are copied to a different repo, and (3) version drift between source and installed copies. All three have proven mitigation patterns from the existing codebase. The biggest implementation challenge is making the existing scripts location-independent (supporting both `scripts/` in the dev repo and `scripts/ralph/` in target repos) -- this refactor must happen before the installer can be built.

## Key Findings

### Recommended Stack

The v2.1 stack adds nothing to the existing v2.0 runtime. gsd-ralph remains pure Bash with jq for JSON manipulation. The installer itself is a self-contained Bash script that downloads a GitHub release tarball and copies files to the target project. No npm package, no Node.js dependency, no build step. See [STACK.md](./STACK.md) for full evaluation of three distribution approaches.

**Core technologies:**
- **Bash 3.2+**: Installer and runtime -- macOS system bash compatibility required
- **jq 1.5+**: JSON manipulation for config merge -- already a v2.0 runtime dependency
- **curl**: Release tarball download -- install-time only, universally available
- **GitHub Releases**: Distribution via tagged tarballs -- no registry, no marketplace, no npm

**What NOT to add:**
- npm/npx package (gsd-ralph has zero Node.js code; npm adds conceptual mismatch)
- Claude Code plugin system (namespacing conflict, static hooks incompatible with dynamic injection)
- Homebrew formula (overkill for a Claude Code-specific tool)
- curl-pipe-bash pattern (security concerns; download-then-execute is safer)

### Expected Features

See [FEATURES.md](./FEATURES.md) for full feature landscape, dependency graph, and competitor analysis.

**Must have (table stakes):**
- Single-command install (`bash install-ralph.sh` or download + local execute)
- Prerequisite detection (claude, GSD, jq, git, bash >= 3.2) with actionable fix instructions
- Idempotent re-runs (skip identical files, warn on user-modified files)
- Non-destructive config merge (jq-based addition of ralph section to `.planning/config.json`)
- Post-install verification (file existence, executable permissions, config validation)
- Install manifest (`.ralph/.installed-files`) for tracking what was installed
- Uninstall command (`install-ralph.sh --uninstall`) reading from manifest
- Clear colored output with next-step guidance

**Should have (differentiators):**
- Upgrade-in-place (`--upgrade` flag replacing managed files, preserving user config)
- Dry-run mode (`--dry-run` previewing all operations)
- GSD integration detection (warn if `.planning/` missing, error if not a git repo)
- Version-pinned installation (`--version X.Y.Z` from tagged releases)

**Defer (v2.2+):**
- Claude Code plugin packaging (revisit when/if namespacing constraints change)
- Marketplace submission (requires plugin packaging first)
- Auto-update mechanism (explicit upgrade is safer for autonomous execution tool)
- Multi-repo batch installer

### Architecture Approach

The installer copies files from a GitHub release tarball into the target project tree, namespaced under `scripts/ralph/` to avoid collisions. Scripts must be refactored to use a `RALPH_SCRIPTS_DIR` variable instead of hardcoded paths, enabling them to work in both the dev repo (`scripts/`) and installed repos (`scripts/ralph/`). The installer does NOT touch `settings.local.json` at install time -- the existing runtime hook injection pattern (install at ralph start, remove at exit) is preserved. The installer only merges the `ralph` config section into `.planning/config.json`. See [ARCHITECTURE.md](./ARCHITECTURE.md) for full component analysis and data flow diagrams.

**Major components:**
1. **install-ralph.sh** -- Single-file installer handling prerequisites, download, copy, config merge, verification, and uninstall
2. **RALPH_SCRIPTS_DIR refactor** -- Path variable in all scripts replacing hardcoded `scripts/` references, enabling dual-location operation
3. **Install manifest** -- `.ralph/.installed-files` tracking every file for clean uninstall
4. **Config merge** -- jq-based addition of `ralph` section to `.planning/config.json` (additive only, never overwrites)

### Critical Pitfalls

See [PITFALLS.md](./PITFALLS.md) for all 6 pitfalls with detailed prevention strategies and recovery procedures.

1. **settings.local.json destruction** -- Use jq per-key array concatenation (not `*` deep merge which replaces arrays). However, the stronger approach is to NOT modify settings.local.json at install time at all, leaving hook management to the launcher at runtime. This is the recommended approach.

2. **Hardcoded absolute paths** -- All installed paths must be relative to TARGET repo root, never source repo. Use `RALPH_SCRIPTS_DIR` variable. Test by installing into a directory at a different path than the source. Avoid `realpath` and `readlink -f` (not available on macOS without coreutils).

3. **Broken or missing uninstall** -- Design uninstall BEFORE install. Write manifest during install; read manifest during uninstall. Test the full cycle: install, verify, uninstall, diff against pre-install state.

4. **Version drift** -- Embed version marker in installed files and `.ralph/.version`. Provide explicit `--upgrade` command. Do NOT auto-update (breaks reproducibility for autonomous execution).

5. **Assumed repo structure** -- Check prerequisites before any file operations. Use `mkdir -p` for all directories. Handle: empty git repo, no `.planning/`, no `.claude/`, existing files at target paths.

## Distribution Mechanism: Resolving the Researcher Disagreement

The four researchers disagreed on distribution. Here is the resolution:

| Researcher | Recommendation | Key Argument |
|-----------|---------------|-------------|
| Stack | Claude Code plugin (primary) + npx (secondary) | Plugin system is THE standard for Claude Code extensions in 2026; 9,000+ plugins use it |
| Architecture | Bash installer (reject plugins) | Plugin namespacing breaks `/gsd:ralph` command; plugin cache breaks project-root path references |
| Features | Bash install script (v2.1), plugin (v2.1.x) | Pragmatic: build bash script first, wrap as plugin later |
| Pitfalls | Evaluate plugins first, then decide | Plugin system mitigates many pitfalls automatically (uninstall, version management, settings merge) |

**Resolution: Bash installer for v2.1. The Architecture researcher is correct on the technical constraints.**

The plugin namespacing issue is not a configuration option -- it is how the plugin system works. A command at `commands/gsd/ralph.md` inside a plugin becomes `/gsd-ralph:gsd:ralph` or a similar namespaced variant, not `/gsd:ralph`. This breaks the core user experience of "same GSD commands, just add `--ralph`." The Stack researcher's research is high quality on HOW the plugin system works but does not address the namespacing conflict with GSD's command structure.

The Pitfalls researcher's suggestion to evaluate plugins first is reasonable, but the Architecture researcher has already done that evaluation and identified concrete incompatibilities. No further evaluation is needed for v2.1.

The Features researcher's phased approach (bash first, plugin later) is the closest to correct, but "later" should mean "when Claude Code plugin namespacing supports nested namespaces or custom command paths" -- not a fixed version number.

## Implications for Roadmap

Based on research, suggested phase structure:

### Phase 1: Location-Independent Scripts

**Rationale:** Every subsequent phase depends on scripts being able to run from `scripts/ralph/` in a target repo, not just `scripts/` in the dev repo. This is a refactor of existing code, not new functionality. PITFALLS.md Pitfall 2 (hardcoded paths) makes this the highest-priority prerequisite.
**Delivers:** All existing scripts use `RALPH_SCRIPTS_DIR` variable; `.claude/commands/gsd/ralph.md` uses configurable path; all 315 existing tests still pass plus new tests for path override.
**Addresses:** Prerequisite for file copy/install core (FEATURES.md dependency graph)
**Avoids:** Hardcoded absolute paths pitfall (PITFALLS.md Pitfall 2)

### Phase 2: Core Installer (Install + Uninstall)

**Rationale:** The installer is the primary deliverable of v2.1. Install and uninstall must be designed together (Pitfalls research insists on this -- Pitfall 3). The manifest format must be defined first, then install writes to it and uninstall reads from it.
**Delivers:** `install-ralph.sh` with prerequisite detection, tarball download, file copy to `scripts/ralph/`, config merge, install manifest, `--uninstall` flag, idempotency, and post-install verification with colored output.
**Addresses:** All P1 features from FEATURES.md (single-command install, prerequisite detection, idempotent re-runs, non-destructive config merge, .ralphrc generation, install manifest, uninstall, clear output)
**Avoids:** settings.local.json destruction (Pitfall 1), assumed repo structure (Pitfall 5), missing jq (Pitfall 6), broken uninstall (Pitfall 3)

### Phase 3: Upgrade and Polish

**Rationale:** Once install/uninstall works, add upgrade support and UX improvements. Version tracking enables upgrade detection. These are P2 features that depend on the core installer being stable.
**Delivers:** `--upgrade` flag, `--dry-run` mode, version tracking in `.ralph/.version`, `--force` overwrite, GSD integration detection warnings.
**Addresses:** P2 features from FEATURES.md (upgrade-in-place, dry-run mode, version pinning)
**Avoids:** Version drift pitfall (Pitfall 4)

### Phase 4: End-to-End Testing

**Rationale:** The installer must be tested against realistic scenarios that differ from the dev environment. This is where path bugs and structure assumptions surface. Earlier phases have unit-level tests; this phase tests the integrated flow.
**Delivers:** Test suite covering: fresh GSD project, project with existing `.claude/` config, non-GSD repo (error path), re-install idempotency, install-then-uninstall cycle, install-then-upgrade cycle, end-to-end `/gsd:ralph execute-phase N --dry-run` after install.
**Addresses:** Post-install verification (FEATURES.md), cross-machine compatibility
**Avoids:** All pitfalls -- this phase is the verification layer

### Phase Ordering Rationale

- **Phase 1 before Phase 2:** Scripts must be location-independent before they can be installed elsewhere. Building the installer first would mean testing against broken scripts.
- **Phase 2 as a single phase (install + uninstall together):** The Pitfalls researcher strongly recommends designing uninstall first, which forces defining the manifest format. Splitting install and uninstall into separate phases risks shipping install without uninstall.
- **Phase 3 after Phase 2:** Upgrade requires a working installer and version tracking. Dry-run wraps existing install logic.
- **Phase 4 last:** Integration tests require all components to exist. This validates the full pipeline.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2:** The tarball download mechanism needs specific GitHub API/URL patterns confirmed. The config merge jq logic should be prototyped against edge cases (empty file, malformed JSON, existing ralph section). The lib/ directory installation path needs a design decision (see Gaps below).

Phases with standard patterns (skip research-phase):
- **Phase 1:** Standard Bash refactoring -- replace hardcoded paths with variables. Well-understood pattern, existing test suite validates.
- **Phase 3:** `--dry-run` and `--upgrade` are standard CLI patterns. gsd-ralph already has dry-run in ralph-launcher.sh as a reference.
- **Phase 4:** Standard test authoring using bats-core (already in use with 315 tests).

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Official Claude Code plugin docs verified; decision to use bash installer is grounded in concrete namespacing constraints confirmed against plugin documentation |
| Features | HIGH | Feature landscape well-mapped with competitor analysis (GSD npx installer, ralph-loop-setup plugin, flow-next plugin); MVP scope is clear; dependency graph is sound |
| Architecture | HIGH | Installer flow is straightforward; existing `_install_hook`/`_remove_hook` patterns prove the merge approach; namespaced directory layout (`scripts/ralph/`) avoids collisions |
| Pitfalls | HIGH | Pitfalls grounded in real codebase analysis (ralph-launcher.sh lines 342-383), real-world installer post-mortems (oh-my-bash issues), and official Claude Code settings merge documentation |

**Overall confidence:** HIGH

### Gaps to Address

- **lib/ directory installation path**: The Features researcher lists `lib/**/*.sh` (18+ files across lib/, lib/commands/, lib/merge/, lib/cleanup/) as managed files, but the Architecture researcher's target layout only shows `scripts/ralph/`. Need to decide during Phase 2 planning whether lib/ files install to `scripts/ralph/lib/`, remain at `lib/` in the target, or get flattened into a different structure.
- **GitHub release tarball URL format**: The exact URL pattern for downloading tagged releases (`https://github.com/USER/REPO/archive/refs/tags/vX.Y.Z.tar.gz`) is standard but should be confirmed during Phase 2 planning.
- **RALPH_SCRIPTS_DIR impact scope**: Phase 1 needs to audit every script-to-script and script-to-lib reference in the codebase. The Architecture researcher identified `ralph-launcher.sh` and `ralph.md` but there may be additional references in lib/ files that source each other.
- **`.ralphrc` and `.ralph/` gitignore handling**: Both the Pitfalls and Architecture researchers flag that these should be added to `.gitignore` if not present. This is a minor installer feature but needs a design decision on whether to auto-modify `.gitignore`.
- **Plugin system re-evaluation trigger**: The plugin system is deferred, not rejected permanently. If Claude Code adds support for custom command namespaces or namespace aliasing in a future version, the plugin approach should be reconsidered. No action needed now, but worth noting for v2.2+ planning.

## Sources

### Primary (HIGH confidence)
- [Claude Code Plugin System docs](https://code.claude.com/docs/en/plugins) -- Plugin structure, manifest, namespacing behavior
- [Claude Code Plugin Marketplace docs](https://code.claude.com/docs/en/plugin-marketplaces) -- Distribution options, marketplace.json
- [Claude Code Discover Plugins docs](https://code.claude.com/docs/en/discover-plugins) -- Installation scopes, team config
- [Claude Code Plugins Reference](https://code.claude.com/docs/en/plugins-reference) -- `CLAUDE_PLUGIN_ROOT`, hooks format, caching
- [Claude Code Skills docs](https://code.claude.com/docs/en/skills) -- Skill discovery, SKILL.md format
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) -- PreToolUse hook schema, settings merge behavior
- [Claude Code Settings docs](https://code.claude.com/docs/en/settings) -- Array concatenation/deduplication across scopes
- [npm package.json bin field](https://docs.npmjs.com/cli/v11/configuring-npm/package-json/) -- npx CLI pattern (evaluated, not recommended)
- gsd-ralph `ralph-launcher.sh` `_install_hook`/`_remove_hook` (lines 342-383) -- Proven jq merge/unmerge pattern
- gsd-ralph test suite (315 tests across 6 suites) -- Existing coverage baseline

### Secondary (MEDIUM confidence)
- [GSD get-shit-done-cc npm package](https://www.npmjs.com/package/get-shit-done-cc) -- npx installer reference pattern
- [ralph-loop-setup plugin](https://github.com/MarioGiancini/ralph-loop-setup) -- Plugin-based distribution reference
- [flow-next plugin](https://github.com/gmickel/gmickel-claude-marketplace) -- Plugin marketplace reference
- [oh-my-bash installer issues #115, #267](https://github.com/ohmybash/oh-my-bash/issues/115) -- Real-world installer pitfalls
- [macOS realpath unavailability](https://github.com/facebook/react-native/issues/34146) -- Bash 3.2 path resolution constraints
- [Idempotent Bash scripts (Fatih Arslan)](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/) -- Guard clause patterns
- [Shopify CLI error handling](https://shopify.github.io/cli/cli/error_handling.html) -- Error UX principles

### Tertiary (LOW confidence)
- [Anthropic Official Marketplace](https://github.com/anthropics/claude-plugins-official) -- 9.7k stars; namespacing behavior inferred from docs, not directly tested against gsd-ralph
- [npm supply chain attacks analysis](https://snyk.io/articles/npm-security-best-practices-shai-hulud-attack/) -- Security rationale for avoiding npx distribution
- [curl-pipe-bash security analysis](https://www.kicksecure.com/wiki/Dev/curl_bash_pipe) -- Partial download vulnerability documentation

---
*Research completed: 2026-03-10*
*Ready for roadmap: yes*
