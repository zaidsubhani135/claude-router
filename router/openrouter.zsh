#!/usr/bin/env zsh
# openrouter.zsh — OpenRouter REST API surface
# No jq parsing beyond decoding responses.  No UI.  No preset business logic.
# Authenticates with ANTHROPIC_AUTH_TOKEN.

# ── Internal helper ──────────────────────────────────────────────────────────

_or_curl() {
    curl --silent --fail \
         --header "Authorization: Bearer ${ANTHROPIC_AUTH_TOKEN}" \
         --header "Content-Type: application/json" \
         "$@"
}

# ── Public functions ──────────────────────────────────────────────────────────

# Download the full OpenRouter model catalogue.
download_models() {
    _or_curl "${OPENROUTER_API}/models"
}

# Download provider endpoint details for a specific model slug.
# Usage: download_endpoints <model-id>
download_endpoints() {
    local model="${1:?download_endpoints requires a model id}"
    _or_curl "${OPENROUTER_API}/models/${model}/endpoints"
}

# Validate that a model id exists in the OpenRouter catalogue.
# Returns 0 if found, 1 if not.
validate_model() {
    local model="${1:?validate_model requires a model id}"
    local response
    response=$(download_endpoints "${model}") || return 1
    print -- "${response}" | jq -e '.data | length > 0' > /dev/null 2>&1
}

create_or_update_preset() {
    local slug="${1:?create_or_update_preset requires a slug}"
    local payload="${2:?create_or_update_preset requires a JSON payload}"

    local response
    response=$(
        _or_curl --request POST \
                 --data "${payload}" \
                 "${OPENROUTER_API}/presets/${slug}/chat/completions"
    ) || return 1

    # Uncomment when debugging:
    # print -u2 -- "${response}"

    return 0
}

# Delete a preset by slug.
# Usage: delete_preset <slug>
delete_preset() {
    local slug="${1:?delete_preset requires a slug}"
    _or_curl --request DELETE "${OPENROUTER_API}/presets/${slug}"
}

# Verify ANTHROPIC_AUTH_TOKEN is accepted by OpenRouter.
verify_api_key() {
    [[ -n "${ANTHROPIC_AUTH_TOKEN}" ]] \
        || { warn "ANTHROPIC_AUTH_TOKEN is not set."; return 1; }

    local response
    response=$(_or_curl "${OPENROUTER_API}/auth/key") \
        || { warn "API key verification request failed."; return 1; }

    print -- "${response}" | grep -q '"data"' \
        || { warn "API key appears invalid."; return 1; }
}
