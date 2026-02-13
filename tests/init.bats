#!/usr/bin/env bats
# tests/init.bats -- Integration tests for gsd-ralph init command

setup() {
    load 'test_helper/common'
    _common_setup
    create_test_repo
    create_gsd_structure
}

teardown() {
    _common_teardown
}

# ---------------------------------------------------------------------------
# Success scenarios
# ---------------------------------------------------------------------------

@test "init creates .ralph directory" {
    run gsd-ralph init
    assert_success
    assert_dir_exists ".ralph"
}

@test "init creates .ralph/logs directory" {
    run gsd-ralph init
    assert_success
    assert_dir_exists ".ralph/logs"
}

@test "init creates .ralphrc in project root" {
    run gsd-ralph init
    assert_success
    assert_file_exists ".ralphrc"
}

@test "init .ralphrc contains project name" {
    run gsd-ralph init
    assert_success
    local dir_name
    dir_name="$(basename "$TEST_TEMP_DIR")"
    run grep "PROJECT_NAME=\"${dir_name}\"" .ralphrc
    assert_success
}

@test "init detects typescript project" {
    echo '{"scripts":{"test":"vitest","build":"tsc"}}' > package.json
    touch tsconfig.json
    run gsd-ralph init
    assert_success
    assert_output --partial "typescript"
}

@test "init detects rust project" {
    cat > Cargo.toml <<'EOF'
[package]
name = "test-project"
version = "0.1.0"
EOF
    run gsd-ralph init
    assert_success
    assert_output --partial "rust"
}

@test "init detects go project" {
    cat > go.mod <<'EOF'
module example.com/test
go 1.21
EOF
    run gsd-ralph init
    assert_success
    assert_output --partial "go"
}

@test "init detects python project" {
    cat > pyproject.toml <<'EOF'
[project]
name = "test-project"
EOF
    run gsd-ralph init
    assert_success
    assert_output --partial "python"
}

@test "init handles unknown project type" {
    # No marker files -- should still succeed per XCUT-01
    run gsd-ralph init
    assert_success
    assert_output --partial "unknown"
}

@test "init .ralphrc has no unresolved placeholders" {
    run gsd-ralph init
    assert_success
    run grep "{{" .ralphrc
    assert_failure  # grep should find nothing
}

@test "init .ralphrc contains detected test command for typescript project" {
    echo '{"scripts":{"test":"vitest","build":"tsc"}}' > package.json
    touch tsconfig.json
    run gsd-ralph init
    assert_success
    run grep 'TEST_CMD="npm test"' .ralphrc
    assert_success
}

@test "init .ralphrc contains detected build command for typescript project" {
    echo '{"scripts":{"test":"vitest","build":"tsc"}}' > package.json
    touch tsconfig.json
    run gsd-ralph init
    assert_success
    run grep 'BUILD_CMD="npm run build"' .ralphrc
    assert_success
}

# ---------------------------------------------------------------------------
# Failure scenarios
# ---------------------------------------------------------------------------

@test "init fails outside git repo" {
    local non_git_dir
    non_git_dir="$(mktemp -d)"
    cd "$non_git_dir" || return 1
    run gsd-ralph init
    assert_failure
    assert_output --partial "Not inside a git repository"
    rm -rf "$non_git_dir"
}

@test "init fails without .planning directory" {
    rm -rf .planning
    run gsd-ralph init
    assert_failure
    assert_output --partial ".planning"
}

# ---------------------------------------------------------------------------
# Idempotency
# ---------------------------------------------------------------------------

@test "init warns when .ralph already exists" {
    run gsd-ralph init
    assert_success
    run gsd-ralph init
    assert_success
    assert_output --partial "already exists"
}

@test "init succeeds with --force when .ralph exists" {
    run gsd-ralph init
    assert_success
    run gsd-ralph init --force
    assert_success
}

@test "init --force overwrites .ralphrc" {
    run gsd-ralph init
    assert_success
    # Modify .ralphrc
    echo "# custom modification" >> .ralphrc
    run gsd-ralph init --force
    assert_success
    # Verify custom modification is gone
    run grep "# custom modification" .ralphrc
    assert_failure
}

@test "init -f short flag works" {
    run gsd-ralph init
    assert_success
    run gsd-ralph init -f
    assert_success
}

# ---------------------------------------------------------------------------
# Dependency checking
# ---------------------------------------------------------------------------

@test "init checks for required dependencies" {
    # Source common.sh to access check_dependency directly
    source "$PROJECT_ROOT/lib/common.sh"
    # Test that a nonexistent tool fails
    run check_dependency "nonexistent_tool_xyz_12345" "install from example.com"
    assert_failure
    assert_output --partial "nonexistent_tool_xyz_12345 is not installed"
}

@test "init check_dependency succeeds for git" {
    source "$PROJECT_ROOT/lib/common.sh"
    run check_dependency "git" "https://git-scm.com"
    assert_success
}

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------

@test "init --help shows usage" {
    run gsd-ralph init --help
    assert_success
    assert_output --partial "Usage: gsd-ralph init"
}
