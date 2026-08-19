#!/usr/bin/env bash
# Timing-only playthrough: no renderer, no screenshots, runs at full speed.
#   GODOT=/path/to/godot ./playfast.sh [plan]
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
exec "$GODOT" --headless --fixed-fps 60 --path "$DIR" \
  --script res://tests/play_run.gd -- "${1:-walk_test}"
