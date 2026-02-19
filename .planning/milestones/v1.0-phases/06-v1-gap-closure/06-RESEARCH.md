# Phase 6: v1 Gap Closure - Research

**Researched:** 2026-02-19
**Domain:** Bash CLI gap closure (terminal bell, retroactive verification, metadata cleanup, tech debt)
**Confidence:** HIGH

## Summary

Phase 6 closes five categories of gaps identified in the v1 milestone audit. The work is entirely internal to the existing gsd-ralph codebase -- no new libraries, no new architectural patterns, no external dependencies. Every gap has a clear, verified fix path.

The five categories are: (1) terminal bell implementation for EXEC-06, (2) retroactive VERIFICATION.md files for Phases 1 and 2, (3) REQUIREMENTS.md checkbox updates, (4) code quality fixes (`.gitignore`, orphaned code, stale references), and (5) SUMMARY frontmatter corrections for Phases 1-3. The terminal bell is the only new code; everything else is documentation or deletion.

**Primary recommendation:** Structure as two plans -- one for the terminal bell feature (code + tests), one for all documentation/metadata/tech debt items (no runtime code changes). This keeps the code-change plan testable and the documentation plan auditable without test overhead.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| EXEC-06 | Tool triggers terminal bell when all plans complete or any plan fails | Terminal bell implementation section below provides exact insertion points in execute.sh and merge.sh, verified `printf '\a'` and `tput bel` both work on macOS Bash 3.2. Bell fires at: execute completion (line 242), execute failure (die calls), merge success (line 418), merge failure (line 416). |
</phase_requirements>

## Standard Stack

### Core

No new libraries or dependencies required. Phase 6 operates entirely within the existing stack.

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Bash | 3.2+ | All implementation | macOS system bash; project requirement |
| `printf '\a'` | N/A | Terminal bell character (BEL, ASCII 0x07) | POSIX-standard; works in Bash 3.2; lighter than `tput bel` |
| `tput bel` | N/A | Alternative terminal bell | More portable across terminal types but requires `tput` binary |
| bats-core | submodule | Testing terminal bell behavior | Already in project test infrastructure |
| ShellCheck | 0.10+ | Lint validation | Already required by `make lint` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `printf '\a'` | `tput bel` | `tput bel` is marginally more portable across exotic terminals but adds a subprocess call; `printf '\a'` is simpler, POSIX-standard, and works in all modern terminal emulators |
| `printf '\a'` | `echo -e '\a'` | `echo -e` is not portable (different behavior on macOS vs. GNU); `printf` is always safe |

**Recommendation:** Use `printf '\a'` for the bell. It is POSIX-standard, works on macOS Bash 3.2 (verified), and matches the project's existing `printf`-based output patterns in `lib/common.sh`.

## Architecture Patterns

### Terminal Bell Insertion Points

The EXEC-06 requirement specifies three trigger conditions:
1. Execute completion (all plans set up successfully)
2. Execute failure (any error during setup)
3. Merge completion (all branches merged)

**Execute command (`lib/commands/execute.sh`):**
- **Success bell:** After the "Run 'ralph' to start execution" line (line 242). This is the final output of a successful execute.
- **Failure bell:** Via the `die` function. Rather than modifying every `die` call, add a bell to the `die` function in `lib/common.sh` so all fatal errors ring the bell project-wide. However, this affects ALL commands, which may be undesirable for simple validation failures (e.g., "Phase number required"). Better approach: add a dedicated `bell` or `notify_bell` function and call it explicitly at the two key exit points.

**Merge command (`lib/commands/merge.sh`):**
- **Success bell:** At the end of `cmd_merge` when returning 0 (all branches merged, no conflicts, tests pass).
- **Failure bell:** At the end of `cmd_merge` when returning 1 (skipped branches, conflicts, or test regressions).

**Recommended pattern -- a `ring_bell` function in `lib/common.sh`:**

```bash
# Ring the terminal bell to notify the user.
# Fires on long-running command completion or failure.
ring_bell() {
    printf '\a'
}
```

Then call `ring_bell` at these four points:
1. `execute.sh` line 242 (after "Run 'ralph' to start execution")
2. `execute.sh` -- before any `exit 1` after the branch has been created (to signal setup failure after significant work)
3. `merge.sh` before `return 0` at end of `cmd_merge` (success)
4. `merge.sh` before `return 1` at end of `cmd_merge` (failure)

**Design decision -- when NOT to bell:**
- Simple validation errors (missing args, not in git repo) should NOT ring the bell. These are instantaneous and the user is already watching.
- The bell should only fire after operations that take meaningful time (execute setup, merge pipeline).

### Retroactive Verification Pattern

