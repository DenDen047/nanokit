# 🔧 Settings from /etc/zshrc (skipped via GLOBAL_RCS in .zshenv)
# UTF-8 combining characters support
if [[ ! -x /usr/bin/locale ]] || [[ "$(locale LC_CTYPE)" == "UTF-8" ]]; then
    setopt COMBINING_CHARS
fi

# 🔧 Initialize completion system
autoload -Uz compinit && compinit

# 👾 For shell tools like Claude
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"

# 🪄 Pixi
export PATH="$HOME/.pixi/bin:$PATH"
eval "$(pixi completion --shell zsh)"

# 🎩 Zsh Plugin Manager
# 2>/dev/null: suppress starship's "failed to load module: zsh/mathfunc"
# (pixi zsh lacks this module; workaround defined below)
eval "$(sheldon source)" 2>/dev/null

# Workaround: pixi zsh lacks zsh/mathfunc module needed by starship
# Redefine starship's time function without int()/rint()
if ! zmodload -e zsh/mathfunc 2>/dev/null; then
    zmodload zsh/datetime 2>/dev/null
    __starship_get_time() {
        STARSHIP_CAPTURED_TIME=$(( ${EPOCHREALTIME} * 1000 ))
        STARSHIP_CAPTURED_TIME=${STARSHIP_CAPTURED_TIME%.*}
    }
fi

# 🎨 ColorTheme (shared with nvim)
base16_gruvbox-dark-hard

# 🌀 zoxide
eval "$(zoxide init zsh)"

# 📝 editor
export EDITOR="nvim"
alias vi="nvim"
alias vim="nvim"

# 🐱 cat
alias cat="bat -pp"

# 📝 eza
alias ls="lsd"
alias ll="lsd -l"

# 🤖 Claude Code
alias cc="claude --allow-dangerously-skip-permissions"

# 📦 direnv
eval "$(direnv hook zsh)"

# 💬 discord webhook
export WEBHOOK_URL=
