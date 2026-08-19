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
1526 assertions  (test functions across 9 suites)
 80 smoke checks (boots the real scene, plays a full shift, save/load round trip)
 13 live checks  (7000 fixed-timestep frames of real NPC AI, pathing and doors)
 15 balance checks (three 16/30-day careers asserting the design intent holds)
 31 screenshots  (every room and every UI screen, rendered offscreen)
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

And because beds are rigid bodies on wheels, `_reconcile_room` now reads a
patient's room from where their bed actually stands rather than from where they
were admitted. Ramping is therefore a thing the player can do on purpose: wheel
a ward patient out to Intake and they keep billing, recover slower, lose
goodwill four times as fast, and their room frees up for somebody better
insured. It takes two trips, because a ward with no bed in it does not count as
a vacancy either — which is about the right amount of effort for what it buys.
Their chart stays where it was, and a chart in the wrong room is already its own
finding. And the act is witnessed like any other: `patient_moved_to_corridor`
carries the player as its actor at visual weight 0.45, and whether it is
defensible is decided by the floor rather than by the player — a genuinely full
ward grants the `bed_shortage` cover, a half-empty one grants nothing. And
leaving them there keeps costing: `corridor_minutes` accumulates while a patient
is parked, and past four hours any nurse whose round reaches them records it, at
a weight that grows with the hours.

Two smaller fixes fell out of it: `_bed_in()` returned the first bed matching a
room, which was fine when every room had exactly one, and Intake has three; and
patients are now moved between rooms by rebinding the existing body rather than
freeing it and spawning another, because the body carries its suspicion-system
registration and its own tree hooks.

### Being bad at the job is a failure state again
`Patient.satisfaction` carried a comment saying low satisfaction produces
complaints with zero suspicion, and it did not. Satisfaction fed one reputation
track that fed one ending condition. Keeping somebody miserable was free.

Below 0.18 a patient now files a formal complaint about their CARE, at a
severity that scales with how unhappy they are. That is heat, and heat is what
brings people to look at you — so a perfectly documented, entirely deniable
career that simply treats people badly still ends up under investigation. It is
also what stops trolley-parking being a free strategy, since corridor time
drains satisfaction four times faster than an ordinary overstay.

The balance run says it landed about right: honest play still finishes with no
complaints and no heat, careful play now picks up one complaint and 11% heat
where it used to run completely clean, and careless play takes seven. All
fourteen design-intent assertions still hold.

### Content pass, and a test that dead content cannot hide
Eight new conditions (four ward, two psych, one emergency, one radiology), four
new treatments and six new complications — 34 conditions, 22 treatments, 20
complications. Everything is still data in `DB.gd`; not one system changed to
accept any of it, which was the point of building it that way.

What did change is that the three places a complication can COME FROM were
match statements, so a complication could sit in the catalogue forever with no
path to it and look exactly like content. They are now
`TreatmentMachine.COMPLICATION_POOLS`,
`TreatmentSystem.WRONG_TREATMENT_COMPLICATIONS` and
`PatientSystem.ENVIRONMENTAL_COMPLICATIONS`, and a test adds all of them up
against `DB.COMPLICATIONS` in both directions: nothing in the catalogue is
unreachable, and nothing points at a complication that does not exist.

Filling that map out properly also fixed a real dullness — every wrong
treatment that was not one of six special cases produced Ambient Dread. A
complication is meant to be a clue you can follow backwards to what was done,
and two thirds of them all said the same thing.

---

## Session 2 — the shift loop

The brief changed shape: pick a shift, work a list of booked patients, make
money being a bad doctor, and see how far you get before somebody stops you.
Six stages, each tested and committed separately.

**Shifts.** Three of them, and the choice is witnesses against attribution
rather than safe against risky. Two of the three touch midnight, which broke the
clock — anything comparing `minute_of_day` against an end hour is wrong for one
of them, so `minutes_into_shift()` counts forward from the start the long way
round. Staffing is a fixed rota so "she's on nights" is worth knowing; the
roster went from three to eight and off-duty staff leave the building without
losing a single memory.