Phases 3-5 have VERIFICATION.md files with a consistent format (YAML frontmatter + structured sections). Phases 1 and 2 need identical treatment. The verification should be generated by examining:

1. **Test results:** All 169 tests currently pass. Phase 1 tests: 9 common + 8 config + 21 init = 38. Phase 2 tests: 12 discovery + 12 prompt + 17 generate = 41.
2. **Code inspection:** All implementation files exist and are substantive (no stubs).
3. **Requirements mapping:** Each requirement maps to specific functions and test cases.

The retroactive VERIFICATION.md files should follow the exact format of `03-VERIFICATION.md`, `04-VERIFICATION.md`, and `05-VERIFICATION.md`:

```markdown
---
phase: NN-slug
verified: YYYY-MM-DDTHH:MM:SSZ
status: passed|human_needed
score: X/Y success criteria verified
re_verification: true  # Because these are retroactive
---
```

### REQUIREMENTS.md Checkbox Update Pattern

Current state: 9/20 v1 checkboxes are checked (all MERG-* and CLEN-*). After Phase 6:
- INIT-01, INIT-02, INIT-03: Check (implementation complete, tests pass)
- EXEC-01: Check (implementation complete with adaptation note)
- EXEC-02, EXEC-03, EXEC-04: Check (implementation complete, tests pass)
- EXEC-05: Check (implementation complete)
- EXEC-06: Check (after terminal bell implementation)
- EXEC-07: Check (implementation complete, tests pass)
- XCUT-01: Check (implementation complete, tests pass)

This brings the count from 9/20 to 20/20. The traceability table status values should also be updated from "Pending" to "Complete" for all checked requirements.

### Tech Debt Resolution

Five specific items from the audit:

| Item | File | Fix | Risk |
|------|------|-----|------|
| `.ralph/worktree-registry.json` not in `.gitignore` | `.gitignore` | Add `.ralph/worktree-registry.json` line | NONE -- purely additive |
| `scripts/ralph-execute.sh` step 7 references `ralph-cleanup.sh` | `scripts/ralph-execute.sh` line 300 | Change `./scripts/ralph-cleanup.sh` to `gsd-ralph cleanup` | LOW -- reference script, not core CLI |
| `worktree_path_for_plan` orphaned in `lib/discovery.sh` | `lib/discovery.sh` lines 73-79 | Remove function | LOW -- has one test in `discovery.bats` that must also be removed |
| `status` command stub advertised in usage | `lib/commands/status.sh` | Leave as-is (STAT-01 is v2) | N/A -- audit noted but not actionable for v1 |
| `EXEC-01` requirement text says "worktree per plan" | `REQUIREMENTS.md` line 18 | Update text to match branch-based implementation | NONE -- documentation only |
| ShellCheck SC2034 in `cleanup.sh` | `lib/commands/cleanup.sh` line 42 | Add `# shellcheck disable=SC2034` before `while` loop (matches execute.sh, generate.sh, merge.sh pattern) | NONE -- consistent with existing codebase pattern |

**Note on the `status` command stub:** The audit flags it as tech debt, but STAT-01 is explicitly a v2 requirement. The stub exists so the CLI dispatch works if someone types `gsd-ralph status`. The success criteria for Phase 6 say "orphaned code removed" -- but `status.sh` is not orphaned; it is a deliberate placeholder for v2. Recommendation: leave it. If the planner disagrees, the stub is 6 lines and can be removed trivially.

**Note on `WORKFLOW.md` and `templates/WORKFLOW.md.template`:** These files also reference `ralph-cleanup.sh` but they are reference/documentation files from the original bayesian-it extraction. Updating them is optional cleanup -- the primary fix target per the audit is `scripts/ralph-execute.sh` only.

### SUMMARY Frontmatter Corrections

Three SUMMARY files need YAML frontmatter additions:

1. **`01-02-SUMMARY.md`**: Has no YAML frontmatter at all. Needs frontmatter block with `phase`, `plan`, `subsystem`, `requirements-completed`, etc.
2. **`02-01-SUMMARY.md`**: Has no YAML frontmatter. Needs frontmatter block.
3. **`02-02-SUMMARY.md`**: Has no YAML frontmatter. Needs frontmatter block.
4. **`03-02-SUMMARY.md`**: Has frontmatter but `requirements-completed: []` should list EXEC-01, EXEC-05.

