#!/usr/bin/env bash
# THREE VANTAGES, FAST. `screenshots.sh` renders twenty-one frames plus two
# layout measurements and takes twenty minutes on a software rasteriser, which
# is far too long a loop to tune a shader, a light or a line weight in. This
# renders the ward wide, a bedside and the corridor and nothing else.
#
#   GODOT=/path/to/godot ./look.sh <tag>
#
# The tag names the set, so two runs can be compared side by side. Output lands
# in the project's user:// data directory under look/.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not found" >&2; exit 2; }
export LOOK_TAG="${1:-x}"
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1
# CAPTURED, TESTED, AND EXITED ON — see CLAUDE.md 21. A harness whose last
# pipeline stage is a filter cannot fail: `check.sh` ended in `| head -40` and
# so exited 0 on every parse error it had just printed.
OUT=$(timeout 600 xvfb-run -a -s "-screen 0 1600x900x24" "$GODOT" \
  --rendering-method gl_compatibility --rendering-driver opengl3 \
  --path "$DIR" --script res://tests/look_run.gd 2>&1)
echo "$OUT" | grep -E "look:|look done|SCRIPT ERROR|Parse Error|SHADER ERROR|Shader compilation"
# A shader that fails to compile is announced once and then renders a fallback
# material forever, which looks like a design decision rather than a fault.
if echo "$OUT" | grep -q "SHADER ERROR\|Shader compilation failed"; then
  echo "look.sh: a shader did not compile" >&2
  exit 1
fi
if ! echo "$OUT" | grep -q "look done"; then
  echo "look.sh: rendered nothing" >&2
  exit 1
fi
