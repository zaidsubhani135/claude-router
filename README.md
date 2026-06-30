# claude-router

A terminal tool that picks Claude Code's model and provider routing through OpenRouter, with live cost/latency/uptime data and reusable presets.

## What is Claude Router?

Claude Router is a small zsh tool that runs right before `claude` starts. It lets you choose which model Claude Code uses (via [OpenRouter](https://openrouter.ai)), see a live comparison of every provider available for that model, set a priority order between them, and save that order as a named preset.

Presets aren't local-only settings. Claude Router creates and manages them as real preset resources on your OpenRouter account, using OpenRouter's own preset API. They persist independently of this tool — once created, a preset is addressable as `@preset/<slug>` from any OpenRouter-compatible client, not just from Claude Router.

Claude Router never wraps, proxies, or modifies Claude Code itself. It sets a couple of environment variables (`ANTHROPIC_MODEL`, and the OpenRouter base URL/token you've already configured) and then runs the real `claude` binary via `exec`.

## What problem does it solve?

Claude Code normally talks to a single, fixed model. Routing it through OpenRouter unlocks many models, and for each model, multiple providers that can serve it — each with different cost, latency, and uptime. OpenRouter doesn't remember your provider priority between sessions on its own, and reconfiguring it by hand, every time you want to switch, gets tedious fast.

Claude Router puts that choice in front of you at launch time, with the data you need to make it (cost in/out per million tokens, 30-minute uptime, latency, throughput), and lets you save the result so you don't redo it.

## Who is it for?

Claude Code users who route through OpenRouter (or want to) and find themselves switching models or re-picking provider priority often enough that doing it by hand is annoying.

If you only ever use one fixed model and don't care which provider serves it, you probably don't need this.

## Why not just use Claude Code directly?

You can — Claude Router doesn't replace Claude Code, it launches it. Plain Claude Code is the right choice if a single hardcoded model is fine for you. Claude Router is for the case where you want to choose between models and providers at launch time, see the cost/performance tradeoffs before choosing, and not lose that choice between sessions.

## Why OpenRouter?

OpenRouter exposes a single API across many model providers, including multiple providers for the same model, each with its own pricing, latency, and uptime. Claude Router's job is to make that choice (model, provider, priority) visible and repeatable instead of one-off and manual. It doesn't work without OpenRouter — OpenRouter is what gives it something to route between, and OpenRouter is also where the presets actually live.

## Why launchers?

Different workflows want different defaults — a brainstorming session might want a cheap, fast model and different Claude Code behavior than a session doing precise code edits. Rather than duplicating routing logic per workflow, Claude Router separates the two concerns: the **router** (`router/`) does model/provider selection and preset management the same way no matter how it's invoked, and a **launcher** is a small script that sets a few environment variables for one workflow and hands off to the router. Writing a new workflow means writing a new launcher, not touching the router.

## At a Glance

- Pick a model from OpenRouter's catalogue (autocomplete, validation, your own saved list)
- See live per-provider cost, uptime, latency, and throughput before choosing
- Save a provider priority order as a named preset — created on your OpenRouter account, not just locally
- Reuse a preset at launch instead of re-picking providers
- Export/import your local preset list as a single JSON file (import recreates presets on OpenRouter)
- Write your own launcher in ~15 lines to set defaults for a specific workflow

## How does it work?

```
Select model  (fzf picker with metadata preview)
    ↓
Choose launch mode: Direct or Preset
    ↓
Direct → export ANTHROPIC_MODEL and launch Claude
         (no provider control — OpenRouter's own default routing applies)
    ↓
Preset → provider intelligence table (cost, uptime, latency, throughput)
         → interactive provider priority ordering
         → creates/updates a real preset on OpenRouter
         → manage named presets locally
           (create / edit / rename / delete / backup / restore)
    ↓
Launch Claude — with ANTHROPIC_MODEL=@preset/<slug>
```

`cr` is the primary launcher — it opens the model picker and hands off to Claude with no extra configuration. Other launchers (`extras/launchers/`) layer workflow-specific defaults on top of the same router; see [Creating Custom Launchers](#creating-custom-launchers) below.

## Requirements

- [Zsh](https://www.zsh.org/) 5.8 or later
- [curl](https://curl.se/)
- [jq](https://stedolan.github.io/jq/) 1.6 or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude` CLI)
- An [OpenRouter](https://openrouter.ai) account
- **[fzf](https://github.com/junegunn/fzf)** (optional but strongly recommended — enables the enhanced UI; falls back to numbered menus without it)

## Getting Started

Clone the repository anywhere on your system:

```zsh
git clone https://github.com/zaidsubhani135/claude-router ~/.local/share/claude-router
```

Set your OpenRouter credentials (add these to `~/.zshrc` or equivalent):

```zsh
export ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1"
export ANTHROPIC_AUTH_TOKEN="sk-or-..."   # Your OpenRouter API key
```

Run the primary launcher, `cr`, directly, or put it on your `PATH`:

```zsh
~/.local/share/claude-router/launchers/cr
# or
ln -s ~/.local/share/claude-router/launchers/cr ~/.local/bin/cr
```

That's it — `cr` picks a model, runs the router, and launches `claude` in one step. No further setup is required. The `router/` directory must remain a sibling of `launchers/` at the repo root.

Without a launcher overriding it, the model picker's default offering is `openrouter/free`. Most users will want to add their own models via the picker's "manage" menu, or use a launcher that sets `CLAUDE_ROUTER_DEFAULT_MODELS`.

### Optional environment variables

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_ROUTER_CACHE_TTL` | `900` | Model cache TTL in seconds |
| `CLAUDE_ROUTER_MODE` | *(interactive)* | Set to `direct` or `preset` to skip the mode prompt |
| `CLAUDE_ROUTER_PROFILE` | *(interactive)* | Set to `balanced` to skip the provider order prompt |
| `CLAUDE_ROUTER_DEFAULT_MODELS` | `openrouter/free` | Newline-joined list of default models offered in the picker. Set automatically by `braining` / `superpowers`; only set this yourself if invoking `claude_router` directly. |

### Enhanced UI (fzf)

When [fzf](https://github.com/junegunn/fzf) is installed, the router uses interactive menus with search, arrow-key navigation, and preview panes. Without it, the router falls back to numbered-list menus with no loss of functionality (a one-time warning is printed the first time fzf is expected but absent).

```zsh
brew install fzf          # macOS
apt-get install fzf       # Debian/Ubuntu
dnf install fzf           # Fedora
```

## Creating Custom Launchers

A launcher's only job is to pick a model and hand off to the router. The router never reads launcher-specific state — only the `CLAUDE_ROUTER_*` and `ANTHROPIC_*` variables documented above — so you can write a new launcher without touching anything under `router/`.

The full contract:

1. *(optional)* Set `CLAUDE_ROUTER_DEFAULT_MODELS` — a newline-joined list of model ids to offer in the picker. Omit to use the router's built-in default (`openrouter/free`).
2. Set `CLAUDE_ROUTER_MODEL` — usually `__pick__` to open the interactive picker, or a specific model id to skip it.
3. Source `router/router_engine.zsh` and call `claude_router`.
4. On success, `exec claude "$@"` (or a custom invocation, as `braining` does with its slash-command).

Nothing else is required. The easiest way to start is to copy the documented skeleton:

```zsh
cp extras/launchers/template launchers/my-launcher
chmod +x launchers/my-launcher
```

`extras/launchers/template` implements the contract above with nothing else added, and is meant to be copied and edited.

### Active vs. example launchers

Only `launchers/` is treated as the project's active set of standalone, executable launchers — `cr` lives there and can be run or symlinked directly. `extras/launchers/` holds examples and templates (`braining`, `superpowers`, `template`); nothing there runs as a standalone executable on its own.

`braining` and `superpowers` are meant to be `source`d into your shell rather than executed, since `superpowers` undoes env vars `braining` sets in the same session. Because of that, "activating" them by copying into `launchers/` is optional and only affects discoverability — they work identically whether sourced from `extras/launchers/` directly or from a copy in `launchers/`:

```zsh
# In ~/.zshrc
source ~/.local/share/claude-router/extras/launchers/braining
source ~/.local/share/claude-router/extras/launchers/superpowers
```

### Example launchers

- **`cr`** (`launchers/`) — the primary entrypoint. No default model list, no behavioral overrides. Runs under `set -euo pipefail`, always opens the interactive picker, and on success runs `exec claude "$@"`. Has no dependencies beyond what's listed in Requirements.

- **`braining`** (`extras/launchers/`) — brainstorming-mode example. Offers a small default model list and sets Claude Code env vars (`CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1`, `CLAUDE_CODE_PLAN_MODE_INTERVIEW_PHASE=1`, `SUPERPOWERS_MODIFIER`) that keep Claude in a conversational, no-code-generation mode, then launches `claude "/brainstorming"`. **This launcher assumes a `/brainstorming` slash command and a `SUPERPOWERS_MODIFIER`-aware setup are already configured in your Claude Code environment** (the "Superpowers" plugin convention) — it is not runnable as-is on a vanilla Claude Code install. Treat it as a template for building your own workflow-specific launcher rather than a ready-to-use tool. Meant to be `source`d, since its env vars are intended to persist in your shell session.

- **`superpowers`** (`extras/launchers/`) — the counterpart to `braining`, not a standalone feature. It uses a larger default model list, unsets the env vars `braining` sets (returning to standard execution mode), and launches `claude "$@"` with arguments passed through unmodified. The name refers to the same plugin convention `braining` depends on, not an independent capability of Claude Router. Also meant to be `source`d.

- **`template`** (`extras/launchers/`) — a documented skeleton implementing the full launcher contract with nothing else added. The recommended starting point if you want to write your own launcher: copy it into `launchers/` and you don't need to read anything under `router/`.

## Repository Structure

```
launchers/                       (active — only launchers here run as standalone scripts)
    └── cr                       (primary entrypoint — no defaults, no overrides)
extras/launchers/                (examples and templates)
    ├── braining                 (example — assumes the Superpowers plugin convention)
    ├── superpowers               (example — undoes braining's overrides)
    └── template                  (start here to write your own)
router/
    ├── router_engine.zsh   (orchestrator — sources all modules, defines claude_router())
    ├── config.zsh          (constants)
    ├── utils.zsh           (die / warn / info / spinner / sanitize_slug)
    ├── cache.zsh           (model catalogue cache lifecycle)
    ├── openrouter.zsh      (REST API — curl wrappers; creates/deletes real OpenRouter presets)
    ├── preset.zsh          (local metadata I/O + JSON payload builders)
    ├── provider_intel.zsh  (provider metadata extraction + display)
    ├── backup.zsh          (export / import — import recreates presets on OpenRouter)
    ├── ui.zsh              (all terminal prompts and display; fzf + fallback)
    ├── validate.zsh        (zsh validation suite, runs against real modules)
    └── validate.py         (Python re-implementation of the same validation suite)
```

Each module has exactly one responsibility. No business logic lives in the launchers — they only set environment variables and hand off. The router is fully independent of which launcher invokes it.

## Reference

### File locations

All data follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html):

| Path | Contents |
|---|---|
| `$XDG_CONFIG_HOME/claude-router/user-models.txt` | User-saved model list |
| `$XDG_CONFIG_HOME/claude-router/presets/<model>.json` | Local mirror of preset metadata — display/edit convenience only; the presets themselves live on OpenRouter |
| `$XDG_CACHE_HOME/claude-router/models.json` | OpenRouter model catalogue cache |
| `$XDG_CACHE_HOME/claude-router/endpoints/<model>.json` | Per-model endpoint cache |

Defaults to `~/.config/claude-router/` and `~/.cache/claude-router/` when XDG variables are not set.

### Provider intelligence table

When creating or editing presets, the router displays a live provider metrics table derived from cached OpenRouter endpoint data:

```
  Provider          In$/M     Out$/M    Uptime    Latency  Throughput
  ────────────────  ────────  ────────  ────────  ───────  ──────────
  DeepSeek          0.1400    0.2800    99.87%    584ms    120t/s
  Fireworks         0.1400    0.2800    96.56%    706ms    98t/s
  Baidu              0.0980    0.1960   N/A       N/A      N/A
```

- **In$/M** — prompt cost per million tokens (USD)
- **Out$/M** — completion cost per million tokens (USD)
- **Uptime** — 30-minute uptime percentage
- **Latency** — median (P50) time to first token (TTFT)
- **Throughput** — median (P50) output tokens per second

Additional fields are captured internally (not shown in the compact table, but available in the verbose view): request cost, image cost, P75/P90/P99 latency, P75/P90/P99 throughput, context length, max prompt/completion tokens, quantization, implicit-caching support, endpoint status, and supported parameters. Fields are `N/A` when OpenRouter doesn't provide data for that provider. No additional API calls are made — values are read from the already-cached endpoint response.

**Data policy:** OpenRouter does not expose per-provider training or data-retention policy via its API. The verbose view shows `Unknown` for all providers. Don't rely on this router for data policy decisions — consult OpenRouter's [Privacy documentation](https://openrouter.ai/docs/guides/privacy/data-collection) and individual provider terms directly.

### Verbose provider view

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

### Sorting

In the provider intelligence table, sort by pressing a key before confirming selection:

| Key | Sort by |
|-----|---------|
| `s` | Cost (cheapest first) |
| `l` | Latency (fastest first) |
| `u` | Uptime (best first) |
| `t` | Throughput (highest first) |
| `n` | Provider name (A–Z) |

Sorting affects only the table view. It never modifies stored preset priorities or routing order.

### Backup and restore

From the preset manager (Preset mode → `x`/📤 to export, `i`/📥 to import):

- **Export** writes a single versioned JSON file containing all locally tracked user models and preset metadata. This is a read of local state only — no network calls are made.
- **Import** is a networked operation: it supports `merge` (keep existing, add imported) and `replace` (overwrite all) modes for local metadata, and for every imported preset it also calls OpenRouter's API to recreate that preset on your account. A bad or unexpected import can create or overwrite real presets on OpenRouter, not just local files.

Default export filename: `claude-router-backup-YYYY-MM-DD.json`

### Testing

The router ships two equivalent validation suites that exercise the pure data-transform logic (provider intelligence extraction, formatting, sorting, verbose rendering, preset/backup schema invariants) against shared fixtures:

```zsh
zsh router/validate.zsh      # exercises the real zsh implementation directly
python3 router/validate.py   # re-implements and checks the same invariants in Python
```

`validate.zsh` sources the actual modules (`config.zsh`, `utils.zsh`, `provider_intel.zsh`, `preset.zsh`, `backup.zsh`, `ui.zsh`) against temporary `XDG_CACHE_HOME`/`XDG_CONFIG_HOME` directories and fixture endpoint JSON, so it also doubles as a regression check on storage and backup file formats. `validate.py` is a zsh-free sanity check on the same logic and fixtures, useful for quickly confirming intended behavior without a zsh environment. Both print a pass/fail summary and exit non-zero on any failure.

## License

MIT — see [LICENSE](LICENSE).
