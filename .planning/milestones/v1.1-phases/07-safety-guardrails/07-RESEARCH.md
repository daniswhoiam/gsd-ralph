# Phase 7: Safety Guardrails - Research

**Researched:** 2026-02-23
**Domain:** Bash CLI tool safety hardening -- elimination of data-loss vectors in file/directory deletion paths
**Confidence:** HIGH

## Summary

Phase 7 addresses a confirmed production data-loss bug and hardens all deletion paths in gsd-ralph. The critical bug is a three-part failure chain: (1) `execute.sh` registers `$(pwd)` -- the project root -- as a worktree path during sequential mode, (2) `cleanup.sh` runs `git worktree remove` on that path which fails because it is the main working tree, and (3) the `rm -rf` fallback on line 180 then deletes the entire project directory. This caused real data loss in the vibecheck project (documented in STATE.md).

The fix requires four coordinated changes mapped to the four SAFE requirements: remove the `rm -rf` fallback entirely (SAFE-01), create a centralized `safe_remove()` guard function that refuses to remove HOME, `/`, or the git toplevel (SAFE-02/SAFE-04), prevent sequential-mode execution from registering the main working tree as removable (SAFE-03), and audit every `rm` call in the codebase to route through the guard (SAFE-04). All changes use existing Bash builtins and git commands -- no new dependencies required.

**Primary recommendation:** Create `lib/safety.sh` with a `safe_remove()` guard function, remove the `rm -rf` fallback in cleanup.sh, add a main-worktree guard to `register_worktree()`, and audit+route all five existing `rm` calls through the guard where appropriate.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| SAFE-01 | Cleanup command never uses rm -rf as fallback for failed worktree removal | Remove `rm -rf "$wt_path"` fallback at cleanup.sh:180; if `git worktree remove` fails, report error and skip (Architecture Pattern 1, Code Example 1) |
| SAFE-02 | All file/directory deletions go through a safe_remove() guard that refuses to remove git toplevel, HOME, or / | Create `lib/safety.sh` with `safe_remove()` function using `[[ -ef ]]` for inode-level path comparison (Architecture Pattern 2, Code Example 2) |
| SAFE-03 | Registry distinguishes worktree-mode vs in-place execution, preventing main working tree from being registered as removable | Add guard to `register_worktree()` in registry.sh that skips registration when path equals git toplevel; cleanup.sh treats such entries as branch-only (Architecture Pattern 3, Code Example 3) |
| SAFE-04 | All existing rm calls across the codebase are audited and routed through safe_remove() | Complete audit identifies 5 `rm` call sites; each categorized as directory-removal (must guard) or known-safe file removal (known paths under .ralph/); all directory removals route through safe_remove() (Audit section below) |
</phase_requirements>

## Standard Stack

### Core

No new libraries or dependencies. Phase 7 uses exclusively existing Bash builtins and git commands.

| Technique | Purpose | Why Standard | Confidence |
|-----------|---------|--------------|------------|
| `[[ "$path1" -ef "$path2" ]]` | Inode-level path comparison | Compares filesystem inodes; handles symlinks, trailing slashes, relative vs absolute. Works in Bash 3.2 on macOS. Verified on darwin24/arm64 | HIGH |
| `cd "$dir" && pwd -P` | Resolve symlinks to canonical path | Pure Bash builtin; `-P` resolves symlinks. Use for path normalization before comparison | HIGH |
| `git rev-parse --show-toplevel` | Get canonical project root path | Already used in codebase (execute.sh:109, generate.sh:95, init.sh:70). Returns absolute path of repo root | HIGH |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `[[ -ef ]]` | String comparison of resolved paths | `-ef` is more robust -- handles mount points, bind mounts, symlinks at the inode level. String comparison fails on symlinked paths |
| `cd && pwd -P` | `realpath` command | `realpath` not available on macOS by default (requires Homebrew coreutils). `pwd -P` is a Bash builtin with zero dependencies |
| `cd && pwd -P` | `readlink -f` | BSD `readlink` on macOS does not support `-f` flag. Only works on GNU/Linux |

