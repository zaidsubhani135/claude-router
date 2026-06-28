#!/usr/bin/env zsh
# provider_intel.zsh — extract and display provider metadata from cached endpoint JSON
#
# All functions are PURE DATA operations on the cached endpoint JSON.
# No network calls.  No UI prompts.  No preset logic.
# Sorting affects only the returned display order — never stored arrays.

# ── Helpers ────────────────────────────────────────────────────────────────────

# Return the path to the cached endpoint file for the current model.
# Usage: _pi_cache_path <model-id>
_pi_cache_path() {
    local model="${1:?_pi_cache_path requires a model id}"
    local safe="${model//\//-}"
    print -- "${CACHE_DIR}/endpoints/${safe}.json"
}

# Format a cost value (USD/token) to a human-readable $/M string.
# Returns "N/A" when value is null/empty/non-numeric.
# Usage: _pi_fmt_cost <raw>
_pi_fmt_cost() {
    local raw="${1}"
    [[ -z "${raw}" || "${raw}" == 'null' ]] && { print -- 'N/A'; return; }
    # Multiply per-token price by 1,000,000 to get $/M tokens, format to 4 sig figs.
    printf '%.4f' "$(print -- "${raw} * 1000000" | bc -l 2>/dev/null || print -- 0)" 2>/dev/null \
        || print -- 'N/A'
}

# Format latency seconds to milliseconds.
_pi_fmt_latency() {
    local raw="${1}"
    [[ -z "${raw}" || "${raw}" == 'null' ]] && { print -- 'N/A'; return; }
    printf '%dms' "$(print -- "${raw} * 1000 / 1" | bc 2>/dev/null || print -- 0)"
}

# Format throughput tok/s.
_pi_fmt_throughput() {
    local raw="${1}"
    [[ -z "${raw}" || "${raw}" == 'null' ]] && { print -- 'N/A'; return; }
    # Use integer truncation to avoid %.0f banker's-rounding differences across
    # printf implementations.  Throughput is always positive.
    printf '%dt/s' "$(( ${raw%%.*} ))" 2>/dev/null || print -- 'N/A'
}

# Format uptime percentage.
_pi_fmt_uptime() {
    local raw="${1}"
    [[ -z "${raw}" || "${raw}" == 'null' ]] && { print -- 'N/A'; return; }
    printf '%.2f%%' "${raw}" 2>/dev/null || print -- 'N/A'
}

# Format context length (e.g. 128000 → 128k).
_pi_fmt_ctx() {
    local raw="${1}"
    [[ -z "${raw}" || "${raw}" == 'null' ]] && { print -- 'N/A'; return; }
    if (( raw >= 1000 )); then
        printf '%dk' "$(( raw / 1000 ))"
    else
        print -- "${raw}"
    fi
}

# ── Data Extraction ────────────────────────────────────────────────────────────

