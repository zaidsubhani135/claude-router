#!/usr/bin/env zsh
# utils.zsh — generic helpers, no networking, no business logic

# Print an error and return 1.
# Never calls exit — router_engine.zsh is sourced, so exit would kill the
# user's shell.  Callers are responsible for propagating the return value.
die() {
    print -u2 -- "❌ ${*}"
    return 1
}

# Print a yellow warning to stderr.
warn() {
    print -u2 -- "⚠️  ${*}"
}

# Print a blue informational line to stderr.
info() {
    print -u2 -- "ℹ️  ${*}"
}

# Show an animated spinner while a background job runs.
# Usage: spinner <pid> [label]
spinner() {
    local pid="${1}"
    local label="${2:-Working…}"
    local -a frames=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
    local i=0

    while kill -0 "${pid}" 2>/dev/null; do
        printf '\r%s %s ' "${frames[$(( i % ${#frames[@]} + 1 ))]}" "${label}" >&2
        (( i++ ))
        sleep 0.1
    done
    printf '\r%*s\r' "$(( ${#label} + 4 ))" '' >&2   # erase the line
}

# Return a Unix timestamp (seconds since epoch).
timestamp() {
    date +%s
}

# Produce a slug safe for use in OpenRouter preset names.
# Lowercases input, replaces forward-slashes with hyphens, then collapses any
# remaining run of non-alphanumeric characters into a single hyphen and strips
# a trailing hyphen.
# Usage: sanitize_slug <string>
# Example: sanitize_slug "deepseek/deepseek-v4-flash"
#          → "deepseek-deepseek-v4-flash"
sanitize_slug() {
    local raw="${1}"
    print -- "${raw:l}" | tr '/' '-' | tr -cs 'a-z0-9-' '-' | sed 's/-$//'
}
