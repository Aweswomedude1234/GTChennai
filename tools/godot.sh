#!/usr/bin/env bash
# Run Godot on the project. Finds the binary via $GODOT, the macOS app bundle, or PATH.
# Usage: tools/godot.sh [godot args] [-- game args]
#   tools/godot.sh                               # play
#   tools/godot.sh --editor                      # open the editor
#   tools/godot.sh --headless --import           # (re)import assets
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "$GODOT" ]; then
  for c in "/Applications/Godot.app/Contents/MacOS/Godot" "$HOME/Applications/Godot.app/Contents/MacOS/Godot" "$(command -v godot || true)" "$(command -v godot4 || true)" "$HOME/tools/Godot_v4.7.2-stable_linux.x86_64" "/home/claude/tools/Godot_v4.7.2-stable_linux.x86_64"; do
    if [ -n "$c" ] && [ -x "$c" ]; then GODOT="$c"; break; fi
  done
fi
[ -z "$GODOT" ] && { echo "Godot 4.7 not found; set \$GODOT" >&2; exit 1; }
exec "$GODOT" --path "$ROOT/godot" "$@"
