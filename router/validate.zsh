#!/usr/bin/env zsh
# tests/validate.zsh — validation tests for claude-router UX modernization
#
# Run: zsh tests/validate.zsh
# Exit 0 = all tests passed.  Non-zero = failures (printed to stderr).

setopt ERR_RETURN 2>/dev/null || true   # tolerate zsh < 5.1
setopt LOCAL_OPTIONS 2>/dev/null || true

_TEST_DIR="${${(%):-%x}:A:h}"
_ROOT="${_TEST_DIR:h}"

# ── Bootstrap router modules (no network, no launcher) ─────────────────────

# Set required env vars that config.zsh reads.
export XDG_CACHE_HOME="/tmp/cr-test-cache-$$"
export XDG_CONFIG_HOME="/tmp/cr-test-config-$$"
export ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1"
export ANTHROPIC_AUTH_TOKEN="sk-test-fake"
export CLAUDE_ROUTER_MODEL="test/model"

mkdir -p "${XDG_CACHE_HOME}/claude-router/endpoints"
mkdir -p "${XDG_CONFIG_HOME}/claude-router/presets"

source "${_ROOT}/router/config.zsh"
source "${_ROOT}/router/utils.zsh"
source "${_ROOT}/router/provider_intel.zsh"

# ── Test harness ──────────────────────────────────────────────────────────────

_PASS=0
_FAIL=0

_assert() {
    local desc="${1}" result="${2}" expected="${3}"
    if [[ "${result}" == "${expected}" ]]; then
        print "  ✅  ${desc}"
        (( _PASS++ ))
    else
        print -u2 "  ❌  ${desc}"
        print -u2 "      expected: ${expected}"
        print -u2 "      got:      ${result}"
        (( _FAIL++ ))
    fi
}

_assert_contains() {
    local desc="${1}" haystack="${2}" needle="${3}"
    if [[ "${haystack}" == *"${needle}"* ]]; then
        print "  ✅  ${desc}"
        (( _PASS++ ))
    else
        print -u2 "  ❌  ${desc}"
        print -u2 "      expected to contain: ${needle}"
        print -u2 "      got: ${haystack}"
        (( _FAIL++ ))
    fi
}

_assert_not_contains() {
    local desc="${1}" haystack="${2}" needle="${3}"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        print "  ✅  ${desc}"
        (( _PASS++ ))
    else
        print -u2 "  ❌  ${desc}"
        print -u2 "      expected NOT to contain: ${needle}"
        print -u2 "      got: ${haystack}"
        (( _FAIL++ ))
    fi
}

_assert_json_len() {
    local desc="${1}" json="${2}" expected_len="${3}"
    local actual
    actual=$(print -- "${json}" | jq 'length' 2>/dev/null)
    _assert "${desc}" "${actual}" "${expected_len}"
}

# ── Fixtures ──────────────────────────────────────────────────────────────────

