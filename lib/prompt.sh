#!/bin/bash
# lib/prompt.sh -- PROMPT.md and fix_plan.md generation pipeline

# Extract tasks from GSD plan XML into fix_plan.md checklist.
# Uses python3 regex for reliable multiline XML parsing.
# Args: plan_file, output_file
# Returns: 0 on success, 1 if plan_file not found
extract_tasks_to_fix_plan() {
    local plan_file="$1"
    local output_file="$2"

    if [[ ! -f "$plan_file" ]]; then
        print_error "Plan file not found: $plan_file"
        return 1
    fi

    python3 -c "
import re, sys
content = open(sys.argv[1]).read()
tasks = re.findall(r'<task[^>]*>(.*?)</task>', content, re.DOTALL)
for t in tasks:
    name_m = re.search(r'<name>(.*?)</name>', t)
    if not name_m:
        continue
    name = name_m.group(1).strip()
    print(f'- [ ] {name}')
" "$plan_file" > "$output_file" 2>/dev/null

    local task_count=0
    if [[ -s "$output_file" ]]; then
        task_count=$(wc -l < "$output_file" | tr -d ' ')
    fi
    print_verbose "Extracted $task_count task(s) from $(basename "$plan_file")"
    return 0
}

# Generate complete PROMPT.md for a plan.
# Renders base template then appends dynamic sections.
# Args: output_path, template_path, phase_num, plan_id, plan_count,
#       plan_filename, phase_dir, project_name, project_lang,
#       test_cmd, build_cmd, repo_name, parent_dir
generate_prompt_md() {
    local output_path="$1"
    local template_path="$2"
    local phase_num="$3"
    local plan_id="$4"
    local plan_count="$5"
    local plan_filename="$6"
    local phase_dir="$7"
    local project_name="$8"
    local project_lang="$9"
    local test_cmd="${10}"
    local build_cmd="${11}"
    local repo_name="${12}"
    local parent_dir="${13}"

    # Step 1: Render base template with variable substitution
    render_template "$template_path" "$output_path" \
        "PROJECT_NAME=${project_name}" \
        "PROJECT_LANG=${project_lang}" \
        "TEST_CMD=${test_cmd}" \
        "BUILD_CMD=${build_cmd}"

    # Step 2: Append scope lock section
    append_scope_lock "$output_path" "$phase_num" "$plan_id" "$plan_filename" "$phase_dir"

    # Step 3: Append merge order section
    append_merge_order "$output_path" "$plan_id" "$plan_count"

    # Step 4: Append peer visibility section
    append_peer_visibility "$output_path" "$phase_num" "$plan_id" "$plan_count" "$repo_name" "$parent_dir"
}

# Append scope lock section to PROMPT.md.
# Args: output_path, phase_num, plan_id, plan_filename, phase_dir
append_scope_lock() {
    local output="$1"
    local phase_num="$2"
    local plan_id="$3"
    local plan_filename="$4"
    local phase_dir="$5"

    cat >> "$output" << EOF

# --- WORKTREE OVERRIDES (Phase ${phase_num}, Plan ${plan_id}) ---

## Scope Lock

You are executing **Phase ${phase_num}, Plan ${plan_id}** ONLY.

- Your plan file: \`${phase_dir}/${plan_filename}\`
- Do NOT work on tasks from other phases or plans
- Do NOT modify the task discovery sequence -- your tasks are in the plan file above
EOF
}

# Append merge order section to PROMPT.md.
# Skips for single-plan phases.
# Args: output_path, plan_id, plan_count
append_merge_order() {
    local output="$1"
    local plan_id="$2"
    local plan_count="$3"

    if [[ "$plan_count" -le 1 ]]; then
        return 0
    fi

    cat >> "$output" << EOF

## Merge Order

This is **Plan ${plan_id} of ${plan_count}** in this phase.
Branches merge in plan order (01, 02, ...). Your branch merges in position ${plan_id}.
EOF
}

# Append peer visibility section to PROMPT.md.
# Lists peer worktree paths for multi-plan phases.
# Args: output_path, phase_num, plan_id, plan_count, repo_name, parent_dir
append_peer_visibility() {
    local output="$1"
    local phase_num="$2"
    local plan_id="$3"
    local plan_count="$4"
    local repo_name="$5"
    local parent_dir="$6"

    if [[ "$plan_count" -le 1 ]]; then
        cat >> "$output" << 'EOF'

## Peer Visibility

_No peer worktrees -- this is the only plan in this phase._
EOF
        return 0
    fi

    cat >> "$output" << 'EOF'

## Read-Only Peer Visibility

Other plans in this phase are executing in parallel. You may READ files in
peer worktrees to check status and inspect their implementations, but do NOT
edit any files outside your own worktree.

**Peer worktrees:**
EOF

    local j peer_id peer_path
    for j in $(seq 1 "$plan_count"); do
        peer_id=$(printf "%02d" "$j")
        [[ "$peer_id" == "$plan_id" ]] && continue
        peer_path="${parent_dir}/${repo_name}-p${phase_num}-${peer_id}"
        echo "- Status: \`${peer_path}/.ralph/status.json\`" >> "$output"
        echo "- Source: \`${peer_path}/\` (read-only)" >> "$output"
    done
}
