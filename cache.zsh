#!/usr/bin/env zsh
# cache.zsh — cache lifecycle management
# No UI, no preset logic, no networking (delegates to openrouter.zsh).

# ── Predicates ─────────────────────────────────────────────────────────────

# Return 0 if the cache file and its timestamp file both exist.
cache_exists() {
    [[ -f "${CACHE_FILE}" && -f "${CACHE_TIMESTAMP}" ]]
}

# Print the age of the cache in seconds, or a large number if absent.
cache_age() {
    if [[ ! -f "${CACHE_TIMESTAMP}" ]]; then
        print -- 999999
        return
    fi
    local stored
    stored=$(< "${CACHE_TIMESTAMP}")
    print $(( $(timestamp) - stored ))
}

# Return 0 if the cache exists and is younger than CACHE_TTL seconds.
cache_valid() {
    cache_exists || return 1
    (( $(cache_age) < CACHE_TTL ))
}

# ── I/O ────────────────────────────────────────────────────────────────────

# Print the raw JSON content of the cache to stdout.
load_cache() {
    cat "${CACHE_FILE}"
}

# Write JSON (from stdin or first argument) to the cache.
save_cache() {
    mkdir -p "${CACHE_DIR}"
    if [[ $# -gt 0 ]]; then
        print -- "${1}" > "${CACHE_FILE}"
    else
        cat > "${CACHE_FILE}"
    fi
    timestamp > "${CACHE_TIMESTAMP}"
}

# Force a fresh download and persist it.
# Delegates the actual HTTP call to download_models() from openrouter.zsh.
refresh_cache() {
    info "Refreshing model cache…"
    local payload
    payload=$(download_models) \
        || { die "Failed to download model list from OpenRouter."; return 1; }
    save_cache "${payload}"
}
