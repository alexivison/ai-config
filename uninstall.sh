#!/bin/bash
# ai-config uninstaller
# Removes symlinks created by install.sh (does not remove the repo)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS=("claude" "codex")

echo "ai-config uninstaller"
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
echo "The ai-config repo remains at: $SCRIPT_DIR"