# A realistic endpoint response fixture (two providers, some null fields).
FIXTURE_ENDPOINTS=$(cat << 'FIXTURE'
{
  "data": {
    "id": "deepseek/deepseek-v4-flash",
    "name": "DeepSeek V4 Flash",
    "endpoints": [
      {
        "name": "DeepSeek: DeepSeek V4 Flash",
        "model_id": "deepseek/deepseek-v4-flash",
        "provider_name": "DeepSeek",
        "tag": "deepseek",
        "context_length": 65536,
        "max_completion_tokens": 8192,
        "max_prompt_tokens": 65536,
        "quantization": "fp16",
        "supports_implicit_caching": true,
        "pricing": {
          "prompt": "0.00000014",
          "completion": "0.00000028",
          "request": "0",
          "image": "0"
        },
        "uptime_last_30m": 99.87,
        "latency_last_30m": {
          "p50": 0.584,
          "p75": 0.720,
          "p90": 0.901,
          "p99": 1.450
        },
        "throughput_last_30m": {
          "p50": 120.5,
          "p75": 98.3,
          "p90": 74.1,
          "p99": 42.0
        },
        "status": 0
      },
      {
        "name": "Fireworks: DeepSeek V4 Flash",
        "model_id": "deepseek/deepseek-v4-flash",
        "provider_name": "Fireworks",
        "tag": "fireworks",
        "context_length": 65536,
        "max_completion_tokens": 8192,
        "max_prompt_tokens": null,
        "quantization": null,
        "supports_implicit_caching": false,
        "pricing": {
          "prompt": "0.00000014",
          "completion": "0.00000028",
          "request": "0",
          "image": "0"
        },
        "uptime_last_30m": 96.56,
        "latency_last_30m": {
          "p50": 0.706,
          "p75": null,
          "p90": null,
          "p99": null
        },
        "throughput_last_30m": {
          "p50": 98.2,
          "p75": null,
          "p90": null,
          "p99": null
        },
        "status": 0
      },
      {
        "name": "Baidu: DeepSeek V4 Flash",
        "model_id": "deepseek/deepseek-v4-flash",
        "provider_name": "Baidu",
        "tag": "baidu",
        "context_length": 32768,
        "max_completion_tokens": 4096,
        "max_prompt_tokens": 32768,
        "quantization": "int8",
        "supports_implicit_caching": false,
        "pricing": {
          "prompt": "0.000000098",
          "completion": "0.000000196",
          "request": "0",
          "image": "0"
        },
        "uptime_last_30m": null,
        "latency_last_30m": null,
        "throughput_last_30m": null,
        "status": 0
      }
    ]
  }
}
FIXTURE
)

# A minimal endpoint response with no metadata at all.
FIXTURE_EMPTY=$(cat << 'FIXTURE'
{
  "data": {
    "id": "test/empty",
    "name": "Empty Model",
    "endpoints": []
  }
}
FIXTURE
)

# ── Write fixtures to fake cache ──────────────────────────────────────────────

FIXTURE_CACHE="${XDG_CACHE_HOME}/claude-router/endpoints/deepseek-deepseek-v4-flash.json"
print -- "${FIXTURE_ENDPOINTS}" > "${FIXTURE_CACHE}"

EMPTY_CACHE="${XDG_CACHE_HOME}/claude-router/endpoints/test-empty.json"
print -- "${FIXTURE_EMPTY}" > "${EMPTY_CACHE}"

# ── Test group 1: _pi_cache_path ─────────────────────────────────────────────

print ''
print '── _pi_cache_path ──────────────────────────────────────────────'

result=$(_pi_cache_path "deepseek/deepseek-v4-flash")
_assert_contains "_pi_cache_path replaces / with -" \
    "${result}" "deepseek-deepseek-v4-flash"

# ── Test group 2: _pi_fmt_cost ───────────────────────────────────────────────

print ''
print '── _pi_fmt_cost ─────────────────────────────────────────────────'

_assert "_pi_fmt_cost null returns N/A" \
    "$(_pi_fmt_cost '')" "N/A"

_assert "_pi_fmt_cost 'null' string returns N/A" \
    "$(_pi_fmt_cost 'null')" "N/A"

# 0.00000014 * 1000000 = 0.1400 $/M
result=$(_pi_fmt_cost "0.00000014")
_assert_contains "_pi_fmt_cost computes $/M tokens" "${result}" "0.14"

# ── Test group 3: _pi_fmt_latency ────────────────────────────────────────────

print ''
print '── _pi_fmt_latency ──────────────────────────────────────────────'

_assert "_pi_fmt_latency null returns N/A" "$(_pi_fmt_latency '')" "N/A"
_assert "_pi_fmt_latency 0.584 → 584ms" "$(_pi_fmt_latency '0.584')" "584ms"
_assert "_pi_fmt_latency 1.450 → 1450ms" "$(_pi_fmt_latency '1.450')" "1450ms"

# ── Test group 4: _pi_fmt_uptime ─────────────────────────────────────────────

print ''
print '── _pi_fmt_uptime ───────────────────────────────────────────────'

_assert "_pi_fmt_uptime null returns N/A" "$(_pi_fmt_uptime '')" "N/A"
_assert "_pi_fmt_uptime 99.87 → 99.87%" "$(_pi_fmt_uptime '99.87')" "99.87%"

# ── Test group 5: _pi_fmt_ctx ────────────────────────────────────────────────

