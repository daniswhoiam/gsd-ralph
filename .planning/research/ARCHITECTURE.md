# Architecture Patterns

**Domain:** CLI tool orchestrating parallel autonomous coding agents via git worktrees
**Researched:** 2026-02-13
**Confidence:** MEDIUM (based on training data for CLI orchestration patterns, git worktree mechanics, and process management; no live verification available this session)

## Recommended Architecture

gsd-ralph is a process orchestrator: it reads structured plans, fans out work to isolated git worktrees, monitors autonomous agents, and converges results back via merges. The architecture follows a **pipeline-with-feedback** pattern: linear flow from plan parsing through execution, with a monitoring loop that feeds status back to the user.

```
                          +------------------+
                          |  CLI Entry Point |
                          |  (commander/yargs)|
                          +--------+---------+
                                   |
                    +--------------+--------------+
                    |              |               |
              +-----v----+  +-----v-----+  +------v------+
              | GSD Plan  |  | Worktree  |  |   Status    |
              | Parser    |  | Manager   |  |   Monitor   |
              +-----------+  +-----------+  +-------------+
                    |              |               ^
                    v              v               |
              +-----------+  +-----------+         |
              | Prompt    |  | Ralph     +---------+
              | Generator |  | Launcher  |
              +-----------+  +-----------+
                                   |
                                   v
                          +--------+---------+
                          | Merge            |
                          | Orchestrator     |
                          +------------------+
                                   |
                                   v
                          +------------------+
                          | Notification     |
                          | System           |
                          +------------------+
```

### Component Boundaries

| Component | Responsibility | Communicates With | I/O |
|-----------|---------------|-------------------|-----|
| **CLI Entry Point** | Parse args, route subcommands (`init`, `execute`, `status`, `merge`, `cleanup`), handle global flags | All components (dispatches to each) | stdin/stdout, exit codes |
| **GSD Plan Parser** | Read `.planning/` directory structure, parse XML tasks, understand dual naming conventions, extract task graph with dependencies | CLI Entry Point (receives commands), Prompt Generator (provides parsed tasks) | Reads `.planning/` filesystem; outputs structured task objects |
| **Worktree Manager** | Create/list/remove git worktrees, ensure clean branch naming, handle worktree lifecycle | CLI Entry Point, Ralph Launcher (provides worktree paths), Merge Orchestrator (provides branch info), Cleanup | Calls `git worktree` commands; manages filesystem |
| **Prompt Generator** | Transform parsed tasks into PROMPT.md, fix_plan.md, and .ralphrc files using templates | GSD Plan Parser (receives task data), Worktree Manager (receives target paths) | Reads templates; writes prompt files into worktrees |
| **Ralph Launcher** | Spawn Ralph processes in worktrees, manage process lifecycle, capture output streams | Worktree Manager (gets paths), Prompt Generator (ensures prompts exist), Status Monitor (reports process state) | Spawns child processes; manages PIDs |
| **Status Monitor** | Track progress across all active worktrees, aggregate status, detect completion/failure | Ralph Launcher (subscribes to events), CLI Entry Point (serves status queries) | Reads process state + git state; outputs status reports |
| **Merge Orchestrator** | Auto-merge clean branches back to target, detect conflicts, flag manual resolution needed | Worktree Manager (gets branch list), Status Monitor (knows which are complete) | Runs `git merge`; reports success/conflict |
| **Notification System** | Alert user on completion, conflicts, failures via terminal bell and optional hooks | Status Monitor and Merge Orchestrator (subscribe to events) | Terminal bell, stdout messages |

### Data Flow

**Phase 1: Plan Ingestion (init/execute)**
```
.planning/ directory
    |
    v
GSD Plan Parser
    |  Produces: TaskGraph { tasks: Task[], dependencies: Edge[] }
    |  Each Task: { id, name, description, phase, files, acceptance_criteria }
    v
Prompt Generator
    |  Consumes: TaskGraph + Templates
    |  Produces: Per-task prompt files (PROMPT.md, .ralphrc, fix_plan.md)
    v
Written into worktree directories
```

