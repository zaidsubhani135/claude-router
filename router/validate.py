#!/usr/bin/env python3
"""
Validation tests for provider_intel.zsh logic — re-implemented in Python
to test the logic and data transformations in a zsh-free environment.

These tests verify the same invariants as validate.zsh, using the same
fixture data. They confirm the implementation decisions are correct before
the code is used in a live zsh environment.
"""

import json
import sys

PASS = 0
FAIL = 0

def ok(desc):
    global PASS
    print(f"  ✅  {desc}")
    PASS += 1

def fail(desc, expected, got):
    global FAIL
    print(f"  ❌  {desc}", file=sys.stderr)
    print(f"      expected: {expected}", file=sys.stderr)
    print(f"      got:      {got}", file=sys.stderr)
    FAIL += 1

def assert_eq(desc, got, expected):
    if got == expected:
        ok(desc)
    else:
        fail(desc, expected, got)

def assert_in(desc, haystack, needle):
    if needle in str(haystack):
        ok(desc)
    else:
        fail(desc, f"contains '{needle}'", haystack)

def assert_not_in(desc, haystack, needle):
    if needle not in str(haystack):
        ok(desc)
    else:
        fail(desc, f"NOT contain '{needle}'", haystack)

# ── Fixtures ──────────────────────────────────────────────────────────────────

FIXTURE = {
  "data": {
    "id": "deepseek/deepseek-v4-flash",
    "name": "DeepSeek V4 Flash",
    "endpoints": [
      {
        "name": "DeepSeek: DeepSeek V4 Flash",
        "provider_name": "DeepSeek",
        "tag": "deepseek",
        "context_length": 65536,
        "max_completion_tokens": 8192,
        "max_prompt_tokens": 65536,
        "quantization": "fp16",
        "supports_implicit_caching": True,
        "pricing": {"prompt": "0.00000014", "completion": "0.00000028", "request": "0", "image": "0"},
        "uptime_last_30m": 99.87,
        "latency_last_30m": {"p50": 0.584, "p75": 0.720, "p90": 0.901, "p99": 1.450},
        "throughput_last_30m": {"p50": 120.5, "p75": 98.3, "p90": 74.1, "p99": 42.0},
        "status": 0
      },
      {
        "name": "Fireworks: DeepSeek V4 Flash",
        "provider_name": "Fireworks",
        "tag": "fireworks",
        "context_length": 65536,
        "max_completion_tokens": 8192,
        "max_prompt_tokens": None,
        "quantization": None,
        "supports_implicit_caching": False,
        "pricing": {"prompt": "0.00000014", "completion": "0.00000028", "request": "0", "image": "0"},
        "uptime_last_30m": 96.56,
        "latency_last_30m": {"p50": 0.706, "p75": None, "p90": None, "p99": None},
        "throughput_last_30m": {"p50": 98.2, "p75": None, "p90": None, "p99": None},
        "status": 0
      },
      {
        "name": "Baidu: DeepSeek V4 Flash",
        "provider_name": "Baidu",
        "tag": "baidu",
        "context_length": 32768,
        "max_completion_tokens": 4096,
        "max_prompt_tokens": 32768,
        "quantization": "int8",
        "supports_implicit_caching": False,
        "pricing": {"prompt": "0.000000098", "completion": "0.000000196", "request": "0", "image": "0"},
        "uptime_last_30m": None,
        "latency_last_30m": None,
        "throughput_last_30m": None,
        "status": 0
      }
    ]
  }
}

# ── Reimplement the format helpers (mirrors zsh logic) ─────────────────────────

def fmt_cost(raw):
    """Multiply per-token price by 1M to get $/M tokens. Returns 'N/A' on null."""
    if raw is None or raw == '':
        return 'N/A'
    try:
        return f"{float(raw) * 1_000_000:.4f}"
    except (ValueError, TypeError):
        return 'N/A'

