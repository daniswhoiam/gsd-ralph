#!/usr/bin/env bats
# tests/installer.bats -- Tests for install.sh installer
# Covers: INST-01, INST-02, INST-03, INST-04, INST-06

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
# Prerequisite checks (INST-02, INST-03)
# ============================================================

@test "installer: exits non-zero without .planning/ directory" {
    # No GSD structure created -- bare temp dir
    run bash "$INSTALLER"
    assert_failure
    assert_output --partial "GSD"
}

@test "installer: exits non-zero without .planning/config.json" {
    mkdir -p .planning
    run bash "$INSTALLER"
    assert_failure
    assert_output --partial "config"
}

@test "installer: exits non-zero when jq is missing" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    # Create a restricted PATH that excludes jq
    local safe_path=""
    local dir
    while IFS= read -r dir; do
        if [ -d "$dir" ]; then
            safe_path="${safe_path:+$safe_path:}$dir"
        fi
    done <<< "$(echo "$PATH" | tr ':' '\n')"

    # Shadow jq with a script that exits 1
    mkdir -p "$TEST_TEMP_DIR/fake_bin"
    cat > "$TEST_TEMP_DIR/fake_bin/jq" <<'FAKE'
#!/bin/bash
exit 127
FAKE
    chmod +x "$TEST_TEMP_DIR/fake_bin/jq"

    # Actually, simpler: use a PATH with no jq
    # Create a minimal PATH with only essential commands
    run env PATH="/usr/bin:/bin:$TEST_TEMP_DIR/fake_bin" bash "$INSTALLER"
    # The check_prerequisites function uses command -v jq, so if we shadow it
    # we need to make command -v fail. Let's use a subshell approach instead.
    # Actually, use a wrapper that hides jq from command -v by using a custom function

    # Simplest approach: create a wrapper script that unsets jq from PATH
    cat > "$TEST_TEMP_DIR/run_without_jq.sh" <<WRAPPER
#!/bin/bash
# Build a PATH that excludes directories containing jq
NEW_PATH=""
IFS=':' read -ra DIRS <<< "\$PATH"
for dir in "\${DIRS[@]}"; do
    if [ ! -x "\$dir/jq" ]; then
        NEW_PATH="\${NEW_PATH:+\$NEW_PATH:}\$dir"
    fi
done
export PATH="\$NEW_PATH"
exec bash "$INSTALLER"
WRAPPER
    chmod +x "$TEST_TEMP_DIR/run_without_jq.sh"

    run bash "$TEST_TEMP_DIR/run_without_jq.sh"
    assert_failure
    assert_output --partial "jq"
}

@test "installer: exits non-zero when git is missing" {
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    cat > "$TEST_TEMP_DIR/run_without_git.sh" <<WRAPPER
#!/bin/bash
NEW_PATH=""
IFS=':' read -ra DIRS <<< "\$PATH"
for dir in "\${DIRS[@]}"; do
    if [ ! -x "\$dir/git" ]; then
        NEW_PATH="\${NEW_PATH:+\$NEW_PATH:}\$dir"
    fi
done
export PATH="\$NEW_PATH"
exec bash "$INSTALLER"
WRAPPER
    chmod +x "$TEST_TEMP_DIR/run_without_git.sh"

    run bash "$TEST_TEMP_DIR/run_without_git.sh"
    assert_failure
    assert_output --partial "git"
}

@test "installer: detects self-install (source == target) and exits with error" {
    # Run installer from within the gsd-ralph repo itself
    cd "$REAL_PROJECT_ROOT"
    run bash "$INSTALLER"
    assert_failure
    assert_output --partial "same"
}

@test "installer: all prerequisite checks run before file operations (no partial install)" {
    # Create a dir with .planning but no config.json -- should fail prereqs
    mkdir -p .planning
    # Don't create config.json

    run bash "$INSTALLER"
    assert_failure

    # No files should have been created
    assert [ ! -d "scripts/ralph" ]
    assert [ ! -f ".claude/commands/gsd/ralph.md" ]
}

# ============================================================
# File copy manifest (INST-01, INST-06)
# ============================================================

@test "installer: creates scripts/ralph/ with 4 .sh files" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    assert [ -f "scripts/ralph/ralph-launcher.sh" ]
    assert [ -f "scripts/ralph/assemble-context.sh" ]
    assert [ -f "scripts/ralph/validate-config.sh" ]
    assert [ -f "scripts/ralph/ralph-hook.sh" ]
}

