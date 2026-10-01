#!/usr/bin/env bash
# Screenshot harness: renders a shot set from godot/harness/shots.json into docs/screens/<set>/.
# Usage: tools/shots.sh <set> [--only=a,b] [--quality=low|medium|high|ultra] [--res=1600x900]
# On a headless Linux box this wraps Godot in Xvfb with Mesa's lavapipe (software Vulkan).
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SET="$1"; shift || true
RES="1600x900"; EXTRA=()
for a in "$@"; do case "$a" in --res=*) RES="${a#--res=}";; *) EXTRA+=("$a");; esac; done
if [ "$(uname)" = "Linux" ] && [ -z "$DISPLAY" ]; then
  exec xvfb-run -a -s "-screen 0 ${RES}x24" "$ROOT/tools/godot.sh" --resolution "$RES" -- --shot="$SET" "${EXTRA[@]}"
fi
exec "$ROOT/tools/godot.sh" --resolution "$RES" -- --shot="$SET" "${EXTRA[@]}"
