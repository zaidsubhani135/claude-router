#!/usr/bin/env zsh
# ui.zsh — every prompt and display element
# No networking.  No preset building.  No cache logic.
#
# fzf is used when available.  When absent, all menus fall back to the
# original numbered-list implementation so the router remains fully functional
# on Chromebook/Crostini, plain SSH sessions, and minimal environments.

# ── fzf detection ─────────────────────────────────────────────────────────────

_ui_has_fzf() {
    command -v fzf > /dev/null 2>&1
}

_UI_FZF_WARNED=0
_ui_warn_no_fzf() {
    (( _UI_FZF_WARNED )) && return
    _UI_FZF_WARNED=1
    warn "fzf not found — using numbered menus. Install fzf for the enhanced UI."
}

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

_ui_fzf_model_selection() {
    local -a models=("${@}")

    local fzf_input=""
    local m
    for m in "${models[@]}"; do
        fzf_input+="${m}"$'\n'
    done
    fzf_input+="+ Add custom model…"$'\n'
    fzf_input+="⚙ Manage saved models…"

    local result
    result=$(
        print -- "${fzf_input}" \
        | fzf \
            --prompt '  Model › ' \
            --height '~40%' \
            --layout reverse \
            --border rounded \
            --no-preview \
            --header '  ↑↓ navigate · Enter select · / search · Esc cancel' \
            2>/dev/tty
    ) || return 1

    case "${result}" in
        '+ Add custom model…') print -- '__custom__' ;;
        '⚙ Manage saved models…') print -- '__manage__' ;;
        *) print -- "${result}" ;;
    esac
}

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

    if _ui_has_fzf; then
        _ui_fzf_model_selection "${models[@]}"
        return $?
    fi

    _ui_warn_no_fzf

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

_ui_fzf_manage_menu() {
    local -a models=("${@}")
    local total="${#models[@]}"

    if (( total == 0 )); then
        print '' >&2
        print '  No saved models. Press any key to go back.' >&2
        read -rk1 >&2
        print -- '__back__'
        return 0
    fi

    local fzf_input=""
    local m
    for m in "${models[@]}"; do
        fzf_input+="${m}"$'\n'
    done
    fzf_input+="← Back"

    local result
    result=$(
        print -- "${fzf_input}" \
        | fzf \
            --prompt '  Delete saved model › ' \
            --height '~30%' \
            --layout reverse \
            --border rounded \
            --no-preview \
            --header '  Select a model to DELETE it · Esc / Back to return' \
            2>/dev/tty
    ) || { print -- '__back__'; return 0; }

    [[ "${result}" == '← Back' || -z "${result}" ]] \
        && { print -- '__back__'; return 0; }

    print -- "${result}"
}

# Prints a model string to delete | "__back__"
show_manage_menu() {
    local -a models=("${@}")

    if _ui_has_fzf; then
        _ui_fzf_manage_menu "${models[@]}"
        return $?
    fi

    _ui_warn_no_fzf

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

_ui_fzf_routing_mode() {
    local result
    result=$(
        printf '%s\n%s\n' \
            '🚀  Direct  — export model directly, no routing' \
            '🎯  Preset  — provider ordering + OpenRouter preset' \
        | fzf \
            --prompt '  Launch mode › ' \
            --height '~20%' \
            --layout reverse \
            --border rounded \
            --no-preview \
            --header '  Enter to select · Esc cancel' \
            2>/dev/tty
    ) || return 1

    case "${result}" in
        '🚀'*) print -- 'direct' ;;
        '🎯'*) print -- 'preset' ;;
        *)     return 1 ;;
    esac
}

