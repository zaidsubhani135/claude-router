#!/usr/bin/env zsh
# router_engine.zsh — main orchestrator
# The only file that braining and superpowers source.
# Defines one public function: claude_router
# All business logic lives here; modules handle one concern each.

# ── Bootstrap ─────────────────────────────────────────────────────────────────

# ${(%):-%x} expands to the path of the file currently being parsed — unlike
# $0, it stays accurate when this file is sourced rather than executed.
_ROUTER_DIR="${${(%):-%x}:A:h}"

source "${_ROUTER_DIR}/config.zsh"
source "${_ROUTER_DIR}/utils.zsh"
source "${_ROUTER_DIR}/cache.zsh"
source "${_ROUTER_DIR}/openrouter.zsh"
source "${_ROUTER_DIR}/preset.zsh"
source "${_ROUTER_DIR}/backup.zsh"
source "${_ROUTER_DIR}/ui.zsh"

# ══════════════════════════════════════════════════════════════════════════════
# Public entry point
# ══════════════════════════════════════════════════════════════════════════════

claude_router() {
    _router_validate_environment || return 1
    _router_select_model         || return 1
    _router_select_routing_mode  || return 1

    case "${_ROUTER_MODE}" in
        direct) _router_run_direct ;;
        preset) _router_run_preset || return 1 ;;
    esac
}

# ══════════════════════════════════════════════════════════════════════════════
# Internals — prefixed _router_, not part of the public API
# ══════════════════════════════════════════════════════════════════════════════

# ── Step 1 — Validate environment (no network) ────────────────────────────────

_router_validate_environment() {
    # ── Dependency check ──────────────────────────────────────────────────────
    local missing=()
    command -v curl > /dev/null 2>&1 || missing+=( 'curl' )
    command -v jq   > /dev/null 2>&1 || missing+=( 'jq' )

    if (( ${#missing[@]} > 0 )); then
        die "Missing required dependencies: ${(j:, :)missing}
  Install them with your package manager, e.g.:
    brew install ${(j: :)missing}
    apt-get install ${(j: :)missing}"
        return 1
    fi

    # ── Environment variables ─────────────────────────────────────────────────
    [[ -n "${ANTHROPIC_BASE_URL}" ]] \
        || { die "ANTHROPIC_BASE_URL is not set."; return 1; }
    [[ -n "${ANTHROPIC_AUTH_TOKEN}" ]] \
        || { die "ANTHROPIC_AUTH_TOKEN is not set."; return 1; }
    [[ -n "${CLAUDE_ROUTER_MODEL}" ]] \
        || { die "CLAUDE_ROUTER_MODEL is not set. The calling script must export it."; return 1; }
}

# ── Step 2 — Model selection ──────────────────────────────────────────────────
# If CLAUDE_ROUTER_MODEL is the sentinel "__pick__", run the interactive picker.
# Otherwise honour the pre-set value and skip straight to routing mode.

_router_select_model() {
    if [[ "${CLAUDE_ROUTER_MODEL}" != '__pick__' ]]; then
        _ROUTER_MODEL="${CLAUDE_ROUTER_MODEL}"
        return 0
    fi

    local -a default_models=( "${(@f)${CLAUDE_ROUTER_DEFAULT_MODELS}}" )
    local -a user_models=( "${(@f)$(_router_load_user_models)}" )

    local -a all_models=( "${default_models[@]}" )
    local m
    for m in "${user_models[@]}"; do
        [[ -n "${m}" ]] || continue
        (( ${all_models[(Ie)${m}]} )) || all_models+=( "${m}" )
    done

    while true; do
        local selection
        selection=$(prompt_model_selection "${all_models[@]}") || return 1

        case "${selection}" in
            __custom__)
                _router_handle_custom_model all_models && return 0
                continue
                ;;
            __manage__)
                _router_handle_manage_menu || true
                # Rebuild list after potential deletions.
                user_models=( "${(@f)$(_router_load_user_models)}" )
                all_models=( "${default_models[@]}" )
                for m in "${user_models[@]}"; do
                    [[ -n "${m}" ]] || continue
                    (( ${all_models[(Ie)${m}]} )) || all_models+=( "${m}" )
                done
                continue
                ;;
            *)
                _ROUTER_MODEL="${selection}"
                return 0
                ;;
        esac
    done
}

