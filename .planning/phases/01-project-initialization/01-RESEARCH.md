# Phase 1: Project Initialization - Research

**Researched:** 2026-02-13
**Domain:** Bash CLI scaffolding, dependency validation, project type auto-detection
**Confidence:** HIGH

## Summary

Phase 1 establishes the entire CLI foundation: the `bin/gsd-ralph` entry point, the `lib/` module structure, the `gsd-ralph init` command, dependency validation, and project type auto-detection. This is the first phase and has zero dependencies -- it creates the skeleton that every subsequent phase builds on.

The technical challenge is modest. The entry point is a standard bash subcommand dispatcher using `case` statements with `getopts` for global flags. The init command creates a `.ralph/` configuration directory, detects the project's tech stack from marker files (package.json, Cargo.toml, go.mod, etc.), and writes a `.ralphrc` with sensible defaults. Dependency checking uses `command -v` to validate git, jq, python3, and ralph are available, with actionable error messages per missing tool.

The real value of this phase is establishing patterns that all subsequent phases follow: the lib module structure, the output/logging conventions, the config loading approach, and the test infrastructure. Getting these right now prevents rework later. Since gsd-ralph is a pure bash CLI targeting bash 3.2+ (macOS default), every pattern must avoid bash 4+ features like associative arrays, `readarray`, and `${var,,}`.

**Primary recommendation:** Build the full CLI skeleton (entry point, lib modules, command dispatch) alongside the init command. Establish bats-core testing from the very first task. Do not defer test infrastructure.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | Script runtime | macOS ships 3.2; target for maximum portability. Avoid bash 4+ features. |
| Git | 2.20+ | Version control (dependency check) | Required by project; `git worktree list --porcelain` reliable since 2.20 |
| jq | 1.6+ | JSON parsing | Used for status.json in later phases; validated at init time |
| Python 3 | 3.8+ | XML task extraction (later phases) | Ships with macOS via Xcode CLI tools; validated at init time |

### Development/Testing

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| bats-core | 1.13.0 | Bash test runner | All test files; `@test` blocks with `run` command capture |
| bats-support | 0.3.0 | Core test assertions | `assert_success`, `assert_failure`, `assert_output` |
| bats-assert | 2.2.0 | Extended assertions | `assert_line`, `refute_output`, partial matching |
| bats-file | 0.4.0 | Filesystem assertions | `assert_file_exists`, `assert_dir_exists` for init tests |
| ShellCheck | 0.10+ | Static analysis/linting | All bash files; catches unquoted variables, POSIX issues, bash version gotchas |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| getopts (built-in) | bash-argsparse, bash framework | getopts is zero-dependency, well-understood; CLI has only 5 subcommands -- no framework needed |
| sed-based templates | envsubst | envsubst requires gettext package, not always available; sed approach has zero extra deps |
| `command -v` for checks | `which` | `command -v` is POSIX-standard and works in all shells; `which` behavior varies across platforms |
| bats-core git submodules | brew install bats-core | Submodules give reproducible versions; Homebrew may install different version on different machines |

**Installation (dev dependencies via git submodules):**
```bash
git submodule add https://github.com/bats-core/bats-core.git tests/bats
git submodule add https://github.com/bats-core/bats-support.git tests/test_helper/bats-support
git submodule add https://github.com/bats-core/bats-assert.git tests/test_helper/bats-assert
git submodule add https://github.com/bats-core/bats-file.git tests/test_helper/bats-file
```

## Architecture Patterns

### Recommended Project Structure

