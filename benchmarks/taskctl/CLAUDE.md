# taskctl

A command-line task manager written in Bash.

## Quick Start

```bash
cd benchmarks/taskctl
src/taskctl.sh add "Buy groceries"
src/taskctl.sh list
src/taskctl.sh done 1
src/taskctl.sh list --done
```

## Running Tests

From the `benchmarks/taskctl/` directory:

```bash
../../tests/bats/bin/bats tests/
```

## Project Structure

```
src/
  taskctl.sh          # Entry point, dispatches to command modules
  storage.sh          # JSON storage layer (CRUD via jq)
  format.sh           # Output formatting for task lists
  commands/
    add.sh            # Add a new task
    list.sh           # List tasks with optional filters (--done, --pending)
    done.sh           # Mark a task as done by ID
```

## Dependencies

- Bash 3.2+
- jq

## Data Storage

Tasks are stored as a JSON array in `.taskctl.json` (in the current directory by default). You can override the storage file location with the `TASKCTL_DATA` environment variable:

```bash
export TASKCTL_DATA="/tmp/my-tasks.json"
src/taskctl.sh add "Custom location task"
```

## Known Limitations

- Test coverage is incomplete -- only add and list have tests
- No delete command
- No input validation on task IDs for the done command
