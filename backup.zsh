#!/usr/bin/env zsh
# backup.zsh — export and import backup files
# No UI (delegates to ui.zsh).  No networking (delegates to openrouter.zsh).

# ── Export ────────────────────────────────────────────────────────────────────

# Export all local state to a single portable JSON file.
# Usage: backup_export [output-path]
# If output-path is omitted, a timestamped file is written to the current dir.
backup_export() {
    local outfile="${1:-./claude-router-backup-$(date +%Y-%m-%d).json}"

    # Collect all user models.
    local user_models_json
    if [[ -f "${USER_MODELS_FILE}" ]]; then
        user_models_json=$(grep -v '^\s*#' "${USER_MODELS_FILE}" \
            | grep -v '^\s*$' \
            | jq -Rn '[inputs]')
    else
        user_models_json='[]'
    fi

    # Collect all per-model preset metadata files.
    local all_presets_json='{}'
    if [[ -d "${PRESETS_DIR}" ]]; then
        for f in "${PRESETS_DIR}"/*.json(N); do
            local model_key="${f:t:r}"   # filename without extension
            local file_json
            file_json=$(cat "${f}")
            all_presets_json=$(print -- "${all_presets_json}" \
                | jq --arg key "${model_key}" \
                     --argjson val "${file_json}" \
                     '. + {($key): $val}')
        done
    fi

    # Assemble the backup envelope.
    local backup
    backup=$(jq -n \
        --arg schema "${BACKUP_SCHEMA_VERSION}" \
        --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --argjson user_models "${user_models_json}" \
        --argjson presets "${all_presets_json}" \
        '{
            schema_version: $schema,
            created_at:     $created,
            user_models:    $user_models,
            presets:        $presets
        }')

    print -- "${backup}" > "${outfile}" \
        || { die "Could not write backup to ${outfile}"; return 1; }

    info "Backup written to ${outfile}"
}

# ── Import ────────────────────────────────────────────────────────────────────

# Import a backup file.
# Usage: backup_import <file> <mode>   mode = merge | replace
backup_import() {
    local file="${1:?backup_import requires a file path}"
    local mode="${2:?backup_import requires a mode (merge|replace)}"

    # ── Validate ──────────────────────────────────────────────────────────────

    [[ -f "${file}" ]] || { die "File not found: ${file}"; return 1; }

    local backup
    backup=$(jq '.' "${file}" 2>/dev/null) \
        || { die "File is not valid JSON: ${file}"; return 1; }

    local schema
    schema=$(print -- "${backup}" | jq -r '.schema_version // empty')
    [[ "${schema}" == "${BACKUP_SCHEMA_VERSION}" ]] \
        || { die "Unsupported backup schema version: ${schema:-missing}"; return 1; }

    # ── User models ───────────────────────────────────────────────────────────

    local -a imported_models
    imported_models=( "${(@f)$(print -- "${backup}" | jq -r '.user_models[]')}" )

    if [[ "${mode}" == 'replace' ]]; then
        # Wipe user models atomically — write empty file via temp to avoid partial state.
        mkdir -p "${CONFIG_DIR}"
        local _tmp_models
        _tmp_models=$(mktemp) \
            || { die "Could not create temp file for replace."; return 1; }
        mv "${_tmp_models}" "${USER_MODELS_FILE}"
    fi

    local m
    for m in "${imported_models[@]}"; do
        [[ -n "${m}" ]] || continue
        if ! grep -qxF "${m}" "${USER_MODELS_FILE}" 2>/dev/null; then
            print -- "${m}" >> "${USER_MODELS_FILE}"
        fi
    done

    # ── Presets ───────────────────────────────────────────────────────────────

    mkdir -p "${PRESETS_DIR}"

    local -a model_keys
    model_keys=( "${(@f)$(print -- "${backup}" | jq -r '.presets | keys[]')}" )

    local key
    for key in "${model_keys[@]}"; do
        [[ -n "${key}" ]] || continue

        local imported_arr dest_file existing merged
        imported_arr=$(print -- "${backup}" | jq --arg k "${key}" '.presets[$k]')
        dest_file="${PRESETS_DIR}/${key}.json"

        if [[ "${mode}" == 'replace' ]] || [[ ! -f "${dest_file}" ]]; then
            print -- "${imported_arr}" > "${dest_file}"
        else
            # Merge: keep existing entries, add imported entries by slug.
            existing=$(cat "${dest_file}")
            merged=$(jq -n \
                --argjson existing "${existing}" \
                --argjson imported "${imported_arr}" \
                '($existing + $imported) | unique_by(.slug)')
            print -- "${merged}" > "${dest_file}"
        fi

        # Recreate OpenRouter presets for each entry in this model.
        local -a slugs
        slugs=( "${(@f)$(print -- "${imported_arr}" | jq -r '.[].slug')}" )
        local providers_json model_id slug

        for slug in "${slugs[@]}"; do
            [[ -n "${slug}" ]] || continue
            providers_json=$(print -- "${imported_arr}" \
                | jq -c --arg s "${slug}" '.[] | select(.slug==$s) | .providers')
            model_id=$(print -- "${imported_arr}" \
                | jq -r --arg s "${slug}" '.[] | select(.slug==$s) | .model // empty')
            [[ -n "${model_id}" ]] || continue

            local payload
            payload=$(preset_payload "${slug}" "${model_id}" "${providers_json}")
            create_or_update_preset "${slug}" "${payload}" \
                || warn "Could not recreate preset \"${slug}\" on OpenRouter."
        done
    done

    info "Import complete (mode: ${mode})."
}
