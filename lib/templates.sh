#!/bin/bash
# lib/templates.sh -- Template rendering with {{VARIABLE}} substitution

# Render a template file by substituting {{KEY}} placeholders with values.
# Args: template_path, output_path, KEY=VALUE pairs...
render_template() {
    local template="$1"
    local output="$2"
    shift 2
    # Remaining args are KEY=VALUE pairs

    if [[ ! -f "$template" ]]; then
        die "Template not found: $template"
    fi

    local content
    content=$(<"$template")

    local pair key value
    for pair in "$@"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        content="${content//\{\{${key}\}\}/${value}}"
    done

    printf '%s\n' "$content" > "$output"
}
