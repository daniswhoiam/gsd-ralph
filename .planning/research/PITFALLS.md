# Domain Pitfalls

**Domain:** CLI orchestration of parallel autonomous coding agents via git worktrees
**Researched:** 2026-02-13
**Confidence:** MEDIUM (based on codebase analysis and training data; WebSearch unavailable for verification)

---

## Critical Pitfalls

Mistakes that cause data loss, corrupted repos, or require fundamental rearchitecture.

---

### Pitfall 1: Git Lock File Contention from Concurrent Worktree Operations

**What goes wrong:** Multiple worktrees share the same `.git` directory (the main repo's). When parallel Ralph instances run `git add`, `git commit`, `git status`, or other index-modifying operations simultaneously, they contend for `.git/index.lock`. Git operations fail with `fatal: Unable to create '/path/.git/index.lock': File exists`. In the existing scripts, `ralph-worktrees.sh` creates branches and worktrees sequentially (lines 81-202), but once Ralph instances are running in parallel, each one commits independently -- and while each worktree has its own index, they share the object store and ref namespace, so operations like `git gc`, packing, or ref updates can still collide.

**Why it happens:** Git worktrees are designed for a single user switching contexts, not for high-throughput concurrent writes. Each worktree gets its own `worktrees/<name>/index`, but ref updates, loose object creation, and packfile operations touch shared state. Autonomous agents commit frequently (after each task), creating bursts of concurrent git operations.

**Consequences:**
- Failed commits silently or noisily, breaking Ralph's task completion tracking
- Corrupted pack files in rare cases (git is mostly safe, but not designed for this concurrency level)
- Ralph agents stall on retries or report false failures
- status.json shows "complete" but the commit never landed

**Prevention:**
- Implement a git operation retry loop with exponential backoff (start 100ms, max 5s, 5 retries) around all git commands in the tool
- Consider using `git -C <worktree>` consistently to ensure operations target the correct worktree index
- Avoid running `git gc` or `git repack` while agents are active
- For merge operations, ensure they run sequentially (the current `ralph-merge.sh` already does this correctly -- merges are sequential in a loop)
- Add a pre-flight check: before starting agents, verify no `.git/index.lock` or `worktrees/*/index.lock` files exist

**Detection:** Monitor for "index.lock" errors in Ralph logs. Track commit success rate per worktree. If an agent reports task complete but `git log` shows no new commit, lock contention is the likely cause.

**Phase to address:** Phase 1 (core worktree management). This must be designed in from the start; retrofitting retry logic is error-prone.

---

### Pitfall 2: Merge Order Sensitivity Creates Silent Data Loss

**What goes wrong:** When merging N parallel branches back to main, the merge order matters enormously. The current `ralph-merge.sh` (line 73) iterates worktrees in filesystem glob order (`${REPO_NAME}-p${PHASE_NUM}-*`), which means plan-01 always merges first, then plan-02, etc. If plan-02 modifies the same files as plan-01, the second merge may silently resolve conflicts in favor of plan-02's version (with `--no-edit` auto-merge), destroying plan-01's work that was just merged. Worse: if both branches modify different sections of the same file, git's 3-way merge may produce syntactically valid but semantically broken code.

**Why it happens:** Parallel branches diverge from the same base commit. Each branch only sees its own changes. Git's merge algorithm handles textual conflicts well but cannot reason about semantic interactions (e.g., both branches add an import but use it differently, both branches add a function with the same name, both branches modify a shared state machine).

**Consequences:**
- Merged code compiles but has subtle bugs from interleaved changes
- One plan's work is partially overwritten by another's merge
- Tests pass individually in each worktree but fail after merge
- Human discovers breakage hours later, after cleanup has removed worktrees and branches

**Prevention:**
- Run the full test suite after EACH sequential merge, not just after all merges complete. If tests fail after merging branch N, stop and alert before merging branch N+1.
- Implement a "merge preview" mode: `git merge --no-commit --no-ff <branch>` to inspect the result before committing
- For phases with high coupling risk (plans that touch overlapping files), add a pre-merge analysis: `git diff main..branch-01 --name-only` intersected with `git diff main..branch-02 --name-only` to flag overlapping files
- Keep worktree branches alive until the human confirms the merged result works (don't auto-cleanup)
- Generate a merge report showing which files were touched by multiple branches

**Detection:** Overlapping file sets between branches. Test failures after merge that didn't exist in individual worktrees. Functions or imports that appear duplicated.

**Phase to address:** Phase covering merge orchestration. This should be one of the last phases built, after status monitoring is reliable, because merge safety depends on knowing that each branch is truly complete and tested.

---

### Pitfall 3: Orphaned Worktrees and Branches After Crashes

**What goes wrong:** If the orchestrator, Ralph, or the user's terminal crashes mid-execution, worktrees and branches are left in inconsistent states. The current cleanup script (`ralph-cleanup.sh`) only runs on explicit invocation. Orphaned worktrees accumulate outside the repo directory (in `$PARENT_DIR`), invisible to normal project tools. Over time, these consume disk space (each worktree is a near-full checkout), create branch name collisions on re-execution, and confuse `git worktree list`.

**Why it happens:** Git worktrees exist as directories outside the main repo. The only record of them is in `.git/worktrees/`. If the process creating or managing them dies, there is no automatic garbage collection. The current architecture (line 87 in `ralph-worktrees.sh`) places worktrees in `$PARENT_DIR/${REPO_NAME}-p${PHASE_NUM}-${PLAN_ID}` -- sibling directories to the repo. These are invisible to `.gitignore`, not tracked by any manifest, and easy to forget.

**Consequences:**
- `git worktree add` fails with "already checked out" errors on re-execution
- Disk fills with abandoned checkouts (especially problematic with large repos or `node_modules`)
- Branch names from previous runs collide with new execution attempts
- The user has to manually find and remove worktrees scattered in the parent directory

**Prevention:**
- Implement an `init` check that runs before every orchestrator operation: scan for stale worktrees, offer to clean them up
- Store worktree registry in a manifest file (`.gsd-ralph/worktrees.json`) that tracks creation time, expected branch, owning phase
- Add a `--force-clean` flag to `execute` that tears down any existing worktrees for the phase before creating new ones
- Set a configurable TTL for worktrees (e.g., 24 hours) and warn/clean on next invocation
- Use `git worktree list --porcelain` to detect prunable entries and run `git worktree prune` as part of every orchestrator startup

**Detection:** `git worktree list` shows entries pointing to non-existent directories. Directories matching `*-p*-*` pattern exist in parent directory without corresponding `git worktree list` entries. Branch names with `phase/` prefix exist but have no active worktree.

**Phase to address:** Phase 1 (worktree management). The registry/manifest pattern should be established early; it becomes the source of truth for all other operations (status, merge, cleanup).

---

### Pitfall 4: Status.json as a Lie -- Unreliable Agent Status Reporting

**What goes wrong:** The orchestrator relies on `.ralph/status.json` in each worktree to know if an agent is running, complete, blocked, or failed. But Ralph (the autonomous agent) must update this file itself -- and autonomous agents are unreliable reporters. Ralph may crash without updating status (still shows "running"). Ralph may report "complete" before its final commit lands. Ralph may never write status.json at all if it encounters an early error. The current `ralph-status.sh` (line 30-38) treats missing status.json as "not_started" -- but it could also mean "crashed before first write."

**Why it happens:** Status reporting is a convention, not an enforcement mechanism. There is no supervisor process watching the agent. The orchestrator script is run manually and reads a file that may be stale. The gap between "agent writes status" and "agent's actual state" is a fundamental distributed systems problem.

**Consequences:**
- `ralph-merge.sh` proceeds with merging branches where the agent crashed mid-task, producing incomplete code
- `ralph-status.sh` shows "running" for agents that died hours ago
- Human waits indefinitely for a "running" agent that is actually dead
- Auto-merge on "complete" status triggers on a stale status file from a previous run

**Prevention:**
- Implement a heartbeat mechanism: status.json should include a `last_heartbeat` timestamp updated every N seconds by an active agent. The status checker should consider any agent with a heartbeat older than 2*N seconds as potentially dead.
- Verify "complete" status against actual git state: check that the branch has commits ahead of main, that the last commit is recent, and that fix_plan.md shows all tasks checked off
- Add process ID (PID) tracking to status.json. The status checker can verify whether the PID is still alive.
- Never auto-merge based solely on status.json. Always require: (1) status says complete, (2) heartbeat is recent or process is terminated, (3) branch has commits, (4) optional: tests pass in worktree
- Include a `run_id` or `session_id` in status.json to distinguish current run from stale data

**Detection:** `last_activity` timestamp more than 10 minutes old with status "running." PID in status.json doesn't correspond to a live process. Branch has zero commits ahead of main despite "complete" status.

**Phase to address:** Phase covering status monitoring. This must be robust before merge automation depends on it.

---

### Pitfall 5: .planning/ Directory Divergence Across Worktrees

**What goes wrong:** The current `ralph-worktrees.sh` (line 108) copies `.planning/` into each worktree at creation time: `cp -r .planning "$WORKTREE_PATH/"`. This creates N independent copies of planning state. When one Ralph agent updates `STATE.md` (as instructed in the PROMPT.md template), that update exists only in its worktree. Other agents reading peer state via the "Read-Only Peer Visibility" paths (lines 137-148) see potentially stale or inconsistent planning data. After merge, there are N divergent versions of STATE.md, and the merged result is unpredictable.

**Why it happens:** Git worktrees branch from a point in time. Each worktree's branch has its own version of every file. `.planning/` files are meant to be shared state but become per-branch state. The PROMPT.md template (lines 119-154) tries to work around this by pointing agents to peer worktree paths for status checks, but this creates cross-worktree filesystem reads that bypass git entirely.

**Consequences:**
- STATE.md merge conflicts on every phase merge (the script even acknowledges this: line 94-95 of ralph-merge.sh)
- Agents make decisions based on stale peer status
- Dependencies between plans within a phase cannot be reliably checked via STATE.md
- Planning artifacts in main become incoherent after merge -- a Frankenstein of N branches' updates

**Prevention:**
- Treat `.planning/` as a read-only snapshot in worktrees. Agents should NOT modify STATE.md or other planning files in their worktree branches.
- Use a separate coordination mechanism for inter-agent status: either the status.json files (accessed via peer paths, which already exists), or a shared status file in the main repo that agents read but don't modify through git
- Add `.planning/STATE.md` to `.gitignore` in worktree branches, or use a post-merge hook to always take main's version
- Merge strategy: for `.planning/` files, always prefer the orchestrator's version (main), not the agent's version. Agents report status through status.json; the orchestrator updates STATE.md.
- Alternatively, use `git checkout --ours .planning/` as part of the merge script for planning files

**Detection:** `git diff main..branch -- .planning/` shows changes to planning files. Multiple branches modify the same planning files. STATE.md has merge conflicts.

**Phase to address:** Phase 1 (worktree setup) and Phase covering merge orchestration. The architectural decision about who owns STATE.md must be made early.

---

## Moderate Pitfalls

---

### Pitfall 6: Template Variable Substitution Fragility

**What goes wrong:** The PROMPT.md template uses heredoc string interpolation (bash `$VARIABLE` inside `cat >> ... << EOF`) to inject phase numbers, plan IDs, peer paths, and plan filenames. This works for simple cases but breaks when: variable values contain special characters, paths contain spaces, plan filenames deviate from expected patterns, or the template needs to include literal `$` signs. The python3 task extraction (lines 169-179 of ralph-worktrees.sh) uses regex to parse XML, which breaks on nested tags, CDATA sections, or multi-line content within tags.

**Why it happens:** Bash string interpolation is inherently fragile. Regex-based XML parsing is a known anti-pattern. The current approach works for the specific bayesian-it format but will fail on edge cases in other GSD projects.

**Consequences:**
- Generated PROMPT.md contains broken instructions (wrong paths, missing context)
- fix_plan.md extraction misses tasks or captures partial task names
- Agents start with corrupted instructions and produce wrong or off-scope work
- Failures are silent -- the agent gets a valid-looking but incorrect prompt

**Prevention:**
- Use a proper template engine instead of bash heredocs. Even a minimal one (envsubst, sed with delimiters, or a simple Python/Node script) is more robust than raw interpolation.
- For XML task extraction, use a proper parser. Python's `xml.etree.ElementTree` or a simple SAX parser handles edge cases that regex cannot.
- Validate generated files after template substitution: check that expected variables were replaced (no `${UNSET}` or empty strings), check that fix_plan.md has at least one task entry, check that PROMPT.md contains the plan file path.
- Use delimiter-based variables (`{{PHASE_NUM}}`, `{{PLAN_ID}}`) instead of bash variables to avoid escaping issues.

**Detection:** Empty or suspiciously short fix_plan.md. PROMPT.md containing literal `${` strings. Agent immediately confused about which plan to execute.

**Phase to address:** Phase covering prompt generation/template system.

---

### Pitfall 7: No Rollback Mechanism for Failed Merges

**What goes wrong:** The current `ralph-merge.sh` exits on the first conflict (line 96: `exit 1`). If the merge of branch 3 out of 5 fails, branches 1 and 2 are already merged into main. The user now has a partially merged main branch. To retry, they need to undo the partial merge (which requires knowing git well enough to `git reset --hard` to the pre-merge commit), fix the conflict, and re-run. There is no save point and no automated rollback.

**Why it happens:** The merge script is designed as a simple sequential loop without transaction semantics. It doesn't record the pre-merge state of main or provide any undo capability.

**Consequences:**
- Main branch in an inconsistent state (some plans merged, others not)
- Human must manually figure out how to undo partial merges
- Risk of data loss if the human runs `git reset --hard` incorrectly
- If the human just resolves the conflict and continues, they may miss that the already-merged branches interact badly with the conflict resolution

**Prevention:**
- Record the pre-merge commit hash before starting: `PRE_MERGE_SHA=$(git rev-parse HEAD)`. On any failure, offer: "Merge failed. Reset to pre-merge state? (git reset --hard $PRE_MERGE_SHA)"
- Use `git merge --no-commit --no-ff` for each branch, run tests, then `git commit`. This gives a chance to inspect before each merge is finalized.
- Implement a merge transaction: merge all branches to a temporary integration branch first. Only fast-forward main to the integration branch if all merges succeed and tests pass.
- Store merge checkpoints so partial progress can be resumed without re-merging already-merged branches

**Detection:** `ralph-merge.sh` exits with non-zero status. Main branch has more merge commits than expected. Tests fail on main after partial merge.

**Phase to address:** Phase covering merge orchestration.

---

### Pitfall 8: Cross-Worktree File Reads Are Fragile

**What goes wrong:** The PROMPT.md template (lines 143-148 of ralph-worktrees.sh) instructs agents to read peer status via absolute filesystem paths: `${PEER_PATH}/.planning/STATE.md` and `${PEER_PATH}/.ralph/status.json`. These paths are hardcoded at worktree creation time. If a worktree is recreated, moved, or cleaned up while peers are still running, the paths become dangling references. The agent encounters FileNotFoundError or reads stale data from a previous run's leftover files.

**Why it happens:** Absolute paths are brittle. They assume all worktrees exist simultaneously and at fixed locations for the entire execution duration. The paths are baked into the PROMPT.md at creation time, not resolved dynamically.

**Consequences:**
- Agent errors trying to read non-existent peer paths
- Agent reads stale status from a leftover directory (previous phase's worktree at same path)
- Agent incorrectly concludes a peer is blocked/complete based on garbage data
- Dependency checking between plans fails silently

**Prevention:**
- Use a centralized status registry instead of cross-filesystem reads. A single status file in the main repo (or a lightweight coordination file) that the orchestrator maintains based on individual worktree status.json files.
- If keeping peer paths, make them relative to a discoverable base directory and verify they exist before reading
- Add a `phase_id` and `run_id` to status.json so agents can detect stale data from a previous run
- Implement graceful degradation: if a peer path doesn't exist, log a warning and proceed rather than failing

**Detection:** Agent logs show file-not-found errors for peer paths. Agent reports conflicting information about peer status. Peer paths in PROMPT.md point to directories that no longer exist.

**Phase to address:** Phase covering worktree setup and status monitoring.

---

### Pitfall 9: Process Lifecycle Blindness -- No Supervision of Agent Processes

**What goes wrong:** The current architecture requires the human to manually start Ralph in each worktree (open N terminals, cd, run ralph). There is no process supervisor. If a terminal closes, the agent dies silently. If the agent hangs (infinite loop, network timeout waiting for API), there is no watchdog to kill and restart it. The orchestrator has no way to detect this beyond checking status.json, which the hung agent may not update.

**Why it happens:** The original workflow was designed for a human running 2-3 agents and watching them. Scaling to many parallel agents requires proper process management that bash scripts traditionally don't provide.

**Consequences:**
- Agents die without notification; human discovers hours later
- Hung agents consume API credits without making progress
- No automatic recovery from transient failures
- Phase execution takes much longer than necessary due to undetected failures

**Prevention:**
- Implement a process supervisor mode: `gsd-ralph execute N --supervised` that launches all Ralph instances as background processes and monitors them
- Track PIDs in the worktree registry. Periodically check if PIDs are alive.
- Implement a watchdog: if status.json `last_activity` hasn't changed in X minutes and the process is still alive, it may be hung. Alert the human.
- Use terminal bell or notification (already in requirements) when an agent completes OR when an agent appears hung/dead
- At minimum, provide a `gsd-ralph doctor N` command that checks: are all agent processes alive? Are all status files being updated? Are any agents stuck?

**Detection:** PID in status.json is no longer a running process. `last_activity` timestamp is stale. Terminal running Ralph has been closed.

**Phase to address:** Later phase, after core worktree and status infrastructure is solid. Process supervision is a feature enhancement over the manual "open N terminals" approach.

---

### Pitfall 10: GSD Naming Convention Edge Cases

**What goes wrong:** GSD has dual naming: `PLAN.md` for single-plan phases and `NN-MM-PLAN.md` for multi-plan phases. The current discovery logic (lines 50-61 of ralph-worktrees.sh) uses `find -name "*-PLAN.md"` for numbered plans, falling back to `PLAN.md`. This glob will also match files like `DRAFT-PLAN.md`, `OLD-PLAN.md`, or `BACKUP-PLAN.md` that aren't actual numbered plans. The plan index assignment (line 83: `PLAN_ID=$(printf "%02d" $PLAN_IDX)`) derives the worktree/branch numbering from array order, not from the actual NN-MM prefix in the filename. If files are discovered in a different order than expected, plans get assigned to the wrong worktrees.

**Why it happens:** Glob patterns are imprecise. The `find | sort` approach sorts lexicographically, which usually works for zero-padded numbers but breaks for mixed naming. The code doesn't extract the actual plan number from the filename -- it just counts array positions.

**Consequences:**
- Wrong plan assigned to wrong worktree/branch
- Non-plan files treated as plans, creating empty or broken worktrees
- Plan numbering in branch names doesn't match plan numbering in filenames
- PHASES.md index is wrong, confusing the human and the status checker

**Prevention:**
- Use a strict regex for numbered plans: `[0-9][0-9]-[0-9][0-9]-PLAN.md` instead of `*-PLAN.md`
- Extract the actual plan number from the filename (the NN-MM prefix) and use it for branch naming instead of array index
- Validate discovered plan files: check they match the expected GSD format, contain XML task blocks
- Log a warning if unexpected files matching `*-PLAN.md` are found but don't match the strict pattern

**Detection:** Branch name numbers don't match plan filename numbers. Worktree PROMPT.md references wrong plan file. Extra worktrees created for non-plan files.

**Phase to address:** Phase 1 (plan discovery/worktree creation).

---

## Minor Pitfalls

---

### Pitfall 11: node_modules and Build Artifacts in Worktrees

**What goes wrong:** Each git worktree is a full checkout. If the project has `node_modules/` (not gitignored contents, but the need to install), each worktree needs its own `npm install` before tests can run. The current scripts don't handle dependency installation. Ralph agents may try to run tests in a worktree with no `node_modules/`, fail, and report the task as blocked.

**Prevention:**
- Add a post-worktree-creation hook that runs `npm install` (or equivalent) in each worktree
- Or use symlinks/hardlinks for `node_modules` (npm supports this poorly, but pnpm's content-addressable store handles it well)
- Document that worktrees need dependency installation; better yet, automate it

**Phase to address:** Phase 1 (worktree setup).

---

### Pitfall 12: Ralph Session State Contamination

**What goes wrong:** Ralph stores session state in `.ralph/` (`.ralph_session`, `.call_count`, `.last_reset`). The current merge script (lines 63-65 of ralph-merge.sh) manually cleans these files before merging. But if a new Ralph runtime file is added in the future, the cleanup list becomes stale and merges break with "untracked working tree files would be overwritten" errors.

**Prevention:**
- Instead of maintaining a manual list of files to clean, add `.ralph/*.json`, `.ralph/.ralph_session`, `.ralph/.call_count`, `.ralph/.last_reset` to `.gitignore` in worktree branches
- Or better: ensure agents don't commit Ralph runtime files at all (`.ralph/` should be in `.gitignore` except for config files)
- Use a pattern-based cleanup: remove all files in `.ralph/` except PROMPT.md, AGENT.md, and other config files

**Phase to address:** Phase covering worktree setup (gitignore configuration).

---

### Pitfall 13: Hardcoded Bash Assumptions About Environment

**What goes wrong:** The current scripts assume `python3` is available (line 169 of ralph-worktrees.sh), `jq` is available (throughout ralph-status.sh and ralph-merge.sh), `date -Iseconds` works (macOS `date` doesn't support `-I` by default -- it requires GNU coreutils). Cross-platform portability breaks on Linux vs macOS differences.

**Prevention:**
- Check for required tools at startup and provide clear error messages
- Use POSIX-compatible alternatives or document requirements
- For date formatting, use `date -u +%Y-%m-%dT%H:%M:%S%z` which works on both macOS and Linux
- Consider rewriting critical logic in a language with fewer platform dependencies (Node.js/TypeScript, which is already in the ecosystem)

**Phase to address:** Phase 1. Environment validation should be one of the first things the tool does.

---

### Pitfall 14: No Idempotency in Orchestration Steps

**What goes wrong:** Running `ralph-execute.sh 2` twice with existing worktrees asks the user to choose "skip or recreate." But `ralph-worktrees.sh` appends to PHASES.md unconditionally (lines 204-226), creating duplicate entries. Branch creation is idempotent (checks existence), but the PROMPT.md template is re-appended if the script is re-run after worktree creation.

**Prevention:**
- Make every operation idempotent: check if the expected end state already exists before acting
- Use the worktree registry (Pitfall 3's manifest) as the source of truth for what exists
- Gate PHASES.md updates on whether the phase section already exists
- Overwrite rather than append to PROMPT.md when regenerating

**Phase to address:** Phase 1 (core operations).

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|---------------|------------|
| Worktree creation/management | Orphaned worktrees (P3), Git lock contention (P1), Naming edge cases (P10) | Build registry manifest first; implement retry loops; use strict naming regex |
| Prompt generation/templates | Template fragility (P6), .planning/ divergence (P5) | Use proper template engine; designate .planning/ as read-only in worktrees |
| Status monitoring | Unreliable status (P4), Process blindness (P9), Cross-worktree reads (P8) | Heartbeat mechanism; PID tracking; centralized status registry |
| Merge orchestration | Merge order sensitivity (P2), No rollback (P7), Partial merges | Pre-merge commit save point; test after each merge; integration branch pattern |
| Cleanup | Session contamination (P12), Idempotency (P14) | Pattern-based cleanup; registry-driven operations |
| Environment/portability | Hardcoded assumptions (P13), node_modules (P11) | Startup validation; automated dependency installation |

---

## Architectural Risk: The Fundamental Coordination Problem

The deepest pitfall spanning this entire project is **treating a distributed system as a local tool**. Multiple autonomous agents running in parallel worktrees is a distributed system. They share state (git objects, planning files), they need coordination (dependency checking, status reporting), and they can fail independently. But the current architecture uses filesystem conventions (status.json, peer paths, glob patterns) instead of proper coordination primitives.

This is not a call to over-engineer. But the tool should be designed with awareness that:

1. **Any file read may be stale** -- another process may have updated it since you read it
2. **Any process may die at any time** -- no operation should leave the system in an unrecoverable state
3. **Order of operations matters** -- merges, status checks, and cleanups must handle partial completion
4. **The human is the ultimate supervisor** -- the tool should make the system state visible and recoverable, not try to handle every edge case automatically

The recommended mitigation is: build a **worktree registry** (manifest file) as the single source of truth, and have every operation (create, status, merge, cleanup) read from and update this registry rather than relying on filesystem glob patterns and scattered status files.

---

## Sources

- Codebase analysis: `scripts/ralph-worktrees.sh`, `ralph-merge.sh`, `ralph-execute.sh`, `ralph-status.sh`, `ralph-cleanup.sh` (HIGH confidence -- direct code inspection)
- `templates/PROMPT.md.template` -- actual template used in production at bayesian-it (HIGH confidence)
- Git worktree documentation: shared object store and ref namespace behavior (MEDIUM confidence -- training data, not verified against current git version)
- Distributed systems coordination patterns (MEDIUM confidence -- well-established principles from training data)
- Ralph status reporting conventions parsed from PROMPT.md template (HIGH confidence -- direct code inspection)