```
gsd-ralph/
  bin/
    gsd-ralph                  # Entry point (chmod +x, #!/bin/bash hashbang)
  lib/
    common.sh                  # Colors, printing, error handling, logging
    config.sh                  # Config loading (.gsd-ralphrc, defaults, project detection)
    git.sh                     # Git operations abstraction (worktree, branch, merge)
    discovery.sh               # GSD plan file discovery (naming conventions)
    templates.sh               # Template rendering ({{VARIABLE}} substitution)
    commands/
      init.sh                  # gsd-ralph init
      execute.sh               # gsd-ralph execute N (future phase)
      status.sh                # gsd-ralph status N (future phase)
      merge.sh                 # gsd-ralph merge N (future phase)
      cleanup.sh               # gsd-ralph cleanup N (future phase)
  templates/
    ralphrc.template           # .ralphrc template with project-specific vars
    PROMPT.md.template         # Base PROMPT.md (already exists)
    AGENT.md.template          # AGENT.md (already exists)
    WORKFLOW.md.template       # Workflow reference (already exists)
    fix_plan.md.template       # fix_plan.md skeleton (already exists)
  tests/
    bats/                      # bats-core (git submodule)
    test_helper/
      bats-support/            # (git submodule)
      bats-assert/             # (git submodule)
      bats-file/               # (git submodule)
      common.bash              # Shared test setup (load helpers, set paths)
    common.bats                # Tests for lib/common.sh
    config.bats                # Tests for lib/config.sh (project detection)
    init.bats                  # Integration tests for init command
  Makefile                     # test, lint, install targets
```

### Pattern 1: Entry Point with Self-Location and Subcommand Dispatch

**What:** The `bin/gsd-ralph` script resolves its own location to find `lib/` relative to itself, sources shared modules, then dispatches to subcommand handlers via a `case` statement.

**When to use:** Always. This is the single entry point for all CLI operations.

**Example:**
```bash
#!/bin/bash
# bin/gsd-ralph -- Entry point for gsd-ralph CLI

set -euo pipefail

# Resolve script location (works even if symlinked)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GSD_RALPH_HOME="$(dirname "$SCRIPT_DIR")"

# Source shared libraries
source "$GSD_RALPH_HOME/lib/common.sh"
source "$GSD_RALPH_HOME/lib/config.sh"

# Version
GSD_RALPH_VERSION="0.1.0"

# Global options
VERBOSE=false

usage() {
    cat <<EOF
gsd-ralph v${GSD_RALPH_VERSION} -- Bridge GSD planning with Ralph execution

Usage: gsd-ralph [options] <command> [args]

Commands:
  init        Initialize gsd-ralph in a GSD project
  execute N   Execute phase N in parallel worktrees
  status N    Show status of phase N worktrees
  merge N     Merge completed branches for phase N
  cleanup N   Remove worktrees and branches for phase N

Options:
  -h, --help     Show this help message
  -v, --verbose  Enable verbose output
  --version      Show version

Run 'gsd-ralph <command> --help' for command-specific help.
EOF
}

# Parse global options (before subcommand)
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage; exit 0 ;;
        --version)    echo "gsd-ralph v${GSD_RALPH_VERSION}"; exit 0 ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -*)           print_error "Unknown option: $1"; usage; exit 1 ;;
        *)            break ;;  # First non-option is the subcommand
    esac
done

if [[ $# -eq 0 ]]; then
    usage
    exit 1
fi

COMMAND="$1"; shift

# Dispatch to command handler
COMMAND_FILE="$GSD_RALPH_HOME/lib/commands/${COMMAND}.sh"
if [[ -f "$COMMAND_FILE" ]]; then
    source "$COMMAND_FILE"
    cmd_${COMMAND} "$@"
else
    print_error "Unknown command: $COMMAND"
    usage
    exit 1
fi
```

### Pattern 2: Structured Output with Color Support

**What:** A common.sh library providing consistent output functions with ANSI color codes. All user-facing output goes through these functions for consistency.

**When to use:** Every command handler and library module.

**Example:**
```bash
# lib/common.sh -- Shared output and utility functions

# Detect if stdout is a terminal (for color support)
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

print_header() {
    printf "\n${BLUE}%s${NC}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "${BLUE} %s${NC}\n" "$1"
    printf "${BLUE}%s${NC}\n\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_success() { printf "${GREEN}[ok]${NC} %s\n" "$1"; }
print_warning() { printf "${YELLOW}[warn]${NC} %s\n" "$1"; }
print_error()   { printf "${RED}[error]${NC} %s\n" "$1" >&2; }
print_info()    { printf "${BLUE}[info]${NC} %s\n" "$1"; }

print_verbose() {
    if [[ "${VERBOSE:-false}" == "true" ]]; then
        printf "${BLUE}[verbose]${NC} %s\n" "$1"
    fi
}

die() {
    print_error "$1"
    exit "${2:-1}"
}
```