**Installation:**
```bash
# No new dependencies to install
# Existing stack is sufficient: bash 3.2+, git 2.20+, jq 1.6+
```

## Architecture Patterns

### Recommended Project Structure

```
lib/
  safety.sh           # NEW: safe_remove(), assert_safe_to_remove(), validate_registry_path()
  common.sh           # UNCHANGED (safety.sh is separate for clean sourcing)
  cleanup/
    registry.sh       # MODIFIED: register_worktree() guards against main worktree
  commands/
    cleanup.sh        # MODIFIED: rm-rf fallback removed, safety guards added
    execute.sh        # UNCHANGED (registry guard handles the fix at registration time)
```

### Pattern 1: Remove rm-rf Fallback (SAFE-01)

**What:** Replace the `rm -rf` fallback on worktree removal failure with error reporting and skip.
**When to use:** When `git worktree remove --force` fails on a registered path.
**Current dangerous code (cleanup.sh:174-183):**

```bash
# CURRENT -- DANGEROUS
if [[ -d "$wt_path" ]]; then
    if git worktree remove --force "$wt_path" 2>/dev/null; then
        print_verbose "Removed worktree: $wt_path"
        wt_removed=$((wt_removed + 1))
    else
        # Fallback: force remove directory
        rm -rf "$wt_path" 2>/dev/null || true          # <-- LINE 180: THE BUG
        print_verbose "Force-removed worktree directory: $wt_path"
        wt_removed=$((wt_removed + 1))
    fi
fi
```

**Replacement pattern:**

```bash
# FIXED -- safe
if [[ -d "$wt_path" ]]; then
    if git worktree remove --force "$wt_path" 2>/dev/null; then
        print_verbose "Removed worktree: $wt_path"
        wt_removed=$((wt_removed + 1))
    else
        print_warning "Failed to remove worktree: $wt_path"
        print_warning "Manual cleanup may be needed: git worktree remove --force '$wt_path'"
        wt_failed=$((wt_failed + 1))
    fi
fi
```

**Key design decision:** When `git worktree remove` fails, the correct response is to report the error, NOT to escalate to a more destructive operation. The `--force` flag on cleanup should only affect branch deletion (`-d` vs `-D`) and confirmation prompts -- it must NEVER bypass path safety checks.

### Pattern 2: Centralized safe_remove() Guard (SAFE-02, SAFE-04)

**What:** A single guard function that every file/directory deletion routes through. Refuses to remove dangerous paths.
**When to use:** Before any `rm -rf` or `rm -r` call that takes a variable path (not a hardcoded known-safe path).

```bash
# lib/safety.sh

# Guard function: validates a path is safe to remove.
# Returns 0 if safe, 1 if dangerous (with error message).
# Checks: empty/unset, filesystem root, home directory, git toplevel, parent of .git.
safe_remove() {
    local target_path="$1"
    local removal_type="${2:-file}"   # "file" or "directory"

    # Block: empty or unset path
    if [[ -z "$target_path" ]]; then
        print_error "SAFETY: Refusing to remove empty path"
        return 1
    fi

    # Resolve to absolute path for comparison
    local abs_path
    if [[ -d "$target_path" ]]; then
        abs_path=$(cd "$target_path" 2>/dev/null && pwd -P) || abs_path="$target_path"
    else
        # For files, resolve the parent directory
        local parent_dir
        parent_dir=$(cd "$(dirname "$target_path")" 2>/dev/null && pwd -P) || parent_dir=$(dirname "$target_path")
        abs_path="${parent_dir}/$(basename "$target_path")"
    fi

    # Block: filesystem root
    if [[ "$abs_path" == "/" ]]; then
        print_error "SAFETY: Refusing to remove filesystem root"
        return 1
    fi

    # Block: home directory
    if [[ -n "$HOME" ]] && [[ "$abs_path" -ef "$HOME" ]]; then
        print_error "SAFETY: Refusing to remove home directory: $abs_path"
        return 1
    fi

    # Block: git toplevel (project root)
    local git_toplevel
    git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_toplevel" ]] && [[ "$abs_path" -ef "$git_toplevel" ]]; then
        print_error "SAFETY: Refusing to remove project root directory: $abs_path"
        return 1
    fi

    # Passed all checks -- perform the removal
    if [[ "$removal_type" == "directory" ]]; then
        rm -rf "$target_path"
    else
        rm -f "$target_path"
    fi
}
```

