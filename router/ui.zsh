#!/usr/bin/env zsh
# ui.zsh — every prompt and display element
# No networking.  No preset building.  No cache logic.

# ── Header ────────────────────────────────────────────────────────────────────

print_header() {
    local model="${1:-unknown}"
    print ''
    print '╔══════════════════════════════════════════════╗'
    printf  '║  🔀  Claude Router                           ║\n'
    printf  '║  Model: %-36s║\n' "${model}"
    print '╚══════════════════════════════════════════════╝'
    print ''
}

# ── Model picker ──────────────────────────────────────────────────────────────

show_model_list() {
    local -a models=("${@}")
    local i=1
    print '' >&2
    print '  Available models' >&2
    print '  ────────────────────────────────────────────' >&2
    for m in "${models[@]}"; do
        printf '  %-3d %s\n' "${i}" "${m}" >&2
        (( i++ ))
    done
    print '  ────────────────────────────────────────────' >&2
    print '  ➕  Enter custom model…' >&2
    print '  📝  Manage saved models…' >&2
    print '' >&2
}

# Prints a model string | "__custom__" | "__manage__"
prompt_model_selection() {
    local -a models=("${@}")
    local total="${#models[@]}"
    local input

    while true; do
        show_model_list "${models[@]}"
        printf '  Select (1–%d, +, m): ' "${total}" >&2
        read -r input

        case "${input}" in
            '+') print -- '__custom__'; return 0 ;;
            'm') print -- '__manage__'; return 0 ;;
        esac

        if [[ "${input}" =~ '^[0-9]+$' ]] && (( input >= 1 && input <= total )); then
            print -- "${models[input]}"
            return 0
        fi

        warn "Enter a number 1–${total}, '+' for custom, or 'm' to manage."
    done
}

# ── Custom model entry ────────────────────────────────────────────────────────

prompt_custom_model() {
    local input
    print '' >&2
    printf '  Enter OpenRouter model: ' >&2
    read -r input
    print -- "${input}"
}

prompt_save_model() {
    local model="${1}"
    local input
    printf '  Save "%s" for future sessions? (y/N) ' "${model}" >&2
    read -r input
    [[ "${input:l}" == 'y' ]]
}

# ── Saved model manager ───────────────────────────────────────────────────────

# Prints a model string to delete | "__back__"
show_manage_menu() {
    local -a models=("${@}")
    local total="${#models[@]}"
    local input

    while true; do
        print '' >&2
        print '  Saved models' >&2
        print '  ────────────────────────────────────────────' >&2
        if (( total == 0 )); then
            print '  (none)' >&2
        else
            local i=1
            for m in "${models[@]}"; do
                printf '  %-3d %s\n' "${i}" "${m}" >&2
                (( i++ ))
            done
        fi
        print '' >&2
        if (( total > 0 )); then
            print '  d<n>  Delete  (e.g. d2)' >&2
        fi
        print '  b     Back' >&2
        print '' >&2
        printf '  > ' >&2
        read -r input

        case "${input}" in
            b) print -- '__back__'; return 0 ;;
            d[0-9]*)
                if (( total == 0 )); then
                    warn "No saved models to delete."
                    continue
                fi
                local idx="${input#d}"
                if [[ "${idx}" =~ '^[0-9]+$' ]] && (( idx >= 1 && idx <= total )); then
                    print -- "${models[idx]}"
                    return 0
                fi
                warn "Invalid index. Use d1–d${total}."
                ;;
            *) warn "Unknown command. Use d<n> or b." ;;
        esac
    done
}

# ── Routing mode ──────────────────────────────────────────────────────────────

# Prints "direct" or "preset"
prompt_routing_mode() {
    local input
    print '' >&2
    print '  Launch mode' >&2
    print '  ────────────────────────────────────────────' >&2
    print '  1  🚀 Direct   (export model directly, no routing)' >&2
    print '  2  🎯 Preset   (provider ordering + OpenRouter preset)' >&2
    print '' >&2

    while true; do
        printf '  Select (1/2): ' >&2
        read -r input
        case "${input}" in
            1) print -- 'direct'; return 0 ;;
            2) print -- 'preset'; return 0 ;;
            *) warn "Enter 1 for Direct or 2 for Preset." ;;
        esac
    done
}