**Injuries.** Six of them, each existing twice — in CONDITIONS as what somebody
arrives with, in COMPLICATIONS as what they leave with, reading identically on
purpose. Patients carry a presenting complaint frozen at admission, and every
complication records whether it happened here, on which shift, and how many
people were in the building. The chart audit reads the gap: one unexplained
injury is a finding, two is a paragraph that names what they came in with.

**The examination.** Reuses the machine grammar exactly: a site, APPLIED
PRESSURE, an indicated value, silence about everything above it. The honest
setting had to be genuinely worth using or the dial would read as a crime
button, so it sharpens your read on the patient and clears a booked slot.

**The list.** A shift used to be eight open-ended hours. It is now four kinds of
booked work, and a walk-in who costs nothing until you find a reason to admit
them. Missing a slot costs you with the person who was sitting there.

**Theatre and pharmacy.** Surgery is three stages of properly/quickly/badly,
recorded in the words a theatre record actually uses, and it is the most
deniable way in the game to hurt somebody because operations genuinely go wrong.
The pharmacy is the quietest verb: the wrong take-home brings them back in a
week at a fresh daily rate with an honest explanation, and they come back
noticing more and trusting less.

**Attribution and the score.** A nurse on rounds does arithmetic from two
injuries upward, with certainty scaled by how many people could have done it and
no cover tag, because there is no cover story for arithmetic. The game-over
screen leads with what you took out of the place and what stopped you, and the
best haul persists between careers.

Two economic corrections fell out of balancing it. Consultations and operations
now carry their own overhead — beds have to stay the business model, and a
clinic that paid for itself would have inverted the premise a second time. And
the insurer now watches ward-acquired injuries per patient-SHIFT, because the
complication rate divides by discharges and goes blind on a ward that never lets
anybody leave.

Balance at 16 days, seed 90210: honest £1,196 and clean; careless £11,828 and
struck off with 44 ward injuries; careful £19,968 and clean with 5.

### Session 3 — making the loop legible, and the bug that found
The shift loop worked and was almost invisible. The booked list existed as one
line in the morning briefing and a single objective string, which is not enough
to plan a shift around — and planning the shift is the entire point of having
one. The tablet has a **List** tab now: every slot, who it is, where they
actually are, how late you are, how many injuries they have picked up here, and
what the fees have come to so far.

Photographing it immediately found a real bug. Slots in the FUTURE were reading
as "23h late", because lateness compared raw hours-of-day and wrapped negatives
by adding 24 — a rule written for the shift that crosses midnight, applied to
every slot that simply had not come round yet. The same arithmetic drives
`_expire_past`, so **the list was marking itself entirely unseen at the first
hour tick**, before the player had walked anywhere, quietly bleeding patient
satisfaction and insurer trust every single day. Counting inside the shift is
the only version that is right for both cases. Four tests now pin it, including
one on the shift that wraps.

**Codex entries for the new verbs.** The game teaches by letting you do a thing
twice and then writing down what your character reckons is going on. The
examination dial, improvised theatre, the take-home loop, the arithmetic a nurse
does, and the night-shift trade all have entries now — without them the pressure
dial was a scale with no feedback and the discovery loop did not close.

**Serious Incident Review.** Ward-acquired injuries had no detection pathway of
their own; they went through heat, and heat is manageable — behave for two
shifts and it comes down. A patient enough player could run a ward full of
broken people indefinitely by being pleasant in between. The review opens off
the injury RATE instead, is harder to survive than a utilisation review, and
pulls the patient things keep happening to rather than the one who has been here
longest — which is very rarely the same person. It is deliberately not an early
return: it is pressure on top of whatever heat was already bringing, because
crowding out a malpractice enquiry by breaking more legs is exactly the wrong
incentive, and that is what happened the first time it was wired up.

