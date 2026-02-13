#!/bin/bash
# lib/config.sh -- Project detection and configuration for gsd-ralph

# Detect project type from marker files in the given directory.
# Sets global variables: DETECTED_LANG, DETECTED_TEST_CMD,
#   DETECTED_BUILD_CMD, DETECTED_PKG_MANAGER
# Args: [project_dir] (defaults to ".")
detect_project_type() {
    local project_dir="${1:-.}"
    local lang="" test_cmd="" build_cmd="" pkg_manager=""

    # Check marker files in priority order
    if [[ -f "$project_dir/package.json" ]]; then
        lang="javascript"
        pkg_manager="npm"
        # Check for typescript
        if [[ -f "$project_dir/tsconfig.json" ]]; then
            lang="typescript"
        fi
        # Detect test/build commands from package.json
        if command -v jq >/dev/null 2>&1; then
            local scripts_test
            scripts_test=$(jq -r '.scripts.test // empty' "$project_dir/package.json" 2>/dev/null)
            if [[ -n "$scripts_test" ]]; then
                test_cmd="npm test"
            fi
            local scripts_build
            scripts_build=$(jq -r '.scripts.build // empty' "$project_dir/package.json" 2>/dev/null)
            if [[ -n "$scripts_build" ]]; then
                build_cmd="npm run build"
            fi
        fi
        # Detect package manager from lockfiles
        if [[ -f "$project_dir/pnpm-lock.yaml" ]]; then
            pkg_manager="pnpm"
            test_cmd="${test_cmd/npm/pnpm}"
            build_cmd="${build_cmd/npm/pnpm}"
        elif [[ -f "$project_dir/yarn.lock" ]]; then
            pkg_manager="yarn"
            test_cmd="${test_cmd/npm/yarn}"
            build_cmd="${build_cmd/npm/yarn}"
        elif [[ -f "$project_dir/bun.lockb" ]] || [[ -f "$project_dir/bun.lock" ]]; then
            pkg_manager="bun"
            test_cmd="${test_cmd/npm/bun}"
            build_cmd="${build_cmd/npm/bun}"
        fi

    elif [[ -f "$project_dir/Cargo.toml" ]]; then
        lang="rust"
        test_cmd="cargo test"
        build_cmd="cargo build"
        pkg_manager="cargo"

    elif [[ -f "$project_dir/go.mod" ]]; then
        lang="go"
        test_cmd="go test ./..."
        build_cmd="go build ./..."
        pkg_manager="go"

    elif [[ -f "$project_dir/pyproject.toml" ]]; then
        lang="python"
        test_cmd="pytest"
        build_cmd=""
        pkg_manager="pip"
        # Detect poetry/uv
        if [[ -f "$project_dir/poetry.lock" ]]; then
            pkg_manager="poetry"
            test_cmd="poetry run pytest"
        elif [[ -f "$project_dir/uv.lock" ]]; then
            pkg_manager="uv"
            test_cmd="uv run pytest"
        fi

    elif [[ -f "$project_dir/requirements.txt" ]] || [[ -f "$project_dir/setup.py" ]]; then
        lang="python"
        test_cmd="python -m pytest"
        build_cmd=""
        pkg_manager="pip"

    elif [[ -f "$project_dir/Gemfile" ]]; then
        lang="ruby"
        test_cmd="bundle exec rspec"
        build_cmd=""
        pkg_manager="bundler"

    elif [[ -f "$project_dir/mix.exs" ]]; then
        lang="elixir"
        test_cmd="mix test"
        build_cmd="mix compile"
        pkg_manager="mix"

    elif [[ -f "$project_dir/build.gradle" ]] || [[ -f "$project_dir/build.gradle.kts" ]]; then
        lang="java"
        test_cmd="./gradlew test"
        build_cmd="./gradlew build"
        pkg_manager="gradle"

    elif [[ -f "$project_dir/pom.xml" ]]; then
        lang="java"
        test_cmd="mvn test"
        build_cmd="mvn package"
        pkg_manager="maven"
    fi

    # Export results via global variables (bash 3.2 compatible -- no nameref)
    # shellcheck disable=SC2034
    DETECTED_LANG="${lang:-unknown}"
    # shellcheck disable=SC2034
    DETECTED_TEST_CMD="${test_cmd:-}"
    # shellcheck disable=SC2034
    DETECTED_BUILD_CMD="${build_cmd:-}"
    # shellcheck disable=SC2034
    DETECTED_PKG_MANAGER="${pkg_manager:-}"
}
