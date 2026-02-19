---
phase: 01-project-initialization
plan: 02
subsystem: initialization
tags: [bash, cli, init-command, dependency-check, project-detection]
requires:
  - phase: 01-project-initialization
    provides: CLI skeleton, shared libraries (common.sh, config.sh), bats test infrastructure
provides:
  - gsd-ralph init command with dependency checking and project type detection
  - 21 integration tests for init command
affects: [02-prompt-generation]
tech-stack:
  added: []
  patterns: [init-command-pattern, dependency-checking, project-type-detection]
key-files:
  created:
    - lib/commands/init.sh
    - tests/init.bats
  modified:
    - bin/gsd-ralph
key-decisions:
  - "Ralph is a soft dependency (warning only), not a hard requirement for init"
  - "Idempotent init: warns if .ralph/ exists, succeeds with --force"
patterns-established:
  - "Command pattern: usage function + cmd_X function + argument parsing"
  - "Dependency checking: check_dependency per tool, check_all_dependencies for suite"
requirements-completed:
  - INIT-01
  - INIT-02
  - INIT-03
  - XCUT-01
duration: single-session
completed: 2026-02-13
---

# Plan 01-02 Summary: Init Command Implementation

**Completed:** 2026-02-13
**Duration:** Single session

## What Was Built

### lib/commands/init.sh
Complete `gsd-ralph init` command implementation:
- Parse `-f/--force` and `-h/--help` flags
- Validate git repo (actionable error if not)
- Validate .planning/ directory (actionable error if missing)
- Idempotent: warns if .ralph/ exists, succeeds with --force
- Dependency checking via check_all_dependencies (git, jq, python3 hard; ralph soft warning)
- Project type auto-detection via detect_project_type
- Project name derived from git root directory basename
- Creates .ralph/logs directory structure
- Renders .ralphrc from template with detected values
- Prints completion summary with next steps

### tests/init.bats
21 integration tests covering:
- **Success (12):** .ralph/ creation, .ralph/logs, .ralphrc creation, project name in config, TypeScript/Rust/Go/Python/unknown detection, no unresolved placeholders, test command detection, build command detection
- **Failure (2):** outside git repo, missing .planning/
- **Idempotency (4):** warns on existing .ralph/, --force succeeds, --force overwrites .ralphrc, -f short flag
- **Dependencies (2):** check_dependency fails for missing tool, succeeds for git
- **Help (1):** --help shows usage

### Foundation (from Plan 01-01 dependency)
Also built the CLI skeleton since Plan 01-01 was not yet executed:
- bin/gsd-ralph: entry point with subcommand dispatch
- lib/common.sh: output functions, dependency checking, utilities
- lib/config.sh: project type detection (13 ecosystems)
- lib/templates.sh: {{VARIABLE}} template rendering
- lib/commands/{execute,status,merge,cleanup}.sh: stubs
- templates/ralphrc.template: parameterized with 4 variables
- Makefile: test, lint, check, install targets
- tests/test_helper/common.bash: shared test setup
- tests/common.bats: 9 unit tests for lib/common.sh
- tests/config.bats: 8 unit tests for lib/config.sh
- bats-core + assert + support + file as git submodules

## Verification

- `make check` passes (ShellCheck + 38 bats tests)
- `bin/gsd-ralph init` creates .ralph/ and .ralphrc in GSD projects
- `bin/gsd-ralph init` outside git repo shows actionable error
- `bin/gsd-ralph init` without .planning/ shows actionable error
- .ralphrc contains auto-detected project settings, no {{}} placeholders
- `bin/gsd-ralph init --force` reinitializes successfully
- 21 integration tests in init.bats (exceeds 14 minimum)
- No bash 4+ features in any source file

## Requirements Covered

- **INIT-01:** gsd-ralph init creates .ralph/ config directory with sensible defaults
- **INIT-02:** Actionable error messages for missing dependencies
- **INIT-03:** Auto-detects language, test command, build tool
- **XCUT-01:** Works regardless of tech stack (unknown project type succeeds)