### Pattern 3: Project Type Detection via Marker Files

**What:** Detect the project's language, test command, and build tool by checking for well-known marker files in the project root.

**When to use:** During `gsd-ralph init` to auto-configure `.ralphrc`.

**Example:**
```bash
# lib/config.sh -- Project detection and configuration

detect_project_type() {
    local project_dir="${1:-.}"
    local lang="" test_cmd="" build_cmd="" pkg_manager=""

    # Check marker files in priority order
    if [[ -f "$project_dir/package.json" ]]; then
        lang="javascript"
        pkg_manager="npm"
        # Check for typescript
        if [[ -f "$project_dir/tsconfig.json" ]]; then
            lang="typescript"
        fi
        # Detect test command from package.json
        if command -v jq >/dev/null 2>&1; then
            local scripts_test
            scripts_test=$(jq -r '.scripts.test // empty' "$project_dir/package.json" 2>/dev/null)
            if [[ -n "$scripts_test" ]]; then
                test_cmd="npm test"
            fi
            local scripts_build
            scripts_build=$(jq -r '.scripts.build // empty' "$project_dir/package.json" 2>/dev/null)
            if [[ -n "$scripts_build" ]]; then
                build_cmd="npm run build"
            fi
            local scripts_typecheck
            scripts_typecheck=$(jq -r '.scripts.typecheck // empty' "$project_dir/package.json" 2>/dev/null)
            if [[ -n "$scripts_typecheck" ]]; then
                build_cmd="npm run typecheck"
            fi
        fi
        # Detect package manager
        if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
            pkg_manager="pnpm"
            test_cmd="${test_cmd/npm/pnpm}"
            build_cmd="${build_cmd/npm/pnpm}"
        elif [[ -f "$project_dir/yarn.lock" ]]; then
            pkg_manager="yarn"
            test_cmd="${test_cmd/npm/yarn}"
            build_cmd="${build_cmd/npm/yarn}"
        elif [[ -f "$project_dir/bun.lockb" ]] || [[ -f "$project_dir/bun.lock" ]]; then
            pkg_manager="bun"
            test_cmd="${test_cmd/npm/bun}"
            build_cmd="${build_cmd/npm/bun}"
        fi

    elif [[ -f "$project_dir/Cargo.toml" ]]; then
        lang="rust"
        test_cmd="cargo test"
        build_cmd="cargo build"
        pkg_manager="cargo"

    elif [[ -f "$project_dir/go.mod" ]]; then
        lang="go"
        test_cmd="go test ./..."
        build_cmd="go build ./..."
        pkg_manager="go"

    elif [[ -f "$project_dir/pyproject.toml" ]]; then
        lang="python"
        # Check for common test frameworks
        if [[ -f "$project_dir/pytest.ini" ]] || [[ -d "$project_dir/tests" ]]; then
            test_cmd="pytest"
        elif [[ -f "$project_dir/setup.py" ]]; then
            test_cmd="python -m pytest"
        fi
        build_cmd=""
        pkg_manager="pip"
        # Detect poetry/uv
        if [[ -f "$project_dir/poetry.lock" ]]; then
            pkg_manager="poetry"
            test_cmd="poetry run pytest"
        elif [[ -f "$project_dir/uv.lock" ]]; then
            pkg_manager="uv"
            test_cmd="uv run pytest"
        fi

    elif [[ -f "$project_dir/requirements.txt" ]] || [[ -f "$project_dir/setup.py" ]]; then
        lang="python"
        test_cmd="python -m pytest"
        build_cmd=""
        pkg_manager="pip"

    elif [[ -f "$project_dir/Makefile" ]]; then
        lang="unknown"
        # Check if Makefile has test target
        if grep -q '^test:' "$project_dir/Makefile" 2>/dev/null; then
            test_cmd="make test"
        fi
        if grep -q '^build:' "$project_dir/Makefile" 2>/dev/null; then
            build_cmd="make build"
        fi

    elif [[ -f "$project_dir/Gemfile" ]]; then
        lang="ruby"
        test_cmd="bundle exec rspec"
        build_cmd=""
        pkg_manager="bundler"

    elif [[ -f "$project_dir/mix.exs" ]]; then
        lang="elixir"
        test_cmd="mix test"
        build_cmd="mix compile"
        pkg_manager="mix"

    elif [[ -f "$project_dir/build.gradle" ]] || [[ -f "$project_dir/build.gradle.kts" ]]; then
        lang="java"
        test_cmd="./gradlew test"
        build_cmd="./gradlew build"
        pkg_manager="gradle"

    elif [[ -f "$project_dir/pom.xml" ]]; then
        lang="java"
        test_cmd="mvn test"
        build_cmd="mvn package"
        pkg_manager="maven"
    fi

    # Export results via global variables (bash 3.2 compatible -- no nameref)
    DETECTED_LANG="${lang:-unknown}"
    DETECTED_TEST_CMD="${test_cmd:-}"
    DETECTED_BUILD_CMD="${build_cmd:-}"
    DETECTED_PKG_MANAGER="${pkg_manager:-}"
}
```