**Design decisions:**
- Uses `[[ -ef ]]` for inode-level comparison (handles symlinks, mount points, trailing slashes)
- Checks empty path first (prevents `rm -rf ""` which can become `rm -rf .` on some shells)
- The guard IS the removal function -- callers do not call `rm` directly, they call `safe_remove`
- For known-safe file paths (hardcoded paths like `.ralph/merge-rollback.json`), the guard adds minimal overhead but prevents future bugs if the path variable becomes dynamic

### Pattern 3: Main Worktree Registration Guard (SAFE-03)

**What:** Prevent `register_worktree()` from storing the project root as a removable worktree path.
**When to use:** In sequential mode, where `execute.sh` creates a branch in the main working tree rather than creating a separate worktree directory.

**Current problematic code (execute.sh:160):**
```bash
register_worktree "$phase_num" "$(pwd)" "$branch_name"
# In sequential mode, $(pwd) IS the project root
```

**Fix location -- in registry.sh `register_worktree()`:**

```bash
register_worktree() {
    local phase_num="$1"
    local worktree_path="$2"
    local branch_name="$3"

    # SAFETY: Never register the main working tree as removable
    local git_toplevel
    git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_toplevel" ]] && [[ "$worktree_path" -ef "$git_toplevel" ]]; then
        print_verbose "Skipping worktree registration for main working tree (sequential mode)"
        # Still register the branch for cleanup (branch deletion is safe)
        # Use sentinel value to indicate this is NOT a removable worktree
        worktree_path="__MAIN_WORKTREE__"
    fi

    # ... rest of existing registration logic with sentinel path
}
```

**Corresponding cleanup.sh change:**
```bash
# When reading registry entries, skip worktree removal for sentinel paths
if [[ "$wt_path" == "__MAIN_WORKTREE__" ]]; then
    print_verbose "Skipping worktree removal for main working tree entry"
    # Still delete the branch (that IS safe)
else
    # Normal worktree removal path (with safety guard)
fi
```

**Design decisions:**
- Use a sentinel value `__MAIN_WORKTREE__` rather than skipping registration entirely, because the branch still needs to be tracked for cleanup (branch deletion is safe; only directory removal is dangerous)
- The guard is in `register_worktree()` not in `execute.sh` -- this is defense-in-depth; even if a future caller passes the project root, the guard catches it
- Uses `[[ -ef ]]` not string comparison, because the paths might be expressed differently (relative vs absolute, symlinked vs real)

### Anti-Patterns to Avoid

- **Conditional safety based on `--force` flag:** The `--force` flag controls branch deletion (`-d` vs `-D`) and confirmation prompts. It must NEVER bypass path safety checks. `assert_safe_to_remove` fires unconditionally regardless of any flag.
- **Guarding only the known-buggy code path:** Fixing only cleanup.sh:180 while leaving other `rm` calls unguarded perpetuates systemic risk. ALL deletion paths must be audited.
- **Using string comparison for paths:** `[[ "$a" == "$b" ]]` fails on symlinks, mount points, and trailing slashes. Always use `[[ "$a" -ef "$b" ]]` for path identity checks.
- **Keeping `rm -rf` as a fallback "just in case":** The `rm -rf` fallback IS the root cause of the data loss. If `git worktree remove` fails, the correct response is to report the error, not to escalate to a more destructive operation.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Path comparison across symlinks | Custom path normalization + string compare | `[[ "$a" -ef "$b" ]]` builtin | Bash's `-ef` operator compares at the inode level, handling symlinks, bind mounts, and all path normalization automatically |
| Path resolution to canonical form | Manual readlink/realpath chains | `cd "$dir" && pwd -P` | Pure Bash builtin; no external dependencies; works identically on macOS and Linux |
| Worktree identity detection | Parse `git worktree list` output | `[[ "$(git rev-parse --git-dir)" == "$(git rev-parse --git-common-dir)" ]]` to detect main worktree | Git's own plumbing distinguishes main vs linked worktrees; no output parsing needed |

