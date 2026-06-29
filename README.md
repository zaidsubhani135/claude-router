# claude-router

A model router for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that integrates with [OpenRouter](https://openrouter.ai) to give you persistent, named, model-scoped routing presets.

## What it does

Instead of hardcoding a model, you choose one at launch time and optionally configure which providers serve it and in what priority order. Your configuration is saved locally and restored automatically on the next launch.

```
Select model  (fzf picker with metadata preview)
    ↓
Choose launch mode: Direct or Preset
    ↓
Direct → export ANTHROPIC_MODEL and launch Claude
    ↓
Preset → provider intelligence table
         → interactive provider selection
         → manage named presets
           (create / edit / rename / delete / backup / restore)
    ↓
Launch Claude
```

## Requirements

- [Zsh](https://www.zsh.org/) 5.8 or later
- [curl](https://curl.se/)
- [jq](https://stedolan.github.io/jq/) 1.6 or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude` CLI)
- An [OpenRouter](https://openrouter.ai) account
- **[fzf](https://github.com/junegunn/fzf)** (optional but strongly recommended — enables the enhanced UI; falls back to numbered menus without it)

## Installation

Clone or copy the repository anywhere on your system:

```zsh
git clone https://github.com/zaidsubhani135/claude-router ~/.local/share/claude-router
```

Add the launchers to your PATH or source them from your shell config:

```zsh
# In ~/.zshrc
source ~/.local/share/claude-router/braining
source ~/.local/share/claude-router/superpowers
```

Or symlink them:

```zsh
ln -s ~/.local/share/claude-router/braining ~/.local/bin/braining
ln -s ~/.local/share/claude-router/superpowers ~/.local/bin/superpowers
```

The `router/` directory must remain a sibling of the launcher scripts.

## Configuration

Set these environment variables before launching:

```zsh
export ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1"
export ANTHROPIC_AUTH_TOKEN="sk-or-..."   # Your OpenRouter API key
```

Add them to your `~/.zshrc` or equivalent.

### Optional variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_ROUTER_CACHE_TTL` | `900` | Model cache TTL in seconds |
| `CLAUDE_ROUTER_MODE` | *(interactive)* | Set to `direct` or `preset` to skip the mode prompt |
| `CLAUDE_ROUTER_PROFILE` | *(interactive)* | Set to `balanced` to skip the provider order prompt |
| `CLAUDE_ROUTER_DEFAULT_MODELS` | launcher-specific (see below) | Newline-joined list of default models offered in the picker. Set automatically by `braining` / `superpowers`; only set this yourself if you're invoking `claude_router` directly. |

## File locations

All data follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html):

| Path | Contents |
|---|---|
| `$XDG_CONFIG_HOME/claude-router/user-models.txt` | User-saved model list |
| `$XDG_CONFIG_HOME/claude-router/presets/<model>.json` | Per-model preset metadata |
| `$XDG_CACHE_HOME/claude-router/models.json` | OpenRouter model catalogue cache |
| `$XDG_CACHE_HOME/claude-router/endpoints/<model>.json` | Per-model endpoint cache |

Defaults to `~/.config/claude-router/` and `~/.cache/claude-router/` when XDG variables are not set.

## Enhanced UI (fzf)

When [fzf](https://github.com/junegunn/fzf) is installed, the router uses interactive menus with search, arrow-key navigation, and preview panes.

**Install fzf:**
```zsh
brew install fzf          # macOS
apt-get install fzf       # Debian/Ubuntu
dnf install fzf           # Fedora
```

Without fzf, the router automatically falls back to the original numbered-list menus with no loss of functionality. A one-time warning is printed the first time fzf is expected but absent.

## Provider Intelligence Table

When creating or editing presets, the router displays a live provider metrics table derived from cached OpenRouter endpoint data:

```
  Provider          In$/M     Out$/M    Uptime    Latency  Throughput
  ────────────────  ────────  ────────  ────────  ───────  ──────────
  DeepSeek          0.1400    0.2800    99.87%    584ms    120t/s
  Fireworks         0.1400    0.2800    96.56%    706ms    98t/s
  Baidu              0.0980    0.1960   N/A       N/A      N/A
```

**Fields displayed in the table:**
- **In$/M** — prompt cost per million tokens (USD)
- **Out$/M** — completion cost per million tokens (USD)
- **Uptime** — 30-minute uptime percentage
- **Latency** — median (P50) time to first token (TTFT)
- **Throughput** — median (P50) output tokens per second

**Additional fields captured internally** (not shown in the compact table, but available to the verbose view and to any code consuming `provider_intel_all`): request cost, image cost, P75/P90/P99 latency, P75/P90/P99 throughput, context length, max prompt/completion tokens, quantization, implicit-caching support, endpoint status, and supported parameters.

Fields are `N/A` when OpenRouter does not provide data for that provider. Values are read from the already-cached endpoint response — no additional API calls are made.

**Data Policy:** OpenRouter does not expose per-provider training or data-retention policy via its API. The verbose view shows `Unknown` for all providers. Do not rely on this router for data policy decisions; consult OpenRouter's [Privacy documentation](https://openrouter.ai/docs/guides/privacy/data-collection) and individual provider terms directly.

## Verbose Provider View

In the fzf provider picker, the preview pane shows full metadata for the highlighted provider:

```
  Provider: DeepSeek

  Context Window:    65k
  Max Output Tokens: 8192
  Quantization:      fp16

  Prompt Cost:       0.1400 $/M tokens
  Completion Cost:   0.2800 $/M tokens
  Request Cost:      N/A

  Latency P50 (TTFT):  584ms
  Latency P90 (TTFT):  901ms
  Throughput P50:      120t/s
  Uptime (30m):        99.87%
  Implicit Caching:    Yes

  Data Policy:       Unknown
  (OpenRouter does not expose per-provider data policy via API)
```

## Sorting

In the provider intelligence table, sort by pressing a key before confirming selection:

| Key | Sort by |
|-----|---------|
| `s` | Cost (cheapest first) |
| `l` | Latency (fastest first) |
| `u` | Uptime (best first) |
| `t` | Throughput (highest first) |
| `n` | Provider name (A–Z) |

Sorting affects only the table view. It never modifies stored preset priorities or routing order.

## Launchers

There are two opinionated launchers and one minimal, mode-agnostic entrypoint.

### `braining`

Launches Claude in brainstorming mode.

- **Default models:** `openrouter/auto`, `cohere/north-mini-code`, `deepseek/deepseek-v4-flash`
- Always opens the interactive model picker (`CLAUDE_ROUTER_MODEL=__pick__`)
- Sets `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` and `CLAUDE_CODE_PLAN_MODE_INTERVIEW_PHASE=1`
- Sets `SUPERPOWERS_MODIFIER`, instructing Claude to act purely as a feature-brainstorming and polishing sparring partner — no code generation, no implementation plans, no TDD tooling. It should pull project context to inform the discussion but keep all output conversational.
- Launches `claude "/brainstorming"`, or `claude "/brainstorming $*"` if arguments are passed.

### `superpowers`

Launches Claude in standard, surgical-execution mode with a larger default model list.

- **Default models:** `openrouter/auto`, `cohere/north-mini-code`, `deepseek/deepseek-v4-flash`, `xiaomi/mimo-v2.5-pro`, `deepseek/deepseek-v4-pro`
- Always opens the interactive model picker (`CLAUDE_ROUTER_MODEL=__pick__`)
- Unsets `CLAUDE_CODE_DISABLE_ADVISOR_TOOL`, `CLAUDE_CODE_PLAN_MODE_INTERVIEW_PHASE`, and `SUPERPOWERS_MODIFIER` — this undoes anything `braining` left behind if you sourced both in the same shell session.
- Launches `claude "$@"`, passing through any arguments unmodified.

### `cr`

A minimal, direct entrypoint into the router that skips both launchers' default-model lists and behavioural overrides entirely. Useful for quick model switches or for scripting around the router without Claude Code-specific configuration.

- Runs under `set -euo pipefail`
- Always opens the interactive model picker (`CLAUDE_ROUTER_MODEL=__pick__`)
- Calls `claude_router "$@"` directly and does **not** itself `exec claude` — it relies on `claude_router`'s direct/preset flow to set `ANTHROPIC_MODEL`, leaving invocation of `claude` to the caller or to whatever sources `cr`.

## Backup and restore

From the preset manager (Preset mode → `x`/📤 to export, `i`/📥 to import):

- **Export** writes a single versioned JSON file containing all user models and preset metadata.
- **Import** supports `merge` (keep existing, add imported) and `replace` (overwrite all) modes. Imported presets are automatically recreated on OpenRouter.

Default export filename: `claude-router-backup-YYYY-MM-DD.json`

## Testing

The router ships two equivalent validation suites that exercise the pure data-transform logic (provider intelligence extraction, formatting, sorting, verbose rendering, preset/backup schema invariants) against shared fixtures:

```zsh
zsh router/validate.zsh      # exercises the real zsh implementation directly
python3 router/validate.py   # re-implements and checks the same invariants in Python
```

`validate.zsh` sources the actual modules (`config.zsh`, `utils.zsh`, `provider_intel.zsh`, `preset.zsh`, `backup.zsh`, `ui.zsh`) against temporary `XDG_CACHE_HOME`/`XDG_CONFIG_HOME` directories and fixture endpoint JSON, so it also doubles as a regression check on storage and backup file formats. `validate.py` is a zsh-free sanity check on the same logic and fixtures, useful for quickly confirming intended behavior without a zsh environment. Both print a pass/fail summary and exit non-zero on any failure.

## Architecture

```
braining / superpowers / cr   (launchers — model list + Claude behaviour only; cr is minimal)
    └── router/
        ├── router_engine.zsh   (orchestrator — sources all modules, defines claude_router())
        ├── config.zsh          (constants)
        ├── utils.zsh           (die / warn / info / spinner / sanitize_slug)
        ├── cache.zsh           (model catalogue cache lifecycle)
        ├── openrouter.zsh      (REST API — curl wrappers only)
        ├── preset.zsh          (local metadata I/O + JSON payload builders)
        ├── provider_intel.zsh  (provider metadata extraction + display)
        ├── backup.zsh          (export / import)
        ├── ui.zsh              (all terminal prompts and display; fzf + fallback)
        ├── validate.zsh        (zsh validation suite, runs against real modules)
        └── validate.py         (Python re-implementation of the same validation suite)
```

Each module has exactly one responsibility. No business logic lives in the launchers. The router is fully independent of which launcher invokes it.

## License

MIT — see [LICENSE](LICENSE).
