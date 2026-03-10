#!/usr/bin/env bats
# tests/e2e-install.bats -- End-to-end install workflow scenario tests
# Covers: SC-1 (fresh install, existing .claude/, non-GSD), SC-2 (dry-run), SC-3 (idempotency)
# Complements installer.bats (unit/integration) with workflow-chain validation.

setup() {
    load 'test_helper/common'
    load 'test_helper/ralph-helpers'
    _common_setup
    REAL_PROJECT_ROOT="$(get_real_project_root)"
    INSTALLER="$REAL_PROJECT_ROOT/install.sh"
}

teardown() {
    _common_teardown
}

# ============================================================
# SC-1a: Fresh GSD project install
# ============================================================

@test "e2e: fresh GSD project -- install succeeds and all artifacts exist" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo","parallelization":true}'
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    # Verify scripts/ralph/ directory with 4 executable scripts
    assert [ -d "scripts/ralph" ]
    assert [ -x "scripts/ralph/ralph-launcher.sh" ]
    assert [ -x "scripts/ralph/assemble-context.sh" ]
    assert [ -x "scripts/ralph/validate-config.sh" ]
    assert [ -x "scripts/ralph/ralph-hook.sh" ]

    # Verify command and skill files
    assert [ -f ".claude/commands/gsd/ralph.md" ]
    assert [ -f ".claude/skills/gsd-ralph-autopilot/SKILL.md" ]

    # Verify ralph config key added
    run jq -e '.ralph' .planning/config.json
    assert_success
}

# ============================================================
# SC-1b: Existing .claude/ files preserved
# ============================================================

@test "e2e: existing .claude/ files preserved during install" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo","parallelization":true}'
    cd "$TEST_TEMP_DIR"

    # Create pre-existing .claude/ content before install
    mkdir -p .claude/commands
    echo '{"permissions":{"allow":["Read"]}}' > .claude/settings.local.json
    echo "# existing command" > .claude/commands/existing.md

    run bash "$INSTALLER"
    assert_success

    # Pre-existing files must survive with original content
    assert [ -f ".claude/settings.local.json" ]
    assert [ -f ".claude/commands/existing.md" ]
    run cat .claude/settings.local.json
    assert_output --partial "Read"
    run cat .claude/commands/existing.md
    assert_output --partial "existing command"

    # Ralph files also installed alongside
    assert [ -f ".claude/commands/gsd/ralph.md" ]
    assert [ -f ".claude/skills/gsd-ralph-autopilot/SKILL.md" ]
}

# ============================================================
# SC-1c: Non-GSD repo fails with guidance
# ============================================================

@test "e2e: non-GSD repo -- installer fails with guidance" {
    create_test_repo
    cd "$TEST_TEMP_DIR"

    # No GSD structure -- should fail
    run bash "$INSTALLER"
    assert_failure
    assert_output --partial "GSD"
}

# ============================================================
# SC-2: Install-then-dry-run chain
# ============================================================

@test "e2e: installed ralph-launcher.sh produces valid dry-run output" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo","parallelization":true}'
    cd "$TEST_TEMP_DIR"

    # Step 1: Install
    bash "$INSTALLER"

    # Step 2: Create minimal phase structure for dry-run
    # STATE.md already has "Phase: 1" from create_gsd_structure
    mkdir -p .planning/phases/1-test-phase
    cat > .planning/phases/1-test-phase/1-01-PLAN.md <<'EOF'
---
phase: 1
plan: 1
---
# Test Plan
## Tasks
- Task 1: Example
EOF

    # Step 3: Run the INSTALLED launcher (not the source one)
    run bash scripts/ralph/ralph-launcher.sh execute-phase 1 --dry-run
    assert_success
    assert_output --partial "Ralph Dry Run"
    assert_output --partial "max_turns"
    assert_output --partial "Context lines:"
}

# ============================================================
# SC-3: Re-install idempotency (zero file changes)
# ============================================================

@test "e2e: full re-install produces zero file changes (idempotent)" {
    create_test_repo
    create_gsd_structure
    create_ralph_config_raw '{"mode":"yolo","parallelization":true}'
    cd "$TEST_TEMP_DIR"

    # First install
    bash "$INSTALLER"

    # Record timestamps of ALL installed files
    local ts_launcher ts_context ts_validate ts_hook ts_cmd ts_skill
    ts_launcher=$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")
    ts_context=$(stat -f "%m" "scripts/ralph/assemble-context.sh")
    ts_validate=$(stat -f "%m" "scripts/ralph/validate-config.sh")
    ts_hook=$(stat -f "%m" "scripts/ralph/ralph-hook.sh")
    ts_cmd=$(stat -f "%m" ".claude/commands/gsd/ralph.md")
    ts_skill=$(stat -f "%m" ".claude/skills/gsd-ralph-autopilot/SKILL.md")

    sleep 1

    # Second install
    run bash "$INSTALLER"
    assert_success
    assert_output --partial "already up to date"

    # ALL timestamps must be unchanged
    assert_equal "$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")" "$ts_launcher"
    assert_equal "$(stat -f "%m" "scripts/ralph/assemble-context.sh")" "$ts_context"
    assert_equal "$(stat -f "%m" "scripts/ralph/validate-config.sh")" "$ts_validate"
    assert_equal "$(stat -f "%m" "scripts/ralph/ralph-hook.sh")" "$ts_hook"
    assert_equal "$(stat -f "%m" ".claude/commands/gsd/ralph.md")" "$ts_cmd"
    assert_equal "$(stat -f "%m" ".claude/skills/gsd-ralph-autopilot/SKILL.md")" "$ts_skill"
}
