#!/usr/bin/env bash
# Render the game offscreen and photograph it from fixed vantage points.
#
#   GODOT=/path/to/godot ./screenshots.sh
#
# Uses Xvfb plus Godot's GL Compatibility renderer, because Forward+ needs a
# Vulkan device that headless boxes generally do not have. Output lands in the
# project's user:// data directory; the path is printed at the end.
#
# ONE FRAME AT A TIME, when that is what you are looking at:
#
#   SHOT_ONLY=struck_off GODOT=/path/to/godot ./screenshots.sh
#
# AT A STATED TIME OF DAY, when the light is what you are looking at:
#
#   SHOT_ONLY=01_corridor SHOT_CLOCK=1165 GODOT=/path/to/godot ./screenshots.sh
#
# SHOT_CLOCK is a minute of the day (1165 is 19:25) and applies to every WORLD
# frame in the run; the UI stages set their own clock and are left alone. It
# writes `GameState.minute_of_day` and calls `Game.apply_shift_look` by hand
# rather than advancing the clock for real, so the ward does not think a day's
# worth of rounds has happened. Sweeping a light means photographing the same
# room at the same minute twice with one number changed, and until this existed
# there was no way to ask for a minute at all.
#
# Comma-separated, matched as fragments of the frame name. Twenty-one frames is
# twenty minutes on a software rasteriser and chasing a fault that shows up in
# two of them means paying for nineteen you already have. The staging still
# runs in order — several stages depend on the ones before them — so only the
# save is skipped; it costs a few frames and nothing else.
# AND IT CAN NOW FAIL. Two of the frames it renders are measurements rather
# than photographs — `02b_fittings_off` against `02_ward_from_door`, which is
# whether the ceiling fittings light anything at all, and `09_ward_evening`
# against the same morning frame, which is whether the evening arrives. Both
# faults are invisible to every other layer in this repo: nothing errors,
# nothing is missing, and the picture looks like a design decision. This used
# to `exec` godot and hand back whatever it exited with, which for a harness
# that only prints is always zero (gotcha 21) — the output is captured and
# tested now, and the exit code comes from what it said.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not found" >&2; exit 2; }
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
OUT=$(xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --path "$DIR" --script res://tests/shot.gd 2>&1)
echo "$OUT"
if echo "$OUT" | grep -q "SHADER ERROR\|Shader compilation failed"; then
  echo "screenshots.sh: a shader did not compile — every surface using it is" >&2
  echo "  rendering a flat fallback material and it looks deliberate" >&2
  exit 1
fi
# ...AND ANYTHING THE GAME THREW WHILE BEING PHOTOGRAPHED. `run_tests.sh` has a
# quiet check and does not run this harness, so a runtime error raised only
# while staging a screen — a card built for the wrong ward, a freed node — was
# printed in the middle of a page of "shot:" lines and exited 0. One was found
# by eye, which is not a way of finding things. `Parameter "m" is null` is the
# headless rasteriser and is filtered for the reason gotcha 16 gives.
# `data.tree` is `get_tree()` on a node that is not in the tree, which is never
# benign and is not something a picture shows you: two of them printed on the
# way out of the main menu — the one transition every player makes — for as long
# as this harness has existed, because `boot_check.sh` stops AT the menu and
# every other harness starts after it.
BAD=$(echo "$OUT" | grep -E "SCRIPT ERROR|Trying to assign invalid|previously freed|data\.tree" \
  | grep -v 'Parameter "m" is null' || true)
if [ -n "$BAD" ]; then
  echo "screenshots.sh: the game threw while being photographed" >&2
  echo "$BAD" | sort -u | sed 's/^/  /' >&2
  exit 1
fi
if echo "$OUT" | grep -q "SHOT CHECK FAILED"; then
  echo "screenshots.sh: a measured frame regressed" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "captured .* frames to"; then
  echo "screenshots.sh: rendered nothing" >&2
  exit 1
fi