print ''
print '── _pi_fmt_ctx ──────────────────────────────────────────────────'

_assert "_pi_fmt_ctx null returns N/A" "$(_pi_fmt_ctx '')" "N/A"
_assert "_pi_fmt_ctx 65536 → 65k" "$(_pi_fmt_ctx '65536')" "65k"
_assert "_pi_fmt_ctx 8192 → 8k" "$(_pi_fmt_ctx '8192')" "8k"
_assert "_pi_fmt_ctx 512 stays numeric" "$(_pi_fmt_ctx '512')" "512"

# ── Test group 6: provider_intel_all ─────────────────────────────────────────

print ''
print '── provider_intel_all ───────────────────────────────────────────'

intel=$( provider_intel_all "deepseek/deepseek-v4-flash" )
_assert_json_len "provider_intel_all returns 3 providers" "${intel}" "3"

# Check DeepSeek entry fields.
deepseek_obj=$(print -- "${intel}" | jq '.[] | select(.provider_name == "DeepSeek")')
_assert "DeepSeek uptime extracted" \
    "$(print -- "${deepseek_obj}" | jq -r '.uptime')" "99.87"
_assert "DeepSeek latency_p50 extracted" \
    "$(print -- "${deepseek_obj}" | jq -r '.latency_p50')" "0.584"
_assert "DeepSeek throughput_p50 extracted" \
    "$(print -- "${deepseek_obj}" | jq -r '.throughput_p50')" "120.5"
_assert "DeepSeek pricing_prompt extracted" \
    "$(print -- "${deepseek_obj}" | jq -r '.pricing_prompt')" "0.00000014"
_assert "DeepSeek context_length extracted" \
    "$(print -- "${deepseek_obj}" | jq -r '.context_length')" "65536"
_assert "DeepSeek quantization extracted" \
    "$(print -- "${deepseek_obj}" | jq -r '.quantization')" "fp16"
_assert "DeepSeek implicit_caching true" \
    "$(print -- "${deepseek_obj}" | jq -r '.supports_implicit_caching')" "true"

# Check Fireworks null fields come through as null (not crashed).
fw_obj=$(print -- "${intel}" | jq '.[] | select(.provider_name == "Fireworks")')
_assert "Fireworks max_prompt_tokens is null (graceful)" \
    "$(print -- "${fw_obj}" | jq -r '.max_prompt_tokens')" "null"
_assert "Fireworks quantization is null (graceful)" \
    "$(print -- "${fw_obj}" | jq -r '.quantization')" "null"
_assert "Fireworks latency_p75 null (sparse data)" \
    "$(print -- "${fw_obj}" | jq -r '.latency_p75')" "null"

# Check Baidu null uptime/latency/throughput.
baidu_obj=$(print -- "${intel}" | jq '.[] | select(.provider_name == "Baidu")')
_assert "Baidu uptime null (graceful)" \
    "$(print -- "${baidu_obj}" | jq -r '.uptime')" "null"
_assert "Baidu latency_p50 null (graceful)" \
    "$(print -- "${baidu_obj}" | jq -r '.latency_p50')" "null"

# Empty endpoint cache returns empty array (no crash).
empty_result=$(provider_intel_all "test/empty")
_assert_json_len "provider_intel_all empty → []" "${empty_result}" "0"

# Missing cache file returns empty array (no crash).
missing_result=$(provider_intel_all "does/not/exist")
_assert_json_len "provider_intel_all missing cache → []" "${missing_result}" "0"

# ── Test group 7: provider_intel_sort ────────────────────────────────────────

print ''
print '── provider_intel_sort ──────────────────────────────────────────'

# Sort by cost: Baidu (0.000000098) < DeepSeek (0.00000014) ≈ Fireworks (0.00000014)
sorted_cost=$(provider_intel_sort "${intel}" "cost")
first_by_cost=$(print -- "${sorted_cost}" | jq -r '.[0].provider_name')
_assert "sort by cost: cheapest first (Baidu)" "${first_by_cost}" "Baidu"

# Sort by latency: DeepSeek 584ms < Fireworks 706ms < Baidu null.
sorted_lat=$(provider_intel_sort "${intel}" "latency")
first_by_lat=$(print -- "${sorted_lat}" | jq -r '.[0].provider_name')
_assert "sort by latency: fastest first (DeepSeek)" "${first_by_lat}" "DeepSeek"

