#!/usr/bin/env bash
# Boot the game through its REAL entry point and fail on anything it prints
# that a shipped build should not print.
#
# Every other harness in tests/ instantiates Game.tscn directly, which skips
# Boot -> MainMenu entirely. That gap has already hidden two things: the game
# being unplayable from the main menu (the briefing was closed by the tutorial,
# and the briefing is the only caller of clock_in), and an engine error printed
# on every single launch because Boot swapped the scene from inside its own
# _ready(). Neither was visible to 1,500 assertions.
#
# Usage: GODOT=/path/to/godot ./boot_check.sh
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
FRAMES="${BOOT_FRAMES:-300}"

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "Godot binary not found. Set GODOT=/path/to/godot" >&2
  exit 1
fi

echo "=== BOOT CHECK ==="
OUT=$(mktemp)
# Rendered, not headless: the main menu is a Control tree and half of what can
# go wrong on the way in is layout.
if command -v xvfb-run >/dev/null 2>&1; then
  timeout 180 xvfb-run -a "$GODOT" --rendering-method gl_compatibility \
    --path "$DIR" --quit-after "$FRAMES" >"$OUT" 2>&1
else
  timeout 180 "$GODOT" --headless --path "$DIR" --quit-after "$FRAMES" >"$OUT" 2>&1
fi
CODE=$?

# Noise this container produces and a player's machine will not: no sound card,
# no vsync under Xvfb, software GL.
IGNORE='ALSA lib|snd_|audio_driver_alsa|All audio drivers failed|Could not set V-Sync|PulseAudio|pcm\.c|conf\.c|confmisc\.c|Unknown PCM|ERR_CANT_OPEN|init_output_device'
PROBLEMS=$(grep -E "ERROR|SCRIPT ERROR|WARNING" "$OUT" | grep -vE "$IGNORE" || true)

if [ "$CODE" -ne 0 ]; then
  echo "  the game did not reach a clean exit (code $CODE)"
  tail -30 "$OUT"
  rm -f "$OUT"
  exit 1
fi

if ! grep -q "Chronic Care booting" "$OUT"; then
  echo "  Boot never ran"
  tail -30 "$OUT"
  rm -f "$OUT"
  exit 1
fi

if [ -n "$PROBLEMS" ]; then
  echo "  the shipped entry point printed this on the way in:"
  echo "$PROBLEMS" | sed 's/^/    /'
  rm -f "$OUT"
  exit 1
fi

echo "  ok: boots to the main menu over $FRAMES frames and says nothing it shouldn't"
echo "BOOT CHECK PASSED"
rm -f "$OUT"
