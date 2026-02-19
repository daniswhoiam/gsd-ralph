#!/bin/bash
# lib/merge/review.sh -- Post-merge summary and review output
#
# Provides formatted summary table of merge results, optional detailed
# diff review, and conflict resolution guidance.

# Print a formatted summary table of merge results.
# Args: result strings (colon-delimited "branch:status:details:commits")
# Each argument is one result entry.
print_merge_summary() {
    local results=("$@")

    local merged_count=0
    local skipped_count=0
    local conflict_count=0

    # Count statuses
    for result in "${results[@]}"; do
        local status
        status=$(echo "$result" | cut -d: -f2)
        case "$status" in
            merged|merged*) merged_count=$((merged_count + 1)) ;;
            skipped)        skipped_count=$((skipped_count + 1)) ;;
            conflict)       conflict_count=$((conflict_count + 1)) ;;
        esac
    done

    printf "\n"
    printf "%-40s %-14s %-8s\n" "Branch" "Status" "Commits"
    printf "%-40s %-14s %-8s\n" \
        "----------------------------------------" \
        "--------------" \
        "--------"

    for result in "${results[@]}"; do
        local branch status details commits
        branch=$(echo "$result" | cut -d: -f1)
        status=$(echo "$result" | cut -d: -f2)
        details=$(echo "$result" | cut -d: -f3)
        commits=$(echo "$result" | cut -d: -f4)

        # For display: show "-" for skipped/conflict commits
        if [[ "$commits" == "0" ]] && [[ "$status" != "merged" ]] && [[ "$status" != "merged*" ]]; then
            commits="-"
        fi

        printf "%-40s %-14s %-8s\n" "$branch" "$status" "$commits"
    done

    printf "\n"
    printf "%s merged, %s skipped, %s conflicts detected\n" \
        "$merged_count" "$skipped_count" "$conflict_count"

    # List skipped branches with details
    local has_skipped=false
    for result in "${results[@]}"; do
        local status
        status=$(echo "$result" | cut -d: -f2)
        if [[ "$status" == "skipped" ]]; then
            if [[ "$has_skipped" == false ]]; then
                printf "\nSkipped branches:\n"
                has_skipped=true
            fi
            local branch details
            branch=$(echo "$result" | cut -d: -f1)
            details=$(echo "$result" | cut -d: -f3)
            printf "  %s -- %s\n" "$branch" "$details"
        fi
    done
}

# Print detailed review output for each merged branch.
# Reads sha_before/sha_after from the rollback file's branches_merged array.
# Args: phase_num
print_merge_review() {
    local phase_num="$1"

    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        print_warning "No rollback file found. Cannot show detailed review."
        return 1
    fi

    local branch_count
    branch_count=$(jq '.branches_merged | length' "$ROLLBACK_FILE" 2>/dev/null)

    if [[ -z "$branch_count" ]] || [[ "$branch_count" -eq 0 ]]; then
        print_info "No branches were merged. Nothing to review."
        return 0
    fi

    printf "\n"
    print_header "Detailed Review (Phase $phase_num)"

    local i=0
    while [[ $i -lt $branch_count ]]; do
        local branch sha_before sha_after
        branch=$(jq -r ".branches_merged[$i].branch" "$ROLLBACK_FILE")
        sha_before=$(jq -r ".branches_merged[$i].sha_before" "$ROLLBACK_FILE")
        sha_after=$(jq -r ".branches_merged[$i].sha_after" "$ROLLBACK_FILE")

        printf "\n--- %s ---\n\n" "$branch"
        printf "Diff stat:\n"
        git diff --stat "$sha_before".."$sha_after" 2>/dev/null || true
        printf "\nCommits:\n"
        git log --oneline "$sha_before".."$sha_after" 2>/dev/null || true
        printf "\n"

        i=$((i + 1))
    done
}

# Print conflict resolution guidance for a skipped branch.
# Args: branch_name, conflicting_files (space or newline separated)
print_conflict_guidance() {
    local branch="$1"
    local conflicted_files="$2"

    printf "\n"
    print_warning "Branch $branch has conflicts in:"
    local file
    for file in $conflicted_files; do
        [[ -n "$file" ]] && printf "         - %s\n" "$file"
    done

    printf "\n       To resolve manually:\n"
    printf "         1. git merge %s\n" "$branch"
    printf "         2. Edit conflicted files (look for <<<<<<< markers)\n"
    printf "         3. git add <resolved-files>\n"
    printf "         4. git commit --no-edit\n"
}
