#!/usr/bin/env bash
# Run the headless test suite. Point GODOT at a Godot 4.3+ binary.
set -uo pipefail
GODOT="${GODOT:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1 && [ ! -x "$GODOT" ]; then
  echo "Godot binary not found. Set GODOT=/path/to/godot" >&2
  exit 2
fi
exec "$GODOT" --headless --path "$(dirname "$0")" --script res://tests/run_tests.gd