The frontmatter format follows the pattern established by `03-02-SUMMARY.md`:
```yaml
---
phase: NN-slug
plan: MM
subsystem: name
tags: [...]
requires: [...]
provides: [...]
affects: [...]
tech-stack: ...
key-files: ...
key-decisions: [...]
patterns-established: [...]
requirements-completed: [REQ-ID, ...]
duration: Xmin
completed: YYYY-MM-DD
---
```

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Terminal bell | Custom notification system | `printf '\a'` | POSIX standard, works everywhere, zero dependencies |
| Verification reports | Automated test-to-report tool | Manual structured markdown | Only 2 reports needed; automation would be over-engineering |
| Checkbox updates | Script to parse/update markdown | Manual edit | Single file, 11 checkboxes; a script would be harder to verify than the edit |

**Key insight:** Phase 6 is primarily editorial/cleanup work. The only new runtime code is the terminal bell (~5 lines). Everything else is documentation updates that should be done carefully by hand, not automated.

## Common Pitfalls

### Pitfall 1: Bell Fires on Trivial Errors
**What goes wrong:** Adding bell to `die()` makes every trivial error (missing args, wrong directory) ring the bell, annoying users.
**Why it happens:** Temptation to centralize bell in the error handler.
**How to avoid:** Only ring bell after operations that take meaningful time. Add `ring_bell` calls at specific exit points in execute and merge, not in `die()`.
**Warning signs:** Bell fires during `gsd-ralph execute` without a phase number.

### Pitfall 2: Removing worktree_path_for_plan Breaks Tests
**What goes wrong:** Removing the function from `discovery.sh` without removing its test from `discovery.bats` causes test failure.
**Why it happens:** Function and test are in different files.
**How to avoid:** Remove function AND test together. The test is at `tests/discovery.bats` lines 132-138.
**Warning signs:** `make test` fails after function removal.

### Pitfall 3: Retroactive Verification Claims Unverified Facts
**What goes wrong:** Writing a VERIFICATION.md that says "VERIFIED" for things not actually checked.
**Why it happens:** Retroactive verification is done from summaries and test counts rather than live verification runs.
**How to avoid:** Base all claims on observable evidence: test counts from `make test`, code inspection of specific line numbers, ShellCheck results. Flag anything that cannot be verified retroactively as "human_needed".
**Warning signs:** VERIFICATION.md claims "all tests pass" without citing test numbers.

### Pitfall 4: ShellCheck Lint Regression
**What goes wrong:** Adding `ring_bell` function and calls introduces new ShellCheck warnings.
**Why it happens:** New function might use patterns ShellCheck flags (unused variables, etc.).
**How to avoid:** Run `make lint` after every code change. The existing SC2034 pattern in cleanup.sh already fails lint -- fix it as part of this phase.
**Warning signs:** `make check` fails on lint step.

### Pitfall 5: REQUIREMENTS.md Checkbox Count Mismatch
**What goes wrong:** Checking boxes for requirements that aren't actually complete yet (EXEC-06 before implementation).
**Why it happens:** Doing documentation updates before code changes.
**How to avoid:** Implement terminal bell first, then check EXEC-06 box. Or: structure plans so code plan completes before documentation plan.
**Warning signs:** Requirements marked complete but code doesn't exist yet.

## Code Examples

### Terminal Bell Function

```bash
# Source: Verified on macOS Bash 3.2.57 (2026-02-19)
# lib/common.sh addition

# Ring the terminal bell to notify the user of command completion.
# Called after long-running operations (execute, merge) succeed or fail.
ring_bell() {
    printf '\a'
}
```

### Execute Command Bell Integration

```bash
# Source: lib/commands/execute.sh -- additions at end of cmd_execute

    # Step 13: Print launch instructions
    printf "\n"
    print_success "Run 'ralph' to start execution"
    ring_bell
}
```

### Merge Command Bell Integration

```bash
# Source: lib/commands/merge.sh -- additions at end of cmd_merge

    # Return non-zero if any branches were skipped, had dry-run conflicts, or tests failed
    local conflict_branch_count=${#conflict_branches[@]}
    if [[ $skip_count -gt 0 ]] || [[ $conflict_branch_count -gt 0 ]] || [[ "$test_failed" == true ]]; then
        ring_bell
        return 1
    fi
    ring_bell
    return 0
}
```

### Testing Terminal Bell in Bats

```bash
# Bats cannot detect the actual bell character in terminal output,
# but we CAN verify ring_bell is called by checking output contains '\a'
# or by mocking ring_bell and verifying it was called.

# Approach 1: Verify the function exists and is callable
@test "ring_bell function exists" {
    run ring_bell
    assert_success
}

# Approach 2: Verify execute output includes bell (captured as part of output)
# Note: bats captures stdout, and printf '\a' writes to stdout,
# so we can check for the BEL character (hex 07) in output
@test "execute rings terminal bell on completion" {
    # ... setup ...
    run gsd-ralph execute "$PHASE_NUM"
    assert_success
    # BEL character is ASCII 0x07; check it's in the output
    [[ "$output" == *$'\a'* ]]
}
```

