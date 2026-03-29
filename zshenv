# Skip /etc/zshrc and other system-wide RC files to avoid
# compatibility errors with non-system zsh (e.g. pixi).
# /etc/zshrc assumes system zsh builtins/modules (log, zsh/mathfunc)
# that may not exist in pixi's zsh.
# Useful settings from /etc/zshrc are replicated in .zshrc instead.
unsetopt GLOBAL_RCS