**Phase 2: Execution (execute)**
```
TaskGraph (with dependency order)
    |
    v
Worktree Manager
    |  Creates: one worktree per task (or per parallelizable batch)
    |  Branch naming: gsd/<phase>/<task-slug>
    v
Ralph Launcher
    |  Spawns: one Ralph process per worktree
    |  Manages: process handles, stdout/stderr streams
    v
Status Monitor (polling loop)
    |  Checks: process alive? git diff empty? tests passing?
    |  Updates: in-memory status map { taskId -> WorkerStatus }
    v
Notification System
    |  Fires on: completion, failure, conflict
```

**Phase 3: Convergence (merge)**
```
Status Monitor (all tasks complete)
    |
    v
Merge Orchestrator
    |  For each completed branch:
    |    1. Check merge-ability (git merge --no-commit --no-ff, then abort)
    |    2. If clean: fast-forward or merge commit
    |    3. If conflict: flag for manual resolution
    |  Order: respects dependency graph (merge dependencies first)
    v
Notification System
    |  Reports: merged branches, conflict branches, summary
    v
Worktree Manager (cleanup)
    |  Removes: merged worktrees
    |  Preserves: conflict worktrees for manual resolution
```

**Shared State**

The system needs a lightweight state file to survive process restarts:

```
.planning/.gsd-ralph-state.json
{
  "session_id": "uuid",
  "started_at": "ISO-8601",
  "tasks": {
    "task-id": {
      "status": "pending|running|complete|failed|merged|conflict",
      "worktree_path": "/path/to/worktree",
      "branch": "gsd/phase-1/task-slug",
      "pid": 12345,
      "started_at": "ISO-8601",
      "completed_at": "ISO-8601|null",
      "exit_code": 0
    }
  }
}
```

This state file is the **single source of truth** for session recovery. Every component reads/writes through a shared StateManager abstraction -- never directly.

## Patterns to Follow

### Pattern 1: Command Pattern for CLI Subcommands

**What:** Each subcommand (`init`, `execute`, `status`, `merge`, `cleanup`) is an independent module implementing a common interface. The CLI entry point dispatches to the correct command handler.

**When:** Always. This is the standard CLI architecture pattern.

**Why:** Keeps the entry point thin. Each command can be tested independently. Adding new commands requires zero changes to existing code.

```typescript
// src/commands/types.ts
interface Command {
  name: string;
  description: string;
  options: OptionDefinition[];
  execute(args: ParsedArgs, context: AppContext): Promise<number>; // exit code
}

// src/commands/execute.ts
export const executeCommand: Command = {
  name: 'execute',
  description: 'Run tasks in parallel worktrees',
  options: [
    { name: '--plan', description: 'Path to planning directory', default: '.planning' },
    { name: '--parallel', description: 'Max parallel workers', default: '4' },
    { name: '--dry-run', description: 'Show what would happen', default: false },
  ],
  async execute(args, context) {
    const tasks = await context.planParser.parse(args.plan);
    const batches = context.scheduler.schedule(tasks, args.parallel);
    // ...
    return 0;
  },
};
```

### Pattern 2: Event Emitter for Cross-Component Communication

**What:** Components communicate through a typed event bus rather than direct method calls. The Status Monitor, Notification System, and Merge Orchestrator all subscribe to events rather than polling or being called directly.

**When:** For all async lifecycle events (task started, task completed, task failed, merge complete, conflict detected).

**Why:** Decouples components. The Ralph Launcher does not need to know about notifications. The Status Monitor does not need to know about merging. Adding new reactions (e.g., a web dashboard) requires zero changes to existing emitters.

```typescript
// src/events.ts
type GsdEvents = {
  'task:started': { taskId: string; worktree: string; pid: number };
  'task:completed': { taskId: string; exitCode: number };
  'task:failed': { taskId: string; error: string };
  'merge:success': { taskId: string; branch: string };
  'merge:conflict': { taskId: string; branch: string; files: string[] };
  'session:complete': { merged: number; conflicts: number; failed: number };
};
```

