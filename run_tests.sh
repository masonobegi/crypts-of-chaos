#!/usr/bin/env bash
# Run the headless test suite. Point GODOT at a Godot 4.3+ binary.
#
# The --import pass is not optional: adding a script with a new `class_name`
# leaves .godot/global_script_class_cache.cfg stale, and every script that
# references the new type then fails to parse with "Could not find type X".
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "Godot binary not found. Set GODOT=/path/to/godot" >&2
  exit 2
fi
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
exec "$GODOT" --headless --path "$DIR" --script res://tests/run_tests.gd
