# taskctl -- CLI Task Manager

A simple command-line task manager written in Bash with JSON storage.

## Installation

No installation required. Just ensure you have:

- Bash 3.2 or later
- jq (JSON processor)

## Usage

All commands are run via `src/taskctl.sh` from the `benchmarks/taskctl/` directory.

### Add a task

```bash
src/taskctl.sh add "Buy groceries"
src/taskctl.sh add "Deploy v2 to production"
```

### List tasks

```bash
# List all tasks
src/taskctl.sh list

# List only completed tasks
src/taskctl.sh list --done

# List only pending tasks
src/taskctl.sh list --pending
```

### Mark a task as done

```bash
src/taskctl.sh done 3
```

## Data File

Tasks are stored in `.taskctl.json` in the current working directory. Override with:

```bash
export TASKCTL_DATA="/path/to/tasks.json"
```

## Running Tests

From the `benchmarks/taskctl/` directory:

```bash
../../tests/bats/bin/bats tests/
```

Tests use isolated temp directories via the `TASKCTL_DATA` environment variable, so they never modify the project data file.