### Pattern 3: Dependency-Aware Task Scheduler

**What:** Tasks are scheduled in topological order respecting the dependency graph. Independent tasks run in parallel up to the concurrency limit. Dependent tasks wait for their prerequisites.

**When:** During `execute` — this is the core scheduling logic.

**Why:** GSD plans have phases and task dependencies. Blindly parallelizing everything would create merge conflicts and broken code. Respecting the dependency graph is the whole point of an orchestrator.

```typescript
// src/scheduler.ts
class TaskScheduler {
  schedule(graph: TaskGraph, maxParallel: number): TaskBatch[] {
    // Kahn's algorithm: topological sort with level grouping
    // Each batch = set of tasks whose dependencies are all satisfied
    // Batch size capped at maxParallel
  }
}
```

### Pattern 4: Idempotent Operations with State Recovery

**What:** Every operation checks current state before acting. `execute` resumes from where it left off. `merge` skips already-merged branches. `cleanup` only removes worktrees that exist.

**When:** Always. Users will re-run commands after failures, interrupts, and partial completions.

**Why:** The user's workflow is: run, check status, fix issues, re-run. If re-running causes duplicate worktrees, double merges, or crashes on missing state, the tool is unusable.

```typescript
// Before creating a worktree:
if (state.tasks[taskId]?.status === 'running') {
  // Check if process is actually alive
  if (isProcessAlive(state.tasks[taskId].pid)) {
    log.info(`Task ${taskId} already running, skipping`);
    continue;
  }
  // Process died — mark as failed, allow retry
  state.tasks[taskId].status = 'failed';
}
```

### Pattern 5: Git Operations Through an Abstraction Layer

**What:** All git operations (worktree create/remove, branch operations, merge) go through a GitOperations interface, never raw shell commands scattered through the codebase.

**When:** Always. Every component that touches git should use this layer.

**Why:** Git operations are the most failure-prone part of this system. Centralizing them enables: consistent error handling, dry-run support, logging, testing with mocks, and future support for alternative VCS.

```typescript
// src/git/operations.ts
interface GitOperations {
  worktreeAdd(path: string, branch: string): Promise<void>;
  worktreeRemove(path: string): Promise<void>;
  worktreeList(): Promise<Worktree[]>;
  mergeBranch(branch: string, into: string): Promise<MergeResult>;
  isMergeClean(branch: string, into: string): Promise<boolean>;
  currentBranch(): Promise<string>;
  branchExists(name: string): Promise<boolean>;
}
```

## Anti-Patterns to Avoid

### Anti-Pattern 1: Shared Mutable Filesystem State

**What:** Multiple worktree agents reading/writing the same `.planning/` directory or state files concurrently without coordination.

**Why bad:** Race conditions. Two agents completing simultaneously both try to update status. File corruption. Merge orchestrator reads partial state.

**Instead:** Single writer for state files. Use file locking (e.g., `proper-lockfile`) or funnel all state writes through a single process (the main orchestrator). Worktrees should be fully isolated -- each gets its own copy of what it needs.

### Anti-Pattern 2: Tight Coupling Between Plan Format and Execution

**What:** Embedding GSD plan parsing logic directly in the execute command or prompt generator.

**Why bad:** The GSD plan format will evolve. Dual naming conventions already hint at format complexity. If parsing is scattered, format changes require touching every component.

**Instead:** The GSD Plan Parser is a hard boundary. It outputs a normalized `TaskGraph` structure. Downstream components never see raw XML or directory layouts. Format changes are isolated to the parser.

### Anti-Pattern 3: Synchronous Process Management

**What:** Using `execSync` or blocking on each Ralph process sequentially.

**Why bad:** The entire value proposition of gsd-ralph is parallelism. Blocking on each process defeats the purpose and makes the tool slower than manual work.

**Instead:** Use `child_process.spawn` with async management. Track processes by PID. Use an event loop for status polling. The scheduler manages concurrency, not sequential waiting.

