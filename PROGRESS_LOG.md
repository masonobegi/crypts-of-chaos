# BUILD LOG — Chronic Care

> Append-only work log. **If you are a future session picking this up: read the
> "NEXT UP" section at the bottom, then `git log --oneline` to see where things stand.**

Engine: **Godot 4.3** (headless binary validated in-session; project opens in 4.3+).
Validation command:
```
$GODOT --headless --path . --script res://tests/run_tests.gd
```
where `$GODOT` is a Godot 4.3 linux binary (downloaded to the session scratchpad,
not committed — see docs/BUILDING.md).

---

## Session 1 — 2026-08-19

### Done
- [x] Wiped prior repo contents (owner request), started fresh.
- [x] Project skeleton: `project.godot`, input map, physics layers, `.gitignore`.

- [x] `docs/DESIGN.md` — critique of the brief + the five design changes made.
- [x] Autoloads: Log, RNG (seeded, per-stream), EventBus, DB (content), GameState,
      AudioMgr (fully procedural synthesis — zero audio assets), SaveSystem.
- [x] Core data model: WorldEvent (truth) / PatientChart (record) / Mind+Evidence
      (belief) / Patient / Complication.
- [x] Headless test harness + 118 passing assertions.

### Gotcha found (documented in docs/BUILDING.md)
`preload()` of scripts that reference many `class_name` types deadlocks the
GDScript loader when combined with typed signal params on an autoload. Fixed by
(a) untyping EventBus signal params and (b) using runtime `load()` in the runner.

- [x] Player controller (FPS, crouch, physics shove) + spring-based grab/throw.
- [x] Prop system, 25 items as data, procedural silhouettes, breakage, noise.
- [x] Procedural hospital: 12 rooms (corridor, 5 wards, lobby, nurses' station,
      treatment bay, supply, staff WC, office), two-tone walls with punched
      doorways, hinged physics doors, signage, lights, full furniture pass.
- [x] Custom A* NavGrid (not a baked NavMesh — needs to work headless and be
      seed-reproducible). Integration test proves every room is reachable.
- [x] Fixtures: treatment machines (dial + prescribed value + auditable log +
      invisible calibration sabotage), windows, light switches, EHR terminals,
      shredder, supply shelves, vitals consoles, patient beds (rigid bodies you
      can wheel down the corridor with someone still in them).
- [x] 279 assertions green.

### Gotchas found (both now guarded in the runner / documented)
1. `preload()` + typed autoload signals deadlocks the GDScript loader.
2. Adding a script with a new `class_name` leaves the global class cache stale
   until `--import` runs; run_tests.sh now always does an import pass first.
3. **Calling `.new()` on a script with parse errors HANGS the process** rather
   than erroring. run_tests.gd now gates every instantiation on
   `can_instantiate()`.

- [x] NPC layer: bodies, perception (FOV/LOS/hearing/attention), SuspicionSystem
      (witness routing, corroboration, gossip, complaints, institutional minds,
      statistical inference), Dialogue (barks + conversations with real odds).
- [x] Simulation: PatientSystem, TreatmentSystem, EconomySystem, RecordsSystem,
      InvestigationSystem (incl. covert/undercover), RandomEventSystem, Upgrades,
      Endings, ShiftSystem (full day loop).
- [x] UI: procedural toolkit + HUD + 13 screens (briefing, chart, records
      terminal, dialogue, chart review, shift report, upgrades, tablet, pause,
      tutorial, game over, vitals, treatment).
- [x] Game root wiring, Game.tscn, MainMenu.tscn with run seeds.
- [x] **Headless playthrough test** (`tests/smoke_run.gd`): boots the real scene,
      plays a full shift, exercises sabotage → complication → documentation →
      audit → billing → save/load → day rollover. 37 checks.
      **This caught two real bugs that compilation could not:**
      1. Spawning into `get_tree().current_scene`, which is null whenever the
         game is instantiated into the tree rather than loaded as the scene root
         — silently dropped every patient body and chart.
      2. A ternary that bound to `box_mesh()`'s argument instead of the whole
         expression, passing a Vector3 where a Mesh was expected (null mesh).