**Endings that know what the career was about.** The evaluator read forged
entries, cures, complications and money, and nothing else — so a run defined
entirely by ward injuries came out as Fraud King. Three endings read the new
shape: **The Butcher of Ward C** (everyone left with something they did not
arrive with), **A Recognised Risk** (every one of them went wrong in theatre and
every one is a known complication, and the theatre record agrees with you
throughout), and **Revolving Door** (never hurt a soul, just kept sending them
home on the wrong thing). All three sit below Legendary on purpose: managing
fifteen ward injuries AND an immaculate reputation deserves the better joke.

Each unlocks a perk that changes the RECORD rather than the world, which is the
right shape for this game — Calibrated Hands gets the outcome of leaning hard
from somebody who did not look like they were, The Phrase files its own cause
for theatre complications, and Somebody In Dispensing means the pharmacy record
has quietly stopped being an independent document. And the reachability test now
asserts every ending in the catalogue has a case proving something produces it,
because all three of these nearly shipped unreachable.

**The clinic board.** The list existed on a tablet, which meant it existed in a
menu. It is now also a whiteboard on the corridor wall by the treatment bay —
five names, times, and what each one is for, ticked off as you go. Reading
somebody's name off a wall on your way past is a different thing from opening a
tablet, and a slot nobody attended keeps their name on it all day in front of
everybody who walks by.

It shipped reading "nothing booked" first time. The board is built with the
building, which happens before the systems that fill it in exist, so connecting
to `roster_changed` on the same frame silently found nothing — the screenshot
pass caught it inside a minute. Deferred connect.

**What you make of them.** The brief asked for ratings attributed to each
person, and the game had them — observance, escalation, whether they are still
counting the days — entirely invisible behind an archetype name. Every patient
now carries a short read in your character's words: *"Watches everything. Asked
what the dial was for."*, *"The sort who asks for it in writing."*, *"Has not
looked up once."*

Two rules make it work. It is never advice — there is a test that walks every
archetype and asserts no line contains "safe", "risky", "witness" or "avoid",
because the moment one does the game is labelling people as safe to hurt, which
is the one thing it does not do. And it is a GUESS until you have examined them:
each patient carries a fixed per-person error in your read, stored rather than
rolled so it does not flicker while you stand there, and the notes say so out
loud. That is the quiet argument for the honest examination — it is the only way
to find out whose account of the afternoon anybody would believe.

**The tutorial covers the shift loop now** — the list first, then going to see
whoever is on it, then the examination — and a test asserts it still never
mentions suspicion, witnesses, money or getting caught. It teaches the
legitimate job and hands you a debt schedule that job cannot service.

**Walk-ins sit down.** Five chairs along the west wall of the treatment bay,
one arrival to a chair, so how many people are still waiting is answerable by
looking rather than by opening a menu.

**Wrong-site surgery.** Every operation now has an indicated site — the injury
they have, or the part their condition is about — stated on the theatre screen
and then not enforced, exactly like a machine's prescribed value. Opening
somewhere else does not help, near-guarantees a complication, is visible
whatever approach you took, and writes both the site you opened and the site you
were meant to into a record that is not yours. It audits at 0.95, the heaviest
single finding in the game, and there is no cover story for it.

The balance harness had to be told to operate on the indicated site. It had been
opening every patient's knee regardless, which turned every operation in every
career into a wrong-site procedure overnight — a good reminder that the harness
is a player too, and a bad one measures the wrong game.

**Sound for the three new verbs**, because they were all sharing a beep. A snap
for something giving way under your hands, a wet drag for theatre, a rattle for
a bottle of pills going into somebody's bag. The snap matters most: nothing on
the examination screen says what has just happened until you read the finding,
so the sound is the tell.

