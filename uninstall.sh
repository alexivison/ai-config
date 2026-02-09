#!/bin/bash
# ai-config-claude uninstaller
# Removes symlinks created by install.sh (does not remove the repo)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS=("claude" "gemini" "codex")

echo "ai-config-claude uninstaller"
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

echo "Removing symlinks..."
echo ""

for tool in "${TOOLS[@]}"; do
    remove_symlink "$tool"
done

echo ""
echo "Uninstall complete!"
echo "The ai-config-claude repo remains at: $SCRIPT_DIR"
