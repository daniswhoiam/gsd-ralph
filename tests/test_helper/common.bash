#!/bin/bash
# tests/test_helper/common.bash -- Shared test setup for bats tests

_common_setup() {
    # Resolve project root from test_helper/ -> tests/ -> project root
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    PATH="$PROJECT_ROOT/bin:$PATH"

    # Load bats libraries using absolute paths
    load "${PROJECT_ROOT}/tests/test_helper/bats-support/load"
    load "${PROJECT_ROOT}/tests/test_helper/bats-assert/load"
    load "${PROJECT_ROOT}/tests/test_helper/bats-file/load"

    # Create temp directory for test isolation
    TEST_TEMP_DIR="$(mktemp -d)"
    cd "$TEST_TEMP_DIR" || return 1
}

_common_teardown() {
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