# Read all provider metadata from the cached endpoint file.
# Prints a JSON array of enriched provider objects to stdout.
# Returns an empty JSON array if the cache file does not exist.
# Usage: provider_intel_all <model-id>
provider_intel_all() {
    local model="${1:?provider_intel_all requires a model id}"
    local cache
    cache=$(_pi_cache_path "${model}")

    [[ -f "${cache}" ]] || { print -- '[]'; return; }

    # Extract the endpoints array and transform into a flat list.
    jq '[
        (.data.endpoints // [])[] |
        {
            provider_name:          (.provider_name // "Unknown"),
            name:                   (.name // "Unknown"),
            tag:                    (.tag // ""),
            context_length:         (.context_length // null),
            max_completion_tokens:  (.max_completion_tokens // null),
            max_prompt_tokens:      (.max_prompt_tokens // null),
            quantization:           (.quantization // null),
            supports_implicit_caching: (.supports_implicit_caching // false),
            pricing_prompt:         (.pricing.prompt // null),
            pricing_completion:     (.pricing.completion // null),
            pricing_request:        (.pricing.request // null),
            pricing_image:          (.pricing.image // null),
            uptime:                 (.uptime_last_30m // null),
            latency_p50:            (.latency_last_30m.p50 // null),
            latency_p75:            (.latency_last_30m.p75 // null),
            latency_p90:            (.latency_last_30m.p90 // null),
            latency_p99:            (.latency_last_30m.p99 // null),
            throughput_p50:         (.throughput_last_30m.p50 // null),
            throughput_p75:         (.throughput_last_30m.p75 // null),
            throughput_p90:         (.throughput_last_30m.p90 // null),
            throughput_p99:         (.throughput_last_30m.p99 // null),
            status:                 (.status // -1),
            supported_parameters:   (.supported_parameters // [])
        }
    ]' "${cache}" 2>/dev/null || print -- '[]'
}

# Sort a JSON provider array by a given field.
# Sorting is VIEW-ONLY — the result is never written back to any persistent store.
# Usage: provider_intel_sort <json-array> <field>
# field: cost | latency | uptime | throughput | name
provider_intel_sort() {
    local arr="${1:?provider_intel_sort requires a JSON array}"
    local field="${2:-name}"

    case "${field}" in
        cost)
            print -- "${arr}" | jq '
                sort_by(
                    if .pricing_prompt == null then 999999
                    else (.pricing_prompt | tonumber)
                    end
                )'
            ;;
        latency)
            print -- "${arr}" | jq '
                sort_by(
                    if .latency_p50 == null then 999999
                    else .latency_p50
                    end
                )'
            ;;
        uptime)
            print -- "${arr}" | jq 'sort_by(-(if .uptime == null then -1 else .uptime end))'
            ;;
        throughput)
            print -- "${arr}" | jq '
                sort_by(
                    if .throughput_p50 == null then -999999
                    else -.throughput_p50
                    end
                )'
            ;;
        name|*)
            print -- "${arr}" | jq 'sort_by(.provider_name | ascii_downcase)'
            ;;
    esac
}

# ── Display ────────────────────────────────────────────────────────────────────

# Print a single table row for a provider entry (JSON object from provider_intel_all).
# Fits within 80 columns.
# Usage: provider_intel_table_row <provider-json-object>
provider_intel_table_row() {
    local obj="${1:?provider_intel_table_row requires a JSON object}"

    local name prompt_cost compl_cost uptime lat_p50 tput_p50

    name=$(print -- "${obj}" | jq -r '.provider_name')
    prompt_cost=$(_pi_fmt_cost "$(print -- "${obj}" | jq -r '.pricing_prompt // empty')")
    compl_cost=$(_pi_fmt_cost "$(print -- "${obj}" | jq -r '.pricing_completion // empty')")
    uptime=$(_pi_fmt_uptime "$(print -- "${obj}" | jq -r '.uptime // empty')")
    lat_p50=$(_pi_fmt_latency "$(print -- "${obj}" | jq -r '.latency_p50 // empty')")
    tput_p50=$(_pi_fmt_throughput "$(print -- "${obj}" | jq -r '.throughput_p50 // empty')")

    # Truncate provider name at 16 chars to stay within 80 cols.
    printf '  %-16s  %-8s  %-8s  %-8s  %-7s  %s\n' \
        "${name[1,16]}" "${prompt_cost}" "${compl_cost}" \
        "${uptime}" "${lat_p50}" "${tput_p50}"
}

# Print the full intelligence table for all providers in a JSON array.
# Usage: provider_intel_table <json-array> [sort-field]
provider_intel_table() {
    local arr="${1:?provider_intel_table requires a JSON array}"
    local sort_field="${2:-}"
    local sorted="${arr}"

    [[ -n "${sort_field}" ]] && sorted=$(provider_intel_sort "${arr}" "${sort_field}")

    local count
    count=$(print -- "${sorted}" | jq 'length')
    (( count == 0 )) && { print '  (no provider data available)'; return; }

    print ''
    printf '  %-16s  %-8s  %-8s  %-8s  %-7s  %s\n' \
        'Provider' 'In$/M' 'Out$/M' 'Uptime' 'Latency' 'Throughput'
    printf '  %-16s  %-8s  %-8s  %-8s  %-7s  %s\n' \
        '────────────────' '────────' '────────' '────────' '───────' '──────────'

    local i obj
    for (( i = 0; i < count; i++ )); do
        obj=$(print -- "${sorted}" | jq ".[$i]")
        provider_intel_table_row "${obj}"
    done
    print ''
}

# Print a fzf-compatible preview for a single provider (by name) from a JSON array.
# Usage: provider_intel_verbose <provider-name> <json-array>
provider_intel_verbose() {
    local name="${1:?provider_intel_verbose requires a provider name}"
    local arr="${2:?provider_intel_verbose requires a JSON array}"

    local obj
    obj=$(print -- "${arr}" | jq --arg n "${name}" '.[] | select(.provider_name == $n)')

    [[ -z "${obj}" || "${obj}" == 'null' ]] && {
        print "  Provider: ${name}"
        print "  No metadata available."
        return
    }

    local ctx max_out quant lat_p50 lat_p90 tput_p50 uptime implicit

    ctx=$(_pi_fmt_ctx   "$(print -- "${obj}" | jq -r '.context_length // empty')")
    max_out=$(           print -- "${obj}" | jq -r '.max_completion_tokens // "N/A"')
    quant=$(             print -- "${obj}" | jq -r '.quantization // "N/A"')
    lat_p50=$(_pi_fmt_latency "$(print -- "${obj}" | jq -r '.latency_p50 // empty')")
    lat_p90=$(_pi_fmt_latency "$(print -- "${obj}" | jq -r '.latency_p90 // empty')")
    tput_p50=$(_pi_fmt_throughput "$(print -- "${obj}" | jq -r '.throughput_p50 // empty')")
    uptime=$(_pi_fmt_uptime "$(print -- "${obj}" | jq -r '.uptime // empty')")
    implicit=$(          print -- "${obj}" | jq -r 'if .supports_implicit_caching then "Yes" else "No" end')

    local p_prompt p_compl p_req
    p_prompt=$(_pi_fmt_cost "$(print -- "${obj}" | jq -r '.pricing_prompt // empty')")
    p_compl=$(_pi_fmt_cost  "$(print -- "${obj}" | jq -r '.pricing_completion // empty')")
    p_req=$(               print -- "${obj}" | jq -r '.pricing_request // "N/A"')

    cat <<EOF

  Provider: ${name}

  Context Window:    ${ctx}
  Max Output Tokens: ${max_out}
  Quantization:      ${quant}

  Prompt Cost:       ${p_prompt} \$/M tokens
  Completion Cost:   ${p_compl} \$/M tokens
  Request Cost:      ${p_req}

  Latency P50 (TTFT):  ${lat_p50}
  Latency P90 (TTFT):  ${lat_p90}
  Throughput P50:      ${tput_p50}
  Uptime (30m):        ${uptime}
  Implicit Caching:    ${implicit}

  Data Policy:       Unknown
  (OpenRouter does not expose per-provider data policy via API)

EOF
}

# Build a provider table line suitable for fzf display.
# Emits "ProviderName  |  In$/M  |  Out$/M  |  Uptime  |  Lat(p50)  |  T-put(p50)"
# Usage: provider_intel_fzf_line <provider-json-object>
provider_intel_fzf_line() {
    local obj="${1:?provider_intel_fzf_line requires a JSON object}"

    local name prompt_cost compl_cost uptime lat_p50 tput_p50

    name=$(print -- "${obj}" | jq -r '.provider_name')
    prompt_cost=$(_pi_fmt_cost "$(print -- "${obj}" | jq -r '.pricing_prompt // empty')")
    compl_cost=$(_pi_fmt_cost "$(print -- "${obj}" | jq -r '.pricing_completion // empty')")
    uptime=$(_pi_fmt_uptime "$(print -- "${obj}" | jq -r '.uptime // empty')")
    lat_p50=$(_pi_fmt_latency "$(print -- "${obj}" | jq -r '.latency_p50 // empty')")
    tput_p50=$(_pi_fmt_throughput "$(print -- "${obj}" | jq -r '.throughput_p50 // empty')")

    printf '%-18s  In: %-8s  Out: %-8s  Up: %-8s  Lat: %-7s  TP: %s' \
        "${name[1,18]}" "${prompt_cost}" "${compl_cost}" \
        "${uptime}" "${lat_p50}" "${tput_p50}"
}
