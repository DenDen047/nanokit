# nanokit

Dotfile & development environment manager. Config files here are symlinked to `$HOME` via dotter.

## Design principles

- **pixi-only**: All shell tools are managed exclusively through `pixi global` + conda-forge. Do NOT use cargo install, pip install, go install, or brew to add tools. If a tool isn't on conda-forge, it should be packaged with `rattler-build` and contributed to conda-forge.
- **Declarative & portable**: `pixi-global.toml` is the single source of truth. `pixi global sync` reproduces the entire tool environment anywhere.
- **No sudo**: Everything installs to `$HOME/.pixi`. No system-level dependencies.
- **Cross-platform**: Must work on Linux (x86_64/aarch64) and macOS. Windows is optional.

## Key commands

```bash
./nanokit install        # Full setup: dotter deploy + pixi global sync
./nanokit claude-setup   # Claude Code config + plugin install
./nanokit uninstall      # Remove symlinks and tools
dotter deploy            # Symlink dotfiles only
dotter undeploy          # Remove symlinks only
pixi global sync         # Install/sync tools from pixi-global.toml
```

## Gotchas

- Files in this repo are symlinked to their targets (see `.dotter/global.toml`). Editing `zshrc` here directly changes `~/.zshrc`.
- `claude/` directory files are symlinked to `~/.claude/`. Changes affect the global Claude Code config immediately.
- The `nanokit` CLI is a Bash script. Always run uninstall from system bash, not pixi-installed zsh.
- pixi-installed zsh should NOT be set as login shell -- if pixi env breaks, login becomes impossible.
