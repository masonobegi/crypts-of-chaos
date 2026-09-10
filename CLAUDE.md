# Working on Chronic Care

Godot 4.3 project, GDScript. No art and no audio assets — every mesh is built
from primitives at runtime and every sound is synthesised on first play. The one
exception is TYPE: `assets/fonts/` carries four OFL-licensed families with their
licences beside them, because a letterform is not something you can reason your
way to from primitives and the engine's stock face on every screen is the
loudest single tell that a game was made in an afternoon. See gotcha 51.

## Always

```bash
GODOT=/path/to/godot ./run_tests.sh      # all of it, ~4 min
GODOT=/path/to/godot ./check.sh scripts/foo.gd   # parse errors for specific files
GODOT=/path/to/godot ./screenshots.sh    # render offscreen, photograph every room and screen
GODOT=/path/to/godot ./look.sh try1      # four vantages, for tuning a shader or a light
GODOT=/path/to/godot ./faces.sh try1     # six faces close up, for tuning a CHARACTER
SHOT_ONLY=struck_off GODOT=/path/to/godot ./screenshots.sh   # one frame, ~90s
GODOT=/path/to/godot ./export.sh all     # windows, linux, macos — and RUNS the linux one
GODOT=/path/to/godot ./playfast.sh day   # play a WHOLE SHIFT with a controller
GODOT=/path/to/godot ./play.sh keys      # play it with WASD and a real mouse, under Xvfb
```

`run_tests.sh` is 363 assertions, a 263-check smoke run through the real tree
on three different wards, 39 playtests against seven success criteria, the
authored-data and draw checks, a career played eight ways on three seeds, a
2,601-strategy adversarial search per ward plus an honest day on all 128 boards
the game can deal, two playthroughs driven entirely by
the input actions a controller sends — the first two minutes, and a whole shift
from the briefing to the next morning — a check that the game prints nothing it
should not while being played, and a boot through the real main menu. Every
phase exits non-zero on its own and the runner reports which.

Three seeds are overridable, and it is the cheapest way to catch a harness that
only works on the board it happens to have been written against:

