# claude-router

A model router for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) that integrates with [OpenRouter](https://openrouter.ai) to give you persistent, named, model-scoped routing presets.

## What it does

Instead of hardcoding a model, you choose one at launch time and optionally configure which providers serve it and in what priority order. Your configuration is saved locally and restored automatically on the next launch.

```
Select model
    ↓
Choose launch mode: Direct or Preset
    ↓
Direct → export ANTHROPIC_MODEL and launch Claude
    ↓
Preset → manage named presets for the selected model
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

The router directory (`router/`) must remain a sibling of the launcher scripts. The installation path does not matter — all module resolution is relative.

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

## File locations

All data follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html):

| Path | Contents |
|---|---|
| `$XDG_CONFIG_HOME/claude-router/user-models.txt` | User-saved model list |
| `$XDG_CONFIG_HOME/claude-router/presets/<model>.json` | Per-model preset metadata |
| `$XDG_CACHE_HOME/claude-router/models.json` | OpenRouter model catalogue cache |
| `$XDG_CACHE_HOME/claude-router/endpoints/<model>.json` | Per-model endpoint cache |

Defaults to `~/.config/claude-router/` and `~/.cache/claude-router/` when XDG variables are not set.

## Launchers

### `braining`

Launches Claude in brainstorming mode. Disables the advisor tool and plan mode interview phase. Sets a `SUPERPOWERS_MODIFIER` that instructs Claude to act as a feature debate partner rather than a code generator.

### `superpowers`

Launches Claude in standard execution mode with an expanded default model list.

## Backup and restore

From the preset manager (Preset mode → `x` to export, `i` to import):

- **Export** writes a single versioned JSON file containing all user models and preset metadata.
- **Import** supports `merge` (keep existing, add imported) and `replace` (overwrite all) modes. Imported presets are automatically recreated on OpenRouter.

Default export filename: `claude-router-backup-YYYY-MM-DD.json`

## Architecture

```
braining / superpowers     (thin launchers — model list + Claude behaviour only)
    └── router/
        ├── router_engine.zsh   (orchestrator — sources all modules, defines claude_router())
        ├── config.zsh          (constants)
        ├── utils.zsh           (die / warn / info / spinner / sanitize_slug)
        ├── cache.zsh           (model catalogue cache lifecycle)
        ├── openrouter.zsh      (REST API — curl wrappers only)
        ├── preset.zsh          (local metadata I/O + JSON payload builders)
        ├── backup.zsh          (export / import)
        └── ui.zsh              (all terminal prompts and display)
```

Each module has exactly one responsibility. No business logic lives in the launchers. The router is fully independent of which launcher invokes it.

## License

MIT — see [LICENSE](LICENSE).