### Anti-Pattern 4: Worktree Paths as Primary Keys

**What:** Using filesystem paths as the primary identifier for tasks/workers throughout the system.

**Why bad:** Paths are fragile (user moves repo, cleanup removes and recreates), platform-dependent, and hard to serialize/deserialize reliably.

**Instead:** Use task IDs as primary keys everywhere. Map task ID to worktree path only when needed, through the Worktree Manager.

### Anti-Pattern 5: Optimistic Merging Without Pre-Check

**What:** Running `git merge` and hoping for the best, then trying to recover from conflicts after the fact.

**Why bad:** A failed merge leaves the target branch in a dirty state. If the orchestrator crashes mid-conflict-resolution, the user's main branch is corrupted.

**Instead:** Always dry-run merges first (`git merge --no-commit --no-ff` then `git merge --abort`). Only proceed with actual merge if dry-run is clean. This is the merge orchestrator's core safety guarantee.

## Component Dependency Graph (Build Order)

The build order is dictated by which components can be tested independently versus which need other components to exist.

```
Layer 0 (no dependencies - build first):
  - Git Operations abstraction
  - State Manager (read/write .gsd-ralph-state.json)
  - Event Bus

Layer 1 (depends on Layer 0):
  - GSD Plan Parser (needs: filesystem only)
  - Worktree Manager (needs: Git Operations)

Layer 2 (depends on Layer 1):
  - Prompt Generator (needs: Plan Parser output, Worktree Manager for paths)
  - Task Scheduler (needs: Plan Parser output for dependency graph)

Layer 3 (depends on Layer 2):
  - Ralph Launcher (needs: Worktree Manager, Prompt Generator, Event Bus)
  - Status Monitor (needs: State Manager, Event Bus)

Layer 4 (depends on Layer 3):
  - Merge Orchestrator (needs: Git Operations, Status Monitor, Worktree Manager)
  - Notification System (needs: Event Bus)

Layer 5 (depends on everything):
  - CLI Entry Point (thin shell dispatching to commands)
  - Individual Command Handlers (compose components per subcommand)
```

**Build order rationale:**

1. **Layer 0 first** because these are pure utilities with no dependencies. They can be fully tested in isolation with unit tests. The Git Operations abstraction is the foundation everything else builds on -- getting this right (with proper error handling and dry-run support) prevents cascading issues.

2. **Layer 1 next** because the Plan Parser and Worktree Manager are the two "edge" components that interface with external systems (filesystem and git). Testing them early surfaces integration issues with the real world.

3. **Layer 2 follows** because the Prompt Generator and Scheduler are pure transformations -- they take structured input and produce structured output. Easy to test, easy to get right once inputs are well-defined.

4. **Layer 3 is where complexity lives.** The Ralph Launcher manages child processes, and the Status Monitor tracks async state. These are the hardest components to test and debug. By this point, all their dependencies are stable.

5. **Layer 4 last (before CLI)** because merging and notifications are "convergence" operations that only make sense when execution is working.

6. **CLI Entry Point last** because it is a thin routing layer. Building it last means all the logic it dispatches to is already tested and working.

## Suggested Directory Structure

```
src/
  index.ts                    # CLI entry point
  commands/
    init.ts                   # Initialize session from plan
    execute.ts                # Run tasks in worktrees
    status.ts                 # Show current progress
    merge.ts                  # Merge completed branches
    cleanup.ts                # Remove worktrees and state
    types.ts                  # Command interface
  core/
    event-bus.ts              # Typed event emitter
    state-manager.ts          # Session state persistence
    scheduler.ts              # Dependency-aware task scheduling
  git/
    operations.ts             # Git abstraction interface
    git-cli.ts                # Implementation via git CLI
  plan/
    parser.ts                 # GSD plan parser
    types.ts                  # TaskGraph, Task, etc.
    naming.ts                 # Dual naming convention handler
  worktree/
    manager.ts                # Worktree lifecycle
    types.ts                  # Worktree types
  prompt/
    generator.ts              # Prompt file generator
    templates/                # Template files
      PROMPT.md.hbs
      fix_plan.md.hbs
      ralphrc.hbs
  ralph/
    launcher.ts               # Process spawning
    types.ts                  # Ralph config types
  monitor/
    status.ts                 # Status aggregation
    types.ts                  # Status types
  merge/
    orchestrator.ts           # Merge logic
    conflict-detector.ts      # Pre-merge dry run
  notify/
    terminal.ts               # Terminal bell + messages
    types.ts                  # Notification types
```