```bash
SMOKE_SEED=99    godot --headless --path . --script res://tests/smoke_run.gd
CAREER_SEED=99   godot --headless --path . --script res://tests/probe/career_run.gd
FRONTIER_SEED=99 godot --headless --path . --script res://tests/probe/frontier_run.gd
PLAY_SEED=99     godot --headless --fixed-fps 60 --path . --script res://tests/play_run.gd -- day
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

45. **A window shows a NARROW SLICE of the world, and everything outside has
    to be sized for it.** From an eye at 1.7m through a sill-1.05/head-2.30
    aperture four metres away, you see about three degrees below the horizontal
    to nine above. Anything close is cut off at the knees, anything short is
    under the sill, and — the one that cost a render — anything tall and near
    fills the whole band and occludes everything behind it: a nine-metre
    treeline at forty-five metres gave a hundred and fifty pixels of flat green
    where the sky and the town should have been. Trees are three to four
    metres now. Three rings at three depths, each darker and bluer than the one
    in front, because at the grass's own lightness a treeline is just more
    grass. RINGS, not scattered blocks: a window on any of four walls has to
    find something to look at.

46. **Ink is constant in PIXELS; the object is not.** So the ink's share of a
    thin object grows without limit with distance, and a cap on the outline's
    WIDTH bounds it at exactly one distance — which is why trimming the width
    cancelled the gain and fixed nothing. The ceiling has to be in METRES, in
    the shader: `min(weight * dist, max_grow)` with `max_grow` a share of the
    object's own thinnest dimension (`Build.INK_CAP`). Without it a 5cm dado
    rail at five metres is eleven pixels wide with eight pixels of ink each
    side, and a corridor reads as two black diagonals with a wall behind them.

47. **DONE, and the note is kept because the ORDER was the whole lesson.**
    The building had no windows, and putting glass in it was not enough:
    two things read as broken because of it: the
    project builds a full procedural sky — sun angle, horizon and ground
    colours, re-tinted every minute as the shift runs — whose own comment says
    it is "only ever seen through the windows"; and `Room.window_open` is a
    saved, loaded state that a complaint line reads out loud ("the window is
    wide open") about a window that does not exist.
    Glazing the four exterior runs was tried and reverted ONCE before it
    worked, and the reason is the useful part: with no terrain outside, a
    window at eye level fills with the sky's GROUND hemisphere, a flat murky
    green that reads as glazing painted over with sage — worse than a blank
    wall. `Hospital._build_outside` now exists and runs first, and the dado
    stops at the sill on exterior runs because teal to a sill swallows the
    lower two thirds of a wall. Do the view before the glass.

48. **A default is only a default until somebody passes the old value.**
    `Surfaces.fabric_mat` took the weave pitch as a default and
    `Build.cloth_mat` passed the old number explicitly, so raising the default
    reached nothing at all: every piece of cloth in the game kept the old pitch
    while the shader's own comments described the new one, and the commit
    message described a change that had not happened. Same class of fault as a
    constant nothing reads, and quieter — the code and the comment disagree,
    and the picture sides with the code. Numbers a shader is tuned on live in
    ONE place (`Surfaces.WEAVE`), never as a default plus a literal.

49. **THE CAMERA YOU JUDGE FROM IS PART OF THE JUDGEMENT.** `look.sh`'s wide
    vantage sat at 2.6m under a 3.25m ceiling — 65cm of headroom — and every
    graphics decision about the ceiling for the last three passes was made from
    it. From up there the ceiling fills the top half of the frame at a near
    grazing angle and its 0.6m grid fans out from the vanishing point into
    broad diagonal bands, and those bands were blamed in turn on the sun's
    shadow map (gotcha 38), on the tile runner being too strong, and on noise
    aliasing. Each fix was real and none of them touched it, because there was
    nothing to fix: rendering the ceiling with each shader term switched off
    put the horizontal standard deviation at 9.33 with the runner and 5.92
    without it, then splitting the runner into its two axes showed the "bands"
    were simply `line.y` — lines of constant world z, drawn correctly, seen
    from a place no player can stand. At the player's own 1.7m they are not
    there at all. The tuning vantages are all eye height now; `screenshots.sh`
    keeps the high wide shot because a store page wants one.
50. **`grid_line`'s argument applies to every procedural pattern, and only
    `grid_line` was making it.** A line finer than a pixel has to fade rather
    than widen — and so does a noise finer than a pixel, and every surface in
    `Surfaces` sampled one at 24 to 60 cycles per metre with no guard at all.
    `detail_fade(q)` takes the pattern coordinate AFTER scaling, so `fwidth(q)`
    is literally cycles per pixel; a symmetric term fades to its mean (0.5) so
    the surface does not change brightness with distance, and a mask fades to
    zero. Aim it at the FINEST octave: `fbm2` runs its second at 2.7x the
    coordinate it was handed.
51. **The typefaces are load-bearing and their failure is invisible.** Four OFL
    families in `assets/fonts/`, with their licences beside them, and the
    mapping from `ChartEntry.Author` to a face lives in ONE place
    (`Typeface.for_author`) because the chart, the records screen and the
    review all quote the same line: your own notes are in handwriting, a
    colleague's in the interface sans, reported speech in italic, a machine's
    result in mono. A font that fails to load leaves `add_theme_font_override`
    with null, Godot falls back to the stock face, and the game looks exactly
    as it did before any of it existed — no error, no missing text. The smoke
    run asserts every face loads and that the licences ship. The root theme is
    applied from `Settings._ready()` and NOT from `Boot`, because every harness
    in this repo instantiates Game.tscn directly and would otherwise photograph
    a different game to the one that ships.
52. **Everything positional goes through a reverb bus; nothing else does.**
    Every sound in the game was dry, which is the loudest "made in a week" tell
    an interior game has — a hospital is hard floors and long straight runs and
    is one of the more reverberant places a person is ever in. `AudioMgr`
    builds a `World` bus with one `AudioEffectReverb` and routes the 3D voice
    pool to it; the music and the UI clicks stay dry on Master, because a
    button that echoes is a button in a cave. Wet is 0.20 on purpose: the point
    is not that you notice a reverb, it is that you stop noticing its absence.
    The smoke run asserts the bus exists, carries a reverb, and has every
    positional voice on it — none of which any other check can see.

53. **A Control that is built and never parented is LEAKED, and it is the
    quietest fault in this repo.** Nothing renders wrong, nothing errors, and
    Godot mentions it once at process exit as `5 RIDs of type "CanvasItem" were
    leaked` — a line that printed after every day run for as long as that
    harness has existed, in the middle of a page of PASSes, and cost nothing,
    so nobody chased it. It was `screen_review.gd`'s citation box on a finding
    that cites nothing: built, then not parented on that path, once per rebuild
    — and the review rebuilds on every answer, so a player accumulates them for
    the whole shift. `free()`, not `queue_free()`: an orphan has no frame
    boundary to defer to. `run_tests.sh` fails the day run on any `RIDs of
    type` line now (`ObjectDB instances` stays filtered — that one is the
    audio server being yanked by `quit()`, and boot_check.sh explains it).
    Proven red by putting the leak back.
54. **The head is what you read at three metres, and every head in the building
    was the same one.** `Appearance` varied skin, hair colour, gown, height and
    girth — and a ward of five still came back as one man in five gowns,
    because height and girth scale a BODY and a body is a coat. `skull` (non
    uniform, independent per axis, so the cast has long faces and round ones
    rather than five sizes of one), `nose`, `jaw` and `hair_style` are what
    actually separate people. Applied to the SILHOUETTE pieces — skull, ears,
    jaw, hair — and never to the `_head` node, because the brows rotate for
    expressions and a rotated child of a non-uniformly scaled parent shears.
    Hair COLOUR is close to invisible across a lit ward; a hair SHAPE is not,
    which is why there are five cuts and they cost two spheres each.

54b. **THERE WAS NO NECK, and it is the loudest primitive tell a body has.** The
    chin sat at 1.285 and the collar's top edge at 1.38, so the head was ten
    centimetres INSIDE the shoulders: photographed from three metres the jaw
    rested on the collar and the cast read as a rack of skittles. It is louder
    than the hands and louder than the flat gown, because a neck is the one part
    of a person the eye checks without being asked. The trunk keeps its hip line
    and loses six centimetres off the top, the head goes up eight, the chin
    lands at 1.37 and five centimetres of throat shows. The crown ends at 1.80
    rather than 1.72, which is a person rather than a short one. And a rounded
    sleeve end beside a rounded trunk leaves a dark vertical seam between two
    separate solids — one sphere in the gown's colour, tucked INTO the join
    rather than capping the shoulder, is the difference between an arm attached
    to a body and a sausage laid against a slab. Capped too high and too proud
    it reads as an epaulette, which is what the first attempt looked like.
55. **The title screen is the first screenshot anybody sees of this game, and
    it was lit like a different one.** `MenuScene` carried its own copy of the
    grade — a sky-blue ambient at 1.05, exposure 0.80, white 2.6, saturation
    1.22 — while `Game` carried the swept, measured one (warm-neutral 1.15,
    0.70, 3.2, 1.35). Two copies of a tuned number is gotcha 48 again, and a
    LOOK is the one thing where the divergence is guaranteed to be visible.
    `Grade.apply(env)` is the single definition; only the background differs,
    and it has to (the ward has a sky it sees through windows, the title
    vignette is one room with no outside). The menu room was also built out of
    `Build.wall` and `box_mi` — one flat albedo per square metre — so the
    screen whose whole job is "the first frame looks like the game" had none of
    the tile, speckle, paint tooth or contact shading of any room behind it. It
    uses `Surfaces` now, like everything else.

56. **`RIM` IS ADDED PER LIGHT, and a ward has a fitting every five metres.**
    Godot scales the rim term by each light's energy and attenuation and sums
    it, so four ceiling fittings at `SPOT_GAIN` 4.4 and `FILL_GAIN` 3.1 deliver
    it four times over. `cloth_mat` carried 0.55 and `prop_mat` 0.42, both set
    when the building was lit by a single dim omni per room — and after
    `ceiling_light` was split into a shadowed spot plus a fill and the gains
    went up, the term stopped supplementing the shading and started erasing it.
    Measured on the real frames: the figure box in `20_struck_off` is **28.8%
    pure 255** at 0.55 and **0.3%** at zero, and the sweep between is a cliff
    rather than a slope (0.22 → 26.8%, 0.10 → 17.5%, 0.05 → 1.7%) because the
    term saturates the moment several lights agree. It was not only characters:
    side by side, the rim turned Adeyemi's blue scrubs into a white blob, the
    nurses' station counter into a white slab, the notice board into a blank
    yellow rectangle and every bed in the ward into a featureless white shape.
    `Surfaces.RIM_EDGE` is one constant, set from GDScript into both shaders,
    and it is 0. Third instance of the same fault after the ceiling's
    `self_lit` and the fabric's weave pitch: a number tuned against a world
    that has since moved, still doing exactly what it was told.
57. **`SHOT_ONLY=struck_off ./screenshots.sh` renders one frame.** Twenty-one
    frames is twenty minutes on a software rasteriser, and four attempts at the
    rim fault above went into building synthetic scenes to avoid paying it —
    none of which reproduced anything, because the fault needed the real
    staging. Reproducing the actual frame took ninety seconds and settled it on
    the first try. The staging still runs in order (several stages depend on
    the ones before them); only the save is skipped.

58. **A duck that is applied and never released is a permanent setting.** The
    score steps back nine decibels over the last forty minutes of a shift so
    the ward, the monitors and the heartbeat come forward — one piece of music,
    used rather than replaced. The half that is easy to forget is the release:
    `AmbienceSystem._pulse_pass` returns early outside the window and has to
    call `duck_music(0.0)` on that path, because the next morning is the same
    audio server and a career is nine nights. Both halves are asserted in the
    smoke run, and only the second one could have failed silently — nothing on
    screen says what the music is doing.

59. **A LOOP IS AS LONG AS THE THING IT PLAYS UNDER.** The score was taken from
    a sixteen-second loop to ninety-four for exactly one stated reason — "the
    loop point is now four times further apart than the longest thing anybody
    does in one place" — and the ROOM TONE, which plays under the whole twelve
    hours, was left at three seconds with a seeded noise floor, so it repeated
    identically about fourteen thousand times a shift. Eleven seconds now, plus
    one slow breath per loop so the tone is not a synthesiser holding a note.
    The constraint that makes it seamless without a cross-fade is that every
    partial fits a WHOLE number of cycles in the buffer (50 Hz × 11 s = 550,
    74 Hz × 11 s = 814); pick a length that leaves either mid-cycle and it
    clicks once per loop forever, under everything, where nothing else in this
    repo would ever hear it. `AudioMgr.HUM_PARTIALS` exists so the smoke run
    can check the arithmetic, and it was proven red with a length of 11.017.

60. **THE EYE IS A MARK, NOT A BALL, and the sclera was the whole problem.**
    Every character had a big white oval with a dark disc floating in it, and
    three separate fixes are recorded above it — the whites came down a third
    for "swimming goggles", the pupil was flattened for "walleyed", the pupil
    was grown for "permanently surprised". Each was real and each was a symptom
    of the white being there at all. A solid dark almond with ONE catchlight is
    what a stylised eye is, and nothing is lost by dropping the sclera because
    NOTHING IN THIS GAME EVER MOVED A PUPIL: gaze is carried entirely by
    `look_toward` turning the head, and it is still legible at four and a half
    metres. The catchlight is not mirrored between the eyes — there is one sun
    — and it is what keeps an eye visible on the darkest skin in
    `Appearance.SKIN`, where a dark almond has very little else to work with.
    A closed eye is a dark LINE in the same colour, not the old skin-coloured
    bar, which on a light face was nothing at all.
61. **THE HAIR CAME DOWN TO THE EYEBROWS ON EVERY CHARACTER.** The forelock's
    bottom edge sat at y=-0.014 — below the brows at 0.052 and below the eyes
    at 0.008 — and the crown's front face reached z=0.194, in front of the eyes
    at 0.184. So the crown was the hairline, the forelock was decorating a
    helmet, and the whole cast had no forehead. The crown is pulled back to own
    the top and the back; the forelock is raised to own the front edge and
    leaves about three centimetres of forehead. It is the single change that
    stopped these reading as blocky, and it is worth more than any amount of
    lighting work.
62. **`./faces.sh` — six faces, close up, in the game's own light.** Character
    work was being judged from `screenshots.sh` (twenty-one frames, twenty
    minutes) or from `look.sh`'s lineup, where a head is sixty pixels tall.
    Neither is a loop you can do an art pass in, which is how a hairstyle that
    is invisible from the front got shipped. Six draws through `Appearance`, so
    what is photographed is what ships, each from eighty centimetres, then the
    whole cast together. **Two harness faults cost a render each and both looked
    exactly like modelling faults**: subjects spaced five metres apart from
    x=2.5 in a twenty-metre corridor put the last two OUTSIDE the building,
    falling, so their portraits framed the top of a skull and I nearly went and
    "fixed" `_tick_look`; and the cast camera four and a half metres back in a
    four-metre-deep corridor photographed the far side of a wall. It asserts
    nobody is falling now. When a subject looks wrong, check where it is
    standing before you change the model.

63. **A FLAT FRONT FACE INSIDE A ROUNDED RIM IS A SANDWICH BOARD.** The torso
    was a taper 0.70 wide and 0.36 deep with a corner radius of 0.13, which
    leaves a flat front 0.44 across bounded by a 0.13 curve — so the chest was a
    big evenly-lit panel with a darker border, the arms read as being BEHIND a
    slab rather than attached to a body, and every character in the ward looked
    like they were wearing a bib. Deeper and much rounder (0.40 deep, radius
    0.17) leaves a small flat front and a wide soft turn, which is a chest. The
    same arithmetic applies to anything built from `taper_mesh` or `rbox_mesh`:
    the ratio of radius to half-depth is what decides whether it reads as a
    solid or as a board.
64. **Two legs need a gap, and it is about two centimetres.** At sx*0.145 with a
    thigh 0.20 across, the inner faces sit 45mm off centre each — nine
    centimetres of daylight between the thighs, which at four metres reads as
    two poles. At 0.118 the gap closes entirely and hip-to-ankle becomes one
    column with a seam down it, which is a different wrong answer. 0.129. And
    an arm that hangs at exactly vertical on everybody is a rack of mannequins:
    `ARM_REST_X`/`ARM_REST_Z` put a few degrees of forward and outward in it,
    and `set_in_bed` restores to those rather than to zero. None of this is
    visible on somebody lying in a bed, which is why it survived until there
    was a harness that photographs people standing up.

65. **A GDScript lambda captures a local BY VALUE.** `var seen := false` then
    `sig.connect(func(): seen = true)` sets a copy, and the variable outside is
    still false however many times the signal fires — so a check written that
    way can never pass, and one written as `var bad := false` can never fail.
    It cost a false failure in the smoke run on the first attempt at asserting
    that deciding a bed emits `money_changed`. Anything a callable writes to
    has to be a container (`var fired := [0]`), which is a reference.
66. **The player was never told what anybody actually was.** `truly_well` is the
    hidden boolean the whole investigation layer exists to deduce, and it was
    exposed in exactly two places: `examine`, which costs a quarter of an hour
    and returns a sentence, and by implication when a finding happens to name
    it. So a bed you KEPT that was perfectly well, and that Sister Nkemelu did
    not query, produced no correction at all — over a nine-night career the
    player got fewer than nine pieces of evidence about a question they were
    asked forty times and never saw the answer. That is why a second career was
    execution rather than deduction. The End of Shift card reads all five beds
    back now: what you did, and what they were, flat, in that order, with no
    score attached — the rule that nothing grades the player's choice for them
    is about JUDGEMENT, not about facts.

67. **`AudioStreamPlayer.playing` reads FALSE while the tree is PAUSED.** It
    asks the audio server whether the playback is active, and a playback
    belonging to a node in a paused tree is not — so a looping emitter that is
    running perfectly reads as stopped for as long as any world-pausing screen
    is open. It cost an hour and, worse, it produced a plausible wrong fix.
68. **A smoke assertion deferred N frames on a piece of UI STATE is not testing
    that state.** `_check_the_ward_is_audible_behind_a_card` set
    `clock_running = false` and asserted three frames later — and passed with
    the broken guard restored, because half the checks in `smoke_impl` open and
    close a screen and `UIRoot._set_modal(false)` puts the flag back on the way
    out. Gotcha 14 says an assertion in the same frame as its setup reads last
    frame's value; this is the other end of it. Anything a neighbouring check
    can reset has to be asserted synchronously.
69. **The other half of gotcha 20 is a PROPERTY READ, and the grep could not see
    it.** `smoke_impl._calls_on` requires a `(` after the identifier, so
    `GameState.stats.items_broken += 1` was skipped — and a read of a member
    that does not exist throws exactly like a call to a method that does not,
    which aborts the function. `Prop._break()` had therefore done nothing since
    the stats dictionary was deleted: no `item_broke`, no `room.soil()`, no
    `prop_broken` WorldEvent, no darkened material, no flattened mesh. A prop
    broke, made a glass noise, and stayed pristine on a spotless floor. The
    ship probe walks the reads too — ninety of them.
70. **A SEED IS NOT A POSITION, and a 64-bit value does not survive JSON.**
    Every `chance`/`pick`/`randf_s` advances the stream it names, so a stream is
    (seed, position) and `RNG.save_state` returning `{"seed": ...}` saved half
    of it — a load rewound every stream to draw zero, deterministically. It
    never actually fired, because RNG was not a registered save provider at all
    and a continued career simply inherited whatever the title screen left
    behind. And `RandomNumberGenerator.state` is a full 64-bit value while JSON
    has one numeric type and it is a double, so written as a number every stream
    resumes a few draws from where it stopped. It is saved as a decimal STRING.
71. **A save provider bound to an object that is replaced every morning saves
    nothing, and reads as working.** `SaveSystem.register("records",
    ward.records.to_dict, ...)` binds two Callables to the `Records` instance
    alive at `Game._ready()`; `ward.start()` then assigns a fresh one every
    morning, so from the first frame of every career the provider serialised an
    orphan. Register a callable that LOOKS THE OBJECT UP, never one bound to it.
72. **`FileAccess.WRITE` truncates, so a save written straight to its own path
    has a window in which a crash leaves a zero-length file where nine nights
    were.** Write a `.tmp`, rename the old file to `.bak`, rename the temporary
    into place, and fall back to the `.bak` when the primary will not parse.
    And `JSON.parse_string` pushes the engine's own error on top of yours, so a
    player with one damaged save got two errors in the log, the first about a
    line number in a file they have never opened — `JSON.new().parse()` returns
    the code and says nothing.
73. **A load that refuses only what will not PARSE is not a load that refuses.**
    `[1,2,3]`, `{}` and a save from a newer build all parse as dictionaries and
    went into `GameState.from_dict`, which defaults every field it cannot find —
    day 1, no cash, seed 0 — WITHOUT `start_new_career`, so Continue produced
    something that looked like a new career and was not one. Validate the shape
    and the version, not the syntax.
74. **Filtered noise CAN loop seamlessly, and the trick is a warm-up rather than
    a cross-fade.** The filter's state is zero at the top of the buffer and
    whatever the last few hundred samples left it at the bottom, and the
    difference is a click once per loop forever — gotcha 59's fault in a new
    place. But the noise is SEEDED, so the samples before position zero are
    knowable: run the filter over the buffer's own tail first and start from the
    state that leaves. **And a seam cannot be measured sample by sample once
    there is noise in the loop** — two seam detectors were written and both were
    noise-dominated, reading 0.66 of a typical step on the good buffer against
    0.83 on one deliberately broken with the length gotcha 59 was proven red
    with. The smoke run checks the arithmetic and the spectrum instead.
75. **A recipe table is tuned against the level it produced.** A band-pass at
    Q 1.2 throws away six to ten decibels of a noise burst, so putting eleven
    recipes onto a filter would have quietly dropped every one of them below the
    level its call sites were mixed at — and the peak check would have gone red
    for the wrong reason. Normalise the peak after any change to the synthesis,
    so `volume_db` at a call site still means what it meant.
76. **`boot_check.sh` stops at the main menu and every other harness starts
    after it, so the step between them — the button a player presses first — had
    never been executed by anything.** That was survivable while New Career was
    one synchronous `change_scene_to_file`; it stopped being survivable the
    moment there was a loading screen in front of it.

77. **A STUB CHECKED LAST IS A STUB THAT IS NEVER CHECKED.** `WardDay.witness_stub`
    exists because no probe builds a world, so `seen_by` was empty in all 2,601
    strategies a ward and `_written_in_front_of_them` — 0.62, and in the
    CONTRADICTED list — could not fire in the search whose entire purpose is
    that a dominant strategy has to hide from a SEARCH rather than from an
    author. The fix set the stub in four probes, with eight lines of comment
    each saying why... and read it *after* `if not is_inside_tree(): return`.
    Every probe runs its whole search inside `_initialize()`, where a node
    added to the root is NOT in the tree (gotcha 5) — so the early return fired
    first, every time, and the stub never reached a single entry. The fix for
    "the probe searches with a detector switched off" was itself switched off,
    in the same way, by the gotcha its own comment cites. Live now: 9,402
    `written_in_front_of_them` and 724 `she_was_standing_there` across the four
    searches, and the frontier's headline numbers did not move, which is the
    result you want from turning a detector on — the properties held without it
    and hold harder with it. Any fallback of this shape belongs ABOVE the guard
    that decides there is no real answer, not below it.
78. **Gotcha 30 in a new place, and it looked exactly like a broken screen.**
    `Cases.roster()` is a pure function of `(day, seed_value)`, and
    `smoke_impl` re-seeds itself mid-run to visit wards it has never seen — so
    the End of Shift readback check asked `roster()` for five names while the
    `WardDay` in the tree, and the card built from it, held a different ward's
    five, and reported all five as missing from a readback that was perfectly
    correct. It only showed on `SMOKE_SEED=0`, which nothing runs by default.
    Anything asserting about what is ON a card has to ask the object the card
    was built FROM.
79. **A noise has a radius, and a check that ignores it is asserting something
    the game deliberately does not do.** `a clatter wakes the dozing ward`
    dropped a twelve-metre `prop_noise` at the first sleeping patient and
    demanded all of them wake. It passed on the three pinned seeds and failed
    on seed 99, where the draw put a dozing patient more than twelve metres
    away — the rule WORKING. Assert on the people who can hear it
    (`perception.can_hear`), and report the ones who cannot. Found by sweeping
    seeds, which is the fourth time.
80. **A THIRD OF THE CAST HAD NO FACE, AND NOTHING ANYWHERE SAID SO.**
    `Appearance.skull` is independent per axis and its z runs 0.90 to 1.09, so
    the front of a head moves nearly four centimetres across the cast — while
    the eyes, the catchlights, the brows, the sockets and the mouth were all
    placed at LITERAL depths tuned against an average head. Above about
    skull.z = 1.05 the skull is in front of them: those people have no eyes and
    no mouth, and what you read as eyes in the frame is the head sphere's own
    shading. Nothing errors, nothing is missing from the scene, the head renders
    correctly, and the pieces are simply behind it. Measured after the fix, 8 of
    72 features across 24 generated faces had been buried, worst by a
    centimetre. Every note in `npc_body.gd` about the face reading flat —
    including gotcha 44's measured argument that lighting is not the lever — was
    written about a model on which part of the cast had no features at all.
    `NPCBody._face_z(x, y, proud)` asks the ellipsoid where its own surface is;
    the smoke run measures the built pieces against the SKULL MESH's own scale,
    not against `_face_z`, which would only ever agree with itself.
81. **AN UNSHADED FEATURE ON A LIT FACE CANNOT PROMISE TO BE DARKER THAN IT.**
    The eye was `unshaded(0.10, 0.09, 0.11)` — a fixed emissive value — and read
    off a real frame, the darkest skin in `Appearance.SKIN` renders at
    (56, 33, 16) while that eye renders at (68, 45, 37): the eye was LIGHTER
    than the face, so on the dark end of the palette these people had eyes and
    a mouth made of slightly-brighter nothing. A LIT material is albedo times
    the same illumination the skin gets, so an eye at 0.03 against skin at 0.29
    is ten times darker on every face, in every room, at every hour, and the
    ratio cannot come apart the way two absolute numbers did. `EYE_INK` and
    `MOUTH_INK`; the catchlight stays unshaded, because a catchlight is a light.
    Gotcha 40 exactly: take the reading off the HARDEST case, not the average.
82. **A JOINT IS NOT WIDER THAN THE LIMB IT JOINS, AND A WRIST IS NOT WIDER
    THAN A SLEEVE.** The shoulder sphere was 0.105 — a 21cm ball on a 20cm
    sleeve, so it was the widest thing on the body and photographed as shoulder
    pads on everybody in the ward, which is the SECOND time this piece has read
    as an epaulette. And the forearm was a capsule 16.4cm across coming out of a
    sleeve that ends at 15, so the whole arm was one tube from shoulder to
    knuckles — with a comment on the line below reading "the hand is WIDER than
    the wrist" about a hand 1.4cm narrower than the arm it is on. Write the
    chain of widths down and check it is monotonic before rendering anything.
83. **A DEPTH CUE HAS TO BE AT A DEPTH, and the ward is not deep.** The
    ceiling and the floor are two thirds of the widest frame in the game and
    had nothing on either, so two downstand beams and a pair of floor lines
    went in — correct reasoning, and both were worse than the empty planes they
    were meant to fix. The ward is twenty metres wide and about six deep with
    the camera standing in its doorway, so a beam anywhere in the near two
    thirds is not a beam crossing a room, it is a cream slab across the top of
    the frame; moving it from two metres in to a third of the way in changed
    nothing, because the camera has not moved. The floor lines landed as two
    stripes directly under the beds. What DID land was the thing that was
    missing rather than the thing that was empty: five gathered curtains with no
    track over any of them (`Dressing.curtain_track`), which is the
    `ceiling_sign` fault again on the most looked-at object in the room. Ninety
    seconds a look with `SHOT_ONLY=ward_from_door ./screenshots.sh`, and both
    bad versions looked perfectly sensible in the source.
84. **TWENTY CONSTANTS AND SIX SIGNALS WERE READ BY NOTHING, AND THE FILE
    ALREADY HAD A GOTCHA ABOUT IT.** Gotcha 15 says to grep every key of a data
    table for a reader before trusting the table; nobody had ever run that over
    the whole repo. The haul: the hour a named visitor arrives, left behind when
    the hardcoded block that read it was replaced by an authored per-patient
    time; a count of doctors on a ward that deliberately has one clinician; the
    ward sister's surname, spelled out as a literal in three places instead
    (gotcha 48 again); three pools of generated names from before the cast was
    authored; a table of insurance companies whose entire point was the jokes in
    their names, which never reached a screen; twelve palette entries; and six
    signals emitted every frame they fire and listened to by nobody. An emit
    with no listener is worse than a dead constant, because it LOOKS
    load-bearing: it costs work and it reads in review as the place where the
    thing happens. The smoke run now fails on either, and both were proven red.
    **Do not name an identifier in the comment above a check that greps for
    identifiers** — the first draft of that paragraph named the sister's
    surname, which gave it a second occurrence and kept it passing.
85. **THE DARK END OF THE SKIN PALETTE HAD NO ROOM LEFT ON IT FOR A FACE.**
    Every feature on this model works by being DARKER than the skin — the eye,
    the brows, the line of the mouth, the socket under each eye. At an albedo of
    0.29 under this grade a cheek renders at **34 of 255** while the same
    person's gown renders at 179, so there is nowhere below it to put four
    things: measured on the real frames, the darkest face carried **21 levels**
    of contrast between its features and its cheek where the mid and pale faces
    carried **91**. A quarter of the contrast, on a third of the cast, and
    invisible to every harness in the repo — it was reported from outside as
    "some of the black characters' faces look messed up compared to the white
    ones", which is exactly what that measurement looks like from the other
    side. Three separate causes, all the same shape (an absolute value chosen
    for the middle of a range that the END of the range cannot carry): features
    pinned at a literal depth on a skull whose front moves (80), an unshaded eye
    lighter than dark skin (81), and a lower lip lerped toward a fixed pink,
    which is DARKER than a pale face and two thirds lighter than the darkest one
    — a salmon block that read as an open mouth with the tongue showing. The lip
    is HSV off the person's own skin now, and the bottom three entries of
    `Appearance.SKIN` are lifted about six hundredths. `./faces.sh` MEASURES it
    per subject and exits non-zero under `FLOOR`; proven red at 50.
86. **THE FOURTH NOTE ABOUT THE EYES, AND THE FIRST ONE THAT NAMED IT: "a lot
    of the eyes look like they're demons".** The first three — goggles,
    walleyed, permanently surprised — were all symptoms of the white sclera, and
    dropping the sclera fixed those three and not this one, because what makes a
    dark eye read as a hole is not the missing white. Three measurable things:
    the almond was 6.5cm on a 42cm head, a SIXTH of the face per eye; it was
    very nearly pure black, which no part of a person is; and it was shiny —
    roughness 0.35, so it carried a specular sheen and read as glass.
    5.5cm, a very dark warm brown, and matte. **An upper lid was tried first and
    was worse, which is the half worth keeping**: a flattened sphere in the
    person's own skin cutting the top quarter off the almond is the textbook
    answer and it produced a heavy pale hood over a low dark crescent — every
    character looked drugged. Three overlapping ellipsoids around one eye
    (socket, lid, almond) is a lumpy mess at any weight, and raising and
    thinning it only turned the hood into a pale blob catching its own light.
    This style does not want lid geometry; it wants a smaller, warmer, matte
    mark. Checked at the cast distance as well as at eighty centimetres, because
    the suspicion layer is built on "is this person looking at me".
87. **A COVER UNDER THE PATIENT IS A COVER NOBODY CAN SEE, and the bedside is
    the camera the whole game is played through.** It showed four blue-grey
    tubes with peach ankles and navy shoes on two of them, lying on top of the
    bedding — you could not tell the arms from the legs, and the man was in bed
    in his shoes. `PatientBed` has had a blanket since it was written; it is
    BEDDING, flat on the mattress two thirds of the way down, and the patient
    is on top of it. Found by turning that one piece BRIGHT RED and
    re-rendering the frame (`SHOT_ONLY=bedside`, ninety seconds): no red
    anywhere near the occupied bed, and a corner of it on the empty one behind.
    Then measured properly rather than guessed — the smoke run builds real beds
    with real patients, so printing the occupant's mesh AABBs through the bed's
    own INVERTED transform costs forty seconds and gives exact numbers: the
    patient occupies z -1.30 to -0.30 of a bed that runs -1.02 to +1.02. They
    sit propped in the head quarter and the rest of the mattress is empty. The
    duvet is over the LAP now, and only while somebody is in the bed.
    **A full re-pose was tried first and reverted**: derived honestly from the
    backrest's own 29-degree ramp, hips at the crease, legs flat — and it put
    the head seventy centimetres past the headboard and the mattress through
    the man's elbows, because the body pivots at its own origin and three
    coupled degrees of freedom do not fall out of one measurement. The pose was
    never the fault; nothing covering it was.
88. **A SEAM FILLER TUCKED INSIDE ANOTHER SOLID STILL HAS A SILHOUETTE AGAINST
    IT.** The shoulder sphere closes the join between the sleeve and the trunk,
    it is half inside the trunk, and it was inked — so the inverted hull drew a
    black horseshoe on the gown at every shoulder in the game, with a small
    black notch above it, and from behind it read as a hole in the back of the
    scrubs. Seen on the TITLE SCREEN, which is the first frame anybody sees.
    The arm and the trunk both carry a line already; a third one between them is
    not the edge of anything, it is a scar. Un-inking it then exposes the V at
    the top-outer corner that the sphere was too small to reach, so the width
    has to go up to the sleeve's own — and no further (gotcha 82).
89. **FOUR AUTHORED WARDS WERE ONE ROOM, PAINTED ONE COLOUR, WITH THE SAME NAME
    OVER THE BEDS.** The building is built once at `Game._ready()` and a career
    rolls the day over in place — `patient_system.reset_day()` swaps the cast and
    nothing else — so four different casts and four different lessons were all
    played in the same twenty metres and the sign said "Ward C" on every night of
    every career. It is the loudest statement the game makes about how much
    content is in it, and it is a LIE about the number: the wards genuinely are
    different and the room denied it. Twenty-five screenshots could not see it
    because every one of them is night one, and no assertion in fifteen test
    layers had any reason to look at a wall.
    `Hospital.reskin()` runs on `day_started`. Repainting is safe where
    rebuilding is not: the floor is one node per room, the DRESSING has no
    collision and no navigation footprint — the rule that lets there be a lot of
    it is exactly what makes it disposable — and the signs are two labels. Three
    things that cost a render each: `Build.surfaced_slab` returns the STATIC
    BODY and not the mesh, so `if f is MeshInstance3D` was false every time and
    the floor alone stayed green while everything else changed; the west and east
    exterior walls ran the building's whole depth as ONE slab each, so the ward's
    own ends could not be painted without painting the office (split at z = 4,
    where the corridor wall meets them and no join can be seen); and the palette
    belongs in `Cases.WARDS` rather than in `Furniture`, because adding a ward
    must not require touching a system.
90. **GOTCHA 46 AGAIN, ON THE PIECES ADDED AFTER IT WAS WRITTEN.** The dado
    rail, the skirting, the picture rail and the cornice all took the standard
    line and the standard `INK_CAP` of 0.30 — a fifty-millimetre moulding may
    grow fifteen millimetres of ink on each side, so seen down a sixty-metre
    corridor it is more ink than rail and the corridor reads as black diagonals
    ruled across a cream wall. Exactly the picture gotcha 46 describes, on four
    pieces added to fix a different problem. `box_mi` takes a `cap` now; the
    mouldings pass 0.10 and a 7mm line, and read as bands of shadow rather than
    as wires. **The A/B mattered**: the streaks looked exactly like an artifact
    of the corner shading that went in the same hour, and switching that off and
    re-rendering was what proved they had been there all along.
91. **A ROOM WITH NO DARK IN ITS CORNERS IS A BOX OF FLAT PLANES.** This
    renderer has no SSAO and no screen-space anything (gotcha 39), so every
    piece of contact darkening here is painted — the wall fades toward the
    floor, the floor fades toward the wall, objects sit on a blob — and the
    vertical join where two walls meet had nothing at all, which is the darkest
    part of a real room. `Build.corner_shade` is a LINEAR ramp rather than the
    radial one `shadow_texture` builds, because a corner darkens with distance
    from one line; alpha only and `BLEND_MODE_MIX` (18), mipmapped (19), and
    faded out toward the ceiling so it does not read as a painted stripe. Two
    strips per corner, mirrored with `scale.x = -1` rather than a second
    texture.
92. **A LEVEL IS NOT AN ARRANGEMENT, and `AudioStreamSynchronized` is the
    reason stems are safe here.** The score was one mixed buffer, so the only
    thing the last forty minutes of a shift could do to it was turn it down nine
    decibels and put a low-pass on it (gotcha 58) — which leaves the brushes
    ticking away under the heartbeat at five to eight, quieter, in a mix that is
    supposed to be emptying out. It renders as three stems now (kit, comping,
    vibraphone) played through ONE `AudioStreamSynchronized`: thirty-two
    sub-streams in lock-step from a single player with a volume each. Three
    separate `AudioStreamPlayer`s started on three consecutive frames are three
    players that never come back into phase, which is the version not to write.
    The normalisation is taken off the SUM and applied to all three equally, so
    at 0 dB the mix is sample-for-sample the one that was tuned (gotcha 75).
    **Write to the STREAM, not the player**: there is no music player under
    `--headless`, so the first version of the mix control reached through
    `_music_player`, and the check that read it back passed by doing nothing on
    the only harness that runs. And anything reading the score's raw samples has
    to add the stems up now — `test_ward.gd`'s four-passes-are-not-one-pass
    measurement broke on exactly that, which is the hazard the handoff flagged.

93. **A VERB THAT WRITES IN SOMEBODY ELSE'S NAME IS INVISIBLE TO EVERY RULE
    THAT READS `Author.YOU`.** `ask_patient` is the one verb in the game that
    manufactures a reason out of nothing, and it signs the entry
    `Author.PATIENT` — so `_reads_own_chart`, which existed precisely to punish
    writing on the chart of somebody who reads it, could not see the one line
    on that chart the patient had most reason to object to. On two dice going
    your way (they agree, and they do not remember whose idea it was) leading a
    perfectly well premium patient was eight hundred and fifty pounds with no
    trace at all. It survived four shipped wards because on every one of them
    the premium well bed happened to carry something ELSE — Sam Oduya tells
    everybody, Douglas Pyne was admitted overnight by a colleague — and the
    sixth ward, whose premium bed carries neither, went dominant on three
    adversarial seeds out of four: the most profitable night on it was also a
    clean one, which is the single property the whole economy stands on. The
    rule reads the attributed line now, gated on BOTH dice having gone your way
    so it cannot double up with `_patient_no_recall` or
    `_symptom_was_suggested`. **Grep any rule that names an `Author` for the
    verbs that write under the other ones.**
94. **A HANDOVER NOTE THAT SUPPORTS THE STAY IS DATED BEFORE THE MORNING'S
    BLOODS COME BACK.** `_objective_refutes` fires when a normal result post-
    dates an entry supporting the hold, and the night staff write at seven —
    so a `SOCIAL` claim in the handover meant every honest day on that board
    came out FLAGGED for ordering a blood test. Every other social bed in the
    game is handed over as `MOBILISING` or `SETTLED` and nobody had ever
    written down why: the night staff record what they SAW, and the reason a
    bed is held for a broken stairlift is the day doctor's to write. It cost
    eight of the sixteen boards on a new ward and looked exactly like an
    economy fault.
95. **A COUPON-COLLECTOR CHECK HAS TO BE SIZED FROM THE NUMBER OF COUPONS.**
    `draws_impl` swept a fixed two thousand seeds and demanded every ward
    ORDER appear. That is true of four wards — 24 permutations — and
    arithmetically impossible for six: 720 permutations over 2,000 uniform
    draws covers about 675 of them, so a perfectly uniform rotation failed the
    moment a fifth ward existed. Collecting n coupons takes about n·ln(n)
    draws; size the sweep from n. **And the line that reports it printed "takes
    all %d permutations" with the count it had just failed on**, so the sweep
    announced itself as complete two lines under its own failure.
96. **TWO FINDINGS DECIDED THE PATIENT'S GENDER FOR THEM, AND THE GREP COULD
    NOT SEE EITHER.** `_check_nobody_is_misgendered` only inspects quoted
    strings that also contain a `%s` — a name substituted into a sentence that
    has already decided who the person is — and `_grateful_witness` ("He was
    very complimentary about you") and `_symptom_was_suggested` ("He says you
    asked him about it") have no `%s` in them at all. Both are read out loud at
    the review, and between them the four people carrying those flags include
    two women. `Cases.about` templates both now. A grep that requires a second
    marker misses every line that simply hardcodes one person.

97. **THREE SIGNS SAY THE WARD'S NAME AND ONE OF THEM IS BUILT SOMEWHERE
    ELSE.** `Furniture.rename_ward` rebuilds the plate above the beds and the
    arrow in the corridor every morning; the flag projecting over the ward
    DOOR — the sign a player actually navigates by — is built out of
    `Hospital.LAYOUT` at construction time and said "Ward C" on every night of
    every career, three metres from a plate saying something else. So did the
    End of Shift card ("Day %d · Ward C", hardcoded, on the most-read screen in
    the game), the objective waypoint over the door, the corridor's own
    `Room.display` that a witness quotes, and two tannoy lines. Found by
    looking at a frame of the fifth ward, which is not a way of finding things
    — the smoke run now walks every `Label3D` under the hospital after each
    reskin and fails if any of them names a different ward. Proven red.
98. **GOTCHA 17 HID THE FAULT FROM THE PROBE THAT WENT LOOKING FOR IT.** There
    are TWO folding screens in the ward and only the far one was ever passed a
    bay colour, so the near one — the largest object in `02_ward_from_door`,
    which is the frame a store page leads with — kept
    `Dressing.screen_partition`'s own default teal on all six wards. Both nodes
    are named "ScreenPartition", Godot discards the second name and substitutes
    the class, so a probe searching by name found exactly ONE screen in a room
    with two, read the wrong one's material, and reported it correct. The same
    fault the ceiling-height check had, in a room I had just repainted.
    **And `get_shader_parameter()` cannot confirm a tint** (gotcha 36), so what
    settled it was the material's INSTANCE ID: `Build.cloth_mat` caches by
    colour, so two colours are two objects and a colour that did not change is
    the same object. Failing that, measure the pixel.

99. **THE MAN IN BED WAS STILL IN HIS SHOES, AND THE COVER WAS NOT IN THE
    WRONG PLACE — THE LEGS WERE TALLER THAN IT.** Gotcha 87 put the duvet over
    the lap and stopped there. Measured properly this time — the occupant's
    mesh boxes through the bed's own inverted transform — the body runs
    z -1.32..0.20 and the SHINS AND SHOES reach y 0.78..1.15, while a 20cm
    cover sitting on a mattress at 0.62 tops out at 1.01. Fourteen centimetres
    of foot came up through the bedding, in the frame the whole game is played
    from. Feet tent a blanket, so the duvet is now as deep as they are.
    **And the probe that measures this has to run PHYSICS frames with the tree
    UNPAUSED**: the pose is applied in `_physics_process`, the morning briefing
    pauses the world, and a probe that waits on `process_frame` measures a
    patient standing to attention beside the bed and reports nonsense with
    great precision.
100. **A CONSTANT MIXED "TOWARD THE FLOOR'S OWN COLOUR" WAS MIXED TOWARD ONE
    WARD'S.** `floor_zone`'s bay strip — the largest painted shape on the floor
    — lerped 55% toward a literal sage green, chosen when there was one ward,
    so on the slate-blue ward it read as a green rug somebody had laid down on
    lino. The comment beside it had said "the floor's own colour" the whole
    time. Gotcha 48's fault with the number in the right place and the wrong
    ward's value in it; it now reads `Cases.ward_look()["floor"]`.

101. **FIFTEEN HEDGES WERE STANDING INSIDE THE BUILDING.** The view through
    the windows is three rings of blocks drawn about the centre of the floor
    plan, and the plan is a 20 x 21 rectangle: a boundary ring of radius 12.5
    to 14 clears the long sides and passes straight through all four CORNERS,
    which are 14.5 out. Two of them stood in the office, half sunk in the
    floor, and photographed as a pair of flat pale-green slabs with none of the
    tooth every indoor surface has — so they read as an unfinished piece of
    FURNITURE rather than as shrubbery, which is why three sessions of looking
    at that frame never recognised them. `_outside_radius(bearing)` returns the
    distance to the building's own wall along a bearing, so the boundary is a
    rounded rectangle at a fixed standoff. The smoke run intersects every
    `outside` mesh's footprint with the plan now; it was proven red at fifteen.
102. **A CHECK THAT MATCHES A NAME HAS TO MATCH THE NAME, not a word in it.**
    The first version of the ward-sign check compared anything beginning or
    ending with "Ward", case-sensitively, against the whole label. It missed
    the station's own whiteboard — "WARD C — TODAY", in marker, on every night
    of every career — because the board SHOUTS, and it missed the corridor's
    hanging sign because that one has a tail. Widened to be case-insensitive
    and it then swept up "WARD RECORDS", which is a door. The precise question
    is "does any sign name a DIFFERENT ward", so the set to test against is
    `Cases.WARDS` itself. **And prove the red on the right line**: breaking the
    board's build-time literal proved nothing, because `rename_for_ward` runs
    on every reskin and put it back.

103. **A PAINTED MARKING IS NOT AN OBJECT STANDING ON THE FLOOR, and it was
    casting a shadow onto itself.** `Dressing._add` gives everything below 5cm
    a blob shadow sized to its own footprint — correct for a bin, a plant or a
    bedside cabinet, and wrong for the bay strip under the beds, which got an
    eighteen-metre RADIAL blob centred on an eighteen-metre painted rectangle.
    That is the shadow trench running the length of every ward frame in this
    game, and it was blamed in turn on the zone's tint, on the ceiling fittings
    falling off toward the far wall, and on five bed shadows merging. Settled by
    turning the zone BRIGHT RED and re-rendering one frame: pure red came back
    at **190 along the strip's front edge and 73 through the middle of it**,
    which is not a lighting gradient, it is a blob. Measured after the fix the
    strip is uniform. Four centimetres is the line — a doormat, a wayfinding
    line and a bay marking are paint; a bin, a plant and a cabinet are objects.
    The tint had also been `darkened()` twice on top of that, which is gotcha
    100 again: two people compensating for the same fault from opposite ends.

104. **"SHARED" MEANT SHARED BY INDEX, AND A SPHERE DOES NOT SHARE ITS SEAM.**
    Gotcha 37 says the outline hull "only stays closed if they are shared", and
    `_reface` accumulated area-weighted normals by vertex INDEX — but every mesh
    in this building is a Godot `SphereMesh` Minkowski-summed with a box, and a
    SphereMesh DUPLICATES its seam meridian: two vertices at the same point with
    different indices, because they need different UVs. So each copy got only
    the faces on its own side of the seam. Measured after the fix: **140 of 540
    shared vertices carried different normals and the worst pair were exactly
    OPPOSITE**. The outline pass pushes every vertex along its own normal, so the
    copies went different ways and opened a crack down the meridian — drawn
    back-faces-only, that is a black hairline running from the middle of a face
    toward its edge, on every rounded box in the game. There was one across the
    bedding of every bed, in the frame the whole game is played from.
    **It survived six renders of red tests** on the bed rails, the bed posts and
    the IV stand's crossbar, and two rounds of tightening `INK_CAP`, because it
    is not a magnitude problem: it is there at two and a half millimetres of ink.
    What found it was zeroing each cloth piece's own `line` in turn. Accumulate
    by POSITION, quantised; the smoke run asserts it and was proven red at 140.

105. **THE BUILDING'S MAIN WAYFINDING HUNG EDGE-ON TO EVERYBODY WHO WALKED
    UNDER IT.** `Dressing.ceiling_sign` faces its own +Z and takes a `rot_y`
    that both call sites left at the default — and the corridor runs in X. So
    the two hanging signs, which carry the only "this way to the ward, that way
    to the station" in the game, presented their 6cm EDGE to anybody walking the
    corridor: a blue vertical stripe in the middle of the ceiling, in the first
    frame of the game, with the text on the two faces nobody can see. A quarter
    turn is the whole fix, and the board already carries the text on both faces
    so it reads walking either way. **And the plate was a fixed 1.5m** while
    `_wall_sign` has always sized its plate to its text, so the words then hung
    off both ends into the air — same estimate (0.62 of the size per character),
    same fix.

106. **THE SIGN CHECK WALKS `Label3D`s AND TWO OF THEM WERE CARDS.** Gotcha 97
    caught five signs naming the wrong ward and the check written for it walks
    the world. It cannot see a UI screen, and the two biggest remaining ones
    were: the MORNING BRIEFING, whose header is the largest text in the game and
    the first card of every shift, and the loading card between the menu and the
    ward. Both said WARD C on all six wards. They also survived a
    `grep "Ward C"` over the whole of `scripts/` **because they SHOUT** — gotcha
    102's lesson a second time in the same week. The static half of the check
    now greps every quoted string in `scripts/` against `Cases.WARDS` itself,
    case-insensitively and on WHOLE WORDS: the first version matched "Ward C"
    inside "the ward can see", which is a line on the records screen.
    It also caught `Hospital.LAYOUT`, which spelled both room names out as
    literals that `reskin()` corrected a moment later — so between `build()` and
    the first reskin, and in every harness that builds a hospital and never
    reskins, the corridor a witness quotes was the wrong ward's. The loading
    card names no ward at all now, because its own comment already says nothing
    on it may read `GameState`: on the Continue path the save has not been read
    yet, so a ward name there would be last career's.

107. **A STAGE THAT NAMES A PATIENT NAMES ONE WHO IS NOT ON THE WARD.**
    `shot_impl`'s ward-three stage set `day = 3` and asked for "fry" by id.
    The ward order is a per-career permutation, so night three is not the third
    ward and Rosalind Fry was not on it — and `request_ui` for a patient who is
    not on the ward opens NOTHING, silently. So one of the twenty-eight frames,
    in a set whose whole job is the screens, was a photograph of the back of a
    nurse's head with no card on it at all. Gotcha 78 in a harness rather than
    in a check: **select by WARD INDEX and let the roster name itself.**
108. **NOBODY STANDS ON THE LENS.** The `ui:` vantage is a metre and a half
    inside the ward door, which is exactly where every nurse in the building
    walks, and those stages settle for five frames before the save — so
    somebody clear when the camera was placed has walked into it by the time
    the picture is taken. Two card frames came back with a head filling a third
    of the picture. The offender is pushed OUT along the line from the camera
    rather than the camera being pushed back, because backing up from that
    vantage walks into the plaster, and it is re-checked EVERY settle frame
    rather than once at stage time. `faces.sh` learned this twice already
    (gotcha 62): when a frame looks wrong, check where the camera is standing
    before you change anything in it. **And the three cards you read at the desk
    are read at the desk**: the end of a shift and both endings are signed off
    in your office with the door shut, and all three were staged in the middle
    of the ward — photographed through a crowd, with a nurse's head filling a
    third of the frame and three speech bubbles clipped across the corner. The
    room behind a card should be the room the card belongs to. A guessed office
    vantage a metre nearer than `07_office`'s put the camera inside the desk;
    reuse the one that is known to frame the thing.

109. **A CONNECTION TO AN AUTOLOAD SIGNAL OUTLIVES THE SCENE THAT MADE IT.**
    `UIRoot._ready` does `EventBus.request_ui.connect(open)`, and EventBus is an
    autoload — so leaving the main menu removed its UIRoot and QUEUED it for
    deletion, but a queued node is not freed until the end of the frame, and
    `Game._start()` emits `request_ui("morning")` inside that same frame. The
    orphan heard it, built a card, and asked a tree it is no longer in to pause:
    **two `Parameter "data.tree" is null` errors on the one transition every
    player makes, on every launch, for as long as this project has had a main
    menu.** `boot_check.sh` stops AT the menu and every other harness starts
    after it, so nothing had ever watched the step between them — gotcha 76's
    gap, with a real error sitting in it. Guarded in `open()` with
    `is_inside_tree()` rather than by disconnecting on the way out, because the
    question "can this show anything" has exactly one answer.
    **Two things about finding it are worth more than the fix.** The error fires
    only when the free and the next scene's construction land in the SAME frame,
    so a probe that waits three frames between them reports the game as clean;
    and `screenshots.sh` had no error grep at all until this session, which is
    why a harness that printed it on every run for months never went red.
    `data.tree` is in that grep now, and it is proven red by the run that found
    this.

110. **THE CAREER PROBE'S HONEST DOCTOR NEVER WROTE ANYTHING DOWN, AND ITS
    GREEDY ONE WAS SOMETIMES HONEST.** Three faults in one file, all found by
    sweeping `CAREER_SEED` — the sixth time that has turned something up.
    `_hold` recorded a `SOCIAL` note for a social bed and NOTHING AT ALL for a
    medical one, so every "honest" policy kept a genuinely ill patient on
    whatever somebody else happened to have written. Then the corroboration was
    `ask_colleague` on every held bed, on every ward — which on the fourth ward
    is exactly the wrong verb, because Gwen Ashworth's chart already carries the
    night registrar's opinion and `colleague_wrong` means asking again gets it
    back in writing: `reversed_a_colleague` TWICE plus an `uncorroborated_stay`,
    on the bed you were right about, every night that ward came round. And
    `greedy` filled the ward to THREE beds and stopped, which is the same
    arithmetic guard `skilled`'s own comment says turns a liar into a survivor —
    so on any ward whose honest hold already fills three it took no extra bed at
    all and played the careful doctor's day, and the property "greed is struck
    off before it finishes" was being asked of a policy that was, a third of the
    time, not lying about anything.
    `frontier_impl` had written the correct day out by hand and left the lesson
    above it ("look at everybody, write up what you found, order the bloods,
    THEN send the nurse to check what you wrote") and this probe never learned
    it. **Two probes measuring two different players is worse than one probe**:
    the frontier said every ward has a clean day and the career said the honest
    doctor collects findings, and both were reporting truthfully about the
    doctor each of them happened to be driving.
111. **A WATCHED DAY RUNS EACH ROUND TWICE AND `Cases.ROUNDS` DOES NOT SAY SO.**
    Writing in the gap between rounds is the central timing skill of the game,
    and `WardDay.rounds_today()` is the only thing that knows where the gaps
    are: once the record is flagged, Adeyemi writes up again forty-five minutes
    after each round. A helper that stepped over the round in `Cases.ROUNDS`
    therefore landed precisely on the second write, so the restrained liar — who
    had STOPPED lying, because she was being watched — took
    `conflicting_observations` at 0.59 for an honest examination note, twice in
    a row, and was struck off for two clean nights. The denser schedule exists
    to make the skill harder to exercise; anything reading the sparse table is
    not exercising it at all. Same shape as gotcha 30: a table that is a
    function of state, read against different state.
112. **A LADDER THAT ARRIVES AFTER THE MONEY IS NOT A LADDER.**
    `ENTRENCHED_NIGHTS` was 5, so the doctor who takes exactly one bed on his own
    word EVERY night banked four free nights, one flag on the fifth and one
    referral on the sixth — four strikes of the five — and the debt clears in
    six. He walked out with the deeds, faster than the restrained liar the whole
    design exists to reward, which is the inversion `review_system.gd`'s own
    comment says the entrenched rate was added to close. It was right and it
    started one night too late. Four now: `habit_warning()` reads the same pair,
    so an entrenched career is TOLD "the next bed you are the only witness for
    goes straight to the panel" on the morning of night five and referred on the
    night of it. Nothing below three-quarters moves — a bed every other night is
    a rate of a half and never reaches this rung. **Check any escalation against
    the length of the run it has to bite inside**, not against the shape of the
    curve.

113. **THE EYES WERE SEATED IN A SOCKET THAT WAS SEATING SOMETHING DELETED THREE
    PASSES AGO.** `NPCBody` built a darkened skin disc behind each eye and its
    own comment said exactly what it was for: "the whites are unshaded ovals
    sitting proud of an ellipsoid, which is why they read as stickers — a real
    eye sits IN something". The whites went with gotcha 60; the disc stayed.
    Ten and a half centimetres across on a five and a half centimetre eye, a
    tenth darker than the cheek, and photographed at eighty centimetres it is a
    pair of teardrop patches that read as spectacle rims on a pale face and as
    bruising on a dark one — while darkening the skin in precisely the region
    the eye has to be legible against, which is gotcha 85's whole subject.
    `faces.sh` measured it: **every one of the six subjects gained room for its
    features when it came out** (+7.3, +1.7, +4.3, +2.3, +0.3, +7.7 levels), the
    darkest gaining least because it had least to give. At the CAST distance the
    two renders are indistinguishable, so it cost nothing where it might have
    been earning and a great deal where a player leans in. Fifth instance of
    gotcha 56: a piece doing exactly what it was told, in a world that moved out
    from under it. **The tell was in its own comment** — when a piece explains
    itself by naming another piece, check that the other piece is still there.

114. **THE TWO MEASUREMENTS THAT CAN SEE A LAYOUT FAULT PRINTED A NUMBER AND
    NOBODY READ IT.** `shot_impl` measures how much of a card is below its own
    fold and what the HUD has under it — both real, both only possible in a real
    window (gotcha 28), and both were `print()` in the middle of a page of
    `shot:` lines. Gotcha 21 in the one harness that photographs the game.
    They fail the run now, and asking them at the interface sizes the SLIDER
    OFFERS rather than only at the one the harness opens found a fault
    immediately: at 120% and 140% the money plate in the top-right corner and
    the objective plate in the top-centre are under the card on every screen in
    the game — "IF YOU SIGNED OFF NOW" covered, a green figure cut in half by a
    card's edge. They hide with the modal now, which is the same decision the
    file had already made twice for the controls reminder and the toasts.
    **The window SIZE turns out not to be the hazard, and that is worth as much
    as the fix.** `stretch/aspect` is `expand`, so the canvas keeps the base 900
    units of height as a MINIMUM and gains more on anything narrower than 16:9 —
    a Steam Deck's 1280x800 lays out against 1600x1000 and has a hundred units
    MORE room than the monitor everything here was tuned on. Swept on this
    harness: every frame reported an identical fold at 1280x800 and 1280x720. No
    monitor shape can push a card off the bottom. `content_scale_factor` can, it
    is the control a player reaches for when the text is too small, and it is
    the only one of the two worth checking.
115. **A CARD OPENED AT ITS FIRST BUTTON RATHER THAN AT ITS TOP.** A
    `ScrollContainer` scrolls a newly focused child into view — right when a pad
    walks a selection down a list, wrong the instant a screen opens. The patient
    sheet's first focusable is "Read the chart", a third of the way down, so
    every bed a player has ever opened scrolled past the patient's own line
    ("I tried the soup at lunch and I couldn't finish it") and cut the money
    block in half. The most-opened screen in the game, in a frame this project
    has photographed twenty times, reading as a clipped panel rather than as a
    scrolled one. **The first fix was a no-op that looked like it worked**:
    `_focus_first` is already the deferred call, because `grab_focus()` on a
    control that is not in the tree yet is silently nothing — but a deferred call
    and a container's own child sort are two different queues, so the scroller
    still reports its PLACEHOLDER height there. Measured: 120 pixels for a region
    that lays out at 510, which fails any "is it still visible" test on every
    card in the game. It takes a real `await get_tree().process_frame`.

116. **THE ARROW THAT SAYS "IT IS OVER THERE" CAME ON THE MOMENT YOU ARRIVED,
    POINTING AT YOUR OWN FEET.** `ObjectiveMarker` fades its chevron out inside
    `FADE_NEAR` because its own docstring says "it is a hint, not a quest arrow,
    and it disappears the moment you are close enough to read the thing it is
    pointing at" — and it measured that distance from the PLAYER BODY, while the
    HUD's edge-of-screen arrow projected the target through the CAMERA. Those
    are the same thing in the game and not in the shot harness, which moves a
    camera to a vantage and leaves the body where it was: the camera stood 1.8m
    from the office door with the body across the building, so the chevron was
    "not arrived yet" and the target was below the lens, and a pale teal triangle
    sat at the bottom edge of `02_ward_from_door` — the frame a store page leads
    with — with nothing under it. The fade is about what you can SEE, so it is
    measured from the eye now, and the arrow also goes out when the marker does.
    **A harness that separates two things the game always keeps together is not
    lying to you, it is asking whether the code knows they are the same.**
117. **A CARD HAS A CLOCK ON IT TOO.** `_set_clock` exists because the first
    evening frame this project rendered was a ward at dusk with "8:03 AM" over
    it, and it pokes the HUD label directly for exactly that reason. The UI
    stages run after the world stages and inherit whatever clock those leave —
    so the morning briefing, the first card of every shift and the one a store
    page leads on, was photographed reading "7:25 PM · five beds" with "7:26 PM"
    beside it. The same self-contradicting frame the function was written to
    stop, on a surface nobody thought of as having a clock.

118. **NOBODY LOOKED AT THE DOCTOR STANDING OVER THEM.** Gaze in this game
    means "I have noticed something" and is rationed on purpose: `refresh_tell`
    turns a head toward you only from `suspicious` upward, so a stare across a
    ward is a warning rather than decoration. That is right at fourteen metres
    and uncanny at one — a doctor walks to a bed, stands over somebody, opens
    their notes and decides whether they go home, and the patient looks straight
    ahead through all of it. `03_bedside` is the camera the whole game is played
    through and it is exactly what that frame showed: a face turned thirty-five
    degrees away with its features crowded onto the side of the skull, which
    looked like a modelling fault and was a behaviour one. Hung on the INTERACT
    PROMPT rather than on proximity, so it is precisely the person you could
    speak to right now — aimed at, in range, one at a time — and it can never
    become a room turning to face you, which is what the rationing protects.
    **`look_toward` LATCHES**, and that is the half that would have rotted in
    silence: `_has_look` is only ever cleared by `clear_look()`, so a head aimed
    once stays aimed at a position the player left minutes ago. The interactor
    releases the previous target the moment the aim moves off it, the smoke run
    asserts both halves, and the release was proven red.
119. **A HARNESS THAT SEPARATES TWO THINGS THE GAME ALWAYS KEEPS TOGETHER IS
    ASKING WHETHER THE CODE KNOWS THEY ARE THE SAME.** `shot_impl` moves a
    CAMERA to a vantage and leaves the player BODY wherever it spawned, so every
    world frame in the set was photographed from a place nobody was standing.
    Two faults came out of that in one session and both looked like modelling
    faults: the objective marker measured "have you arrived" from the body while
    the HUD arrow projected the target through the camera (gotcha 116), and
    every NPC's gaze and every interact prompt read the body, so nobody in any
    frame was reacting to the picture. `_stand_where_the_camera_is` moves the
    body's XZ to the camera's, AFTER the camera is placed — the camera is a
    child of the player, so moving the body afterwards carries the vantage with
    it, and taking the body's own Y would drop a 2.6m store-page camera to the
    floor. The bedside frame gained its interact prompt the moment it landed,
    which is the game's own affordance appearing in a photograph of the game.

120. **THE FIX WAS ALREADY WRITTEN DOWN EIGHTEEN LINES FURTHER DOWN THE SAME
    FUNCTION.** `_station`'s corridor counter carries a note saying a 2.1m slab
    with a top on it was "the largest single object in the room and a
    featureless rectangle from every angle, which is most of why the station
    read as placeholder", and lists the three things that fix it: a recessed
    kick, a shadow gap under the worktop, a lean rail. The BACK worktop in the
    same function is SIX metres, fills `06_station` end to end, and was built as
    exactly the slab that note condemns. Its top was bare too — the same fault
    the office desk had, with `Dressing.desk_clutter` sitting unplaced again —
    and the one permanently staffed post in the building had nowhere to sit.
    **When a file already contains the argument, check every other object it
    applies to before writing a new one.**

121. **THE ONE SCREEN THAT IS A PLACE WAS PHOTOGRAPHED FROM A RANDOM FLOOR
    TILE.** `Hospital.point_in` returns "a random point in a room" and says so in
    its own docstring — it exists to send a nurse somewhere, and `_stage_ui`
    used it to stand the player up for the handover board. So the screen whose
    whole design argument is that it is somewhere rather than something you can
    open from anywhere came back with two thirds of the frame filled by a flat
    beige wall seen from a few centimetres. Gotcha 108 from the other end: it is
    not only that nobody should stand on the lens, it is that the lens has to be
    somewhere a person would be, chosen rather than drawn. Every UI stage takes
    a named vantage now — the desk, the board, or down the ward.
    **And moving it immediately went red on the new under-the-card check**: from
    the station the ward door is off to the side, so the objective arrow came on
    and landed under the card. It hides with the modal now, like the two plates
    along the top and the controls reminder — a card is not a thing you read
    past, and the one thing an edge-of-screen pointer is for is the one thing you
    cannot do with a screen open. Second fault that measurement caught in an
    afternoon, having caught none in the year it spent printing.

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
- **THE BELIEF LAYER REACHES THE VERDICT, THROUGH ONE QUESTION.** `Mind`,
  `Evidence`, the gossip pass and the four escalating things a witness says are
  about nine hundred and fifty lines modelling being SEEN, and they reached the
  eight o'clock audit through exactly one channel: `seen_by`, stamped on an
  entry as it was typed. Twelve hours of people watching you work went in the
  bin at handover. `SuspicionSystem.what_the_ward_saw` is what the room would
  say if anybody asked it, and `Contradictions.she_was_standing_there` is the
  one question it is allowed to become — a bed you held that nobody else saw a
  reason for, in front of a room that has been watching. It is in the
  CONTRADICTED list, so it costs exactly one notch: NOTED becomes FLAGGED.
  **It is not the nurse, and that was the first version.** Filtering on
  `role == "nurse"` returned nothing at all: measured in the real tree after a
  shift of bedside notes, the minds holding witnessed evidence were five
  PATIENTS (0.331 down to 0.186) and no staff, because the nurse is at her
  station and the people who can see the bay are the ones lying in it. Four
  gates keep it off a careful doctor: a pattern rather than one note
  (`WATCHED_TIER`, and `Mind.add_evidence` MERGES duplicates so it takes
  several beds), anybody else having recorded a reason, `no_care_at_home`, and
  having EXAMINED them — that last one is the design rule and not a balance
  decision, because a measure that fires on "wrote where somebody could see"
  and not on "went and looked first" pays you to decide blind.
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
- **Six verbs, and every one of them costs time.** Read a chart (15 min), write
  it yourself (10), lead the patient (15), send a nurse (35), order a test (10,
  back in 75), examine them (25, and it writes NOTHING), ask the registrar (50,
  and only during his hours). The costs are the game: the day is not long enough
  to do all six on all five beds, so a day is a budget rather than a checklist.
  **That sentence was false for as long as there were six verbs** — at
  12/8/10/15/5/15/25 the whole checklist was 450 minutes of a 720-minute shift,
  so the correct play was to do everything to everybody and then decide, with
  two hundred and seventy minutes spare, and nothing had ever measured it
  because every probe drives the ward with `advance_to(15 * 60)`. `WardDay`
  counts `minutes_worked` now and `frontier_impl` fails on a checklist that
  fits, on an honest day that does not, and on a top-of-the-money night that is
  also a clean one. The numbers today: 160 a bed, 800 for the ward, and the
  honest day works 510 of 720 and finishes about half past five. A uniform
  multiplier cannot produce that shape — the honest day was already 74% of the
  exhaustive one — so what is dear is CORROBORATION (the nurse and the
  registrar are two thirds of the checklist), what is cheap is FINDING OUT
  (reading and the lab), and examining sits in between. Add a verb by adding a
  cost constant and a `WardDay` method that writes a `ChartEntry` with an
  honest `author` and `written_minute`.
- **Information must never have negative expected value.** This is the rule the
  career rework exists to enforce, and it was broken for three iterations:
  examining a patient wrote nothing to the chart, so the only thing looking at
  somebody did was manufacture the knowledge that convicted you of ignoring it.
  Anything that makes the player *less* willing to find out what is true has
  inverted the game. `_never_laid_eyes_on_them` is the counterweight — three
  blind decisions is itself a finding.
- **The ward goes quiet in the evening, and it is the only thing left of the
  three shift types.** `SLEEP_CHANCE` was a table on `GameState.shift_kind`,
  read by `_on_shift_started`, which had no caller, about a member that does not
  exist — the shift types went with the redesign and left the table, the reader
  and a docstring about a distraction economy behind. There is one shift and it
  runs 08:00 to 20:00, so the honest version is the last few hours of it:
  patients doze from half past four, once per twenty minutes of ward time, on a
  ramp. The live half is `perception.suppressed` — a sleeping patient does not
  witness you — which the audit reads through `seen_by`, so a note typed at a
  bedside at half past six is less likely to have been typed in front of anybody
  than the same note at ten. They wake when you speak to them and when you make
  a noise.
- **A PROBE THAT BUILDS NO WORLD SEARCHES A GAME THAT DOES NOT SHIP.**
  `_who_can_see_me` needs a suspicion system, a player body and a hospital, and
  not one of `frontier_impl`, `playtest_impl`, `draws_impl`, `career_impl` or
  `econ_impl` builds any of them — they put a bare `WardDay` in the tree root
  and play a day against it. So `seen_by` was empty on every entry any of them
  ever wrote, and `_written_in_front_of_them` (up to 0.62, and in the
  CONTRADICTED list, so it kills a bed) could not fire in one of the 2,601
  strategies searched per ward. The probe whose entire purpose is that a
  dominant strategy has to hide from a SEARCH rather than from an author was
  searching with a detector switched off, and turning it on re-ranked the top of
  the money curve on the first ward. `WardDay.witness_stub` is one bit — was
  somebody standing there while you typed — and the TERMINAL decides it, which
  is the distinction the design has always been about.
- **An exemption has to reach the VERDICT, not just the finding.**
  `_uncorroborated_stay` has said since it was written that "a social admission
  needs no corroborating observation — there is nothing clinical to
  corroborate", and that exemption stopped reaching anything the day the verdict
  stopped being a severity sum: `audit_beds` replaced the sum and did not
  inherit it, so a bed held on an honest social note came out SOLO, two of them
  is FLAGGED, and the third ward — whose entire authored subject is the hold
  that has nothing to do with medicine — could not be played correctly without a
  note on your file. `pattern_findings` had the same hole and scored the correct
  play as a SHAPE at 0.70, twelve times over in the draw sweep. Whenever a rule
  is exempted, grep for every OTHER thing that reads the same fact.
- **`no_care_at_home` HAS TWO HALVES and only ever had one.** It appeared in
  `Contradictions` four times, every one an exemption protecting a HOLD, and
  nowhere at all on the other side of the ledger — so sending the
  eighty-one-year-old found on the floor twice this year back to an empty flat
  produced no finding, no audited bed and no line on the record, on the ward
  whose entire authored subject that is. `_sent_home_with_nowhere_to_go` is
  ungated like `_they_came_back`, graded like `_sent_home_unwell` (worse if you
  ASKED them and did it anyway), and `emptied_wrongly` no longer requires
  `not well`. It also means every honest policy in every probe had to learn
  that keeping somebody is not only a medical question.
- **A CLEAN NIGHT USED TO PAY A STRIKE BACK, FOREVER.** So alternating one bad
  night with one good one was net zero at five strikes' distance from the end —
  a treadmill, not a brake, and the every-night liar came out identical to the
  doctor who stops when she starts reading his charts. The career probe found it
  directly: lying every single night paid off the whole debt on one seed in
  three. `DoctorRecord.FORGIVENESS` caps the refunds at three a career. A CAP
  and not a streak, because a streak makes the record order-dependent and the
  design rule is that the career score is a pure read over counters that never
  reset.
- **A finding is a severity, not a gate.** `_sent_home_unwell` is a ladder
  (0.85 if a peer said otherwise, 0.72 if you examined them, 0.58 if it was
  merely documented, 0.55 if you never looked). A boolean gate is a cliff the
  player learns to stand exactly one inch from.
- **The physics layer has exactly one meaning and it is the one the design
  already needed.** `Interactor` is four hundred lines of grab, throw,
  hold-rotate and long-press, and `Prop`'s own docstring calls props "the
  distraction economy: noise pulls NPC attention, and NPC attention is the
  resource you are actually managing all shift" — about attention that nothing
  in the shipped design read for any outcome. A stranger picked up an IV stand
  in the first minute, threw it, watched nothing happen, and concluded the world
  was inert. Now: after half past four the ward dozes, a dozing patient does not
  witness you, `seen_by` is read by the audit, and a clatter wakes them. The
  shift you chose because nobody was watching becomes one where everybody is,
  because you made a noise. The chain is prop → `WorldEvent` →
  `SuspicionSystem` → `on_heard_noise` → `wake_up`, and the smoke run walks all
  of it.
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
  system.** Sixty-four people across six wards, each a dictionary of authored
  strings; `tests/probe/data_run.gd` walks every one and fails on any field a
  system would otherwise silently default. If a new kind of patient needs a new
  `if` in `WardDay`, the data model is wrong, not the patient.
- **Two candidates for a slot must be found the SAME WAY, not merely be the same
  tier.** `only_visible_in_person`, `test_reveals` and `colleague_wrong` are the
  three flags that decide how a truth is reached, and which of them a ward's ill
  patient carries IS the ward's thesis. Ward two had `only_visible_in_person` on
  Lomax and not on Ibarra; ward four had all three on Ashworth and none on
  Castellanos — so on half of every career's nights on those two wards, decided
  by a coin flip nobody can see, the ward played as an ordinary read-the-chart
  ward with its premise switched off, and `test_reveals` was authored on ONE
  person in the whole game who appears on one side of one coin. `data_run`
  asserts the parity now. Nothing else could see it: both ends were the same
  tier, both could go both ways, and every authored measurement plays seed 0.
- **A ward whose ill patient no verb can corroborate has no clean day, and that
  is a ward that punishes honesty.** One bed held on your word alone is `noted`
  on the night and `flagged for audit` once `uncorroborated_rate` crosses a
  half — so a doctor who works the second ward correctly every time it comes
  round accumulates a penalty for it. `nurse_check` distinguishes a DIRECTED
  check from a routine one: a routine review is a score and cannot find a man
  whose tremor is at four in the afternoon, but if you have examined him
  yourself AND written down what you found, Adeyemi reads it and goes and checks
  THAT. The ward teaches a sequence rather than a verb — look, write, then send
  her — and it cannot be used to manufacture anything, because she still reports
  what is true.
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
- **The ORDER of the wards is drawn too, and seed 0 is the old order.** Night
  one was always the Marchetti ward and night four always the one Dr Costa
  covered, and because each ward is a LESSON, that single `%`
  was the largest piece of transferable knowledge in the game: a returning
  player walked onto every ward already knowing which verb it was about.
  `Cases.pool_index(day)` is a per-career permutation with a fresh one every
  cycle, so every ward is still visited exactly once per cycle — the
  pressure curve and the debt arithmetic are unchanged — but which one is
  something you find out by reading the handover. There are SIX wards now, so a
  nine-night career visits all six before it repeats anything, and the cycle
  length is `DAYS.size()` everywhere rather than a four written down. Anything
  that pairs a night
  with a ward-indexed table (`PRIOR_BY_DAY`, `ILL_PAIR_BY_DAY`, `DAYS`) must go
  through it, and anything that GROUPS results by night is averaging several
  different wards together — `draws_impl` counts deals per WARD, and
  `enumerate_pool(index)` is the ward-space form of `enumerate_draws(day)`.
- **Anything seeded gets its distribution counted, not eyeballed.** The draw has
  been broken twice in a way that dealt the same two games forever while looking
  perfect in the game, the tests and the data check: once because `hash ^ seed`
  only mixes at the bottom bit (which is the only bit that matters when a slot
  has two candidates), once because Godot's String `hash()` does not spread into
  that bit either. Also: the textbook splitmix64 constants do NOT fit in a
  signed 64-bit int and GDScript mangles the literal rather than wrapping it.
  `tests/probe/draws_run.gd` counts distinct wards over two thousand seeds.

## Testing philosophy

`tests/` has fifteen layers, and each has caught things the others could not:

| Layer | Catches |
|---|---|
| unit + integration (`tests/run_tests.gd`) | maths, serialisation, the audit rules, floor connectivity — 363 assertions across `test_compile.gd`, `test_suspicion.gd` and `test_ward.gd` |
| `smoke_run.gd` | "everything compiles and nothing works" — 263 checks through the real tree, and then the whole file again on two wards it has never seen. Every check in it used to name its patients ("oduya", "blake"), so it could only ever run against one of the thirty-two boards the first ward alone can deal; pointing it anywhere else produced eight failures that were all the harness. `SMOKE_SEED` overrides. |
| `playtest_run.gd` | design inversions, over 39 authored strategies — twenty-three on the first ward, eight on the second, four each on the third and fourth. The last eight exist because the two wards added most recently were checked by the data probe (are they well formed?) and the frontier probe (is there a clean day?) and by nothing that asks what a PERSON would do on them: the third ward's honest hold is in a life and the fourth's is in somebody else's decision, and neither proposition had a single authored day behind it. Seven criteria, and it exits non-zero when one regresses. The seventh is the frontier: the spread must not be flat, and the biggest day in the table must not be a clean one. It was pointed at a field Vinnie drives to zero on every night but the last, and ranked 31 strategies by a constant for four iterations without anybody noticing, because a sorted column of zeroes is a sorted column. |
| `faces.sh` | the one thing that can see a face: it MEASURES how much room each subject has left below its own skin for the four features that are all darker than it, and exits non-zero when a face runs out. It is also the loop an art pass needs. Six people drawn through `Appearance` — so what is photographed is what ships — each from eighty centimetres, then one whole body, then the cast together. It found in one frame what twenty-one frames of `screenshots.sh` had not in three sessions: a white sclera that made the whole cast read as default-stylised, hair that came down to the eyebrows on every character, a torso whose flat front made everybody look like they were wearing a sandwich board, and nine centimetres of daylight between everyone's thighs. It also produced THREE faults of its own that each looked exactly like a modelling fault — subjects standing outside the building and falling, a camera four and a half metres back in a four-metre room, and a body shot taken after the cast had closed ranks — so it asserts nobody is falling, and the rule is: when a subject looks wrong, check where the camera and the feet are before you change the model. |
| `look.sh` | nothing on its own — it is `screenshots.sh` with twenty-one frames taken out. Twenty minutes is the wrong loop for a shader, a light or a line weight, and every graphics decision in this project that was made without a picture in front of it turned out to be wrong. It fails on a shader that did not compile, which is the one fault a picture will not show you. |
| `screenshots.sh` | anything you can only see — and the two things it MEASURES, because a real 1600x900 window is the only place a layout is real: how much of a card is below the fold, and what the card is sitting on top of. The second found the controls reminder buried under the patient card, with three letters of "pause" showing past its edge. |
| the fixture audit (in `smoke_run.gd`) | anything standing on nothing. Every `Fixture`'s footprint is tested against everything underneath it and reported as "chair floats by 4cm" or "bin is sunk by 11cm" — the failure two pieces of code that do not know about each other produce when they furnish the same square metre. |
| `tests/probe/data_run.gd` | the authored content itself — sixty-four people across six wards, every field a system will silently default if it is missing, and the one inequality every ward must satisfy (five beds earn less than three). The property tests assert what the game DOES; this asserts what it is made of, which is where a content bug lives. In `run_tests.sh`. |
| `tests/probe/econ_run.gd` | FOUR WAYS TO PLAY WITHOUT LOOKING AT ANYBODY. The career probe asserts "never looking NEVER pays it off" about exactly one blind policy — discharge all five, every night — which is the laziest blind play there is. The interesting one READS THE HANDOVER: keep whoever the night staff already wrote up as unwell, look at nobody, write nothing. It used to clear the whole debt in eleven nights and never be struck off. The file that found that printed four tables, asserted nothing and was not in `run_tests.sh`, so the largest design inversion in the game was discovered and reported to nobody — the same shape as a harness whose last pipeline stage is `head`. It fails on a blind career that PAYS and on one that neither pays nor is struck off in twenty-five nights, because a career that never ends is the loop the debt rework exists to stop. |
| `tests/probe/career_run.gd` | anything that only exists ACROSS days — the carry, the remembered beds, the denser rounds after a flag, the debt that grows on a short night. Plays twenty nights eight ways (coast, honest, honest+corroborated, restrained, skilled, one lie, greedy, adaptive). It found that `remembered_beds` was dead across a roster change and that `auditor_present` did nothing at all; after the rework it is the harness that proves crime pays only if you can stop. The six properties: honest play pays it off, a RESTRAINED liar pays it off faster, doing it every night does not, greed is struck off first, never looking at anybody NEVER pays it off, and one bad night is recoverable. Run on three seeds, because nine wards drawn from four pools is not the same nine wards twice; `CAREER_SEED` overrides. |
| `tests/probe/frontier_run.gd` | dominant strategies, and whether a day is a BUDGET. It fails on a checklist that fits in a shift, on an honest day that does not, and on a top-of-the-money night that is also a clean one — that last property had been PRINTED and never asserted for as long as the probe existed. It also plays an honest day on all 52 reachable boards rather than on the one its seed deals: "every ward has an honest day that signs off" was a claim about four boards out of fifty-two, and the four it happened to pick were the four where it was true. The second ward could not be signed off on ANY of its twelve. 2,601 plays a ward — every subset of beds up to three, crossed with thirteen ways of justifying a hold, crossed with whether you MIX them (a peer behind the bed that deserves one, your own note on the bed that does not), crossed with whether the day was played DILIGENTLY, crossed with how you answer in the room — reported as the most money made at each verdict. Two properties: **the top figure must not be reachable signed off**, and **every ward must have an honest day that signs off**. The second is why the 2,601st play is not a strategy at all but the day a careful person plays, written out by hand: the search alone reported ward four as having no clean day, and that was a claim about the search. In `run_tests.sh`; re-run it after touching the economy, the contradiction rules, the bed audit or a roster. |
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
