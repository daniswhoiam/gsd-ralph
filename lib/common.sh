#!/bin/bash
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
    # shellcheck disable=SC2034
    RED='' GREEN='' YELLOW='' BLUE='' BOLD='' NC=''
fi

print_header() {
    printf "\n${BLUE}%s${NC}\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    printf "${BLUE} %s${NC}\n" "$1"
    printf "${BLUE}%s${NC}\n\n" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_success() { printf "${GREEN}[ok]${NC} %s\n" "$1"; }
print_warning() { printf "${YELLOW}[warn]${NC} %s\n" "$1" >&2; }
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

# ISO 8601 timestamp that works on both macOS and Linux
iso_timestamp() {
    date -u +%Y-%m-%dT%H:%M:%SZ
}

check_dependency() {
    local cmd="$1"
    local install_hint="$2"
    local min_version="${3:-}"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        print_error "$cmd is not installed"
        printf "  Install: %s\n" "$install_hint" >&2
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

    # ralph is a soft dependency -- only needed at execute time, not init time
    if ! command -v ralph >/dev/null 2>&1; then
        print_warning "ralph not found. You'll need it before running 'gsd-ralph execute'."
        printf "  Install: %s\n" "https://github.com/frankbria/ralph-claude-code" >&2
    fi

    if [[ $missing -gt 0 ]]; then
        printf "\n" >&2
        print_error "$missing required dependency(ies) missing. Install them and re-run."
        return 1
    fi

    print_success "All dependencies found"
    return 0
}