**Key insight:** Bash 3.2 and git already provide all the safety primitives needed. The bug was not caused by missing tooling -- it was caused by missing guard discipline. The fix is architectural (centralized guard function), not technological.

## Common Pitfalls

### Pitfall 1: Incomplete rm-rf Guard Leaves New Vectors

**What goes wrong:** Only cleanup.sh:180 is patched while other `rm` calls (signal files, rollback files, temp files) remain unguarded. Future code additions with `rm` bypass the guard.
**Why it happens:** Developers fix the symptom (the specific `rm -rf` call that caused the incident) rather than the root cause (no centralized deletion guard).
**How to avoid:** Create `safe_remove()` as the ONLY way to delete files/directories. Audit all 5 existing `rm` call sites (see Audit section). Add a project rule: raw `rm` outside `safe_remove()` is a review-blocking finding.
**Warning signs:** Any raw `rm -rf` or `rm -r` in `lib/` or `bin/` outside of `safe_remove()`.

### Pitfall 2: Registry Path Mismatch After Fix

**What goes wrong:** Old v1.0 registry entries contain `$(pwd)` (the project root) as `worktree_path`. New code that reads the registry might not handle these legacy entries correctly.
**Why it happens:** The registry was designed for parallel-worktree mode but sequential mode reuses the main working tree. The impedance mismatch means old entries are semantically wrong.
**How to avoid:** When reading registry entries, check for the sentinel `__MAIN_WORKTREE__` value AND check whether the path resolves to the git toplevel (defense-in-depth for pre-migration entries). Never attempt `rm -rf` on any path without going through `safe_remove()`.
**Warning signs:** Tests only use new-format registry entries; no test for pre-existing v1.0 format.

### Pitfall 3: `rm -rf ""` Becomes `rm -rf .`

**What goes wrong:** If a variable is unset or empty, `rm -rf "$var"` on some shell configurations can remove the current directory.
**Why it happens:** Shell word splitting and glob expansion on empty strings. While `set -u` (already active via `set -euo pipefail` in the entry point) catches unset variables, it does not catch variables that are set to an empty string.
**How to avoid:** The `safe_remove()` guard checks for empty path as its first validation. This catches both unset and empty-string cases before `rm` is ever invoked.
**Warning signs:** Any `rm` call using a variable without a preceding empty-check.

### Pitfall 4: Symlink to Project Root Bypasses String Comparison

**What goes wrong:** If the worktree path stored in the registry is a symlink that resolves to the project root, a string comparison (`==`) would not detect the match.
**Why it happens:** Path comparison using strings instead of filesystem identity. A path `/tmp/link-to-project` could be a symlink to the actual project root.
**How to avoid:** Use `[[ "$a" -ef "$b" ]]` for all path identity checks. The `-ef` operator resolves through symlinks to compare actual inodes.
**Warning signs:** Any path comparison using `==` where filesystem identity matters.

## Code Examples

### Complete rm Audit

All `rm` calls in `lib/` and `bin/` (verified by grep):

| File | Line | Call | Risk Level | Action |
|------|------|------|-----------|--------|
| `lib/commands/cleanup.sh` | 180 | `rm -rf "$wt_path"` | **CRITICAL** -- variable path from registry; caused real data loss | **REMOVE ENTIRELY** -- replace with error report (Pattern 1) |
| `lib/commands/cleanup.sh` | 216 | `rm -f ".ralph/merge-signals/phase-${phase_num}-"*` | LOW -- hardcoded `.ralph/` prefix; removes signal files only | Route through `safe_remove()` for consistency and defense-in-depth |
| `lib/commands/cleanup.sh` | 223 | `rm -f ".ralph/merge-rollback.json"` | LOW -- hardcoded known path; single specific file | Route through `safe_remove()` for consistency |
| `lib/prompt.sh` | 253 | `rm -f "$temp_tasks"` | LOW -- `$temp_tasks` is `$(mktemp)`; system temp file | Route through `safe_remove()` for consistency |
| `lib/merge/rollback.sh` | 78 | `rm -f "$ROLLBACK_FILE"` | LOW -- `$ROLLBACK_FILE` is hardcoded to `.ralph/merge-rollback.json` | Route through `safe_remove()` for consistency |

