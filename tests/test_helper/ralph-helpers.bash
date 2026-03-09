#!/bin/bash
# tests/test_helper/ralph-helpers.bash -- Shared test fixtures for Ralph tests

# Helper: get the real project root (not TEST_TEMP_DIR)
# This is needed when tests check actual project files (e.g., SKILL.md)
get_real_project_root() {
    # Navigate from this file's location to the project root
    # test_helper/ -> tests/ -> project root
    local helper_dir
    helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    echo "$(cd "$helper_dir/../.." && pwd)"
}

# Helper: create a mock config.json with customizable ralph key fields
# Usage: create_ralph_config [enabled] [max_turns] [permission_tier]
# All args optional; omit to use defaults
create_ralph_config() {
    local enabled="${1:-true}"
    local max_turns="${2:-50}"
    local permission_tier="${3:-default}"

    mkdir -p "$TEST_TEMP_DIR/.planning"
    cat > "$TEST_TEMP_DIR/.planning/config.json" <<EOF
{
  "mode": "yolo",
  "parallelization": true,
  "commit_docs": true,
  "ralph": {
    "enabled": $enabled,
    "max_turns": $max_turns,
    "permission_tier": "$permission_tier"
  }
}
EOF
}

# Helper: create a mock config.json from raw JSON string
# Usage: create_ralph_config_raw '{"ralph": {"enabled": true}}'
create_ralph_config_raw() {
    local json_content="$1"
    mkdir -p "$TEST_TEMP_DIR/.planning"
    echo "$json_content" > "$TEST_TEMP_DIR/.planning/config.json"
}

# Helper: create a mock STATE.md in TEST_TEMP_DIR
create_mock_state() {
    mkdir -p "$TEST_TEMP_DIR/.planning"
    cat > "$TEST_TEMP_DIR/.planning/STATE.md" <<'EOF'
---
gsd_state_version: 1.0
status: executing
---

# Project State

## Current Position

Phase: 10 of 12
Plan: 1 of 2
Status: Executing
EOF
}
