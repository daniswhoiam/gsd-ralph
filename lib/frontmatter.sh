#!/bin/bash
# lib/frontmatter.sh -- YAML frontmatter parser for GSD plan files

# Parse YAML frontmatter from a GSD plan file.
# Sets globals: FM_WAVE, FM_DEPENDS_ON, FM_FILES_MODIFIED, FM_PHASE, FM_PLAN, FM_TYPE
# Args: plan_file
# Returns: 0 on success, 1 if file not found or no frontmatter
parse_plan_frontmatter() {
    local plan_file="$1"

    # Reset globals
    FM_WAVE=""
    FM_DEPENDS_ON=""
    FM_FILES_MODIFIED=""
    FM_PHASE=""
    FM_PLAN=""
    FM_TYPE=""

    if [[ ! -f "$plan_file" ]]; then
        print_error "Plan file not found: $plan_file"
        return 1
    fi

    local in_frontmatter=false
    local found_start=false
    local line key value

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Detect frontmatter boundaries
        if [[ "$line" == "---" ]]; then
            if [[ "$found_start" == false ]]; then
                found_start=true
                in_frontmatter=true
                continue
            else
                # End of frontmatter
                break
            fi
        fi

        [[ "$in_frontmatter" == false ]] && continue

        # Skip blank lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Skip YAML list continuation lines (- item format under a key)
        if [[ "$line" =~ ^[[:space:]]+- ]]; then
            # This is a multi-line list item; extract value
            value="${line#*- }"
            value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            # Remove quotes
            value="${value%\"}"
            value="${value#\"}"
            value="${value%\'}"
            value="${value#\'}"
            # Append to the last key's accumulator
            if [[ -n "$_fm_current_key" ]]; then
                case "$_fm_current_key" in
                    depends_on)
                        if [[ -n "$FM_DEPENDS_ON" ]]; then
                            FM_DEPENDS_ON="$FM_DEPENDS_ON $value"
                        else
                            FM_DEPENDS_ON="$value"
                        fi
                        ;;
                    files_modified)
                        if [[ -n "$FM_FILES_MODIFIED" ]]; then
                            FM_FILES_MODIFIED="$FM_FILES_MODIFIED $value"
                        else
                            FM_FILES_MODIFIED="$value"
                        fi
                        ;;
                esac
            fi
            continue
        fi

        # Parse key: value lines
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*(.*) ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            _fm_current_key="$key"

            # Trim whitespace
            value="$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

            # Handle inline YAML arrays: ["a", "b"] or [a, b]
            if [[ "$value" =~ ^\[.*\]$ ]]; then
                value="${value#\[}"
                value="${value%\]}"
                # Parse comma-separated values, strip quotes and whitespace
                local parsed=""
                local IFS=","
                local item
                for item in $value; do
                    item="$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
                    # Remove surrounding quotes
                    item="${item%\"}"
                    item="${item#\"}"
                    item="${item%\'}"
                    item="${item#\'}"
                    if [[ -n "$item" ]]; then
                        if [[ -n "$parsed" ]]; then
                            parsed="$parsed $item"
                        else
                            parsed="$item"
                        fi
                    fi
                done
                value="$parsed"
            else
                # Remove surrounding quotes from scalar values
                value="${value%\"}"
                value="${value#\"}"
                value="${value%\'}"
                value="${value#\'}"
            fi

            # shellcheck disable=SC2034
            case "$key" in
                wave)           FM_WAVE="$value" ;;
                depends_on)     FM_DEPENDS_ON="$value" ;;
                files_modified)
                    # Could be inline array or start of multi-line list
                    if [[ -n "$value" ]]; then
                        FM_FILES_MODIFIED="$value"
                    fi
                    ;;
                phase)          FM_PHASE="$value" ;;
                plan)           FM_PLAN="$value" ;;
                type)           FM_TYPE="$value" ;;
            esac
        fi
    done < "$plan_file"

    unset _fm_current_key

    if [[ "$found_start" == false ]]; then
        print_verbose "No frontmatter found in $(basename "$plan_file")"
        return 1
    fi

    return 0
}