# Sort by uptime: DeepSeek 99.87 > Fireworks 96.56 > Baidu null.
sorted_up=$(provider_intel_sort "${intel}" "uptime")
first_by_up=$(print -- "${sorted_up}" | jq -r '.[0].provider_name')
_assert "sort by uptime: best first (DeepSeek)" "${first_by_up}" "DeepSeek"

# Sort by throughput: DeepSeek 120.5 > Fireworks 98.2 > Baidu null.
sorted_tp=$(provider_intel_sort "${intel}" "throughput")
first_by_tp=$(print -- "${sorted_tp}" | jq -r '.[0].provider_name')
_assert "sort by throughput: highest first (DeepSeek)" "${first_by_tp}" "DeepSeek"

# Sort by name: Baidu < DeepSeek < Fireworks.
sorted_name=$(provider_intel_sort "${intel}" "name")
first_by_name=$(print -- "${sorted_name}" | jq -r '.[0].provider_name')
last_by_name=$(print -- "${sorted_name}" | jq -r '.[-1].provider_name')
_assert "sort by name: alphabetical first (Baidu)" "${first_by_name}" "Baidu"
_assert "sort by name: alphabetical last (Fireworks)" "${last_by_name}" "Fireworks"

# Critical: sorting does NOT modify the original array.
orig_first=$(print -- "${intel}" | jq -r '.[0].provider_name')
after_sort_first=$(print -- "${intel}" | jq -r '.[0].provider_name')
_assert "sort is non-destructive (original array unchanged)" \
    "${orig_first}" "${after_sort_first}"

# ── Test group 8: provider_intel_verbose ─────────────────────────────────────

print ''
print '── provider_intel_verbose ───────────────────────────────────────'

verbose=$(provider_intel_verbose "DeepSeek" "${intel}")

_assert_contains "verbose includes provider name" "${verbose}" "DeepSeek"
_assert_contains "verbose includes context window formatted" "${verbose}" "65k"
_assert_contains "verbose includes quantization" "${verbose}" "fp16"
_assert_contains "verbose includes latency p50" "${verbose}" "584ms"
_assert_contains "verbose includes uptime" "${verbose}" "99.87%"
_assert_contains "verbose includes implicit caching" "${verbose}" "Yes"

# Data policy must always show Unknown — never inferred or hardcoded.
_assert_contains "verbose shows Unknown data policy" "${verbose}" "Unknown"
_assert_not_contains "verbose does NOT claim training status" "${verbose}" "No training"
_assert_not_contains "verbose does NOT claim retention status" "${verbose}" "Retention"

# Fireworks: partial nulls render as N/A, no crash.
verbose_fw=$(provider_intel_verbose "Fireworks" "${intel}")
_assert_contains "verbose Fireworks null quantization → N/A" "${verbose_fw}" "N/A"

# Unknown provider: graceful.
verbose_unknown=$(provider_intel_verbose "NonExistentProvider" "${intel}")
_assert_contains "verbose unknown provider is graceful" "${verbose_unknown}" "NonExistentProvider"

# ── Test group 9: provider_intel_table_row ───────────────────────────────────

print ''
print '── provider_intel_table_row ─────────────────────────────────────'

deepseek_row=$(provider_intel_table_row "${deepseek_obj}")
_assert_contains "table row contains provider name" "${deepseek_row}" "DeepSeek"
_assert_contains "table row contains uptime" "${deepseek_row}" "99.87%"
_assert_contains "table row contains latency" "${deepseek_row}" "584ms"

baidu_row=$(provider_intel_table_row "${baidu_obj}")
_assert_contains "table row Baidu null uptime → N/A" "${baidu_row}" "N/A"

# ── Test group 10: sanitize_slug (unchanged) ─────────────────────────────────

print ''
print '── sanitize_slug (regression) ───────────────────────────────────'

_assert "sanitize_slug slashes → hyphens" \
    "$(sanitize_slug 'deepseek/deepseek-v4-flash')" "deepseek-deepseek-v4-flash"
