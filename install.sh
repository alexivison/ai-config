#!/bin/bash
# ai-party installer
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

echo "ai-party installer"
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

create_file_symlink() {
    local source="$1"
    local target="$2"
    local label="$3"

    if [[ ! -f "$source" ]]; then
        echo "⏭  Skipping $label (source file not found)"
        return 1
    fi

    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        echo "✓  $label already linked"
        return 0
    fi

    backup_existing "$target"
    ln -s "$source" "$target"
    echo "✓  Created symlink: $target → $source"
    return 0
}

append_configured_agent() {
    local name="$1"
    local existing

    [[ -n "$name" ]] || return 0
    for existing in "${CONFIGURED_AGENTS[@]:-}"; do
        if [[ "$existing" == "$name" ]]; then
            return 0
        fi
    done
    CONFIGURED_AGENTS+=("$name")
}

run_agent_query() {
    local mode="$1"

    if command -v party-cli &> /dev/null; then
        party-cli agent query "$mode" 2>/dev/null
        return $?
    fi

    if command -v go &> /dev/null && [[ -f "$SCRIPT_DIR/tools/party-cli/main.go" ]]; then
        go -C "$SCRIPT_DIR/tools/party-cli" run . agent query "$mode" 2>/dev/null
        return $?
    fi

    return 1
}

query_configured_agents() {
    local mode

    for mode in primary-name companion-name; do
        run_agent_query "$mode" || true
    done
}

detect_configured_agents() {
    CONFIGURED_AGENTS=()

    while IFS= read -r name; do
        append_configured_agent "$name"
    done < <(query_configured_agents || true)

    if [[ ${#CONFIGURED_AGENTS[@]} -eq 0 ]]; then
        CONFIGURED_AGENTS=(claude codex)
    fi
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
        if command -v brew &> /dev/null; then
            prompt_install "claude" \
                "brew install --cask claude-code" \
                "brew install --cask claude-code"
        else
            echo "⚠  Install Claude Code from your package manager or anthropic.com"
        fi
    else
        echo "✓  claude CLI already installed"
    fi

    if command -v claude &> /dev/null; then
        prompt_auth "claude" "settings.local.json"
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
# PI
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PI_NPM_PACKAGE="@mariozechner/pi-coding-agent"
PI_REQUIRED_PACKAGES=("npm:pi-subagents")

setup_pi() {
    echo ""
    echo "━━━ pi ━━━"

    create_symlink "pi" || return

    if [[ "$SYMLINKS_ONLY" == true ]]; then
        return
    fi

    if ! command -v pi &> /dev/null; then
        if ! command -v npm &> /dev/null; then
            echo "⚠  npm not found. Install Node.js (e.g. brew install node) and re-run."
            return
        fi
        prompt_install "pi" \
            "npm install -g $PI_NPM_PACKAGE" \
            "npm install -g $PI_NPM_PACKAGE" || return
    else
        echo "✓  pi CLI already installed"
    fi

    if ! command -v pi &> /dev/null; then
        return
    fi

    local installed_packages
    installed_packages="$(pi list 2>/dev/null || true)"
    local pkg
    for pkg in "${PI_REQUIRED_PACKAGES[@]}"; do
        if grep -Fq "$pkg" <<< "$installed_packages"; then
            echo "✓  pi package already installed: $pkg"
        else
            echo "📦 Installing pi package: $pkg"
            if pi install "$pkg"; then
                echo "✓  Installed pi package: $pkg"
            else
                echo "⚠  Failed to install pi package: $pkg"
            fi
        fi
    done

    prompt_auth "pi" "agent/auth.json"
}

setup_agent() {
    case "$1" in
        claude) setup_claude ;;
        codex) setup_codex ;;
        pi) setup_pi ;;
        *)
            echo ""
            echo "━━━ $1 ━━━"

            if [[ -d "$SCRIPT_DIR/$1" ]]; then
                create_symlink "$1" || true
            fi

            if [[ "$SYMLINKS_ONLY" == true ]]; then
                return
            fi

            if command -v "$1" &> /dev/null; then
                echo "✓  $1 CLI already installed"
            else
                echo "⚠  No installer recipe for agent '$1'. Install its CLI manually."
            fi
            ;;
    esac
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# TMUX
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_tmux() {
    echo ""
    echo "━━━ tmux ━━━"
}


# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# PARTY-CLI (built from tools/party-cli)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_party_cli() {
    echo ""
    echo "━━━ party-cli ━━━"

    if [[ "$SYMLINKS_ONLY" == true ]]; then
        return
    fi

    if command -v party-cli &> /dev/null; then
        echo "✓  party-cli already installed"
        return
    fi

    if ! command -v go &> /dev/null; then
        if command -v brew &> /dev/null; then
            prompt_install "go" \
                "brew install go" \
                "brew install go" || {
                echo "⚠  Skipping party-cli build (Go required)"
                return
            }
        else
            echo "⚠  Go not found. Install from https://go.dev/dl/ and re-run."
            return
        fi
    fi

    echo "Building party-cli..."
    if make -C "$SCRIPT_DIR/tools/party-cli" install; then
        echo "✓  party-cli installed to ~/.local/bin/party-cli"
        case ":$PATH:" in
            *":$HOME/.local/bin:"*) ;;
            *) echo "⚠  ~/.local/bin is not on PATH. Add it to your shell rc." ;;
        esac
    else
        echo "⚠  party-cli build failed"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# FZF (interactive session picker)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setup_fzf() {
    echo ""
    echo "━━━ fzf ━━━"

    if [[ "$SYMLINKS_ONLY" == true ]]; then
        return
    fi

    if command -v fzf &> /dev/null; then
        echo "✓  fzf already installed"
    elif command -v brew &> /dev/null; then
        prompt_install "fzf" \
            "brew install fzf" \
            "brew install fzf"
    else
        echo "⚠  fzf not found. Install with: brew install fzf"
        echo "   (Used for interactive party session picker)"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# MAIN
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
CONFIGURED_AGENTS=()
detect_configured_agents

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
echo "Agents to check: ${CONFIGURED_AGENTS[*]}"
echo ""
read -p "Continue? [Y/n] " -n 1 -r
echo
if [[ $REPLY =~ ^[Nn]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

pi_already_setup=false
for agent_name in "${CONFIGURED_AGENTS[@]}"; do
    setup_agent "$agent_name"
    [[ "$agent_name" == "pi" ]] && pi_already_setup=true
done
if [[ "$pi_already_setup" == false ]]; then
    setup_pi
fi
setup_tmux
setup_party_cli
setup_fzf

echo ""
echo "━━━━━━━━━━━━━━━━━━━━"
echo "Installation complete!"
echo ""
echo "Installed symlinks:"
printed_pi_symlink=false
for tool in "${CONFIGURED_AGENTS[@]}"; do
    target="$HOME/.$tool"
    if [[ -L "$target" ]]; then
        echo "  ~/.$tool → $(readlink "$target")"
        [[ "$tool" == "pi" ]] && printed_pi_symlink=true
    fi
done
if [[ "$printed_pi_symlink" == false && -L "$HOME/.pi" ]]; then
    echo "  ~/.pi → $(readlink "$HOME/.pi")"
fi
if [[ -L "$HOME/.tmux.conf" ]]; then
    echo "  ~/.tmux.conf → $(readlink "$HOME/.tmux.conf")"
fi
