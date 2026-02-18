#!/bin/bash
# lib/commands/generate.sh -- Generate per-plan files for a phase

# Source required libraries
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/templates.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/discovery.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/prompt.sh"

generate_usage() {
    cat <<EOF
Generate per-plan files for a GSD phase

Usage: gsd-ralph generate [options] <phase_number>

Generates PROMPT.md, fix_plan.md, AGENT.md, .ralphrc, and status.json
for each plan in the specified phase. Output goes to .ralph/generated/
by default.

Options:
  --output-dir DIR  Output directory (default: .ralph/generated)
  -v, --verbose     Enable verbose output
  -h, --help        Show this help message

Examples:
  gsd-ralph generate 2          Generate files for phase 2
  gsd-ralph generate 1 --output-dir /tmp/gen  Custom output directory
EOF
}

cmd_generate() {
    local phase_num=""
    local output_dir=".ralph/generated"

    # Parse arguments
    # shellcheck disable=SC2034
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)       generate_usage; exit 0 ;;
            -v|--verbose)    VERBOSE=true; shift ;;
            --output-dir)
                if [[ -z "${2:-}" ]]; then
                    die "--output-dir requires a directory path"
                fi
                output_dir="$2"; shift 2 ;;
            -*)              die "Unknown option for generate: $1" ;;
            *)
                if [[ -z "$phase_num" ]]; then
                    phase_num="$1"; shift
                else
                    die "Unexpected argument: $1"
                fi
                ;;
        esac
    done

    if [[ -z "$phase_num" ]]; then
        print_error "Phase number required"
        generate_usage
        exit 1
    fi

    print_header "gsd-ralph generate (Phase $phase_num)"

    # Validate environment
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die "Not inside a git repository. Run this from your project root."
    fi
    if [[ ! -d ".planning" ]]; then
        die "No .planning/ directory found. Initialize GSD first."
    fi
    if [[ ! -d ".ralph" ]]; then
        die "Not initialized. Run 'gsd-ralph init' first."
    fi

    # Find phase directory
    if ! find_phase_dir "$phase_num"; then
        die "Phase $phase_num not found. Check .planning/phases/ for available phases."
    fi
    print_info "Phase directory: $PHASE_DIR"

    # Discover plan files
    if ! discover_plan_files "$PHASE_DIR"; then
        die "No plan files found in $PHASE_DIR"
    fi
    print_info "Found $PLAN_COUNT plan(s)"

    # Detect project type
    detect_project_type "."

    # Derive project context
    local project_name repo_name parent_dir
    project_name=$(basename "$(git rev-parse --show-toplevel)")
    repo_name="$project_name"
    parent_dir=$(dirname "$(git rev-parse --show-toplevel)")

    # Generate files for each plan
    local plan_file plan_id plan_filename plan_output_dir
    for plan_file in "${PLAN_FILES[@]}"; do
        plan_id=$(plan_id_from_filename "$plan_file")
        plan_filename=$(basename "$plan_file")
        plan_output_dir="${output_dir}/plan-${plan_id}"

        mkdir -p "${plan_output_dir}/logs"

        # Generate fix_plan.md
        extract_tasks_to_fix_plan "$plan_file" "${plan_output_dir}/fix_plan.md"

        # Generate PROMPT.md
        generate_prompt_md \
            "${plan_output_dir}/PROMPT.md" \
            "$GSD_RALPH_HOME/templates/PROMPT.md.template" \
            "$phase_num" "$plan_id" "$PLAN_COUNT" \
            "$plan_filename" "$PHASE_DIR" \
            "$project_name" "$DETECTED_LANG" \
            "$DETECTED_TEST_CMD" "$DETECTED_BUILD_CMD" \
            "$repo_name" "$parent_dir"

        # Generate AGENT.md
        render_template \
            "$GSD_RALPH_HOME/templates/AGENT.md.template" \
            "${plan_output_dir}/AGENT.md" \
            "PROJECT_NAME=${project_name}" \
            "PROJECT_LANG=${DETECTED_LANG}" \
            "TEST_CMD=${DETECTED_TEST_CMD}" \
            "BUILD_CMD=${DETECTED_BUILD_CMD}"

        # Generate .ralphrc
        render_template \
            "$GSD_RALPH_HOME/templates/ralphrc.template" \
            "${plan_output_dir}/.ralphrc" \
            "PROJECT_NAME=${project_name}" \
            "PROJECT_TYPE=${DETECTED_LANG}" \
            "TEST_CMD=${DETECTED_TEST_CMD}" \
            "BUILD_CMD=${DETECTED_BUILD_CMD}"

        # Generate initial status.json
        cat > "${plan_output_dir}/status.json" << STATUSEOF
{
  "phase": $phase_num,
  "plan": "$plan_id",
  "status": "ready",
  "started_at": null,
  "last_activity": "$(iso_timestamp)"
}
STATUSEOF

        print_success "Generated files for Plan ${phase_num}-${plan_id}"
    done

    # Print summary
    print_header "Generation complete"
    print_info "Plans processed: $PLAN_COUNT"
    print_info "Output directory: $output_dir"
    print_info "Files per plan: PROMPT.md, fix_plan.md, AGENT.md, .ralphrc, status.json"
}