**Additional rm calls in `scripts/` (legacy, pre-v1.0 ad-hoc scripts):**

| File | Line | Call | Risk Level | Action |
|------|------|------|-----------|--------|
| `scripts/ralph-cleanup.sh` | 53 | `git worktree remove "$wt" --force 2>/dev/null \|\| rm -rf "$wt"` | **CRITICAL** -- same pattern as the main bug | Route through `safe_remove()` or document as legacy/deprecated |
| `scripts/ralph-execute.sh` | 195 | `git worktree remove "$wt" --force 2>/dev/null \|\| rm -rf "$wt"` | **CRITICAL** -- same pattern | Route through `safe_remove()` or document as legacy/deprecated |
| `scripts/ralph-merge.sh` | 65 | `rm -f .ralph/fix_plan.md .ralph/status.json ...` | LOW -- hardcoded known paths | Route through `safe_remove()` or document as legacy/deprecated |

**Decision for `scripts/` directory:** These are legacy ad-hoc scripts from before the CLI was formalized. They contain the same dangerous `rm -rf` fallback pattern. Options: (a) fix them too, (b) deprecate and remove them, (c) add a deprecation warning. Recommendation: add a prominent deprecation comment and remove the `rm -rf` fallback in the scripts as well, since they may still be used by early adopters.

### Example 1: safe_remove() in lib/safety.sh

```bash
#!/bin/bash
# lib/safety.sh -- Centralized path validation and safe deletion

# Source: designed from codebase analysis and git documentation
# Addresses: SAFE-02, SAFE-04

# Validate a path is safe for removal. Refuses dangerous paths.
# Args: target_path, [removal_type: "file"|"directory"]
# Returns: 0 on success (file removed), 1 on refusal (file NOT removed)
safe_remove() {
    local target_path="$1"
    local removal_type="${2:-file}"

    # Block: empty or unset path
    if [[ -z "$target_path" ]]; then
        print_error "SAFETY: Refusing to remove empty path"
        return 1
    fi

    # Resolve to absolute path for comparison
    local abs_path
    if [[ -d "$target_path" ]]; then
        abs_path=$(cd "$target_path" 2>/dev/null && pwd -P) || abs_path="$target_path"
    else
        local parent_dir
        parent_dir=$(cd "$(dirname "$target_path")" 2>/dev/null && pwd -P) || parent_dir=$(dirname "$target_path")
        abs_path="${parent_dir}/$(basename "$target_path")"
    fi

    # Block: filesystem root
    if [[ "$abs_path" == "/" ]]; then
        print_error "SAFETY: Refusing to remove filesystem root"
        return 1
    fi

    # Block: home directory
    if [[ -n "${HOME:-}" ]] && [[ -d "$abs_path" ]] && [[ "$abs_path" -ef "$HOME" ]]; then
        print_error "SAFETY: Refusing to remove home directory: $abs_path"
        return 1
    fi

    # Block: git toplevel (project root)
    local git_toplevel
    git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_toplevel" ]] && [[ -d "$abs_path" ]] && [[ "$abs_path" -ef "$git_toplevel" ]]; then
        print_error "SAFETY: Refusing to remove project root directory: $abs_path"
        return 1
    fi

    # Passed all checks -- perform the removal
    if [[ "$removal_type" == "directory" ]]; then
        rm -rf "$target_path"
    else
        rm -f "$target_path"
    fi
}

# Validate a registry path before use.
# Returns 0 if valid, 1 if suspicious.
validate_registry_path() {
    local path="$1"

    # Must not be empty
    if [[ -z "$path" ]]; then
        print_error "SAFETY: Registry path is empty"
        return 1
    fi

    # Sentinel value for main worktree -- valid but not removable
    if [[ "$path" == "__MAIN_WORKTREE__" ]]; then
        return 0
    fi

    # Must be absolute
    if [[ "$path" != /* ]]; then
        print_error "SAFETY: Registry path is not absolute: $path"
        return 1
    fi

    # Must not contain path traversal
    case "$path" in
        *..*)
            print_error "SAFETY: Registry path contains traversal: $path"
            return 1
            ;;
    esac

    return 0
}
```