**And the save now proves it keeps the shift loop.** Fifteen new smoke checks
walk a full round trip over everything the last two sessions added, because most
of it is state that fails silently — a lost `admitted` flag turns every walk-in
into an inpatient on load, and a lost theatre record deletes the one document in
the game the player cannot write. What they arrived with, your read on them and
its bias, trolley time, the theatre record including which site was indicated,
the pharmacy record, and the injury with its true cause, its acquired-here flag
and its staffing count all survive.

**The clock-out review reads the new shape.** Injuries sustained on the ward get
their own block above the findings, listing what each patient came in with and
what has happened to them since, with the filed mechanism beside each one or
"no mechanism recorded". Deliberately separate from the undocumented-complication
list: filing a cause closes the individual gap and does nothing at all about the
fact that this is the third thing to happen to the same person, and the screen
should not imply otherwise by folding them together.

---

## Session 4 — "stop building it like a systems demo"

New brief: the systems are done and green; the job now is FUN, CLARITY, FEEL,
TENSION, COMEDY, EMERGENCE — then content, polish and shipping. Ordering is the
brief's, and it is the right one.

**Branch renamed** `claude/github-repo-deletion-3hf0gq` -> `claude/chronic-care`.
The old remote branch could not be deleted from this container (the git proxy
refuses the delete refspec); it is stale and safe to remove from the GitHub UI.

### The play harness — because "green" and "good" are different claims
`tests/play_run.gd` + `tests/play_impl.gd` + `./play.sh <plan>`.

Everything before this session verified that the systems WORK. Nothing verified
that the game is nice to be inside. This harness drives the real player
controller through the real input actions — `Input.action_press("move_forward")`,
real acceleration, real collision, real doors — over real frames at a fixed
60fps, and writes down how long everything took in seconds a human would
actually sit through. It screenshots as it goes and dumps, at each beat, what
the SCREEN says rather than what the simulation knows. The gap between those two
is the thing this session is about.

Plans: `walk_test` (movement feel and how far everything is), `first_shift`
(what a stranger sees in their first two minutes), `honest` (is there enough to
do if you behave).

Note for future sessions: under Xvfb + llvmpipe the harness runs far slower than
real time, but `--fixed-fps 60` means the SIMULATION still advances 1/60s per
frame, so every duration it reports is the duration a player would experience.

### THE GAME WAS UNPLAYABLE FROM THE MAIN MENU

Found within the first hour of actually looking. Pressing **New Career** put you
in a hospital where the clock never started.

`game._start()` calls `shift.begin_day()`, which ends by emitting
`briefing_ready` — `ui_root` opens the morning brief. The very next line emits
`request_ui("tutorial")`, and `ui_root.open()` begins with
`if current != null: close()`. So the brief was destroyed before a frame was
drawn. The tutorial's own button said **"Clock in"** and did not clock anybody
in: it set a flag and closed. `grep -rn clock_in scripts/` returns exactly one
shipping caller — the button on the briefing that had just been thrown away.

The result: PRE_SHIFT forever. `clock_running` false, clock frozen at 8:00 AM,
no hour ticks, no appointments arriving, no tutorial steps (they are gated on
`shift_started`), and no input anywhere that could start or end the day.

**Every harness sets `tutorial_done` before booting** (`live_impl.gd:39`,
`shot_impl.gd:188`, and my own play harness calls `clock_in()` directly), so not
one of 1526 assertions had ever walked the route a stranger has to take.

Fixed: the tutorial hands off to the brief instead of replacing it, and the
brief's Clock in button remains the single thing that starts a day. Also fixed
the second half of the same bug — `clock_in()` emitted `shift_started` (tutorial
writes step 1 to the objective line) and then overwrote it two lines later with
"Get through the shift.", so the only instruction a new player ever got was
destroyed in the same frame.

Guarded by `smoke_impl._check_first_run()`, which boots with no flags set, finds
the buttons by their labels and presses them the way a person does, then asserts
the shift is actually running. That test is the real deliverable here.

### You could not walk down your own corridor

The second thing the play harness found, and it needed no code reading at all:
a scripted walk from one end of the building to the other **timed out at 60
seconds**, wedged on a wet floor sign at x=20. Sprinting worked. Walking did not.

