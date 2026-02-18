# Plan 02-02 Summary: File generation pipeline and generate subcommand

## What Was Built
- **lib/prompt.sh** — File generation pipeline with 5 functions: `extract_tasks_to_fix_plan`, `generate_prompt_md`, `append_scope_lock`, `append_merge_order`, `append_peer_visibility`
- **lib/commands/generate.sh** — `gsd-ralph generate N` subcommand that orchestrates discovery + generation to produce per-plan output files (PROMPT.md, fix_plan.md, AGENT.md, .ralphrc, status.json)
- **tests/prompt.bats** — 12 unit tests for all prompt generation functions including task extraction, scope lock, merge order, peer visibility, and full generation pipeline
- **tests/generate.bats** — 17 integration tests covering success paths, failure cases, single-plan/multi-plan phases, template quality, and custom output directory
- **bin/gsd-ralph** — Updated with `generate` in usage text (already dispatches via dynamic command loading)

## Key Decisions
- Task extraction uses `python3 -c` with `re.findall` and `re.DOTALL` for reliable multiline XML parsing (not grep/sed which breaks on GSD plan format)
- `generate_prompt_md` uses two-part generation: `render_template` for base template + heredoc appending for dynamic sections (scope lock, merge order, peer visibility)
- Peer visibility section lists both source directory and status.json paths for each peer worktree
- Single-plan phases get a "only plan" note instead of peer visibility section, and merge order is omitted entirely
- ShellCheck SC2034 disable on the `while` loop for VERBOSE (used by print_verbose in sourced common.sh)
- Output directory defaults to `.ralph/generated/` with `--output-dir` flag for customization

## Verification Results
- `shellcheck -s bash lib/prompt.sh lib/commands/generate.sh` — PASS
- `make check` — PASS (79/79 tests, 29 new: 12 prompt.bats + 17 generate.bats)
- `grep -c '@test' tests/prompt.bats` — 12 (>= 10 required)
- `grep -c '@test' tests/generate.bats` — 17 (>= 15 required)
- `bin/gsd-ralph generate 1` against real project — PASS (correct scope lock, task extraction, no placeholder leaks)
- Generated .ralphrc and AGENT.md have no `{{}}` placeholders — PASS
- Generated status.json is valid JSON with phase, plan, status fields — PASS
- No bash 4+ features in new code — PASS

## Files Modified
- `lib/prompt.sh` (created, 158 lines)
- `lib/commands/generate.sh` (created, 158 lines)
- `tests/prompt.bats` (created, 178 lines)
- `tests/generate.bats` (created, 243 lines)
- `bin/gsd-ralph` (modified, added generate to usage)

## Metrics
- Tasks completed: 2
- Tests added: 29 (12 unit + 17 integration)
- Lines of code added: ~737
