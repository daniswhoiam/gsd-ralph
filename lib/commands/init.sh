#!/bin/bash
# lib/commands/init.sh -- Initialize gsd-ralph in a GSD project

init_usage() {
    cat <<EOF
Initialize gsd-ralph in a GSD project

Usage: gsd-ralph init [options]

Creates a .ralph/ configuration directory and .ralphrc with auto-detected
project settings.

Options:
  -f, --force  Reinitialize even if .ralph/ already exists
  -h, --help   Show this help message
EOF
}

cmd_init() {
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
    if ! check_all_dependencies; then
        exit 1
    fi

    # Step 5: Detect project type
    print_info "Detecting project type..."
    detect_project_type "."

    print_success "Language: ${DETECTED_LANG}"
    if [[ -n "$DETECTED_TEST_CMD" ]]; then
        print_success "Test command: ${DETECTED_TEST_CMD}"
    fi
    if [[ -n "$DETECTED_BUILD_CMD" ]]; then
        print_success "Build command: ${DETECTED_BUILD_CMD}"
    fi
    if [[ -n "$DETECTED_PKG_MANAGER" ]]; then
        print_success "Package manager: ${DETECTED_PKG_MANAGER}"
    fi

    # Step 6: Derive project name from git root directory
    local project_name
    project_name="$(basename "$(git rev-parse --show-toplevel)")"

    # Step 7: Create .ralph/ directory structure
    mkdir -p .ralph/logs

    # Step 8: Render .ralphrc from template
    # shellcheck source=/dev/null
    source "$GSD_RALPH_HOME/lib/templates.sh"
    render_template \
        "$GSD_RALPH_HOME/templates/ralphrc.template" \
        ".ralphrc" \
        "PROJECT_NAME=${project_name}" \
        "PROJECT_TYPE=${DETECTED_LANG}" \
        "TEST_CMD=${DETECTED_TEST_CMD}" \
        "BUILD_CMD=${DETECTED_BUILD_CMD}"

    # Step 9: Print completion summary
    print_header "Initialization complete"
    print_success "Created .ralph/ configuration directory"
    print_success "Created .ralphrc with project settings"
    print_info "Next steps:"
    printf "  1. Review .ralphrc configuration\n"
    printf "  2. Plan your first phase with GSD\n"
    printf "  3. Run: gsd-ralph execute 1\n"
}