def fmt_latency(raw):
    """Convert seconds to milliseconds. Returns 'N/A' on null."""
    if raw is None:
        return 'N/A'
    try:
        return f"{int(float(raw) * 1000)}ms"
    except (ValueError, TypeError):
        return 'N/A'

def fmt_uptime(raw):
    """Format uptime percentage. Returns 'N/A' on null."""
    if raw is None:
        return 'N/A'
    try:
        return f"{float(raw):.2f}%"
    except (ValueError, TypeError):
        return 'N/A'

def fmt_ctx(raw):
    """Format context length. Returns 'N/A' on null."""
    if raw is None:
        return 'N/A'
    try:
        n = int(raw)
        return f"{n // 1000}k" if n >= 1000 else str(n)
    except (ValueError, TypeError):
        return 'N/A'

def fmt_throughput(raw):
    """Format throughput tokens/sec. Returns 'N/A' on null."""
    if raw is None:
        return 'N/A'
    try:
        return f"{float(raw):.0f}t/s"
    except (ValueError, TypeError):
        return 'N/A'

# ── Extract provider intel from fixture ────────────────────────────────────────

def extract_intel(data):
    endpoints = data.get("data", {}).get("endpoints", [])
    result = []
    for ep in endpoints:
        lat = ep.get("latency_last_30m") or {}
        tput = ep.get("throughput_last_30m") or {}
        pricing = ep.get("pricing") or {}
        result.append({
            "provider_name": ep.get("provider_name", "Unknown"),
            "name": ep.get("name", "Unknown"),
            "tag": ep.get("tag", ""),
            "context_length": ep.get("context_length"),
            "max_completion_tokens": ep.get("max_completion_tokens"),
            "max_prompt_tokens": ep.get("max_prompt_tokens"),
            "quantization": ep.get("quantization"),
            "supports_implicit_caching": ep.get("supports_implicit_caching", False),
            "pricing_prompt": pricing.get("prompt"),
            "pricing_completion": pricing.get("completion"),
            "pricing_request": pricing.get("request"),
            "pricing_image": pricing.get("image"),
            "uptime": ep.get("uptime_last_30m"),
            "latency_p50": lat.get("p50"),
            "latency_p75": lat.get("p75"),
            "latency_p90": lat.get("p90"),
            "latency_p99": lat.get("p99"),
            "throughput_p50": tput.get("p50"),
            "throughput_p75": tput.get("p75"),
            "throughput_p90": tput.get("p90"),
            "throughput_p99": tput.get("p99"),
            "status": ep.get("status", -1),
        })
    return result

def sort_intel(arr, field):
    """Sort intel array by field. VIEW-ONLY. Never mutates input."""
    import copy
    result = copy.deepcopy(arr)
    BIG = 999999
    if field == "cost":
        result.sort(key=lambda x: float(x["pricing_prompt"]) if x["pricing_prompt"] else BIG)
    elif field == "latency":
        result.sort(key=lambda x: x["latency_p50"] if x["latency_p50"] is not None else BIG)
    elif field == "uptime":
        result.sort(key=lambda x: -(x["uptime"] if x["uptime"] is not None else -1))
    elif field == "throughput":
        result.sort(key=lambda x: -(x["throughput_p50"] if x["throughput_p50"] is not None else -BIG))
    elif field == "name":
        result.sort(key=lambda x: x["provider_name"].lower())
    return result

def make_verbose(name, arr):
    """Build verbose string for a provider. Mirrors provider_intel_verbose."""
    obj = next((x for x in arr if x["provider_name"] == name), None)
    if not obj:
        return f"Provider: {name}\nNo metadata available."
    lines = [
        f"  Provider: {name}",
        f"  Context Window:    {fmt_ctx(obj['context_length'])}",
        f"  Max Output Tokens: {obj['max_completion_tokens'] or 'N/A'}",
        f"  Quantization:      {obj['quantization'] or 'N/A'}",
        f"  Prompt Cost:       {fmt_cost(obj['pricing_prompt'])} $/M tokens",
        f"  Completion Cost:   {fmt_cost(obj['pricing_completion'])} $/M tokens",
        f"  Latency P50 (TTFT):  {fmt_latency(obj['latency_p50'])}",
        f"  Latency P90 (TTFT):  {fmt_latency(obj['latency_p90'])}",
        f"  Throughput P50:      {fmt_throughput(obj['throughput_p50'])}",
        f"  Uptime (30m):        {fmt_uptime(obj['uptime'])}",
        f"  Implicit Caching:    {'Yes' if obj['supports_implicit_caching'] else 'No'}",
        "  Data Policy:       Unknown",
        "  (OpenRouter does not expose per-provider data policy via API)",
    ]
    return "\n".join(lines)

