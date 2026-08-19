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

## Note on `preload` in test/tooling scripts
`preload()` resolves at compile time and pulls the entire `class_name` graph into
the compiling script. Because the core classes emit through the `EventBus`
autoload and `EventBus` would in turn reference those classes, that deadlocks the
GDScript loader. Use runtime `load()` in scripts that pull in many core classes,
and keep `EventBus` signal parameters untyped.