### Pattern 4: Dependency Validation with Actionable Messages

**What:** Check that all required external tools are available before proceeding. Provide specific, actionable installation instructions per tool.

**When to use:** At the start of `gsd-ralph init`, and optionally as a pre-flight check before other commands.

**Example:**
```bash
# lib/common.sh (continued)

check_dependency() {
    local cmd="$1"
    local install_hint="$2"
    local min_version="${3:-}"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "$cmd is not installed"
        printf "  Install: %s\n" "$install_hint"
        return 1
    fi

    if [[ -n "$min_version" ]]; then
        print_verbose "$cmd found at $(command -v "$cmd")"
    fi
    return 0
}

check_all_dependencies() {
    local missing=0

    check_dependency "git" "https://git-scm.com/download" || missing=$((missing + 1))
    check_dependency "jq" "brew install jq  (or: https://jqlang.github.io/jq/download/)" || missing=$((missing + 1))
    check_dependency "python3" "Install Xcode CLI tools: xcode-select --install" || missing=$((missing + 1))
    check_dependency "ralph" "https://github.com/frankbria/ralph-claude-code" || missing=$((missing + 1))

    if [[ $missing -gt 0 ]]; then
        printf "\n"
        print_error "$missing required dependency(ies) missing. Install them and re-run."
        return 1
    fi

    print_success "All dependencies found"
    return 0
}
```

### Pattern 5: Init Command Structure

**What:** The `gsd-ralph init` command validates dependencies, detects project type, creates the `.ralph/` configuration directory, and writes sensible default configuration files.

**When to use:** First-time setup in any GSD project.

**Example:**
```bash
# lib/commands/init.sh

cmd_init() {
    # Parse init-specific options
    local force=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force) force=true; shift ;;
            -h|--help)  init_usage; exit 0 ;;
            *)          die "Unknown option for init: $1" ;;
        esac
    done

    print_header "gsd-ralph init"

    # Step 1: Validate we are in a git repo
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die "Not inside a git repository. Run this from your project root."
    fi

    # Step 2: Check for GSD planning directory
    if [[ ! -d ".planning" ]]; then
        die "No .planning/ directory found. Initialize GSD first."
    fi

    # Step 3: Check if already initialized
    if [[ -d ".ralph" ]] && [[ "$force" != "true" ]]; then
        print_warning ".ralph/ directory already exists. Use --force to reinitialize."
        exit 0
    fi

    # Step 4: Check dependencies
    print_info "Checking dependencies..."
    check_all_dependencies || exit 1

    # Step 5: Detect project type
    print_info "Detecting project type..."
    detect_project_type "."

    print_success "Language: ${DETECTED_LANG}"
    [[ -n "$DETECTED_TEST_CMD" ]] && print_success "Test command: ${DETECTED_TEST_CMD}"
    [[ -n "$DETECTED_BUILD_CMD" ]] && print_success "Build command: ${DETECTED_BUILD_CMD}"
    [[ -n "$DETECTED_PKG_MANAGER" ]] && print_success "Package manager: ${DETECTED_PKG_MANAGER}"

    # Step 6: Create .ralph/ directory structure
    mkdir -p .ralph/logs

    # Step 7: Generate configuration files from templates
    # ... render_template calls here ...

    print_header "Initialization complete"
    print_success "Created .ralph/ configuration directory"
    print_info "Next steps:"
    printf "  1. Review .ralphrc configuration\n"
    printf "  2. Plan your first phase with GSD\n"
    printf "  3. Run: gsd-ralph execute 1\n"
}
```

