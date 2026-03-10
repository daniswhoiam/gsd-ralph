# Phase 15: Core Installer - Research

**Researched:** 2026-03-10
**Domain:** Bash installer scripting, idempotent file operations, config merging, prerequisite detection
**Confidence:** HIGH

## Summary

Phase 15 builds a single-command installer that copies gsd-ralph components into any GSD project. The installer is a pure Bash script (no npm, no curl-pipe-bash) that checks prerequisites, copies files to three target directories (`scripts/ralph/`, `.claude/commands/gsd/`, `.claude/skills/gsd-ralph-autopilot/`), merges a `ralph` config section into `.planning/config.json`, verifies the installation, and prints a colored summary with next-step guidance.

The codebase has two distinct subsystems with different path architectures. The `bin/` + `lib/` + `templates/` subsystem is the v1.x CLI (`gsd-ralph init`, `gsd-ralph execute`, etc.) and is NOT part of the install scope -- it was superseded by the v2.0 integration layer. The `scripts/` subsystem (ralph-launcher.sh, assemble-context.sh, validate-config.sh, ralph-hook.sh) plus `.claude/commands/gsd/ralph.md` and `.claude/skills/gsd-ralph-autopilot/SKILL.md` are the v2.0 components that need to be installed. Phase 14 already made scripts location-independent via `RALPH_SCRIPTS_DIR`, so they work from `scripts/ralph/` in the target repo.

One critical detail: the `.claude/commands/gsd/ralph.md` command file hardcodes `bash scripts/ralph-launcher.sh $ARGUMENTS`. The installed version must use `bash scripts/ralph/ralph-launcher.sh $ARGUMENTS` instead. The installer must perform this path adjustment when copying the command file to the target repo.

**Primary recommendation:** Create a standalone `install.sh` at the repo root that can be executed via `bash install.sh` from inside the target project directory (after cloning or downloading gsd-ralph). The installer should be a single file with no dependencies beyond bash, jq, and git (the same prerequisites it checks for).

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| INST-01 | User can install gsd-ralph into any repo with a single terminal command | Single `install.sh` script; user clones gsd-ralph repo, then runs `bash /path/to/gsd-ralph/install.sh` from their project root |
| INST-02 | Installer checks for GSD framework and displays version guidance if missing | Check for `.planning/` directory and `.planning/config.json`; display GSD install instructions if missing |
| INST-03 | Installer checks for jq, git, and bash >= 3.2 with actionable fix instructions | Use `command -v` for jq/git; parse `$BASH_VERSION` for >= 3.2; print install hints per tool |
| INST-04 | Re-running the installer is safe -- identical files are skipped, no data loss | Use `cmp -s` for file comparison; skip files that match; report "already up to date" |
| INST-05 | Installer adds ralph config section to .planning/config.json without overwriting existing settings | Use jq `*` (recursive merge) operator; check if `.ralph` key already exists before merging |
| INST-06 | Installer copies all Ralph components (scripts, skills, commands) to target repo | Defined file manifest covering 4 scripts + 1 command file + 1 skill file = 6 files total |
| INST-07 | Post-install verification confirms all files exist and are executable | Loop over manifest checking `-f` and `-x` for scripts; `-f` for non-script files |
| INST-08 | Installer displays clear output with next-step guidance after completion | Colored output using existing color pattern from `lib/common.sh`; count of files installed; next-step instructions |
</phase_requirements>

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | Installer script language | macOS system bash compatibility required; project constraint |
| jq | any | JSON config merging (INST-05) | Already a dependency; used for `.planning/config.json` manipulation |
| git | any | Repo detection, project root resolution | Already a dependency |
| cmp | system | Binary file comparison for idempotency | POSIX standard, available everywhere; faster than checksum for equality |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Bats | 1.x (vendored) | Test framework for installer tests | Testing the installer itself |
| mktemp | system | Safe temporary file creation | Needed for jq config merge (atomic write) |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `cmp -s` for file comparison | `shasum`/`md5` checksums | `cmp -s` is simpler, faster for binary equality; checksums are overkill for same-file comparison |
| `jq` for config merge | `sed`/`awk` for JSON | `jq` is already a hard dependency; `sed` on JSON is fragile and error-prone |
| Standalone `install.sh` | npm package / npx | Out of scope per REQUIREMENTS.md; pure Bash tool should not require npm |
| File-by-file copy | tar archive | Unnecessary complexity for 6 files; individual copy allows granular skip/update reporting |

