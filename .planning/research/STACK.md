# Technology Stack

**Project:** gsd-ralph
**Researched:** 2026-02-13
**Overall confidence:** MEDIUM (no WebSearch available; recommendations based on codebase analysis, foundational document constraints, and training data knowledge of bash CLI tooling)

## Decision: Bash, Not Node.js

The foundational document explicitly states: "Bash-based CLI for portability (same environment as Ralph)" and "No additional runtime dependencies beyond what GSD and Ralph already require." The PROJECT.md reinforces: "Same ecosystem as GSD/Ralph."

Ralph is a bash tool. gsd-ralph orchestrates Ralph. Building gsd-ralph in bash means:
- Zero new dependencies for users who already have Ralph installed
- Native access to `git worktree`, process management, file system operations
- Same debugging/maintenance mental model as Ralph itself
- The existing reference scripts are already bash and work

Building in Node.js would require a package.json, npm install step, and node runtime -- friction that contradicts the "no exotic dependencies" constraint. GSD uses Node.js for its *plugin system*, but gsd-ralph is explicitly a standalone tool, not a GSD plugin.

**Verdict:** Pure bash with structured project layout. Use `python3` only for XML parsing (already a dependency in the existing scripts; available on all macOS systems).

## Recommended Stack

### Core Runtime

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| Bash | 3.2+ (macOS default) | Script runtime | Required by Ralph ecosystem; macOS ships with 3.2, most devs have 5.x via Homebrew. Target 3.2 for maximum compat (avoid associative arrays, `readarray`, etc.) | HIGH |
| Git | 2.20+ | Worktree management | `git worktree` is stable since ~2.15; 2.20+ for reliable `git worktree list --porcelain` | HIGH |
| jq | 1.6+ | JSON parsing (status.json) | Already used in existing scripts for status checking. Available via Homebrew, lightweight, standard for bash JSON work | HIGH |
| Python 3 | 3.8+ | XML task extraction | Already used in existing scripts for regex-based XML parsing. Ships with macOS (or via Xcode CLI tools). Only used for the `<task>` extraction step, not as a general dependency | MEDIUM |

### Project Structure

| Component | Path | Purpose | Why | Confidence |
|-----------|------|---------|-----|------------|
| Entry point | `bin/gsd-ralph` | Single executable with subcommand dispatch | Standard pattern for bash CLI tools. `bin/` convention matches npm/Homebrew expectations for installable scripts | HIGH |
| Library modules | `lib/*.sh` | Shared functions sourced by commands | Separates concerns without Node.js. Each module owns one domain (git, templates, output, config) | HIGH |
| Subcommands | `lib/commands/*.sh` | One file per subcommand (init, execute, status, merge, cleanup) | Clean separation. Each command is testable in isolation. `bin/gsd-ralph` dispatches to the right file | HIGH |
| Templates | `templates/*.template` | Prompt/config templates with variable substitution | Already exists in the project. Template files with `{{VARIABLE}}` placeholders, substituted via `sed` or `envsubst` | HIGH |
| Tests | `tests/*.bats` | Automated test suite | BATS is the standard bash testing framework. Tests verify each command and library function | HIGH |
| Config | `.gsd-ralphrc` | Per-project config (optional) | Mirrors Ralph's `.ralphrc` pattern. Source it if present, use defaults otherwise | MEDIUM |

### Recommended Project Layout

```
gsd-ralph/
  bin/
    gsd-ralph              # Entry point (chmod +x, hashbang)
  lib/
    common.sh              # Colors, printing, error handling
    config.sh              # Config loading (.gsd-ralphrc, defaults)
    git.sh                 # Worktree creation, branch management, merge
    discovery.sh           # Plan file discovery (GSD naming conventions)
    templates.sh           # Template rendering (variable substitution)
    process.sh             # Ralph launching, PID tracking, monitoring
    notify.sh              # Terminal bell, completion notifications
    commands/
      init.sh              # gsd-ralph init
      execute.sh           # gsd-ralph execute N
      status.sh            # gsd-ralph status N
      merge.sh             # gsd-ralph merge N
      cleanup.sh           # gsd-ralph cleanup N
  templates/
    PROMPT.md.template     # Already exists
    AGENT.md.template      # Already exists
    fix_plan.md.template   # Already exists
    ralphrc.template       # Already exists
    WORKFLOW.md.template   # Already exists
  tests/
    test_helper.bash       # BATS test helpers, fixtures setup
    discovery.bats         # Plan discovery tests
    git.bats               # Worktree/branch tests
    templates.bats         # Template rendering tests
    init.bats              # Init command integration tests
    execute.bats           # Execute command integration tests
  Makefile                 # install, test, lint targets
  README.md
```