### Example 2: Updated register_worktree() in registry.sh

```bash
# In register_worktree() -- add at the top, before init_registry call:
register_worktree() {
    local phase_num="$1"
    local worktree_path="$2"
    local branch_name="$3"

    # SAFETY (SAFE-03): Never register the main working tree as removable
    local git_toplevel
    git_toplevel=$(git rev-parse --show-toplevel 2>/dev/null) || true
    if [[ -n "$git_toplevel" ]] && [[ "$worktree_path" -ef "$git_toplevel" ]]; then
        print_verbose "Main working tree detected; registering as non-removable (sequential mode)"
        worktree_path="__MAIN_WORKTREE__"
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    init_registry

    local tmp
    tmp=$(jq --arg phase "$phase_num" \
             --arg wt "$worktree_path" \
             --arg br "$branch_name" \
             --arg ts "$timestamp" \
        'if .[$phase] then
            .[$phase] += [{"worktree_path": $wt, "branch": $br, "created_at": $ts}]
         else
            .[$phase] = [{"worktree_path": $wt, "branch": $br, "created_at": $ts}]
         end' "$WORKTREE_REGISTRY")
    printf '%s\n' "$tmp" > "$WORKTREE_REGISTRY"

    print_verbose "Registered worktree for phase $phase_num: $branch_name"
    return 0
}
```

### Example 3: Updated cleanup.sh worktree removal loop