## Architecture Patterns

### Installer File Location and Invocation

The installer script (`install.sh`) lives at the root of the gsd-ralph repo. Users invoke it from their target project:

```
# User's workflow
cd /path/to/my-gsd-project
bash /path/to/gsd-ralph/install.sh
```

Or after cloning:
```
git clone https://github.com/[owner]/gsd-ralph.git /tmp/gsd-ralph
bash /tmp/gsd-ralph/install.sh
```

The installer resolves its own directory via `BASH_SOURCE[0]` (the same proven pattern used in `bin/gsd-ralph` and `scripts/ralph-launcher.sh`) to find source files relative to itself. The target directory is the current working directory (`pwd`), which must be the root of a GSD project.

### Install Manifest

The installer copies exactly these files:

| Source (relative to gsd-ralph repo) | Target (relative to target project root) | Executable? | Notes |
|--------------------------------------|------------------------------------------|-------------|-------|
| `scripts/ralph-launcher.sh` | `scripts/ralph/ralph-launcher.sh` | Yes | Core autopilot launcher |
| `scripts/assemble-context.sh` | `scripts/ralph/assemble-context.sh` | Yes | GSD context assembly |
| `scripts/validate-config.sh` | `scripts/ralph/validate-config.sh` | Yes | Config validation |
| `scripts/ralph-hook.sh` | `scripts/ralph/ralph-hook.sh` | Yes | PreToolUse hook |
| `.claude/commands/gsd/ralph.md` | `.claude/commands/gsd/ralph.md` | No | Slash command definition (path-adjusted) |
| `.claude/skills/gsd-ralph-autopilot/SKILL.md` | `.claude/skills/gsd-ralph-autopilot/SKILL.md` | No | Autopilot behavior rules |

**NOT installed** (out of scope):
- `bin/gsd-ralph`, `bin/ralph-stop` -- v1.x CLI entry points, superseded
- `lib/` directory -- v1.x CLI libraries, not used by v2.0 launcher
- `templates/` directory -- used by v1.x `gsd-ralph init`, not by v2.0
- `scripts/ralph-execute.sh`, `scripts/ralph-merge.sh`, etc. -- DEPRECATED legacy scripts
- `.ralphrc` -- not installed; the launcher reads config from `.planning/config.json`

### Pattern 1: BASH_SOURCE Self-Resolution for Installer
**What:** Installer resolves its own location to find source files.
**When to use:** Always -- the installer must know where gsd-ralph repo files are.
**Example:**
```bash
# Resolve installer's own directory (follows symlinks)
INSTALLER_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$INSTALLER_SOURCE" ]; do
    INSTALLER_DIR="$(cd "$(dirname "$INSTALLER_SOURCE")" && pwd)"
    INSTALLER_SOURCE="$(readlink "$INSTALLER_SOURCE")"
    [[ "$INSTALLER_SOURCE" != /* ]] && INSTALLER_SOURCE="$INSTALLER_DIR/$INSTALLER_SOURCE"
done
GSD_RALPH_REPO="$(cd "$(dirname "$INSTALLER_SOURCE")" && pwd)"
```

### Pattern 2: Idempotent File Copy with Skip Reporting
**What:** Copy a file only if it differs from the target; report skip/update/install.
**When to use:** Every file in the manifest.
**Example:**
```bash
# Install a single file with idempotency
# Args: source_path, target_path, make_executable (true/false)
install_file() {
    local src="$1" dst="$2" executable="${3:-false}"
    local dst_dir
    dst_dir="$(dirname "$dst")"

    mkdir -p "$dst_dir"

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        # File already exists and is identical
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    cp "$src" "$dst"
    if [ "$executable" = "true" ]; then
        chmod +x "$dst"
    fi
    INSTALLED=$((INSTALLED + 1))
}
```