# Handle custom model entry: validate, optionally save, set _ROUTER_MODEL.
# Takes a nameref to the all_models array so it can append on save.
_router_handle_custom_model() {
    local -n _hcm_models="${1}"

    while true; do
        local candidate
        candidate=$(prompt_custom_model)
        [[ -n "${candidate}" ]] || return 1   # blank = back to picker

        info "Validating \"${candidate}\"…"
        if ! validate_model "${candidate}"; then
            show_error "Model \"${candidate}\" not found on OpenRouter."
            continue
        fi

        if prompt_save_model "${candidate}"; then
            _router_append_user_model "${candidate}"
            _hcm_models+=( "${candidate}" )
        fi

        _ROUTER_MODEL="${candidate}"
        return 0
    done
}

# Manage saved models: delete entries until the user goes back.
_router_handle_manage_menu() {
    while true; do
        local -a saved=( "${(@f)$(_router_load_user_models)}" )
        local choice
        choice=$(show_manage_menu "${saved[@]}") || return 0
        [[ "${choice}" == '__back__' ]] && return 0
        _router_delete_user_model "${choice}"
        info "Removed \"${choice}\"."
    done
}

# ── Step 3 — Routing mode ─────────────────────────────────────────────────────
# Precedence: CLAUDE_ROUTER_MODE env var → interactive prompt

_router_select_routing_mode() {
    if [[ -n "${CLAUDE_ROUTER_MODE}" ]]; then
        case "${CLAUDE_ROUTER_MODE}" in
            direct|preset) _ROUTER_MODE="${CLAUDE_ROUTER_MODE}"; return 0 ;;
            *) die "Unknown CLAUDE_ROUTER_MODE: ${CLAUDE_ROUTER_MODE}"; return 1 ;;
        esac
    fi
    _ROUTER_MODE=$(prompt_routing_mode) || return 1
}

# ── Direct mode ───────────────────────────────────────────────────────────────

_router_run_direct() {
    export ANTHROPIC_MODEL="${_ROUTER_MODEL}"
    show_success "${_ROUTER_MODEL}"
}

# ── Preset mode ───────────────────────────────────────────────────────────────
# Entry point for the model-scoped preset manager.

_router_run_preset() {
    # Ensure endpoint data is fresh before entering the menu loop.
    _router_ensure_providers || return 1

    local presets_json=""
    local action=""
    local verb=""
    local ref=""
    
    while true; do
        presets_json=$(preset_load_all "${_ROUTER_MODEL}")
    
        action=$(show_preset_menu "${_ROUTER_MODEL}" "${presets_json}") || return 1
    
        verb="${action%%:*}"
        ref="${action#*:}"

        case "${verb}" in
            launch)      _router_preset_launch "${ref}"  && return 0 ;;
            __create__)  _router_preset_create           || true ;;
            edit)        _router_preset_edit   "${ref}"  || true ;;
            rename)      _router_preset_rename "${ref}"  || true ;;
            delete)      _router_preset_delete "${ref}"  || true ;;
            __import__)  _router_preset_import           || true ;;
            __export__)  _router_preset_export           || true ;;
            __back__)    return 0 ;;
        
            *)
                print -u2 "BUG: unexpected preset action [${verb}]"
                return 1
                ;;
        esac
    done
}

# ── Endpoint cache ─────────────────────────────────────────────────────────────

