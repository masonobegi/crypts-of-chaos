# HANDOFF — read this first

`PROGRESS_LOG.md` is the append-only history. This file is only ever "where
things stand right now", and it is rewritten rather than added to. It is
updated and pushed as work proceeds, so an interrupted session loses nothing
but the half-finished edit in the buffer.

> **This file was, until recently, three reworks out of date.** It described
> minigames on an anatomy rig, an evening street phase, a lawsuit system,
> twenty-five achievements and a balance simulation — none of which exist, and
> most of which were deliberately cut. If anything below ever stops matching
> `git log`, believe the log.

## Live log — 2026-09-23

**State: green and shipped-shaped.** Version 1.0.0. `run_tests.sh` passes end to
end (368 assertions, 292 smoke checks on three seeds); `screenshots.sh` renders
all 30 frames and passes its own checks.

Nothing is half-done in the working tree. The last two sessions were audits of
the BUILDING and then of the STORE PAGE, and between them they are where every
commit below came from.

| What |
|---|
| The patient in the bed was a head on a slab |
| Four curtain rails were hanging from nothing |
| Nothing in this building is inside anything else |
| Six IV stands were hanging ninety centimetres above the floor |
| Every character walked with their toes five centimetres into the floor |

**In flight right now:** nothing.

**Where this build actually stands, rated the way a buyer rates it.** The loop
is the asset and it is the thing a store page cannot show: truth, record and
belief allowed to disagree, six verbs on one twelve-hour clock, no dominant
strategy across a 2,601-strategy search per ward. Everything weak is
presentation, and the two surfaces a buyer sees were the two worst things in
the build — the capsule could not be read and the frame the game is played in
was a head on a slab. Both are fixed; what is still short is listed under
**Open** and the top three are a TRAILER, ACHIEVEMENTS and LENGTH. A career is
nine nights at eight to fifteen minutes a shift, which is an hour and a half to
two and a half hours to see everything the game has, one win state and one lose
state. That is a five-to-eight dollar game as it stands and no amount of polish
moves it.

**What the last session changed.** An arm was one rigid node from the shoulder
to the knuckles — the leg has had a knee and an ankle since the walk went in —
so both arms and both hands sat twenty centimetres inside the bedding on every
patient in every ward, and `03_bedside` was a bald head floating over a teal
slab. It has an elbow now and the angles are solved rather than guessed. The
capsule's strapline fell off the dado onto the pale floor and dissolved; the
camera was 5.9m back on a 52-degree lens with 45% of the frame empty plane; and
the sight line past the nurse ran through a plant pot whose terracotta lined up
exactly with the gap between her legs. The floating name over a bed was white
on cream and unreadable at fifteen metres. The main menu's third stop was a
developer seed field. The view through every window was three flat bands. And
there was nowhere in the game to read what the six verbs cost.

**`00d_hero` is new and is the frame a store page should lead with.**
`02_ward_from_door` is a DIAGNOSTIC and cannot move — two measured pairs are
taken from it — and it is a bad photograph: measured, 48% of its 3D area is
flat ceiling or flat floor and a patient's head in it is 45 pixels tall. The
new one is 0%.

## Previous log — 2026-09-10

**State: green and shipped-shaped.** Version 1.0.0. `run_tests.sh` passes end
to end (363 assertions, 267 smoke checks on three seeds); `screenshots.sh`
renders all 28 frames and passes its own checks; all three platforms export at
1.0.0 and the Linux build boots and exits cleanly.

Nothing is half-done in the working tree. This session's commits, newest first:

| What |
|---|
| The check for "a function nobody calls" passed with ten of them in it |
| The capsule the menu has been able to pose for all along |
| The screen that promises who saw you, and the record of who saw you |
| Sixty-seven seeds, and a click that did not exist |
| The board was read from a random floor tile |
| The station, and an argument the file had already made |
| Nobody looked at the doctor standing over them |
| Four things in the frames, found by looking at them again |
| Two measurements that printed a number nobody read |
| The eye socket was seating something that had been deleted |
| The ladder, asserted where it can be read |
| The career probe was driving a different doctor to the frontier probe |
| Something on the screen |
| Two engine errors on the one transition every player makes |
| The three cards you read at the desk are read at the desk |
| One of the twenty-eight frames had no card on it |
| Two more Ward Cs, on the two biggest pieces of text in the game |
| The wayfinding was turned ninety degrees from the way people walk |
| "Shared" meant shared by index, and a sphere does not share its seam |
| A painted marking was casting a shadow onto itself |
| HANDOFF is the live log again |
| 1.0.0 |
| Fifteen hedges were standing inside the building |
| The man in bed was still in his shoes, and the bay strip was a green rug |
| Every sign in the building agreed on the ward's name except three |
| Two more wards, and the three rules they broke |