### Pattern 3: Config Merge Without Overwrite (INST-05)
**What:** Add `ralph` key to existing config.json only if it doesn't exist.
**When to use:** Config setup during installation.
**Example:**
```bash
merge_ralph_config() {
    local config_file="$1"

    # Check if ralph key already exists
    if jq -e '.ralph' "$config_file" >/dev/null 2>&1; then
        echo "Ralph config already exists in config.json, skipping"
        return 0
    fi

    # Add ralph section with defaults
    local ralph_defaults='{"ralph":{"enabled":true,"max_turns":50,"permission_tier":"default","timeout_minutes":30}}'
    local tmp_file
    tmp_file="$(mktemp)"

    jq --argjson ralph "$ralph_defaults" '. * $ralph' "$config_file" > "$tmp_file" && \
        mv "$tmp_file" "$config_file"
}
```

### Pattern 4: Prerequisite Check with Actionable Messages
**What:** Check each prerequisite and provide specific install instructions.
**When to use:** Before any file operations.
**Example:**
```bash
check_prerequisites() {
    local missing=0

    # Check bash version (>= 3.2)
    local bash_major bash_minor
    bash_major="${BASH_VERSINFO[0]}"
    bash_minor="${BASH_VERSINFO[1]}"
    if [ "$bash_major" -lt 3 ] || { [ "$bash_major" -eq 3 ] && [ "$bash_minor" -lt 2 ]; }; then
        print_error "Bash >= 3.2 required (found $BASH_VERSION)"
        printf "  macOS: Bash 3.2 is the system default\n" >&2
        printf "  Linux: Install via your package manager\n" >&2
        missing=$((missing + 1))
    fi

    # Check git
    if ! command -v git >/dev/null 2>&1; then
        print_error "git is not installed"
        printf "  Install: https://git-scm.com/download\n" >&2
        missing=$((missing + 1))
    fi

    # Check jq
    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is not installed"
        printf "  macOS: brew install jq\n" >&2
        printf "  Linux: apt install jq / yum install jq\n" >&2
        missing=$((missing + 1))
    fi

    # Check GSD framework
    if [ ! -d ".planning" ]; then
        print_error "GSD framework not detected (no .planning/ directory)"
        printf "  Install GSD first: https://github.com/get-shit-done/get-shit-done\n" >&2
        printf "  Then run: /gsd:new-project\n" >&2
        missing=$((missing + 1))
    fi

    if [ ! -f ".planning/config.json" ]; then
        print_error "GSD config not found (.planning/config.json missing)"
        printf "  Run /gsd:new-project to initialize GSD in this repo\n" >&2
        missing=$((missing + 1))
    fi

    return $missing
}
```

### Pattern 5: Path Adjustment for Command File
**What:** When copying `ralph.md`, adjust the launcher path from `scripts/` to `scripts/ralph/`.
**When to use:** During command file installation only.
**Example:**
```bash
install_command_file() {
    local src="$GSD_RALPH_REPO/.claude/commands/gsd/ralph.md"
    local dst=".claude/commands/gsd/ralph.md"

    mkdir -p "$(dirname "$dst")"

    # Adjust path: scripts/ralph-launcher.sh -> scripts/ralph/ralph-launcher.sh
    sed 's|bash scripts/ralph-launcher\.sh|bash scripts/ralph/ralph-launcher.sh|g' "$src" > "$dst"
}
```

### Recommended Installer Structure

```
install.sh                    # Single-file installer at repo root
  |
  |-- resolve_self()          # Find gsd-ralph repo via BASH_SOURCE
  |-- check_prerequisites()   # INST-02, INST-03: validate environment
  |-- install_scripts()       # INST-06: copy 4 scripts to scripts/ralph/
  |-- install_command()       # INST-06: copy ralph.md with path adjustment
  |-- install_skill()         # INST-06: copy SKILL.md
  |-- merge_config()          # INST-05: add ralph section to config.json
  |-- verify_install()        # INST-07: check all files exist and are executable
  |-- print_summary()         # INST-08: colored output with next steps
```