### .gitignore Addition

```
# Worktree registry (runtime artifact, not committed)
.ralph/worktree-registry.json
```

### Orphaned Function Removal

```bash
# REMOVE from lib/discovery.sh (lines 70-79):
# worktree_path_for_plan() { ... }

# REMOVE from tests/discovery.bats (lines 132-138):
# @test "worktree_path_for_plan computes correct path" { ... }
```

### ShellCheck Fix for cleanup.sh

```bash
# lib/commands/cleanup.sh -- add SC2034 disable before while loop
# (matches pattern in execute.sh line 44, generate.sh line 38, merge.sh line 120)

    # shellcheck disable=SC2034
    while [[ $# -gt 0 ]]; do
```

## State of the Art

Not applicable -- Phase 6 is entirely internal cleanup work. No external technology changes affect this phase.

## Open Questions

1. **Should `ring_bell` also fire on `cleanup` command completion?**
   - What we know: The EXEC-06 requirement says "when all plans complete or any plan fails." Cleanup is not plan execution.
   - What's unclear: Whether the user expects a bell after `gsd-ralph cleanup N`.
   - Recommendation: Do NOT add bell to cleanup. The requirement is specific to execute and merge. Cleanup is fast and the user watches it.

2. **Should the status command stub be removed?**
   - What we know: STAT-01 is a v2 requirement. The stub exists at `lib/commands/status.sh` (6 lines).
   - What's unclear: Whether "orphaned code removed" in success criteria includes deliberate v2 stubs.
   - Recommendation: Leave it. It is not orphaned -- it is a placeholder. Removing it would break `gsd-ralph status` entirely (currently gives "Not yet implemented" which is informative). The audit specifically identifies `worktree_path_for_plan` as the orphaned code, not the status stub.

3. **Should `WORKFLOW.md` and `templates/WORKFLOW.md.template` be updated to reference `gsd-ralph cleanup` instead of `ralph-cleanup.sh`?**
   - What we know: The audit specifically targets `scripts/ralph-execute.sh` step 7. WORKFLOW.md is a reference document from the original extraction.
   - What's unclear: Whether the success criteria "script references fixed" extends beyond `ralph-execute.sh`.
   - Recommendation: Fix `ralph-execute.sh` as required. Optionally fix `WORKFLOW.md` and the template if the planner includes it, but it is not strictly required by the audit.

4. **Should `EXEC-01` requirement text be updated from "worktree per plan" to match branch-based implementation?**
   - What we know: The audit identifies this as tech debt. The Phase 3 verification notes the adaptation.
   - What's unclear: Whether changing the requirement text is appropriate or whether the adaptation should remain documented as a deviation.
   - Recommendation: Update the requirement text to say "execution environment" instead of "worktree per plan" and add a parenthetical "(branch-based)" to reflect the actual implementation. This matches how Phase 3 verification describes it.

## Sources

### Primary (HIGH confidence)
- Direct codebase inspection of all files referenced (lib/commands/execute.sh, lib/commands/merge.sh, lib/commands/cleanup.sh, lib/common.sh, lib/discovery.sh, .gitignore, scripts/ralph-execute.sh, lib/merge/signals.sh)
- `.planning/v1-MILESTONE-AUDIT.md` -- complete audit with specific line numbers and evidence
- `.planning/phases/03-phase-execution/03-VERIFICATION.md` -- verification format reference
- `.planning/phases/05-cleanup/05-VERIFICATION.md` -- verification format reference
- `.planning/phases/04-merge-orchestration/04-VERIFICATION.md` -- verification format reference
- `make check` output -- 169/169 tests pass, ShellCheck has 1 known issue (SC2034 in cleanup.sh)
- macOS Bash 3.2.57 verification of `printf '\a'` and `tput bel`

### Secondary (MEDIUM confidence)
- `.planning/research/STACK.md` -- original project research recommending `tput bel`
- `.planning/REQUIREMENTS.md` -- requirements definitions and traceability table
- `.planning/ROADMAP.md` -- phase definitions and success criteria
- SUMMARY files for Phases 1-3 -- evidence of what was implemented

### Tertiary (LOW confidence)
- None -- all findings are based on direct code inspection and verified behavior.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new dependencies; verified existing tools
- Architecture: HIGH -- insertion points identified with exact line numbers; patterns verified against existing code
- Pitfalls: HIGH -- all pitfalls identified from direct codebase analysis; no speculation
- Terminal bell: HIGH -- `printf '\a'` verified on macOS Bash 3.2.57 in this session

**Research date:** 2026-02-19
**Valid until:** Indefinitely (internal codebase analysis, no external dependencies)
