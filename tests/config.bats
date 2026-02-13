#!/usr/bin/env bats
# tests/config.bats -- Unit tests for lib/config.sh

setup() {
    load 'test_helper/common'
    _common_setup

    # Source config.sh (and its dependency common.sh) for unit testing
    VERBOSE=false
    source "$PROJECT_ROOT/lib/common.sh"
    source "$PROJECT_ROOT/lib/config.sh"
}

teardown() {
    _common_teardown
}

@test "detect_project_type with package.json detects javascript" {
    echo '{}' > package.json
    detect_project_type "."
    [[ "$DETECTED_LANG" == "javascript" ]]
}

@test "detect_project_type with package.json + tsconfig.json detects typescript" {
    echo '{}' > package.json
    touch tsconfig.json
    detect_project_type "."
    [[ "$DETECTED_LANG" == "typescript" ]]
}

@test "detect_project_type with Cargo.toml detects rust" {
    touch Cargo.toml
    detect_project_type "."
    [[ "$DETECTED_LANG" == "rust" ]]
}

@test "detect_project_type with go.mod detects go" {
    echo 'module example.com/test' > go.mod
    detect_project_type "."
    [[ "$DETECTED_LANG" == "go" ]]
}

@test "detect_project_type with pyproject.toml detects python" {
    touch pyproject.toml
    detect_project_type "."
    [[ "$DETECTED_LANG" == "python" ]]
}

@test "detect_project_type with no marker files detects unknown" {
    detect_project_type "."
    [[ "$DETECTED_LANG" == "unknown" ]]
}

@test "detect_project_type reads test command from package.json scripts.test" {
    echo '{"scripts":{"test":"vitest"}}' > package.json
    detect_project_type "."
    [[ "$DETECTED_TEST_CMD" == "npm test" ]]
}

@test "detect_project_type detects pnpm from pnpm-lock.yaml" {
    echo '{"scripts":{"test":"vitest"}}' > package.json
    touch pnpm-lock.yaml
    detect_project_type "."
    [[ "$DETECTED_PKG_MANAGER" == "pnpm" ]]
    [[ "$DETECTED_TEST_CMD" == "pnpm test" ]]
}
