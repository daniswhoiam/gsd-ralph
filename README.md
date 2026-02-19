# gsd-ralph

**One command turns a GSD-planned phase into a ready-to-go Ralph execution environment.**

gsd-ralph bridges [GSD](https://github.com/daniswhoiam/get-shit-done) structured planning with [Ralph](https://github.com/daniswhoiam/ralph) autonomous execution. Instead of manually setting up branches, crafting prompts, and babysitting AI agents — you run one command and Ralph handles the rest.

```
gsd-ralph execute 3
```

That's it. You get a git branch with a GSD Execution Protocol PROMPT.md, a combined fix_plan.md, and an execution log — everything Ralph needs to autonomously complete every plan in the phase.

---

## How It Works

```
GSD Plans (.planning/)          gsd-ralph              Ralph Agent
┌─────────────────────┐    ┌─────────────────┐    ┌──────────────────┐
│ Phase 3              │    │                 │    │                  │
│ ├── 03-01-PLAN.md   │───>│  init           │    │  Reads PROMPT.md │
│ ├── 03-02-PLAN.md   │    │  generate       │───>│  Follows 7-step  │
│ └── frontmatter:    │    │  execute  ◄─────│    │  GSD Protocol    │
│     wave: 1         │    │  status   (wip) │    │  Commits tasks   │
│     depends_on: []  │    │  merge    (wip) │    │  Creates summary │
└─────────────────────┘    │  cleanup  (wip) │    └──────────────────┘
                           └─────────────────┘
```

1. **GSD** creates structured plans with phases, tasks, dependencies, and verification criteria
2. **gsd-ralph** reads those plans, parses frontmatter metadata, and generates everything an AI agent needs
3. **Ralph** executes autonomously on the prepared branch, following the 7-step protocol

---

## Commands

| Command | Description | Status |
|---------|-------------|--------|
| `gsd-ralph init` | Initialize in any GSD project — detects stack, creates `.ralph/` config | ✓ |
| `gsd-ralph generate N` | Generate per-plan files for phase N (PROMPT.md, fix_plan.md, .ralphrc) | ✓ |
| `gsd-ralph execute N` | Create branch + protocol PROMPT.md + combined fix_plan.md + execution log | ✓ |
| `gsd-ralph status N` | Show status of phase N execution | Planned |
| `gsd-ralph merge N` | Merge completed branches with conflict detection and rollback safety | Planned |
| `gsd-ralph cleanup N` | Remove worktrees and branches after phase completion | Planned |

---

## Quick Start

```bash
# Clone and add to PATH
git clone https://github.com/daniswhoiam/gsd-ralph.git
export PATH="$PWD/gsd-ralph/bin:$PATH"

# Navigate to any GSD project
cd your-gsd-project

# Initialize
gsd-ralph init

# Execute a phase
gsd-ralph execute 2

# Launch Ralph on the prepared branch
ralph
```

### Prerequisites

- **git** (with worktree support)
- **bash** 3.2+ (macOS default works)
- **python3** (for task extraction)
- **jq** (for JSON handling)

---

## What Gets Generated

Running `gsd-ralph execute N` creates:

| File | Purpose |
|------|---------|
| `.ralph/PROMPT.md` | 7-step GSD Execution Protocol — orient, locate, execute, verify, commit, update state, check completion |
| `.ralph/fix_plan.md` | Combined task checklist from all plans in the phase, grouped by plan |
| `.ralph/logs/execution-log.md` | Timestamped execution log for observability |
| `.planning/STATE.md` | Updated with current phase position |

The protocol PROMPT.md includes a file permissions table enforcing which files the agent can modify, preventing scope creep.

---

## Auto-Detection

gsd-ralph detects your project stack and configures accordingly:

| Stack | Detection | Test Command | Build Command |
|-------|-----------|-------------|---------------|
| JavaScript/TypeScript | `package.json` | `npm test` | `npm run build` |
| Rust | `Cargo.toml` | `cargo test` | `cargo build` |
| Go | `go.mod` | `go test ./...` | `go build ./...` |
| Python | `pyproject.toml` / `setup.py` | `pytest` | — |
| Ruby | `Gemfile` | `bundle exec rake test` | — |
| Elixir | `mix.exs` | `mix test` | `mix compile` |
| Java | `pom.xml` / `build.gradle` | `mvn test` / `gradle test` | `mvn package` / `gradle build` |

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
- **Parallel-capable phases** (independent plans in the same wave) are detected and reported — parallel worktree execution is planned for a future release

Dependency validation catches circular references and missing dependencies before execution starts.

---

## Architecture

```
bin/
  gsd-ralph              # CLI entry point, dispatches to lib/commands/

lib/
  common.sh              # Output formatting (print_header, print_success, etc.)
  config.sh              # Project type detection (9 stacks)
  discovery.sh           # Phase directory lookup and plan file enumeration
  frontmatter.sh         # YAML frontmatter parser for GSD plan metadata
  prompt.sh              # PROMPT.md and fix_plan.md generation pipeline
  strategy.sh            # Execution strategy analyzer and dependency validator
  templates.sh           # {{VAR}} template substitution engine
  commands/
    init.sh              # gsd-ralph init
    generate.sh          # gsd-ralph generate N
    execute.sh           # gsd-ralph execute N
    status.sh            # (stub) gsd-ralph status N
    merge.sh             # (stub) gsd-ralph merge N
    cleanup.sh           # (stub) gsd-ralph cleanup N

templates/
  PROTOCOL-PROMPT.md.template   # 7-step GSD Execution Protocol
  PROMPT.md.template            # Per-plan prompt template
  AGENT.md.template             # Build/test reference
  fix_plan.md.template          # Task extraction template
  ralphrc.template              # Circuit breaker config

tests/                   # 125 tests across 9 BATS test suites
```

---

## Testing

```bash
# Run all tests (lint + unit + integration)
make check

# Run a specific test suite
./tests/bats/bin/bats tests/frontmatter.bats

# Lint only
make lint
```

**125 tests** across 9 suites — all ShellCheck clean, all Bash 3.2 compatible.

---

## Roadmap

| Phase | What | Status |
|-------|------|--------|
| 1. Project Initialization | CLI scaffolding, dependency validation, project type detection | ✓ Complete |
| 2. Prompt Generation | Template system producing PROMPT.md, fix_plan.md, .ralphrc from plans | ✓ Complete |
| 3. Phase Execution | `execute` command with frontmatter parsing and protocol generation | ✓ Complete |
| 4. Merge Orchestration | Wave-aware auto-merge, dry-run conflict detection, review mode, rollback | In Progress |
| 5. Cleanup | Registry-driven worktree and branch removal | Planned |

---

## License

MIT
