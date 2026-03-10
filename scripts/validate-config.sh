#!/bin/bash
# scripts/validate-config.sh -- Config validation with strict-with-warnings semantics
# Bash 3.2 compatible (no associative arrays, no ${var,,})
#
# Usage: source this file and call validate_ralph_config <config_file>
# Or run directly: bash scripts/validate-config.sh <config_file>

validate_ralph_config() {
    local config_file="$1"
    local has_warnings=0

    if [ -z "$config_file" ]; then
        echo "WARNING: No config file specified" >&2
        return 0
    fi

    if [ ! -f "$config_file" ]; then
        echo "WARNING: Config file not found: $config_file" >&2
        return 0
    fi

    # Check ralph key exists
    if ! jq -e '.ralph' "$config_file" >/dev/null 2>&1; then
        echo "WARNING: No 'ralph' key in config.json" >&2
        return 0
    fi

    # Validate enabled field: must be true or false (boolean)
    local enabled
    enabled=$(jq -r '.ralph.enabled // "MISSING"' "$config_file")
    if [ "$enabled" != "true" ] && [ "$enabled" != "false" ] && [ "$enabled" != "MISSING" ]; then
        echo "WARNING: ralph.enabled should be true or false, got: $enabled" >&2
        has_warnings=1
    fi

    # Validate max_turns field: must be an integer
    local max_turns
    max_turns=$(jq -r '.ralph.max_turns // "MISSING"' "$config_file")
    if [ "$max_turns" != "MISSING" ]; then
        if ! echo "$max_turns" | grep -qE '^[0-9]+$'; then
            echo "WARNING: ralph.max_turns should be an integer, got: $max_turns" >&2
            has_warnings=1
        fi
    fi

    # Validate permission_tier field: must be one of default, auto-mode, yolo
    local tier
    tier=$(jq -r '.ralph.permission_tier // "MISSING"' "$config_file")
    if [ "$tier" != "MISSING" ] && [ "$tier" != "default" ] && [ "$tier" != "auto-mode" ] && [ "$tier" != "yolo" ]; then
        echo "WARNING: ralph.permission_tier should be default|auto-mode|yolo, got: $tier" >&2
        has_warnings=1
    fi

    # Validate timeout_minutes field: must be a positive integer
    local timeout_min
    timeout_min=$(jq -r '.ralph.timeout_minutes // "MISSING"' "$config_file")
    if [ "$timeout_min" != "MISSING" ]; then
        if ! echo "$timeout_min" | grep -qE '^[0-9]+$'; then
            echo "WARNING: ralph.timeout_minutes should be a positive integer, got: $timeout_min" >&2
            has_warnings=1
        fi
    fi

    # Warn on unknown keys (strict with warnings)
    local known_keys="enabled max_turns permission_tier timeout_minutes"
    local actual_keys
    actual_keys=$(jq -r '.ralph | keys[]' "$config_file" 2>/dev/null)
    local key
    for key in $actual_keys; do
        case " $known_keys " in
            *" $key "*) ;;
            *) echo "WARNING: Unknown ralph config key: $key (typo?)" >&2
               has_warnings=1
               ;;
        esac
    done

    return 0
}

# Allow direct execution for syntax checking
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ -n "$1" ]; then
        validate_ralph_config "$1"
    fi
fi
