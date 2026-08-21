# HANDOFF — read this first if the session was interrupted

Rewritten continuously. `PROGRESS_LOG.md` is the append-only history; this file
is only ever "where things stand right now".

## Where the work lives

Branch: `claude/github-repo-deletion-3hf0gq`. Everything is committed and pushed
after each milestone — there should never be more than one batch of uncommitted
work. `main` is untouched.

An earlier stretch of this work was pushed to `claude/chronic-care`; the
designated branch was fast-forwarded onto it, so the two share history and the
designated branch is the one to use. If a container recycle ever leaves the
checkout behind again, `git log --oneline origin/claude/chronic-care` is where
to look for what went missing.

## How to run anything

Godot is NOT installed in this container by default; it gets wiped when the
container recycles. Re-fetch it first:

```bash
cd /tmp && curl -sSL -o godot.zip \
  "https://github.com/godotengine/godot/releases/download/4.3-stable/Godot_v4.3-stable_linux.x86_64.zip" \
  && unzip -o -q godot.zip && chmod +x Godot_v4.3-stable_linux.x86_64
export GODOT=/tmp/Godot_v4.3-stable_linux.x86_64
```

Then, from `/home/user/crypts-of-chaos`:

```bash
./run_tests.sh                       # units + smoke + live. Must be green before committing.
./check.sh scripts/foo.gd            # parse errors for specific files
./screenshots.sh                     # renders 32 stills — run after ANY world/UI change
./playfast.sh first_shift            # scripted playthrough, timings only, no renderer
./play.sh first_shift                # same but rendered, with screenshots
BALANCE_DAYS=30 BALANCE_SEEDS=3 $GODOT --headless --path . --script res://tests/balance_sim.gd
```

Screenshots land in `~/.local/share/godot/app_userdata/Chronic Care/shots/`.
Play-run logs land in `.../Chronic Care/play/`.

## Last known good

**2,202 assertions · 132 smoke checks (incl. an object-overlap audit) · 45 live
checks over 7,000 frames · boot check · 21/21 balance design checks · 71
screenshots.** Windows and Linux both export,
and the exported Linux build boots and exits cleanly.

`play.sh` takes 30-45 real minutes under this container's software GL — it is
rendering-bound, not simulation-bound. Use `playfast.sh` for the quick loop and
`play.sh` only when you need the photographs.

## Building

```bash
GODOT=/tmp/Godot_v4.3-stable_linux.x86_64 ./export.sh          # windows + linux, then runs the linux one
GODOT=/tmp/Godot_v4.3-stable_linux.x86_64 ./boot_check.sh      # real entry point only
```

Export templates are a separate ~1GB download and are NOT vendored. `export.sh`
prints the exact command to fetch them if they are missing.

## What has been done this session

See the Session 5 sections of `PROGRESS_LOG.md`. Headlines:

- **The minigames happen on a body.** `Anatomy` draws nine rigs (forearm,
  wrist, hand, ankle, knee, shoulder, ribs, brow, flank) out of one primitive.
  Setting a bone is holding a fragment steady against tremor and spasm;
  suturing is six bites down a laceration that moves as they breathe; dosing is
  which bottle times how much, drawn against graduations into a real arm.
- **You declare intent first and are graded against it.** Treat them or make it
  worse — doing either well is rewarded, doing either badly is punished, and
  intending harm and fumbling it is the worst square on the board.
- **The day ends at your office desk.** Anybody you did not see personally is
  treated correctly by a nurse, so the day is "which of these five is worth MY
  hands" rather than "get through the list".
- **The envelope**: any witness can be offered money in three sizes, with the
  odds off who they are and what they saw. Refusal costs no money and leaves
  behind something worse than what they saw.
- **The letter**: discharged patients sue. Settle for about half, or fight it
  with one of four lawyers ascending in price and descending in scruple.
  Imaging you ordered weeks ago cannot be edited and turns up in court.
- **The evening is a street you walk down**, in first person, with the same
  controls as the ward — not a top-down diagram. Road, pavements, two terraces
  of lit houses, a van to hide behind, sodium lamps that pool, watchers whose
  cones of vision are drawn on the pavement, and an exposure bar on the HUD.
  Reach somebody unseen and they are on your list in the morning; walk back the
  way you came if you change your mind. It is built four hundred metres UNDER
  the hospital, because hiding the hospital hides its meshes and not its
  colliders (`Street.ORIGIN`).
- **The title screen is a live 3D ward** rendered into a SubViewport behind the
  panel, with the camera drifting across it.
- **A fourth verb**: taking a dislocated joint through an arc, which is a
  tracking skill rather than a holding or clicking one.
- Rebindable keys, gamepad support, controls/credits/achievements screens,
  twenty-five achievements, click and hover sounds on every button.
- Every room dressed — curtains, gas panels, sharps bins, noticeboards,
  handrails, floor guide lines, bedside cabinets, vending machines.
- The balance simulation is **fully green for the first time**.

## Immediately next

Nothing is known-broken. The open questions are all playtest ones:

- Is the street's difficulty right? Three watchers with a 0.62 rad cone at 17 m
  over a 74 m street, exposure at 0.42/s scaled by how lit you are. It has
  never been played by a person, and all of those numbers are guesses.
- Walk-ins arrive as appointment slots. If the redesign wants more upright
  patients than bedbound ones, that ratio lives in
  `AppointmentSystem._make()`.

Two harmless noises worth knowing about before chasing them:

- ~180 `mesh_get_surface_count: Parameter "m" is null` errors per headless run.
  They come from Godot's *dummy* renderer, which has no meshes to count. They
  do not appear in the rendered screenshot runs and they are not a bug in this
  project.
- `ObjectDB instances leaked at exit` after a screenshot run. The harness quits
  from inside a `--script` main loop without tearing the scene down.
