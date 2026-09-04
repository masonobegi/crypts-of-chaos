# Working on Chronic Care

Godot 4.3 project, GDScript, no art or audio assets — every mesh is built from
primitives at runtime and every sound is synthesised on first play.

## Always

```bash
GODOT=/path/to/godot ./run_tests.sh      # all of it, ~4 min
GODOT=/path/to/godot ./check.sh scripts/foo.gd   # parse errors for specific files
GODOT=/path/to/godot ./screenshots.sh    # render offscreen, photograph every room and screen
GODOT=/path/to/godot ./look.sh try1      # three vantages, ninety seconds, for tuning the look
GODOT=/path/to/godot ./export.sh all     # windows, linux, macos — and RUNS the linux one
GODOT=/path/to/godot ./playfast.sh day   # play a WHOLE SHIFT with a controller
GODOT=/path/to/godot ./play.sh keys      # play it with WASD and a real mouse, under Xvfb
```

`run_tests.sh` is 297 assertions, a 161-check smoke run through the real tree
on three different wards, 31 playtests against seven success criteria, the
authored-data and draw checks, a career played eight ways on three seeds, a
2,601-strategy adversarial search per ward, two playthroughs driven entirely by
the input actions a controller sends — the first two minutes, and a whole shift
from the briefing to the next morning — a check that the game prints nothing it
should not while being played, and a boot through the real main menu. Every
phase exits non-zero on its own and the runner reports which.

Two seeds are overridable, and it is the cheapest way to catch a harness that
only works on the board it happens to have been written against:

```bash
SMOKE_SEED=99  godot --headless --path . --script res://tests/smoke_run.gd
CAREER_SEED=99 godot --headless --path . --script res://tests/probe/career_run.gd
PLAY_SEED=99   godot --headless --fixed-fps 60 --path . --script res://tests/play_run.gd -- day
```

Sweeping those found four things in one session that three fixed seeds had not:
two flaky checks, a patient standing in a doorway who could not be spoken to,
and a tap on a walking patient that did nothing at all. Twenty seeds is a
minute.

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
   `smoke_run.gd`, `playtest_run.gd`, `shot.gd` and everything in
    `tests/probe/` are thin runners that
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

12. **An entry recorded under one id and charted under another produces BOTH
    findings at once.** `Contradictions.audit_beds()` matches what you did
    against what the chart says by string: an id in one and not the other reads
    as "billed with no record of it" *and* "done but never written up", so one
    honest act generates the two findings the game reserves for fraud. If you
    add a verb, use ONE id for both sides of it. (This was first written about
    a treatment system that has since been cut; the failure mode outlived it,
    because it is a property of matching two lists by string.)

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

18. **`BLEND_MODE_MUL` does not sample the albedo texture on the Compatibility
    renderer.** A contact shadow built as a black-to-transparent texture and
    multiplied over the floor rendered as a hard black RECTANGLE: right
    material, right texture, flat result, because the renderer this project
    ships never read the texture at all. Shadows are `BLEND_MODE_MIX` with the
    falloff in ALPHA, which both backends agree about. Anything that looks
    right in the editor and wrong in a screenshot — suspect the renderer before
    the maths.
19. **A texture built with no mipmaps samples FLAT** under the default
    `LINEAR_WITH_MIPMAPS` filter, at every distance. `Build.shadow_texture()`
    calls `generate_mipmaps()` and it is not optional: without it the falloff
    exists in the image, is uploaded correctly, and never appears on screen.
    The same symptom as 18 from an unrelated cause, which is why the shadows
    took two goes.
20. **Gotcha 11 fires for a method that does not exist, too.** Calling
    `GameState.adjust_rep()` — deleted with the reputation system — is a
    runtime error, and a runtime error ABORTS THE CALLING FUNCTION, so the
    press-day complaint and the nurse who finds a tampered room had both
    silently done nothing for weeks with every test around them green.
    `smoke_impl.gd` now greps every `Autoload.method(` call site in `scripts/`
    against that autoload's real method list, because the compiler will not.
