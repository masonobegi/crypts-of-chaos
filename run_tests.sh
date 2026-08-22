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

# Engine chatter that is not this project's, filtered so a REAL error is visible.
#
# `Parameter "m" is null` is one line per Label3D freed, from Godot's headless
# dummy rasterizer: it queries the surface count of a mesh that backend never
# generates. The game creates and destroys Label3Ds constantly — every nametag,
# speech bubble and floating sign — so a unit run emitted 110 of them and a
# smoke run 35, and anything genuinely wrong was buried in the middle of it.
# Verified as engine-side rather than ours: one bare Label3D added and freed in
# an otherwise empty SceneTree reproduces it exactly, and the labels render
# correctly under the real backend (see screenshots.sh).
NOISE="RID allocations|PagedAllocator|ObjectDB instances|resources still in use|^ *at: |Parameter \"m\" is null"

"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1

"$GODOT" --headless --path "$DIR" --script res://tests/run_tests.gd 2>&1 | grep -vE "$NOISE"
UNIT=${PIPESTATUS[0]}

"$GODOT" --headless --path "$DIR" --script res://tests/smoke_run.gd 2>&1 | grep -vE "$NOISE"
SMOKE=${PIPESTATUS[0]}

# The design harness. live_run.gd tested a world that no longer exists; what
# replaced it is twenty ways of playing the day measured against the six
# criteria in docs/REDESIGN.md. It exits non-zero when one of them regresses,
# which is the only automated defence against the game quietly becoming a
# formality again.
"$GODOT" --headless --path "$DIR" --script res://tests/playtest_run.gd 2>&1 | grep -vE "$NOISE"
PLAY=${PIPESTATUS[0]}

# The authored content, which the property tests do not touch: fifteen people
# across three wards, every field a system will silently default if it is
# missing, and the one inequality every ward has to satisfy.
"$GODOT" --headless --path "$DIR" --script res://tests/probe/data_run.gd 2>&1 | grep -vE "$NOISE"
DATA=${PIPESTATUS[0]}

# And finally the one route no other harness takes: the real entry point.
# Everything above instantiates Game.tscn directly, which skips Boot and the
# main menu entirely — the gap that hid both "the game is unplayable from the
# main menu" and an engine error printed on every launch.
echo ""
GODOT="$GODOT" "$DIR/boot_check.sh"
BOOT=$?

if [ "$UNIT" -ne 0 ] || [ "$SMOKE" -ne 0 ] || [ "$PLAY" -ne 0 ] || [ "$DATA" -ne 0 ] || [ "$BOOT" -ne 0 ]; then
  echo "TESTS FAILED (unit=$UNIT smoke=$SMOKE playtest=$PLAY data=$DATA boot=$BOOT)" >&2
  exit 1
fi
echo "ALL TESTS PASSED"
