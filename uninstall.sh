#!/usr/bin/env bash
# Removes symlinks installed by install.sh from ~/.claude/commands/

set -euo pipefail

COMMANDS_DIR="$(cd "$(dirname "$0")/commands" && pwd)"
TARGET_DIR="$HOME/.claude/commands"

echo "Removing Claude command symlinks from $TARGET_DIR"
echo ""

for file in "$COMMANDS_DIR"/*.md; do
  name="$(basename "$file")"
  target="$TARGET_DIR/$name"

  if [ -L "$target" ]; then
    rm "$target"
    echo "  removed: $name"
  else
    echo "  skipped (not a symlink): $name"
  fi
done

echo ""
echo "Done."