### Anti-Patterns to Avoid

- **Associative arrays (`declare -A`):** Requires bash 4+. Use indexed arrays, function return values, or temporary files instead. For key-value config, use `source`-able files (KEY=value format).
- **`readarray` / `mapfile`:** Requires bash 4+. Use `while IFS= read -r line; do ... done` loops.
- **`${var,,}` / `${var^^}`:** Requires bash 4+. Use `tr '[:upper:]' '[:lower:]'` or `tr '[:lower:]' '[:upper:]'`.
- **`|&` (pipe stderr):** Requires bash 4+. Use `2>&1 |` instead.
- **GNU-specific flags:** macOS ships BSD utilities. Avoid `grep -P`, `sed -i''` without backup arg, `date --iso-8601`, `date -Iseconds`. Use POSIX-compatible flags.
- **Hardcoded paths in templates:** Use `{{VARIABLE}}` placeholder substitution, not bash `$VARIABLE` interpolation in heredocs.
- **Global state leakage:** Every lib function should use `local` for all variables. Export only through explicit mechanisms.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bash testing | Custom assert functions | bats-core + bats-assert + bats-file | Mature ecosystem, TAP-compliant, bash 3.2 compatible, widely adopted |
| Bash linting | Manual code review | ShellCheck | Catches 200+ bug patterns; non-negotiable for bash project of this size |
| JSON parsing in bash | awk/sed on JSON strings | jq | JSON structure is recursive; regex/awk parsing breaks on nested objects, escapes |
| Argument parsing | Manual $1/$2 shifting | getopts for flags, case for subcommands | Built-in, handles edge cases (missing args, combined flags) correctly |
| Color output detection | Hardcoded ANSI codes | `[[ -t 1 ]]` check | Prevents broken output when piped or redirected to file |
| Timestamp formatting | `date -Iseconds` (GNU) | `date -u +%Y-%m-%dT%H:%M:%SZ` | Works on both macOS (BSD date) and Linux (GNU date) |

**Key insight:** Bash is powerful but fragile. Every place you can use a standard tool or pattern instead of custom code reduces the surface area for bash-specific bugs.

## Common Pitfalls

### Pitfall 1: Bash 3.2 Incompatibility Sneaking In

**What goes wrong:** Developer has bash 5.x via Homebrew and uses bash 4+ features without realizing it. Code works locally but breaks on stock macOS.
**Why it happens:** `/usr/local/bin/bash` (or `/opt/homebrew/bin/bash`) is bash 5.x, but `/bin/bash` is 3.2 on macOS. If the hashbang says `#!/bin/bash`, the system bash (3.2) is used.
**How to avoid:** Run ShellCheck on all files. Use `#!/bin/bash` (not `#!/usr/bin/env bash` which may pick up bash 5). Test with `bash --version` to verify 3.2. Add a CI/Makefile target that runs tests with `/bin/bash` explicitly.
**Warning signs:** `declare -A`, `readarray`, `${var,,}`, `|&` appearing in source code.

### Pitfall 2: Unquoted Variables Causing Word Splitting

**What goes wrong:** A path or value with spaces gets split into multiple arguments. Example: `cd $WORKTREE_PATH` fails if path contains spaces.
**Why it happens:** Bash performs word splitting on unquoted variables by default.
**How to avoid:** Always double-quote variables: `"$var"`. ShellCheck catches this (SC2086). The only exception is intentional word splitting with arrays: `"${array[@]}"`.
**Warning signs:** ShellCheck warning SC2086 anywhere in the codebase.

### Pitfall 3: `set -e` Masking Errors in Conditionals