### Testing Framework

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| bats-core | 1.11+ | Bash test runner | The de facto standard for testing bash scripts. Provides `@test` blocks, `run` command capture, setup/teardown. Actively maintained (bats-core org took over from original bats) | HIGH |
| bats-support | 0.3.0 | Test assertions | Provides `assert_success`, `assert_failure`, `assert_output` -- cleaner than raw `[ "$status" -eq 0 ]` | HIGH |
| bats-assert | 2.2.0 | Extended assertions | `assert_line`, `refute_output`, partial matching. Part of the bats-core ecosystem | HIGH |
| bats-file | 0.4.0 | File assertions | `assert_file_exists`, `assert_dir_exists`. Useful for testing init/worktree creation | MEDIUM |

**Installation for testing:** BATS and helpers install via git submodules in `tests/libs/` or via Homebrew (`brew install bats-core`). Git submodules preferred for CI reproducibility.

### Linting

| Technology | Version | Purpose | Why | Confidence |
|------------|---------|---------|-----|------------|
| ShellCheck | 0.10+ | Static analysis | Catches common bash pitfalls (unquoted variables, useless use of cat, POSIX issues). Widely adopted, integrates with editors. Non-negotiable for a bash project of this size | HIGH |

### Supporting Tools (Already Available)

| Tool | Purpose | Notes |
|------|---------|-------|
| `envsubst` | Template variable substitution | Part of `gettext`; available on macOS via Homebrew or use `sed` fallback |
| `mktemp` | Temporary file/directory creation for tests | Standard POSIX utility |
| `date` | Timestamps for status.json | macOS `date` differs from GNU; use `-Iseconds` carefully or fall back to `date +%Y-%m-%dT%H:%M:%S%z` |
| `tput` | Terminal bell (`tput bel`) | More portable than `echo -e "\a"` |
| `wc`, `sort`, `find` | File counting, ordering, discovery | Already used in existing scripts |

## Template Rendering Strategy

The existing scripts use bash heredocs and `cat >>` for template rendering. This works but is fragile (templates embedded in bash code). Better approach:

**Use `sed`-based variable substitution on external template files.**

```bash
render_template() {
    local template="$1"
    local output="$2"
    # Shift past the first two args, remaining are KEY=VALUE pairs
    shift 2
    local content
    content=$(<"$template")
    for pair in "$@"; do
        local key="${pair%%=*}"
        local value="${pair#*=}"
        content="${content//\{\{${key}\}\}/${value}}"
    done
    printf '%s\n' "$content" > "$output"
}
```

This keeps templates as standalone files (easy to edit, version, and review) while avoiding `envsubst` as a hard dependency. The `{{VARIABLE}}` syntax is simple and grep-able.

**Confidence:** HIGH -- this is a well-established pattern for bash template rendering.

## Process Management Strategy

For launching and monitoring Ralph instances:

| Approach | When | How |
|----------|------|-----|
| **Foreground (interactive)** | Default for `execute` | Print instructions for user to open terminals manually. This is what existing scripts do and it works well -- user maintains control |
| **Background (automated)** | Optional `--background` flag | Launch Ralph via `nohup ralph > .ralph/logs/ralph.log 2>&1 &` and store PID in `.ralph/pid`. Status command reads PIDs to check if processes are alive |
| **Terminal bell** | On completion/failure | `tput bel` when status detects all worktrees complete or any worktree errored |

**Start with foreground mode only** (matching existing behavior). Background mode is a differentiator feature for later phases.

**Confidence:** HIGH for foreground, MEDIUM for background (needs careful signal handling and orphan process cleanup).

## Alternatives Considered

| Category | Recommended | Alternative | Why Not |
|----------|-------------|-------------|---------|
| Language | Bash | Node.js (Commander.js/oclif) | Foundational doc explicitly requires bash. Adding npm/node dependency contradicts "no additional runtime dependencies" constraint |
| Language | Bash | Python | Heavier runtime, not in Ralph ecosystem, creates a dependency management problem (pip/venv) |
| Language | Bash | Go (compiled binary) | Compile step, different ecosystem, harder for users to inspect/modify. Over-engineering for this scope |
| Testing | bats-core | shunit2 | shunit2 is older, less actively maintained. bats-core has better ecosystem (bats-support, bats-assert, bats-file) |
| Testing | bats-core | No tests | The existing scripts have zero tests. This is tech debt. A clean rebuild should include tests from day one |
| Template rendering | sed substitution | envsubst | envsubst requires gettext package, not always available. sed-based approach has zero extra deps |
| Template rendering | sed substitution | gomplate/mustache CLI | Extra binary dependency, overkill for simple variable substitution |
| JSON parsing | jq | python3 json module | jq is purpose-built, faster, already a dependency in existing scripts |
| XML parsing | python3 regex | xmlstarlet/xmllint | The GSD "XML" is actually embedded in Markdown, not a valid XML document. Regex extraction is the pragmatic approach (and what works in the existing scripts) |
| Arg parsing | Manual case/getopts | bash framework (bash-argsparse, etc.) | getopts is built-in, well-understood, zero dependencies. The subcommand set is small (5 commands) -- no framework needed |
| Linting | ShellCheck | bashate | ShellCheck is more comprehensive and more widely adopted |

