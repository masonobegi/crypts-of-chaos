#!/usr/bin/env bash
# Play the game with a controller, with no renderer, at full speed.
#   GODOT=/path/to/godot ./playfast.sh [pad|keys]
#
# `keys` needs a captured mouse cursor for the look, which the dummy display
# driver will not give — use ./play.sh for that one.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
exec "$GODOT" --headless --fixed-fps 60 --path "$DIR" \
  --script res://tests/play_run.gd -- "${1:-pad}"
