#!/bin/bash
# ai-party uninstaller
# Removes symlinks created by install.sh (does not remove the repo)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS=("claude" "codex")

echo "ai-party uninstaller"
echo "====================="
echo ""

remove_symlink() {
    local tool="$1"
    local source="$SCRIPT_DIR/$tool"
    local target="$HOME/.$tool"

    if [[ ! -L "$target" ]]; then
        echo "⏭  Skipping ~/.$tool (not a symlink)"
        return
    fi

    if [[ "$(readlink "$target")" != "$source" ]]; then
        echo "⏭  Skipping ~/.$tool (points elsewhere: $(readlink "$target"))"
        return
    fi

    rm "$target"
    echo "✓  Removed symlink: ~/.$tool"
}

remove_file_symlink() {
    local source="$1"
    local target="$2"
    local label="$3"

    if [[ ! -L "$target" ]]; then
        echo "⏭  Skipping $label (not a symlink)"
        return
    fi

    if [[ "$(readlink "$target")" != "$source" ]]; then
        echo "⏭  Skipping $label (points elsewhere: $(readlink "$target"))"
        return
    fi

    rm "$target"
    echo "✓  Removed symlink: $label"
}

echo "Removing symlinks..."
echo ""

for tool in "${TOOLS[@]}"; do
    remove_symlink "$tool"
done

# Pi has no repo-tracked config symlink. The pi binary was installed via
# `npm install -g @mariozechner/pi-coding-agent`; user data lives in
# ~/.pi/agent/ (settings.json, auth.json, sessions/). Leave both untouched.
if command -v pi &> /dev/null; then
    echo ""
    echo "ℹ  pi CLI was installed via npm and is not removed by this script."
    echo "   To remove: npm uninstall -g @mariozechner/pi-coding-agent"
    echo "   User data (~/.pi/agent/) is preserved."
fi

echo ""
echo "Uninstall complete!"
echo "The ai-party repo remains at: $SCRIPT_DIR"
