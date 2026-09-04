#!/usr/bin/env bash
# Play the game through the real input actions, with a real window behind it.
#   GODOT=/path/to/godot ./play.sh [pad|keys]
#
# Xvfb and the GL Compatibility renderer, same as screenshots.sh — and unlike
# ./playfast.sh this gives the game a real display, which is the only way the
# mouse cursor can be captured and therefore the only way the `keys` plan can
# test looking around.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
PLAN="${1:-keys}"
command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not found" >&2; exit 2; }
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
exec xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --fixed-fps 60 --path "$DIR" --script res://tests/play_run.gd -- "$PLAN"
