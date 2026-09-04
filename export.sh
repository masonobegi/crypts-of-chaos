#!/usr/bin/env bash
# Build the game. Windows is the primary target; Linux is built too because it
# is the only one this machine can actually RUN, which is the only way to know
# an export works at all.
#
#   GODOT=/path/to/godot ./export.sh [windows|linux|all]
#
# Export templates are a separate ~1GB download and are NOT in the repo. If they
# are missing this script says so and tells you the one command that fixes it.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
WHAT="${1:-all}"
TEMPLATES="$HOME/.local/share/godot/export_templates/4.3.stable"

if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "Godot binary not found. Set GODOT=/path/to/godot" >&2
  exit 1
fi

if [ ! -d "$TEMPLATES" ]; then
  cat >&2 <<'MSG'
Export templates for 4.3.stable are not installed. They are a separate ~1GB
download and deliberately not vendored:

  cd /tmp && curl -sSL -o t.tpz \
    "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_export_templates.tpz" \
    && unzip -q -o t.tpz -d /tmp/tpl \
    && mkdir -p ~/.local/share/godot/export_templates \
    && mv /tmp/tpl/templates ~/.local/share/godot/export_templates/4.3.stable \
    && rm -f t.tpz
MSG
  exit 1
fi

# The class cache has to be current or the export bakes a stale one. Same reason
# run_tests.sh imports first.
"$GODOT" --headless --path "$DIR" --import >/dev/null 2>&1

fail=0
build() {
  local preset="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  echo "=== $preset ==="
  local log
  log=$(mktemp)
  "$GODOT" --headless --path "$DIR" --export-release "$preset" "$out" >"$log" 2>&1
  local code=$?
  # rcedit is a Windows-only tool for stamping the icon and version block onto
  # the .exe. Its absence costs cosmetics, not correctness, and it cannot run
  # here — so it is reported and not treated as a failure.
  grep -E "^(ERROR|WARNING)" "$log" | grep -v "rcedit" | sed 's/^/  /'
  grep -q "rcedit" "$log" && echo "  note: no rcedit, so the exe carries no icon or version block"
  rm -f "$log"
  if [ "$code" -ne 0 ] || [ ! -s "$out" ]; then
    echo "  FAILED"
    fail=1
    return
  fi
  echo "  $(du -h "$out" | cut -f1)  $out"
}

[ "$WHAT" = "all" ] || [ "$WHAT" = "windows" ] && build "Windows" "$DIR/build/windows/ChronicCare.exe"
[ "$WHAT" = "all" ] || [ "$WHAT" = "linux" ] && build "Linux" "$DIR/build/linux/ChronicCare.x86_64"
[ "$WHAT" = "all" ] || [ "$WHAT" = "macos" ] && build "macOS" "$DIR/build/macos/ChronicCare.zip"

# And then actually run the thing, because an export that produces a file and
# an export that produces a GAME are different claims.
if [ -x "$DIR/build/linux/ChronicCare.x86_64" ]; then
  echo "=== running the exported build ==="
  out=$(mktemp)
  if command -v xvfb-run >/dev/null 2>&1; then
    # NO --rendering-method. This is the one check that runs the artefact a
    # player downloads, and passing the flag here is exactly how "the shipping
    # renderer does not start at all" stayed invisible last time: the project
    # was set to forward_plus, Godot 4.3 does not fall back, and every harness
    # in the repo quietly avoided it. boot_check.sh carries the same note.
    timeout 180 xvfb-run -a "$DIR/build/linux/ChronicCare.x86_64" \
      --quit-after 300 >"$out" 2>&1
  else
    timeout 180 "$DIR/build/linux/ChronicCare.x86_64" --headless --quit-after 300 >"$out" 2>&1
  fi
  code=$?
  if [ "$code" -ne 0 ] || ! grep -q "Chronic Care booting" "$out"; then
    echo "  the exported build did not boot (code $code)"
    tail -20 "$out"
    fail=1
  else
    echo "  ok: the exported build boots and exits cleanly"
  fi
  rm -f "$out"
fi

[ "$fail" -eq 0 ] && echo "EXPORT OK" || echo "EXPORT FAILED"
exit "$fail"