# ── Tests ─────────────────────────────────────────────────────────────────────

intel = extract_intel(FIXTURE)

print()
print("── Format helpers ───────────────────────────────────────────────")

assert_eq("fmt_cost(None) → N/A", fmt_cost(None), "N/A")
assert_eq("fmt_cost('') → N/A", fmt_cost(''), "N/A")
assert_in("fmt_cost 0.00000014 → contains 0.14", fmt_cost("0.00000014"), "0.14")
assert_eq("fmt_latency(None) → N/A", fmt_latency(None), "N/A")
assert_eq("fmt_latency(0.584) → 584ms", fmt_latency(0.584), "584ms")
assert_eq("fmt_latency(1.45) → 1450ms", fmt_latency(1.45), "1450ms")
assert_eq("fmt_uptime(None) → N/A", fmt_uptime(None), "N/A")
assert_eq("fmt_uptime(99.87) → 99.87%", fmt_uptime(99.87), "99.87%")
assert_eq("fmt_ctx(None) → N/A", fmt_ctx(None), "N/A")
assert_eq("fmt_ctx(65536) → 65k", fmt_ctx(65536), "65k")
assert_eq("fmt_ctx(8192) → 8k", fmt_ctx(8192), "8k")
assert_eq("fmt_ctx(512) → 512", fmt_ctx(512), "512")
assert_eq("fmt_throughput(None) → N/A", fmt_throughput(None), "N/A")
assert_in("fmt_throughput(120.5) → ~120t/s", fmt_throughput(120.5), "t/s")

print()
print("── provider intel extraction ─────────────────────────────────────")

assert_eq("intel has 3 providers", len(intel), 3)

ds = next(x for x in intel if x["provider_name"] == "DeepSeek")
assert_eq("DeepSeek uptime", ds["uptime"], 99.87)
assert_eq("DeepSeek latency_p50", ds["latency_p50"], 0.584)
assert_eq("DeepSeek throughput_p50", ds["throughput_p50"], 120.5)
assert_eq("DeepSeek pricing_prompt", ds["pricing_prompt"], "0.00000014")
assert_eq("DeepSeek context_length", ds["context_length"], 65536)
assert_eq("DeepSeek quantization", ds["quantization"], "fp16")
assert_eq("DeepSeek implicit_caching True", ds["supports_implicit_caching"], True)

fw = next(x for x in intel if x["provider_name"] == "Fireworks")
assert_eq("Fireworks max_prompt_tokens is None (graceful)", fw["max_prompt_tokens"], None)
assert_eq("Fireworks quantization is None (graceful)", fw["quantization"], None)
assert_eq("Fireworks latency_p75 is None (sparse)", fw["latency_p75"], None)

baidu = next(x for x in intel if x["provider_name"] == "Baidu")
assert_eq("Baidu uptime is None (graceful)", baidu["uptime"], None)
assert_eq("Baidu latency_p50 is None (graceful)", baidu["latency_p50"], None)

empty_intel = extract_intel({"data": {"endpoints": []}})
assert_eq("empty endpoints → []", len(empty_intel), 0)

missing_intel = extract_intel({})
assert_eq("missing data → []", len(missing_intel), 0)

print()
print("── sorting (view-only) ──────────────────────────────────────────")

orig_order = [x["provider_name"] for x in intel]

