# HANDOFF — read this first if the session was interrupted

Rewritten continuously. `PROGRESS_LOG.md` is the append-only history; this file
is only ever "where things stand right now".

## Where the work lives

Branch: `claude/chronic-care`. Everything is committed and pushed after each
milestone — there should never be more than one batch of uncommitted work.
`main` is untouched.

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

**1,569 assertions · 116 smoke · 23 live · boot check · 21/21 balance design
checks over 3 seeds · 36 screenshots.** Windows and Linux both export, and the exported Linux
build boots and exits cleanly.

## Building

```bash
GODOT=/tmp/Godot_v4.3-stable_linux.x86_64 ./export.sh          # windows + linux, then runs the linux one
GODOT=/tmp/Godot_v4.3-stable_linux.x86_64 ./boot_check.sh      # real entry point only
```

Export templates are a separate ~1GB download and are NOT vendored. `export.sh`
prints the exact command to fetch them if they are missing.

## What has been done this session

See the Session 4 sections of `PROGRESS_LOG.md`. Headlines:

- Day one now opens on an inherited ward with two people fit for discharge; the
  9am and 10am slots are their discharges.
- Shift deadline + live appointment countdown on the HUD.
- Staff step aside instead of body-blocking the corridor; props actually shove.
- Economy rebalanced: reckless play no longer pays best (it paid 3x careful).
- Length of stay is measured against the CHART, not the projection.
- Noise events not caused by the player were being discarded, so throwing
  something to distract a nurse had never worked.
- The treatment dial turns both ways and reports only where it stops.
- Ward door cards; corridor flag signs.

## Immediately next

The parallel audit (`chronic-care-audit` workflow) produced **28 verified
findings, 26 refuted**. **All 28 are now fixed.** Full detail in
`PROGRESS_LOG.md` — the headline ones were: no door in the building had ever
closed anything; three separate ways to end a career by pressing Escape;
throwing something to distract a nurse had never worked; the tutorial could
never get past step 1 of 6; calibration sabotage and log-wiping had no way in;
and substituting a syringe's contents was completely free.

Brief phases not yet started: 6 (comedy pass), 7 (emergent chaos), 8 (events
that change strategy), 11 (visible progression), 12 (content), 14 (juice), 15
(streamability), 19 (performance profiling).

Done since: 5 (NPC behavioural tells — they stop and write things down, gossip
is a scene), 9 (a wrong site is a revisable situation, and the site is marked on
the patient), 13 (the shift report says what the shift was), 16 (three shifts
that look and play differently — the ward sleeps at night), 20 (export), plus a
bright/cartoony visual pass across the whole game.

Phase 20 (export) is DONE — `export.sh` builds both presets and launches the
Linux one. The only cosmetic outstanding is that the .exe carries no icon or
version block, which needs `rcedit` and cannot be done from this container.

Two things worth knowing before picking anything up:

- **ward_102 approached laterally from the hinge side** is the only door of
  eleven that still fails `play.sh doors`.
- Across all four playstyle runs, **the player's money never moves during a
  shift**. The crime pays only at clock-out, so the HUD money ticker has
  nothing to show while you are actually playing.

## Standing constraints from the brief

- Priority order: fun > comprehension > meaningful decisions > tension > comedy
  > emergent stories > replayability > polish > content > technical complexity.
- **Do not confuse more content with more fun.**
- Nothing in the UI is ever labelled "questionable". No suspicion number.
- Suspicion is derived, never stored.
- Don't ask questions; use judgement and keep building.