21. **A harness whose last pipeline stage is `head`, or whose runner calls
    `quit()` with no argument, CANNOT FAIL.** `check.sh` ended in `| head -40`
    and so exited 0 on every parse error it had just printed — and it is the
    "does this file compile" tool the whole project leans on. Capture the
    output, test it for emptiness, exit on that. Feed any new harness a
    deliberately broken input once and watch it actually go red.

22. **`Input.action_press()` dispatches NOTHING.** It sets the polled state of
    an action, which is all `is_action_pressed()` reads — but no InputEvent is
    created, so `_input`, `_unhandled_input` and every Control in the tree never
    hear it. Half the game listens for events: the pause key, every screen, the
    focus navigation. The first version of `play_impl.gd` used it and could not
    close the morning briefing. `Input.parse_input_event()` is the one that
    presses a button for real.
23. **The dummy display driver ignores `Input.mouse_mode`.** Setting it to
    `MOUSE_MODE_CAPTURED` headless leaves it at 0, and `Player._unhandled_input`
    gates mouse look on the capture — so mouse LOOK cannot be tested without a
    display, and a harness that tries will pass by doing nothing. `./play.sh`
    runs the keyboard plan under Xvfb, where the capture is real; the pad plan
    needs no cursor and runs anywhere.
24. **Godot binds the D-pad to `ui_up`/`ui_down` and nothing to `ui_accept`.**
    Out of the box `ui_accept` is Enter, Kp Enter and Space, and `ui_cancel` is
    Escape — no pad buttons on either — while the directions get both the D-pad
    and the left stick. So a controller could move a selection perfectly and had
    no way to press it. `Settings.PAD_UI` adds A and B. Check the defaults
    rather than assuming them: they are not symmetrical.
25. **`NavigationServer3D`'s map is EMPTY in this project** — no regions, no
    error, and `map_get_path` returns a zero-length path that reads as "there is
    no way in". The building is procedural and headless, so it navigates on its
    own deterministic A* grid: `Hospital.nav` (`NavGrid.find_path`) is what the
    nurses use and what anything else routing across the floor must use too.

26. **Godot's default `stretch/aspect` is `keep`, which pillarboxes.** Setting
    `stretch/mode = canvas_items` and stopping there pins the whole game to the
    base resolution and puts black bars down the sides of every monitor that is
    not 16:9 — on a first-person 3D game, that reads as a game that does not
    know what display it is on. `expand` widens the viewport instead: the
    camera sees more of the room and anchored Controls stay in their corners.
    Render the screenshot set at 2560x1080 after touching anything about the
    layout; it is the only way to see it, and it is how the controls reminder
    turned out to have been sitting under the patient card at every aspect.

## Systems gotchas, which have cost exactly as much

The list above is the engine's fault. These are ours, and they are numbered
with it because a lost afternoon does not care which.

27. **There is ONE clock, and it lives in `GameState`.** Every verb on the ward
    costs minutes (`WardDay.READ_COST` and friends) and those minutes were
    being spent on `WardDay.minute` alone, while the HUD, the force-end and
    everything else driven by `minute_passed` went on counting real seconds —
    so the chart said half past seven and the corner of the screen said five
    past eleven, and the gap widened the more the player did. `advance_to()`
    calls `GameState.skip_to()`, which re-enters `_on_minute` immediately;
    anything that advances the clock must therefore be re-entrancy safe.
    `end_day()` was not, and took the debt off the takings twice.
28. **Under `--headless` the root Window is 64 pixels tall.** Every Control
    lays out against it, so a card capped at `viewport height - 116` gets a
    negative height and reports as three-quarters below the fold. Layout
    measurements belong in `screenshots.sh`, which runs a real 1600x900 window
    under Xvfb. Setting `tree.root.size` does not help — the dummy display
    driver ignores it.

29. **A harness that reuses `GameState` must clear the whole carry, not part of
    it.** The playtest cleared `remembered_beds` between runs and left
    `carried_debt` alone, so from the first strategy that came up short every
    later one owed Vinnie more than the last — three successive audits reported
    a risk/reward frontier that depended on the order of the list, and "one
    well-timed lie" was recorded as worth $150 when it is worth $850.
    `_clean_slate()` clears all of it and `_day()` fails loudly if a run starts
    owing anything but `Cases.DEBT_DUE`. The one measurement that WANTS a carry
    (criterion 6) builds its ward through `_carried_day()` instead.
