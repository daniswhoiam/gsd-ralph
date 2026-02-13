# Ralph Scripts

## When to Run What

### Starting a New Phase

You've just planned a phase with `/gsd:plan-phase N` and want to execute it.

```bash
./scripts/ralph-execute.sh N
```

This is the **main entry point**. It checks if the phase is planned, creates worktrees, and tells you what to do next. You rarely need the other scripts directly — this one walks you through the full workflow.

### Running Ralph

After `ralph-execute.sh` creates your worktrees, open a terminal per worktree:

```bash
cd ../bayesian-it-pN-01 && ralph
cd ../bayesian-it-pN-02 && ralph   # if multiple plans
```

For single-plan phases or quick tasks, you can also run Ralph directly in the main repo (no worktrees needed):

```bash
ralph
```

Ralph reads `.planning/STATE.md` to find the current phase and executes the next unchecked task.

### Checking Progress

While Ralph is running:

```bash
./scripts/ralph-status.sh N
```

Shows a color-coded table of all worktrees for phase N — complete, running, blocked, or errored.

### After Ralph Finishes

Once all worktrees show "complete":

```bash
./scripts/ralph-merge.sh N       # merge all branches back to main
./scripts/ralph-cleanup.sh N     # remove worktrees and branches
```

Then start the next phase:

```bash
./scripts/ralph-execute.sh $((N+1))
```

## Quick Reference

| Script | When | What |
|--------|------|------|
| `ralph-execute.sh N` | Start of each phase | Creates worktrees, shows full workflow |
| `ralph-status.sh N` | During execution | Check progress of all worktrees |
| `ralph-merge.sh N` | After all plans complete | Merge branches back to main |
| `ralph-cleanup.sh N` | After merging | Remove worktrees and branches |
| `ralph-worktrees.sh N` | Rarely (called by execute) | Just the worktree creation step |

## The Full Cycle

```
/gsd:plan-phase N          Plan the phase (GSD)
         ↓
ralph-execute.sh N         Create worktrees
         ↓
ralph (in each worktree)   Execute autonomously
         ↓
ralph-status.sh N          Monitor progress
         ↓
ralph-merge.sh N           Merge to main
         ↓
ralph-cleanup.sh N         Remove worktrees
         ↓
ralph-execute.sh N+1       Next phase
```