**What goes wrong:** `set -e` (exit on error) does not trigger inside `if` conditions, `&&` chains, or command substitutions used in conditionals. A function called in `if my_function; then` will NOT cause the script to exit even if commands inside `my_function` fail.
**Why it happens:** POSIX behavior: commands checked by `if`, `while`, `until`, `||`, or `&&` are exempt from `set -e`.
**How to avoid:** Use explicit return codes from functions. Check `$?` after critical operations. Use `set -euo pipefail` (pipefail catches failures in piped commands). Be aware that `set -u` may cause issues with `${var:-default}` patterns in bash 3.2.
**Warning signs:** Functions that should fail but silently succeed when called in conditionals.

### Pitfall 4: `date` Command Differences Between macOS and Linux

**What goes wrong:** `date -Iseconds` works on GNU/Linux but fails on macOS BSD date. `date -d` works on Linux but not macOS. The existing scripts use `date -Iseconds` which will fail on stock macOS.
**Why it happens:** macOS ships BSD date; Linux ships GNU date. Different flag sets.
**How to avoid:** Use `date -u +%Y-%m-%dT%H:%M:%SZ` for ISO 8601 timestamps (works on both). For epoch conversion, use `date +%s`. Never use `-I`, `-d`, or `--iso-8601`.
**Warning signs:** `date -I` or `date -d` in any script.

### Pitfall 5: Config File Sourcing Without Validation

**What goes wrong:** `.ralphrc` or `.gsd-ralphrc` is sourced directly with `source .ralphrc`, which executes arbitrary bash code. A malformed config file can crash the tool or execute unintended commands.
**Why it happens:** `source` runs the file as bash code. If a value contains unescaped characters, subshells, or commands, they execute.
**How to avoid:** Validate config files before sourcing. Use a restricted parser that only accepts `KEY=VALUE` lines (no command substitution, no subshells). Or read line-by-line with `IFS='=' read -r key value`.
**Warning signs:** Direct `source` of user-editable config files without prior validation.

### Pitfall 6: Tests Not Running in Isolation

**What goes wrong:** bats tests modify the real filesystem or git repo instead of a temporary test directory. Tests interfere with each other or with the developer's working state.
**Why it happens:** Test setup doesn't create isolated temp directories. Tests use `cd` to change to test fixtures but don't restore the working directory.
**How to avoid:** Use `setup()` to create a temp directory with `mktemp -d` and `cd` into it. Use `teardown()` to remove it. Use `bats-file`'s `temp_make` and `temp_del` helpers. Initialize a fresh git repo in the temp directory for tests that need git.
**Warning signs:** Tests that pass individually but fail when run as a suite.

## Code Examples

Verified patterns from official sources and established bash practices:

### Test Helper Setup (tests/test_helper/common.bash)

```bash
# Source: bats-core tutorial (https://bats-core.readthedocs.io/en/stable/tutorial.html)
# Common test setup -- loaded by every .bats file

_common_setup() {
    # Load bats libraries
    load 'bats-support/load'
    load 'bats-assert/load'
    load 'bats-file/load'

    # Get the containing directory of this file (test_helper/)
    # then resolve to the project root
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    PATH="$PROJECT_ROOT/bin:$PATH"

    # Create temp directory for test isolation
    TEST_TEMP_DIR="$(mktemp -d)"
    cd "$TEST_TEMP_DIR"
}

_common_teardown() {
    # Clean up temp directory
    if [[ -d "$TEST_TEMP_DIR" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Helper: create a minimal git repo for testing
create_test_repo() {
    git init .
    git commit --allow-empty -m "Initial commit"
}

# Helper: create a minimal GSD planning structure
create_gsd_structure() {
    mkdir -p .planning/phases
    cat > .planning/ROADMAP.md <<'EOF'
# Roadmap
- [ ] **Phase 1: Test Phase**
EOF
    cat > .planning/STATE.md <<'EOF'
# Project State
## Current Position
Phase: 1
EOF
}
```

### Example Test File (tests/init.bats)