- [x] 314 assertions + 37 smoke checks, all green.

### Gotcha #4
Autoload singletons are NOT resolvable at compile time from a `--script` main
loop. `tests/smoke_run.gd` is a thin runner that `load()`s `smoke_impl.gd` at
runtime for exactly this reason.

- [x] Wired every upgrade effect into the systems that consume it (cameras
      create permanent institutional records, private rooms scale witness
      quality, retainer raises the investigation threshold, diagnostics bench
      de-noises vitals, coffee machine keeps nurses at the station, confidential
      waste contract normalises shredding).
- [x] Codex: learn-by-observation notes, unlocked after seeing an effect twice.
- [x] **Balance harness** (`tests/balance_sim.gd`) — three 16-day careers with
      asserted design intent. It found a design inversion nothing else could:
      with five beds, curing fast and refilling out-earned prolonging, so
      cheating paid LESS than honesty. Fixed with an admission cost + acuity
      escalation, so duration beats turnover. Also exposed that running a
      machine not indicated for a condition was completely invisible.
- [x] Sanction ladder now scales with heat past Probation, so a cleaned-up
      doctor gets room to recover but one at max heat does not.
- [x] Killed 155 spurious engine errors in the harness: nodes added during a
      SceneTree's `_initialize()` are NOT inside the tree, so every
      `global_position` read failed. Furniture now builds with local positions
      (order-independent), and the runner waits for a real frame.
- [x] README.

### Current numbers (seed 90210, 16 days)
| strategy | earned | ending | standing |
|---|---|---|---|
| honest   | $13,099 | Saint | Clean, rep 1.00, broke |
| careless | $12,301 | Struck off day 12 | heat 100% |
| careful  | $38,645 | Tycoon | Clean, rep 0.89 |

- [x] Investigators with bodies: they walk to each chart, nurse and machine in
      turn, so every step is interceptable. Covert ones still get no body.
- [x] Staff propositions: corrupt nurses name a price, loyal ones warn you,
      gossips tell you what's going around. Paying buys real silence and counts
      toward Medical Mafia; threatening backfires into fresh evidence.
- [x] Content: 19 conditions, 17 treatments, 14 complications, 19 random events.
      Added validation tests that walk ALL content and assert every condition has
      reachable treatments with real tools, every complication has real cause
      tags, and every machine treatment is indicated somewhere.
- [x] PA tannoy system — atmosphere that doubles as an institutional-mood signal.
- [x] Student-on-placement event (a witness with legs), agency nurse (owes you
      nothing), coffee machine failure (defeats the coffee upgrade), bed closure.
- [x] Remaining upgrade behaviours wired: service contract fixes AND reports
      miscalibration, ward clerk files your gaps but notices the pattern, second
      opinion policy puts a colleague through every extended stay.
- [x] 519 assertions, 37 smoke checks, 8 balance checks.

- [x] Tutorial: five objective beats through the legitimate job only. It never
      mentions the other thing — the player is taught what a good doctor does
      and handed a debt a good doctor cannot service.
- [x] Whistleblower is now an actual action (private terminal only), so all
      nine endings are reachable. Test walks every one and asserts it.
- [x] Second statistical signal: complication RATE, not just length of stay.
      Perfect paperwork is no defence against being an outlier. Two bugs found
      writing it — the denominator originally included still-admitted patients
      (diluting exactly the behaviour being measured) and it averaged per-shift
      ratios instead of summing the window (complications and discharges do not
      land on the same shifts, so a 3x ward looked average).
- [x] 549 assertions, 37 smoke checks, 12 balance checks.

