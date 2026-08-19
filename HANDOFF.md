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

**1,553 assertions · 95 smoke · 17 live · boot check · 20/20 balance design
checks over 3 seeds.** Windows and Linux both export, and the exported Linux
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

1. A background audit workflow (`chronic-care-audit`) is/was running over seven
   areas: shared-material mutation, dead content, whether the institution ever
   mentions beds, unreachable affordances, whether the three shifts differ,
   progression + end-of-shift payoff, and first-hour comprehension. Its findings
   are adversarially verified before being believed. **Check for its result and
   work the confirmed list in severity order.**
2. Remaining brief phases not yet started: 5 (NPC behavioural tells), 6 (comedy
   pass), 7 (emergent chaos), 8 (events that change strategy), 9 (soften
   accidental wrong-site failure diegetically), 11 (visible progression), 12
   (content), 13 (shift results with personality), 14 (juice), 15
   (streamability), 16 (make the three shifts substantially different), 19
   (performance profiling).

Phase 20 (export) is DONE: `export.sh`, both presets build, the Linux build is
launched and checked as part of it. The only outstanding cosmetic is that the
.exe has no icon or version block, which needs `rcedit` and cannot be done from
this container.

## Standing constraints from the brief

- Priority order: fun > comprehension > meaningful decisions > tension > comedy
  > emergent stories > replayability > polish > content > technical complexity.
- **Do not confuse more content with more fun.**
- Nothing in the UI is ever labelled "questionable". No suspicion number.
- Suspicion is derived, never stored.
- Don't ask questions; use judgement and keep building.