```bash
# Source: bats-core best practices
setup() {
    load 'test_helper/common'
    _common_setup
    create_test_repo
    create_gsd_structure
}

teardown() {
    _common_teardown
}

@test "init creates .ralph directory" {
    run gsd-ralph init
    assert_success
    assert_dir_exists ".ralph"
}

@test "init creates .ralph/logs directory" {
    run gsd-ralph init
    assert_success
    assert_dir_exists ".ralph/logs"
}

@test "init fails outside git repo" {
    cd "$(mktemp -d)"  # Go to a non-git directory
    run gsd-ralph init
    assert_failure
    assert_output --partial "Not inside a git repository"
}

@test "init fails without .planning directory" {
    rm -rf .planning
    run gsd-ralph init
    assert_failure
    assert_output --partial "No .planning/ directory found"
}

@test "init detects missing dependencies" {
    # Mock a missing dependency by manipulating PATH
    PATH="/usr/bin:/bin"  # Exclude typical ralph install locations
    run gsd-ralph init
    assert_failure
    assert_output --partial "missing"
}

@test "init detects typescript project" {
    echo '{"scripts":{"test":"vitest","build":"tsc"}}' > package.json
    touch tsconfig.json
    run gsd-ralph init
    assert_success
    assert_output --partial "typescript"
}

@test "init is idempotent with --force" {
    run gsd-ralph init
    assert_success
    run gsd-ralph init --force
    assert_success
}

@test "init refuses to reinitialize without --force" {
    run gsd-ralph init
    assert_success
    run gsd-ralph init
    assert_success  # Should succeed with a warning, not error
    assert_output --partial "already exists"
}
```

### Makefile Targets

```makefile
# Makefile for gsd-ralph

BATS := ./tests/bats/bin/bats
SHELLCHECK := shellcheck
SRC_FILES := bin/gsd-ralph $(wildcard lib/*.sh) $(wildcard lib/commands/*.sh)

.PHONY: test lint install clean

test:
	$(BATS) tests/*.bats

lint:
	$(SHELLCHECK) -s bash $(SRC_FILES)

check: lint test

install:
	@echo "Installing gsd-ralph..."
	ln -sf "$(PWD)/bin/gsd-ralph" /usr/local/bin/gsd-ralph
	@echo "Installed. Run 'gsd-ralph --help' to verify."

uninstall:
	rm -f /usr/local/bin/gsd-ralph
```

### Template Rendering Function

```bash
# lib/templates.sh -- Template rendering with {{VARIABLE}} substitution

render_template() {
    local template="$1"
    local output="$2"
    shift 2
    # Remaining args are KEY=VALUE pairs

    if [[ ! -f "$template" ]]; then
        die "Template not found: $template"
    fi

    local content
    content=$(<"$template")

    local pair key value
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        # Use bash parameter expansion for substitution
        # This avoids sed delimiter issues with special chars in values
        content="${content//\{\{${key}\}\}/${value}}"
    done

    printf '%s\n' "$content" > "$output"
}
```

### Portable Date Function

```bash
# lib/common.sh (continued)

# ISO 8601 timestamp that works on both macOS and Linux
iso_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `date -Iseconds` (GNU only) | `date -u +%Y-%m-%dT%H:%M:%SZ` | Always (POSIX standard) | Portable timestamps across macOS/Linux |
| Bash heredoc variable interpolation | `{{VARIABLE}}` sed/parameter expansion substitution | Common pattern in modern bash tools | Avoids escaping issues, keeps templates as standalone files |
| `#!/usr/bin/env bash` | `#!/bin/bash` for macOS compatibility | Project decision | Ensures macOS system bash (3.2) is used, not Homebrew bash |
| Manual test scripts | bats-core 1.13.0 | bats-core actively maintained | TAP-compliant, bash 3.2 compatible, rich assertion ecosystem |
| Original scripts (monolithic) | bin/lib/commands structure | This rebuild | Testable, maintainable, extensible |

**Deprecated/outdated:**
- **shunit2:** Older bash test framework; less actively maintained than bats-core. Use bats-core.
- **`which` command:** Not POSIX-standard; behavior varies. Use `command -v` instead.
- **`echo -e`:** Behavior varies across platforms and shells. Use `printf` for formatted output.

## Open Questions