### Balance, 30 days, seed 90210
| strategy | earned | comp/discharge | insurer | outcome |
|---|---|---|---|---|
| honest   | $21,249 | 0.17 | 0% | Clean, rep 1.00, still broke |
| careless | $22,496 | 10.00 | 99% | Struck off, day 16 |
| careful  | $89,537 | 0.38 | 26% | Tycoon, clean, 2 investigations survived |

The careful line is doing what the brief asked for without being scripted: it
cures a high volume of people quickly to keep the numbers clean, and hides a
small number of profitable outliers inside that volume.

- [x] Physical sabotage verbs: decanting between containers (labels stay put),
      and doorway obstruction that genuinely removes nav cells.
- [x] **Screenshot harness** (`./screenshots.sh`, Xvfb + GL Compatibility).
      Being able to look at the game found five bugs no test could:
      HUD labels wrapping one character per line; the money readout, toasts and
      control hints never drawing at all (zero-size root Control); patients
      standing bolt upright inside their beds; every debt missed on day one
      before the player had done anything; and an eviction failure path whose
      counter was never incremented, making the bankrupt-by-rent ending
      unreachable.
- [x] Career meta: endings unlock starting perks, persisted in user://meta.json.
      Nine perks, each shaped by the ending that grants it. Main menu shows
      careers finished, endings found, and perk selection.
- [x] 595 assertions, 37 smoke checks, 12 balance checks.

- [x] Proximity-scoped subtitles.
- [x] Small talk is no longer rolled (a confidence band on "how are you feeling?"
      was teaching players to distrust the band everywhere it matters).
- [x] **Three departments**, each adding a mechanic rather than a room:
      Emergency (mid-shift arrivals), Radiology (imaging = exact vitals, and a
      permanent record everything must agree with), Psychiatry (recovery driven
      by satisfaction/comfort, patients far more observant).
- [x] 663 assertions, 37 smoke checks, 12 balance checks.

- [x] Upgrade economy rescaled after the harness showed the whole catalogue
      being bought out inside 20 days; two late-game sinks added.
- [x] Thermostats (quiet environmental sabotage with a device log) and chart
      misfiling detection (carrying a chart away is now a real, recoverable
      middle ground between leaving it and shredding it).
- [x] CLAUDE.md with the eight engine gotchas and the load-bearing design rules.
- [x] 671 assertions, 37 smoke checks, 14 balance checks.

- [x] Device logs persisted (they are evidence — losing them on load made the
      sabotage free after any save).
- [x] Clinical impression is relative to expected progress, not absolute.
- [x] Ambient audio bed: a seamlessly looping room tone plus sparse positional
      noises placed away from the player, so "background" and "something just
      happened near me" stay distinguishable — which the whole distraction
      economy depends on.
- [x] 767 assertions, 40 smoke checks, 14 balance checks.

### All 21 requested systems are implemented and verified
architecture · player controller · interaction/physics · hospital environment ·
patients · treatment/recovery · NPC AI · NPC memory/suspicion · dialogue ·
economy · shift/day loop · procedural generation · investigations · reputation ·
progression/upgrades · random events · save/load · UI · audio · tutorial ·
multiple endings.

- [x] Audited for dead mechanics (things set/serialised and never read). Wired
      up inspection warnings, arguing families, supply shortages and the social
      graph; deleted two exports with no readers.
- [x] Tablet Record tab (audit exposure at any moment, not just at clock-out).
- [x] The nurse errand option, which had rolled a dice and then done nothing.
- [x] Export presets for Linux / Windows / macOS.
- [x] Perception asserted against the real building in `live_run.gd`, and the
      freed-registry bug it turned out to be hiding (see CLOSED, below).
- [x] The west annexe: departments are now ROOMS, shuttered until bought.
- [x] Imaging has teeth and a counterplay: it writes the true cause into the
      record, colleagues can order it, and the aperture is how you ruin a scan.
- [x] The Intake trolleys are real beds, so a full ward overflows onto them.

---

## STATE OF THE PROJECT