`Player._handle_movement` scaled its shove impulse by `velocity.length()` AFTER
`move_and_slide()` — and `move_and_slide` zeroes velocity along the axis you are
blocked on. So the instant a prop actually stopped you, you could no longer push
it: you were stuck against it precisely because it was in your way. Sprinting
escaped only because it left enough residual speed to generate an impulse.

This is the identical bug `NPCBody` was fixed for in session 1 and the player
never was. Now scaled by `_intended_speed` — how hard you are asking to move,
captured before collision resolution — through a pure `Player.shove_impulse()`
so the rule can be asserted without waiting on a physics frame.

Measured, before and after, same route, same seed:

| leg | before | after |
|---|---|---|
| corridor west→east, 58m, walking | 59.9s (timed out) | **16.8s** |
| Room 101 → treatment bay | 20.4s | **8.4s** |
| corridor east→west, sprinting | 10.2s | 15.5s* |

\* the sprint leg is slower afterwards only because the props are no longer
where the previous wedged run left them.

### You could not pick up a syringe

Third blocker, same first ten minutes. `SupplyShelf.use_seconds()` returned 0.6
whenever the shelf had more than one item — which is every shelf in the building
— so the interactor's tap branch (`hold_time <= 0.0`) was unreachable. The only
surviving route was the hold-completion call, which fires while E is still
physically down, and `interact()` read `Input.is_action_pressed("interact")` and
cycled the index instead of dispensing. **`_dispense()` was dead code on every
shelf.** No treatment tool could be obtained by any input, so no patient could be
treated by hand, and tutorial step five sends you to the supply room to try.

Now: tap takes, Shift+E cycles, neither is a hold. Guarded in smoke.

### The crime happened inside a paused text box

The single biggest FEEL problem, and the heart of the brief. `ui_root` ran the
treatment INSIDE a screen builder — and `open()` calls `get_tree().paused = true`
before the builder runs. So the entire premise of the game, turning a dial past
its prescribed value and seeing what happens to a person, arrived as a 480x340
dim panel printing one of four flavour lines over a frozen world. The patient's
`say()` and `startle()` fired into a paused tree behind a modal. The same was
true of every hand treatment.

Both now resolve in the world, unpaused:
- the machine sounds, loudly and differently when the dial is off (`machine_bad`
  at −3 dB from three notches out)
- the patient gasps where they are lying, and an injury adds the snap
- a toast names what you just did and at what setting
- whoever is standing in the doorway is present for all of it

**Being seen now registers the first time.** `_react` was gated on the tier
ladder, which needs ~0.28 of accumulated evidence, and a one-notch deviation is
worth 0.05 — so for the first several shifts you could be watched committing the
premise and the world would not move. There is now a NOTICE beat below the
ladder: any evidence over 0.1 makes that person turn and look at you, sometimes
mutter, throttled to once per 20 in-game minutes each.

**Sabotage is visible.** `Build.ceiling_light()` puts an unshaded emissive panel
beside the lamp, and `Room.set_lights()` only hid the `OmniLight3D` — so turning
a ward's lights off left every fitting glowing at full brightness. Ambient was
0.55, which lit the room anyway. Now the whole fitting hides and ambient is 0.28.

### Money you can see moving

`EventBus.transaction` was emitted from both halves of `GameState` and connected
to **nothing**. Five debts totalling $695/day drained the starting $820 in
silence before the player had read either number, and their own balance then sat
still for twelve real minutes. The thing the entire game is about — money
arriving because somebody stayed another night — was never visible arriving.

There is now a ticker under the money readout: every transaction, as it happens,
with a sound. And `bonus_rate` (0.08) had never been rendered by any screen, so
"keeping them pays ME" was something the design knew and the player could not
find out. `Patient.your_cut_per_day()` is now on the tablet ward row, and the
discharge screen leads with the arithmetic the brief asked for:

