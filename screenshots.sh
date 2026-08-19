#!/usr/bin/env bash
# Render the game offscreen and photograph it from fixed vantage points.
#
#   GODOT=/path/to/godot ./screenshots.sh
#
# Uses Xvfb plus Godot's GL Compatibility renderer, because Forward+ needs a
# Vulkan device that headless boxes generally do not have. Output lands in the
# project's user:// data directory; the path is printed at the end.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not found" >&2; exit 2; }
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
exec xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --path "$DIR" --script res://tests/shot.gd
