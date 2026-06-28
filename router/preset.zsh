#!/usr/bin/env zsh
# preset.zsh — pure data transforms and local preset metadata I/O
# Nothing interactive.  Nothing networked.

# ── Slug helpers ──────────────────────────────────────────────────────────────

# Produce a stable OpenRouter preset slug from a model id and preset name.
# Usage: preset_slug <model-id> <preset-name>
# Example: preset_slug "deepseek/deepseek-v4-flash" "Cheapest"
#          → "claude-deepseek-deepseek-v4-flash-cheapest"
preset_slug() {
    local model="${1:?preset_slug requires a model id}"
    local name="${2:?preset_slug requires a preset name}"
    sanitize_slug "${PRESET_PREFIX}-${model}-${name}"
}

# ── OpenRouter payload builders ───────────────────────────────────────────────

# Build a single provider entry for the preset's provider array.
# Usage: provider_payload <provider-name> [weight]
provider_payload() {
    local name="${1:?provider_payload requires a provider name}"
    local weight="${2:-1}"
    printf '{"provider":"%s","weight":%d}' "${name}" "${weight}"
}

preset_payload() {
    local slug="${1:?preset_payload requires a slug}"
    local model="${2:?preset_payload requires a model id}"
    local providers="${3:?preset_payload requires a providers array}"

    local provider_order
    provider_order=$(
        print -- "${providers}" |
        jq '[.[].provider]'
    )

    jq -nc \
       --arg model "${model}" \
       --argjson order "${provider_order}" '
    {
      model: $model,
      messages: [
        {
          role: "user",
          content: "router preset"
        }
      ],
      provider: {
        order: $order
      }
    }'
}

# ── Local metadata file helpers ───────────────────────────────────────────────

# Return the path to the metadata file for a given model.
# Usage: preset_metadata_file <model-id>
preset_metadata_file() {
    local model="${1:?preset_metadata_file requires a model id}"
    print -- "${PRESETS_DIR}/${model//\//-}.json"
}

# Load all presets for a model as a JSON array (prints to stdout).
# Returns an empty array if the file does not exist.
preset_load_all() {
    local model="${1:?preset_load_all requires a model id}"
    local file
    file=$(preset_metadata_file "${model}")
    if [[ -f "${file}" ]]; then
        cat "${file}"
    else
        print -- '[]'
    fi
}

# Save a JSON array of presets for a model.
# Usage: preset_save_all <model-id> <json-array>
preset_save_all() {
    local model="${1:?preset_save_all requires a model id}"
    local json="${2:?preset_save_all requires a JSON array}"
    local file
    file=$(preset_metadata_file "${model}")
    mkdir -p "${PRESETS_DIR}"
    print -- "${json}" > "${file}"
}

# Append or update a single preset entry in the model's metadata file.
# Usage: preset_upsert <model-id> <slug> <name> <providers-json-array>
preset_upsert() {
    local model="${1:?preset_upsert requires a model id}"
    local slug="${2:?preset_upsert requires a slug}"
    local name="${3:?preset_upsert requires a name}"
    local providers="${4:?preset_upsert requires providers}"

    local existing
    existing=$(preset_load_all "${model}")

    # Remove any entry with the same slug, then append the new one.
    local updated
    updated=$(print -- "${existing}" \
        | jq --arg slug "${slug}" 'map(select(.slug != $slug))')
    updated=$(print -- "${updated}" \
        | jq --arg slug "${slug}" \
             --arg name "${name}" \
             --arg model "${model}" \
             --argjson providers "${providers}" \
             '. + [{"slug":$slug,"name":$name,"model":$model,"providers":$providers}]')

    preset_save_all "${model}" "${updated}"
}

# Remove a preset entry from the model's metadata file by slug.
# Usage: preset_remove <model-id> <slug>
preset_remove() {
    local model="${1:?preset_remove requires a model id}"
    local slug="${2:?preset_remove requires a slug}"
    local existing updated
    existing=$(preset_load_all "${model}")
    updated=$(print -- "${existing}" \
        | jq --arg slug "${slug}" 'map(select(.slug != $slug))')
    preset_save_all "${model}" "${updated}"
}

# Rename a preset in the model's metadata file.
# Usage: preset_rename_local <model-id> <old-slug> <new-name> <new-slug>
preset_rename_local() {
    local model="${1:?preset_rename_local requires a model id}"
    local old_slug="${2:?preset_rename_local requires an old slug}"
    local new_name="${3:?preset_rename_local requires a new name}"
    local new_slug="${4:?preset_rename_local requires a new slug}"

    local existing updated
    existing=$(preset_load_all "${model}")
    updated=$(print -- "${existing}" | jq \
        --arg old_slug "${old_slug}" \
        --arg new_slug "${new_slug}" \
        --arg new_name "${new_name}" \
        'map(if .slug == $old_slug then .slug = $new_slug | .name = $new_name else . end)')
    preset_save_all "${model}" "${updated}"
}

# Build a providers JSON array string from an ordered list of provider names.
# Usage: providers_array_from_names <provider1> <provider2> …
providers_array_from_names() {
    local arr="["
    local first=1
    local p
    for p in "$@"; do
        (( first )) || arr+=","
        arr+=$(provider_payload "${p}" 1)
        first=0
    done
    arr+="]"
    print -- "${arr}"
}
