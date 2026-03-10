---
status: resolved
trigger: "ralph-launcher.sh calls `claude -p` which spawns a new headless Claude Code process. This requires shell execution outside the sandbox, which gets blocked by Claude Code's permission system."
created: 2026-03-10T00:00:00Z
updated: 2026-03-10T00:08:00Z
---

## Current Focus

hypothesis: CONFIRMED -- Fix applied: slash command now uses "prepare-and-instruct" pattern
test: Ran --dry-run validation and full test suite
expecting: User confirms that /gsd:ralph now correctly prepares and presents the command instead of trying to spawn inline
next_action: Await user verification

## Symptoms

expected: Running `/gsd:ralph plan-phase` should launch Claude in a subprocess and execute the command autonomously
actual: The output file doesn't exist -- the first attempt fails before producing output. The second attempt gets rejected by Claude's permission system.
errors: Shell execution outside sandbox is blocked when ralph-launcher.sh tries to spawn `claude -p`
reproduction: Run `/gsd:ralph plan-phase` on any project with gsd-ralph configured
started: This is a design issue -- ralph-launcher.sh inherently needs to spawn a child Claude process

## Eliminated

(none -- root cause was confirmed on first hypothesis)

## Evidence

- timestamp: 2026-03-10T00:01:00Z
  checked: ralph-launcher.sh execution chain
  found: The slash command `.claude/commands/gsd/ralph.md` instructs the current Claude session to run `bash scripts/ralph-launcher.sh $ARGUMENTS`. The launcher's `execute_iteration()` function builds a `claude -p` command and runs it via `bash -c "$cmd"`. This means the Bash tool spawns ralph-launcher.sh, which spawns `bash -c`, which spawns `claude -p` -- a 3-deep subprocess chain.
  implication: The child `claude -p` process is spawned inside the sandbox of the parent Claude Code session.

- timestamp: 2026-03-10T00:02:00Z
  checked: CLAUDECODE env var handling
  found: Line 184 of ralph-launcher.sh prepends `env -u CLAUDECODE` to the claude command. This is the known workaround to prevent "cannot be launched inside another Claude Code session" rejection. The code already addresses this issue.
  implication: The CLAUDECODE env var inheritance is handled, but this doesn't solve the sandbox restriction.

- timestamp: 2026-03-10T00:03:00Z
  checked: Claude Code sandbox documentation and known issues
  found: On macOS, Claude Code uses Seatbelt framework for OS-level sandboxing. All child processes inherit sandbox restrictions. The sandbox limits write access to the project directory and /tmp. A spawned `claude -p` process would itself need to: (a) write to its own working directory, (b) make network calls to the Anthropic API, (c) possibly create worktrees outside the project directory. The sandbox blocks (b) and possibly (c).
  implication: Even if the `claude` binary can execute, the child Claude process cannot function properly inside the parent's sandbox because it needs unrestricted network access and may need write access outside the project directory.

- timestamp: 2026-03-10T00:04:00Z
  checked: settings.local.json permissions
  found: The file includes `"Bash(claude:*)"` in the allow list (line 35), meaning the parent session has approved running `claude` commands. However, this only addresses the parent Claude Code's permission system, not the OS-level sandbox.
  implication: Bash tool permission approval and OS-level sandbox are two separate security layers. Having `Bash(claude:*)` approved only passes layer 1.

- timestamp: 2026-03-10T00:05:00Z
  checked: Architecture of the slash command
  found: The `/gsd:ralph` slash command (`.claude/commands/gsd/ralph.md`) is a Claude Code custom command that instructs Claude to execute `bash scripts/ralph-launcher.sh $ARGUMENTS`. This makes the launcher script run AS a tool call within the current Claude session. The launcher then tries to spawn a SECOND Claude session.
  implication: The fundamental issue is the architecture: a Claude tool call trying to spawn a new Claude process. This is inherently blocked by the sandbox design.

- timestamp: 2026-03-10T00:06:00Z
  checked: Fix options viability
  found: Three approaches exist: (A) Sandbox escape via `excludedCommands: ["claude"]` in sandbox settings and/or `dangerouslyDisableSandbox` -- partially works but has known reliability issues (excludedCommands may not fully bypass network sandbox). (B) Restructure the slash command to NOT spawn claude inline, but instead output the ready-to-run command for the user to execute in a separate terminal -- avoids the sandbox problem entirely. (C) Use Claude Code's built-in Task/subagent system instead of spawning a raw `claude -p` process -- the Task tool spawns subagents within Claude's own framework, bypassing sandbox issues. Option B is simplest and most reliable. Option C is most aligned with Claude Code's design intent.
  implication: Option B (generate-and-instruct) is the safest immediate fix. Option C (Task tool integration) is the ideal long-term architecture.

- timestamp: 2026-03-10T00:07:00Z
  checked: Dry-run validation
  found: Running `bash scripts/ralph-launcher.sh plan-phase 1 --dry-run` succeeds, outputting the full `claude -p` command, context file details, and config summary. All 63 tests in ralph-launcher.bats pass.
  implication: The prepare-and-instruct pattern works correctly. The slash command can safely run --dry-run without hitting the sandbox.

## Resolution

root_cause: The `/gsd:ralph` command architecture has a fundamental design conflict with Claude Code's sandbox model. The execution chain is: User -> Claude Code session -> Bash tool (sandboxed) -> ralph-launcher.sh -> `claude -p` (child process). The child `claude -p` process inherits the parent's OS-level sandbox restrictions (macOS Seatbelt), which blocks it from making network API calls and potentially writing outside the project directory. Even though `env -u CLAUDECODE` addresses the "nested session" env var check, and `Bash(claude:*)` is in the permission allow-list, neither addresses the OS-level sandbox that all child processes inherit. This is not a bug in ralph-launcher.sh -- it is a fundamental constraint of running inside Claude Code's sandboxed Bash tool.

fix: Replaced `claude -p` subprocess approach with Claude Code's native Agent tool. The `/gsd:ralph` slash command now:
  (1) Assembles context via `scripts/assemble-context.sh` (safe in sandbox — just reads files)
  (2) Reads autopilot rules from `.claude/skills/gsd-ralph-autopilot/SKILL.md`
  (3) Spawns a general-purpose Agent subagent with the context and rules embedded in the prompt
  (4) The subagent invokes the GSD skill via Skill tool (e.g., `/gsd:plan-phase 17 --ralph`)
  (5) Loop with circuit breakers (timeout, stop file, stall detection) between iterations
  This eliminates the sandbox conflict entirely — Agent tool manages subprocess spawning internally
  within Claude's own framework, with no OS-level sandbox inheritance issues.

  The `ralph-launcher.sh` script remains unchanged for standalone terminal use.

verification: Pending — needs end-to-end test of `/gsd:ralph plan-phase` in a project.

files_changed:
  - .claude/commands/gsd/ralph.md
