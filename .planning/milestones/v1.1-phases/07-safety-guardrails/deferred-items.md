# Deferred Items -- Phase 07 Safety Guardrails

## Pre-existing test failures: GSD_RALPH_HOME not set in test helpers

**Discovered during:** 07-03 Task 2 (integration test verification)

**Issue:** The `register_test_branch()` helper in `tests/cleanup.bats` sources
`lib/cleanup/registry.sh` which (since 07-01) sources `$GSD_RALPH_HOME/lib/safety.sh`.
However, `register_test_branch()` does not export `GSD_RALPH_HOME="$PROJECT_ROOT"`,
so the source resolves to `/lib/safety.sh` (nonexistent).

Same issue affects `tests/prompt.bats` where `lib/prompt.sh` now sources safety.sh.

**Affected tests:** 11 tests in cleanup.bats, 9 tests in prompt.bats (all that use
`register_test_branch` or source `prompt.sh` directly).

**Fix:** Add `export GSD_RALPH_HOME="$PROJECT_ROOT"` to the `register_test_branch()`
helper in cleanup.bats and to the `setup()` function in prompt.bats.

**Not fixed here because:** Out of scope -- pre-existing issue caused by 07-01/07-02
changes, not by 07-03 safety test additions.