1. **Should `.gsd-ralphrc` be the per-project config file name?**
   - What we know: Ralph uses `.ralphrc` for its own config. The project research suggests `.gsd-ralphrc` for gsd-ralph-specific config (separate from Ralph's `.ralphrc`).
   - What's unclear: Whether gsd-ralph should generate the `.ralphrc` (Ralph's config) at init time, or only its own `.gsd-ralphrc`, or both.
   - Recommendation: Generate both. `.ralphrc` with project-detected settings (test command, etc.) from the template. `.gsd-ralphrc` (or just detect from `.ralph/config` inside the `.ralph/` directory) for gsd-ralph-specific settings if needed. For Phase 1, focus on generating `.ralphrc` since that is what Ralph reads. Defer `.gsd-ralphrc` until there are gsd-ralph-specific settings that need persistence.

2. **How to handle `ralph` not being installed during init?**
   - What we know: `ralph` is listed as a required dependency. But a user might want to initialize gsd-ralph first, then install Ralph.
   - What's unclear: Should `ralph` missing be a hard error or a warning?
   - Recommendation: Make it a warning, not a hard error. The init command creates config files; Ralph is only needed at execution time. Print a clear warning: "ralph not found. You'll need it before running 'gsd-ralph execute'."

3. **Where do generated files go -- `.ralph/` in project root?**
   - What we know: The existing workflow puts PROMPT.md, AGENT.md, fix_plan.md in `.ralph/`. The `.ralphrc` goes in the project root.
   - What's unclear: Whether `gsd-ralph init` should create the main project `.ralph/` directory or just a `.gsd-ralph/` config directory.
   - Recommendation: Create `.ralph/` with PROMPT.md and AGENT.md (matching existing Ralph expectations). Place `.ralphrc` in project root (matching Ralph's convention). The `.ralph/` directory is Ralph's standard location. Do not introduce a separate `.gsd-ralph/` directory for Phase 1 -- keep it simple and aligned with Ralph's conventions.

## Sources

### Primary (HIGH confidence)
- [bats-core GitHub](https://github.com/bats-core/bats-core) -- v1.13.0 release, bash 3.2 compatibility confirmed
- [bats-core tutorial](https://bats-core.readthedocs.io/en/stable/tutorial.html) -- project structure, git submodule setup, library loading
- [bats-file GitHub](https://github.com/bats-core/bats-file) -- filesystem assertions (assert_file_exists, temp_make, temp_del)
- Existing codebase: `scripts/ralph-worktrees.sh`, `ralph-execute.sh` -- reference implementation patterns
- Existing codebase: `templates/ralphrc.template` -- current `.ralphrc` format and fields
- `.planning/research/STACK.md` -- stack decisions, bash 3.2 compatibility checklist
- `.planning/research/PITFALLS.md` -- 14 identified pitfalls, Phase 1-relevant items
- `.planning/REQUIREMENTS.md` -- INIT-01, INIT-02, INIT-03, XCUT-01 specifications

### Secondary (MEDIUM confidence)
- [bats submodule setup gist](https://gist.github.com/natbusa/1e4fc7c0b089f74560a6003dcd60dd9b) -- alternative submodule directory layout
- [getopts with subcommands gist](https://gist.github.com/pablordoricaw/9c3f89a66d654fdbdcf762eafb048842) -- dispatch pattern with per-subcommand option parsing
- [ShellCheck GitHub](https://github.com/koalaman/shellcheck) -- bash linting capabilities, CI integration

### Tertiary (LOW confidence)
- Project detection heuristics for less common ecosystems (Elixir, Gradle, Maven) -- based on training data knowledge of marker files; not verified against real projects of those types

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- bats-core version verified (1.13.0), bash 3.2 compat confirmed, ShellCheck well-established
- Architecture: HIGH -- bin/lib/commands is standard bash CLI pattern; entry point self-location is well-documented
- Project detection: MEDIUM -- common ecosystems (Node/TS, Rust, Go, Python) are straightforward; edge cases (monorepos, multiple package managers, mixed projects) may need refinement
- Pitfalls: HIGH -- bash 3.2 traps are well-documented; `date` portability is a known issue; testing isolation patterns are standard

**Research date:** 2026-02-13
**Valid until:** 2026-03-13 (stable domain; bash CLI patterns do not change rapidly)
