# Building & running

## Requirements
- **Godot 4.3+** (developed and tested against 4.3-stable).

## Run the game
```
godot --path .            # or open project.godot in the editor and hit F5
```

## Run the tests
Most of the game runs headless, so the suspicion, economy and audit maths is
covered by tests that need no window — and three layers that DO need one
(the play runs, the boot check) run under Xvfb:

```
GODOT=/path/to/godot ./run_tests.sh          # all of it, ~6 min
GODOT=/path/to/godot ./check.sh scripts/x.gd # parse errors for specific files
GODOT=/path/to/godot ./boot_check.sh         # the real entry point, on its own
GODOT=/path/to/godot ./playfast.sh day       # a whole shift, played on a pad
GODOT=/path/to/godot ./play.sh keys          # WASD and a real captured mouse
```

Exit code is non-zero if anything fails — including `check.sh`, which for a
long time exited 0 on every parse error it had just printed.

## Exporting

```
GODOT=/path/to/godot ./export.sh all
```

Builds Windows, Linux and macOS, then RUNS the Linux one and fails if it does
not reach a clean exit — which is the only way to know an export works at all.
Presets are in `export_presets.cfg`; they exclude `tests/`, `docs/` and the
tooling scripts, and carry an `include_filter` for `assets/fonts/*.txt` because
`all_resources` does not carry a plain text file and the font licences have to
ship. Export templates are a separate ~1GB download and are not vendored;
`export.sh` prints the exact command to fetch them if they are missing.

## Looking at it

```
GODOT=/path/to/godot ./screenshots.sh                 # 21 frames, ~20 min
SHOT_ONLY=struck_off GODOT=/path/to/godot ./screenshots.sh   # one frame, ~90 s
GODOT=/path/to/godot ./look.sh try1                   # 4 frames — a shader or a light
GODOT=/path/to/godot ./faces.sh try1                  # 7 frames — a CHARACTER
```

All three render the real game offscreen through Xvfb using the **GL
Compatibility** renderer rather than Forward+, because a headless machine
usually has no Vulkan device — and because that is the renderer this project
ships.

`screenshots.sh` photographs every room and every screen, including the title,
and MEASURES two things a real 1600x900 window is the only place to measure:
how much of a card is below the fold, and what a card is sitting on top of.
`look.sh` is four of those frames — the ward wide, a bedside, the corridor and
the five patients side by side — and is the loop for a shader, a light or a line
weight. `faces.sh` draws six people through `Appearance` and photographs each
from eighty centimetres, which is the loop for a character: a head is sixty
pixels tall in the lineup and that is not enough to judge a face by.

Run the full set after any UI or world change. The count of bugs found only by
looking is now well into double figures, and the most expensive of them was a
rim light that had been quietly erasing every surface in the building.

## Note on `preload` in test/tooling scripts
`preload()` resolves at compile time and pulls the entire `class_name` graph into
the compiling script. Because the core classes emit through the `EventBus`
autoload and `EventBus` would in turn reference those classes, that deadlocks the
GDScript loader. Use runtime `load()` in scripts that pull in many core classes,
and keep `EventBus` signal parameters untyped.