### Anti-Patterns to Avoid
- **Copying the entire scripts/ directory:** Only 4 of 9 scripts are v2.0 core. The other 5 are DEPRECATED v1.x scripts that should not be installed.
- **Installing bin/ or lib/ directories:** These are the v1.x CLI subsystem, not needed for v2.0 autopilot.
- **Using `cp -r` for everything:** Loses granular idempotency tracking. Copy files individually.
- **Modifying settings.local.json at install time:** Per REQUIREMENTS.md "Out of Scope" -- the launcher handles hooks dynamically at runtime via `_install_hook` / `_remove_hook`.
- **Creating `.ralph/` directory or `.ralphrc` at install time:** These are runtime artifacts. The `.ralph/` directory is created by the launcher when it runs. The `.ralphrc` was a v1.x pattern; v2.0 uses `.planning/config.json`.
- **Using `realpath`:** Not available on stock macOS. Use `dirname` + `cd && pwd` pattern.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| File comparison for idempotency | Custom checksum logic | `cmp -s` | POSIX standard, returns 0 if files are identical, no hashing overhead |
| JSON config merging | sed/awk JSON manipulation | `jq` with `*` operator | Already a dependency; sed on JSON is fragile and will break on edge cases |
| Color output | Custom ANSI code management | Copy color pattern from `lib/common.sh` | Already proven, handles non-terminal detection |
| Symlink-following path resolution | `realpath` or custom logic | Copy BASH_SOURCE pattern from `bin/gsd-ralph` | Already tested, works on macOS Bash 3.2 |
| Bash version comparison | String comparison or `sort -V` | `$BASH_VERSINFO` array comparison | Built-in array, no parsing needed, available in all Bash 2.0+ |

**Key insight:** The existing codebase already has proven patterns for every technical challenge the installer faces. Copy patterns, don't invent new ones.

## Common Pitfalls

### Pitfall 1: Command File Path Not Adjusted
**What goes wrong:** Installing `ralph.md` as-is leaves `bash scripts/ralph-launcher.sh` in the command, but installed scripts are at `scripts/ralph/ralph-launcher.sh`. The `/gsd:ralph` command fails with "No such file."
**Why it happens:** Direct file copy without considering the different directory layout in installed repos.
**How to avoid:** Use `sed` to replace the path during installation. Only one line needs adjustment: the `bash scripts/ralph-launcher.sh` invocation.
**Warning signs:** `/gsd:ralph execute-phase N --dry-run` fails with "ralph-launcher.sh: No such file or directory."

### Pitfall 2: Config Merge Overwrites Existing Ralph Settings
**What goes wrong:** User has custom ralph settings (e.g., `max_turns: 100`). Installer overwrites with defaults.
**Why it happens:** Using jq `+` (shallow merge) instead of checking for key existence first.
**How to avoid:** Check `jq -e '.ralph'` first. If the key exists, skip the config merge entirely. Do not attempt partial merging of individual sub-keys.
**Warning signs:** User's custom `max_turns` or `permission_tier` reverts to defaults after re-install.

### Pitfall 3: Installer Run From Wrong Directory
**What goes wrong:** User runs installer from inside the gsd-ralph repo instead of from their target project.
**Why it happens:** Ambiguity about which directory is "current."
**How to avoid:** Validate that `pwd` is NOT the gsd-ralph repo itself (check that the install source directory != the current directory). Also validate that `.planning/` exists in `pwd` (GSD check already covers this).
**Warning signs:** Installer installs into itself, creating `scripts/ralph/` inside the gsd-ralph repo.

### Pitfall 4: File Permissions Not Set on Scripts
**What goes wrong:** Scripts are copied but not executable. `bash scripts/ralph/ralph-launcher.sh` still works (explicit bash invocation), but `./scripts/ralph/ralph-launcher.sh` fails.
**Why it happens:** `cp` preserves permissions from source, but only if source has them. If the gsd-ralph repo was downloaded as a zip (not cloned), source files may lack execute permission.
**How to avoid:** Explicitly `chmod +x` all `.sh` files after copying, regardless of source permissions.
**Warning signs:** Permission denied errors when scripts are invoked directly (without `bash` prefix).

