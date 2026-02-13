#!/bin/bash
# tests/test_helper/common.bash -- Shared test setup

_common_setup() {
    # Load bats libraries
    load 'bats-support/load'
    load 'bats-assert/load'
    load 'bats-file/load'

    # Get the containing directory of this file (test_helper/)
    # then resolve to the project root
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    PATH="$PROJECT_ROOT/bin:$PATH"

    # Create temp directory for test isolation
    TEST_TEMP_DIR="$(mktemp -d)"
    cd "$TEST_TEMP_DIR" || return 1
}

_common_teardown() {
    # Clean up temp directory
    if [[ -d "${TEST_TEMP_DIR:-}" ]]; then
        rm -rf "$TEST_TEMP_DIR"
    fi
}

# Helper: create a minimal git repo for testing
create_test_repo() {
    git init . >/dev/null 2>&1
    git commit --allow-empty -m "Initial commit" >/dev/null 2>&1
}

# Helper: create a minimal GSD planning structure
create_gsd_structure() {
    mkdir -p .planning/phases
    cat > .planning/ROADMAP.md <<'EOF'
# Roadmap
- [ ] **Phase 1: Test Phase**
EOF
    cat > .planning/STATE.md <<'EOF'
# Project State
## Current Position
Phase: 1
EOF
}
