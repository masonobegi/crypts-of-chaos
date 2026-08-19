# BUILD LOG — Chronic Care

> Append-only work log. **If you are a future session picking this up: read the
> "NEXT UP" section at the bottom, then `git log --oneline` to see where things stand.**

Engine: **Godot 4.3** (headless binary validated in-session; project opens in 4.3+).
Validation command:
```
$GODOT --headless --path . --script res://tests/run_tests.gd
```
where `$GODOT` is a Godot 4.3 linux binary (downloaded to the session scratchpad,
not committed — see docs/BUILDING.md).

---

## Session 1 — 2026-08-19

### Done
- [x] Wiped prior repo contents (owner request), started fresh.
- [x] Project skeleton: `project.godot`, input map, physics layers, `.gitignore`.

- [x] `docs/DESIGN.md` — critique of the brief + the five design changes made.
- [x] Autoloads: Log, RNG (seeded, per-stream), EventBus, DB (content), GameState,
      AudioMgr (fully procedural synthesis — zero audio assets), SaveSystem.
- [x] Core data model: WorldEvent (truth) / PatientChart (record) / Mind+Evidence
      (belief) / Patient / Complication.
- [x] Headless test harness + 118 passing assertions.

### Gotcha found (documented in docs/BUILDING.md)
`preload()` of scripts that reference many `class_name` types deadlocks the
GDScript loader when combined with typed signal params on an autoload. Fixed by
(a) untyping EventBus signal params and (b) using runtime `load()` in the runner.

### NEXT UP
- Player controller + interaction/grab physics.
