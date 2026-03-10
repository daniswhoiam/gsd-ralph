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

# Helper: create a mock `claude` executable in PATH for testing
# Usage: create_mock_claude_command [exit_code] [output]
create_mock_claude_command() {
    local exit_code="${1:-0}"
    local output="${2:-{\"type\":\"result\",\"result\":\"done\",\"num_turns\":5}}"
    mkdir -p "$TEST_TEMP_DIR/bin"
    cat > "$TEST_TEMP_DIR/bin/claude" <<MOCKEOF
#!/bin/bash
echo '$output'
exit $exit_code
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/bin/claude"
    export PATH="$TEST_TEMP_DIR/bin:$PATH"
}

# Helper: create a temp context file for testing
# Usage: create_context_file [content]
create_context_file() {
    local content="${1:-# Test Context}"
    echo "$content" > "$TEST_TEMP_DIR/context.md"
}

# Helper: create a mock STATE.md with configurable phase, plan, and status
# Usage: create_mock_state_advanced <phase_number> <plan_number> <status>
# Example: create_mock_state_advanced 11 2 "Executing"
create_mock_state_advanced() {
    local phase_number="${1:-10}"
    local plan_number="${2:-1}"
    local status="${3:-Executing}"
    local total_phases="${4:-12}"

    mkdir -p "$TEST_TEMP_DIR/.planning"
    cat > "$TEST_TEMP_DIR/.planning/STATE.md" <<EOF
---
gsd_state_version: 1.0
status: executing
---

# Project State

## Current Position

Phase: ${phase_number} of ${total_phases}
Plan: ${plan_number} of 2
Status: ${status}
EOF
}

# Helper: create a mock assemble-context.sh script
# Usage: create_mock_assemble_context [exit_code]
# The mock script writes predictable context content to the output file argument
create_mock_assemble_context() {
    local exit_code="${1:-0}"
    mkdir -p "$TEST_TEMP_DIR/scripts"
    cat > "$TEST_TEMP_DIR/scripts/assemble-context.sh" <<MOCKEOF
#!/bin/bash
# Mock assemble-context.sh for testing
OUTPUT_FILE="\$1"
if [ -z "\$OUTPUT_FILE" ]; then
    echo "ERROR: No output file specified" >&2
    exit 1
fi
echo "# Mock assembled context" > "\$OUTPUT_FILE"
echo "# STATE.md content would go here" >> "\$OUTPUT_FILE"
exit ${exit_code}
MOCKEOF
    chmod +x "$TEST_TEMP_DIR/scripts/assemble-context.sh"
}

# Helper: create a .ralph/.stop sentinel file for graceful stop testing
# Usage: create_mock_stop_file
create_mock_stop_file() {
    mkdir -p "$TEST_TEMP_DIR/.ralph"
    touch "$TEST_TEMP_DIR/.ralph/.stop"
}

# Helper: create a mock audit log file with optional content
# Usage: create_mock_audit_log [content]
# If content is provided, it's written to the audit log; otherwise file is empty
create_mock_audit_log() {
    local content="${1:-}"
    mkdir -p "$TEST_TEMP_DIR/.ralph"
    if [ -n "$content" ]; then
        echo "$content" > "$TEST_TEMP_DIR/.ralph/audit.log"
    else
        : > "$TEST_TEMP_DIR/.ralph/audit.log"
    fi
}

# Helper: create a mock .claude/settings.local.json in TEST_TEMP_DIR
# Usage: create_mock_settings_local [content]
# Default content: {"permissions":{"allow":[]}}
create_mock_settings_local() {
    local content="${1:-{\"permissions\":{\"allow\":[]}}}"
    mkdir -p "$TEST_TEMP_DIR/.claude"
    echo "$content" > "$TEST_TEMP_DIR/.claude/settings.local.json"
}