### Pitfall 5: jq Not Available During Config Merge
**What goes wrong:** Installer passes prerequisite check for jq but jq fails during config merge due to malformed config.json.
**Why it happens:** `.planning/config.json` exists but contains invalid JSON.
**How to avoid:** Validate JSON syntax before attempting merge: `jq '.' .planning/config.json > /dev/null 2>&1`. Report specific error if invalid.
**Warning signs:** Cryptic jq parse error during installation, leaving config.json in corrupted state.

### Pitfall 6: Atomic Config Write Failure
**What goes wrong:** jq writes to a temp file, but `mv` fails (e.g., cross-filesystem). Config.json is left unchanged but installer reports success.
**Why it happens:** `mktemp` may create temp files on a different filesystem than `.planning/`.
**How to avoid:** Create the temp file in the same directory as the target: `mktemp .planning/config.json.XXXXXX`. This ensures `mv` is an atomic rename on the same filesystem.
**Warning signs:** Config merge appears to succeed but ralph config is missing from config.json.

## Code Examples

Verified patterns from the existing codebase:

### Color Output (from lib/common.sh)
```bash
# Source: lib/common.sh lines 5-21
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

print_success() { printf "${GREEN}[ok]${NC} %s\n" "$1"; }
print_warning() { printf "${YELLOW}[warn]${NC} %s\n" "$1" >&2; }
print_error()   { printf "${RED}[error]${NC} %s\n" "$1" >&2; }
print_info()    { printf "${BLUE}[info]${NC} %s\n" "$1"; }
```

### BASH_SOURCE Self-Resolution (from bin/gsd-ralph)
```bash
# Source: bin/gsd-ralph lines 10-17
SCRIPT_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SCRIPT_SOURCE" ]; do
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
    SCRIPT_SOURCE="$(readlink "$SCRIPT_SOURCE")"
    [[ "$SCRIPT_SOURCE" != /* ]] && SCRIPT_SOURCE="$SCRIPT_DIR/$SCRIPT_SOURCE"
done
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
GSD_RALPH_REPO="$(dirname "$SCRIPT_DIR")"  # If install.sh is at repo root, just use SCRIPT_DIR
```

Note: If `install.sh` is at the repo root (not in a subdirectory), the resolution is simpler:
```bash
GSD_RALPH_REPO="$(cd "$(dirname "$INSTALLER_SOURCE")" && pwd)"
```

### Bash Version Check Using BASH_VERSINFO
```bash
# BASH_VERSINFO is a built-in array available in all Bash 2.0+
# BASH_VERSINFO[0] = major, BASH_VERSINFO[1] = minor
check_bash_version() {
    local required_major=3
    local required_minor=2
    local actual_major="${BASH_VERSINFO[0]}"
    local actual_minor="${BASH_VERSINFO[1]}"

    if [ "$actual_major" -lt "$required_major" ] || \
       { [ "$actual_major" -eq "$required_major" ] && [ "$actual_minor" -lt "$required_minor" ]; }; then
        print_error "Bash >= ${required_major}.${required_minor} required (found ${BASH_VERSION})"
        return 1
    fi
    return 0
}
```

### Config Merge with jq (safe, non-overwriting)
```bash
# Source: Pattern derived from existing _install_hook in ralph-launcher.sh lines 354-378
merge_ralph_config() {
    local config_file="$1"

    # Guard: check if ralph key already exists
    if jq -e '.ralph' "$config_file" >/dev/null 2>&1; then
        print_info "Ralph config already present in config.json"
        return 0
    fi

    # Validate existing JSON before modifying
    if ! jq '.' "$config_file" >/dev/null 2>&1; then
        print_error "config.json contains invalid JSON -- cannot merge"
        return 1
    fi

    # Merge ralph defaults (same directory temp file for atomic mv)
    local tmp_file
    tmp_file="$(mktemp "$(dirname "$config_file")/config.json.XXXXXX")"

    if jq '. + {"ralph":{"enabled":true,"max_turns":50,"permission_tier":"default","timeout_minutes":30}}' \
        "$config_file" > "$tmp_file"; then
        mv "$tmp_file" "$config_file"
        print_success "Added ralph config to config.json"
    else
        rm -f "$tmp_file"
        print_error "Failed to merge ralph config"
        return 1
    fi
}
```

