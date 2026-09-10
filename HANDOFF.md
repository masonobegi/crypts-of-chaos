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

## Live log — 2026-09-10

**State: green and shipped-shaped.** Version 1.0.0. `run_tests.sh` passes end
to end; all three platforms export; the Linux build boots and exits cleanly.

Nothing is half-done in the working tree. Recent commits, newest first:

| Commit | What |
|---|---|
| `HEAD` | A painted marking was casting a shadow onto itself |
| — | HANDOFF is the live log again |
| `82b5bcc` | 1.0.0 — version bumped in `project.godot` and all four `export_presets.cfg` fields |
| `69702d4` | Fifteen hedges were standing inside the building |
| `0528d81` | The man in bed was still in his shoes, and the bay strip was a green rug |
| `30dec47` | Every sign in the building agreed on the ward's name except three |
| `1738fb5` | Two more wards, and the three rules they broke |

**In flight right now:** working through item 2 under *Open* — looking at every
screenshot frame in turn. Examined and clean so far this pass: `00_title`,
`01_corridor`, `02_ward_from_door`, `02e_ward_beech`, `02f_ward_2a`,
`03_bedside`, `04_face` (`try1__04`), `04b_lineup` (as `try1__cast`),
`05_ward_along`, `06_station`, `07_office`, `08_ward_wide`, `11_patient`,
`17_review`, `18_day_over`. Still to examine: `00b_title_settings`,
`02b_fittings_off`, `04c_visitor`, `09_ward_evening`, `10_morning`, `12_chart`,
`13_board`, `14_write`, `15_ward_two`, `16_ward_three`, `19_paid`,
`20_struck_off`.

**One thing looked at and deliberately left:** two dark stripes on the corridor
floor running parallel to the wayfinding lines. Proved by a magenta test NOT to
be `Dressing.floor_line`; best remaining hypothesis is the wall-mounted strip
lights' housings casting shadows from the ceiling spots, which is physically
right and reads as floor marking. Not worth more archaeology.

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

**363 assertions · 265 smoke checks on three seeds · 39 day criteria runs
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

1. **THE GAME HAS NEVER BEEN PLAYED BY A PERSON.** Every design number in it —
   the verb costs, the round times, the forty-five-minute window — is validated
   by probes rather than by anybody's hands. This is the biggest open item by
   some distance and no amount of further polish substitutes for it.
2. **Keep looking at frames.** Every visual fault found in the last two
   sessions was found by looking, and each one had been shipping for a long
   time with the whole suite green around it: a hedge growing inside the
   office, five signs naming the wrong ward, a patient in bed in his shoes, a
   folding screen that ignored the ward palette. There is very likely more. The
   loop is `SHOT_ONLY=<frag> ./screenshots.sh` at ninety seconds a frame.
   Frames not yet examined closely this pass: `04b_lineup`, `04c_visitor`,
   `05_ward_along`, `09_ward_evening`, `10_morning`, `12_chart`, `13_board`,
   `14_write`, `15_ward_two`, `16_ward_three`, `19_paid`, `20_struck_off`,
   `00b_title_settings`.
3. **Two `Parameter "data.tree" is null` errors on every launch.** Bisected to
   after `Game._start()` returns — in a `start_day()`/`day_started` listener or
   the morning screen. Pre-existing, harmless, not yet located. They are NOT
   filtered by the quiet check, which reads only `ERROR|SCRIPT ERROR|WARNING`
   lines from the play run; these come from the shot harness.
4. **The office EHR monitor is a blank green rectangle.** The terminal is the
   object the game is about and its screen has nothing on it.
5. **The corridor keeps Ward C's teal dado on every ward.** Deliberate — only
   the ward room repaints — but a player walking from a teal corridor into a
   slate ward may read it as a bug. `Hospital.WARD_DADO_GROUP` tags on
   `mid.z > 4.05`; widening it to the corridor is a one-line change plus a
   look.
6. **Whether tripling the outline weight costs real fill on hardware.**
   Unmeasurable on llvmpipe; needs a machine with a GPU.
7. **The hands are still mittens with a thumb**, and there are no cheekbones.
   Both are `npc_body.gd`, and both should be judged from `faces.sh` and not
   from a twenty-minute screenshot run.
8. **A second ill-pair per ward.** The 128 boards are 21 puzzles wearing 128
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
   an honest day on all 128.

## Two noises that are not bugs

- `Parameter "m" is null` from the headless dummy rasterizer, one line per
  `Label3D` freed. `run_tests.sh` filters it and says why.
- `ObjectDB instances leaked at exit` after a `--script` run: a looping
  AudioStreamWAV that is still playing when `quit()` yanks the audio server.
  `boot_check.sh` documents it at length. The RID leak that used to sit beside
  it was real, and is fixed.
