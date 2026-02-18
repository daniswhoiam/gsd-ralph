#!/bin/bash
# lib/strategy.sh -- Execution strategy analyzer for GSD phases

# Analyze execution strategy for a phase.
# Determines sequential vs parallel based on plan frontmatter.
# Args: phase_dir
# Sets: STRATEGY_MODE ("sequential" | "parallel"), STRATEGY_WAVE_COUNT,
#       STRATEGY_PLAN_ORDER (array of plan files in execution order)
# Returns: 0 on success, 1 if no plans found
analyze_phase_strategy() {
    local phase_dir="$1"

    STRATEGY_MODE="sequential"
    STRATEGY_WAVE_COUNT=0
    STRATEGY_PLAN_ORDER=()

    # Discover plan files
    if ! discover_plan_files "$phase_dir"; then
        print_error "No plan files found in $phase_dir"
        return 1
    fi

    # Single plan is always sequential
    if [[ $PLAN_COUNT -eq 1 ]]; then
        STRATEGY_MODE="sequential"
        STRATEGY_WAVE_COUNT=1
        STRATEGY_PLAN_ORDER=("${PLAN_FILES[@]}")
        return 0
    fi

    # Parse frontmatter for each plan to collect wave info
    local plan_file wave max_wave=0
    local -a waves=()

    for plan_file in "${PLAN_FILES[@]}"; do
        parse_plan_frontmatter "$plan_file"
        wave="${FM_WAVE:-1}"

        # Track max wave
        if [[ "$wave" -gt "$max_wave" ]]; then
            max_wave="$wave"
        fi

        waves+=("$wave")
    done

    STRATEGY_WAVE_COUNT="$max_wave"

    # Count plans per wave to determine if any wave has >1 plan
    local w count parallel_detected=false
    for w in $(seq 1 "$max_wave"); do
        count=0
        local i
        for i in $(seq 0 $((PLAN_COUNT - 1))); do
            if [[ "${waves[$i]}" -eq "$w" ]]; then
                count=$((count + 1))
            fi
        done
        if [[ "$count" -gt 1 ]]; then
            parallel_detected=true
        fi
    done

    if [[ "$parallel_detected" == true ]]; then
        STRATEGY_MODE="parallel"
    else
        STRATEGY_MODE="sequential"
    fi

    # Build execution order: sort by wave, then by plan position within wave
    STRATEGY_PLAN_ORDER=()
    for w in $(seq 1 "$max_wave"); do
        local i
        for i in $(seq 0 $((PLAN_COUNT - 1))); do
            if [[ "${waves[$i]}" -eq "$w" ]]; then
                STRATEGY_PLAN_ORDER+=("${PLAN_FILES[$i]}")
            fi
        done
    done

    return 0
}

# Validate phase dependencies (no circular refs, no missing deps).
# Args: phase_dir
# Returns: 0 if valid, 1 if invalid (prints error message)
validate_phase_dependencies() {
    local phase_dir="$1"

    if ! discover_plan_files "$phase_dir"; then
        print_error "No plan files found in $phase_dir"
        return 1
    fi

    # Collect all plan IDs and their dependencies
    local plan_file plan_id
    local -a plan_ids=()
    local -a plan_deps=()

    for plan_file in "${PLAN_FILES[@]}"; do
        plan_id=$(plan_id_from_filename "$plan_file")
        plan_ids+=("$plan_id")

        parse_plan_frontmatter "$plan_file"
        plan_deps+=("${FM_DEPENDS_ON:-}")
    done

    # Check for missing dependency references
    local i dep dep_found
    for i in $(seq 0 $((PLAN_COUNT - 1))); do
        local deps="${plan_deps[$i]}"
        [[ -z "$deps" ]] && continue

        for dep in $deps; do
            dep_found=false
            local j
            for j in $(seq 0 $((PLAN_COUNT - 1))); do
                if [[ "${plan_ids[$j]}" == "$dep" ]]; then
                    dep_found=true
                    break
                fi
            done
            if [[ "$dep_found" == false ]]; then
                print_error "Plan ${plan_ids[$i]} depends on '$dep' which does not exist in phase"
                return 1
            fi
        done
    done

    # Check for circular dependencies using iterative approach
    # For each plan, follow the dependency chain and detect if we revisit a node
    for i in $(seq 0 $((PLAN_COUNT - 1))); do
        local visited=""
        local current="${plan_ids[$i]}"
        local chain_broken=false

        while [[ -n "$current" ]] && [[ "$chain_broken" == false ]]; do
            # Check if we've visited this node before
            local v
            for v in $visited; do
                if [[ "$v" == "$current" ]]; then
                    print_error "Circular dependency detected involving plan $current"
                    return 1
                fi
            done

            visited="$visited $current"

            # Find the deps for current
            local current_deps=""
            local k
            for k in $(seq 0 $((PLAN_COUNT - 1))); do
                if [[ "${plan_ids[$k]}" == "$current" ]]; then
                    current_deps="${plan_deps[$k]}"
                    break
                fi
            done

            # Follow first dependency (for chain detection)
            if [[ -n "$current_deps" ]]; then
                # Take the first dep to follow the chain
                current="${current_deps%% *}"
            else
                chain_broken=true
            fi
        done
    done

    return 0
}

# Print human-readable phase structure.
# Args: phase_dir
# Returns: 0
print_phase_structure() {
    local phase_dir="$1"

    if ! analyze_phase_strategy "$phase_dir"; then
        return 1
    fi

    print_info "Strategy: $STRATEGY_MODE"
    print_info "Waves: $STRATEGY_WAVE_COUNT"
    print_info "Plans: $PLAN_COUNT"

    # Re-parse to show details per plan
    local plan_file plan_id wave deps
    for plan_file in "${STRATEGY_PLAN_ORDER[@]}"; do
        plan_id=$(plan_id_from_filename "$plan_file")
        parse_plan_frontmatter "$plan_file"
        wave="${FM_WAVE:-1}"
        deps="${FM_DEPENDS_ON:-none}"
        print_info "  Plan $plan_id: wave=$wave, depends_on=$deps"
    done

    return 0
}
