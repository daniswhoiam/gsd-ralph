#!/usr/bin/env bash
# install.sh -- Single-command installer for gsd-ralph
# Copies Ralph autopilot components into any GSD project.
#
# Usage:
#   cd /path/to/your-gsd-project
#   bash /path/to/gsd-ralph/install.sh
#
# Prerequisites: bash >= 3.2, git, jq, GSD framework (.planning/)
# Bash 3.2 compatible (macOS system bash)

set -euo pipefail

# --- Self-resolution: find gsd-ralph repo root ---
INSTALLER_SOURCE="${BASH_SOURCE[0]}"
while [ -L "$INSTALLER_SOURCE" ]; do
    INSTALLER_DIR="$(cd "$(dirname "$INSTALLER_SOURCE")" && pwd)"
    INSTALLER_SOURCE="$(readlink "$INSTALLER_SOURCE")"
    [[ "$INSTALLER_SOURCE" != /* ]] && INSTALLER_SOURCE="$INSTALLER_DIR/$INSTALLER_SOURCE"
done
GSD_RALPH_REPO="$(cd "$(dirname "$INSTALLER_SOURCE")" && pwd)"

# --- Color output (adapted from lib/common.sh) ---
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

# --- Prerequisite checks (INST-02, INST-03) ---
# Checks ALL prerequisites before returning; does not exit on first failure.
check_prerequisites() {
    local missing=0

    # Check bash version >= 3.2
    local bash_major="${BASH_VERSINFO[0]}"
    local bash_minor="${BASH_VERSINFO[1]}"
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

    # Check config.json
    if [ ! -f ".planning/config.json" ]; then
        print_error "GSD config not found (.planning/config.json missing)"
        printf "  Run /gsd:new-project to initialize GSD in this repo\n" >&2
        missing=$((missing + 1))
    fi

    # Self-install guard: source dir must not be the same as target dir
    local resolved_source resolved_target
    resolved_source="$(cd "$GSD_RALPH_REPO" && pwd)"
    resolved_target="$(pwd)"
    if [ "$resolved_source" = "$resolved_target" ]; then
        print_error "Cannot install into the gsd-ralph repo itself (source and target are the same directory)"
        printf "  Run this installer from your target project directory instead:\n" >&2
        printf "  cd /path/to/your-project && bash %s\n" "$0" >&2
        missing=$((missing + 1))
    fi

    return $missing
}

# --- Idempotent file copy (INST-04, INST-06) ---
# Args: source_path, target_path, make_executable (true/false)
install_file() {
    local src="$1" dst="$2" executable="${3:-false}"
    local dst_dir
    dst_dir="$(dirname "$dst")"

    mkdir -p "$dst_dir"

    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        # File already exists and is identical -- skip
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    cp "$src" "$dst"
    if [ "$executable" = "true" ]; then
        chmod +x "$dst"
    fi
    INSTALLED=$((INSTALLED + 1))
}

# --- Command file installer with path adjustment (INST-06) ---
# Adjusts scripts/ralph-launcher.sh -> scripts/ralph/ralph-launcher.sh
install_command_file() {
    local src="$GSD_RALPH_REPO/.claude/commands/gsd/ralph.md"
    local dst=".claude/commands/gsd/ralph.md"
    local dst_dir
    dst_dir="$(dirname "$dst")"

    mkdir -p "$dst_dir"

    # Generate the path-adjusted version
    local tmp_adjusted
    tmp_adjusted="$(mktemp "${TMPDIR:-/tmp}/ralph-cmd.XXXXXX")"
    sed 's|bash scripts/ralph-launcher\.sh|bash scripts/ralph/ralph-launcher.sh|g' "$src" > "$tmp_adjusted"

    if [ -f "$dst" ] && cmp -s "$tmp_adjusted" "$dst"; then
        # File already exists and matches adjusted version -- skip
        SKIPPED=$((SKIPPED + 1))
        rm -f "$tmp_adjusted"
        return 0
    fi

    mv "$tmp_adjusted" "$dst"
    INSTALLED=$((INSTALLED + 1))
}

# --- Config merge (INST-05) ---
# Adds ralph config defaults to .planning/config.json without overwriting existing settings.
# Args: config_file path
merge_ralph_config() {
    local config_file="$1"

    # Check if ralph key already exists -- skip if present
    if jq -e '.ralph' "$config_file" >/dev/null 2>&1; then
        print_info "Ralph config already present in config.json"
        return 0
    fi

    # Validate existing JSON before modifying
    if ! jq '.' "$config_file" >/dev/null 2>&1; then
        print_error "config.json contains invalid JSON -- cannot merge ralph config"
        return 1
    fi

    # Create temp file in same directory for atomic mv (same filesystem)
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

# --- Post-install verification (INST-07) ---
# Checks that all installed files exist, scripts are executable, and config has ralph key.
# Returns error count (0 = success).
verify_installation() {
    local errors=0

    # Scripts must exist and be executable
    local script
    for script in ralph-launcher.sh assemble-context.sh validate-config.sh ralph-hook.sh; do
        local path="scripts/ralph/$script"
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
        if [ ! -f "$file" ]; then
            print_error "Missing: $file"
            errors=$((errors + 1))
        fi
    done

    # Config must have ralph key
    if ! jq -e '.ralph' .planning/config.json >/dev/null 2>&1; then
        print_error "Ralph config missing from .planning/config.json"
        errors=$((errors + 1))
    fi

    return $errors
}

# --- Summary output (INST-08) ---
# Prints a colored summary with file counts and next-step instructions.
# Uses INSTALLED and SKIPPED counters set during file copy.
print_summary() {
    printf "\n"
    printf "%s\n" "----------------------------------------"

    if [ "$INSTALLED" -gt 0 ]; then
        printf "${BOLD}${GREEN}Installation complete!${NC}\n"
    else
        printf "${BOLD}${GREEN}Already up to date!${NC}\n"
    fi

    printf "\n"

    if [ "$INSTALLED" -gt 0 ]; then
        printf "  Installed: %d files\n" "$INSTALLED"
    fi
    if [ "$SKIPPED" -gt 0 ]; then
        printf "  Skipped:   %d files (already up to date)\n" "$SKIPPED"
    fi

    printf "\n"
    printf "Next steps:\n"
    printf "  1. Run /gsd:ralph execute-phase N --dry-run to verify\n"
    printf "  2. See .claude/skills/gsd-ralph-autopilot/SKILL.md for autopilot behavior rules\n"
    printf "%s\n" "----------------------------------------"
}

# --- Main execution ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_prerequisites || exit 1

    INSTALLED=0
    SKIPPED=0

    # Copy scripts
    install_file "$GSD_RALPH_REPO/scripts/ralph-launcher.sh" "scripts/ralph/ralph-launcher.sh" true
    install_file "$GSD_RALPH_REPO/scripts/assemble-context.sh" "scripts/ralph/assemble-context.sh" true
    install_file "$GSD_RALPH_REPO/scripts/validate-config.sh" "scripts/ralph/validate-config.sh" true
    install_file "$GSD_RALPH_REPO/scripts/ralph-hook.sh" "scripts/ralph/ralph-hook.sh" true

    # Copy command file (with path adjustment)
    install_command_file

    # Copy skill file
    install_file "$GSD_RALPH_REPO/.claude/skills/gsd-ralph-autopilot/SKILL.md" ".claude/skills/gsd-ralph-autopilot/SKILL.md" false

    # Merge ralph config into .planning/config.json
    merge_ralph_config ".planning/config.json" || exit 1

    # Post-install verification
    verify_installation || { print_error "Verification failed"; exit 1; }

    # Print summary with file counts and next steps
    print_summary
fi
