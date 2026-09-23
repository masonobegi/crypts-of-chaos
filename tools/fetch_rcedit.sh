#!/usr/bin/env bash
# rcedit is the ONLY thing that stamps an icon and a version block onto a
# Windows .exe, Godot shells out to it, and it is itself a Windows binary — so
# on this machine it runs under wine. It is not vendored because it is a 1.3MB
# third-party binary and this repo ships no binaries but four font files.
#
#   ./tools/fetch_rcedit.sh        # downloads tools/rcedit.exe
#
# export.sh finds it there on its own; nothing else has to be configured.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
URL="https://github.com/electron/rcedit/releases/download/v2.0.0/rcedit-x64.exe"
if [ -f "$DIR/rcedit.exe" ]; then
  echo "already have $DIR/rcedit.exe"
  exit 0
fi
curl -sSfL -o "$DIR/rcedit.exe" "$URL"
echo "fetched $DIR/rcedit.exe ($(du -h "$DIR/rcedit.exe" | cut -f1))"
if ! command -v wine64 >/dev/null 2>&1 && [ ! -x /usr/lib/wine/wine64 ]; then
  echo "NOTE: no wine on this machine, so rcedit cannot be run here."
  echo "      apt-get install -y --no-install-recommends wine64"
fi