30. **`Cases.roster()` is a function of `GameState.day`, so anything that
    changes the day mid-run must change it back at the right moment.** Setting
    it back before `end_day()` meant the force-discharge loop walked the first
    ward's roster while the `WardDay` still held the second ward's patients, and
    every lookup errored. Reset after the review, not after the play.
31. **What a document says is not what is true, and the second ward is built on
    the gap.** `WardDay.reads_as_well()` is what the rounds, a nurse review and
    a test report; `truly_well` is what an examination and the registrar find.
    A patient marked `only_visible_in_person` differs between the two. Without
    it Adeyemi's ten o'clock round simply announced Peter Lomax and there was no
    reason to go and look at anybody.

32. **A gate on something the PLAYER does is a reward for doing nothing.**
    `_sent_home_unwell` used to `continue` unless the discharge was documented,
    examined, or overruled — all three player-initiated. So the way to make a
    wrongful discharge invisible was to never read a chart, never examine
    anybody and never ask: **information had strictly negative expected value**,
    because looking at a patient was the only way to manufacture the evidence
    that convicted you of the decision you then made. Any new rule that asks
    "did the player produce a document about this" needs a rung for "no, and
    that is worse", not an early return. `_they_came_back` and
    `_never_laid_eyes_on_them` are ungated on purpose.
33. **`WardDay.start()` runs every morning, so anything assigned in it is
    assigned every morning.** `cash = Cases.STARTING_CASH` sat there and minted
    the player nine hundred pounds a night out of nowhere — a third of a night's
    takings, under every strategy, in every measurement this project ever took,
    and it made "he takes everything at eight" vacuous because nothing survived
    the night. One-off state belongs in `GameState.start_new_career`.
34. **A verdict tier nothing reaches is content behind a trigger that never
    fires.** `struck_off()` read only REFERRED verdicts, and the money-optimal
    play lands on FLAGGED on both wards and never on REFERRED (that needs two
    indefensible beds, and every two-indefensible variant earns less). So the
    optimal player accrued zero strikes forever and the auditor never spawned.
    Score every night on a scale instead of matching a verdict NAME.
35. **A carried flag recomputed from last night lasts one night.** The auditor
    was `verdict == ESCALATED`, recomputed in `_carry`, so a single clean shift
    made her vanish. Anything meant to persist needs its own countdown
    (`auditor_shifts`), not a re-derivation.

36. **`ShaderMaterial.duplicate()` copies the shader and LOSES every parameter
    set on it.** The copy renders with the shader's defaults, silently: making
    a lighter-lined variant of a material by duplicating it turned every steel
    bed leg and the orange visitor chair cream-white, in a build that otherwise
    looked like an improvement, and nothing errored. Rebuild from a recipe
    (`Build._fit_line` records one on the original), or ask `Surfaces` for an
    unshared material and set your own `next_pass`. `get_shader_parameter()` is
    no help either — it returns null for a parameter that was set and is being
    rendered correctly.
37. **A Minkowski-summed mesh keeps the SPHERE's normals unless you recompute
    them.** `rbox_mesh` and `taper_mesh` push a sphere's vertices out to the
    corners of a box; the normals do not move. So every flat face in the
    building — a twenty-metre ceiling, a cabinet, a wall — was shaded as though
    it were curved, the normal across one flat wall wandering by up to 22
    degrees, and nothing in the frame could be crisply lit. `Build._reface`
    fixes it, area-weighted onto SHARED vertices: sharing matters twice,
    because the outline hull grows along the same normals and only stays closed
    if they are shared.
38. **A screen-space grid line must FADE when it gets denser than a pixel, not
    widen.** `grid_line`'s first version widened, so a ceiling seen at a
    grazing angle turned into a white wireframe — the bright diagonal streaks
    in every screenshot this project had ever taken. Half of the rest of those
    streaks were the sun's shadow map landing on the underside of a ceiling
    that nothing can be above.