> Send them home today — your bonus is settled at $0
> Every further night — hospital $1,335 · you $107

Stated flatly, never labelled, and the player can do what they like with it.

### NEXT UP
- Human playtest for feel: movement speed, shift length, prompt clarity.
- Open door leaves are not in the nav graph, so staff bump them and rely on
  stuck-recovery. Works, but could be modelled properly.
- A nurse walking past a ward with no bed in it still has no opinion about the
  empty room itself, only about the patient who ended up in the corridor.
- Nothing yet lets you argue with a wrong-site finding, which is correct, but it
  does mean one misclick is a career. Worth watching in a playtest.

---

## Session 4 (cont.) — the first ten minutes, and being able to walk

Audit items #5 and #6 from the top-10 list, plus three things the play harness
found on the way. Everything below was verified by driving the real controller
through the real input actions, not by reading code.

### #5 — nobody was ever ready to go home

Day one opened on five people admitted forty seconds ago. Nobody was finished,
nobody was waiting on anything, and the question the entire game turns on —
*does this person go home today?* — could not be asked for another three in-game
days. The realisation the game is built around arrived somewhere in the middle
of day four, by which point the player had already decided what kind of game
this was.

Now the night doctor hands over a ward (`ShiftSystem.OPENING_WARD`,
`_seed_opening_ward`):

| | condition | state | knows their date | worth |
|---|---|---|---|---|
| Room 101 | Mild Gravitational Confusion | **medically fit to go home** | no | $1,840/night, your cut $147 |
| Room 102 | Chronic Beige | **fit, and four days over** | yes, and counting | $969/night, your cut $78 |
| Room 103 | Excessive Spleen Torque | halfway | yes | $1,490/night |

Two more arrive that morning to fill the ward. The 9am slot on day one is now
*always* a discharge (the only appointment in the game that is chosen rather
than rolled), the 10am slot is the other one. So the first two hours of a career
are the game's question asked twice, with the two different answers built in:
one person who will notice, one who will not.

Nothing anywhere says "keep her". What it says, on the person, when you look at
her, is:

> **Talk to Ines Bracket**
> Mild Gravitational Confusion · fit to go home · $1,840 a night

Supporting changes:
- `Dialogue.READY_LINES` + a bark that fires *before* the overdue one and
  regardless of whether they are counting. "I packed. Probably shouldn't have
  packed."
- The briefing leads with a HANDOVER block: who is in which room, how many
  nights, what the bed earns, what your share is, and flatly whether they are
  fit for discharge.
- `Patient.your_cut_per_day()` surfaced on the bedside prompt, the briefing and
  the tablet.
- `PatientSystem.generate()` no longer produces two Kowalczyks in adjacent
  rooms — in a game whose whole risk model is *whose chart says what*, a
  duplicated surname reads as a bug in the tablet.
- Random events no longer fire on day one. A mass-casualty event was taking all
  three handover beds before the handover ran, so on exactly the seeds where the
  first shift most needed authoring, it silently had none.

### #6 — no deadline, and a first appointment that could not arrive

Three separate faults in one system:

1. `build_for_shift` put the first slot at the hour the shift starts. Hour ticks
   only fire on the hour *after* that, so `_on_hour` never marked it arrived, no
   walk-in ever materialised for it — and three hours later `_expire_past`
   marked it a no-show and docked reputation and patient satisfaction. Every
   shift, every seed, for a slot the player was given no opportunity to attend.
2. Arrival matched the slot hour *exactly*, so anything missed for any other
   reason could never arrive either. Now `arrive_due()` brings in everybody
   whose slot has come round, and it is called at clock-in as well as on the
   hour.
3. The list booked the same patient repeatedly — four discharges for one man in
   one day. `_booked` keeps it to distinct people.

The list now runs from an hour in to an hour before the end. The first hour is
the handover; the last is the one you need free for paperwork you would rather
nobody read closely.

And the deadline is now on screen, because everything the player is deciding is
a question about it:

