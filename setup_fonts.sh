#!/usr/bin/bash
# Create the fonts directory if it doesn't exist 📂
mkdir -p ~/.local/share/fonts

# Change to the fonts directory 📍
cd ~/.local/share/fonts

# Download Hack Nerd Font (Regular) 🎉
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Regular/HackNerdFont-Regular.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Regular/HackNerdFontMono-Regular.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Regular/HackNerdFontPropo-Regular.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Bold/HackNerdFont-Bold.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Bold/HackNerdFontMono-Bold.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Bold/HackNerdFontPropo-Bold.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Italic/HackNerdFont-Italic.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Italic/HackNerdFontMono-Italic.ttf && \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/Hack/Italic/HackNerdFontPropo-Italic.ttf && \
echo "Hack Nerd Font downloaded! 🎨"

# Download FiraCode Nerd Font (Regular) 🎉
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Regular/FiraCodeNerdFont-Regular.ttf &&  \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Regular/FiraCodeNerdFontMono-Regular.ttf &&  \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Regular/FiraCodeNerdFontPropo-Regular.ttf &&  \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Bold/FiraCodeNerdFont-Bold.ttf &&  \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Bold/FiraCodeNerdFontMono-Bold.ttf &&  \
curl -fLO https://github.com/ryanoasis/nerd-fonts/raw/HEAD/patched-fonts/FiraCode/Bold/FiraCodeNerdFontPropo-Bold.ttf &&  \
echo "FiraCode Nerd Font downloaded! 🎨"

# Update the font cache to make sure it's available 🌟
fc-cache -fv && \
echo "Font cache updated! 💫"

# Check if the fonts are installed properly 🧐
echo "Checking Hack Nerd Font... 🔍"
fc-list | grep -i "Hack" && echo "Hack Nerd Font found! 🎉" || echo "Hack Nerd Font not found 😢"

echo "Checking FiraCode Nerd Font... 🔍"
fc-list | grep -i "FiraCode" && echo "FiraCode Nerd Font found! 🎉" || echo "FiraCode Nerd Font not found 😢"

# Final confirmation 🎉
echo "Hack and FiraCode Nerd Fonts are installed and ready! 🚀"
