# Phase 2: Prompt Generation - Research

**Researched:** 2026-02-13
**Domain:** GSD plan parsing, template-based file generation, XML task extraction, Bash 3.2 text processing
**Confidence:** HIGH

## Summary

Phase 2 transforms GSD planning artifacts into the per-worktree files that Ralph agents consume: PROMPT.md, fix_plan.md, and .ralphrc. This is a pure file-generation phase -- it reads structured input (GSD plan files with XML tasks, project configuration from Phase 1's `detect_project_type`, and template files) and produces structured output (three files per plan, correctly parameterized for the target worktree).

The technical challenges are: (1) parsing GSD's XML task format reliably from Bash (using python3, already a validated dependency), (2) discovering plan files under the dual naming convention (PLAN.md vs NN-MM-PLAN.md), (3) generating PROMPT.md with per-worktree context (scope lock, peer visibility, plan-specific instructions), and (4) ensuring the existing `render_template` function from Phase 1 handles the new templates correctly.

The reference implementation in `scripts/ralph-worktrees.sh` (both the gsd-ralph prototype at 245 lines and the bayesian-it version at 400 lines) proves this is achievable. The bayesian-it version added important features not in the prototype: merge order instructions, peer source visibility (not just status files), and shared contracts detection for overlapping files. Phase 2 should extract the proven generation logic into clean library functions (`lib/discovery.sh`, `lib/prompt.sh`) that follow the patterns established in Phase 1 (local variables, bash 3.2 compat, ShellCheck clean, bats-testable).

**Primary recommendation:** Build two new library modules (`lib/discovery.sh` for plan file discovery, `lib/prompt.sh` for the three-file generation pipeline) and a new `generate` subcommand that produces per-worktree files without creating worktrees. Keep worktree creation for Phase 3. Test each generation function in isolation with bats, using fixture plan files with known XML task structures.

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Bash | 3.2+ | Script runtime | Established in Phase 1; all code must target macOS system bash |
| Python 3 | 3.8+ | XML task extraction from plan files | Already a validated dependency from Phase 1; `re` module handles GSD's XML-in-Markdown reliably |
| jq | 1.6+ | JSON generation for status.json | Already validated; used for structured output |

### Development/Testing

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| bats-core | 1.13.0 | Test all generation functions | Already installed as git submodules from Phase 1 |
| bats-assert | 2.2.0 | Assert generated file content | `assert_output --partial`, `assert_line` for checking generated content |
| bats-file | 0.4.0 | Assert file existence and content | `assert_file_exists`, `assert_file_contains` for generated files |
| ShellCheck | 0.10+ | Lint all new bash files | Non-negotiable; established in Phase 1 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Python 3 for XML extraction | Pure bash with grep/sed | Python regex is far more reliable for multi-line XML parsing; grep/sed breaks on edge cases (multiline `<task>` blocks, nested content with special chars). Python 3 is already a hard dependency. |
| `render_template` (Phase 1) for all templates | Heredoc string assembly | render_template is better for static templates (ralphrc); heredoc assembly is better for dynamic content (PROMPT.md sections appended conditionally). Use both patterns where appropriate. |
| Single monolithic generate function | Separate functions per output file | Separate functions are independently testable and follow Phase 1's modular pattern. |

## Architecture Patterns

### Recommended Project Structure (Phase 2 additions)

```
lib/
  discovery.sh               # GSD plan file discovery and naming convention handling
  prompt.sh                  # PROMPT.md, fix_plan.md, .ralphrc generation pipeline
  commands/
    generate.sh              # gsd-ralph generate N -- generate per-plan files (no worktree creation)
templates/
  PROMPT.md.template         # Base PROMPT.md template (already exists, needs parameterization)
  AGENT.md.template          # AGENT.md template (already exists)
  ralphrc.template           # Already parameterized from Phase 1
tests/
  discovery.bats             # Unit tests for plan discovery
  prompt.bats                # Unit tests for file generation functions
  generate.bats              # Integration tests for generate command
  test_helper/
    fixtures/                # Fixture plan files for testing
      single-plan/           # Phase dir with single PLAN.md
      multi-plan/            # Phase dir with NN-MM-PLAN.md files
      edge-cases/            # Malformed XML, empty tasks, etc.
```

### Pattern 1: Phase Directory Discovery

**What:** A function that takes a phase number and returns the path to the phase directory, handling the GSD naming convention (NN-slug format, e.g., `01-project-initialization`).

**When to use:** Every operation that needs to find plan files for a given phase.

**Example:**
```bash
# lib/discovery.sh

# Find phase directory by number. Sets PHASE_DIR global.
# Supports GSD format: NN-slug (e.g., 01-project-initialization)
# Args: phase_number, [planning_base] (defaults to .planning/phases)
# Returns: 0 if found, 1 if not found
find_phase_dir() {
    local phase_num="$1"
    local base="${2:-.planning/phases}"
    local padded
    padded=$(printf "%02d" "$phase_num")

    # GSD format: NN-slug
    local dir
    dir=$(ls -d "${base}/${padded}"-* 2>/dev/null | head -1)
    if [[ -n "$dir" ]] && [[ -d "$dir" ]]; then
        PHASE_DIR="$dir"
        return 0
    fi

    PHASE_DIR=""
    return 1
}
```

### Pattern 2: Plan File Discovery with Dual Naming Convention

**What:** A function that discovers plan files within a phase directory, handling both single PLAN.md and numbered NN-MM-PLAN.md formats.

**When to use:** After finding the phase directory, before generating per-plan files.

**Why:** GSD uses two naming conventions. Single-plan phases have `PLAN.md`. Multi-plan phases have `NN-MM-PLAN.md` (e.g., `02-01-PLAN.md`). The discovery must handle both without ambiguity. Numbered plans take priority over a bare `PLAN.md` (per reference implementation behavior).

**Example:**
```bash
# lib/discovery.sh (continued)

# Discover plan files in a phase directory.
# Sets PLAN_FILES array (bash 3.2 compatible indexed array).
# Sets PLAN_COUNT integer.
# Args: phase_dir
# Returns: 0 if plans found, 1 if none
discover_plan_files() {
    local phase_dir="$1"
    PLAN_FILES=()
    PLAN_COUNT=0

    # Look for numbered plan files first (NN-MM-PLAN.md)
    local numbered
    # Use ls + grep instead of find for bash 3.2 compat and simplicity
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        PLAN_FILES+=("$f")
    done < <(ls -1 "$phase_dir"/*-PLAN.md 2>/dev/null | sort)

    # Fallback: single PLAN.md
    if [[ ${#PLAN_FILES[@]} -eq 0 ]] && [[ -f "$phase_dir/PLAN.md" ]]; then
        PLAN_FILES+=("$phase_dir/PLAN.md")
    fi

    PLAN_COUNT=${#PLAN_FILES[@]}
    [[ $PLAN_COUNT -gt 0 ]]
}
```

**Important edge case:** The `*-PLAN.md` glob also matches `NN-MM-PLAN.md` (the intended numbered format) and any other file ending in `-PLAN.md` (like `RESEARCH-PLAN.md` if it existed). The reference implementation uses `find "$phase_dir" -maxdepth 1 -name "*-PLAN.md"` which has the same behavior. This is acceptable because GSD's convention is that only plan files end in `-PLAN.md` within a phase directory.

### Pattern 3: XML Task Extraction via Python 3

**What:** Extract `<task>` blocks from a GSD plan file and produce a checklist for `fix_plan.md`.

**When to use:** For every plan file, to generate the task checklist that Ralph works through.

**Why:** GSD plan files embed XML `<task>` blocks inside Markdown. The XML is not valid standalone XML (it is mixed with Markdown content). Python's `re` module handles this reliably with `re.DOTALL` for multiline matching. Pure bash solutions (grep + sed) break on multiline blocks, nested angle brackets in action content, and special characters.

**Example:**
```bash
# lib/prompt.sh

# Extract tasks from a GSD plan file into fix_plan.md format.
# Uses python3 regex to parse <task>...<name>...</name>...</task> blocks.
# Args: plan_file, output_file
# Returns: 0 on success, 1 on failure
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

    if [[ ! -s "$output_file" ]]; then
        print_warning "No tasks extracted from $(basename "$plan_file")"
        return 0  # Not an error -- plan may have no auto tasks
    fi

    return 0
}
```

### Pattern 4: PROMPT.md Generation with Per-Worktree Context

**What:** Generate a complete PROMPT.md for a specific plan within a phase. The PROMPT.md consists of a base template plus dynamically appended sections for scope lock, peer visibility, and merge order.

**When to use:** For each plan, after discovery.

**Why:** The reference implementation (bayesian-it `ralph-worktrees.sh` lines 207-309) builds PROMPT.md by copying a base template and appending heredoc blocks. This is the correct pattern because the dynamic sections (peer worktree paths, plan count, plan ID) cannot be expressed as simple `{{VARIABLE}}` substitutions -- they require conditional logic (number of peers, peer worktree paths, contracts file existence).

**Design choice -- two-part generation:**
1. **Base template** via `render_template` with `{{VARIABLE}}` substitution (project name, language, test command, build command, plan file path, phase directory format)
2. **Dynamic sections** appended via functions that take plan context (phase number, plan ID, plan count, peer paths) and emit Markdown to stdout, which gets appended to the file

```bash
# lib/prompt.sh (continued)

# Generate PROMPT.md for a specific plan.
# Args: output_path, template_path, phase_num, plan_id, plan_count,
#        plan_filename, phase_dir, project_name, project_lang,
#        test_cmd, build_cmd, repo_name, parent_dir
generate_prompt_md() {
    local output_path="$1"
    local template_path="$2"
    local phase_num="$3"
    local plan_id="$4"
    local plan_count="$5"
    local plan_filename="$6"
    local phase_dir="$7"
    # ... additional args for project context

    # Step 1: Render base template
    render_template "$template_path" "$output_path" \
        "PROJECT_NAME=$project_name" \
        "PROJECT_LANG=$project_lang" \
        "TEST_CMD=$test_cmd" \
        "BUILD_CMD=$build_cmd"

    # Step 2: Append scope lock section
    append_scope_lock "$output_path" "$phase_num" "$plan_id" "$plan_filename" "$phase_dir"

    # Step 3: Append merge order section
    append_merge_order "$output_path" "$plan_id" "$plan_count"

    # Step 4: Append peer visibility section
    append_peer_visibility "$output_path" "$phase_num" "$plan_id" "$plan_count" \
        "$repo_name" "$parent_dir"
}
```

### Pattern 5: Parameterized PROMPT.md Template

**What:** The base PROMPT.md template needs parameterization with `{{VARIABLE}}` placeholders for project-specific values, while keeping the Ralph execution instructions as static content.

**When to use:** The template at `templates/PROMPT.md.template` needs updating from its current state (which is a bayesian-it-specific document) to a parameterized template.

**Key variables needed:**
- `{{PROJECT_NAME}}` -- project name from git root
- `{{PROJECT_LANG}}` -- detected language
- `{{TEST_CMD}}` -- detected test command
- `{{BUILD_CMD}}` -- detected build/lint command
- `{{PHASE_DIR_FORMAT}}` -- how phase directories are named (e.g., `NN-slug`)
- `{{PLAN_FILE_FORMAT}}` -- how plan files are named (e.g., `NN-MM-PLAN.md`)

**Sections that remain static** (baked into template, not parameterized):
- GSD task format documentation
- Required reading instructions
- Execution rules
- Dependency checking instructions
- Blocked state template
- Status reporting format
- Ralph status block format

**Sections that are dynamically appended** (not in template):
- Scope lock (phase/plan specific)
- Merge order (plan count specific)
- Peer visibility (worktree paths specific)
- Shared contracts reference (conditional on contracts file existence)

### Pattern 6: .ralphrc Per-Worktree Generation

**What:** The `.ralphrc` template from Phase 1 already supports `{{PROJECT_NAME}}`, `{{PROJECT_TYPE}}`, `{{TEST_CMD}}`, `{{BUILD_CMD}}`. For worktree-specific generation, additional worktree-context variables may be needed.

**When to use:** When generating files for each worktree.

**Design choice:** For Phase 2, the `.ralphrc` generation can reuse `render_template` from Phase 1 with the existing template. The current template already covers all required fields. Per-worktree customization is minimal -- the main project-level `.ralphrc` is suitable for all worktrees of the same project. If worktree-specific overrides are needed later (e.g., different working directories), the template can be extended with optional variables.

### Anti-Patterns to Avoid

- **Parsing XML with grep/sed/awk:** GSD task blocks are multiline XML embedded in Markdown. Regex-based line-by-line parsing breaks on `<action>` blocks that span dozens of lines, contain code samples with `<` and `>` characters, or have nested markup. Use python3's `re.DOTALL` as the reference implementation does.
- **Hardcoding peer worktree path format:** The path format `${PARENT_DIR}/${REPO_NAME}-p${PHASE_NUM}-${PLAN_ID}` is established in the reference scripts but should be computed once and passed through, not scattered across functions. Define it in one place (e.g., a `worktree_path` function).
- **Mixing file discovery with file generation:** The discovery module should only find and return plan file paths. The generation module should only produce output files from inputs. Keep them separate for testability.
- **Reading .planning/PROJECT.md at generation time:** PROMPT.md should not parse PROJECT.md at generation time. The project context (name, language, test command) comes from the already-detected values (Phase 1's `detect_project_type`). Template rendering uses these values directly.
- **Using `find` for plan discovery:** The reference implementation uses `find "$phase_dir" -maxdepth 1 -name "*-PLAN.md"`. This works but `find` output order varies by platform. Use `ls -1 | sort` or `ls -d | sort` for deterministic ordering. On macOS, `ls` output is alphabetically sorted by default, which matches the desired plan order.
- **Embedding test/build commands directly in PROMPT.md:** These should come from `detect_project_type` via the template variable system, not be hardcoded per-project. The current PROMPT.md.template has hardcoded `npm test` and `npm run typecheck` -- these must be replaced with `{{TEST_CMD}}` and `{{BUILD_CMD}}`.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| XML task parsing | Bash grep/sed regex pipeline | Python 3 `re.findall` with `re.DOTALL` | Multiline XML blocks, special characters in code samples, nested angle brackets all break line-oriented parsing |
| Template rendering | New template engine | Phase 1's `render_template` function | Already tested, ShellCheck clean, handles `{{VAR}}` substitution correctly |
| File path construction | String concatenation in every function | Centralized path-building helpers | Prevents path format inconsistencies across discovery, generation, and future worktree creation |
| Plan file sorting | Arbitrary `find` ordering | `sort` on filenames | GSD plan IDs encode execution order (01 before 02); correct ordering is essential |

**Key insight:** Phase 2's generation logic is already proven in the reference scripts. The challenge is not "can we do it" but "can we decompose it into clean, testable library functions." The reference `ralph-worktrees.sh` works but is a monolithic 245-400 line script. Breaking it into `discovery.sh` + `prompt.sh` with testable functions is the real work.

## Common Pitfalls

### Pitfall 1: PROMPT.md Template Has Hardcoded Project-Specific Content

**What goes wrong:** The existing `templates/PROMPT.md.template` is a copy of the bayesian-it PROMPT.md with hardcoded references to TypeScript, npm, Vitest, etc. If rendered as-is for a Rust project, the agent gets incorrect build/test instructions.
**Why it happens:** The template was created from a real working PROMPT.md (bayesian-it) without parameterizing project-specific sections.
**How to avoid:** Audit the template and replace every project-specific value with a `{{VARIABLE}}`. The "Project Stack" section must use `{{PROJECT_LANG}}`, `{{TEST_CMD}}`, `{{BUILD_CMD}}`. The "Execution Rules" section's "Run tests" and "Run typecheck" items must use `{{TEST_CMD}}` and `{{BUILD_CMD}}`. The project description must use `{{PROJECT_NAME}}`.
**Warning signs:** Grep the template for "npm", "TypeScript", "Vitest", "bayesian-it", "tsc" -- any matches are unhardcoded project-specific content.

### Pitfall 2: Plan File Glob Matches Unintended Files

**What goes wrong:** The `*-PLAN.md` glob matches files like `02-RESEARCH-PLAN.md` or `SOME-OTHER-PLAN.md` that are not actual plan files.
**Why it happens:** GSD only creates `PLAN.md` or `NN-MM-PLAN.md` files, but a user might create other `-PLAN.md` files. The glob is too broad.
**How to avoid:** Use a more specific pattern. GSD numbered plans always have the format `NN-MM-PLAN.md` where NN and MM are two-digit numbers. The regex `[0-9][0-9]-[0-9][0-9]-PLAN.md` is precise. In bash globbing: `[0-9][0-9]-[0-9][0-9]-PLAN.md`.
**Warning signs:** Extra files showing up in the plan list during testing.

### Pitfall 3: Empty Plan Files or Plans With No `<task>` Blocks

**What goes wrong:** A plan file exists but has no `<task>` blocks (e.g., it is a research plan, or the planner has not added tasks yet). The task extraction produces an empty `fix_plan.md`, and Ralph has nothing to work on.
**Why it happens:** GSD plans are created incrementally. A plan directory may exist before tasks are written.
**How to avoid:** After extraction, check if `fix_plan.md` is empty. If so, emit a warning ("No tasks found in NN-MM-PLAN.md -- is this plan complete?") but do not fail. The generate command should report the number of tasks extracted per plan for user verification.
**Warning signs:** `fix_plan.md` with 0 bytes.

### Pitfall 4: Dynamic PROMPT.md Sections Break if Plan Count is 1

**What goes wrong:** The peer visibility section says "Other plans in this phase are executing in parallel" when there is only one plan. Merge order section says "Plan 01 of 1 total" which is meaningless.
**Why it happens:** The generation logic was written for the multi-plan case and the single-plan case was not considered.
**How to avoid:** Conditionally omit the merge order and peer visibility sections when `PLAN_COUNT == 1`. The reference implementation (gsd-ralph `ralph-worktrees.sh` lines 176-179) handles this: "No peer worktrees -- this is the only plan in Phase N." Follow this pattern.
**Warning signs:** Generated PROMPT.md with peer visibility section but no peer paths listed.

### Pitfall 5: `date -Iseconds` in Generated status.json

**What goes wrong:** The reference scripts use `date -Iseconds` for the `last_activity` field in `status.json`. This fails on macOS stock `date` (BSD date does not support `-I`).
**Why it happens:** The prototype scripts were written/tested with GNU date on Linux or Homebrew bash on macOS.
**How to avoid:** Use the `iso_timestamp` function from `lib/common.sh` which uses `date -u +%Y-%m-%dT%H:%M:%SZ` (portable across macOS and Linux). Phase 1 already established this pattern.
**Warning signs:** `date -Iseconds` or `date -I` appearing anywhere in new code.

### Pitfall 6: Template Variables Containing Bash Special Characters

**What goes wrong:** If `DETECTED_TEST_CMD` contains characters like `./` or `*` or spaces (e.g., `go test ./...`), the `render_template` function's `${content//\{\{${key}\}\}/${value}}` substitution may behave unexpectedly because the value is treated as a pattern by bash parameter expansion.
**Why it happens:** In bash parameter expansion `${var//pattern/replacement}`, the replacement string is not treated as a regex, but certain characters (`/`, `\`) still need care. The `value` in the substitution is literal, but if it contains `/` characters, it could be misinterpreted as the delimiter.
**How to avoid:** Test `render_template` with values containing `./`, `*`, spaces, and other common characters from test/build commands. The current implementation should handle these correctly because bash parameter expansion's replacement side is literal (not regex), but edge cases with `\` and `&` should be verified. Add tests with values like `go test ./...`, `cargo test -- --nocapture`, `npm run build && npm run typecheck`.
**Warning signs:** Generated files with garbled test/build commands.

## Code Examples

Verified patterns from the reference implementation and Phase 1 codebase:

### Complete Discovery Module Pattern

```bash
# lib/discovery.sh -- GSD plan file discovery

# Find phase directory by number.
# Args: phase_number, [planning_base]
# Sets: PHASE_DIR (global)
# Returns: 0 found, 1 not found
find_phase_dir() {
    local phase_num="$1"
    local base="${2:-.planning/phases}"
    local padded
    padded=$(printf "%02d" "$phase_num")

    local dir
    dir=$(ls -d "${base}/${padded}"-* 2>/dev/null | head -1)
    if [[ -n "$dir" ]] && [[ -d "$dir" ]]; then
        PHASE_DIR="$dir"
        return 0
    fi

    PHASE_DIR=""
    return 1
}

# Discover plan files in a phase directory.
# Uses precise glob: NN-MM-PLAN.md for numbered, PLAN.md for single.
# Args: phase_dir
# Sets: PLAN_FILES (global array), PLAN_COUNT (global integer)
# Returns: 0 found, 1 none found
discover_plan_files() {
    local phase_dir="$1"
    PLAN_FILES=()
    PLAN_COUNT=0

    # Numbered plans: NN-MM-PLAN.md (more specific glob)
    local f
    for f in "$phase_dir"/[0-9][0-9]-[0-9][0-9]-PLAN.md; do
        [[ -f "$f" ]] || continue
        PLAN_FILES+=("$f")
    done

    # Fallback: single PLAN.md
    if [[ ${#PLAN_FILES[@]} -eq 0 ]] && [[ -f "$phase_dir/PLAN.md" ]]; then
        PLAN_FILES+=("$phase_dir/PLAN.md")
    fi

    PLAN_COUNT=${#PLAN_FILES[@]}
    [[ $PLAN_COUNT -gt 0 ]]
}

# Derive plan ID from plan filename.
# "02-01-PLAN.md" -> "01"
# "PLAN.md" -> "01" (single plan case)
# Args: plan_filename
plan_id_from_filename() {
    local filename="$1"
    local basename_
    basename_=$(basename "$filename")
    if [[ "$basename_" =~ ^[0-9][0-9]-([0-9][0-9])-PLAN\.md$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo "01"
    fi
}

# Compute worktree path for a plan.
# Format: ${parent_dir}/${repo_name}-p${phase_num}-${plan_id}
# Args: parent_dir, repo_name, phase_num, plan_id
worktree_path_for_plan() {
    local parent_dir="$1"
    local repo_name="$2"
    local phase_num="$3"
    local plan_id="$4"
    echo "${parent_dir}/${repo_name}-p${phase_num}-${plan_id}"
}
```

### Complete Task Extraction Pattern

```bash
# lib/prompt.sh (task extraction)

# Extract tasks from GSD plan XML into fix_plan.md checklist.
# Args: plan_file, output_file
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

    # Report result
    local task_count=0
    if [[ -s "$output_file" ]]; then
        task_count=$(wc -l < "$output_file" | tr -d ' ')
    fi
    print_verbose "Extracted $task_count task(s) from $(basename "$plan_file")"
    return 0
}
```

### Test Fixture Strategy

```bash
# tests/test_helper/fixtures/multi-plan/02-01-PLAN.md
# Minimal fixture plan file with known task structure

---
phase: test-phase
plan: 01
---

<tasks>

<task type="auto">
  <name>Task 1: Create the first component</name>
  <files>src/component.sh</files>
  <action>Create the component file.</action>
  <verify>File exists and is valid.</verify>
  <done>Component created.</done>
</task>

<task type="auto">
  <name>Task 2: Add tests for the component</name>
  <files>tests/component.bats</files>
  <action>Write tests.</action>
  <verify>Tests pass.</verify>
  <done>Tests written and passing.</done>
</task>

</tasks>
```

### PROMPT.md Dynamic Section Generation

```bash
# lib/prompt.sh (dynamic sections)

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

# Append peer visibility section.
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

**Status files:**
EOF

    local j peer_id peer_path
    for j in $(seq 1 "$plan_count"); do
        peer_id=$(printf "%02d" "$j")
        [[ "$peer_id" == "$plan_id" ]] && continue
        peer_path="${parent_dir}/${repo_name}-p${phase_num}-${peer_id}"
        echo "- \`${peer_path}/.ralph/status.json\`" >> "$output"
    done
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Monolithic `ralph-worktrees.sh` (245 lines) | Decomposed into `discovery.sh` + `prompt.sh` library modules | This phase | Testable, maintainable, extensible |
| Hardcoded PROMPT.md per project | Parameterized template + dynamic section appending | This phase | Works for any project, not just TypeScript |
| `find ... -name "*-PLAN.md"` for discovery | Precise glob `[0-9][0-9]-[0-9][0-9]-PLAN.md` | This phase | Avoids matching non-plan files |
| `date -Iseconds` for timestamps | `iso_timestamp` from `lib/common.sh` | Phase 1 | Portable across macOS/Linux |
| Peer visibility = status files only | Peer visibility = status + source files (read-only) | bayesian-it evolution | Agents can check if peers already implemented shared code |

**Deprecated/outdated:**
- The `@fix_plan.md` at worktree root (legacy compatibility) -- the bayesian-it reference still creates this but it duplicates `.ralph/fix_plan.md`. Phase 2 should generate only `.ralph/fix_plan.md` and not the legacy root copy, unless Ralph specifically requires the root location.
- The `PHASES.md` tracking file -- the reference scripts append to this, but it duplicates information that will be in the worktree registry manifest (decided in project planning). Defer PHASES.md generation to Phase 3 when the registry is built.

## Open Questions

1. **Should Phase 2 create a `generate` subcommand or fold generation into `execute`?**
   - What we know: The roadmap separates "prompt generation" (Phase 2) from "phase execution" (Phase 3). Phase 2's success criteria focus on file generation, not worktree creation. Phase 3 depends on Phase 2 having the generation logic ready.
   - What's unclear: Whether a standalone `generate` subcommand is useful to users, or if generation should be an internal step called by `execute`.
   - Recommendation: Create the generation functions in `lib/prompt.sh` and `lib/discovery.sh` as library code. Expose it via a `generate` subcommand for testing and debugging purposes. Phase 3's `execute` command will call these same library functions internally. The `generate` command can be documented as a diagnostic/debug tool, not a primary workflow command.

2. **How should the PROMPT.md template handle project-specific conventions that go beyond test/build commands?**
   - What we know: The current bayesian-it PROMPT.md has project-specific sections like "Key Patterns" (ES modules, Zod validation, etc.) and "File Structure" (project-specific directory layout). These cannot be auto-detected.
   - What's unclear: Whether to include a generic "Key Patterns" section in the template or omit it.
   - Recommendation: Include a `## Project Conventions` section in the template with `{{PROJECT_CONVENTIONS}}` placeholder. Default to empty string if not provided. Users can add project-specific conventions in `.ralph/CONVENTIONS.md` and the tool can inject them. For Phase 2, keep it simple: the template should be useful without project-specific conventions, and the `## Project Conventions` section can be populated in a future enhancement.

3. **Should `extract_tasks_to_fix_plan` handle the `<task type="manual">` vs `<task type="auto">` distinction?**
   - What we know: GSD plan tasks have a `type` attribute. `type="auto"` tasks are for autonomous agents. `type="manual"` tasks require human intervention. The reference implementation extracts ALL tasks regardless of type.
   - What's unclear: Whether Ralph should see manual tasks in its fix_plan.md. Including them could cause Ralph to attempt manual work; excluding them could cause Ralph to think it is done when manual tasks remain.
   - Recommendation: Extract only `type="auto"` tasks by default. Add a comment in `fix_plan.md` noting that manual tasks exist if any were skipped. This prevents Ralph from attempting human-only work. The python extraction regex should filter: `re.findall(r'<task[^>]*type="auto"[^>]*>(.*?)</task>', content, re.DOTALL)`. However, note that many plans may not specify `type` at all or may use only `type="auto"`. The extraction should handle missing type attribute gracefully (default to include).

4. **Should PROMPT.md template be project-type-aware (different templates for bash vs TypeScript vs Rust)?**
   - What we know: The current template has bash-specific content in the gsd-ralph version and TypeScript-specific content in the bayesian-it version. Test commands, build commands, and coding conventions vary by language.
   - What's unclear: Whether one parameterized template is sufficient or whether per-language template variants are needed.
   - Recommendation: One parameterized template is sufficient for Phase 2. The `{{TEST_CMD}}`, `{{BUILD_CMD}}`, and `{{PROJECT_LANG}}` variables handle the essential project-type differences. Language-specific coding conventions (bash 3.2 constraints, ES module rules, etc.) belong in the project's own PROMPT.md or CONVENTIONS.md, not in the gsd-ralph template. Keep the template generic.

5. **Where does AGENT.md generation fit?**
   - What we know: The bayesian-it `.ralph/AGENT.md` contains project-specific build/test instructions. The `templates/AGENT.md.template` already exists in gsd-ralph. Ralph reads AGENT.md for operational instructions separate from PROMPT.md.
   - What's unclear: Whether Phase 2 should generate AGENT.md per worktree or if the project-level AGENT.md (created during init or manually) is sufficient.
   - Recommendation: Phase 2 should generate AGENT.md per worktree from the template, parameterized with `{{TEST_CMD}}`, `{{BUILD_CMD}}`, `{{PROJECT_LANG}}`. This ensures each worktree has correct operational instructions. The template should be simple -- just build/test commands and project structure overview. Do not duplicate the PROMPT.md's execution rules in AGENT.md.

## Sources

### Primary (HIGH confidence)
- Existing codebase: `scripts/ralph-worktrees.sh` (gsd-ralph prototype, 245 lines) -- proven plan discovery, task extraction, PROMPT.md generation
- Existing codebase: bayesian-it `scripts/ralph-worktrees.sh` (400 lines) -- evolved version with merge order, peer source visibility, shared contracts
- Existing codebase: `lib/templates.sh` -- Phase 1's render_template function, tested and ShellCheck clean
- Existing codebase: `lib/config.sh` -- Phase 1's detect_project_type providing DETECTED_LANG, DETECTED_TEST_CMD, DETECTED_BUILD_CMD
- Existing codebase: `templates/PROMPT.md.template`, `templates/AGENT.md.template`, `templates/ralphrc.template` -- current template files
- Existing codebase: `tests/test_helper/common.bash` -- Phase 1's test infrastructure pattern
- GSD plan files: `.planning/phases/01-project-initialization/01-01-PLAN.md`, `01-02-PLAN.md` -- real examples of GSD XML task format with frontmatter
- bayesian-it plan files: `.planning/phases/phase-2/02-01-PLAN.md` -- real example of multi-plan phase with dependencies

### Secondary (MEDIUM confidence)
- `.planning/research/ARCHITECTURE.md` -- component boundaries (Plan Parser, Prompt Generator, Worktree Manager)
- `.planning/research/PITFALLS.md` -- orphaned worktree risks, merge order sensitivity
- `.planning/REQUIREMENTS.md` -- EXEC-02, EXEC-03, EXEC-04, EXEC-07 specifications

### Tertiary (LOW confidence)
- `templates/fix_plan.md.template` -- existing but appears to be a static example, not a parameterized template. May need replacement with dynamic generation only (no template needed for fix_plan.md since it is fully generated from plan XML).

## Metadata

**Confidence breakdown:**
- Discovery logic: HIGH -- Pattern is proven in two reference implementations, GSD naming conventions are well-documented in ROADMAP.md and plan files
- Task extraction: HIGH -- Python regex approach is proven in reference scripts, tested against real GSD plan files with XML tasks
- PROMPT.md generation: HIGH -- Proven in reference implementations, but template parameterization needs careful audit of project-specific content
- Template system: HIGH -- Phase 1's render_template is tested and sufficient for static templates; dynamic sections use proven heredoc appending
- Testing strategy: HIGH -- Phase 1's bats infrastructure is ready; fixture-based testing is straightforward for file generation
- Edge cases: MEDIUM -- Single-plan phases, empty task blocks, and missing type attributes need testing but are predictable

**Research date:** 2026-02-13
**Valid until:** 2026-03-13 (stable domain; bash text processing and GSD format do not change rapidly)
