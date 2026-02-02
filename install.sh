#!/bin/bash
# ai-config installer
# Creates symlinks from ~ to the tool config directories

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS=("claude" "gemini" "codex")

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
        return
    fi

    # Check if already correctly linked
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        echo "✓  $tool already linked correctly"
        return
    fi

    backup_existing "$target"

    ln -s "$source" "$target"
    echo "✓  Created symlink: ~/.$tool → $source"
}

echo "Installing tool configurations..."
echo ""

for tool in "${TOOLS[@]}"; do
    create_symlink "$tool"
done

echo ""
echo "Installation complete!"
echo ""
echo "Installed symlinks:"
for tool in "${TOOLS[@]}"; do
    target="$HOME/.$tool"
    if [[ -L "$target" ]]; then
        echo "  ~/.$tool → $(readlink "$target")"
    fi
done
