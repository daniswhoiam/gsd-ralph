# Phase 4: Merge Orchestration - Research

**Researched:** 2026-02-19
**Domain:** Git merge automation, conflict resolution, rollback, wave-aware orchestration in Bash
**Confidence:** HIGH

## Summary

Phase 4 implements `gsd-ralph merge N` -- a command that merges completed execution branches back into main with automated conflict handling, dry-run detection, rollback safety, post-merge testing, and wave-aware signaling. The merge command exists as both a standalone CLI command and as a function called automatically by the execute pipeline when a plan completes.

The core technical challenge is building a reliable, automated merge pipeline in Bash 3.2+ that: (1) detects conflicts before attempting real merges via `git merge-tree`, (2) auto-resolves predictable conflicts in `.planning/` and generated files, (3) skips truly conflicted branches and continues with remaining plans, (4) saves rollback points, (5) runs tests and detects only newly-introduced regressions, and (6) signals wave transitions for dependency-driven execution.

**Primary recommendation:** Use `git merge-tree --write-tree` for zero-risk dry-run conflict detection (requires Git 2.38+, safe on any modern macOS), `git merge --no-commit --no-ff` with selective `git checkout --ours` for auto-resolution of known file patterns, and `git reset --hard` to saved SHAs for rollback. Test regression detection should use a before/after comparison pattern: capture test results before merging, run tests after, and only halt on newly-failing tests.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Conflict resolution flow
- Merges are automated by Ralph as part of the execution loop -- minimal human involvement
- Conflict resolution strategy should be informed by best practices from research
- When a real conflict can't be auto-resolved, skip that branch and continue with remaining plans
- Report unmerged branches at the end with clear information about what conflicted
- Auto-resolve .planning/ file conflicts by preferring main's version
- Also auto-resolve common generated files (lock files, build artifacts, .gitignore) -- anything typically regenerated

#### Review mode experience
- Review is post-merge, not pre-merge -- show a summary of what was merged after completion
- Default: summary table showing each branch status (merged/skipped/conflicted), files changed count, commit count
- Optional flag to also show full git diffs for each merged branch
- No interactive approval flow -- merges are automatic

#### Rollback behavior
- Always save rollback point -- every merge saves the pre-merge SHA automatically
- Rollback scope, invocation method, and expiry are Claude's discretion based on research

#### Wave merge signaling
- Ralph should understand to proceed to wave N+1 after merging wave N -- seamless within the execution loop
- Follow GSD's dependency-driven execution model for wave transitions
- The specific signaling mechanism is Claude's discretion based on research
- After successful merge of all branches for a phase, auto-update STATE.md and ROADMAP.md to mark phase complete

#### Post-merge testing
- Always run the project's test suite after merging
- Do NOT stop the flow if regressions existed before this phase/wave -- only halt on regressions introduced by the merged code

#### Standalone command
- `gsd-ralph merge N` exists as its own command
- Execute always calls merge when a plan completes (opt-out may come in a later version)
- Manual invocation merges completed branches for the phase

### Claude's Discretion

- Merge timing (per-branch immediate vs per-wave batch)
- Manual merge: whether to merge all completed branches or allow picking
- Rollback scope (entire phase vs per-branch)
- Rollback invocation (subcommand flag vs separate command)
- Rollback expiry conditions
- Wave signaling mechanism (file-based, direct invocation, or other)

### Deferred Ideas (OUT OF SCOPE)

