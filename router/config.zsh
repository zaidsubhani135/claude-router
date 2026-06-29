#!/usr/bin/env zsh
# config.zsh — constants only, nothing executable

# ── XDG-compliant paths ───────────────────────────────────────────────────────

CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/claude-router"
CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/claude-router"

# ── Cache files ───────────────────────────────────────────────────────────────

CACHE_FILE="${CACHE_DIR}/models.json"
CACHE_TIMESTAMP="${CACHE_DIR}/models.timestamp"
CACHE_TTL="${CLAUDE_ROUTER_CACHE_TTL:-900}"

# ── User data ─────────────────────────────────────────────────────────────────

USER_MODELS_FILE="${CONFIG_DIR}/user-models.txt"
PRESETS_DIR="${CONFIG_DIR}/presets"

# ── OpenRouter ────────────────────────────────────────────────────────────────

PRESET_PREFIX="claude"
OPENROUTER_API="https://openrouter.ai/api/v1"

# ── Default models ────────────────────────────────────────────────────────────

if (( ! ${+CLAUDE_ROUTER_DEFAULT_MODELS} )); then
  typeset -ga CLAUDE_ROUTER_DEFAULT_MODELS=(
    "openrouter/free"
  )
fi

# ── Backup ────────────────────────────────────────────────────────────────────

BACKUP_SCHEMA_VERSION="1"
