#!/usr/bin/env bash
# Removes symlinks installed by install.sh from ~/.claude/

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMANDS_SRC="$REPO_DIR/commands"
SKILLS_SRC="$REPO_DIR/skills"
COMMANDS_TARGET="$HOME/.claude/commands"
SKILLS_TARGET="$HOME/.claude/skills"

# ── Commands ──────────────────────────────────────────────────────────────────
echo "Removing command symlinks from $COMMANDS_TARGET"

for file in "$COMMANDS_SRC"/*.md; do
  name="$(basename "$file")"
  target="$COMMANDS_TARGET/$name"

  if [ -L "$target" ]; then
    rm "$target"
    echo "  removed: $name"
  else
    echo "  skipped (not a symlink): $name"
  fi
done

# ── Skills ────────────────────────────────────────────────────────────────────
echo ""
echo "Removing skill symlinks from $SKILLS_TARGET"

for dir in "$SKILLS_SRC"/*/; do
  name="$(basename "$dir")"
  target="$SKILLS_TARGET/$name"

  if [ -L "$target" ]; then
    rm "$target"
    echo "  removed: $name"
  else
    echo "  skipped (not a symlink): $name"
  fi
done

echo ""
echo "Done."