**Everything the brief asked for is implemented and verified.** All 21 numbered
systems, the vertical slice, the emergent-story machinery, and three departments
beyond it.

```
883 assertions   (test functions across 5 suites)
 49 smoke checks (boots the real scene, plays a full shift, save/load round trip)
 13 live checks  (7000 fixed-timestep frames of real NPC AI, pathing and doors)
 14 balance checks (three 16/30-day careers asserting the design intent holds)
 25 screenshots  (every room and every UI screen, rendered offscreen)
```

Balance at 30 days, seed 90210:

| strategy | earned | comp/discharge | insurer | outcome |
|---|---|---|---|---|
| honest   | $20,716 | 0.07 | 0% | Saint. Perfect standing, still broke. |
| careless | $14,385 | 5.00 | 97% | Prison, day 13. |
| careful  | $178,126 | 0.43 | 21% | Tycoon. Clean, two investigations survived. |

### Verification layers, and what each has actually caught
| Layer | Found |
|---|---|
| unit/integration | stay maths, chart auditing, evidence decay, floor connectivity |
| `smoke_run.gd` | spawns silently dropped; a Vector3 passed where a Mesh was expected |
| `live_run.gd` | **every door in the building was welded shut** — no member of staff could enter any patient room; **one departed visitor switched off witnessing for the rest of the shift**; NPCs could not push anything; navigation ignored furniture; nurses abandoned their rounds |
| `balance_sim.gd` | cheating originally paid LESS than honesty; wrong-machine use was invisible; the whole upgrade catalogue bought out by day 20 |
| `screenshots.sh` | HUD wrapping per-character; three HUD blocks never drawing; patients standing in beds; day-one economy; a confidence band on "how are you feeling?" |

### CLOSED — the perception check, and the bug it was hiding
The open item from the previous session was real, and it was not the test.

`live_run.gd` now asserts perception against the actual geometry of the
building, in three checks. A nurse is stood in the corridor with the Room 101
wall between her and a blatant act 4.0m away, then moved into the ward 3.5m from
the same act. The two halves are at deliberately comparable range so the wall is
the only meaningful difference — standing the blocked witness across the
building would have passed for the wrong reason. Observance is forced to 1.0 and
the act made maximally blatant so the assertion is about routing rather than a
dice roll; `notice_chance()` has its own unit tests.

Why it read zero before: **reading a freed object into a typed local aborts the
function.** `_on_world_event` did `var body: NPCBody = _bodies[id]`, and that
statement raises "Trying to assign invalid previously freed instance" rather
than yielding null — so the `is_instance_valid()` guard written on the very next
line never ran, and the loop died. Visitors go home, investigators finish their
round and patients are discharged; each frees its own body and left a corpse in
the registry. From the first departure onwards, **no character in the building
witnessed anything the player did for the rest of the shift.** The stealth game
turned itself off partway through every session, and because the engine only
logged a script error, nothing failed.

Fixed at the source and at the point of use: `SuspicionSystem.register()` now
hooks `tree_exiting` and drops the body (keeping the MIND — somebody who saw you
and then went home still saw you), and every read of either registry goes
through one guarded accessor, `SuspicionSystem._body()` / `PatientSystem
.get_body()`, which sweeps stale entries as it passes. `PatientSystem` had the
same latent bug: one discharged patient could abort `tick()` before it advanced
anybody else. Regression test:
`test_a_departed_npc_does_not_switch_off_everyone_elses_senses`, which plants a
stale entry ahead of a live witness on purpose. Engine gotcha #11 in CLAUDE.md.

### The west annexe — departments are rooms now
Departments used to be pure capability unlocks: you paid £28,000 and a checkbox
somewhere started letting emergency patients spawn. Nothing about the building
changed, so the most expensive things in the game were the least visible.

