#!/usr/bin/env bash
# Run the full test suite:
#   1. unit + integration assertions
#   2. a headless shift (systems end to end, save/load round trip)
#   3. a LIVE run with real frames (NPC AI, pathing, doors, rounds, investigators)
#
# Usage: GODOT=/path/to/godot ./run_tests.sh
#
# The --import pass is not optional: adding a script with a new `class_name`
# leaves .godot/global_script_class_cache.cfg stale, and every script that
# references the new type then fails to parse with "Could not find type X".
#
# The live run uses --fixed-fps so a frame is a fixed slice of simulated time
# rather than however fast the machine happens to be. Without it the result
# depends on the host and the test is flaky.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "Godot binary not found. Set GODOT=/path/to/godot" >&2
  exit 2
fi

NOISE="RID allocations|PagedAllocator|ObjectDB instances|resources still in use|^ *at: "

"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1

"$GODOT" --headless --path "$DIR" --script res://tests/run_tests.gd
UNIT=$?

"$GODOT" --headless --path "$DIR" --script res://tests/smoke_run.gd 2>&1 | grep -vE "$NOISE"
SMOKE=${PIPESTATUS[0]}

"$GODOT" --headless --fixed-fps 60 --path "$DIR" --script res://tests/live_run.gd 2>&1 | grep -vE "$NOISE"
LIVE=${PIPESTATUS[0]}

if [ "$UNIT" -ne 0 ] || [ "$SMOKE" -ne 0 ] || [ "$LIVE" -ne 0 ]; then
  echo "TESTS FAILED (unit=$UNIT smoke=$SMOKE live=$LIVE)" >&2
  exit 1
fi
echo "ALL TESTS PASSED"
