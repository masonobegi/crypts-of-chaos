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

12. **A treatment recorded under one id and charted under another produces
    BOTH fraud findings at once.** `Patient.record_treatment(id)` and
    `Chart.log_treatment(id)` are matched by string in `Chart.audit()`: an id
    in one and not the other is "billed with no record of it being performed"
    (weight 0.55) *plus* "administered but never charted". Every hand-procedure
    got this wrong on the way in, so performing one honestly generated the two
    findings the game reserves for fraud. If you add a verb, use ONE id for
    both sides of it, and give it a name in `DB.OFF_MENU_TREATMENTS`.
13. **One wall-mounting offset does not fit a poster and a sharps bin.** A 3cm
    poster sits fine 9cm proud of the plaster; a 20cm-deep box mounted the same
    way is half inside it. `Dressing._add()` takes the piece's own depth and
    pushes it out by half of it. This was most of the reported "things phasing
    through each other".

14. **An assertion made in the same frame as its setup reads LAST frame's
    value.** Anything a node writes in `_process`/`_physics_process` — an
    animation pose, a derived perception value, a `queue_free` — has not
    happened yet when the setup line returns. `_check_the_ward_sleeps_at_night`
    asserted `attention == 0.0` in the frame that called `set_asleep(true)` and
    passed for months while every sleeping patient in the building witnessed
    everything, because `_process` recomputed `attention` from `_distraction`
    each frame and overwrote the zero. `smoke_impl.gd` has `_defer(n, callable)`
    for exactly this, and the run refuses to report while one is outstanding.
15. **A constant nothing reads is a promise the game is making in copy and not
    keeping in code.** `SHIFTS[kind]["scrutiny"]` was documented as "how
    carefully the paperwork is read afterwards", was printed at the player on
    both shift cards ("Nobody sees a thing"), and was read by nothing at all —
    so the night shift paid the best multiplier, had the fewest witnesses, and
    drew institutional attention at exactly the same rate as a day shift. Grep
    every key of a data table for a reader before trusting the table.

16. **`ERROR: Parameter "m" is null` is Godot, not you.** One line per `Label3D`
    freed, from the headless dummy rasterizer querying a mesh that backend never
    builds. A unit run emitted 110 and a smoke run 35, which is enough to bury a
    real error — `run_tests.sh` filters it and says why. Reproduce in ten lines:
    add a bare `Label3D` to an empty `SceneTree` and free it.

17. **Godot DISCARDS an explicit name when it collides with a sibling** and
    substitutes the class name: two nodes both called `"Vent"` under one parent
    become `Vent` and `@Node3D@5306`. Every dressing piece is added to the
    Hospital node, so thirteen of the fourteen vents cannot be found by name at
    all. Two versions of a ceiling-height check searched by name, found exactly
    one of each kind in a fifteen-room hospital, and reported it correct — three
    inspected objects reading as coverage. Find sets of things by GROUP
    (`Dressing.CEILING_GROUP`), never by name.

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
- **A day has three phases and they are separate systems.** The ward
  (`ShiftSystem`, ends at the office desk), the evening (`NightSystem`, a
  street with cones of vision on it), and the post (`LegalSystem`, a claim to
  settle or fight). `ShiftSystem.after_statement()` is the join: each screen
  calls back into it when it closes, so the sequence is driven by the player
  finishing with one rather than by a timer.
- **Every hand-procedure declares intent first and is graded against it.**
  `Procedures.OUTCOMES[kind][intent][band]`. Doing either job well is rewarded
  and doing either badly is punished — there is no safe option and no free
  crime, and intending harm and fumbling it is the worst square on the board.
  Add a procedure by adding a `kind` to that table and a screen that grades a
  manoeuvre 0..1; `TreatmentSystem.apply_outcome()` does the rest.
- **The minigames are performed on a drawing of the actual body part.**
  `Anatomy` builds nine rigs out of one primitive (a tapered capsule), drawn
  grown-dark-first and then filled so a hand reads as one object. A new part is
  a `_rig_*()` returning `prox`/`dist`/`pbone`/`dbone`/`pivot`/`axis`/`wound`.
- **Decoration has no collision and no navigation footprint.** Everything in
  `Dressing` is scenery; if it needs to be usable it belongs in `Furniture`
  with an `_occupy()`. That rule is what lets there be a lot of it.
- **Achievements are a pure read over `GameState.stats` and flags.** A system
  that has to remember to award one is a system with an achievement bug in it.
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
| overlap audit (in `smoke_run.gd`) | two objects placed in the same cubic metre by two pieces of code that do not know about each other |
| `tests/probe/career_run.gd` | anything that only exists ACROSS days — the carry, the remembered beds, the denser rounds after a flag, the debt that grows on a short night. Plays a week five ways (honest, honest+corroborated, one lie, greedy, adaptive) and asks three questions: does honest play clear every night, is greed caught, and is one bad night recoverable. It found that `remembered_beds` was dead across a roster change and that `auditor_present` did nothing at all; after the rework it is the harness that proves crime pays only if you can stop. The six properties: honest play pays it off, a RESTRAINED liar pays it off faster, doing it every night does not, greed is struck off first, never looking at anybody NEVER pays it off, and one bad night is recoverable. |
| `tests/probe/frontier_run.gd` | dominant strategies. Two thousand two hundred plays — both wards, every subset of beds up to three, crossed with eleven ways of justifying a hold, crossed with whether you MIX them (a peer behind the bed that deserves one, your own note on the bed that does not), crossed with how you answer in the room — reported as the most money made at each verdict. Slow (~12 min), so it is not in `run_tests.sh`; run it after touching the economy, the contradiction rules, the bed audit or a roster. The property it exists to defend: **the top figure must not be reachable signed off.** |

