#!/usr/bin/env bash
# Run the full test suite: unit/integration assertions, then a headless
# playthrough that boots the real game scene and plays a whole shift.
#
# Usage: GODOT=/path/to/godot ./run_tests.sh
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

"$GODOT" --headless --path "$DIR" --script res://tests/run_tests.gd
UNIT=$?

"$GODOT" --headless --path "$DIR" --script res://tests/smoke_run.gd 2>&1 \
  | grep -vE "RID allocations|PagedAllocator|ObjectDB instances|resources still in use|^ *at: "
SMOKE=${PIPESTATUS[0]}

if [ "$UNIT" -ne 0 ] || [ "$SMOKE" -ne 0 ]; then
  echo "TESTS FAILED (unit=$UNIT smoke=$SMOKE)" >&2
  exit 1
fi
echo "ALL TESTS PASSED"
