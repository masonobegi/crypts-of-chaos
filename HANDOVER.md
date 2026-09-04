# Paused mid-polish — where to pick up

Everything below is committed and pushed on `claude/github-repo-deletion-3hf0gq`
(HEAD `1feed12`). Working tree clean. Suite green:

```
GODOT=/tmp/Godot_v4.3-stable_linux.x86_64 ./run_tests.sh
274 assertions · 79 smoke checks · 7/7 playtest criteria
32 authored people · 32/32 deals playable · boot check · exit 0
```

**NOTE:** the container has rolled back three times this session. If
`scripts/systems/cases.gd` is missing or a `night_system.gd` appears, recover:
`git checkout -- . && git clean -fdq && git fetch origin <branch> && git merge --ff-only origin/<branch>`

## What this session fixed

A 7-lens adversarial audit (64 agents, 43 verified findings) found things no
screenshot could. The worst were real and are fixed:

- **The crosshair printed the answer key.** Looking at a patient appended "fit
  to go home", derived from `truly_well`. Walking the row for free answered the
  only question the game asks. Guarded by a test now.
- **No career could reach day two.** The handover's "Go home" emitted `day_over`
  and then called `close()`, freeing the card it had just opened. Escape and the
  paused-tree main-menu exits had the same class of hole.
- **Two of three terminals were dead** and there was no `records` screen at all,
  so writing a note anywhere private — the core of the whole "who saw you type
  it" mechanic — was impossible. New `screen_records.gd`.
- Settings on the title screen captured the cursor and left the game HUD on the
  menu; the office terminal ended the shift on one unconfirmed keypress; the
  debt's 10%/night interest was charged and never shown; every verb was
  unpriced; the ward sister's opening line was at 1.5:1 contrast.
- Visual: the empty half of the ward is dressed, signs no longer render
  mirrored, patients no longer look walleyed, the verdict stamp encloses its
  text, the patient card no longer hangs off the bottom of the window.

## What is still open, in priority order

The full ranked ship plan is in the workflow output:
`/tmp/claude-0/.../tasks/w8gy9omi9.output` → `result.ranked` (read it with
`json.load(...)["result"]["ranked"]`). If /tmp is gone, re-run the audit.

1. **W11 — the answer key never moves.** Every genuinely ill patient sits on a
   bed slot with exactly ONE candidate, so although the cast is drawn per
   career, *which bed* is ill is fixed per ward. Fix by authoring an alternate
   for each honest-hold slot (`marchetti` d1 b1, `bux`/`lomax` d2, `okwuosa`
   d3, `ashworth`/`vane` d4) — same tier, same `truly_well`, per the data
   check's interchangeability rule.
2. **W5 — the returning test result is silent** and draws behind the open card.
   It is the loop's only delayed payoff. `hud.gd:404` plays audio only for
   "money"/"bad"; `ward_day.gd:74` emits it as "info".
3. **W6 — settings toggles are 1.6:1 and ON/OFF look identical on hover.**
   `ui_kit.gd:213`.
4. **W8 — ambience picks four room keys that do not exist** (`lobby`,
   `ward_101`, `ward_105`, `supply`), so two thirds of it emits from world
   origin and the ward gets none. `ambience.gd:49`. Add a test asserting every
   key passed to `Hospital.point_in` is in `LAYOUT`.
5. **W9 — the off-screen objective arrow floats mid-screen** rather than at the
   edge; it is in several first-minute screenshots. `hud.gd:249`.
6. **W10 — two of three tutorial lines are unreachable** and one quotes $3,200
   against a `DEBT_DUE` of $2,200. `tutorial.gd:45` — `note()` has one caller.
7. Audio breadth generally: one 23-second music loop for a 2-3 hour career,
   every character speaks with the same grunt, endings play in silence.

## Known non-defect

The frontier probe still reports "no clean day" on ward four. A clean day there
is real — played by hand twice, signed off, 0 indefensible, 0 solo. The probe
applies ONE verb uniformly to every held bed, and the honest ward-four day needs
different treatment per bed. `only_if_needed` narrowed it (ward four now reaches
the top figure at 'noted'). The property the probe defends still holds on all
four wards: the most money anybody makes is never available signed off.
