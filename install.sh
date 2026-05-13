#!/usr/bin/env bash
# Installs team Claude Code commands by symlinking them into ~/.claude/commands/
# Run once after cloning: ./install.sh

set -euo pipefail

COMMANDS_DIR="$(cd "$(dirname "$0")/commands" && pwd)"
TARGET_DIR="$HOME/.claude/commands"

mkdir -p "$TARGET_DIR"

echo "Installing Claude commands from $COMMANDS_DIR → $TARGET_DIR"
echo ""

for file in "$COMMANDS_DIR"/*.md; do
  name="$(basename "$file")"
  target="$TARGET_DIR/$name"

  if [ -L "$target" ]; then
    echo "  updating symlink: $name"
  elif [ -f "$target" ]; then
    echo "  replacing existing file: $name (backup saved as $name.bak)"
    mv "$target" "$target.bak"
  else
    echo "  installing: $name"
  fi

  ln -sf "$file" "$target"
done

echo ""
echo "Done. Restart Claude Code to pick up new commands."