# Prints "direct" or "preset"
prompt_routing_mode() {
    if _ui_has_fzf; then
        _ui_fzf_routing_mode
        return $?
    fi

    _ui_warn_no_fzf

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

# ── Provider intelligence table display ───────────────────────────────────────

show_provider_intelligence() {
    local intel_arr="${1:-[]}"

    local count
    count=$(print -- "${intel_arr}" | jq 'length' 2>/dev/null || print 0)
    (( count == 0 )) && return 0

    print '' >&2
    print '  ── Provider Intelligence (cached metadata) ──────────────────' >&2
    provider_intel_table "${intel_arr}" >&2
}

# ── Provider table (plain numbered display) ───────────────────────────────────

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

# ── Provider ordering (fzf multi-select with live sort) ───────────────────────
#
# Sort is implemented by writing pre-sorted temp files and using fzf --bind
# to reload from the appropriate file.  This approach:
#   - Works on all fzf versions (reload action available since fzf 0.21, 2020)
#   - Requires no shell quoting inside --bind arguments
#   - Is fully non-destructive: sorted files are temp, original array unchanged

_ui_fzf_provider_order() {
    local -a providers=("${@}")
    local intel_arr="${_ROUTER_PROVIDER_INTEL:-[]}"

    # Write one temp file per sort order.
    local tmp_name tmp_cost tmp_lat tmp_up tmp_tp
    tmp_name=$(mktemp) || { warn "Cannot create temp file."; return 1; }
    tmp_cost=$(mktemp) || { rm -f "${tmp_name}"; warn "Cannot create temp file."; return 1; }
    tmp_lat=$(mktemp)  || { rm -f "${tmp_name}" "${tmp_cost}"; warn "Cannot create temp file."; return 1; }
    tmp_up=$(mktemp)   || { rm -f "${tmp_name}" "${tmp_cost}" "${tmp_lat}"; warn "Cannot create temp file."; return 1; }
    tmp_tp=$(mktemp)   || { rm -f "${tmp_name}" "${tmp_cost}" "${tmp_lat}" "${tmp_up}"; warn "Cannot create temp file."; return 1; }

    # Populate all sort files.  Falls back to provider name only when no intel.
    local has_intel=0
    local count
    count=$(print -- "${intel_arr}" | jq 'length' 2>/dev/null || print 0)
    (( count > 0 )) && has_intel=1

    if (( has_intel )); then
        provider_intel_write_sorted "${tmp_name}" "${intel_arr}" "name"
        provider_intel_write_sorted "${tmp_cost}" "${intel_arr}" "cost"
        provider_intel_write_sorted "${tmp_lat}"  "${intel_arr}" "latency"
        provider_intel_write_sorted "${tmp_up}"   "${intel_arr}" "uptime"
        provider_intel_write_sorted "${tmp_tp}"   "${intel_arr}" "throughput"
    else
        # No intel — write bare provider names to all files (same content).
        local p
        for p in "${providers[@]}"; do
            print -- "${p}"
        done > "${tmp_name}"
        cp "${tmp_name}" "${tmp_cost}"
        cp "${tmp_name}" "${tmp_lat}"
        cp "${tmp_name}" "${tmp_up}"
        cp "${tmp_name}" "${tmp_tp}"
    fi

    print '' >&2
    print '  ── Provider Selection ──────────────────────────────────────' >&2
    print '  TAB to select · Enter to confirm · Esc to cancel' >&2
    print '  Sort: s=cost  l=latency  u=uptime  t=throughput  n=name' >&2
    print '  Select in your desired priority order (first = highest priority)' >&2
    print '' >&2

    local selected_lines
    selected_lines=$(
        fzf \
            --prompt '  Providers › ' \
            --multi \
            --height '~60%' \
            --layout reverse \
            --border rounded \
            --no-preview \
            --header '  TAB select · ↑↓ navigate · s/l/u/t/n sort · Enter confirm' \
            --bind "s:reload(cat ${tmp_cost})" \
            --bind "l:reload(cat ${tmp_lat})" \
            --bind "u:reload(cat ${tmp_up})" \
            --bind "t:reload(cat ${tmp_tp})" \
            --bind "n:reload(cat ${tmp_name})" \
            < "${tmp_name}" \
            2>/dev/tty
    )
    local rc=$?
    rm -f "${tmp_name}" "${tmp_cost}" "${tmp_lat}" "${tmp_up}" "${tmp_tp}"

    (( rc != 0 )) && return 1
    [[ -z "${selected_lines}" ]] && { warn "No providers selected."; return 1; }

    # Extract provider name: first whitespace-delimited token on each line.
    # provider_intel_fzf_line guarantees the name is the first token with no
    # embedded spaces (OpenRouter provider names never contain spaces).
    local line pname
    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue
        pname="${line%%[[:space:]]*}"
        [[ -n "${pname}" ]] && print -- "${pname}"
    done <<< "${selected_lines}"
}

# Prints ordered provider names (newline-separated) to stdout.
prompt_provider_order() {
    local -a providers=("${@}")

    if _ui_has_fzf; then
        _ui_fzf_provider_order "${providers[@]}"
        return $?
    fi

    _ui_warn_no_fzf

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

        local -A seen
        for t in "${tokens[@]}"; do
            if (( ${+seen[$t]} )); then
                warn "Index \"${t}\" appears more than once."
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

# ── Preset menu (fzf unified, two-step) ──────────────────────────────────────
#
# Two-step design avoids --bind become (fzf >=0.36 only) and all inline
# shell quoting inside fzf arguments:
#   Step 1 — pick an item; tag prefix encodes type (ACTION: or PRESET:)
#   Step 2 — for presets, a second small fzf picks the action verb

_ui_fzf_preset_menu() {
    local model="${1:?_ui_fzf_preset_menu requires a model}"
    local presets_json="${2:?_ui_fzf_preset_menu requires presets JSON}"

    local total
    total=$(print -- "${presets_json}" | jq 'length')

    # Build input: tagged lines so first token carries type:payload.
    local fzf_input
    fzf_input="ACTION:__create__  ➕  Create new preset"$'\n'
    fzf_input+="ACTION:__import__  📥  Import backup"$'\n'
    fzf_input+="ACTION:__export__  📤  Export backup"$'\n'
    fzf_input+="ACTION:__back__    ⬅   Back to model selection"

    if (( total > 0 )); then
        fzf_input+=$'\n'"SEP:------  ────────────────────────────────────────"
        local i name slug summary
        for (( i = 0; i < total; i++ )); do
            name=$(print -- "${presets_json}" | jq -r ".[$i].name")
            slug=$(print -- "${presets_json}" | jq -r ".[$i].slug")
            summary=$(print -- "${presets_json}" | jq -r \
                --argjson idx "${i}" \
                '.[$idx].providers | map(.provider) | join(" → ")')
            fzf_input+=$'\n'"PRESET:${slug}  ⚡ ${name}  [${summary}]"
        done
    fi

    # Step 1: pick item. --with-nth hides the tag prefix from display.
    local raw_pick
    raw_pick=$(
        print -- "${fzf_input}" \
        | fzf \
            --prompt "  Presets › " \
            --height '~50%' \
            --layout reverse \
            --border rounded \
            --no-preview \
            --with-nth '2..' \
            --delimiter ' ' \
            --header '  Enter to select · Esc cancel' \
            2>/dev/tty
    ) || { print -- '__back__'; return 0; }

    [[ -z "${raw_pick}" ]] && { print -- '__back__'; return 0; }

    # Decode the tag prefix (first space-delimited token of the raw line).
    local first_token="${raw_pick%%[[:space:]]*}"
    local tag="${first_token%%:*}"
    local payload="${first_token#*:}"

    case "${tag}" in
        ACTION)
            print -- "${payload}"
            return 0
            ;;
        PRESET)
            # Step 2: pick action for this preset.
            local slug="${payload}"
            local action_line
            action_line=$(
                printf '%s\n%s\n%s\n%s\n' \
                    "launch  ▶  Launch this preset" \
                    "edit    ✏  Edit provider order" \
                    "rename  📝  Rename" \
                    "delete  🗑  Delete" \
                | fzf \
                    --prompt "  Action › " \
                    --height '~25%' \
                    --layout reverse \
                    --border rounded \
                    --no-preview \
                    --with-nth '2..' \
                    --delimiter ' ' \
                    --header '  Esc to go back' \
                    2>/dev/tty
            ) || { print -- '__back__'; return 0; }

            local verb="${action_line%%[[:space:]]*}"
            [[ -z "${verb}" ]] && { print -- '__back__'; return 0; }
            print -- "${verb}:${slug}"
            return 0
            ;;
        SEP|*)
            print -- '__back__'
            return 0
            ;;
    esac
}

