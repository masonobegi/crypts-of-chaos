#!/usr/bin/env bash
# SIX FACES, CLOSE UP. An art pass on a character needs a picture of a face at
# the distance a player sees one, and neither of the other two harnesses gives
# you that: `screenshots.sh` is twenty-one frames and twenty minutes, and
# `look.sh`'s lineup renders a head sixty pixels tall.
#
#   GODOT=/path/to/godot ./faces.sh <tag>
#
# Seven frames: six portraits at eighty-five centimetres, then the whole cast
# together. Output lands under user://faces/, named by the tag so two passes
# can be compared side by side.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not found" >&2; exit 2; }
export FACES_TAG="${1:-x}"
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
# CAPTURED, TESTED, AND EXITED ON — see CLAUDE.md 21.
OUT=$(timeout 1200 xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --path "$DIR" --script res://tests/faces_run.gd 2>&1)
echo "$OUT" | grep -E "face:|faces done|SCRIPT ERROR|Parse Error|SHADER ERROR|Shader compilation"
if echo "$OUT" | grep -q "SHADER ERROR\|Shader compilation failed"; then
  echo "faces.sh: a shader did not compile" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "faces done"; then
  echo "faces.sh: rendered nothing" >&2
  exit 1
fi
