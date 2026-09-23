#!/usr/bin/env bash
# Build the game. Windows is the primary target; Linux is built too because it
# is the only one this machine can actually RUN, which is the only way to know
# an export works at all.
#
#   GODOT=/path/to/godot ./export.sh [windows|linux|macos|all]
#   GODOT=/path/to/godot STRICT=1 ./export.sh all     # what a RELEASE has to pass
#
# Export templates are a separate ~1GB download and are NOT in the repo. If they
# are missing this script says so and tells you the one command that fixes it.
#
# STRICT=1 is the difference between "this builds" and "this can be uploaded".
# Everything it turns from a note into a failure is cosmetic to a developer and
# is the first thing a buyer sees: the exe's icon and version block, and the
# placeholder identity fields. A day-to-day build should not be blocked on any
# of it, and a release must not ship without it — so it is one flag rather than
# a note somebody remembers to read.
set -uo pipefail
GODOT="${GODOT:-godot}"
DIR="$(cd "$(dirname "$0")" && pwd)"
WHAT="${1:-all}"
STRICT="${STRICT:-0}"
TEMPLATES="$HOME/.local/share/godot/export_templates/4.3.stable"
VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' "$DIR/project.godot" | head -1)

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

# POINTING GODOT AT rcedit, WHICH IS THE ONLY THING THAT STAMPS AN EXE.
#
# It is a Windows binary, so on Linux it runs under wine, and Godot reaches
# both of them through EDITOR settings rather than through anything in the
# project — there is no project file, no preset field and no command-line flag
# that carries them, so a repo alone cannot describe its own release build.
# That is why this is here: the two paths are found and written into the editor
# settings by the build script, so a fresh machine needs one command
# (tools/fetch_rcedit.sh) and not a paragraph of instructions nobody reads.
RCEDIT="${RCEDIT:-}"
[ -z "$RCEDIT" ] && [ -f "$DIR/tools/rcedit.exe" ] && RCEDIT="$DIR/tools/rcedit.exe"
[ -z "$RCEDIT" ] && [ -f "$HOME/.local/share/godot/rcedit.exe" ] && RCEDIT="$HOME/.local/share/godot/rcedit.exe"
WINE="${WINE:-}"
if [ -z "$WINE" ]; then
  for c in "$(command -v wine64 2>/dev/null)" "$(command -v wine 2>/dev/null)" /usr/lib/wine/wine64; do
    [ -n "$c" ] && [ -x "$c" ] && WINE="$c" && break
  done
fi
ES="$HOME/.config/godot/editor_settings-4.3.tres"
if [ -n "$RCEDIT" ] && [ -f "$ES" ]; then
  RCEDIT="$RCEDIT" WINE="$WINE" ES="$ES" python3 - <<'WIRE'
import os, re, pathlib
p = pathlib.Path(os.environ["ES"])
s = p.read_text()
for key, val in (("rcedit", os.environ["RCEDIT"]), ("wine", os.environ["WINE"])):
    line = 'export/windows/%s = "%s"' % (key, val)
    pat = re.compile(r'^export/windows/%s = ".*"$' % key, re.M)
    s = pat.sub(line, s) if pat.search(s) else s.replace("[resource]", "[resource]\n" + line, 1)
p.write_text(s)
WIRE
fi

fail=0
echo "=== Chronic Care $VERSION ==="

# WHAT THE FILE CALLS ITSELF, checked before anything is built.
#
# The build shipped as `com.example.chroniccare` by an em-dash company at
# version 0.1.0 — the bundle id Apple refuses, the string Windows shows in the
# Details tab, and a version number that matched nothing. None of it is visible
# from inside the game and none of it is in any harness's line of sight, so the
# only place it can be caught is here and in tests/probe/ship_impl.gd.
identity=0
grep -q "com\.example" "$DIR/export_presets.cfg" && { echo "  placeholder bundle identifier (com.example)"; identity=1; }
grep -q 'company_name="—"' "$DIR/export_presets.cfg" && { echo "  placeholder company name"; identity=1; }
for want in "application/short_version=\"$VERSION\"" "application/version=\"$VERSION\"" "application/file_version=\"$VERSION\"" "application/product_version=\"$VERSION\""; do
  grep -qF "$want" "$DIR/export_presets.cfg" || { echo "  preset version does not match project.godot ($want)"; identity=1; }
done
[ "$identity" -eq 0 ] && echo "  identity ok: $VERSION, no placeholders"
[ "$identity" -ne 0 ] && [ "$STRICT" = "1" ] && fail=1

build() {
  local preset="$1" out="$2"
  mkdir -p "$(dirname "$out")"
  echo "=== $preset ==="
  local log
  log=$(mktemp)
  "$GODOT" --headless --path "$DIR" --export-release "$preset" "$out" >"$log" 2>&1
  local code=$?
  # rcedit's own lines are dropped here rather than read. Godot prints
  # `rcedit (<path>):` as a HEADING over that stage whether or not
  # anything went wrong, so the presence of the word in the log says nothing at
  # all — which is how this script reported "no rcedit, the exe carries no icon
  # or version block" about an exe that had both, for as long as rcedit worked.
  # The artefact is inspected below instead. See tools/stamp_check.py.
  grep -E "^(ERROR|WARNING)" "$log" | grep -v "rcedit" | sed 's/^/  /'
  rm -f "$log"
  if [ "$code" -ne 0 ] || [ ! -s "$out" ]; then
    echo "  FAILED"
    fail=1
    return
  fi
  echo "  $(du -h "$out" | cut -f1)  $out"
}

[ "$WHAT" = "all" ] || [ "$WHAT" = "windows" ] && build "Windows" "$DIR/build/windows/ChronicCare.exe"
if { [ "$WHAT" = "all" ] || [ "$WHAT" = "windows" ]; } && [ -s "$DIR/build/windows/ChronicCare.exe" ]; then
  # WHAT A BUYER SEES BEFORE THE GAME STARTS: the icon in their library and the
  # Details tab of the file sitting in it. Neither is visible from inside the
  # game, from any harness in this repo, or from any machine this project is
  # developed on — so the only place it can be caught is by opening the exe.
  if ! python3 "$DIR/tools/stamp_check.py" "$DIR/build/windows/ChronicCare.exe" \
        "Chronic Care" "Mason Obegi" "$VERSION"; then
    if [ "$STRICT" = "1" ]; then
      echo "  RELEASE BLOCKER: the exe is not stamped."
      [ -z "$RCEDIT" ] && echo "    No rcedit found. Run ./tools/fetch_rcedit.sh and build again."
      [ -n "$RCEDIT" ] && [ -z "$WINE" ] && echo "    rcedit is at $RCEDIT but there is no wine to run it with."
      fail=1
    else
      echo "  note: the exe is not stamped (STRICT=1 makes this fatal)"
    fi
  fi
fi
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