The floor now runs from x = -16 instead of x = 0, and the three departments are
real rooms off the west end of the corridor: **Emergency Intake** (triage desk,
three trolleys, ambulance bay), **Radiology** (a gantry with a bore, a couch, the
imaging bench, and a control booth you can stand behind), and the **Psych Day
Room** (armchairs in a circle, a television nobody chose, a jigsaw missing a
piece). They are built, lit and furnished from the first shift and sealed behind
roller shutters — `RollerShutter` blocks movement, blocks line of sight, and cuts
its doorway out of the navigation graph, so nothing paths into a department the
hospital has not bought. Buying one rolls the shutter up in place; no rebuild.

Wanting a room you can already see beats wanting a line in a shop. It also means
the corridor is a running score: how much of the west end is still shut says
where the career is, every time you walk past.

Three things fell out of it that were not in the plan and are better than what
was:
- **Emergency arrivals now happen in Intake**, at the opposite end of the floor
  from the wards, and they are loud enough that everybody hears. The department
  pays twice — once in day rate, and once in the quiet minute it buys you in
  Room 105 while the staff are all at the other end of the building.
- **Psych patients leave their beds for the day room** and sit there a long
  while. Recovery is scored against the comfort of the room a patient is
  ACTUALLY in, so a cold, dark day room slows down every psych admission on the
  floor at once, from a thermostat nobody associates with any of them.
- **Staff patrol the annexe once it opens**, filtered live rather than at spawn.
  Buying a department means more of the building is walked through, and
  therefore more of it is watched.

### Imaging: the one document you did not write
The annexe left Radiology as a room containing a button that was purely good for
the player — exact vitals for a day, no downside worth the walk. It is now the
sharpest thing in the game.

`PatientChart.imaging_findings` records the TRUE cause of every active
complication at the moment of the scan, and the audit raises
`contradicts_imaging` against any of them whose filed cause disagrees. A clean,
plausibly documented complication — the thing careful play is built on — passes
every audit until somebody points a scanner at it. And the player is not the
only person who can: a colleague reading an overdue chart will ask for imaging,
the request shows on the tablet, and ignoring it costs you at clock-out with the
one person who asked. There is nothing in the record to explain, because none of
it is in the record.

The counterplay is the aperture, which is why the machine had to be fixed first:
prescribed values were only ever set for machines standing in the patient's own
ward, so both the treatment bay and Radiology showed a by-the-book setting
belonging to nobody present. `_nearby_patient` now sets it from whoever has been
wheeled in. Two notches off and the scan degrades to artefact — no record, the
request satisfied on paper, and one line in a device log at the far end of the
building.

### Trolleys: what a full ward actually feels like
`waiting` was an `Array[Patient]` and nothing else. When every bed was full an
admission joined it, invisibly, and popped into the next bed that came free. The
pressure the ward is built around — five beds, and the whole economy resting on
that number — was never once visible on the floor.

The three Intake trolleys are now real `PatientBed` nodes. A full ward overflows
onto one: the patient is admitted, is billing, and is lying in the busiest room
in the building where everybody walks past. Trolley time costs goodwill about
four times as fast as merely being kept too long, and discharging a ward patient
moves whoever has been parked longest into the freed bed. So "the ward is full
and somebody just arrived" is a decision with two bad halves — send a
still-profitable overstayer home early, or let the new arrival lie there losing
you the reputation that brings better-insured patients in.

Two smaller fixes fell out of it: `_bed_in()` returned the first bed matching a
room, which was fine when every room had exactly one, and Intake has three; and
patients are now moved between rooms by rebinding the existing body rather than
freeing it and spawning another, because the body carries its suspicion-system
registration and its own tree hooks.

### NEXT UP
- Human playtest for feel: movement speed, shift length, prompt clarity.
- Open door leaves are not in the nav graph, so staff bump them and rely on
  stuck-recovery. Works, but could be modelled properly.
- `Patient.room` does not follow the body when a bed is wheeled, so deliberately
  parking a ward patient in Intake to free their bed does not yet register.
  That is the natural next mechanic and the last piece of the trolley system.