`playtest_run.gd` exits non-zero when a success criterion regresses, so a
design inversion fails `run_tests.sh` rather than printing a report nobody
reads. A test that asserts NOTHING is failed by the runner: reading a key a
dictionary no longer has aborts the function without erroring, so the
assertions after it never run and the suite reports green.

Where a fix corrects a subtle behaviour, add the test that would have caught it
and say in the comment *why* the obvious thing was wrong.

14. **There is ONE clock, and it lives in `GameState`.** Every verb on the ward
    costs minutes (`WardDay.READ_COST` and friends) and those minutes were
    being spent on `WardDay.minute` alone, while the HUD, the force-end and
    everything else driven by `minute_passed` went on counting real seconds —
    so the chart said half past seven and the corner of the screen said five
    past eleven, and the gap widened the more the player did. `advance_to()`
    calls `GameState.skip_to()`, which re-enters `_on_minute` immediately;
    anything that advances the clock must therefore be re-entrancy safe.
    `end_day()` was not, and took the debt off the takings twice.
15. **Under `--headless` the root Window is 64 pixels tall.** Every Control
    lays out against it, so a card capped at `viewport height - 116` gets a
    negative height and reports as three-quarters below the fold. Layout
    measurements belong in `screenshots.sh`, which runs a real 1600x900 window
    under Xvfb. Setting `tree.root.size` does not help — the dummy display
    driver ignores it.

16. **A harness that reuses `GameState` must clear the whole carry, not part of
    it.** The playtest cleared `remembered_beds` between runs and left
    `carried_debt` alone, so from the first strategy that came up short every
    later one owed Vinnie more than the last — three successive audits reported
    a risk/reward frontier that depended on the order of the list, and "one
    well-timed lie" was recorded as worth $150 when it is worth $850.
    `_clean_slate()` clears all of it and `_day()` fails loudly if a run starts
    owing anything but `Cases.DEBT_DUE`. The one measurement that WANTS a carry
    (criterion 6) builds its ward through `_carried_day()` instead.
17. **`Cases.roster()` is a function of `GameState.day`, so anything that
    changes the day mid-run must change it back at the right moment.** Setting
    it back before `end_day()` meant the force-discharge loop walked the first
    ward's roster while the `WardDay` still held the second ward's patients, and
    every lookup errored. Reset after the review, not after the play.
18. **What a document says is not what is true, and the second ward is built on
    the gap.** `WardDay.reads_as_well()` is what the rounds, a nurse review and
    a test report; `truly_well` is what an examination and the registrar find.
    A patient marked `only_visible_in_person` differs between the two. Without
    it Adeyemi's ten o'clock round simply announced Peter Lomax and there was no
    reason to go and look at anybody.

19. **A gate on something the PLAYER does is a reward for doing nothing.**
    `_sent_home_unwell` used to `continue` unless the discharge was documented,
    examined, or overruled — all three player-initiated. So the way to make a
    wrongful discharge invisible was to never read a chart, never examine
    anybody and never ask: **information had strictly negative expected value**,
    because looking at a patient was the only way to manufacture the evidence
    that convicted you of the decision you then made. Any new rule that asks
    "did the player produce a document about this" needs a rung for "no, and
    that is worse", not an early return. `_they_came_back` and
    `_never_laid_eyes_on_them` are ungated on purpose.
20. **`WardDay.start()` runs every morning, so anything assigned in it is
    assigned every morning.** `cash = Cases.STARTING_CASH` sat there and minted
    the player nine hundred pounds a night out of nowhere — a third of a night's
    takings, under every strategy, in every measurement this project ever took,
    and it made "he takes everything at eight" vacuous because nothing survived
    the night. One-off state belongs in `GameState.start_new_career`.
21. **A verdict tier nothing reaches is content behind a trigger that never
    fires.** `struck_off()` read only REFERRED verdicts, and the money-optimal
    play lands on FLAGGED on both wards and never on REFERRED (that needs two
    indefensible beds, and every two-indefensible variant earns less). So the
    optimal player accrued zero strikes forever and the auditor never spawned.
    Score every night on a scale instead of matching a verdict NAME.
22. **A carried flag recomputed from last night lasts one night.** The auditor
    was `verdict == ESCALATED`, recomputed in `_carry`, so a single clean shift
    made her vanish. Anything meant to persist needs its own countdown
    (`auditor_shifts`), not a re-derivation.
