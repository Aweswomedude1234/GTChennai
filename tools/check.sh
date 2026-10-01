#!/usr/bin/env bash
# Parse-check every GDScript file (autoload identifiers are expected to be unresolved here).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/godot"
"$ROOT/tools/godot.sh" --headless --import >/dev/null 2>&1
fail=0
for f in $(find scripts -name '*.gd'); do
  out=$("$ROOT/tools/godot.sh" --headless --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|at: GDScript" | grep -vE "Identifier not found: (Settings|Audio)|Failed to compile depended" )
  if echo "$out" | grep -q "SCRIPT ERROR"; then echo "== $f"; echo "$out" | head -4; fail=1; fi
done
exit $fail
