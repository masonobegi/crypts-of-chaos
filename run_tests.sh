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

# ...AND ON TWO WARDS IT HAS NEVER SEEN.
#
# A ward is five people drawn from a pool of ten per day, so the first ward
# alone can deal thirty-two boards — and every check in smoke_impl.gd used to
# name its patients ("oduya", "marchetti", "blake"), which meant the whole file
# could only ever run against one of them. Pointing it anywhere else produced
# eight failures that were all the harness naming somebody who was not there.
#
# Two extra seeds, quietly, and only the verdict is printed: the point is that
# the game works on a board nobody has looked at, not to read it three times.
SMOKE_SEEDS=0
for s in 1 12345; do
  out=$(SMOKE_SEED="$s" "$GODOT" --headless --path "$DIR" \
    --script res://tests/smoke_run.gd 2>&1)
  code=$?
  line=$(echo "$out" | grep -E "SMOKE RUN (PASSED|FAILED)" | head -1)
  echo "  seed $s: $line"
  if [ "$code" -ne 0 ]; then
    echo "$out" | grep -A20 "SMOKE RUN FAILED" | sed 's/^/    /'
    SMOKE_SEEDS=1
  fi
done

# The design harness. live_run.gd tested a world that no longer exists; what
# replaced it is twenty ways of playing the day measured against the six
# criteria in docs/REDESIGN.md. It exits non-zero when one of them regresses,
# which is the only automated defence against the game quietly becoming a
# formality again.
"$GODOT" --headless --path "$DIR" --script res://tests/playtest_run.gd 2>&1 | grep -vE "$NOISE"
PLAY=${PIPESTATUS[0]}

# The authored content, which the property tests do not touch: every person on
# every ward, drawn or not, every field a system will silently default if it is
# missing, and the one inequality every ward has to satisfy.
"$GODOT" --headless --path "$DIR" --script res://tests/probe/data_run.gd 2>&1 | grep -vE "$NOISE"
DATA=${PIPESTATUS[0]}

# EVERY WARD A CAREER CAN DEAL, played honestly. A ward is a draw from a pool
# now, so the game can deal a board nobody has ever looked at; this walks all of
# them and asserts an honest day is never a disaster and always covers the
# night. It also counts distinct wards across two thousand seeds, because the
# draw has twice been broken in a way that dealt the same two games forever and
# looked perfect from everywhere else.
"$GODOT" --headless --path "$DIR" --script res://tests/probe/draws_run.gd 2>&1 | grep -vE "$NOISE"
DRAWS=${PIPESTATUS[0]}

# DOES A CAREER HOLD ITS SHAPE. Eight policies played to their ending, against
# the six criteria the design lives or dies by — honest play pays it off, a
# restrained liar pays it off faster, doing it every night does not, greed is
# struck off before it finishes. It is under a second and it is the only thing
# that catches a balance inversion; it caught one this session, immediately
# after a fix removed the mechanism that had been hiding it.
"$GODOT" --headless --path "$DIR" --script res://tests/probe/career_run.gd 2>&1 | grep -vE "$NOISE"
CAREER=${PIPESTATUS[0]}

# AND CAN EVERY WARD BE SIGNED OFF BY PLAYING IT STRAIGHT. Twenty-six hundred
# strategies a ward, plus one that is not a strategy: the day a careful person
# plays, written out. The search alone reported the fourth ward as having no
# clean day at all, which was a claim about the search.
"$GODOT" --headless --path "$DIR" --script res://tests/probe/frontier_run.gd 2>&1 | grep -vE "$NOISE"
FRONTIER=${PIPESTATUS[0]}

# ...AND THE GAME SAYS NOTHING IT SHOULD NOT WHILE BEING PLAYED.
#
# `boot_check.sh` asserts this for the way IN — Boot and the main menu — and
# that is where it stops, because it quits at the title screen. So nothing has
# ever checked what the game prints once Game.tscn is actually loaded, which is
# where the environment, the world, the NPCs and every system live.
#
# It cost a warning on every launch of the shipped build: the environment
# enabled SSAO, which is Forward+ only, on a project that ships Compatibility.
# Six harnesses ran past it for as long as it existed.
#
# The same ignore list boot_check.sh uses, for the same reasons: this container
# has no sound card, no vsync and a dummy renderer.
QUIET_IGNORE='ALSA lib|snd_|audio_driver_alsa|All audio drivers failed|Could not set V-Sync|PulseAudio|pcm\.c|conf\.c|confmisc\.c|Unknown PCM|ERR_CANT_OPEN|init_output_device|ObjectDB instances leaked|PagedAllocator|Unreferenced static string|RID allocations|resources still in use|Parameter "m" is null|mesh_get_surface_count|^ *at: '
NOISY=$("$GODOT" --headless --path "$DIR" --script res://tests/smoke_run.gd 2>&1 \
  | grep -E "ERROR|SCRIPT ERROR|WARNING" | grep -vE "$QUIET_IGNORE" || true)
QUIET=0
if [ -n "$NOISY" ]; then
  echo ""
  echo "=== THE GAME PRINTED THIS WHILE BEING PLAYED ==="
  echo "$NOISY" | sort -u | sed 's/^/  /'
  QUIET=1
fi

# And finally the one route no other harness takes: the real entry point.
# Everything above instantiates Game.tscn directly, which skips Boot and the
# main menu entirely — the gap that hid both "the game is unplayable from the
# main menu" and an engine error printed on every launch.
echo ""
GODOT="$GODOT" "$DIR/boot_check.sh"
BOOT=$?

if [ "$UNIT" -ne 0 ] || [ "$SMOKE" -ne 0 ] || [ "$SMOKE_SEEDS" -ne 0 ] || [ "$QUIET" -ne 0 ] || [ "$PLAY" -ne 0 ] || [ "$DATA" -ne 0 ] \
    || [ "$DRAWS" -ne 0 ] || [ "$CAREER" -ne 0 ] || [ "$FRONTIER" -ne 0 ] || [ "$BOOT" -ne 0 ]; then
  echo "TESTS FAILED (unit=$UNIT smoke=$SMOKE seeds=$SMOKE_SEEDS quiet=$QUIET playtest=$PLAY data=$DATA draws=$DRAWS career=$CAREER frontier=$FRONTIER boot=$BOOT)" >&2
  exit 1
fi
echo "ALL TESTS PASSED"