**In flight right now:** nothing. Everything below is committed and pushed, the
whole suite is green (368 assertions, 273 smoke checks on three seeds), all 29
frames render and pass their own checks, and all three platforms export with the
Linux build booting and exiting cleanly.

**This session**, in the order it happened. A `CAREER_SEED` sweep across
twenty-seven values found three faults in the career probe and, under them, one
real inversion in the economy — the every-night liar was beating the restrained
one, which is the single thing the whole design is built to prevent
(`ENTRENCHED_NIGHTS` is 4 now, and two unit tests pin the ladder from both
ends). Then the eye socket, which had been seating a sclera deleted three passes
ago and was eating the contrast the darkest faces need. Then the shot harness:
its two layout measurements now fail the run rather than printing a number
nobody reads, and asking them at the interface sizes the SLIDER offers found the
money plate and the objective plate under the card on every screen above 100%.
Then the frames — the handover staged in the wrong room, the morning briefing
reading 7:25 PM, the objective arrow pointing at the player's own feet, the
handover board photographed from a random floor tile, the station's six-metre
worktop built as exactly the slab its own neighbour's comment condemns. Then the
biggest one: the harness moves a camera and leaves the body, so every world
frame was photographed from a place nobody was standing — which is how "nobody
in this game ever looks at the doctor standing over them" stayed invisible.
Then two duplications that were lies rather than untidiness: the screen that
promises who saw you and the record of who saw you were two copies of one loop.
And finally the dead-code sweep — ten functions with no caller, two of which
were features nobody finished (the store capsule and the vending machine the
tannoy talks about), and the CHECK that was supposed to catch them, which had
been passing with all ten in it because it counted bare tokens.

See `PROGRESS_LOG.md` and gotchas 110-127.

The frame-by-frame pass of item 2 is DONE —
every one of the 28 screenshot frames and all six `faces.sh` portraits have been
looked at closely, and everything found was fixed. Nine faults came out of it,
of which four had been shipping for a long time with the whole suite green
around them.

**Three things looked at and deliberately left:**
- Two dark stripes on the corridor floor running parallel to the wayfinding
  lines. Proved by a magenta test NOT to be `Dressing.floor_line`; best
  remaining hypothesis is the wall-mounted strip lights' housings casting
  shadows from the ceiling spots, which is physically right and reads as floor
  marking.
- `09_ward_evening` shows nobody dozing, because the shot harness sets the clock
  directly rather than running the sim. The frame exists for the LIGHT and is a
  controlled pair with `02_ward_from_door`.
- The corridor and office keep Ward C's teal dado on every ward. Only the ward
  room repaints. Defensible — corridors are painted on their own schedule — but
  see item 5.

## Where the work lives

Branch: `claude/github-repo-deletion-3hf0gq`. Everything is committed and
pushed after each milestone; there should never be more than one batch of
uncommitted work. `main` is untouched. An earlier stretch was pushed to
`claude/chronic-care` and the designated branch was fast-forwarded onto it, so
the two share history — if a container recycle ever leaves the checkout behind,
`git log --oneline origin/claude/chronic-care` is where to look.

## How to run anything

Godot is NOT installed in this container by default and is wiped when the
container recycles. Re-fetch it first:

```bash
cd /tmp && curl -sSL -o godot.zip \
  "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip" \
  && unzip -o -q godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64
export GODOT=/tmp/Godot_v4.3-stable_linux.x86_64
```

Then, from `/home/user/crypts-of-chaos`:

```bash
./run_tests.sh                    # all of it, ~9 min. Green before committing.
./check.sh scripts/foo.gd         # parse errors for specific files
./look.sh try1                    # FOUR frames — the loop for a shader, a light
                                  # or a line weight
./faces.sh try1                   # SIX faces close up, one body, the cast —
                                  # the loop for a CHARACTER
./screenshots.sh                  # all 28 frames plus two layout measurements
SHOT_ONLY=struck_off ./screenshots.sh   # one frame, ~90 s
./playfast.sh day                 # play a whole shift with a controller
./play.sh keys                    # WASD and a real mouse, under Xvfb
./export.sh all                   # windows, linux, macos — and RUNS the linux one
```

Screenshots land in `~/.local/share/godot/app_userdata/Chronic Care/shots/`,
`look.sh` frames under `.../look/`, `faces.sh` under `.../faces/`.

Export templates are a separate ~1GB download and are NOT vendored; `export.sh`
prints the exact command to fetch them.

