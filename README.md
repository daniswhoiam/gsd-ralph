# gsd-ralph

**One command turns a GSD-planned phase into merged, working code.**

gsd-ralph bridges [GSD](https://github.com/daniswhoiam/get-shit-done) structured planning with [Ralph](https://github.com/daniswhoiam/ralph) autonomous execution. Instead of manually setting up branches, crafting prompts, and babysitting AI agents — you run one command and Ralph handles the rest.

```bash
gsd-ralph execute 3    # Prepare branch with protocol PROMPT.md + fix_plan.md
ralph                  # Ralph completes the phase autonomously
gsd-ralph merge 3      # Auto-merge with conflict detection and rollback safety
gsd-ralph cleanup 3    # Remove branches and worktrees
```

---

## How It Works

```
GSD Plans (.planning/)          gsd-ralph              Ralph Agent
┌─────────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ Phase 3              │    │                 │    │                  │
│ ├── 03-01-PLAN.md   │───>│  init           │    │  Reads PROMPT.md │
│ ├── 03-02-PLAN.md   │    │  generate       │───>│  Follows 7-step  │
│ └── frontmatter:    │    │  execute  ──────│    │  GSD Protocol    │
│     wave: 1         │    │  merge    ──────│    │  Commits tasks   │
│     depends_on: []  │    │  cleanup  ──────│    │  Creates summary │
└─────────────────────┘    └─────────────────┘    └──────────────────┘
```

1. **GSD** creates structured plans with phases, tasks, dependencies, and verification criteria
2. **gsd-ralph** reads those plans, parses frontmatter metadata, and generates everything an AI agent needs
3. **Ralph** executes autonomously on the prepared branch, following the 7-step protocol
4. **gsd-ralph merge** brings completed work back to main with safety guarantees
5. **gsd-ralph cleanup** removes branches and worktrees when done

---

## Commands

| Command | Description |
|---------|-------------|
| `gsd-ralph init` | Initialize in any GSD project — detects stack, creates `.ralph/` config |
| `gsd-ralph generate N` | Generate per-plan files for phase N (PROMPT.md, fix_plan.md, .ralphrc) |
| `gsd-ralph execute N` | Create branch + protocol PROMPT.md + combined fix_plan.md + execution log |
| `gsd-ralph merge N` | Merge completed branches with dry-run conflict detection and rollback safety |
| `gsd-ralph merge N --review` | Review each branch diff before merging |
| `gsd-ralph merge N --rollback` | Rollback the last merge for this phase |
| `gsd-ralph cleanup N` | Remove worktrees and branches after phase completion |
| `gsd-ralph cleanup N --force` | Force cleanup without confirmation |

---

## Quick Start

```bash
# Install
git clone https://github.com/daniswhoiam/gsd-ralph.git
cd gsd-ralph
make install    # Symlinks to /usr/local/bin

# Navigate to any GSD project
cd your-gsd-project

# Initialize
gsd-ralph init

# Execute a phase (creates branch with everything Ralph needs)
gsd-ralph execute 2

# Launch Ralph on the prepared branch
ralph

# After Ralph completes, merge back to main
gsd-ralph merge 2

# Clean up
gsd-ralph cleanup 2
```

### Prerequisites

- **bash** 3.2+ (macOS default works)
- **git** 2.38+ (with worktree support, merge-tree)
- **python3** (for task extraction)
- **jq** (for JSON handling)
- **ralph** (only needed at execute time, not init)

---

## What Gets Generated

Running `gsd-ralph execute N` creates a git branch with:

| File | Purpose |
|------|---------|
| `.ralph/PROMPT.md` | 7-step GSD Execution Protocol — orient, locate, execute, verify, commit, update state, check completion |
| `.ralph/fix_plan.md` | Combined task checklist from all plans in the phase, grouped by plan |
| `.ralph/logs/execution-log.md` | Timestamped execution log for observability |
| `.planning/STATE.md` | Updated with current phase position |

The protocol PROMPT.md includes a file permissions table enforcing which files the agent can modify, preventing scope creep.

A terminal bell sounds on completion or failure, so you don't have to watch the terminal.

---

## Auto-Detection

gsd-ralph detects your project stack and configures accordingly:

| Stack | Detection | Test Command | Build Command |
|-------|-----------|-------------|---------------|
| TypeScript | `package.json` + `tsconfig.json` | `npm test` | `npm run build` |
| JavaScript | `package.json` | `npm test` | `npm run build` |
| Rust | `Cargo.toml` | `cargo test` | `cargo build` |
| Go | `go.mod` | `go test ./...` | `go build ./...` |
| Python | `pyproject.toml` / `setup.py` | `pytest` | — |
| Ruby | `Gemfile` | `bundle exec rake test` | — |
| Elixir | `mix.exs` | `mix test` | `mix compile` |
| Java/Kotlin | `pom.xml` / `build.gradle` | `mvn test` / `gradle test` | `mvn package` / `gradle build` |

Package manager auto-detected from lockfiles (pnpm, yarn, bun, npm).

---

## Merge Safety

`gsd-ralph merge` provides multiple layers of protection:

- **Pre-merge dry-run** — detects conflicts before touching your working tree (uses `git merge-tree`)
- **Auto-resolve** — safely resolves known-safe conflicts (.planning/ files, lock files)
- **Rollback** — saves pre-merge commit hash; run `--rollback` to undo
- **Review mode** — `--review` shows each branch diff for approval before merging
- **Wave signaling** — merging wave N signals the execution pipeline to unblock wave N+1 dependents
- **Post-merge regression detection** — compares test exit codes before and after merge

---

## Execution Strategy

gsd-ralph reads plan frontmatter to understand phase structure:

```yaml
---
phase: 03-phase-execution
plan: 01
wave: 1
depends_on: []
autonomous: true
---
```

- **Sequential phases** (linear dependency chain) get a single branch with combined tasks
- **Parallel-capable phases** (independent plans in the same wave) are detected and reported
- Dependency validation catches circular references and missing dependencies before execution starts

---

## Architecture

```
bin/
  gsd-ralph              # CLI entry point, dispatches to lib/commands/

lib/
  common.sh              # Output formatting, dependency checking, terminal bell
  config.sh              # Project type detection (13 ecosystems)
  discovery.sh           # Phase directory lookup and plan file enumeration
  frontmatter.sh         # YAML frontmatter parser for GSD plan metadata
  prompt.sh              # PROMPT.md and fix_plan.md generation pipeline
  strategy.sh            # Execution strategy analyzer and dependency validator
  templates.sh           # {{VAR}} template substitution engine
  commands/
    init.sh              # gsd-ralph init
    generate.sh          # gsd-ralph generate N
    execute.sh           # gsd-ralph execute N
    merge.sh             # gsd-ralph merge N
    cleanup.sh           # gsd-ralph cleanup N
    status.sh            # (stub — planned for v2)
  merge/
    auto_resolve.sh      # .planning/ and lock file conflict resolution
    dry_run.sh           # Pre-merge conflict detection via git merge-tree
    review.sh            # Interactive branch diff review
    rollback.sh          # Pre-merge state saving and rollback
    signals.sh           # Wave completion signaling
    test_runner.sh       # Post-merge regression detection
  cleanup/
    registry.sh          # Worktree registry (JSON manifest of created resources)

templates/
  PROTOCOL-PROMPT.md.template   # 7-step GSD Execution Protocol
  PROMPT.md.template            # Per-plan prompt template
  AGENT.md.template             # Build/test reference
  fix_plan.md.template          # Task extraction template
  ralphrc.template              # Circuit breaker config

scripts/
  ralph-execute.sh       # Ralph execution loop with circuit breaker
  ralph-worktrees.sh     # Worktree creation helper

tests/                   # 171 tests across 11 BATS test suites
```

---

## Testing

```bash
# Run all tests (lint + unit + integration)
make check

# Run tests only
make test

# Run a specific test suite
./tests/bats/bin/bats tests/merge.bats

# Lint only
make lint
```

**171 tests** across 11 suites — all ShellCheck clean, all Bash 3.2 compatible.

---

## License

MIT