# Populate _ROUTER_PROVIDERS for _ROUTER_MODEL from cache or API.
_router_ensure_providers() {
    local endpoint_cache_dir="${CACHE_DIR}/endpoints"
    local safe="${_ROUTER_MODEL//\//-}"
    local ecache="${endpoint_cache_dir}/${safe}.json"
    local ets="${ecache}.timestamp"
    local json

    if [[ -f "${ecache}" && -f "${ets}" ]] \
        && (( $(timestamp) - $(< "${ets}") < CACHE_TTL )); then
        info "Using cached endpoint data for ${_ROUTER_MODEL}."
        json=$(< "${ecache}")
    else
        # Only verify key and hit network when cache is stale.
        if ! cache_valid; then
            verify_api_key || return 1
            refresh_cache  || return 1
        fi
        info "Fetching endpoints for ${_ROUTER_MODEL}…"
        json=$(download_endpoints "${_ROUTER_MODEL}") \
            || { die "Could not fetch endpoints for ${_ROUTER_MODEL}."; return 1; }
        mkdir -p "${endpoint_cache_dir}"
        print -- "${json}" > "${ecache}"
        timestamp > "${ets}"
    fi

    local providers_raw
    providers_raw=$(
      print -- "${json}" |
      jq -r '
        .data?.endpoints? // []
        | map(.provider_name // empty)
        | unique
        | .[]
      '
    )
    _ROUTER_PROVIDERS=()
    local _p
    while IFS= read -r _p; do
        [[ -n "${_p}" ]] && _ROUTER_PROVIDERS+=( "${_p}" )
    done <<< "${providers_raw}"

    (( ${#_ROUTER_PROVIDERS[@]} > 0 )) \
        || { die "No providers found for ${_ROUTER_MODEL}."; return 1; }
}

# ── Provider ordering ─────────────────────────────────────────────────────────
# Populates _ROUTER_ORDERED_PROVIDERS.
# Precedence: CLAUDE_ROUTER_PROFILE → interactive prompt (no saved-order in
# preset mode because each named preset owns its own provider list).

_router_choose_provider_order() {
    if [[ -n "${CLAUDE_ROUTER_PROFILE}" ]]; then
        case "${CLAUDE_ROUTER_PROFILE}" in
            balanced)
                _ROUTER_ORDERED_PROVIDERS=( "${_ROUTER_PROVIDERS[@]}" )
                return 0
                ;;
            *)
                die "Unknown CLAUDE_ROUTER_PROFILE: ${CLAUDE_ROUTER_PROFILE}"
                return 1
                ;;
        esac
    fi

    print_header "${_ROUTER_MODEL}"
    show_provider_table "${_ROUTER_PROVIDERS[@]}"
    _ROUTER_ORDERED_PROVIDERS=( "${(@f)$(prompt_provider_order "${_ROUTER_PROVIDERS[@]}")}" ) \
        || return 1
}

# ── Preset actions ────────────────────────────────────────────────────────────

# Launch: export ANTHROPIC_MODEL and return success to break the menu loop.
_router_preset_launch() {
    local slug="${1:?_router_preset_launch requires a slug}"
    export ANTHROPIC_MODEL="@preset/${slug}"
    show_success "@preset/${slug}"
}

# Create: choose providers → name → push to OpenRouter → save metadata.
_router_preset_create() {
    _router_choose_provider_order || return 1

    # Default name: "Preset N+1"
    local presets_json count default_name
    presets_json=$(preset_load_all "${_ROUTER_MODEL}")
    count=$(print -- "${presets_json}" | jq 'length')
    default_name="Preset $(( count + 1 ))"

    local name
    name=$(prompt_preset_name "${default_name}")
    [[ -n "${name}" ]] || name="${default_name}"

    local slug providers_json payload
    slug=$(preset_slug "${_ROUTER_MODEL}" "${name}")
    providers_json=$(providers_array_from_names "${_ROUTER_ORDERED_PROVIDERS[@]}")
    payload=$(preset_payload "${slug}" "${_ROUTER_MODEL}" "${providers_json}")

    create_or_update_preset "${slug}" "${payload}" \
        || { die "Could not create preset on OpenRouter."; return 1; }

    preset_upsert "${_ROUTER_MODEL}" "${slug}" "${name}" "${providers_json}"
    info "Preset \"${name}\" created."
}

# Edit: re-run provider ordering for an existing preset, push update.
_router_preset_edit() {
    local slug="${1:?_router_preset_edit requires a slug}"

    local presets_json name
    presets_json=$(preset_load_all "${_ROUTER_MODEL}")
    name=$(print -- "${presets_json}" \
        | jq -r --arg s "${slug}" '.[] | select(.slug==$s) | .name')

    [[ -n "${name}" ]] || { die "Preset \"${slug}\" not found."; return 1; }

    info "Editing \"${name}\" — choose new provider order."
    _router_choose_provider_order || return 1

    local providers_json payload
    providers_json=$(providers_array_from_names "${_ROUTER_ORDERED_PROVIDERS[@]}")
    payload=$(preset_payload "${slug}" "${_ROUTER_MODEL}" "${providers_json}")

    create_or_update_preset "${slug}" "${payload}" \
        || { die "Could not update preset on OpenRouter."; return 1; }

    preset_upsert "${_ROUTER_MODEL}" "${slug}" "${name}" "${providers_json}"
    info "Preset \"${name}\" updated."
}

# Rename: new name → optionally new slug → update OpenRouter + metadata.
_router_preset_rename() {
    local old_slug="${1:?_router_preset_rename requires a slug}"

    local presets_json old_name
    presets_json=$(preset_load_all "${_ROUTER_MODEL}")
    old_name=$(print -- "${presets_json}" \
        | jq -r --arg s "${old_slug}" '.[] | select(.slug==$s) | .name')

    [[ -n "${old_name}" ]] || { die "Preset \"${old_slug}\" not found."; return 1; }

    local result
    result=$(prompt_rename_preset "${old_name}")
    [[ "${result}" == '__cancel__' ]] && return 0

    local new_name="${result#confirmed:}"
    local new_slug
    new_slug=$(preset_slug "${_ROUTER_MODEL}" "${new_name}")

    # If the slug changes, delete the old OpenRouter preset first.
    if [[ "${new_slug}" != "${old_slug}" ]]; then
        delete_preset "${old_slug}" 2>/dev/null || true
    fi

    # Fetch existing providers from metadata as compact JSON (not re-encoded string).
    local providers_json payload
    providers_json=$(print -- "${presets_json}" \
        | jq -c --arg s "${old_slug}" '.[] | select(.slug==$s) | .providers')
    payload=$(preset_payload "${new_slug}" "${_ROUTER_MODEL}" "${providers_json}")

    create_or_update_preset "${new_slug}" "${payload}" \
        || { die "Could not update preset on OpenRouter."; return 1; }

    preset_rename_local "${_ROUTER_MODEL}" "${old_slug}" "${new_name}" "${new_slug}"
    info "Preset renamed to \"${new_name}\"."
}

# Delete: confirm → remove from OpenRouter → remove from metadata.
_router_preset_delete() {
    local slug="${1:?_router_preset_delete requires a slug}"

    local presets_json name
    presets_json=$(preset_load_all "${_ROUTER_MODEL}")
    name=$(print -- "${presets_json}" \
        | jq -r --arg s "${slug}" '.[] | select(.slug==$s) | .name')

    [[ -n "${name}" ]] || { die "Preset \"${slug}\" not found."; return 1; }

    prompt_delete_preset "${name}" "${_ROUTER_MODEL}" || return 0

    delete_preset "${slug}" 2>/dev/null || warn "Could not delete preset on OpenRouter (may already be gone)."
    preset_remove "${_ROUTER_MODEL}" "${slug}"
    info "Preset \"${name}\" deleted."
}

# ── Backup actions ────────────────────────────────────────────────────────────

_router_preset_export() {
    local default_path="./claude-router-backup-$(date +%Y-%m-%d).json"
    printf '  Output file [%s]: ' "${default_path}" >&2
    local path
    read -r path
    [[ -n "${path}" ]] || path="${default_path}"
    backup_export "${path}"
}

_router_preset_import() {
    local path
    path=$(prompt_import_file)
    [[ -n "${path}" ]] || return 0

    local mode
    mode=$(prompt_import_mode) || return 1

    printf '  Import "%s" (%s)? (y/N) ' "${path}" "${mode}" >&2
    local confirm
    read -r confirm
    [[ "${confirm:l}" == 'y' ]] || return 0

    backup_import "${path}" "${mode}"
}

# ══════════════════════════════════════════════════════════════════════════════
# User model file helpers
# ══════════════════════════════════════════════════════════════════════════════

_router_load_user_models() {
    [[ -f "${USER_MODELS_FILE}" ]] || return 0
    grep -v '^\s*#' "${USER_MODELS_FILE}" | grep -v '^\s*$'
}

_router_append_user_model() {
    local model="${1:?_router_append_user_model requires a model}"
    mkdir -p "${CONFIG_DIR}"
    if [[ -f "${USER_MODELS_FILE}" ]] \
        && grep -qxF "${model}" "${USER_MODELS_FILE}" 2>/dev/null; then
        info "\"${model}\" is already saved."
        return 0
    fi
    print -- "${model}" >> "${USER_MODELS_FILE}"
    info "Saved \"${model}\"."
}

_router_delete_user_model() {
    local model="${1:?_router_delete_user_model requires a model}"
    [[ -f "${USER_MODELS_FILE}" ]] || return 0
    local tmp
    tmp=$(mktemp) || { warn "Could not create temp file."; return 1; }
    grep -vxF "${model}" "${USER_MODELS_FILE}" > "${tmp}" \
        && mv "${tmp}" "${USER_MODELS_FILE}"
}