## What NOT to Use

| Technology | Why Not |
|------------|---------|
| **Node.js / npm** | Contradicts bash ecosystem constraint. Adds runtime dependency. Over-engineering |
| **Docker** | Users run this locally in their terminal alongside their editor. Docker adds startup latency and filesystem complexity with worktrees |
| **Make as CLI** | Make is for build targets, not user-facing CLIs. Confusing UX |
| **zsh-specific features** | bash is the portable target. Existing Ralph scripts use bash |
| **GNU-specific flags** | macOS ships BSD utils. Avoid `grep -P`, `sed -i''` without backup arg, `date --iso-8601`. Use POSIX-compatible flags |
| **Associative arrays** | Requires bash 4+. macOS ships bash 3.2. Use indexed arrays or plain variables |
| **`readarray`/`mapfile`** | Bash 4+ only. Use `while IFS= read -r` loops |
| **`[[ ]]` with regex** | Works but varies across bash versions. Use `grep` or `case` for pattern matching |
| **Fancy TUI frameworks** | charmbracelet/gum, dialog, whiptail. Adds dependencies. printf/echo with ANSI codes is sufficient (already working in existing scripts) |

## Installation Strategy

The tool should be installable by:

1. **Git clone + PATH** (primary): `git clone`, add `bin/` to PATH or symlink `bin/gsd-ralph` to `/usr/local/bin/`
2. **Makefile install**: `make install` copies to `/usr/local/bin/gsd-ralph` and bundles lib/ + templates/
3. **Homebrew tap** (future): For polished distribution, but not for v1

The binary (`bin/gsd-ralph`) must resolve its own location to find `lib/` and `templates/` relative to itself:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GSD_RALPH_HOME="$(dirname "$SCRIPT_DIR")"
# Now source libs from $GSD_RALPH_HOME/lib/
```

**Confidence:** HIGH -- this is standard practice for self-contained bash tool distribution.

## Dependency Summary

### Required (user must have)

| Dependency | Likely Already Installed | Why |
|------------|--------------------------|-----|
| bash 3.2+ | Yes (ships with macOS) | Script runtime |
| git 2.20+ | Yes (required by both GSD and Ralph) | Worktree management |
| jq 1.6+ | Likely (common dev tool, `brew install jq`) | JSON parsing for status.json |
| python3 3.8+ | Yes (ships with macOS or via Xcode tools) | XML task extraction from GSD plans |

### Required for development only

| Dependency | Purpose |
|------------|---------|
| bats-core 1.11+ | Running test suite |
| ShellCheck 0.10+ | Linting |

### Pre-flight Check

The `gsd-ralph init` command (or a `gsd-ralph doctor` subcommand) should verify dependencies at first run:

```bash
check_dependencies() {
    local missing=()
    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v ralph >/dev/null 2>&1 || missing+=("ralph (https://github.com/frankbria/ralph-claude-code)")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing dependencies: ${missing[*]}"
        return 1
    fi
}
```

## Bash 3.2 Compatibility Checklist

Since macOS ships bash 3.2 and the project targets macOS as primary platform:

| Feature | Bash 3.2 | Bash 4+ | Approach |
|---------|----------|---------|----------|
| Associative arrays | NO | `declare -A` | Use flat variables or temp files |
| `readarray`/`mapfile` | NO | YES | Use `while IFS= read -r` |
| `${var,,}` lowercase | NO | YES | Use `tr '[:upper:]' '[:lower:]'` |
| `${var^^}` uppercase | NO | YES | Use `tr '[:lower:]' '[:upper:]'` |
| `|&` pipe stderr | NO | YES | Use `2>&1 |` |
| `[[ ]]` | YES | YES | Safe to use |
| `$(...)` command sub | YES | YES | Safe to use |
| Regular arrays | YES | YES | Safe to use |
| `local` variables | YES | YES | Safe to use |
| Here-strings `<<<` | YES | YES | Safe to use |

**Confidence:** HIGH -- these are well-documented bash version differences.

## Sources

- Existing codebase analysis: `/Users/daniswhoiam/Projects/gsd-ralph/scripts/*.sh` (5 scripts analyzed)
- Existing templates: `/Users/daniswhoiam/Projects/gsd-ralph/templates/*.template` (5 templates analyzed)
- Foundational document: `/Users/daniswhoiam/Projects/gsd-ralph/FOUNDATIONAL_DOCUMENT.md`
- Project requirements: `/Users/daniswhoiam/Projects/gsd-ralph/.planning/PROJECT.md`
- Ralph config reference: `/Users/daniswhoiam/Projects/gsd-ralph/templates/ralphrc.template`
- Training data knowledge for bats-core, ShellCheck, bash version compatibility (MEDIUM confidence -- versions should be verified against official repos before development begins)