## Last known good

**368 assertions · 292 smoke checks on three seeds · 39 day criteria runs
against 7 criteria · the authored-data, ship, draw and economics checks · 6
career properties on three seeds · a 2,601-strategy frontier probe per ward plus
an honest day on all 128 reachable boards · both play runs · the quiet check ·
the boot check.** All three platforms export at 1.0.0 with no placeholders, and
the Linux build boots and exits cleanly. `./play.sh keys` passes separately
under Xvfb.

## What this game is, in one paragraph

First-person, one hospital floor, one twelve-hour shift, five beds. Six verbs,
all of which cost minutes off one clock, so a day is a budget rather than a
checklist. Three layers are allowed to disagree — what is TRUE, what the
RECORD says, and what somebody BELIEVES — and the ward sister's review at eight
o'clock is a read across the gaps. There is no evening phase, no legal phase
and no minigame; `ShiftSystem`, `NightSystem` and `LegalSystem` are gone.
Six authored wards, sixty-four patients, 128 boards a nine-night career can
reach, and the ward order is drawn per career.

## Open, in rough order of value

0. **THERE IS NO TRAILER, THERE ARE NO ACHIEVEMENTS, AND A CAREER IS UNDER
   THREE HOURS.** These are the three things standing between this build and a
   store page that converts, and none of them is a bug. A trailer is the single
   asset a Steam page is mostly judged on and this project has never produced
   one second of motion — `screenshots.sh` can pose and photograph anything, so
   the machinery is there and what is missing is a shot list. Achievements need
   GodotSteam, which is a GDExtension and a build step, and a page with zero of
   them reads as unfinished to a large slice of buyers. And nine nights at eight
   to fifteen minutes a shift is an hour and a half to two and a half hours,
   with one win state and one lose state: that is a five-to-eight dollar game
   and polish does not move it. Item 10 below is the honest lever on the last
   one and its own note explains why the obvious version of it breaks the
   economy.
1. **THE GAME HAS NEVER BEEN PLAYED BY A PERSON.** Every design number in it —
   the verb costs, the round times, the forty-five-minute window — is validated
   by probes rather than by anybody's hands. This is the biggest open item by
   some distance and no amount of further polish substitutes for it.
2. **Keep looking at frames.** THREE full passes are done now and between them
   they found twenty-five faults, most of which had been shipping for a long
   time with the whole suite green around them — a hedge growing inside the office, a
   hairline on every rounded box, the corridor's wayfinding hung edge-on, seven
   places naming the wrong ward, an eye socket seating a sclera deleted three
   passes ago, the morning briefing reading 7:25 PM, nobody in the building
   looking at the doctor standing over them. The loop is
   `SHOT_ONLY=<frag> ./screenshots.sh` at ninety seconds a frame, and the red
   test — turn the suspect piece bright red and re-render one frame — settles an
   argument in ninety seconds rather than an afternoon. Re-do the pass after any
   change to `Surfaces`, `Build`, `Dressing` or `NPCBody`.
   The third pass was an audit of the BUILDING and most of what it found was
   geometric rather than visual — things floating, things inside each other,
   things hung on a window — so nine of its findings are now standing checks
   and will not come back. What a frame is still the only way to see: whether a
   composition works, whether an object reads as the thing it is meant to be,
   and whether a colour is doing what its comment says.
3. **The floor is a third of several frames and there is nothing on it —
   LOOKED AT AND LEFT, with the reasoning, because it will come up again.**
   `06_station`, `02_ward_from_door` and `05_ward_along` all put the horizon at
   about 55% and fill the bottom with empty vinyl. The station's was real and is
   fixed (a chair at the worktop, and the camera moved in). The WARD's is not:
   `_dress_ward_top` already puts the working end — linen, hamper, boxes, mop
   bucket, whiteboard, gel, stools, water cooler — along the DOOR wall, which is
   the wall the store-page camera stands against, so all of it is behind the
   lens. The clear floor between the door and the beds is the space a ward is
   supposed to keep clear. **Read gotcha 83 before touching this**: two attempts
   at "the empty planes" — downstand beams and floor lines — were both worse
   than the emptiness, and what landed was the thing that was MISSING rather
   than the thing that was empty. If this is revisited, the lever is the CAMERA
   (gotcha 49), not more objects — but `02_ward_from_door` is one half of two
   measured pairs (`02b_fittings_off`, `09_ward_evening`), so both halves have
   to move together and both readings re-taken.
