#!/usr/bin/env bash
# Drive the real game through the real input actions and photograph it.
#   GODOT=/path/to/godot ./play.sh [plan]
# plans: first_shift (default) | walk_test | honest | reckless | careful_criminal
#        | opportunist | idiot_chaos | doors
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
PLAN="${1:-first_shift}"
command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not found" >&2; exit 2; }
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
exec xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --fixed-fps 60 --path "$DIR" --script res://tests/play_run.gd -- "$PLAN"
