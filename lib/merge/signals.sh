#!/bin/bash
# lib/merge/signals.sh -- Wave completion signaling and phase completion state updates
#
# Writes JSON signal files to .ralph/merge-signals/ to indicate wave and phase
# completion. Updates STATE.md and ROADMAP.md when a phase completes.

# Signal file directory
SIGNAL_DIR=".ralph/merge-signals"

# Signal that a wave's branches have been merged.
# Writes a JSON signal file with metadata about the completed wave.
# Args: phase_num, wave_num, branches_merged (space-separated list)
# Returns: 0 on success
signal_wave_complete() {
    local phase_num="$1"
    local wave_num="$2"
    local branches_merged="$3"

    mkdir -p "$SIGNAL_DIR"

    local signal_file="$SIGNAL_DIR/phase-${phase_num}-wave-${wave_num}-complete"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local main_sha
    main_sha=$(git rev-parse HEAD)

    # Build JSON array from space-separated branch list
    local json_array=""
    local branch
    for branch in $branches_merged; do
        if [[ -n "$json_array" ]]; then
            json_array="${json_array}, \"${branch}\""
        else
            json_array="\"${branch}\""
        fi
    done

    cat > "$signal_file" <<EOF
{
  "phase": ${phase_num},
  "wave": ${wave_num},
  "completed_at": "${timestamp}",
  "branches_merged": [${json_array}],
  "main_sha": "${main_sha}"
}
EOF

    print_success "Signaled wave $wave_num complete for phase $phase_num"
    return 0
}

# Check if a wave has been completed (signal file exists).
# Args: phase_num, wave_num
# Returns: 0 if signal file exists, 1 if not
check_wave_complete() {
    local phase_num="$1"
    local wave_num="$2"

    [[ -f "$SIGNAL_DIR/phase-${phase_num}-wave-${wave_num}-complete" ]]
}

# Update STATE.md and ROADMAP.md to mark a phase as complete.
# Uses sed-based pattern matching for STATE.md and ROADMAP.md updates.
# Args: phase_num
# Returns: 0 on success
update_phase_complete_state() {
    local phase_num="$1"
    local today
    today=$(date -u +%Y-%m-%d)

    # ── Update STATE.md ──
    if [[ -f ".planning/STATE.md" ]]; then
        local state_content
        state_content=$(<".planning/STATE.md")
        state_content=$(printf '%s' "$state_content" | sed "s/^Phase:.*/Phase: ${phase_num} of 5 -- Complete/")
        state_content=$(printf '%s' "$state_content" | sed "s/^Status:.*/Status: Complete/")
        state_content=$(printf '%s' "$state_content" | sed "s/^Last activity:.*/Last activity: ${today} -- Phase ${phase_num} merged/")
        printf '%s\n' "$state_content" > ".planning/STATE.md"
        print_verbose "Updated STATE.md: phase $phase_num marked complete"
    else
        print_warning "STATE.md not found, skipping state update"
    fi

    # ── Update ROADMAP.md ──
    if [[ -f ".planning/ROADMAP.md" ]]; then
        # Update the progress table row for this phase:
        # Pattern: "| N. <name> | X/Y | <old status> | <old date> |"
        # Replace status with "Complete" and date with today
        sed -i '' "s/| ${phase_num}\. \(.*\) | \([0-9]*\/[0-9]*\) | [^|]* | [^|]* |/| ${phase_num}. \1 | \2 | Complete | ${today} |/" ".planning/ROADMAP.md" 2>/dev/null || \
        sed -i "s/| ${phase_num}\. \(.*\) | \([0-9]*\/[0-9]*\) | [^|]* | [^|]* |/| ${phase_num}. \1 | \2 | Complete | ${today} |/" ".planning/ROADMAP.md" 2>/dev/null || true
        print_verbose "Updated ROADMAP.md: phase $phase_num marked complete"
    else
        print_warning "ROADMAP.md not found, skipping roadmap update"
    fi

    # Commit the state changes
    git add .planning/STATE.md .planning/ROADMAP.md 2>/dev/null
    git commit -m "docs(phase-${phase_num}): mark phase complete after merge" >/dev/null 2>&1 || true

    return 0
}

# Signal that all branches for a phase have been merged.
# Updates STATE.md and ROADMAP.md, then writes a phase-level signal file.
# Args: phase_num
# Returns: 0 on success
signal_phase_complete() {
    local phase_num="$1"

    # Update project state documents
    update_phase_complete_state "$phase_num"

    # Write phase completion signal
    mkdir -p "$SIGNAL_DIR"

    local signal_file="$SIGNAL_DIR/phase-${phase_num}-complete"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local main_sha
    main_sha=$(git rev-parse HEAD)

    cat > "$signal_file" <<EOF
{
  "phase": ${phase_num},
  "completed_at": "${timestamp}",
  "main_sha": "${main_sha}"
}
EOF

    print_success "Phase $phase_num complete -- STATE.md and ROADMAP.md updated"
    return 0
}