4. **The store capsule is a 16:9 frame and a capsule is not.** `00c_capsule`
   renders the posed title room with the game's name over the quiet left, at
   1457x820. Steam's header is 460x215 (about 2.14:1) and the library capsule is
   600x900, i.e. VERTICAL. The composition survives a centre crop to the header
   shape — the subjects sit vertically centred and the title is low-left — and
   does not survive a portrait crop at all. Whoever makes the store art should
   pose again for that one: `MenuScene.pose_for_capsule` is the place, and the
   loop is `SHOT_ONLY=00c_capsule ./screenshots.sh` at ninety seconds a try.
5. **The corridor and the office keep Ward C's teal dado on every ward.**
   Deliberate — only the ward room repaints — but a player walking from a teal
   corridor into a slate ward may read it as a bug. `Hospital.WARD_DADO_GROUP`
   tags on `mid.z > 4.05`; widening it to the corridor is a one-line change plus
   a look.
6. **The Windows exe has no icon and no version block.** `export.sh` says so and
   names the remedy — install rcedit and point `export/windows/rcedit` at it;
   Godot generates the icon from `config/icon` once it has the tool, so nothing
   needs committing. `STRICT=1 ./export.sh` treats it as a release blocker,
   which is the right setting for the build that actually ships. Not fixable in
   this container: rcedit is a Windows binary.
7. **THE NURSES' STATION COUNTER IS UNIFORMLY LIT ALONG ALL SIX METRES OF IT,
   and the reason it has not been fixed is worth more than the fault.** Measured
   off `06_station`: the counter's front face reads 123..129 across its whole
   width — a spread of SIX — while the floor in the same frame runs 121..171 and
   the wall 83..129. `Furniture._block` goes through `Build.wall`, which goes
   through `box_mi`, which is `rbox_mesh`: a Minkowski-summed sphere whose
   vertices all end up on the piece's own edges, so a 6 x 0.86 face has nothing
   in the middle of it for a ceiling fitting to light. It is gotcha 131 and
   gotcha 139 on the largest object in the room, and it is most of why that
   counter still reads as a slab after the kick and the shadow gap went in.
   **The obvious fix does not work.** `slab_mesh` subdivides, which is why the
   floors, the walls and now the bay markings and the doormats use it — but
   Godot's `BoxMesh` splits its vertices at every edge, and the inverted-hull
   outline pushes each vertex along its own normal, so an INKED subdivided box
   opens a crack down every edge (gotchas 37 and 104 are both about exactly
   this). The counter has an outline and should keep one. The real fix is
   `rbox_mesh` built from a SUBDIVIDED box rather than from a bare sphere, so
   the Minkowski sum keeps the rounded corners and the shared normals AND gains
   interior vertices. That is a change to the function every solid in the
   building is made of, so it wants its own session and a full frame pass after
   it.
8. **Whether tripling the outline weight costs real fill on hardware.**
   Unmeasurable on llvmpipe; needs a machine with a GPU.
9. **The hands are still mittens with a thumb**, and there are no cheekbones.
   Both are `npc_body.gd`, and both should be judged from `faces.sh` and not
   from a twenty-minute screenshot run. The socket removal (gotcha 113) is the
   evidence that this model wants FEWER pieces rather than more: read gotcha 86
   before adding geometry to a face.
10. **A second ill-pair per ward.** The 128 boards are 21 puzzles wearing 128
   sets of names, because a ward's variability is one coin flip.
   `ILL_PAIR_BY_DAY` becomes a LIST of pairs, `_pair_flip` takes an index, and
   `enumerate_draws` folds over them. **Read this before doing it:** a pair
   means "exactly one of these two is ill", so a SECOND pair adds an ill
   patient to the ward and the honest hold count goes 2 -> 3, which is the
   money-optimal count — honest play would then earn what the best lie earns
   and the central tension collapses. The safe shapes are a same-tier GROUP of
   three (exactly one ill, count unchanged) or a pair on a DIFFERENT axis,
   `no_care_at_home`, which moves which bed the social lesson is on and cannot
   touch the economy at all. Whichever, `frontier_run` is the arbiter: it plays
   an honest day on all 128. **Weigh it against the rule that matters most**:
   128 deals crossed with 720 ward orders is already a great deal of variety,
   and more content is not more fun.

## Two noises that are not bugs

- `Parameter "m" is null` from the headless dummy rasterizer, one line per
  `Label3D` freed. `run_tests.sh` filters it and says why.
- `ObjectDB instances leaked at exit` after a `--script` run: a looping
  AudioStreamWAV that is still playing when `quit()` yanks the audio server.
  `boot_check.sh` documents it at length. The RID leak that used to sit beside
  it was real, and is fixed.