# ── Provider table ────────────────────────────────────────────────────────────

show_provider_table() {
    local -a providers=("${@}")
    local i=1
    print '  #   Provider' >&2
    print '  ─   ────────' >&2
    for p in "${providers[@]}"; do
        printf '  %-3d %s\n' "${i}" "${p}" >&2
        (( i++ ))
    done
    print '' >&2
}

# Prints ordered provider names (newline-separated) to stdout.
prompt_provider_order() {
    local -a providers=("${@}")
    local total="${#providers[@]}"
    local input

    while true; do
        printf '  Enter provider priority (e.g. 2 1 3): ' >&2
        read -r input

        local -a tokens=( ${=input} )
        [[ ${#tokens[@]} -gt 0 ]] || { warn "Enter at least one provider index."; continue; }

        local valid=1
        local t
        for t in "${tokens[@]}"; do
            if ! [[ "${t}" =~ '^[0-9]+$' ]] || (( t < 1 || t > total )); then
                warn "\"${t}\" is not a valid index (1–${total})."
                valid=0
                break
            fi
        done
        (( valid )) || continue

        # Reject duplicates — a provider must not appear more than once.
        local -A seen
        for t in "${tokens[@]}"; do
            if (( ${+seen[$t]} )); then
                warn "Index \"${t}\" appears more than once. Each provider may only be selected once."
                valid=0
                break
            fi
            seen[$t]=1
        done
        (( valid )) || continue

        for t in "${tokens[@]}"; do
            print -- "${providers[t]}"
        done
        return 0
    done
}

# ── Preset manager UI ─────────────────────────────────────────────────────────

# Display the preset list for a model and prompt for an action.
# Presets argument is a JSON array from local metadata.
# Prints a composite result to stdout: "<action>:<slug>" or a sentinel.
#   __create__  → create new preset
#   __import__  → import backup
#   __export__  → export backup
#   __back__    → back to model selection
#   launch:<slug>
#   edit:<slug>
#   rename:<slug>
#   delete:<slug>
show_preset_menu() {
    local model="${1:?show_preset_menu requires a model}"
    local presets_json="${2:?show_preset_menu requires a presets JSON array}"

    # Determine the number of presets without relying on (@f) empty-string artefact.
    # jq outputs nothing (not "null") when iterating an empty array with .[].field.
    local total
    total=$(print -- "${presets_json}" | jq 'length')

    # Parse names and slugs only when there is something to parse.
    local -a names slugs
    if (( total > 0 )); then
        names=( "${(@f)$(print -- "${presets_json}" | jq -r '.[].name')}" )
        slugs=( "${(@f)$(print -- "${presets_json}" | jq -r '.[].slug')}" )
    fi

    # Hoist idx to avoid repeated local declarations inside case arms.
    local idx input
    local summary=""
    local i
    
    while true; do
        print '' >&2
        printf '  🎯 Presets for\n\n  %s\n\n' "${model}" >&2
        print '  ────────────────────────────────────────────' >&2

        if (( total == 0 )); then
            print '  (no presets yet)' >&2
        else
            i=1
            while (( i <= total )); do
                summary=$(print -- "${presets_json}" \
                    | jq -r --argjson idx $(( i - 1 )) \
                        '.[$idx].providers | map(.provider) | join(" → ")')
                printf '  %-3d ⚡ %s\n' "${i}" "${names[i]}" >&2
                printf '      %s\n' "${summary}" >&2
                (( i++ ))
            done
        fi

        print '' >&2
        print '  ────────────────────────────────────────────' >&2
        print '  +       Create new preset' >&2
        print '  i       Import backup' >&2
        print '  x       Export backup' >&2
        print '  ────────────────────────────────────────────' >&2
        if (( total > 0 )); then
            print '  <n>     Launch preset  (e.g. 1)' >&2
            print '  e<n>    Edit preset    (e.g. e2)' >&2
            print '  r<n>    Rename preset  (e.g. r1)' >&2
            print '  d<n>    Delete preset  (e.g. d3)' >&2
        fi
        print '  b       Back to model selection' >&2
        print '' >&2
        printf '  > ' >&2
        read -r input

        case "${input}" in
            '+') print -- '__create__'; return 0 ;;
            i)   print -- '__import__'; return 0 ;;
            x)   print -- '__export__'; return 0 ;;
            b)   print -- '__back__';   return 0 ;;

            # Direct launch by number: "1", "2", …
            <1->)
                if (( total == 0 )); then
                    warn "No presets yet. Create one with '+'."
                    continue
                fi
                if (( input >= 1 && input <= total )); then
                    print -- "launch:${slugs[input]}"
                    return 0
                fi
                warn "Invalid number. Choose 1–${total}."
                ;;

            e<1->)
                if (( total == 0 )); then
                    warn "No presets yet. Create one with '+'."
                    continue
                fi
                idx="${input#e}"
                if (( idx >= 1 && idx <= total )); then
                    print -- "edit:${slugs[idx]}"
                    return 0
                fi
                warn "Invalid index. Use e1–e${total}."
                ;;

            r<1->)
                if (( total == 0 )); then
                    warn "No presets yet. Create one with '+'."
                    continue
                fi
                idx="${input#r}"
                if (( idx >= 1 && idx <= total )); then
                    print -- "rename:${slugs[idx]}"
                    return 0
                fi
                warn "Invalid index. Use r1–r${total}."
                ;;

            d<1->)
                if (( total == 0 )); then
                    warn "No presets yet. Create one with '+'."
                    continue
                fi
                idx="${input#d}"
                if (( idx >= 1 && idx <= total )); then
                    print -- "delete:${slugs[idx]}"
                    return 0
                fi
                warn "Invalid index. Use d1–d${total}."
                ;;

            *)
                warn "Unknown command. See options above."
                ;;
        esac
    done
}

