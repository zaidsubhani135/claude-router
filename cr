#!/usr/bin/env zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"

source "${SCRIPT_DIR}/router/router_engine.zsh"

export CLAUDE_ROUTER_MODEL="__pick__"

claude_router "$@"
