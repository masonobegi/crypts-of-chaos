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
OUT=$("$GODOT" --headless --path "$DIR" --script res://tests/_check.gd 2>&1 \
  | grep -E "Parse Error|Failed to load" | sed 's/^ *//' | head -25)
rm -f "$DIR/tests/_check.gd"

# AND IT HAS TO FAIL. The last command in the old pipeline was `head`, which
# succeeds whether or not anything came down it — so this script exited 0 on
# every parse error it has ever printed. Anything reading the exit code, or
# skimming for silence, was told the file was fine.
if [ -n "$OUT" ]; then
  echo "$OUT"
  exit 1
fi
