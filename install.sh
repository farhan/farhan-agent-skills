#!/usr/bin/env bash
# Installs team Claude Code commands and skills by symlinking them into ~/.claude/
# Run once after cloning: ./install.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
COMMANDS_SRC="$REPO_DIR/commands"
SKILLS_SRC="$REPO_DIR/skills"
COMMANDS_TARGET="$HOME/.claude/commands"
SKILLS_TARGET="$HOME/.claude/skills"

# ── Commands ──────────────────────────────────────────────────────────────────
mkdir -p "$COMMANDS_TARGET"
echo "Installing commands: $COMMANDS_SRC → $COMMANDS_TARGET"

for file in "$COMMANDS_SRC"/*.md; do
  name="$(basename "$file")"
  target="$COMMANDS_TARGET/$name"

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

# ── Skills ────────────────────────────────────────────────────────────────────
mkdir -p "$SKILLS_TARGET"
echo ""
echo "Installing skills: $SKILLS_SRC → $SKILLS_TARGET"

for dir in "$SKILLS_SRC"/*/; do
  name="$(basename "$dir")"
  target="$SKILLS_TARGET/$name"

  if [ -L "$target" ]; then
    echo "  updating symlink: $name"
  elif [ -d "$target" ]; then
    echo "  replacing existing directory: $name (backup saved as $name.bak)"
    mv "$target" "$target.bak"
  else
    echo "  installing: $name"
  fi

  ln -sf "$dir" "$target"
done

echo ""
echo "Done. Restart Claude Code to pick up new commands and skills."