```bash
# Replace the worktree removal section (currently lines 168-210):
i=0
while [[ $i -lt $entry_count ]]; do
    local wt_path br_name
    wt_path=$(printf '%s' "$registry_json" | jq -r ".[$i].worktree_path")
    br_name=$(printf '%s' "$registry_json" | jq -r ".[$i].branch")

    # Validate registry path
    if ! validate_registry_path "$wt_path"; then
        print_warning "Skipping invalid registry entry: $wt_path"
        i=$((i + 1))
        continue
    fi

    # Handle main worktree sentinel -- branch-only cleanup
    if [[ "$wt_path" == "__MAIN_WORKTREE__" ]]; then
        print_verbose "Skipping worktree removal for main working tree (sequential mode)"
    elif [[ -d "$wt_path" ]]; then
        # SAFE-01: No rm -rf fallback. If git worktree remove fails, report and skip.
        if git worktree remove --force "$wt_path" 2>/dev/null; then
            print_verbose "Removed worktree: $wt_path"
            wt_removed=$((wt_removed + 1))
        else
            print_warning "Failed to remove worktree: $wt_path"
            print_warning "Manual cleanup may be needed: git worktree remove --force '$wt_path'"
            wt_failed=$((wt_failed + 1))
        fi
    else
        print_verbose "Worktree already removed: $wt_path"
    fi

    # Delete branch (unchanged from current logic)
    if git show-ref --verify --quiet "refs/heads/$br_name" 2>/dev/null; then
        if git branch -d "$br_name" 2>/dev/null; then
            print_verbose "Deleted branch: $br_name"
            br_deleted=$((br_deleted + 1))
        elif [[ "$force" == true ]]; then
            if git branch -D "$br_name" 2>/dev/null; then
                print_verbose "Force-deleted branch: $br_name"
                br_deleted=$((br_deleted + 1))
            else
                print_warning "Failed to delete branch: $br_name"
                br_skipped=$((br_skipped + 1))
            fi
        else
            print_warning "Branch not fully merged: $br_name (use --force to delete)"
            br_skipped=$((br_skipped + 1))
        fi
    else
        print_verbose "Branch already deleted: $br_name"
    fi

    i=$((i + 1))
done
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `rm -rf` as fallback for failed worktree removal | Report error and skip; never escalate to raw rm | v1.1 (this phase) | Eliminates the root cause of data loss |
| Store project root as worktree_path in sequential mode | Use `__MAIN_WORKTREE__` sentinel; skip directory removal | v1.1 (this phase) | Prevents project root from ever being a deletion target |
| Ad-hoc `rm` calls scattered across modules | Centralized `safe_remove()` guard in lib/safety.sh | v1.1 (this phase) | All future deletions route through a single validated path |
| No path validation before deletion | `validate_registry_path()` + `safe_remove()` guards | v1.1 (this phase) | Defense-in-depth: multiple layers prevent dangerous deletions |

**Deprecated/outdated:**
- `rm -rf "$wt_path"` fallback pattern (cleanup.sh:180): REMOVE -- this is the data-loss bug
- Storing `$(pwd)` as worktree_path in sequential mode (execute.sh:160): REPLACE -- with sentinel value via registry guard

## Open Questions

1. **Legacy scripts in `scripts/` directory**
   - What we know: `scripts/ralph-cleanup.sh` and `scripts/ralph-execute.sh` contain the same `rm -rf` fallback pattern
   - What's unclear: Whether these scripts are still actively used by any users
   - Recommendation: Add deprecation comments and remove `rm -rf` fallbacks. If scripts are unused, consider removing them entirely. Planner should decide scope.

2. **Pre-existing v1.0 registry entries**
   - What we know: Any user who ran `gsd-ralph execute N` followed by a phase completion (without cleanup) has a registry with the project root as `worktree_path`
   - What's unclear: How many such registries exist (the tool is new; likely few)
   - Recommendation: Cleanup.sh should handle old-format entries safely -- if `worktree_path` resolves to git toplevel, treat it the same as `__MAIN_WORKTREE__` (skip directory removal, only clean branch). This provides backward compatibility without a formal migration.

3. **Test file teardown rm calls**
   - What we know: `tests/test_helper/common.bash` line 22 uses `rm -rf "$TEST_TEMP_DIR"` for test cleanup
   - What's unclear: Whether test teardown should also route through `safe_remove()`
   - Recommendation: Test teardown is NOT production code -- the `$TEST_TEMP_DIR` is created by `mktemp -d` and is always under `/tmp/`. Routing through `safe_remove()` is unnecessary overhead for tests. However, consider adding a guard that `TEST_TEMP_DIR` starts with `/tmp/` or `/var/` as a minimal safety check.

## Sources

### Primary (HIGH confidence)
- Direct codebase analysis: `lib/commands/cleanup.sh` lines 174-183 -- confirmed `rm -rf` fallback bug
- Direct codebase analysis: `lib/commands/execute.sh` line 160 -- `$(pwd)` registration in sequential mode
- Direct codebase analysis: `lib/cleanup/registry.sh` -- registry CRUD structure
- `.planning/STATE.md` -- Known incident: vibecheck project data loss, documented as CRITICAL pending todo
- `.planning/research/STACK.md` -- v1.1 stack research with verified Bash 3.2 and git techniques
- `.planning/research/ARCHITECTURE.md` -- v1.1 architecture design with integration points
- `.planning/research/PITFALLS.md` -- Pitfall 1 (incomplete guard) and Pitfall 6 (registry mismatch)
- Git official documentation: `git-worktree` -- main worktree cannot be removed via `git worktree remove`
- Git official documentation: `git-rev-parse --show-toplevel` -- returns canonical project root path
- Bash 3.2 manual: `[[ file1 -ef file2 ]]` -- True if file1 and file2 refer to the same device and inode numbers

### Secondary (MEDIUM confidence)
- `.planning/research/SUMMARY.md` -- Consolidated research summary with gap analysis
- `.planning/REQUIREMENTS.md` -- SAFE-01 through SAFE-04 requirement definitions

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- All techniques are Bash builtins and git commands already in the project. Zero new dependencies. Verified on Bash 3.2/darwin24/arm64.
- Architecture: HIGH -- Integration points verified against actual source line numbers. Patterns follow existing codebase conventions (source-on-demand, globals, jq for JSON).
- Pitfalls: HIGH -- Grounded in a real production incident (vibecheck data loss). The rm-rf fallback is confirmed buggy by direct code reading and STATE.md documentation.

**Research date:** 2026-02-23
**Valid until:** 2026-03-23 (stable domain; Bash/git safety patterns do not change rapidly)
