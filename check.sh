#!/usr/bin/env bash
# Print parse errors for specific scripts: ./check.sh scripts/world/machine.gd ...
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
LIST=""
for f in "$@"; do LIST="$LIST\"res://${f#./}\", "; done
cat > "$DIR/tests/_check.gd" <<GD
extends SceneTree
func _initialize():
	for f in [$LIST]:
		load(f)
	quit(0)
GD
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
"$GODOT" --headless --path "$DIR" --script res://tests/_check.gd 2>&1 \
  | grep -E "Parse Error|Failed to load" | sed 's/^ *//' | head -25
rm -f "$DIR/tests/_check.gd"