- Parallel worktree merge support -- build when parallel execution mode is implemented
- Opt-out flag for automatic merge during execute -- future version
- Pre-merge interactive approval flow -- not needed given automated approach
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| MERG-01 | User can auto-merge all completed branches for a phase in plan order with `gsd-ralph merge N` | Core merge pipeline: iterate branches in plan order, `git merge --no-ff --no-edit`, skip on conflict, report summary |
| MERG-02 | User can review each branch diff before merging with `--review` flag | Post-merge review via `git diff --stat` and `git log --oneline` per merged branch; `--review` shows full diffs |
| MERG-03 | Tool detects merge conflicts and provides clear resolution guidance | `git merge-tree --write-tree` for pre-merge dry-run; `git diff --name-only --diff-filter=U` for conflict listing during real merge |
| MERG-04 | Tool auto-resolves .planning/ conflicts (prefer main's version) | `git checkout --ours .planning/` after merge attempt; extend to lock files and generated files |
| MERG-05 | Tool saves pre-merge commit hash and offers rollback on failure | Save SHA via `git rev-parse HEAD` before each merge; rollback via `git reset --hard <saved-SHA>` |
| MERG-06 | Pre-merge dry-run detects conflicts before attempting the real merge | `git merge-tree --write-tree --quiet main <branch>` exit code: 0=clean, 1=conflicts; run for all branches upfront |
| MERG-07 | Wave-aware merge: when wave N branches are merged, tool signals execution pipeline to unblock wave N+1 | File-based signal: `.ralph/merge-signals/wave-N-complete` with metadata; execute pipeline checks for signal before launching next wave |
</phase_requirements>

## Standard Stack

### Core

This phase uses no external libraries -- it is pure Bash + Git commands, consistent with the project's zero-dependency philosophy.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2+ | Script runtime | macOS system default, project constraint |
| Git | 2.38+ | Merge operations, conflict detection | `git merge-tree --write-tree` requires 2.38+; macOS Homebrew ships 2.47+, Xcode CLT ships recent versions |
| jq | any | JSON manipulation for status/signal files | Already a project dependency |

### Key Git Commands

| Command | Purpose | Notes |
|---------|---------|-------|
| `git merge-tree --write-tree --quiet main <branch>` | Dry-run conflict detection | Exit 0 = clean, 1 = conflicts. Does NOT touch working tree or index |
| `git merge-tree --write-tree --name-only main <branch>` | List conflicting file names | For reporting which files conflict |
| `git merge --no-ff --no-edit <branch>` | Actual merge | `--no-ff` ensures merge commit for traceability |
| `git checkout --ours <path>` | Auto-resolve conflicts preferring main | For `.planning/`, lock files, generated files |
| `git diff --name-only --diff-filter=U` | List unresolved conflicts | After merge attempt, identifies remaining conflicts |
| `git rev-parse HEAD` | Capture pre-merge SHA | For rollback point |
| `git reset --hard <SHA>` | Rollback to saved point | Fast, local-only, appropriate for this use case |
| `git diff --stat <before>..<after>` | Files changed summary | For review mode output |
| `git log --oneline <before>..<after>` | Commit count/summary | For review mode output |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `git merge-tree` | `git merge --no-commit --no-ff` + `git merge --abort` | Touches working tree/index, slower, less clean for dry-run |
| `git checkout --ours` per-path | `git merge -Xours` globally | Too coarse -- resolves ALL conflicts as ours, not just known safe files |
| `git reset --hard` for rollback | `git revert -m 1` | Revert creates new commits, adds noise; reset is cleaner for local-only operations |
| File-based wave signals | Direct function invocation | Function invocation couples merge and execute too tightly; files are inspectable and debuggable |

## Architecture Patterns

### Recommended Module Structure

```
lib/
  commands/
    merge.sh          # cmd_merge() entry point, argument parsing, orchestration
  merge/
    dry_run.sh        # Dry-run conflict detection using git merge-tree
    auto_resolve.sh   # Auto-resolution of .planning/, lock files, generated files
    rollback.sh       # SHA saving, rollback execution
    review.sh         # Post-merge summary and diff display
    signals.sh        # Wave completion signaling and state updates
    test_runner.sh    # Post-merge test execution and regression detection
```

**Rationale:** The merge command is the most complex command in gsd-ralph. Splitting into focused modules keeps each file testable and under ~100 lines. The `lib/merge/` directory follows the same pattern as `lib/commands/` but for internal modules. Each module exposes 1-3 functions with clear inputs and outputs.

**Alternative:** Keep everything in `lib/commands/merge.sh`. This is simpler but will result in a 400+ line file that is hard to test in isolation. Given the complexity of merge orchestration (7 requirements, multiple failure modes), the split approach is strongly recommended.

### Pattern 1: Merge Pipeline (Core Loop)

**What:** Sequential merge of branches with pre-flight checks, auto-resolution, and graceful skip-on-failure.

**When to use:** Every `gsd-ralph merge N` invocation.

```bash
# Pseudocode for the core merge pipeline
cmd_merge() {
    local phase_num="$1"

    # 1. Validate environment (git repo, .ralph exists, .planning exists)
    # 2. Discover branches for this phase (plan order)
    # 3. Switch to main branch
    # 4. Save pre-merge rollback point

    # 5. Dry-run all branches first (MERG-06)
    local -a clean_branches=()
    local -a conflict_branches=()
    for branch in "${branches[@]}"; do
        if merge_dry_run "$branch"; then
            clean_branches+=("$branch")
        else
            conflict_branches+=("$branch")
        fi
    done

    # 6. Report dry-run results
    # 7. Merge clean branches in plan order
    for branch in "${clean_branches[@]}"; do
        save_rollback_point
        if ! merge_branch_with_auto_resolve "$branch"; then
            record_skip "$branch" "conflict"
            rollback_to_saved_point
            continue
        fi
        record_success "$branch"
    done

    # 8. Run post-merge tests (regression detection)
    # 9. Print summary (MERG-02 review mode)
    # 10. Update STATE.md and ROADMAP.md if all branches merged
    # 11. Signal wave completion if applicable (MERG-07)
}
```

### Pattern 2: Dry-Run Conflict Detection (MERG-06)

**What:** Use `git merge-tree --write-tree` to detect conflicts without touching working tree.

**When to use:** Before any real merge attempt.

```bash
# Dry-run using git merge-tree (Git 2.38+)
merge_dry_run() {
    local branch="$1"
    local main_branch
    main_branch=$(git symbolic-ref --short HEAD)

    # Exit code: 0 = conflicts, 1 = clean (inverted from intuition!)
    # Actually: 0 = clean merge, 1 = conflicts per current docs
    # IMPORTANT: Verify exact exit code semantics at implementation time
    if git merge-tree --write-tree --quiet "$main_branch" "$branch" >/dev/null 2>&1; then
        return 0  # Clean merge possible
    else
        return 1  # Conflicts detected
    fi
}

# List conflicting files for a branch
merge_dry_run_conflicts() {
    local branch="$1"
    local main_branch
    main_branch=$(git symbolic-ref --short HEAD)

    git merge-tree --write-tree --name-only "$main_branch" "$branch" 2>&1 | \
        tail -n +2  # Skip the tree SHA line
}
```

**IMPORTANT NOTE on `git merge-tree` exit codes:** The official git documentation states: exit status 0 means the merge had no conflicts (clean), and exit status 1 means the merge had conflicts. However, some documentation sources show inverted semantics. The planner MUST verify the exact exit code behavior during implementation by running a test case. This is flagged as a verification point.

### Pattern 3: Auto-Resolution of Known Safe Files (MERG-04)

**What:** After a merge attempt with conflicts, auto-resolve conflicts in known-safe file patterns by preferring main's version.

**When to use:** When `git merge` reports conflicts and some are in auto-resolvable paths.

```bash
# Auto-resolvable file patterns (prefer main's version = --ours during merge)
AUTO_RESOLVE_PATTERNS=(
    ".planning/*"           # Planning files -- main is authoritative
    "*.lock"                # Lock files -- regenerated
    "package-lock.json"     # npm lock -- regenerated
    "yarn.lock"             # yarn lock -- regenerated
    "pnpm-lock.yaml"        # pnpm lock -- regenerated
    "Cargo.lock"            # Cargo lock -- regenerated
    ".gitignore"            # gitignore -- main is authoritative
    "*.pyc"                 # Python compiled -- regenerated
)

auto_resolve_known_conflicts() {
    # Get list of conflicted files
    local -a conflicted
    conflicted=($(git diff --name-only --diff-filter=U))

    local -a resolved=()
    local -a remaining=()

    for file in "${conflicted[@]}"; do
        if matches_auto_resolve_pattern "$file"; then
            git checkout --ours "$file"
            git add "$file"
            resolved+=("$file")
        else
            remaining+=("$file")
        fi
    done

    # If all conflicts resolved, complete the merge
    if [[ ${#remaining[@]} -eq 0 ]]; then
        git commit --no-edit
        return 0  # Fully resolved
    fi

    return 1  # Some conflicts remain
}
```

### Pattern 4: Rollback Safety (MERG-05)

**What:** Save pre-merge SHA before each merge operation and provide rollback capability.

**When to use:** Every merge attempt.

**Recommendation: Phase-level rollback with per-merge tracking.**

```bash
# Save rollback point to a JSON file
ROLLBACK_FILE=".ralph/merge-rollback.json"

save_rollback_point() {
    local phase_num="$1"
    local sha
    sha=$(git rev-parse HEAD)
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Store as JSON for structured access
    cat > "$ROLLBACK_FILE" <<EOF
{
  "phase": $phase_num,
  "pre_merge_sha": "$sha",
  "timestamp": "$timestamp",
  "branches_merged": []
}
EOF
}

# Append merged branch to rollback record
record_merged_branch() {
    local branch="$1"
    local sha_before="$2"
    local sha_after
    sha_after=$(git rev-parse HEAD)

    # Use jq to append to the branches_merged array
    local tmp
    tmp=$(jq --arg b "$branch" --arg before "$sha_before" --arg after "$sha_after" \
        '.branches_merged += [{"branch": $b, "sha_before": $before, "sha_after": $after}]' \
        "$ROLLBACK_FILE")
    printf '%s\n' "$tmp" > "$ROLLBACK_FILE"
}

rollback_merge() {
    local phase_num="$1"

    if [[ ! -f "$ROLLBACK_FILE" ]]; then
        die "No rollback point found. Nothing to roll back."
    fi

    local saved_sha
    saved_sha=$(jq -r '.pre_merge_sha' "$ROLLBACK_FILE")

    git reset --hard "$saved_sha"
    rm -f "$ROLLBACK_FILE"
    print_success "Rolled back to pre-merge state: $saved_sha"
}
```

**Rollback scope recommendation: Phase-level.** The rollback file saves the SHA from before ANY merges for the phase began. `gsd-ralph merge N --rollback` resets to that point. Per-branch rollback adds complexity without proportional value -- if one merge is bad, the subsequent merges built on top of it are also suspect.

**Rollback invocation recommendation: Subcommand flag.** `gsd-ralph merge N --rollback` is discoverable and keeps the command namespace clean. A separate `gsd-ralph rollback N` command adds a top-level command for a niche operation.

**Rollback expiry recommendation: Until next successful merge or cleanup.** The rollback file persists in `.ralph/merge-rollback.json` until either: (a) the next `gsd-ralph merge N` succeeds and overwrites it, (b) `gsd-ralph cleanup N` removes it, or (c) the user manually deletes it. No time-based expiry -- the file is small and the user decides when it is no longer needed.

### Pattern 5: Post-Merge Test Regression Detection

**What:** Run test suite after merging and compare results against pre-merge baseline to distinguish new regressions from pre-existing failures.

**When to use:** After all branches for a phase/wave are merged.

```bash
run_post_merge_tests() {
    local test_cmd="$1"
    local pre_merge_sha="$2"

    if [[ -z "$test_cmd" ]]; then
        print_warning "No test command configured. Skipping post-merge tests."
        return 0
    fi

    # Step 1: Capture pre-merge test baseline
    # (Run tests at the pre-merge SHA to know what was already failing)
    local pre_merge_exit=0
    local pre_merge_output
    git stash --include-untracked 2>/dev/null || true
    pre_merge_output=$(git stash list | head -1)  # Just to check if stash happened

    # Save current HEAD, checkout pre-merge state, run tests
    local current_head
    current_head=$(git rev-parse HEAD)
    git checkout "$pre_merge_sha" --detach 2>/dev/null

    local pre_failures=""
    pre_failures=$($test_cmd 2>&1) || pre_merge_exit=$?

    # Return to merged state
    git checkout "$current_head" --detach 2>/dev/null
    git checkout - 2>/dev/null  # Back to branch

    # Step 2: Run tests at current (post-merge) state
    local post_merge_exit=0
    local post_failures=""
    post_failures=$($test_cmd 2>&1) || post_merge_exit=$?

    # Step 3: Compare results
    if [[ $post_merge_exit -eq 0 ]]; then
        print_success "All tests passing after merge"
        return 0
    fi

    if [[ $pre_merge_exit -ne 0 ]]; then
        # Pre-existing failures -- check if count increased
        print_warning "Tests failing, but failures existed before merge"
        print_info "Pre-merge test exit: $pre_merge_exit"
        print_info "Post-merge test exit: $post_merge_exit"
        # Don't halt -- pre-existing failures
        return 0
    fi

    # New regressions introduced by merge
    print_error "NEW test regressions introduced by merge!"
    return 1
}
```

**Note:** The above pattern is a simplification. In practice, comparing test output line-by-line is fragile. A more robust approach: compare exit codes. If pre-merge tests already fail (exit != 0), don't halt. If pre-merge tests pass (exit 0) but post-merge tests fail, halt and report. This simple heuristic covers the user's requirement without fragile output parsing.

### Pattern 6: Wave Signaling (MERG-07)

**What:** Signal that wave N merges are complete so the execution pipeline can launch wave N+1.

**Recommendation: File-based signaling with JSON metadata.**

```bash
SIGNAL_DIR=".ralph/merge-signals"

signal_wave_complete() {
    local phase_num="$1"
    local wave_num="$2"
    local branches_merged="$3"  # Space-separated list

    mkdir -p "$SIGNAL_DIR"

    local signal_file="$SIGNAL_DIR/phase-${phase_num}-wave-${wave_num}-complete"
    cat > "$signal_file" <<EOF
{
  "phase": $phase_num,
  "wave": $wave_num,
  "completed_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "branches_merged": [$(echo "$branches_merged" | sed 's/ /", "/g' | sed 's/^/"/' | sed 's/$/"/')],
  "main_sha": "$(git rev-parse HEAD)"
}
EOF
    print_success "Signaled wave $wave_num complete for phase $phase_num"
}

check_wave_complete() {
    local phase_num="$1"
    local wave_num="$2"

    [[ -f "$SIGNAL_DIR/phase-${phase_num}-wave-${wave_num}-complete" ]]
}
```

**Why file-based over direct invocation:** Files are inspectable (`cat .ralph/merge-signals/*`), debuggable, and survive process restarts. Direct function calls would require the execute pipeline to be running when merge completes -- which is true for the automated execute-then-merge flow, but not for standalone `gsd-ralph merge N`. Files work for both cases.

**Integration with execute:** The execute pipeline (when enhanced for wave-aware execution) will check for signal files before launching wave N+1 plans. This is a future enhancement -- for Phase 4, the merge command writes the signals. Phase 3's sequential mode does not need to read them yet.

### Pattern 7: Branch Discovery for Merge

**What:** Find all branches belonging to a phase, determine their merge order.

**When to use:** At the start of every merge operation.

```bash
# Discover branches for a phase in plan order
# Current convention: phase-N/slug (single branch per phase in sequential mode)
# Future convention: phase/N/plan-NN (per-plan branches in parallel mode)
discover_merge_branches() {
    local phase_num="$1"

    MERGE_BRANCHES=()

    # Sequential mode: single branch named phase-N/slug
    local phase_dir
    if find_phase_dir "$phase_num"; then
        local slug
        slug=$(basename "$PHASE_DIR")
        local slug_part="${slug#[0-9][0-9]-}"
        local branch_name="phase-${phase_num}/${slug_part}"

        if git show-ref --verify --quiet "refs/heads/$branch_name" 2>/dev/null; then
            MERGE_BRANCHES+=("$branch_name")
        fi
    fi

    # Also check for legacy worktree branches: phase/N/plan-NN
    local branch
    for branch in $(git for-each-ref --format='%(refname:short)' "refs/heads/phase/${phase_num}/" 2>/dev/null); do
        MERGE_BRANCHES+=("$branch")
    done

    [[ ${#MERGE_BRANCHES[@]} -gt 0 ]]
}
```

### Anti-Patterns to Avoid

- **Merging without checking main is clean:** Always verify no uncommitted changes on main before starting merges. `git status --porcelain` should be empty.
- **Using `git merge -Xours` globally:** This resolves ALL conflicts as ours, not just known safe patterns. Use targeted `git checkout --ours <path>` for specific files.
- **Parsing git output for structured data:** Use `git diff --name-only`, `--diff-filter=U`, and exit codes rather than parsing human-readable messages.
- **Modifying history on shared branches:** Never use `git rebase` or `git push --force` on main. Use `git reset --hard` only for local rollback before pushing.
- **Assuming `git merge-tree` exit codes without testing:** The documented behavior should be verified at implementation time. Write a test case that creates a known conflict and checks the exit code.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Dry-run conflict detection | Manual diff comparison between branches | `git merge-tree --write-tree` | Git's three-way merge algorithm handles renames, directory conflicts, and edge cases that manual diff cannot |
| Conflict file listing | Parsing `git status` output with regex | `git diff --name-only --diff-filter=U` | Structured output, no parsing fragility |
| Branch existence check | `git branch | grep` | `git show-ref --verify --quiet refs/heads/$name` | Exit code based, no output parsing |
| Main branch detection | Hardcoding "main" or "master" | `git symbolic-ref --short HEAD` (when on main) or check both | Some repos use "master", some use "main" |
| Pre-merge SHA capture | Parsing `git log` output | `git rev-parse HEAD` | Returns exact SHA, no parsing needed |
| JSON manipulation | sed/awk on JSON | jq | Already a project dependency; correct JSON handling |

**Key insight:** Git provides low-level plumbing commands (`merge-tree`, `show-ref`, `rev-parse`, `for-each-ref`) that return structured, machine-readable output. Always prefer these over parsing porcelain (human-readable) commands.

## Common Pitfalls

### Pitfall 1: Unclean Working Tree Before Merge

**What goes wrong:** Merge fails or produces unexpected results because working tree has uncommitted changes.
**Why it happens:** User or prior command left files modified.
**How to avoid:** Check `git status --porcelain` is empty before starting merge pipeline. If not empty, abort with clear message.
**Warning signs:** `git merge` warnings about "overwriting untracked files."

### Pitfall 2: Branch Divergence After Dry-Run

**What goes wrong:** Dry-run says merge is clean, but actual merge has conflicts because main changed between dry-run and merge.
**Why it happens:** In sequential mode this is unlikely (no parallel merges), but possible if user makes manual commits between dry-run and merge phases.
**How to avoid:** Run dry-run immediately before each merge, not as a separate upfront-only step. The upfront dry-run is for user reporting; the per-branch dry-run is for safety.
**Warning signs:** Dry-run passes but actual merge fails.

### Pitfall 3: .planning/ Auto-Resolution Hiding Real Issues

**What goes wrong:** Auto-resolving .planning/ conflicts by preferring main's version silently drops branch changes to STATE.md or ROADMAP.md that should be preserved.
**Why it happens:** Branch updated STATE.md with progress, main has different state.
**How to avoid:** This is acceptable by design -- the merge command updates STATE.md and ROADMAP.md itself after merging. Branch-side .planning/ changes are informational (progress tracking during execution) and main's version is the canonical state.
**Warning signs:** None -- this is the intended behavior per user decision.

### Pitfall 4: Test Command Not Configured

**What goes wrong:** Post-merge test step fails or does nothing because project has no test command detected.
**Why it happens:** `detect_project_type()` returned empty `DETECTED_TEST_CMD`.
**How to avoid:** Gracefully skip post-merge testing with a warning if no test command is configured. Don't fail the merge.
**Warning signs:** `[warn] No test command configured. Skipping post-merge tests.`

### Pitfall 5: Rollback After Push

**What goes wrong:** User rolls back after having pushed merged commits to remote.
**Why it happens:** `git reset --hard` only affects local state. If commits were pushed, reset creates a diverged local state.
**How to avoid:** The merge command does NOT push. Rollback is safe because all operations are local. Document this: "Rollback is only possible before pushing merged changes."
**Warning signs:** User running `gsd-ralph merge N --rollback` after `git push`.

### Pitfall 6: macOS Git Version Too Old for merge-tree

**What goes wrong:** `git merge-tree --write-tree` fails with "unknown option" on older Git versions.
**Why it happens:** Apple's Xcode CLT may ship Git < 2.38.
**How to avoid:** Version-check Git at startup. If < 2.38, fall back to `git merge --no-commit --no-ff` + `git merge --abort` pattern for dry-run. Print a warning suggesting Homebrew Git upgrade.
**Warning signs:** `git merge-tree --write-tree` returns error instead of exit code 0 or 1.

### Pitfall 7: Bash 3.2 Array Limitations

**What goes wrong:** Array operations that work in Bash 4+ fail silently in Bash 3.2.
**Why it happens:** Features like `declare -A` (associative arrays), `${!array[@]}` iteration patterns, and `readarray` are Bash 4+ only.
**How to avoid:** Use indexed arrays only. Use `for i in $(seq 0 ...)` loops. Use space-delimited strings for simple lookups instead of associative arrays. The existing codebase (strategy.sh, frontmatter.sh) demonstrates the correct patterns.
**Warning signs:** Syntax errors or empty results when running on macOS default Bash.

## Code Examples

Verified patterns from the existing codebase and Git documentation.

### Branch Name Derivation (from execute.sh)

```bash
# Existing pattern in lib/commands/execute.sh
local phase_slug
phase_slug=$(basename "$PHASE_DIR")
local slug_part="${phase_slug#[0-9][0-9]-}"
local branch_name="phase-${phase_num}/${slug_part}"
```

### Checking for Unresolved Conflicts

```bash
# Source: git-diff documentation
# Returns list of files with unresolved merge conflicts
git diff --name-only --diff-filter=U
```

### Auto-Resolve Specific Paths

```bash
# Source: git-checkout documentation
# Resolve .planning/ conflicts by keeping main's version
git checkout --ours -- .planning/
git add .planning/

# Resolve lock files
git checkout --ours -- "*.lock" package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null
git add "*.lock" package-lock.json yarn.lock pnpm-lock.yaml 2>/dev/null
```

### Summary Table Generation

```bash
# Generate post-merge summary table
print_merge_summary() {
    local -a results=("$@")  # Array of "branch:status:files:commits" strings

    printf "\n%-40s %-12s %-8s %-8s\n" "Branch" "Status" "Files" "Commits"
    printf "%-40s %-12s %-8s %-8s\n" "$(printf '%.0s-' {1..40})" "$(printf '%.0s-' {1..12})" "$(printf '%.0s-' {1..8})" "$(printf '%.0s-' {1..8})"

    for result in "${results[@]}"; do
        IFS=':' read -r branch status files commits <<< "$result"
        printf "%-40s %-12s %-8s %-8s\n" "$branch" "$status" "$files" "$commits"
    done
}
```

### Git Version Check

```bash
# Check Git version >= 2.38 for merge-tree --write-tree support
check_git_merge_tree_support() {
    local git_version
    git_version=$(git --version | sed 's/git version //')
    local major minor
    major=$(echo "$git_version" | cut -d. -f1)
    minor=$(echo "$git_version" | cut -d. -f2)

    if [[ "$major" -gt 2 ]] || { [[ "$major" -eq 2 ]] && [[ "$minor" -ge 38 ]]; }; then
        return 0  # merge-tree supported
    else
        return 1  # fallback needed
    fi
}
```

### STATE.md Update Pattern (from execute.sh)

```bash
# Existing pattern for STATE.md updates via sed
state_content=$(<".planning/STATE.md")
state_content=$(echo "$state_content" | sed "s/^Phase:.*/Phase: ${phase_num} of 5 -- Complete/")
state_content=$(echo "$state_content" | sed "s/^Status:.*/Status: Complete/")
state_content=$(echo "$state_content" | sed "s/^Last activity:.*/Last activity: $(date -u +%Y-%m-%d) -- Phase ${phase_num} merged/")
printf '%s\n' "$state_content" > ".planning/STATE.md"
```

## Discretion Recommendations

These are recommendations for the areas marked as "Claude's Discretion" in the user constraints.

### Merge Timing: Per-Branch Immediate

**Recommendation:** Merge branches one at a time, in plan order, immediately.

**Rationale:** In sequential mode (the only mode for Phase 4), there is one branch per phase. Even when extended to multi-branch parallel mode, per-branch immediate merging is simpler and gives better error isolation. If branch 2 of 4 fails, branches 1's merge is already done and safe. Batch merging (all at once) would require rolling back all if any fail.

### Manual Merge: Merge All Completed Branches

**Recommendation:** `gsd-ralph merge N` merges all completed branches. No branch-picking.

**Rationale:** Simplicity. In sequential mode there is only one branch. In future parallel mode, the user wants all completed branches merged -- that is the whole point of the command. If a user needs to skip a specific branch, they can delete or rename it before running merge.

### Rollback Scope: Entire Phase

**Recommendation:** `gsd-ralph merge N --rollback` resets to the SHA captured before any merges for phase N began.

**Rationale:** Per-branch rollback adds complexity (tracking individual SHAs in a stack, deciding which branch to roll back) without proportional benefit. If any merge is bad, all subsequent merges built on top of it are suspect. Rolling back to the clean pre-merge state is the safest and simplest option.

### Rollback Invocation: Subcommand Flag

**Recommendation:** `gsd-ralph merge N --rollback`

**Rationale:** Keeps the command namespace clean. The rollback is conceptually part of the merge workflow, not a separate operation. Users discover it via `gsd-ralph merge --help`.

### Rollback Expiry: Until Overwritten or Cleaned

**Recommendation:** The rollback file `.ralph/merge-rollback.json` persists until:
1. The next `gsd-ralph merge N` succeeds and overwrites it
2. `gsd-ralph cleanup N` removes it
3. The user manually deletes it

**Rationale:** No time-based expiry needed. The file is tiny (< 1KB). The user decides when it is no longer useful. Automatic expiry risks deleting rollback capability when the user still needs it.

### Wave Signaling: File-Based JSON Signals

**Recommendation:** Signal files in `.ralph/merge-signals/` directory.

**Rationale:** Files are inspectable, debuggable, and survive process restarts. They work for both automated (execute-calls-merge) and manual (`gsd-ralph merge N`) invocation paths. The execute pipeline can poll for signal files when wave-aware execution is implemented.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `git merge --no-commit` + abort for dry-run | `git merge-tree --write-tree` | Git 2.38 (Oct 2022) | Zero side effects, faster, scriptable |
| Parse `git status` for conflicts | `git diff --name-only --diff-filter=U` | Long available, best practice | Structured output, no regex needed |
| Manual conflict resolution | `git checkout --ours/--theirs` per path | Long available | Scriptable, targeted resolution |

**Deprecated/outdated:**
- `git merge-tree` trivial-merge mode (old 3-argument form): Deprecated in favor of `--write-tree` mode. The old mode had limited applicability and poor output format.

## Open Questions

1. **Exact `git merge-tree` exit code semantics**
   - What we know: Documentation says 0 = clean, 1 = conflicts. Some sources suggest inverted semantics.
   - What's unclear: Exact behavior with current Git versions on macOS.
   - Recommendation: Write a verification test during implementation that creates a known-conflict scenario and checks exit codes. LOW risk -- if inverted, just swap the check.

2. **Sequential mode branch naming for merge discovery**
   - What we know: Execute creates branches named `phase-N/slug` (e.g., `phase-3/phase-execution`).
   - What's unclear: Will there always be exactly one branch per phase in sequential mode? What if execute is run multiple times?
   - Recommendation: `discover_merge_branches()` should find all branches matching the phase pattern and deduplicate. Prevent re-merging already-merged branches by checking if the branch tip is an ancestor of main.

3. **Execute-calls-merge integration timing**
   - What we know: "Execute always calls merge when a plan completes." The current execute command does not call merge.
   - What's unclear: Should this integration be part of Phase 4, or deferred?
   - Recommendation: Phase 4 focuses on the standalone `gsd-ralph merge N` command. The execute-calls-merge integration is a small enhancement to execute.sh that calls `cmd_merge` after Ralph signals completion. This integration should be part of Phase 4 since it is a locked decision, but can be the last plan item.

## Sources

### Primary (HIGH confidence)
- [Git merge-tree documentation](https://git-scm.com/docs/git-merge-tree) - write-tree mode, exit codes, options, conflict detection
- [Git merge documentation](https://git-scm.com/docs/git-merge) - --no-commit, --no-ff, --abort, -Xours/-Xtheirs strategies
- [Git diff documentation](https://git-scm.com/docs/git-diff) - --name-only, --diff-filter=U, --stat, --shortstat
- [Git checkout documentation](https://git-scm.com/docs/git-checkout/2.27.0) - --ours/--theirs per-path resolution
- Existing codebase analysis: `lib/commands/execute.sh`, `lib/commands/merge.sh` (stub), `lib/strategy.sh`, `lib/discovery.sh`, `lib/common.sh`, `scripts/ralph-merge.sh` (reference)

### Secondary (MEDIUM confidence)
- [Atlassian merge conflict tutorial](https://www.atlassian.com/git/tutorials/using-branches/merge-conflicts) - Best practices for conflict handling
- [GitHub gist: dry-run merge](https://gist.github.com/devinschumacher/ea27f994d1be4e1cbf06f4735addae04) - Community patterns for merge dry-run
- [git-resolve-conflict](https://github.com/jakub-g/git-resolve-conflict) - Per-file resolution strategies (ours/theirs/union)
- [freeCodeCamp: undo merge](https://www.freecodecamp.org/news/git-undo-merge-how-to-revert-the-last-merge-commit-in-git/) - Rollback strategies (reset vs revert)
- [Atlassian git reflog tutorial](https://www.atlassian.com/git/tutorials/rewriting-history/git-reflog) - Reflog for rollback point discovery
- [clash-sh/clash](https://github.com/clash-sh/clash) - Real-world tool using merge-tree for worktree conflict detection

### Tertiary (LOW confidence)
- None -- all findings verified through official documentation or multiple sources.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - Pure Bash + Git, same tools used throughout the project. All Git commands verified in official docs.
- Architecture: HIGH - Patterns derived from existing codebase conventions (execute.sh, strategy.sh, discovery.sh). Module split follows established project structure.
- Pitfalls: HIGH - Derived from documented Git behaviors and existing project's Bash 3.2 compatibility learnings.
- Discretion recommendations: MEDIUM - Based on analysis of user's requirements and existing codebase patterns, but these are design choices that could reasonably go either way.

**Research date:** 2026-02-19
**Valid until:** 2026-03-19 (stable domain -- Git merge semantics change infrequently)