39. **`hint_screen_texture` samples FLAT on gl_compatibility.** There are no
    screen-space effects available at all — no SSAO, SSR, SSIL, SDFGI or DoF
    either, all of which are Forward+ only. Contact darkening is painted into
    the surface shaders (the wall's floor gradient, the floor's wall gradient)
    and under objects as a blob texture. Verified rather than assumed: omni and
    spot SHADOWS, custom spatial shaders, vertex displacement,
    `MODELVIEW_MATRIX`, `fwidth`, triplanar, detail maps, vertex colours,
    emission and glow all DO work here.
40. **`ambient_light_color` is not the brightness knob and warming it proves
    nothing.** Two rounds went into the colour before anybody measured the
    ENERGY: a cream wall reads (113, 124, 129) at 0.62 and (195, 197, 194) at
    3.0. Take a reading off a render before turning anything; the ward's blue
    cast was a cool DirectionalLight3D fill, not the ambient and not the sky
    (`ambient_light_sky_contribution` is a measured no-op with
    AMBIENT_SOURCE_COLOR on this backend).
41. **A cel outline is a WEIGHT problem before it is a colour problem.** A
    sweep that re-tinted every outline material in the live ward and
    photographed the same bed under each showed pure black and a per-object ink
    to be indistinguishable, while THREE TIMES the weight was transformative. It also
    has to be trimmed to the object: the hull grows outward in every direction,
    so the standard weight on a 5cm rail is a third ink and a ward full of
    those reads as a cage.

42. **A shader that fails to compile is a surface rendered with a FALLBACK
    material, announced once and then never again.** The wall shader declared a
    local `drift` over the preamble's `varying float drift` — "Redefinition of
    'drift'" — so every wall in the building rendered as flat mid-grey with
    none of the tooth, emulsion drift, contact darkening or dado the file
    describes, and two rounds went into raising the ambient to fix a wall the
    shader was not drawing. `run_tests.sh`'s quiet check greps everything the
    game prints for `ERROR` and catches it; read that output rather than
    assuming a shader edit took, because the picture will not tell you — a
    fallback material looks like a design decision.
43. **`get_meta(key, null)` ERRORS on a miss instead of returning the default.**
    A NIL default is indistinguishable from no default inside the engine, so
    the guard has to be `has_meta()`. `Build._fit_line` runs for every mesh in
    the building and the first version filled two thousand lines of the test
    log with "The object does not have any 'meta' values with the key".

44. **`BACKLIGHT` works on gl_compatibility and does not fix a flat face.**
    Tried and measured, because "the characters have no form" is the obvious
    next thing to reach for after the normals are fixed: a wrap term on skin at
    0.28 moved 6,100 pixels by at most 27 levels, and at 0.70 — well past
    subtle — 6,300 pixels by at most 52, with the face reading identically in
    both. The reason is that the faces are not short of light. The sun is a
    DIRECTIONAL key with shadows off, so it lights the interior from
    upper-left, and ambient is 1.15 on top of it; a head is already lit from
    two directions. What makes a face read flat here is the geometry and the
    decal eyes, not the lighting, so that is where the next attempt should go.
    The term compiles and costs nothing — it is simply not the lever.

