# HANDOFF — read this first

`PROGRESS_LOG.md` is the append-only history. This file is only ever "where
things stand right now", and it is rewritten rather than added to.

> **This file was, until recently, three reworks out of date.** It described
> minigames on an anatomy rig, an evening street phase, a lawsuit system,
> twenty-five achievements and a balance simulation — none of which exist, and
> most of which were deliberately cut. If anything below ever stops matching
> `git log`, believe the log.

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
./run_tests.sh                    # all of it, ~6 min. Green before committing.
./check.sh scripts/foo.gd         # parse errors for specific files
./look.sh try1                    # FOUR frames, ~4 min — the loop for a shader,
                                  # a light, a line weight or a face
./screenshots.sh                  # all 21 frames plus two layout measurements
SHOT_ONLY=struck_off ./screenshots.sh   # one frame, ~90 s
./playfast.sh day                 # play a whole shift with a controller
./play.sh keys                    # WASD and a real mouse, under Xvfb
./export.sh all                   # windows, linux, macos — and RUNS the linux one
```

Screenshots land in `~/.local/share/godot/app_userdata/Chronic Care/shots/`,
`look.sh` frames under `.../look/`.

Export templates are a separate ~1GB download and are NOT vendored; `export.sh`
prints the exact command to fetch them.

## Last known good

**298 assertions · 170 smoke checks on three seeds · 7 day criteria · 6 career
properties on three seeds · 2,601-strategy frontier probe per ward · both play
runs · the quiet check · the boot check.** All three platforms export and the
Linux build boots and exits cleanly.

## What this game is, in one paragraph

First-person, one hospital floor, one twelve-hour shift, five beds. Six verbs,
all of which cost minutes off one clock, so a day is a budget rather than a
checklist. Three layers are allowed to disagree — what is TRUE, what the
RECORD says, and what somebody BELIEVES — and the ward sister's review at eight
o'clock is a read across the gaps. There is no evening phase, no legal phase
and no minigame; `ShiftSystem`, `NightSystem` and `LegalSystem` are gone.

## Open, in rough order of value

1. **Nothing is known-broken.** The suite, the screenshots and the exports are
   all green as of the last commit.
2. **Whether tripling the outline weight costs real fill on hardware.**
   Unmeasurable on llvmpipe; needs a machine with a GPU.
3. **Faces are geometry, not lighting.** Measured twice: `BACKLIGHT` at 0.28
   moved 6,100 pixels by at most 27 levels and the face read identically, and
   at 0.70 — well past subtle — 6,300 pixels by at most 52. The heads have
   varied skulls, noses, jaws and five hairstyles now, which is what made the
   ward read as five people; the FACE itself is still an egg with decal eyes.
   If it is worth another attempt it belongs in `npc_body.gd`.
4. **The game has never been played by a person.** Every design number in it —
   the verb costs, the round times, the forty-five-minute window — is validated
   by probes rather than by anybody's hands.

## Two noises that are not bugs

- `Parameter "m" is null` from the headless dummy rasterizer, one line per
  `Label3D` freed. `run_tests.sh` filters it and says why.
- `ObjectDB instances leaked at exit` after a `--script` run: a looping
  AudioStreamWAV that is still playing when `quit()` yanks the audio server.
  `boot_check.sh` documents it at length. The RID leak that used to sit beside
  it was real, and is fixed.
