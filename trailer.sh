#!/usr/bin/env bash
# Render the trailer: a frame sequence out of the real game, muxed with the
# real score.
#
#   GODOT=/path/to/godot ./trailer.sh                 # the whole cut, ~40s
#   TRAILER_ONLY=03_bedside GODOT=... ./trailer.sh    # one shot, for framing
#   TRAILER_SECS=4 GODOT=... ./trailer.sh             # a smoke render
#
# WHY THIS IS A SHELL SCRIPT AND NOT A NOTE IN A DOCUMENT. A trailer is the one
# asset a Steam page is mostly judged on, and the reason this project did not
# have one was never that the shots were hard — it is that "render the game to
# video" was four tools nobody had lined up at once. They are lined up here.
#
# --fixed-fps IS LOAD-BEARING. A frame takes about two seconds to rasterise on
# a software renderer, so a tree stepped by real delta animates at half a frame
# a second: the walk cycles, the clock, the typewriter and every fade run forty
# times too slow and the finished film is people teleporting between poses. With
# a fixed delta each rendered frame is exactly 1/FPS of game time however long
# it took to draw.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
FPS="${TRAILER_FPS:-24}"
W="${TRAILER_W:-1920}"
H="${TRAILER_H:-1080}"
OUT="${TRAILER_OUT:-$DIR/build/trailer/chronic-care-trailer.mp4}"

command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not found" >&2; exit 2; }
command -v ffmpeg >/dev/null 2>&1 || {
  echo "ffmpeg not found. apt-get install -y --no-install-recommends ffmpeg" >&2
  exit 2
}

"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
echo "=== rendering $W x $H at $FPS fps ==="
LOG=$(mktemp)
# The Xvfb screen is bigger than the film on purpose — see the note in
# trailer_impl.gd about the window manager's margin.
SW=$((W + 200)); SH=$((H + 200))
TRAILER_FPS="$FPS" TRAILER_W="$W" TRAILER_H="$H" \
  xvfb-run -a -s "-screen 0 ${SW}x${SH}x24" "$GODOT" \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --resolution "${W}x${H}" --fixed-fps "$FPS" \
  --path "$DIR" --script res://tests/trailer_run.gd >"$LOG" 2>&1
grep -E "^trailer:|TRAILER " "$LOG"
# GOTCHA 21, AND GOTCHA 42 UNDER IT. A harness whose last stage only prints
# cannot fail, and a shader that did not compile renders a flat fallback
# material that looks like a design decision — in a still that is a bad
# screenshot, in forty seconds of film it is the whole trailer.
if grep -q "SHADER ERROR\|Shader compilation failed" "$LOG"; then
  echo "trailer.sh: a shader did not compile — every surface using it is flat" >&2
  sed -n '1,40p' "$LOG" >&2
  exit 1
fi
if ! grep -q "TRAILER OK" "$LOG"; then
  echo "trailer.sh: the render did not finish" >&2
  tail -40 "$LOG" >&2
  rm -f "$LOG"
  exit 1
fi
rm -f "$LOG"

USERDIR="$HOME/.local/share/godot/app_userdata/Chronic Care"
SEQ="$USERDIR/trailer"
WAV="$USERDIR/trailer_music.wav"
n=$(ls -1 "$SEQ"/f*.png 2>/dev/null | wc -l)
[ "$n" -eq 0 ] && { echo "no frames in $SEQ" >&2; exit 1; }
echo "=== encoding $n frames ==="
mkdir -p "$(dirname "$OUT")"

# -shortest AND an audio fade, because the score is ninety-four seconds and the
# cut is about forty: without both, the file carries a minute of music over a
# frozen last frame on players that pad rather than truncate.
DUR=$(python3 -c "print(f'{$n/$FPS:.3f}')")
AUDIO=()
if [ -f "$WAV" ]; then
  AUDIO=(-i "$WAV" -filter:a "atrim=0:$DUR,afade=t=in:st=0:d=1.2,afade=t=out:st=$(python3 -c "print(f'{max(0,$DUR-2.0):.3f}')"):d=2.0"
         -c:a aac -b:a 192k -ac 2)
else
  echo "  no music wav; the film will be silent"
fi
# The scale filter is a backstop rather than the fix: x264 refuses an odd
# width outright, and discovering that after a forty-minute render is the
# expensive way to learn it.
ffmpeg -y -loglevel error -framerate "$FPS" -i "$SEQ/f%05d.png" "${AUDIO[@]}" \
  -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" \
  -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart \
  -shortest "$OUT" || { echo "ffmpeg failed" >&2; exit 1; }
echo "  $(du -h "$OUT" | cut -f1)  $OUT  (${DUR}s)"
echo "TRAILER OK"