45. **The building has no windows, and putting glass in it is not enough.**
    Two things read as broken because of it and both are still open: the
    project builds a full procedural sky — sun angle, horizon and ground
    colours, re-tinted every minute as the shift runs — whose own comment says
    it is "only ever seen through the windows"; and `Room.window_open` is a
    saved, loaded state that a complaint line reads out loud ("the window is
    wide open") about a window that does not exist.
    Glazing the four exterior runs was tried and reverted, and the reason is
    the useful part: with no terrain outside, a window at eye level fills with
    the sky's GROUND hemisphere, which is a flat murky green. It reads as
    glazing painted over with sage, which is worse than a blank wall. Windows
    need something to look at first — a horizon band, a massed building, a
    distant treeline — and the dado wants rebalancing at the same time, because
    running teal up to a sill at 1.15 swallows the lower two thirds of every
    wall. Do the view before the glass.

46. **A default is only a default until somebody passes the old value.**
    `Surfaces.fabric_mat` took the weave pitch as a default and
    `Build.cloth_mat` passed the old number explicitly, so raising the default
    reached nothing at all: every piece of cloth in the game kept the old pitch
    while the shader's own comments described the new one, and the commit
    message described a change that had not happened. Same class of fault as a
    constant nothing reads, and quieter — the code and the comment disagree,
    and the picture sides with the code. Numbers a shader is tuned on live in
    ONE place (`Surfaces.WEAVE`), never as a default plus a literal.

## Design rules that are load-bearing

- **Nothing tells the player to press a key by name.** There is a rebinding
  screen and a controller layout, so a string literal saying "[E] use" is wrong
  for anybody who has touched either — and four places had one, including the
  first line on the title screen. `Settings.prompt_label(action)` is the only
  honest answer and it prefers the pad when one is plugged in;
  `Settings.binding_label` is the different question the rebind rows ask and
  stays a key. The smoke run greps for the literals.
- **Nothing in the UI is ever labelled "questionable".** No suspicion cost, no
  recovery delta, no "+3 days". A chart shows what it says and what it pays,
  and nothing anywhere scores the player's choice for them. Developer-facing
  truth is in `docs/SPOILERS.md`; the player gets it by watching what happens
  at the review, twice. (There was a Codex that wrote them a line after the
  second time. It went with the redesign, and the only thing left of it was a
  lookup in `StaffNPC` for a group nothing has been in since — guarded, so it
  read as a working feature.)
- **Suspicion is derived, never stored.** It is a read over the `Evidence` a
  `Mind` holds. Never add a "suspicion += x" anywhere; emit a `WorldEvent` and
  let perception decide who noticed.
- **Three layers are allowed to disagree**: truth (what the `Cases` entry says
  the person is actually like), record (the `ChartEntry` list in `Records`),
  and belief (what `Mind` holds, and what Sister Nkemelu asks you about). All
  the comedy is in the gaps, and the whole audit is a read across them.
- **`Cases.ADMISSION_FEE` against `Cases.DEBT_DUE` is the load-bearing pair.**
  Turnover must not beat duration on a five-bed ward or the premise inverts —
  the whole game is *this bed is worth more with somebody in it*. The data
  check asserts the inequality directly, per ward: five beds held honestly earn
  less than the best three. If that ever flips, the game is about discharging
  people quickly and there is no story in it.
- **A day is one place and one clock.** There is no evening phase and no legal
  phase; both were cut. The ward runs 08:00 to 20:00, every verb costs minutes
  off one clock in `GameState`, and the day ends at the office desk with the
  handover. `ShiftSystem`, `NightSystem` and `LegalSystem` are gone — if you are
  reading about them somewhere, that document is older than this one.
- **Six verbs, and every one of them costs time.** Write it yourself (8 min),
  lead the patient (10), send a nurse (15), order a test (5, back in 75),
  examine them (15, and it writes NOTHING), ask the registrar (25, and only
  during his hours). The costs are the game: the day is not long enough to do
  all six on all five beds, so a day is a budget rather than a checklist. Add a
  verb by adding a cost constant and a `WardDay` method that writes a
  `ChartEntry` with an honest `author` and `written_minute`.
- **Information must never have negative expected value.** This is the rule the
  career rework exists to enforce, and it was broken for three iterations:
  examining a patient wrote nothing to the chart, so the only thing looking at
  somebody did was manufacture the knowledge that convicted you of ignoring it.
  Anything that makes the player *less* willing to find out what is true has
  inverted the game. `_never_laid_eyes_on_them` is the counterweight — three
  blind decisions is itself a finding.
- **A finding is a severity, not a gate.** `_sent_home_unwell` is a ladder
  (0.85 if a peer said otherwise, 0.72 if you examined them, 0.58 if it was
  merely documented, 0.55 if you never looked). A boolean gate is a cliff the
  player learns to stand exactly one inch from.
- **Decoration has no collision and no navigation footprint.** Everything in
  `Dressing` is scenery; if it needs to be usable it belongs in `Furniture`
  with an `_occupy()`. That rule is what lets there be a lot of it.
- **The career score is a pure read over `DoctorRecord`.** A system that has to
  remember to escalate is a system with an escalation bug in it. Her opening
  line, the weight of a repeated finding, which excuses she will still hear,
  and whether you are still a doctor are all derived from four counters and a
  strike total that never reset. There are no achievements and no stats
  dictionary — both existed, both were read by nothing, and both were cut.
- **Content lives in `Cases`, and adding a patient must not require touching a
  system.** Forty people across four wards, each a dictionary of authored
  strings; `tests/probe/data_run.gd` walks every one and fails on any field a
  system would otherwise silently default. If a new kind of patient needs a new
  `if` in `WardDay`, the data model is wrong, not the patient.
- **A ward is five SLOTS, not five people, and `bed` is the slot id.** Several
  authored patients share a bed number and exactly one of them is in it on any
  given night, drawn as a pure function of the career seed. This exists because
  a career is nine nights and the second one had no game in it — you remembered
  which bed was genuinely ill, and the whole investigation layer became a
  formality. Candidates for a slot MUST have the same `tier` and the same
  `truly_well` as each other; the data check enforces it, and it is what stops a
  draw producing a ward with no honest hold or a different economy. Seed 0 is
  the canonical ward and is what every test and every authored measurement
  plays — `setup()` pins it.
- **Anything seeded gets its distribution counted, not eyeballed.** The draw has
  been broken twice in a way that dealt the same two games forever while looking
  perfect in the game, the tests and the data check: once because `hash ^ seed`
  only mixes at the bottom bit (which is the only bit that matters when a slot
  has two candidates), once because Godot's String `hash()` does not spread into
  that bit either. Also: the textbook splitmix64 constants do NOT fit in a
  signed 64-bit int and GDScript mangles the literal rather than wrapping it.
  `tests/probe/draws_run.gd` counts distinct wards over two thousand seeds.

## Testing philosophy

`tests/` has twelve layers, and each has caught things the others could not:

| Layer | Catches |
|---|---|
| unit + integration (`tests/run_tests.gd`) | maths, serialisation, the audit rules, floor connectivity — 297 assertions across `test_compile.gd`, `test_suspicion.gd` and `test_ward.gd` |
| `smoke_run.gd` | "everything compiles and nothing works" — 161 checks through the real tree, and then the whole file again on two wards it has never seen. Every check in it used to name its patients ("oduya", "blake"), so it could only ever run against one of the thirty-two boards the first ward alone can deal; pointing it anywhere else produced eight failures that were all the harness. `SMOKE_SEED` overrides. |
| `playtest_run.gd` | design inversions, over 31 authored strategies — twenty-three on the first ward and eight on the second. Seven criteria, and it exits non-zero when one regresses. The seventh is the frontier: the spread must not be flat, and the biggest day in the table must not be a clean one. It was pointed at a field Vinnie drives to zero on every night but the last, and ranked 31 strategies by a constant for four iterations without anybody noticing, because a sorted column of zeroes is a sorted column. |
| `look.sh` | nothing on its own — it is `screenshots.sh` with twenty-one frames taken out. Twenty minutes is the wrong loop for a shader, a light or a line weight, and every graphics decision in this project that was made without a picture in front of it turned out to be wrong. It fails on a shader that did not compile, which is the one fault a picture will not show you. |
| `screenshots.sh` | anything you can only see — and the two things it MEASURES, because a real 1600x900 window is the only place a layout is real: how much of a card is below the fold, and what the card is sitting on top of. The second found the controls reminder buried under the patient card, with three letters of "pause" showing past its edge. |
| the fixture audit (in `smoke_run.gd`) | anything standing on nothing. Every `Fixture`'s footprint is tested against everything underneath it and reported as "chair floats by 4cm" or "bin is sunk by 11cm" — the failure two pieces of code that do not know about each other produce when they furnish the same square metre. |
| `tests/probe/data_run.gd` | the authored content itself — forty people across four wards, every field a system will silently default if it is missing, and the one inequality every ward must satisfy (five beds earn less than three). The property tests assert what the game DOES; this asserts what it is made of, which is where a content bug lives. In `run_tests.sh`. |
| `tests/probe/career_run.gd` | anything that only exists ACROSS days — the carry, the remembered beds, the denser rounds after a flag, the debt that grows on a short night. Plays twenty nights eight ways (coast, honest, honest+corroborated, restrained, skilled, one lie, greedy, adaptive). It found that `remembered_beds` was dead across a roster change and that `auditor_present` did nothing at all; after the rework it is the harness that proves crime pays only if you can stop. The six properties: honest play pays it off, a RESTRAINED liar pays it off faster, doing it every night does not, greed is struck off first, never looking at anybody NEVER pays it off, and one bad night is recoverable. Run on three seeds, because nine wards drawn from four pools is not the same nine wards twice; `CAREER_SEED` overrides. |
| `tests/probe/frontier_run.gd` | dominant strategies. 2,601 plays a ward — every subset of beds up to three, crossed with thirteen ways of justifying a hold, crossed with whether you MIX them (a peer behind the bed that deserves one, your own note on the bed that does not), crossed with whether the day was played DILIGENTLY, crossed with how you answer in the room — reported as the most money made at each verdict. Two properties: **the top figure must not be reachable signed off**, and **every ward must have an honest day that signs off**. The second is why the 2,601st play is not a strategy at all but the day a careful person plays, written out by hand: the search alone reported ward four as having no clean day, and that was a claim about the search. In `run_tests.sh`; re-run it after touching the economy, the contradiction rules, the bed audit or a roster. |
| `play_run.gd` (`./playfast.sh`, `./play.sh`) | whether it can be PLAYED, and whether it can be FINISHED. Every other layer reaches past the input layer and calls the method a keypress would have called, so all of them pass on a build where nothing is bound to anything. This one presses the buttons: closes the briefing, walks the doctor to a bed on the stick, aims with the other stick, taps use, moves the selection on the card that opens and backs out. On its first run it found that a pad could look all the way round the ward without taking a step (the four move actions had a key each and no axis), that no screen in the game ever took focus, and that A and B were not bound to `ui_accept`/`ui_cancel` at all — on a build whose own Controls screen promised the opposite. Three plans. `pad` and `keys` are the first two minutes — the briefing, a walk across the ward, a card opened and navigated. `day` is the whole shift, played the way a stranger gets it — the tutorial ON, which nothing else in this repo has ever done: a chart read and a note written on the pad, five beds walked to and decided, the office found through a shut door, the records opened, the shift signed off, the ward sister answered until the End of Shift card is up, and "Work tomorrow" pressed into the next morning. `pad` and `day` are in `run_tests.sh` and cost three seconds each; `keys` needs a real captured cursor, so it lives in `./play.sh` under Xvfb. |
| the quiet check (in `run_tests.sh`) | anything the game PRINTS while it is being played. `boot_check.sh` asserts this for the way in and stops at the title screen, so nothing had ever looked at what Game.tscn says once it is loaded — which is where the world, the NPCs and every system are. It cost a warning on every launch of the shipped build: the environment enabled SSAO, which is Forward+ only, on a project that ships Compatibility. Six harnesses ran past it. It reads the UNIT run too, which it did not: that one had been printing "Cannot call method 'queue_free' on a previously freed instance" twice on every invocation, from two tests that tidied up a ward `setup()` had already freed, and the throw took the line after it with it. A check that watches one surface reports on one surface. |
| `boot_check.sh` | the real entry point. Everything else instantiates Game.tscn directly and skips Boot and the main menu, which is how "the game is unplayable from the main menu" survived 1,500 assertions. |

`playtest_run.gd` exits non-zero when a success criterion regresses, so a
design inversion fails `run_tests.sh` rather than printing a report nobody
reads. A test that asserts NOTHING is failed by the runner: reading a key a
dictionary no longer has aborts the function without erroring, so the
assertions after it never run and the suite reports green.

Where a fix corrects a subtle behaviour, add the test that would have caught it
and say in the comment *why* the obvious thing was wrong.
