# 🔧 Initialize completion system
autoload -Uz compinit && compinit

# 👾 For shell tools like Claude
export PATH="$HOME/.local/bin:$PATH"

# 🪄 Pixi
export PATH="$HOME/.pixi/bin:$PATH"
eval "$(pixi completion --shell zsh)"

# 🎩 Zsh Plugin Manager
eval "$(sheldon source)"

# 🎨 ColorTheme (shared with nvim)
base16_gruvbox-dark-hard

# 🌀 zoxide
eval "$(zoxide init zsh)"

# 📝 editor
export EDITOR="nvim"
alias vi="nvim"

# 🐱 cat
alias cat="bat -pp"

# 📝 eza 
alias ls="lsd"
alias ll="lsd -l"

# 💬 discord webhook
export WEBHOOK_URL= 