## Scalability Considerations

| Concern | At 5 tasks | At 20 tasks | At 50+ tasks |
|---------|------------|-------------|-------------|
| **Worktree disk usage** | Negligible (~5 copies) | Noticeable (worktrees share objects via git, so mostly just working trees) | May need explicit disk checks before creating; stagger creation |
| **Process management** | Simple concurrent spawns | Need concurrency limit (4-8 parallel) to avoid CPU/memory exhaustion | Queue-based scheduling; may need process priority |
| **Merge conflicts** | Rare if tasks are well-scoped | Likely between related tasks; dependency ordering critical | Need merge ordering strategy; possibly staged merge (merge group A, then group B on top) |
| **State file contention** | No issues | Infrequent writes, no contention | Consider SQLite or structured state if JSON becomes bottleneck |
| **Git operations** | Fast | Some git commands slow with many worktrees (e.g., `git worktree list`) | Cache worktree list; batch git operations |
| **User cognitive load** | Status fits in terminal | Need summary view + detail drill-down | Need filtering, grouping by phase, progress bars |

## Key Architecture Decisions

### Decision 1: Single Process Orchestrator, Not Distributed

gsd-ralph should be a **single Node.js process** that spawns Ralph as child processes. Not a daemon, not a server, not a distributed system. Reasons:

- The user runs it from their terminal. Terminal lifecycle = orchestrator lifecycle.
- State recovery via JSON file handles crashes.
- No need for IPC complexity -- child process stdout/stderr is sufficient.
- The concurrency model is "a few parallel processes" not "a fleet of workers."

### Decision 2: Worktrees Over Clones

Git worktrees share the object store, so they are fast to create and space-efficient. Each worktree gets its own working tree and index, so agents cannot interfere with each other. This is the correct isolation primitive -- not Docker containers, not separate clones, not branch switching in a single worktree.

### Decision 3: File-Based Communication With Ralph

Ralph expects PROMPT.md and .ralphrc in the working directory. gsd-ralph communicates intent to Ralph by writing these files, not by passing CLI arguments or environment variables. This means:

- The Prompt Generator is a critical component (not just a convenience).
- Template quality directly impacts execution quality.
- gsd-ralph does not need to understand Ralph's internal API -- just its file conventions.

### Decision 4: Pull-Based Status Monitoring

Rather than Ralph "reporting back" to gsd-ralph (which would require modifying Ralph), the Status Monitor polls:

1. Is the process still alive? (PID check)
2. Has the worktree changed? (git status in worktree)
3. Did the process exit? (exit code)

This keeps gsd-ralph and Ralph decoupled. Ralph does not need to know it is being orchestrated.

## Sources

- Git worktree documentation: `git-worktree(1)` man page -- worktrees share objects, each has own HEAD and index
- Node.js `child_process` module -- spawn for async process management, stdio pipe options
- Commander.js / yargs patterns for CLI subcommand routing
- General orchestration patterns from CI/CD pipeline architectures (Jenkins, GitHub Actions) where parallel job management and artifact merging are well-studied problems
- Process management patterns from tools like PM2, concurrently, and npm-run-all

**Confidence note:** Architecture patterns are drawn from training data knowledge of CLI tools, process orchestrators, and git internals. No live verification was possible this session. The patterns described (event bus, command pattern, topological scheduling, git worktree isolation) are well-established and HIGH confidence individually. Their specific composition for this exact use case is MEDIUM confidence -- the integration points (especially Ralph process monitoring and merge ordering) will need validation during implementation.
