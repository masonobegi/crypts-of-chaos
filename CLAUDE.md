# Working on Chronic Care

Godot 4.3 project, GDScript, no art or audio assets — every mesh is built from
primitives at runtime and every sound is synthesised on first play.

## Always

```bash
GODOT=/path/to/godot ./run_tests.sh      # 665 assertions + a full headless shift
GODOT=/path/to/godot ./check.sh scripts/foo.gd   # parse errors for specific files
GODOT=/path/to/godot ./screenshots.sh    # render offscreen, photograph every room and screen
BALANCE_DAYS=30 godot --headless --path . --script res://tests/balance_sim.gd
```

Run the tests before committing. Run the screenshots after any UI or world
change — five real bugs have been caught only by looking at the game.

## Engine gotchas that have already cost time

1. **`preload()` of scripts that reference many `class_name` types deadlocks the
   GDScript loader** when combined with typed signal parameters on an autoload.
   `EventBus` signal params are deliberately untyped; the real type is in a
   comment beside each one. Test suites use runtime `load()`.
2. **A new `class_name` leaves the global class cache stale** until `--import`
   runs, and everything referencing the new type fails with "Could not find type
   X". `run_tests.sh` and `check.sh` always do an import pass first.
3. **Calling `.new()` on a script with parse errors HANGS the process** rather
   than erroring. Always gate on `can_instantiate()` — the test runner does.
4. **Autoloads are not resolvable at compile time from a `--script` main loop.**
   `smoke_run.gd`, `balance_sim.gd` and `shot.gd` are thin runners that
   `load()` their implementation at runtime for exactly this reason.
5. **Nodes added during a SceneTree's `_initialize()` are NOT inside the tree**,
   so every `global_position` read errors. The test runner waits three frames;
   world construction uses local `position` throughout and is therefore
   independent of tree membership.
6. **`set_anchors_preset()` sets anchors but not offsets**, leaving a freshly
   created Control at zero size — every child anchored right or bottom then
   lands off-screen. Use `UIKit.place()`, or `set_anchors_and_offsets_preset()`
   for full-rect.
7. **`Label` autowrap inside a container with no width collapses to one
   character per line.** `UIKit.label()` takes autowrap as an opt-in parameter.
8. **`HingeJoint3D` rotates about its own local Z**, which at identity is
   horizontal. A door hinged with a default-oriented joint is welded shut. Doors
   are now script-driven (`SwingDoor` integrates an angle by hand) because the
   solver also fought every attempt to drive the leaf, and "can a nurse get into
   this room" should be a certainty rather than a solver outcome.
9. **A `CharacterBody3D` does not move rigid bodies it collides with**, and its
   velocity is zeroed by `move_and_slide` on contact — so gating a shove on
   post-slide speed means a blocked body can never push anything. Probe ahead
   instead (`NPCBody._open_door_ahead`).
10. **Navigation must be baked AFTER furniture exists**, or NPCs path straight
    through desks and wedge against them.
11. **Reading a freed object into a *typed* local raises "Trying to assign
    invalid previously freed instance" and ABORTS THE FUNCTION** — it does not
    yield null, so the `is_instance_valid()` check on the next line never runs.
    Any dictionary that holds nodes with lifetimes of their own therefore needs
    a single guarded accessor that everything reads through
    (`SuspicionSystem._body`, `PatientSystem.get_body`), plus a `tree_exiting`
    hook that removes the entry. This one cost the most: one visitor going home
    aborted the witnessing pass before it reached the nurse standing in front of
    the player, so the entire stealth game switched itself off partway through
    every shift and nothing failed loudly.

## Design rules that are load-bearing

- **Nothing in the UI is ever labelled "questionable".** No suspicion cost, no
  recovery delta, no "+3 days". Machines show a dial and a prescribed value.
  Developer-facing truth is in `docs/SPOILERS.md`; the player gets Codex notes
  only after personally causing the same effect twice.
- **Suspicion is derived, never stored.** It is a read over the `Evidence` a
  `Mind` holds. Never add a "suspicion += x" anywhere; emit a `WorldEvent` and
  let perception decide who noticed.
- **Three layers are allowed to disagree**: truth (`Patient.recovery`), record
  (`PatientChart`), belief (`Mind`). All the comedy is in the gaps.
- **`EconomySystem.ADMISSION_COST` is the most load-bearing constant.** Without
  it, turnover beats duration on a five-bed ward and the premise inverts. There
  is a balance check for this.
- Content lives in data (`DB`, `Items`, `Upgrades`, `Meta.PERKS`). Adding a
  condition, item, complication, event or perk should not require touching a
  system. Tests walk all of it and assert referential integrity.

## Testing philosophy

`tests/` has four layers, and each has caught things the others could not:

| Layer | Catches |
|---|---|
| unit + integration | maths, serialisation, floor connectivity |
| `smoke_run.gd` | "everything compiles and nothing works" |
| `live_run.gd` | anything that only breaks with real frames — it found that every ward door was welded shut and no member of staff could enter any patient room |
| `balance_sim.gd` | design inversions — it found that cheating originally paid *less* than honesty |
| `screenshots.sh` | anything you can only see |

`live_run.gd` must use `--fixed-fps`, or a frame is however long the host took
and the result is flaky.

Where a fix corrects a subtle behaviour, add the test that would have caught it
and say in the comment *why* the obvious thing was wrong.
