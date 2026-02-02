#!/bin/bash
# ai-config installer
# Installs CLI tools, creates symlinks, and handles authentication

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMLINKS_ONLY=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --symlinks-only)
            SYMLINKS_ONLY=true
            shift
            ;;
        -h|--help)
            echo "Usage: ./install.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --symlinks-only  Only create config symlinks, skip CLI installation"
            echo "  -h, --help       Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Run './install.sh --help' for usage"
            exit 1
            ;;
    esac
done

echo "ai-config installer"
echo "==================="
echo "Repo location: $SCRIPT_DIR"
echo ""

backup_existing() {
    local target="$1"
    local backup="${target}.backup.$(date +%Y%m%d_%H%M%S)"

    if [[ -L "$target" ]]; then
        echo "  Removing existing symlink: $target"
        rm "$target"
    elif [[ -e "$target" ]]; then
        echo "  Backing up existing directory: $target → $backup"
        mv "$target" "$backup"
    fi
}

create_symlink() {
    local tool="$1"
    local source="$SCRIPT_DIR/$tool"
    local target="$HOME/.$tool"

    if [[ ! -d "$source" ]]; then
        echo "⏭  Skipping $tool (source directory not found)"
        return 1
    fi

    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        echo "✓  $tool config already linked"
        return 0
    fi

    backup_existing "$target"
    ln -s "$source" "$target"
    echo "✓  Created symlink: ~/.$tool → $source"
    return 0
}

prompt_install() {
    local tool="$1"
    local install_cmd="$2"
    local install_desc="$3"

    echo "📦 $tool CLI not found."
    echo "   Install via: $install_desc"
    read -p "   Run install? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Installing..."
        eval "$install_cmd"
        echo "✓  $tool CLI installed"
        return 0
    else
        echo "⏭  Skipping $tool CLI installation"
        return 1
    fi
}

prompt_auth() {
    local tool="$1"
    local auth_file="$2"
    local config_dir="$HOME/.$tool"

    if [[ -f "$config_dir/$auth_file" ]]; then
        echo "✓  $tool already authenticated"
        return 0
    fi

    echo "🔐 $tool needs authentication."
    read -p "   Run $tool to authenticate? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "   Starting $tool... (complete auth flow, then exit)"
        echo ""
        $tool || true
        echo ""
        echo "✓  $tool authentication complete"
        return 0
    else
        echo "⏭  Skipping $tool authentication"
        return 1
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CLAUDE
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_claude() {
    echo ""
    echo "━━━ claude ━━━"

    create_symlink "claude" || return

    if [[ "$SYMLINKS_ONLY" == true ]]; then
        return
    fi

    if ! command -v claude &> /dev/null; then
        prompt_install "claude" \
            "curl -fsSL https://cli.anthropic.com/install.sh | sh" \
            "curl installer (cli.anthropic.com)"
    else
        echo "✓  claude CLI already installed"
    fi

    if command -v claude &> /dev/null; then
        prompt_auth "claude" "settings.local.json"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# GEMINI
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_gemini() {
    echo ""
    echo "━━━ gemini ━━━"

    create_symlink "gemini" || return

    if [[ "$SYMLINKS_ONLY" == true ]]; then
        return
    fi

    if ! command -v gemini &> /dev/null; then
        if command -v npm &> /dev/null; then
            prompt_install "gemini" \
                "npm install -g @google/gemini-cli" \
                "npm install -g @google/gemini-cli"
        else
            echo "⚠  npm not found. Install Node.js first, then run:"
            echo "   npm install -g @google/gemini-cli"
        fi
    else
        echo "✓  gemini CLI already installed"
    fi

    if command -v gemini &> /dev/null; then
        prompt_auth "gemini" "oauth_creds.json"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# CODEX
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_codex() {
    echo ""
    echo "━━━ codex ━━━"

    create_symlink "codex" || return

    if [[ "$SYMLINKS_ONLY" == true ]]; then
        return
    fi

    if ! command -v codex &> /dev/null; then
        if command -v brew &> /dev/null; then
            prompt_install "codex" \
                "brew install --cask codex" \
                "brew install --cask codex"
        else
            echo "⚠  Homebrew not found. Install from:"
            echo "   https://github.com/openai/codex/releases"
        fi
    else
        echo "✓  codex CLI already installed"
    fi

    if command -v codex &> /dev/null; then
        prompt_auth "codex" "auth.json"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [[ "$SYMLINKS_ONLY" == true ]]; then
    echo "This installer will:"
    echo "  1. Create config symlinks"
    echo ""
    echo "(CLI installation skipped with --symlinks-only)"
else
    echo "This installer will:"
    echo "  1. Create config symlinks"
    echo "  2. Install CLI tools (optional)"
    echo "  3. Set up authentication (optional)"
fi
echo ""
read -p "Continue? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

setup_claude
setup_gemini
setup_codex

echo ""
echo "━━━━━━━━━━━━━━━━━━━━"
echo "Installation complete!"
echo ""
echo "Installed symlinks:"
for tool in claude gemini codex; do
    target="$HOME/.$tool"
    if [[ -L "$target" ]]; then
        echo "  ~/.$tool → $(readlink "$target")"
    fi
done
