# Building & running

## Requirements
- **Godot 4.3+** (developed and tested against 4.3-stable).

## Run the game
```
godot --path .            # or open project.godot in the editor and hit F5
```

## Run the tests
The whole simulation layer is engine-agnostic enough to run headless, so the
suspicion/economy/patient maths is covered by tests that need no window:

```
GODOT=/path/to/godot ./run_tests.sh
```

Exit code is non-zero if anything fails.

## Screenshots

```
GODOT=/path/to/godot ./screenshots.sh
```

Renders the real game offscreen through Xvfb and photographs it from ten fixed
vantage points. It uses the **GL Compatibility** renderer rather than Forward+,
because a headless machine usually has no Vulkan device.

This is worth running after any UI or world change — it has already caught three
layout bugs that no test could see (the HUD clock wrapping one character per
line, the money readout rendering off-screen, and patients standing upright
inside their beds).

## Note on `preload` in test/tooling scripts
`preload()` resolves at compile time and pulls the entire `class_name` graph into
the compiling script. Because the core classes emit through the `EventBus`
autoload and `EventBus` would in turn reference those classes, that deadlocks the
GDScript loader. Use runtime `load()` in scripts that pull in many core classes,
and keep `EventBus` signal parameters untyped.