# Displays a preset list and prompts for an action.
# Prints: "launch:<slug>" | "edit:<slug>" | "rename:<slug>" | "delete:<slug>"
#       | "__create__" | "__import__" | "__export__" | "__back__"
show_preset_menu() {
    local model="${1:?show_preset_menu requires a model}"
    local presets_json="${2:?show_preset_menu requires a presets JSON array}"

    if _ui_has_fzf; then
        _ui_fzf_preset_menu "${model}" "${presets_json}"
        return $?
    fi

    _ui_warn_no_fzf

    # ── Numbered-list fallback (original implementation, unchanged) ────────────
    local total
    total=$(print -- "${presets_json}" | jq 'length')

    local -a names slugs
    if (( total > 0 )); then
        names=( "${(@f)$(print -- "${presets_json}" | jq -r '.[].name')}" )
        slugs=( "${(@f)$(print -- "${presets_json}" | jq -r '.[].slug')}" )
    fi

    local idx input summary=""
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

            <1->)
                if (( total == 0 )); then warn "No presets yet. Create one with '+'."; continue; fi
                if (( input >= 1 && input <= total )); then
                    print -- "launch:${slugs[input]}"; return 0
                fi
                warn "Invalid number. Choose 1–${total}."
                ;;

            e<1->)
                if (( total == 0 )); then warn "No presets yet."; continue; fi
                idx="${input#e}"
                if (( idx >= 1 && idx <= total )); then
                    print -- "edit:${slugs[idx]}"; return 0
                fi
                warn "Invalid index. Use e1–e${total}."
                ;;

            r<1->)
                if (( total == 0 )); then warn "No presets yet."; continue; fi
                idx="${input#r}"
                if (( idx >= 1 && idx <= total )); then
                    print -- "rename:${slugs[idx]}"; return 0
                fi
                warn "Invalid index. Use r1–r${total}."
                ;;

            d<1->)
                if (( total == 0 )); then warn "No presets yet."; continue; fi
                idx="${input#d}"
                if (( idx >= 1 && idx <= total )); then
                    print -- "delete:${slugs[idx]}"; return 0
                fi
                warn "Invalid index. Use d1–d${total}."
                ;;

            *) warn "Unknown command. See options above." ;;
        esac
    done
}

# ── Preset name / rename / delete prompts ─────────────────────────────────────

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
    if _ui_has_fzf; then
        local result
        result=$(
            printf '%s\n%s\n' \
                'merge   — keep existing, add imported' \
                'replace — overwrite all existing data' \
            | fzf \
                --prompt '  Import mode › ' \
                --height '~20%' \
                --layout reverse \
                --border rounded \
                --no-preview \
                2>/dev/tty
        ) || return 1
        case "${result}" in
            merge*)   print -- 'merge';   return 0 ;;
            replace*) print -- 'replace'; return 0 ;;
        esac
    fi

    _ui_warn_no_fzf
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
