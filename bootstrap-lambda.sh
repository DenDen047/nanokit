#!/bin/bash
# Bootstrap script for Lambda Cloud instances.
# Usage: curl -fsSL https://raw.githubusercontent.com/DenDen047/nanokit/main/bootstrap-lambda.sh | bash

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

step()    { echo -e "${BLUE}▶ $1${NC}"; }
ok()      { echo -e "${GREEN}✔ $1${NC}"; }
wait_msg(){ echo -e "${YELLOW}⏳ $1${NC}"; }

# --- 1. pixi ---
if command -v pixi &>/dev/null; then
    ok "pixi already installed"
else
    step "Installing pixi..."
    curl -fsSL https://pixi.sh/install.sh | bash
fi
export PATH="${HOME}/.pixi/bin:${PATH}"

# --- 2. gh CLI ---
if command -v gh &>/dev/null; then
    ok "gh already installed"
else
    step "Installing gh via pixi..."
    pixi global install gh
fi

# --- 3. GitHub auth (requires user interaction) ---
if gh auth status &>/dev/null; then
    ok "GitHub already authenticated"
else
    step "GitHub authentication required"
    echo ""
    echo "  This will open a device-code flow."
    echo "  Copy the code shown below and open the URL in your LOCAL browser."
    echo ""
    gh auth login --hostname github.com --git-protocol https --web
    echo ""

    # Verify auth succeeded
    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}Authentication failed. Re-run this script to retry.${NC}"
        exit 1
    fi
    ok "GitHub authenticated"
fi

# --- 4. git config (from GitHub profile) ---
if git config --global user.name &>/dev/null && git config --global user.email &>/dev/null; then
    ok "git config already set"
else
    step "Configuring git user from GitHub profile..."
    git config --global user.name "$(gh api user --jq .name)"
    git config --global user.email "$(gh api user/emails --jq '[.[] | select(.primary)] | .[0].email')"
    ok "git config: $(git config --global user.name) <$(git config --global user.email)>"
fi

# --- 5. nanokit ---
NANOKIT_DIR="${HOME}/nanokit"
if [[ -d "${NANOKIT_DIR}" ]]; then
    ok "nanokit already cloned"
else
    step "Cloning nanokit..."
    gh repo clone DenDen047/nanokit "${NANOKIT_DIR}"
fi

step "Running nanokit install..."
cd "${NANOKIT_DIR}"
./nanokit install
