# nanokit agent instructions

Dotfile & development environment manager. Config files here are symlinked to `$HOME` via dotter.
This file is the repository instruction source; `AGENTS.md` is a symlink to it.

## Design principles

- **pixi-only**: All shell tools are managed exclusively through `pixi global` + conda-forge. Do NOT use cargo install, pip install, go install, or brew to add tools. If a tool isn't on conda-forge, it should be packaged with `rattler-build` and contributed to conda-forge.
- **Declarative & portable**: `pixi-global.toml` is the single source of truth. `pixi global sync` reproduces the entire tool environment anywhere.
- **No sudo**: Everything installs to `$HOME/.pixi`. No system-level dependencies.
- **Cross-platform**: Must work on Linux (x86_64/aarch64) and macOS. Windows is optional.

## Key commands

```bash
./nanokit deploy         # Apply every config change: dotter deploy + agent-config-sync (--diff previews)
./nanokit install        # Full setup: dotter deploy + pixi global sync
./nanokit claude-setup   # Claude Code config + plugin install
./nanokit agent-config-sync  # Shared Claude Code / Codex instructions, skills, and Codex config
./nanokit uninstall      # Remove symlinks and tools
dotter deploy            # Symlink dotfiles only
dotter undeploy          # Remove symlinks only
pixi global sync         # Install/sync tools from pixi-global.toml
```

`./nanokit deploy` is the default way to reflect an edit made in this repo — it covers both distribution mechanisms below, so there is no need to remember which one a given file uses. It works from any directory and is safe to re-run.

## Agent config distribution

`claude/CLAUDE.md` and `claude/skills/*` are the global agent sources. Two mechanisms distribute them, and `./nanokit deploy` runs both:

- **dotter** symlinks tool-specific files under `~/.claude/` (scripts, output styles, ccstatusline config). The mappings live in `.dotter/global.toml` — that file is the source of truth, do not restate it elsewhere. Reflect changes with `dotter deploy`.
- **`./nanokit agent-config-sync`** distributes the shared instructions, skills, Codex config, and `settings.json`. It symlinks `claude/CLAUDE.md` → `~/.codex/AGENTS.md` and each `claude/skills/<name>` → both `~/.claude/skills/<name>` and `~/.agents/skills/<name>`. A `SessionStart` hook (`agent-config-sync-reconnect.sh`) re-runs it idempotently every session: **silent on success, `systemMessage` warning only when something is out of sync** (added after skill distribution silently drifted in 2026-07). `sync-config.py` does not abort the whole run on one collision — it skips that item, distributes the rest, and reports explicitly (`rc=2`).

Individual skill mappings do not belong in `.dotter/global.toml`; `agent-config-sync` discovers every directory containing `SKILL.md`.

### `settings.json` is merged, not symlinked

`~/.claude/settings.json` is a file **Claude Code itself owns and writes**. Every UI change (`/model`, `/vim`, output style, plugin enable) and key normalization rewrites it via atomic replace, which destroys a symlink (it becomes a regular file). So it is not under dotter: `agent-config-sync` (`settings_change()` in `codex/sync-config.py`) merges **nanokit's declared keys into live as the authority**, the same model as Codex `config.toml`.

- Top-level keys declared by the source win. **Live-only app-authored keys (`hasCompletedOnboarding`, `skillOverrides`, …) are preserved** — no data loss.
- The `SessionStart` hook self-heals this every session, so a diverged live file needs **no manual repair**.
- Implication: changing a managed key inside the app reverts at the next sync. To make a change permanent, **edit nanokit's `settings.json`** (single source).

```bash
# Manual reflection (normally unnecessary — SessionStart does it)
./nanokit deploy        # --diff to preview
```

### Codex config

Codex's portable settings (`model`, `model_reasoning_effort`, `approval_policy`, `web_search`, …) are managed here too. Edit `codex/config.toml`; reflect with `./nanokit agent-config-sync` (`--diff` previews). The live file can't be a symlink because the Codex desktop app writes host-specific state (`[projects.*]` trust levels) back into it, and nanokit is a public repo — so the sync upserts only the managed keys idempotently and preserves other sections. `codex-install` runs it automatically.

On a new host the Codex plugin is declared in `claude/settings.json` via `extraKnownMarketplaces` + `enabledPlugins`. If it doesn't install itself, run `claude plugin install codex@openai-codex`; register the MCP with `./nanokit codex-install`.

## Gotchas

- Files in this repo are symlinked to their targets (see `.dotter/global.toml`). Editing `zshrc` here directly changes `~/.zshrc`.
- The `nanokit` CLI is a Bash script. Always run uninstall from system bash, not pixi-installed zsh.
- pixi-installed zsh should NOT be set as login shell -- if pixi env breaks, login becomes impossible.