# Prompt for a preset name, with an optional default.
# Usage: prompt_preset_name [default-name]
# Prints the entered name (or the default) to stdout.
prompt_preset_name() {
    local default="${1:-}"
    local input
    if [[ -n "${default}" ]]; then
        printf '  Preset name [%s]: ' "${default}" >&2
    else
        printf '  Preset name: ' >&2
    fi
    read -r input
    if [[ -z "${input}" && -n "${default}" ]]; then
        print -- "${default}"
    else
        print -- "${input}"
    fi
}

# Prompt for a new name during rename.
# Prints "confirmed:<new-name>" or "__cancel__"
prompt_rename_preset() {
    local current="${1:?prompt_rename_preset requires current name}"
    local new_name input

    print '' >&2
    print '  Rename preset' >&2
    printf '  Current: %s\n' "${current}" >&2
    printf '  New name: ' >&2
    read -r new_name

    [[ -n "${new_name}" ]] || { print -- '__cancel__'; return 0; }

    printf '  Rename to "%s"? (y/N) ' "${new_name}" >&2
    read -r input
    if [[ "${input:l}" == 'y' ]]; then
        print -- "confirmed:${new_name}"
    else
        print -- '__cancel__'
    fi
}

# Prompt for confirmation before deleting a preset.
# Returns 0 for yes, 1 for no.
prompt_delete_preset() {
    local name="${1:?prompt_delete_preset requires name}"
    local model="${2:?prompt_delete_preset requires model}"
    local input
    print '' >&2
    printf '  Delete preset "%s" for %s? (y/N) ' "${name}" "${model}" >&2
    read -r input
    [[ "${input:l}" == 'y' ]]
}

# ── Backup prompts ────────────────────────────────────────────────────────────

prompt_import_file() {
    local input
    print '' >&2
    printf '  Import backup file: ' >&2
    read -r input
    print -- "${input}"
}

prompt_import_mode() {
    local input
    print '' >&2
    print '  Import mode' >&2
    print '  1  Merge   (keep existing, add imported)' >&2
    print '  2  Replace (overwrite all existing data)' >&2
    print '' >&2
    while true; do
        printf '  Select (1/2): ' >&2
        read -r input
        case "${input}" in
            1) print -- 'merge';   return 0 ;;
            2) print -- 'replace'; return 0 ;;
            *) warn "Enter 1 or 2." ;;
        esac
    done
}

# ── Feedback ──────────────────────────────────────────────────────────────────

show_success() {
    local value="${1:-}"
    print ''
    print "  ✅  ANTHROPIC_MODEL=${value}"
    print ''
}

show_error() {
    local message="${1:-An unexpected error occurred.}"
    print ''
    print "  ❌  ${message}" >&2
    print ''
}
