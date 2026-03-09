#!/usr/bin/env bats
# tests/ralph-config.bats -- Tests for Ralph config schema validation

setup() {
    load 'test_helper/common'
    load 'test_helper/ralph-helpers'
    _common_setup
    REAL_PROJECT_ROOT="$(get_real_project_root)"

    # Source the validation script
    source "$REAL_PROJECT_ROOT/scripts/validate-config.sh"
}

teardown() {
    _common_teardown
}

# --- Tests for actual config.json in project ---

@test "config.json has ralph key with enabled, max_turns, permission_tier fields" {
    local config="$REAL_PROJECT_ROOT/.planning/config.json"
    run jq -e '.ralph.enabled' "$config"
    assert_success

    run jq -e '.ralph.max_turns' "$config"
    assert_success

    run jq -e '.ralph.permission_tier' "$config"
    assert_success
}

@test "ralph.max_turns defaults to 50" {
    local config="$REAL_PROJECT_ROOT/.planning/config.json"
    run jq -r '.ralph.max_turns' "$config"
    assert_success
    assert_output "50"
}

@test "ralph.permission_tier is one of: default, auto-mode, yolo" {
    local config="$REAL_PROJECT_ROOT/.planning/config.json"
    local tier
    tier=$(jq -r '.ralph.permission_tier' "$config")
    [[ "$tier" = "default" || "$tier" = "auto-mode" || "$tier" = "yolo" ]]
}

# --- Tests for validate_ralph_config function ---

@test "validate_ralph_config accepts valid config with all 3 fields" {
    create_ralph_config true 50 "default"
    run validate_ralph_config "$TEST_TEMP_DIR/.planning/config.json"
    assert_success
    refute_output --partial "WARNING"
}

@test "validate_ralph_config warns on non-boolean enabled value" {
    create_ralph_config_raw '{"ralph": {"enabled": "yes", "max_turns": 50, "permission_tier": "default"}}'
    run validate_ralph_config "$TEST_TEMP_DIR/.planning/config.json"
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial "enabled"
}

@test "validate_ralph_config warns on non-integer max_turns" {
    create_ralph_config_raw '{"ralph": {"enabled": true, "max_turns": "fifty", "permission_tier": "default"}}'
    run validate_ralph_config "$TEST_TEMP_DIR/.planning/config.json"
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial "max_turns"
}

@test "validate_ralph_config warns on invalid permission_tier value" {
    create_ralph_config_raw '{"ralph": {"enabled": true, "max_turns": 50, "permission_tier": "superuser"}}'
    run validate_ralph_config "$TEST_TEMP_DIR/.planning/config.json"
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial "permission_tier"
}

@test "validate_ralph_config warns on unknown keys (strict with warnings)" {
    create_ralph_config_raw '{"ralph": {"enabled": true, "max_turns": 50, "permission_tier": "default", "unknown_field": "value"}}'
    run validate_ralph_config "$TEST_TEMP_DIR/.planning/config.json"
    assert_success
    assert_output --partial "WARNING"
    assert_output --partial "unknown_field"
}

@test "validate_ralph_config succeeds when ralph key is missing (not an error)" {
    create_ralph_config_raw '{"mode": "yolo"}'
    run validate_ralph_config "$TEST_TEMP_DIR/.planning/config.json"
    assert_success
    # Should warn but not fail
    assert_output --partial "WARNING"
}