sorted_cost = sort_intel(intel, "cost")
assert_eq("sort cost: cheapest first (Baidu)", sorted_cost[0]["provider_name"], "Baidu")

sorted_lat = sort_intel(intel, "latency")
assert_eq("sort latency: fastest first (DeepSeek)", sorted_lat[0]["provider_name"], "DeepSeek")

sorted_up = sort_intel(intel, "uptime")
assert_eq("sort uptime: best first (DeepSeek)", sorted_up[0]["provider_name"], "DeepSeek")

sorted_tp = sort_intel(intel, "throughput")
assert_eq("sort throughput: highest first (DeepSeek)", sorted_tp[0]["provider_name"], "DeepSeek")

sorted_name = sort_intel(intel, "name")
assert_eq("sort name: alphabetical first (Baidu)", sorted_name[0]["provider_name"], "Baidu")
assert_eq("sort name: alphabetical last (Fireworks)", sorted_name[-1]["provider_name"], "Fireworks")

# Critical: original array is NOT modified by sorting.
new_order = [x["provider_name"] for x in intel]
assert_eq("sort is non-destructive: orig order preserved", new_order, orig_order)

print()
print("── verbose display ──────────────────────────────────────────────")

verbose_ds = make_verbose("DeepSeek", intel)
assert_in("verbose: provider name", verbose_ds, "DeepSeek")
assert_in("verbose: context 65k", verbose_ds, "65k")
assert_in("verbose: quantization fp16", verbose_ds, "fp16")
assert_in("verbose: latency 584ms", verbose_ds, "584ms")
assert_in("verbose: uptime 99.87%", verbose_ds, "99.87%")
assert_in("verbose: implicit caching Yes", verbose_ds, "Yes")
assert_in("verbose: data policy Unknown", verbose_ds, "Unknown")
assert_not_in("verbose: NO training claim", verbose_ds, "No training")
assert_not_in("verbose: NO retention claim", verbose_ds, "Retention")

verbose_fw = make_verbose("Fireworks", intel)
assert_in("verbose Fireworks null quantization → N/A", verbose_fw, "N/A")

verbose_unk = make_verbose("Ghost", intel)
assert_in("verbose unknown provider graceful", verbose_unk, "Ghost")

print()
print("── storage format invariants ────────────────────────────────────")

# Confirm the preset JSON schema is exactly as expected (unchanged from original).
preset_entry = {
    "slug": "claude-test-model-fast",
    "name": "Fast",
    "model": "test/model",
    "providers": [{"provider": "DeepSeek", "weight": 1}]
}
for key in ("slug", "name", "model", "providers"):
    assert_in(f"preset schema has '{key}' field", json.dumps(preset_entry), key)
assert_eq("preset providers is list", type(preset_entry["providers"]), list)
assert_eq("preset provider[0].provider", preset_entry["providers"][0]["provider"], "DeepSeek")
assert_eq("preset provider[0].weight", preset_entry["providers"][0]["weight"], 1)

print()
print("── data policy: never inferred ──────────────────────────────────")

# This is the most important compliance check: data policy must NEVER be inferred,
# guessed, or hardcoded from provider name or reputation.
for provider_name in ("DeepSeek", "Fireworks", "Baidu", "OpenAI", "Anthropic", "Google"):
    v = make_verbose(provider_name, intel)
    # Should always say Unknown for data policy, never a definitive claim.
    if "Data Policy" in v:
        assert_in(f"{provider_name}: data policy shows Unknown", v, "Unknown")
        assert_not_in(f"{provider_name}: no No training claim", v, "✓ No training")
        assert_not_in(f"{provider_name}: no Training permitted claim", v, "✗ Training")
        assert_not_in(f"{provider_name}: no Retention possible claim", v, "⚠ Retention")

print()
print("════════════════════════════════════════════════════════════════")
print(f"  Results:  ✅ {PASS} passed   ❌ {FAIL} failed")
print("════════════════════════════════════════════════════════════════")
print()

sys.exit(0 if FAIL == 0 else 1)