### Post-Install Verification Loop
```bash
verify_installation() {
    local target_root="$1"
    local errors=0

    # Scripts must exist and be executable
    local script
    for script in ralph-launcher.sh assemble-context.sh validate-config.sh ralph-hook.sh; do
        local path="$target_root/scripts/ralph/$script"
        if [ ! -f "$path" ]; then
            print_error "Missing: $path"
            errors=$((errors + 1))
        elif [ ! -x "$path" ]; then
            print_error "Not executable: $path"
            errors=$((errors + 1))
        fi
    done

    # Non-script files must exist
    local file
    for file in ".claude/commands/gsd/ralph.md" ".claude/skills/gsd-ralph-autopilot/SKILL.md"; do
        if [ ! -f "$target_root/$file" ]; then
            print_error "Missing: $target_root/$file"
            errors=$((errors + 1))
        fi
    done

    # Config must have ralph key
    if ! jq -e '.ralph' "$target_root/.planning/config.json" >/dev/null 2>&1; then
        print_error "Ralph config missing from .planning/config.json"
        errors=$((errors + 1))
    fi

    return $errors
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `gsd-ralph init` (v1.x CLI) | `install.sh` standalone installer | Phase 15 (this phase) | No CLI dependency; works before Ralph is "installed" |
| `$PROJECT_ROOT/scripts/` hardcoded paths | `$RALPH_SCRIPTS_DIR` auto-detection | Phase 14 (completed) | Scripts work from `scripts/ralph/` in installed repos |
| Claude Code plugin distribution | Bash installer | REQUIREMENTS.md decision | Plugin namespacing breaks `/gsd:ralph` command |
| npm/npx distribution | `git clone` + `bash install.sh` | REQUIREMENTS.md decision | Pure Bash tool; npm adds conceptual mismatch |

**Deprecated/outdated patterns to NOT replicate:**
- `gsd-ralph init` creates `.ralph/` directory and `.ralphrc` -- v1.x pattern. The v2.0 launcher uses `.planning/config.json` for configuration and creates `.ralph/` at runtime.
- `lib/commands/init.sh` dependency checking includes `python3` and `ralph` -- these are v1.x requirements. The v2.0 installer only needs bash, git, and jq.
- `templates/ralphrc.template` rendering -- not used in v2.0 flow.

## Open Questions

1. **Should the installer also copy `bin/ralph-stop`?**
   - What we know: `bin/ralph-stop` is a tiny script (9 lines) that touches `.ralph/.stop` to request graceful stop. It uses `git rev-parse --show-toplevel` for project root detection, so it's already location-independent.
   - What's unclear: Whether users of installed repos need this. The success criteria don't mention it.
   - Recommendation: Do NOT include in v2.1 scope. The `.ralph/.stop` file can be created manually (`touch .ralph/.stop`) if needed. Add to v2.2 if users request it.

2. **Should the installer support an `--uninstall` or `--upgrade` flag?**
   - What we know: REQUIREMENTS.md explicitly defers LIFE-01 (uninstall) and LIFE-02 (upgrade) to v2.2+.
   - Recommendation: Do NOT implement. Out of scope per requirements.

3. **How should the installer handle existing `.claude/commands/gsd/ralph.md`?**
   - What we know: The target repo may already have a `ralph.md` from a previous install. Idempotency (INST-04) requires that re-running produces no changes.
   - Recommendation: Use the same `cmp -s` pattern as scripts. But since `ralph.md` gets `sed`-modified during install (path adjustment), the comparison must be against the modified version, not the source. Generate the modified version first, then compare.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Bats 1.x (vendored at tests/bats/) |
| Config file | None (bats uses convention) |
| Quick run command | `./tests/bats/bin/bats tests/installer.bats` |
| Full suite command | `./tests/bats/bin/bats tests/*.bats` |

### Phase Requirements -> Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| INST-01 | Single command installs all files | integration | `./tests/bats/bin/bats tests/installer.bats -f "installs all"` | No -- Wave 0 |
| INST-02 | GSD framework detection with guidance | unit | `./tests/bats/bin/bats tests/installer.bats -f "GSD"` | No -- Wave 0 |
| INST-03 | jq/git/bash version checks | unit | `./tests/bats/bin/bats tests/installer.bats -f "prerequisite"` | No -- Wave 0 |
| INST-04 | Idempotent re-run (no changes, no errors) | integration | `./tests/bats/bin/bats tests/installer.bats -f "idempotent"` | No -- Wave 0 |
| INST-05 | Config merge without overwrite | unit | `./tests/bats/bin/bats tests/installer.bats -f "config"` | No -- Wave 0 |
| INST-06 | All components copied to correct locations | integration | `./tests/bats/bin/bats tests/installer.bats -f "copies"` | No -- Wave 0 |
| INST-07 | Post-install verification | unit | `./tests/bats/bin/bats tests/installer.bats -f "verify"` | No -- Wave 0 |
| INST-08 | Colored summary with next steps | integration | `./tests/bats/bin/bats tests/installer.bats -f "summary"` | No -- Wave 0 |

### Sampling Rate
- **Per task commit:** `./tests/bats/bin/bats tests/installer.bats`
- **Per wave merge:** `./tests/bats/bin/bats tests/*.bats`
- **Phase gate:** Full suite green (319+ existing tests + new installer tests) before `/gsd:verify-work`

### Wave 0 Gaps
- [ ] `tests/installer.bats` -- new test file covering all INST-* requirements
- [ ] Test helpers for creating mock GSD projects in temp directories (may extend `tests/test_helper/common.bash`)
- [ ] `install.sh` -- the installer script itself (does not exist yet)

## Scope Sizing

| What | Count | Complexity |
|------|-------|-----------|
| Files to create | 1 (`install.sh`) | MEDIUM -- ~150-200 lines, multiple concerns |
| Files to modify | 0 | N/A |
| Test files to create | 1 (`tests/installer.bats`) | MEDIUM -- ~200-250 lines, needs temp project setup |
| Total new code | ~400-450 lines | MEDIUM |
| Risk areas | Config merge, path adjustment, idempotency edge cases | LOW-MEDIUM |

**Estimated plan count:** 1-2 plans. The installer is a single script with clear concerns that can be built in one wave. A second plan may be needed if testing reveals edge cases.

## Sources

### Primary (HIGH confidence)
- `scripts/ralph-launcher.sh` -- direct inspection of RALPH_SCRIPTS_DIR pattern (Phase 14 result)
- `bin/gsd-ralph` -- proven BASH_SOURCE self-resolution pattern
- `lib/common.sh` -- color output pattern
- `ralph-launcher.sh` lines 354-378 -- `_install_hook` / `_remove_hook` pattern for JSON merge
- `.claude/commands/gsd/ralph.md` -- hardcoded path `scripts/ralph-launcher.sh` that needs adjustment
- `.planning/REQUIREMENTS.md` -- explicit scope boundaries (no uninstall, no npm, no curl-pipe-bash)
- `.planning/config.json` -- existing config structure showing ralph section format

### Secondary (MEDIUM confidence)
- [Idempotent Bash Scripts](https://arslan.io/2019/07/03/how-to-write-idempotent-bash-scripts/) -- patterns for idempotent file operations
- [jq Manual](https://jqlang.org/manual/) -- `*` operator for recursive merge, `+` for shallow merge
- [How to Merge JSON Files Using jq](https://copyprogramming.com/howto/how-to-merge-json-files-using-jq-or-any-tool) -- jq merge patterns

### Tertiary (LOW confidence)
- None -- all findings are directly verifiable from the codebase or official tool documentation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- all tools already in use in the project
- Architecture: HIGH -- installer copies files to locations defined by success criteria; patterns copied from existing code
- Pitfalls: HIGH -- identified through direct code inspection of existing path references and config patterns
- Install manifest: HIGH -- success criteria explicitly list target directories; deprecated files identified via DEPRECATED headers in source

**Research date:** 2026-03-10
**Valid until:** Indefinite (Bash file operations and jq are stable; no external dependencies to version)