@test "installer: creates .claude/commands/gsd/ralph.md" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    assert [ -f ".claude/commands/gsd/ralph.md" ]
}

@test "installer: creates .claude/skills/gsd-ralph-autopilot/SKILL.md" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    assert [ -f ".claude/skills/gsd-ralph-autopilot/SKILL.md" ]
}

@test "installer: all 4 .sh files in scripts/ralph/ are executable" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    assert [ -x "scripts/ralph/ralph-launcher.sh" ]
    assert [ -x "scripts/ralph/assemble-context.sh" ]
    assert [ -x "scripts/ralph/validate-config.sh" ]
    assert [ -x "scripts/ralph/ralph-hook.sh" ]
}

@test "installer: installed ralph.md contains scripts/ralph/ralph-launcher.sh path" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    run grep "scripts/ralph/ralph-launcher.sh" ".claude/commands/gsd/ralph.md"
    assert_success
}

@test "installer: installed scripts match source scripts byte-for-byte" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    # Compare each script file
    run cmp -s "$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh" "scripts/ralph/ralph-launcher.sh"
    assert_success

    run cmp -s "$REAL_PROJECT_ROOT/scripts/assemble-context.sh" "scripts/ralph/assemble-context.sh"
    assert_success

    run cmp -s "$REAL_PROJECT_ROOT/scripts/validate-config.sh" "scripts/ralph/validate-config.sh"
    assert_success

    run cmp -s "$REAL_PROJECT_ROOT/scripts/ralph-hook.sh" "scripts/ralph/ralph-hook.sh"
    assert_success

    # SKILL.md should also match
    run cmp -s "$REAL_PROJECT_ROOT/.claude/skills/gsd-ralph-autopilot/SKILL.md" ".claude/skills/gsd-ralph-autopilot/SKILL.md"
    assert_success
}

# ============================================================
# Idempotency (INST-04)
# ============================================================

@test "installer: running twice produces exit code 0 both times" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    run bash "$INSTALLER"
    assert_success

    run bash "$INSTALLER"
    assert_success
}

@test "installer: re-run when files match skips all copies (no timestamp changes)" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    bash "$INSTALLER"

    # Record modification times
    local ts_launcher ts_context ts_validate ts_hook
    ts_launcher=$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")
    ts_context=$(stat -f "%m" "scripts/ralph/assemble-context.sh")
    ts_validate=$(stat -f "%m" "scripts/ralph/validate-config.sh")
    ts_hook=$(stat -f "%m" "scripts/ralph/ralph-hook.sh")

    # Wait a moment to ensure any re-copy would change timestamps
    sleep 1

    bash "$INSTALLER"

    # Verify timestamps unchanged
    assert_equal "$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")" "$ts_launcher"
    assert_equal "$(stat -f "%m" "scripts/ralph/assemble-context.sh")" "$ts_context"
    assert_equal "$(stat -f "%m" "scripts/ralph/validate-config.sh")" "$ts_validate"
    assert_equal "$(stat -f "%m" "scripts/ralph/ralph-hook.sh")" "$ts_hook"
}

@test "installer: re-run when one file differs updates only that file" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    bash "$INSTALLER"

    # Modify one file
    echo "# modified" >> "scripts/ralph/validate-config.sh"

    # Record timestamps of other files
    local ts_launcher ts_hook
    ts_launcher=$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")
    ts_hook=$(stat -f "%m" "scripts/ralph/ralph-hook.sh")

    sleep 1

    bash "$INSTALLER"

    # validate-config.sh should be restored (content matches source)
    run cmp -s "$REAL_PROJECT_ROOT/scripts/validate-config.sh" "scripts/ralph/validate-config.sh"
    assert_success

    # Other files should NOT have been re-copied
    assert_equal "$(stat -f "%m" "scripts/ralph/ralph-launcher.sh")" "$ts_launcher"
    assert_equal "$(stat -f "%m" "scripts/ralph/ralph-hook.sh")" "$ts_hook"
}

# ============================================================
# Self-location (structural)
# ============================================================

@test "installer: resolves source directory correctly via absolute path" {
    create_test_repo
    create_gsd_structure
    create_ralph_config
    cd "$TEST_TEMP_DIR"

    # Invoke via absolute path
    run bash "$INSTALLER"
    assert_success

    # Verify files came from the right source
    run cmp -s "$REAL_PROJECT_ROOT/scripts/ralph-launcher.sh" "scripts/ralph/ralph-launcher.sh"
    assert_success
}