```
Day 1
8:22 AM
7h 38m left · ends 4:00 PM        <- amber under an hour, red under thirty
Clean
```
```
   Discharge and take-home — Ines Bracket in 38m      <- live, its own line, so
                                                         the tutorial and the
                                                         objective line do not
                                                         fight over it
```

### Found by playing: you could not get past your own colleagues

Two `CharacterBody3D`s cannot displace each other — neither is affected by the
other's velocity and `move_and_slide` zeroes the blocked axis on both. A nurse
standing anywhere in a two-metre corridor was a wall. There are eight staff on a
sixty-two-metre floor and they walk the length of it all shift.

Measured: **11 seconds** lost to Nurse Nell in one corridor traverse, **21
seconds** to a wheelchair on the way into Room 101.

- `NPCBody.step_aside()` — sidesteps (not backs off; retreating along your line
  of travel keeps them in front of you the whole way), picks the side that is
  actually floor, and says something. "Yep. Yep. Going."
- `Player.shove_impulse()` rewritten. The old rule divided a constant by mass,
  producing 1.9 N·s against a twenty-kilo wheelchair — a tenth of a metre per
  second, i.e. nothing. Now it is momentum-shaped: you impart `PUSH_POWER`, but
  never more than the object would have if it were already moving as fast as you
  are. Light things scatter, heavy things grudgingly slide, nothing outruns you.

Corridor end to end: **28.4s → 11.9s**. Board to Room 101 bedside: **40s
(timeout) → 8.9s**.

### Found by playing: the bedside offered you a pole

Every bed has an IV stand beside it, standing squarely between the doorway-side
approach and the patient's head. Walking up to a patient and looking straight at
them reliably offered **"Pick up IV Stand"**. The most important interaction in
the game lost, every time, to a pole.

`Interactor._prefer_person` now splits the USE target from the GRAB target: [E]
reaches the person behind a loose prop, [LMB] still picks the prop up. Only
plain grabbables are overruled — a machine, chart, console or door keeps the
prompt, because reaching past a patient for the dial is the entire game.

I reverted this once, thinking the harness's aim was to blame, and the play run
put the pole straight back. Kept.

### Pacing

`TIME_SCALE` 0.666 → 0.444, so an eight-hour shift is **18 real minutes** rather
than 12. Twelve was not long enough to have a shape: by the time you had walked
the floor, read the ward and decided what today was, you were clocking out.

### The balance sim was a coin flip

One seed per strategy. A change that only reshuffled *which patients turned up
in which order* moved the careless career from $27k to $198k and flipped a
design check, without touching a single number in the economy.

`BALANCE_SEEDS` (default 3) now runs every strategy across several careers and
every design assertion reads a **mean**. It also reports **earnings per day**,
because totals quietly reward surviving — a strategy that makes a fortune and is
struck off in a fortnight reads as modest, which is exactly backwards.

Which immediately exposed the real problem, stable across all three seeds:

| | per day | survives | sanction | injuries/shift |
|---|---|---|---|---|
| honest | $952 | 20d | 0.0 | 0.000 |
| **careless** | **$8,379** | **18.3d** | 7.3 | 0.450 |
| careful | $2,778 | 20d | 0.0 | 0.109 |

Reckless butchery pays **three times more per day than careful play** and still
survives 18 days out of 20 at 93% heat with 528 witnessed acts. The game's
answer to "how should I do this?" is currently "badly, and quickly". That is the
next thing to fix.

### Harness

- `play_impl` now names what is physically blocking the player when it wedges,
  re-plans when stuck (as NPCs already did), pitches the camera as well as
  yawing it — bedside beats were aiming a metre over the patient's head — and
  reports the ward: who is ready, who is overdue, what each bed earns.
- Plans are built after the first frame, because several beats ask the hospital
  where a bed is and the hospital does not exist until the game has had a frame.

**1,534 assertions · 95 smoke · 13 live · balance across 3 seeds. All green.**