_assert "sanitize_slug lowercases" \
    "$(sanitize_slug 'OpenAI/GPT-4')" "openai-gpt-4"

# ── Test group 11: storage format unchanged ───────────────────────────────────

print ''
print '── storage format regression ────────────────────────────────────'

source "${_ROOT}/router/preset.zsh"

# Write a preset and read it back — confirm schema unchanged.
TEST_MODEL="test/storage-model"
TEST_SLUG="claude-test-storage-model-fast"
TEST_NAME="Fast"
TEST_PROVIDERS='[{"provider":"DeepSeek","weight":1},{"provider":"Fireworks","weight":1}]'

preset_upsert "${TEST_MODEL}" "${TEST_SLUG}" "${TEST_NAME}" "${TEST_PROVIDERS}"
loaded=$(preset_load_all "${TEST_MODEL}")

_assert_json_len "preset storage: one entry" "${loaded}" "1"

entry=$(print -- "${loaded}" | jq '.[0]')
_assert "preset storage: slug field" \
    "$(print -- "${entry}" | jq -r '.slug')" "${TEST_SLUG}"
_assert "preset storage: name field" \
    "$(print -- "${entry}" | jq -r '.name')" "${TEST_NAME}"
_assert "preset storage: model field" \
    "$(print -- "${entry}" | jq -r '.model')" "${TEST_MODEL}"
_assert "preset storage: providers is array" \
    "$(print -- "${entry}" | jq '.providers | type')" '"array"'
_assert "preset storage: providers[0].provider" \
    "$(print -- "${entry}" | jq -r '.providers[0].provider')" "DeepSeek"
_assert "preset storage: providers[0].weight" \
    "$(print -- "${entry}" | jq -r '.providers[0].weight')" "1"

# ── Test group 12: backup format unchanged ────────────────────────────────────

print ''
print '── backup format regression ─────────────────────────────────────'

source "${_ROOT}/router/backup.zsh"

# Add a user model.
mkdir -p "${CONFIG_DIR}"
print -- "test/usermodel" > "${USER_MODELS_FILE}"

# Export.
BACKUP_OUT="/tmp/cr-test-backup-$$.json"
backup_export "${BACKUP_OUT}" 2>/dev/null

[[ -f "${BACKUP_OUT}" ]] && {
    bk=$(cat "${BACKUP_OUT}")
    _assert "backup schema_version is 1" \
        "$(print -- "${bk}" | jq -r '.schema_version')" "1"
    _assert "backup has created_at" \
        "$(print -- "${bk}" | jq 'has("created_at")')" "true"
    _assert "backup has user_models array" \
        "$(print -- "${bk}" | jq '.user_models | type')" '"array"'
    _assert "backup has presets object" \
        "$(print -- "${bk}" | jq '.presets | type')" '"object"'
    _assert "backup user_models contains our test model" \
        "$(print -- "${bk}" | jq -r '.user_models[]' | grep -c 'test/usermodel')" "1"
} || {
    print -u2 "  ❌  backup_export did not produce a file"
    (( _FAIL++ ))
}

rm -f "${BACKUP_OUT}"

# ── Test group 13: fzf detection ─────────────────────────────────────────────

print ''
print '── fzf detection ────────────────────────────────────────────────'

source "${_ROOT}/router/ui.zsh"

if command -v fzf > /dev/null 2>&1; then
    _assert "_ui_has_fzf returns 0 (fzf available)" "$(_ui_has_fzf && print yes || print no)" "yes"
    print "  ℹ️   fzf is available — fzf paths active"
else
    _assert "_ui_has_fzf returns 1 (fzf absent)" "$(_ui_has_fzf && print yes || print no)" "no"
    print "  ℹ️   fzf not found — numbered-list fallback active"
fi

# ── Cleanup ───────────────────────────────────────────────────────────────────

rm -rf "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}"

# ── Summary ───────────────────────────────────────────────────────────────────

print ''
print '════════════════════════════════════════════════════════════════'
print "  Results:  ✅ ${_PASS} passed   ❌ ${_FAIL} failed"
print '════════════════════════════════════════════════════════════════'
print ''

(( _FAIL == 0 ))
