#!/bin/bash
# lib/commands/execute.sh -- Execute a phase with GSD-protocol sequential mode

# Source required libraries
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/templates.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/discovery.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/prompt.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/frontmatter.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/strategy.sh"
# shellcheck source=/dev/null
source "$GSD_RALPH_HOME/lib/cleanup/registry.sh"

execute_usage() {
    cat <<EOF
Execute a GSD phase with sequential protocol mode

Usage: gsd-ralph execute [options] <phase_number>

Creates a branch, generates a GSD-protocol PROMPT.md, combined fix_plan.md,
and execution log — preparing the environment for Ralph to autonomously
complete all plans in the phase.

Options:
  --dry-run     Show what would happen without creating branch or files
  -v, --verbose Enable verbose output
  -h, --help    Show this help message

Examples:
  gsd-ralph execute 3          Set up execution for phase 3
  gsd-ralph execute 2 --dry-run  Preview what would be generated
EOF
}

cmd_execute() {
    local phase_num=""
    local dry_run=false

    # Parse arguments
    # shellcheck disable=SC2034
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)       execute_usage; exit 0 ;;
            -v|--verbose)    VERBOSE=true; shift ;;
            --dry-run)       dry_run=true; shift ;;
            -*)              die "Unknown option for execute: $1" ;;
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
        execute_usage
        exit 1
    fi

    print_header "gsd-ralph execute (Phase $phase_num)"

    # Step 1: Validate environment
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        die "Not inside a git repository. Run this from your project root."
    fi
    if [[ ! -d ".planning" ]]; then
        die "No .planning/ directory found. Initialize GSD first."
    fi
    if [[ ! -d ".ralph" ]]; then
        die "Not initialized. Run 'gsd-ralph init' first."
    fi

    # Step 2: Find phase directory and discover plans
    if ! find_phase_dir "$phase_num"; then
        die "Phase $phase_num not found. Check .planning/phases/ for available phases."
    fi
    print_info "Phase directory: $PHASE_DIR"

    if ! discover_plan_files "$PHASE_DIR"; then
        die "No plan files found in $PHASE_DIR"
    fi
    print_info "Found $PLAN_COUNT plan(s)"

    # Step 3: Analyze strategy
    analyze_phase_strategy "$PHASE_DIR"
    print_info "Strategy: $STRATEGY_MODE ($STRATEGY_WAVE_COUNT wave(s))"

    if [[ "$STRATEGY_MODE" == "parallel" ]]; then
        print_info "Phase has parallel-capable plans, but executing sequentially (parallel mode deferred)"
    fi

    # Validate dependencies
    if ! validate_phase_dependencies "$PHASE_DIR"; then
        die "Phase dependency validation failed"
    fi
    print_success "Dependencies validated"

    # Step 4: Detect project type
    detect_project_type "."

    local project_name
    project_name=$(basename "$(git rev-parse --show-toplevel)")

    # Step 5: Derive branch name
    local phase_slug
    phase_slug=$(basename "$PHASE_DIR")
    # Extract slug part after the NN- prefix
    local slug_part="${phase_slug#[0-9][0-9]-}"
    local branch_name="phase-${phase_num}/${slug_part}"

    # Count total tasks for summary
    local total_tasks=0
    local plan_file task_count
    for plan_file in "${STRATEGY_PLAN_ORDER[@]}"; do
        task_count=$(python3 -c "
import re, sys
content = open(sys.argv[1]).read()
tasks = re.findall(r'<task[^>]*>(.*?)</task>', content, re.DOTALL)
print(len(tasks))
" "$plan_file" 2>/dev/null || echo "0")
        total_tasks=$((total_tasks + task_count))
    done

    # Dry-run: show what would happen and exit
    if [[ "$dry_run" == true ]]; then
        print_header "Dry Run Summary"
        print_info "Branch: $branch_name"
        print_info "Mode: $STRATEGY_MODE"
        print_info "Plans: $PLAN_COUNT"
        print_info "Tasks: $total_tasks"
        print_info "Project: $project_name ($DETECTED_LANG)"
        print_info "Test command: ${DETECTED_TEST_CMD:-none}"
        print_info "Build command: ${DETECTED_BUILD_CMD:-none}"
        print_info ""
        print_info "Would generate:"
        print_info "  .ralph/PROMPT.md (GSD Execution Protocol)"
        print_info "  .ralph/fix_plan.md (combined task checklist)"
        print_info "  .ralph/logs/execution-log.md"
        print_info ""
        print_info "Strategy analysis:"
        print_phase_structure "$PHASE_DIR"
        return 0
    fi

    # Step 6: Create and switch to branch
    if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
        die "Branch '$branch_name' already exists. Delete it first or use a different phase."
    fi
    git checkout -b "$branch_name" >/dev/null 2>&1
    print_success "Created branch: $branch_name"

    # Register branch in worktree registry for cleanup tracking
    register_worktree "$phase_num" "$(pwd)" "$branch_name"
    print_verbose "Registered branch in worktree registry"

    # Ensure bell rings if any post-branch step fails (user has done significant work)
    trap 'ring_bell' EXIT

    # Step 7: Generate protocol PROMPT.md
    mkdir -p .ralph/logs
    generate_protocol_prompt_md \
        ".ralph/PROMPT.md" \
        "$GSD_RALPH_HOME/templates/PROTOCOL-PROMPT.md.template" \
        "$phase_num" "$PHASE_DIR" \
        "$project_name" "$DETECTED_LANG" \
        "$DETECTED_TEST_CMD" "$DETECTED_BUILD_CMD" \
        "${STRATEGY_PLAN_ORDER[@]}"
    print_success "Generated .ralph/PROMPT.md (GSD Execution Protocol)"

    # Step 8: Generate combined fix_plan.md
    generate_combined_fix_plan \
        "$PHASE_DIR" \
        ".ralph/fix_plan.md" \
        "${STRATEGY_PLAN_ORDER[@]}"
    print_success "Generated .ralph/fix_plan.md (combined task checklist)"

    # Step 9: Initialize execution log
    local padded_phase
    padded_phase=$(printf "%02d" "$phase_num")
    local phase_title="${phase_slug#[0-9][0-9]-}"
    phase_title="${phase_title//-/ }"

    cat > ".ralph/logs/execution-log.md" << EOF
# Phase ${padded_phase}: Execution Log

Phase: ${phase_slug}
Started: $(iso_timestamp)
Mode: $STRATEGY_MODE
Plans: $PLAN_COUNT
Tasks: $total_tasks

---
EOF
    print_success "Initialized .ralph/logs/execution-log.md"

    # Step 10: Update STATE.md
    if [[ -f ".planning/STATE.md" ]]; then
        # Update current position section
        local state_content
        state_content=$(<".planning/STATE.md")

        # Use sed for line-by-line replacements in multi-line content (Bash 3.2 safe)
        # shellcheck disable=SC2001
        state_content=$(echo "$state_content" | sed "s/^Phase:.*/Phase: ${phase_num} of 5 -- In Progress/")
        # shellcheck disable=SC2001
        state_content=$(echo "$state_content" | sed "s/^Plan:.*/Plan: 0 of ${PLAN_COUNT} complete/")
        # shellcheck disable=SC2001
        state_content=$(echo "$state_content" | sed "s/^Status:.*/Status: Executing/")
        # shellcheck disable=SC2001
        state_content=$(echo "$state_content" | sed "s/^Last activity:.*/Last activity: $(date -u +%Y-%m-%d) -- Phase ${phase_num} execution started/")
        # shellcheck disable=SC2001
        state_content=$(echo "$state_content" | sed "s/^Stopped at:.*/Stopped at: Phase ${phase_num} execution environment set up/")

        printf '%s\n' "$state_content" > ".planning/STATE.md"
        print_success "Updated .planning/STATE.md"
    fi

    # Step 11: Commit setup
    git add .ralph/PROMPT.md .ralph/fix_plan.md .ralph/logs/execution-log.md .planning/STATE.md >/dev/null 2>&1
    git commit -m "chore(phase-${phase_num}): set up execution environment for ${slug_part}" >/dev/null 2>&1
    print_success "Committed execution environment setup"

    # Step 12: Print summary
    print_header "Execution Environment Ready"
    print_info "Branch: $branch_name"
    print_info "Mode: sequential"
    print_info "Plans: $PLAN_COUNT"
    print_info "Tasks: $total_tasks"
    print_info ""
    print_info "Generated files:"
    print_info "  .ralph/PROMPT.md         -- GSD Execution Protocol"
    print_info "  .ralph/fix_plan.md       -- Combined task checklist"
    print_info "  .ralph/logs/execution-log.md -- Execution log"
    print_info ""

    # Step 13: Print launch instructions
    printf "\n"
    print_success "Run 'ralph' to start execution"
    ring_bell
    trap - EXIT
}