---

## Session 4 (cont.) — Phase 10: the economy had the wrong answer in it

The multi-seed balance sim asked the game "how should I do this?" and the game
said **"badly, and quickly."**

| | per day | survives | sanction | injuries/shift |
|---|---|---|---|---|
| honest | $952 | 20d | 0.0 | 0.000 |
| **careless** | **$8,379** | 18.3d | 7.3 | 0.450 |
| careful | $2,778 | 20d | 0.0 | 0.109 |

Three separate faults, each one a rule that was pointing the wrong way.

### 1. Complications were an uncapped linear bonus

`+0.26` per complication, forever. A patient with fifteen of them billed nearly
five times base. Nobody pays five times the daily rate for one man who keeps
falling over — they ask why he keeps falling over.

`Patient.COMPLICATION_STEPS` = `[0.26, 0.19, 0.12, 0.07, 0.04]`, then 0.015 each,
ceiling +0.78. The first complication is unchanged, so the careful player feels
nothing; the fifteenth is worth almost nothing, so the butcher's income
collapses. **The first complication is where the money is; the fifteenth is
where the prison is.**

### 2. Length of stay was measured against the projection, not the record

This was the important one, and it was backwards in a way that broke the whole
premise.

`average_overstay()` counted every day past `expected_stay_days`. So causing a
complication and *filing it correctly* made your length-of-stay figures worse.
The game punished the exact behaviour it is built to reward — and the balance
sim proved it: a **mild** strategy that hurts nobody, forges nothing and simply
takes its time with the discharge summary out-earned the sophisticated one.

Now `Patient.unexplained_overstay()`: days beyond what the *chart* justifies. A
documented complication accounts for the days it added. An undocumented one
accounts for nothing — which is precisely the risk of not filing, and precisely
why the sophisticated player files immediately.

### 3. Consequences arrived at a constant rate however loud you got

Two concurrent investigations, one opening per day, and a mercy throttle above
Probation that let a doctor with 448 witnessed acts keep his licence for
eighteen days.

- `concurrent_cap()` scales 2 → 4 with the ladder. Being under police
  investigation does not stop an insurer auditing you; it makes it likelier.
- Above two-thirds heat, a second envelope lands the same day.
- The mercy throttle is for somebody who is *recovering*. Sitting at the top of
  the heat scale for a fortnight is a pattern, not a bad week: above 85% heat
  it can take two rungs at once.

### And a fourth rung, because the brief asked for four and the sim had three

`MILD` — every treatment indicated, every setting correct, every chart true,
nobody hurt. The only thing this doctor does is fail to be in a hurry about the
paperwork on people whose insurance is good. "Comfortable" was an aspiration
nobody had measured.

### Where it landed (3 seeds × 30 days)

| | per day | survives | sanction | insurer | injuries/shift |
|---|---|---|---|---|---|
| honest | $1,029 | 30d | 0.0 | 0% | 0.000 |
| mild | $5,683 | 30d | 0.3 | 95% | 0.000 |
| careless | $2,656 | **13.7d** | 8.0 | 100% | 0.609 |
| careful | **$6,349** | 30d | 0.3 | 76% | 0.084 |

Honest is hard survival — $9,391 banked in thirty days against a $435,400 debt.
Mild is comfortable, and by day thirty the insurer is at 95% and adverse
findings have started, so it is not free forever. Reckless is genuinely rich per
day and is struck off in a fortnight on **every seed**. Sophisticated is the
best-paid thing in the game and carries real heat while doing it.

All twenty design-intent assertions pass across three seeds. The honest check
was also rewritten: "personal money under $N" needed retuning every time the
career length changed and stated nothing. It is now *an honest doctor cannot
make a living here* (under 35% of the sophisticated rate) and *never gets within
sight of the debt* (under 10% of $435,400) — both scale-free.

**1,548 assertions · 95 smoke · 13 live · 20/20 balance across 3 seeds.**
