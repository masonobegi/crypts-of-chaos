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

---

## Session 4 (cont.) — #7 the dial lied to you, #8 the distractions did nothing

### #7 — the most important control in the game

Two faults, both in `TreatmentMachine`.

**The prompt went stale.** `interact()` turned the dial and refreshed the 3D
label, but the interactor only pushes a HUD prompt when the thing you are
*looking at* changes. So the readout in front of you sat frozen on whatever it
said when you walked up: you were setting a number while being shown a
different one. It now re-emits on every click.

**The dial only turned one way.** `dial = DIAL_MIN if dial >= DIAL_MAX else
dial + 1`. The only route from 9 down to 4 ran 10, 11, 0, 1, 2, 3, 4 — seven
stops, five of them four or more off prescription, each one firing
`machine_extreme_dial` at everybody in the room. **Turning a dial down was the
most incriminating act in the building** and nothing in the interface said so.
`[Shift+E]` now turns it back, and the prompt says so.

**And it fired on every click.** Nobody in a real room reacts to a dial sweeping
past a number; they react to where it stops. Overshooting by one and correcting
published two extreme readings instead of none. The event now waits for the dial
to be still for 0.7s and reports the resting value once.

### #8 — nobody made a sound, and the distractions were never connected

**Footsteps.** The player made them. Nobody else in the building did. In a game
whose entire tension is *is somebody about to walk in*, every member of staff
moved in complete silence and the only way to know a nurse was behind you was to
already be looking at her. `NPCBody._footsteps` — positional, slightly quieter
than your own, gated to twenty metres so eight people walking a sixty-two-metre
floor do not churn the whole twenty-four-voice 3D pool.

**And then the real one.** `SuspicionSystem._on_world_event` opened with:

```gdscript
if e.actor != "player":
    return
```

Every world event not caused by the player was dropped before it reached a
single perception. Which means:

- `Prop._emit_noise` — emitted with no actor, deliberately, under a comment
  reading *"Noise is loud but INNOCENT... What it does is move NPCs, which is
  far more useful"* — **moved nobody, ever.** Throwing something to pull a nurse
  out of a ward is the single most important stealth affordance in the game and
  it had never once worked.
- The emergency admission that is documented as dragging every member of staff
  to the far end of the building: nothing.
- Every random event that clatters: nothing.

Four systems — the event, the hearing radius, the INVESTIGATE state, the walk —
and three of them working is worth exactly nothing. No test had ever run the
chain end to end.

Non-player events now go through `_broadcast_noise`: everybody in earshot is
distracted and gets their roll to come and look. No evidence is recorded,
because nothing about a clatter says who caused it.

Measured in `live_run`, before and after the same fix:

```
before:  noise: 0 of 4 staff in earshot came, closing up to 0.0m
after:   noise: 2 of 5 staff in earshot came, closing up to 13.3m
```

Somebody already watching you is still allowed to ignore a clatter — that is the
design, and it is why the assertion is "somebody comes", not "this person
comes".

Two new live checks cover the other half of the same layer: a heavy prop left in
a ward doorway genuinely cuts the room off the navigation graph, and clearing it
puts it back. That one already worked; now it cannot quietly stop.

**1,552 assertions · 95 smoke · 17 live.**

---

## Session 4 (cont.) — #9: the building now tells you who is behind each door

Sixty-two metres of identical doors. The room number was an 8cm plate flat
against the wall, unreadable past about four metres, and *who is in there* —
the only thing the player actually needs — was available only by walking in or
by opening a tablet they have to already suspect matters.

**Corridor flag signs.** Projecting into the corridor at right angles, the way
a real ward is signed, so the floor is legible from anywhere on it. Built as two
back-to-back single-sided labels: the first render used one double-sided
`Label3D` and it read `l0l` and `ǝʞɐʇnI ⅋ ʎqqo˥` walking the other way, which is
worse than no sign at all.

**A door card beside every ward door** (`scripts/world/door_card.gd`) carrying
the room number, the occupant's name, their condition, how many nights they have
been in, and a full-width status strip in a colour readable from the far end of
the ward:

```
┌──────────────────────────────┐
│ FIT FOR DISCHARGE            │  ← green
│ 101                          │
│ Tam Wollop                   │
│ Mild Gravitational Confusion │
│ night 4                      │
└──────────────────────────────┘
```

VACANT · UNDER TREATMENT · IMPROVING · FIT FOR DISCHARGE · PAST EXPECTED DATE.
Nothing on it is a judgement — it is exactly what a ward door card carries in a
real hospital. That "FIT FOR DISCHARGE" in green is also the most tempting
sentence in the game is the game's problem, not the card's.

The card polls its own room once a second rather than being pushed to, because
it has to react to recovery crossing a threshold, a complication, a transfer and
a discharge — four systems, none of which should have to know door cards exist.

### The landmine found on the way

The first render showed a card reading **FIT FOR DISCHARGE under a blue UNDER
TREATMENT strip**. `Build.mat()` returns a **shared instance from a colour-keyed
cache** — correct for a hospital assembled from primitives, and silently wrong
for anything that changes colour at runtime. All five cards were handed the same
`StandardMaterial3D`, so every strip turned whichever colour the last card to
refresh wanted, and writing to it would equally have repainted any other object
in the building built from the same grey.

`WardDoorCard._own_material()` duplicates the material on build. **Anything that
mutates a Build material at runtime must own it first** — worth sweeping the rest
of the codebase for.

Also added `03b_door_card` to the screenshot set, because this is precisely the
class of thing only a picture catches.

**1,553 assertions · 95 smoke · 17 live. All green.**

---

## Session 4 (cont.) — Phase 20: it exports, and the first thing it printed was an error

Export templates were never installed and no export had ever been run. Both
presets now build:

```
=== Windows ===
  81M  build/windows/ChronicCare.exe      PE32+ executable (GUI) x86-64
=== Linux ===
  64M  build/linux/ChronicCare.x86_64
=== running the exported build ===
  ok: the exported build boots and exits cleanly
EXPORT OK
```

`export.sh` does all three steps, because "an export produced a file" and "an
export produced a game" are different claims. Templates are a separate ~1GB
download and are deliberately not vendored; the script prints the one command
that fetches them.

The only outstanding warning is `rcedit`, the Windows-only tool that stamps the
icon and version block onto the .exe. Absent it, the exe carries no icon. That is
cosmetic and cannot be done from this container, so it is reported and not
treated as a failure.

### What running the real entry point immediately found

```
[INFO][Boot] Chronic Care booting
ERROR: Parent node is busy adding/removing children, `remove_child()` can't be
       called at this time.
```

`Boot._ready()` called `change_scene_to_file` synchronously from inside its own
`_ready()`, while the tree was still adding that node's children. **The first
line of output the shipped build produced was an engine error**, on every single
launch. Deferred now.

Nothing in 1,553 assertions had ever seen it, for the same reason the
"unplayable from the main menu" bug survived: **every harness instantiates
`Game.tscn` directly and skips Boot and the main menu entirely.**

So there is now a `boot_check.sh`, wired into `run_tests.sh`: it launches the
real main scene rendered under Xvfb for 300 frames and fails on anything printed
that a shipped build should not print. It filters exactly three kinds of
container noise — no sound card, no vsync under Xvfb, software GL — and nothing
else. Verified against the bug it was written for: reverting the one-line fix
makes it fail with the exact error above.

**1,553 assertions · 95 smoke · 17 live · boot check · 20/20 balance.**

---

## Session 4 (cont.) — no door in this game had ever closed anything

Phase 1 of the brief is "play the actual game" as five playstyles. I taught the
play harness to commit crimes — turn a dial by pressing E over and over, hold
the run button, pick things up, throw them — and played Reckless, Careful
Criminal, Opportunist and Idiot Chaos. Two of the four spent forty-five and
sixty seconds standing at a door.

Pulling that thread found five separate defects, ending in one that had been
sitting under the whole stealth game since the doors were written.

### 1. Nav routes cut corners at doorways

`NavGrid._smooth` dropped every waypoint on a straight run — including long
diagonals. A grid diagonal is walkable cell to cell, but a body has a radius,
so twelve collapsed diagonal cells become one straight line that shaves a
doorframe. NPCs survived it because `_check_stuck` re-plans; the player does
not re-plan.

Diagonals are no longer collapsed, and every doorway is registered as a **pinch
point** whose waypoints are never dropped, so a route is steered *through* a
1.4m gap rather than past it.

### 2. A door being held open slammed against its own stop, forever

`open_for` was called every physics frame while a body was in contact, and each
call re-set `angular_velocity` to full speed. The leaf hit its stop, bounced,
was re-driven at full speed on the next frame, and spent the whole time sweeping
back and forth **through the person holding it** — who is then batted around by
a kinematic body they cannot push. A door that would not stop opening, not a
door that would not open.

Doors now know they are being leaned on (`_held`) and rest against the stop.

### 3. The swing direction was measured from the hinge

`open_for` asked which side of the door plane you were on, measuring from
`global_position` — which is the **hinge**, at one edge of the doorway. Somebody
entering near that edge has an offset almost parallel to the closed leaf, the
dot product lands either side of zero by rounding, and the fallback swung the
door whichever way the code preferred: frequently straight into them. Now
measured from the middle of the opening, with a 0.9s latch so the leaf does not
reverse into you the instant you cross the threshold — and *only* 0.9s, so
somebody pinned behind an open leaf can still push it off themselves.

### 4. The player waited for body contact; NPCs have probed ahead for years

`NPCBody._open_door_ahead` has existed since doors became script-driven. The
player had nothing equivalent and opened doors by walking into them, which means
the leaf is always sweeping through you as it opens. `Player._open_door_ahead`
now probes 1.6m along the direction you are *trying* to move (not the way you
are facing, so strafing through a doorway works).

And both versions had `and not door.is_open()`, which hands the door back to its
own closer at about twenty degrees: it eases shut, the probe fires again, and it
oscillates in the gap forever. Removed from both.

### 5. And then: every door leaf was rotated ninety degrees

```
ward_101   hinge=(3.8,4.0) rot=0.0deg   leaf spans x 3.76..3.84  z 4.00..5.40
```

Room 101's doorway spans **x 3.8 → 5.2 at z = 4.0**. Its door leaf was a
seven-centimetre slab standing **perpendicular** to that, jutting 1.4m into the
room beside the opening. Every door in the building, the same.

`rotation.y = atan2(-along.x, -along.z) + PI * 0.5` evaluates to exactly 0 for
every door here (all of them run along +X). The leaf is built extending along
local +Z, so it needs `atan2(along.x, along.z)`.

**No door in this game had ever closed anything.** Every ward stood permanently,
completely open to the corridor.

Nothing caught it, and the reason is instructive: doors swung, made their noise,
reported angles, and passed every test — because what was tested was *can staff
path through a doorway*, and the answer was yes, trivially, since there was
nothing in it. Nobody had ever asked whether a **shut** door shuts anything.

That is not a small change. Closing the door is the stealth game's most basic
move. Privacy, line of sight into a ward, being seen from the corridor, and
every upgrade that reduces witnesses were all resting on a leaf that was not in
the way of anything.

After the fix:

```
ward_101   hinge=(3.8,4.0) rot=90.0deg  leaf spans x 3.80..5.20  z 3.96..4.03
```

### A permanent test for it

`play.sh doors` walks every doored room in the building three ways: in from the
corridor, back out again (*a door you can only go one way through is a room you
can get trapped in*), and — the case every play-run failure actually was — from
two metres off to the side, pressed against the wall.

| | in | out | from beside it |
|---|---|---|---|
| all five wards, lobby, station, treatment, supply, bathroom, office | 1.0–1.8s | 0.8s | 1.2–2.5s |

One outstanding: **ward_102 approached laterally from the hinge side still
fails**, alone among the eleven. Everything else on the floor passes.
The three shuttered annexe departments correctly refuse entry.

### And what the playstyles found

**Reckless** now runs end to end: three machines cranked to 11, three
complications, one patient driven from 0.42 recovery to −0.02, and Yusuf
Ratchet's suspicion at 66% with three people watching. Fifty real seconds.

**Careful Criminal** is the line the game is designed around, and it reads
correctly: one notch off prescription, recovery 1.00 → 0.98, no complication,
29% suspicion, then straight to the office to file it.

But across all four styles, **`money you $125 hospital $7,750` never changed
once**. The crime pays only at clock-out, invisibly. The HUD money ticker added
earlier has nothing to show during a shift. That is the next thing worth
looking at.

Also this session: the live run's noise-distraction check went flaky the moment
doors started genuinely blocking, because it asserted *distance closed in 6.7
seconds*. It now asserts what the original bug actually was — that the noise
reached them and changed what they were doing — and reports distance as
supporting evidence.

**1,553 assertions · 95 smoke · 18 live · boot check · every door in the
building, three ways.**

---

## Session 4 (cont.) — three ways to end a career by pressing Escape

I ran a seven-way parallel audit over the codebase looking for one shape:
*code that exists, has a comment saying what it is for, and is never reached*.
Every finding was then handed to an adversarial verifier told to refute it by
default. **28 survived, 26 were killed.**

The four criticals were all the same bug wearing different clothes.

### The chart review offered to end your career, politely

```gdscript
buttons.add_child(UIKit.button("Go fix something", close))
```

`ShiftSystem.clock_out()` had **exactly one caller in the shipping game**: the
button three lines below that one. And `end_shift()` cannot run twice — it sets
`CHART_REVIEW`, which sets `clock_running = false`, and the clock tick is the
only thing that calls `end_shift()`.

So: you reach 4:00 PM, the review tells you what an auditor would find, and
offers to let you go and fix it. The screen's own copy encourages it —
*"Terminals are still on."* — and the objective line reads *"Finish your
paperwork before you leave."* You take the game up on it. The clock is now
stopped forever. No report, no pay, no profit share, no upgrade shop, no next
day, no ending. The only exit is Quit to Menu, which throws the whole shift
away. Saving from the pause menu bakes the dead state into the autosave.

The irony the auditor found: `ui_root.gd` explicitly refuses to let Escape
dismiss the review, listing it among the screens that *"are not dismissible"* —
and the screen ships a button that dismisses it anyway.

### And the same trap twice more

- **Escape on the first-run tutorial** softlocked a brand-new career in
  PRE_SHIFT. The briefing underneath it is the only caller of `clock_in()`.
- **Escape on the upgrade shop** softlocked the day in POST_SHIFT. The statement
  it was opened from is the only caller of `next_day()`.

Three of the game's five phases could only be left through one button on one
screen, and every one of those screens could be dismissed.

### One rule, not three patches

Adding "tutorial" and "upgrades" to the non-dismissible list would have made the
tutorial unskippable and the shop a trap of its own. Instead: **Escape with
nothing on screen puts back the screen the phase is owed.**

```
PRE_SHIFT     → the briefing
CHART_REVIEW  → the chart review
POST_SHIFT    → the shift report
```

Dismissing is always allowed. Losing the game to it is not. `ShiftSystem` now
keeps `last_review` and `last_statement` for exactly this.

### And a way home that is in the building

"Go fix something" is a good offer and should stay a good offer, so it now reads
**"Go and fix it"** and tells you where to sign off. The **admin terminal in
your office** offers *"Finish the shift — sign off and go home"* during chart
review, and clocking out there ends the day.

That puts the last act of the day in the room where the records are, which is
where it belongs, and makes "go and fix something first" a real errand with a
real way back rather than a one-way door.

Three new smoke checks cover it, including a general one: **with nothing on
screen, every phase that can only be left through a screen must be able to put
that screen back.**

```
ok: the chart review is kept, so closing it is not the end of the career
ok: there is an admin terminal to sign off at
ok: and after the review it offers to end the day (Finish the shift)
ok: with nothing on screen, CHART_REVIEW offers its way out (review)
ok: with nothing on screen, POST_SHIFT offers its way out (statement)
```

**1,553 assertions · 100 smoke · 21 live · boot check.**

### Still open from the same audit

Twelve majors and twelve minors, all verified. The ones that matter most:

- The tutorial can never get past step 1 — nothing emits `request_ui("tablet")`.
- The machine maintenance panel can never be opened, so calibration sabotage —
  and everything downstream of it — is dead code.
- `clear_log()` has no player route, so wiping a device log, described in the
  source as one of the most incriminating acts in the game, cannot be done.
- Splint and Sling are defined but never placed, so two treatments are
  impossible; and **no treatment with an empty `tool` can ever be given**,
  though the chart lists six of them as indicated.
- The shift report prints the admission-cost line but leaves it out of the
  profit above it — and out of the share the player is paid.
- Continue re-runs the whole morning after loading, charging a second day of
  debts.
- The appointment system overwrites the tutorial's instruction line every
  in-game hour.

---

## Session 4 (cont.) — working the audit's majors

Twelve verified majors from the parallel audit. Six of them were features the
source described in detail and the player could not reach.

### The tutorial could never get past step 1

Six steps, strictly in order, and step 1 is "check your list" — completed by
`_on_ui("tablet")`, bound to `EventBus.request_ui`.

`request_ui` is a **request**. The tablet is opened straight from the input
handler (`open("tablet", {})`) and from the pause-menu button, both of which
call the router directly. Nothing in the codebase has ever emitted
`request_ui("tablet")`. So step 1 never completed, and because the tutorial
advances in order, **neither did the other five**.

`EventBus.ui_opened(id)` is now emitted by `UIRoot.open()` *after* a screen is
actually up, whatever asked for it. The tutorial listens to the opening rather
than to the asking. The other five hooks worked only by luck of which screens
happen to route through the bus.

### Six treatments the chart calls indicated and the game had no verb for

`rest`, `reduction`, `counter_yawn`, `talk_therapy_lite`, `sequential_apology`
and `reorientation_walk` have no `tool`. The only route into
`TreatmentSystem.apply()` is holding an item whose id equals the treatment's
tool — and no item has an empty id, so none of them could ever match. The chart
printed each one under INDICATED TREATMENTS with "no equipment" beside it.

They now appear at the bedside, in the dialogue screen's clinical-action block
alongside Examine / Theatre / Discharge, which is where they belong: there is no
way to hold "rest" in your hands.

### And two more the chart named the tool for

`splint` and `sling` are defined, meshed, priced, and are the tools for
Splinting and Sling Support — and were stocked **nowhere in the building**. The
only two treatments for a fracture could not be given by anybody, while the
chart said "Splinting — splint".

Both are now in General Stock and Treatment Stock, and a smoke check walks
`DB.TREATMENTS`, takes every non-empty `tool` that is a carryable item, and
asserts it is obtainable somewhere on the floor.

### Calibration sabotage and log-wiping did not exist

`open_panel()` had no caller anywhere in the shipping game. `_panel_open` was
initialised false and never written, so both branches behind it were dead —
including `_nudge_calibration()`, **the only code in the project that lowers
`calibration`**. Calibration was therefore always exactly 1.0, `is_miscalibrated()`
could never return true, and the branch of `run_cycle` that reads it never fired.
The class docstring calls calibration sabotage a headline mechanic;
`docs/SPOILERS.md` documents it to the developer as a real player verb.

`clear_log()` had no caller either, under a comment describing it as *"the act
of someone with something to hide"*.

Both now hang off one object that has been sitting in Treatment Stock all along:

| | wrench in hand | hands free |
|---|---|---|
| **panel shut** | open the maintenance panel | the dial, as before |
| **panel open** | turn the calibration screw *(tap)* | wipe the device log *(hold 2.5s)* |

A panel left hanging open shuts itself once you walk away from it, because a
panel hanging open is a thing somebody notices. The regression test drives the
real `interact()` path rather than the private helpers — calling those directly
is exactly what hid this for so long.

### The statement did not add up, and the player was paid on the wrong number

`daily_costs()` computed `admissions` and then left it out of `total`. The
statement printed the admission line inside the cost stack with the profit
directly underneath it, so the block visibly did not sum — and worse,
`compute_bonus()` ran on the inflated figure, so **the player's profit share was
computed on money the hospital had already spent**. (The hospital's cash was
always right; `ADMISSION_COST` is debited at admission.)

### Loading your own game charged you a second day's rent

`Game._start()` called `begin_day()` unconditionally after loading — and the
autosave is written inside `clock_out()`, with the day just worked still
current. So Continue re-settled the debts, re-rolled the morning's events,
re-ran the investigation checks and rebuilt the appointment list for a shift
that was over. A save taken from the pause menu mid-shift was worse: it put you
back at 8am with the ward as it stood at 2pm.

`phase` and `last_begun_day` are now persisted, `begin_day()` refuses to run
twice for the same day and shift, and Continue resumes where the save was taken:
mid-shift back onto the floor, chart review back to the review, post-shift
straight into the next morning.

### Which moved the economy, so the economy moved back

Folding admission workups into the profit share was correct and cost the honest
doctor about forty per cent of their income — from scraping by to **bankrupt on
day fifteen**. "Honest is hard" is the premise; "honest is not a playstyle" is a
missing playstyle.

`BASE_SALARY` 240 → 520. A wage is the right place to put that floor back: it is
the one income a doctor has that does not depend on what happens to the
patients, so it keeps an honest career alive and is a rounding error to a rich
one. It is also still hopeless — fifteen thousand a month against four hundred
and thirty-five thousand of debt is the whole reason any of this starts.

| | per day | survives |
|---|---|---|
| honest | $1,061 | 20d |
| careless | $2,904 | **13.7d** |
| mild | $3,206 | 20d |
| careful | $3,781 | 20d |

All 21 design-intent assertions pass across three seeds.

**1,562 assertions · 106 smoke · 21 live · boot check · 21/21 balance.**

---

## Session 4 (cont.) — the audit's minors, and a leak

### The symptom halo was an opaque ball, and it leaked

```gdscript
col.a = 0.35 + 0.15 * sin(...)
_symptom_mesh.material_override = Build.unshaded(col)
```

`Build.unshaded()` caches by colour string and never touches `transparency`, so
it stays at `TRANSPARENCY_DISABLED` where the alpha channel is not used at all.

Two things wrong at once. The pulse animated a channel that was discarded, so
the halo that is supposed to say *something is wrong in here* from the doorway
was an opaque ball sitting on the patient. And because the key includes the
colour, a pulsing alpha wrote a **new material into a static dictionary sixty
times a second, per patient**, forever.

The halo owns one material now, with transparency on, and the pulse writes to
it.

### The appointment roster was wiping the tutorial mid-step

`_announce_next()` writes to `objective_changed` — the single HUD line the
tutorial writes its six steps to — on every hour tick and every completed slot,
with no idea a tutorial was running. The identical clobber in `clock_in()` was
found and guarded a while ago; the guard was never applied here.

It does not need that line any more: the HUD has a dedicated appointment readout
that counts down live, added earlier this session. So the roster stops writing
to the objective line altogether, and "List cleared. The rest of the shift is
yours." became a toast, which is where one-off news belongs.

### Every room in the hospital was permanently spotless

`Room.soil()` and `Room.clean()` were the only writers of `cleanliness` and
neither had a caller, so it sat at exactly 1.0 for the whole game — and four
separate rules read it: comfort, the room's complaint list,
`has_plausible_fault()`, and the environmental complication roll. All four
evaluated a spotless hospital forever.

Breaking something now soils the room it broke in. Nothing downstream needed
changing; all four readers already existed.

### Comprehension pass

- **Every clock in the game is 12-hour, except the appointment list**, which
  printed `09:00` on the briefing, the tablet and the clinic board while the HUD
  said `9:00 AM`. All of them go through `GameState.hour_string()` now.
- **The tutorial says the chart states the prescribed dial setting. It did
  not.** The number lived inside `TreatmentMachine.set_prescribed_for()` as an
  expression, so the one thing a player needs *before* walking into a room could
  only be learned by walking into the room. `DB.prescribed_setting()` is now the
  single definition, and the chart prints it above the indicated treatments.
- **The chart listed tools by identifier** — `iv_bag`, `machine_vibe`,
  `blanket`. A chart that says "iv_bag" is a chart written by a programmer. It
  now says "IV Bag", "Gravitational Blanket", "at the machine".
- **Pressing [E] on the clinic board did nothing at all**, while the tutorial's
  first step names the board *first*: "It's on the board by the treatment bay,
  and on your tablet [Q]". A player who followed the instruction as written got
  no response and no way to know the game wanted a different key. The board
  opens the list now.

**1,562 assertions · 106 smoke · 21 live · boot check · 21/21 balance.**

---

## Session 4 (cont.) — the one mechanic the game is about paid out after you stopped playing

Four scripted playthroughs — honest, reckless, careful criminal, opportunist —
all reported the same thing:

```
** before
   money  you $125   hospital $7,750
** after cranking three machines to 11
   money  you $125   hospital $7,750
```

Bed days arrived as **one lump at clock-out**. Nothing the player did to anybody
moved a number they could see while they were doing it. The HUD money ticker
added earlier this session had nothing to show for an entire shift.

Procedure fees have always been billed the moment the work is done, under a
comment reading *"the whole point of a booked list is that you can watch it add
up"*. Beds are the business model. They now get the same treatment: every
occupied bed accrues a slice every fifteen in-game minutes — about thirty-four
real seconds at the current time scale — and `bill_day()` bills only whatever
the day's slices have not already covered, so **the day's total is identical to
the lump it replaced.**

Hourly was the obvious first choice and it is far too coarse to feel: eight
movements across a whole shift, two and a bit real minutes apart. A number that
changes twice in the time it takes to walk the corridor is not feedback.

The ledger is per patient; the movement on screen is one line for the ward —
`4 beds occupied  +$412` — because five separate lines every thirty seconds is
not a readout, it is weather. The statement still itemises every bed.

Verified: 21/21 balance design checks still pass across three seeds, and the
tiers barely move.

| | per day | survives |
|---|---|---|
| honest | $1,061 | 20d |
| careless | $2,906 | 13.7d |
| mild | $3,565 | 20d |
| careful | $3,899 | 20d |

**1,562 assertions · 106 smoke · 21 live · boot check · 21/21 balance.**

---

## Session 4 (cont.) — Phase 13: the shift report says what the shift was

The report was a correct table of numbers with a randomly chosen headline on
top. A table of numbers is right and tells you nothing about what your day *was*.

`ShiftSystem._shift_notes()` reads three flat observations straight off the same
state the table is built from, and prints them under the headline:

```
'THE MACHINE WAS LIKE THAT WHEN I GOT HERE', SAYS DOCTOR

              Nobody went home.
  Every bed is full. There is nowhere to put anybody.
```

Nothing there is invented and nothing is a judgement — no adjective, no
suspicion figure, no "questionable". *"Nobody went home."* is the whole shift in
three words, it is funnier and more damning than any number on the card, and it
is only ever printed when it is true. The joke is the flatness.

The full set: the longest current stay named with its room and its expected
length, nobody-went-home / three-or-more-went-home, how many people left the
shift with something they did not arrive with, "You were noticed 4 times. Nobody
said anything.", and every bed being full. Failing all of those:
*"An unremarkable shift, on paper."*

### Three verified bugs on the same screen

**The upgrade shop was rewriting the verdict to the flattering one.**
`screen_upgrades._last_statement()` rebuilt the report context by hand with
`"heat_delta": 0.0` and `"clean": true` hardcoded, and re-rolled
`Endings.headline()` — which is a random pick. So walking into the shop and back
out changed the game's judgement of your shift and gave you a different
headline. The two numbers the card exists to show were the two it threw away.
It now returns the report that was actually issued.

**"Nobody has anything on you." had never once been shown to anybody.**
`ranked_suspicions()` deliberately keeps institutions in the list at zero,
because an institution with nothing on you is still watching — right for the
tablet, wrong for the report, where three institutional minds are created at
start-up and never removed, so the list was never empty and the clean-shift line
was dead. The report now prints only the people who actually have something.

**The billing block did not sum to the Revenue under it.** `procedure_fees` was
a single total, so the whole appointment economy — every consultation fee, every
clinic overhead, every hour of theatre time — was folded invisibly into Revenue.
The one screen that reports the day did not mention the day's list. Fees are now
itemised under PROCEDURES & CLINIC, and the bed lines are headed BED DAYS.

```
BED DAYS
Tam Wollop — Mild Gravitational Confusion (premium)      $2,250
Marlene Blunt — Chronic Beige (Standard)                 $1,001   ← overdue, in colour
Astrid Muldoon — Excessive Spleen Torque (Standard)      $1,636
Chip Spleen — Inflamed Funny Bone (Uninsured)              $359
Kip Bright — Mild Gravitational Confusion (Uninsured)      $405
Revenue                                                  $5,651
```

**1,562 assertions · 106 smoke · 21 live · boot check.**

---

## Session 4 (cont.) — the last of the audit's verified list

### The tablet showed the three OLDEST things anybody had on you

`m.evidence` is iterated in insertion order, and `add_evidence()` appends.
Institutional records decay at a hundredth of their weight per day and the three
institutions are always listed — so the first three filings an insurer ever made
stayed above the display floor for an entire thirty-day career, and **every
statistic filed after them was unreachable on the only screen that shows what
anybody has on you**, including the ones about to sink you. Sorted by current
weight now, which is what `Mind.strongest()` has always returned for dialogue.

### Substituting a syringe's contents was completely free

Decanting worked and produced a container that says one thing and holds another.
`is_mislabelled()`, commented *"what an observant nurse spots"*, had exactly one
reader in the whole repository: a unit test. `relabel()` had no caller at all.
So the verb the source calls *"the single most useful in the game"* had no risk
and no undo — which is not a mechanic, it is a cheat code.

Both halves now exist:

- **Leaving one where it can be seen is an act.** Putting down a mislabelled
  container emits a low-weight, covered `substitution` event — a mislabelled
  bottle on a trolley is odd rather than damning, and mislabelled bottles do
  genuinely happen in hospitals. It fires the moment you put it down, which is
  the moment somebody could see it.
- **Rewriting the label is the tidying-up.** Hold a blank form or a clipboard
  and hold [E] on a container that is lying, and it stops lying. Which makes the
  loop: decant (seen, risky) → use it → *either* drop it and leave a found
  object, *or* spend two seconds putting the label right first.

And `is_mislabelled()` was itself broken: it compared the label against the raw
substance **id**, so a container honestly labelled "Ambient Dread" containing
`ambient_dread` read as lying. Every multi-word substance in the game was
permanently mislabelled. It only ever looked right because the substance
everything was tested with, `chalkinol`, happens to be one word.

### And doors can be slammed

`SwingDoor.slam()` had no caller — it zeroes the leaf, thuds, and emits a
sixteen-metre noise event, which is one of the loudest distractions available
and could not be produced. `[Shift+E]` on an open door slams it, matching the
"other way round" modifier the supply shelf and the treatment dial already use.

**1,568 assertions · 106 smoke · 21 live · boot check.**

---

## Session 4 (cont.) — bright and cartoony

Asked for: make the graphics bright and cartoony, Fortnite-ish. The game has no
art assets at all — every mesh is primitives assembled at runtime — so this is
entirely a palette, lighting and proportion problem.

A parallel inventory first, because a missed constant leaves one object the old
colour and looks like a bug. Five sweeps established that `Build.mat()` and
`Build.unshaded()` are the **only** two places a `StandardMaterial3D` is ever
constructed, that the palette was 16 constants of which ten sat below S=0.10 in
HSV, and that `hospital.gd` hard-codes eleven room floor colours that bypass the
palette entirely. It also turned up two dead constants — `FLOOR_B` and `TRIM`
have zero references anywhere — and that **interior lights cast no shadows at
all**; the sun is the only shadow caster in the game.

### Environment

- **A real sky.** `BG_COLOR` with `Color(0.10, 0.12, 0.15)` — a dark grey void —
  became a `ProceduralSkyMaterial`. It is only ever seen through the windows and
  off the ends of the corridor, and those were the two places the building
  looked cut out of a larger, sadder game.
- **No fog.** Distance haze is what makes a corridor look grim, and this one is
  sixty-two metres long. It was the single biggest reason the far end of the
  ward read as a bad place to be.
- **Ambient 0.28 → 0.34, room lamps 1.25 → 1.05, plus a cold fill light** at a
  quarter of the key from the opposite side. Nothing in a cartoon has a black
  side; it has a cooler side.
- **Soft shadows** — `shadow_blur = 2.4`, specular down. A hard black shadow
  under every chair is the other half of "grim".
- **Saturation 1.16, contrast 1.04, soft glow.** One global knob over the top of
  every other choice.

The first attempt used `TONE_MAPPER_LINEAR` for maximum colour purity and
produced a photograph of a lightbulb — an ambient term, a key, a fill and a
ceiling lamp every five metres all landing on the same white wall. Linear keeps
colours pure right up to 1.0 and then clips flat. Filmic rolls the top off,
which is precisely what lets everything below it be bright.

### Palette

Every constant pushed up in saturation and value: a wall is cream rather than
off-grey, the dado is a real teal rather than a suggestion of one, a warning is
a proper sunny orange. **The rule for adding to it: if you would describe the
colour with the word "slightly", it is wrong — pick the actual colour.**

The eleven per-room floor tints were eleven shades of the same grey, which is
why the whole floor plan read as one continuous corridor. They are now
distinguishable colours, so you know which room you are in from the doorway.

And **a soft rim on every material**, tinted toward the surface's own colour.
This is most of what separates "a grey box" from "a stylised grey box": every
object picks up a light edge where it turns away from you, so silhouettes read
at distance and nothing dissolves into the wall behind it.

Metals stopped being metals. Bed rails, IV stands, cart frames and the door
handle were at 0.5–0.8 metallic; a stylised interior has no reflection probes,
so anything above about 0.2 metallic has nothing to reflect and renders as grey
mud. Chrome in this game is painted chrome now.

### People

Built to realistic proportions — a 0.155m head on a 0.22m torso with 0.062m
arms — which at the distance you actually see people in this game, across a
sixty-two metre corridor, reads as a set of grey sticks. Everything is about a
third heavier and the head about a fifth too big, which is what makes a
silhouette legible at forty metres and a face legible at four. Plus a collar in
a lighter shade of the outfit, and **eyes with whites behind them** — a dot on a
sphere is a mole; a dot on a white oval is an eye.

The first pass gave them a 0.37m hair cap on a 0.40m head, centred. That is a
helmet — and a patient lying in a bed is rotated ninety degrees, so the first
rendered close-up was a brown block where a face should be with two eyes peering
over the top of it. Narrower, set back, and on the crown now.

Verified: full suite green, and `play.sh doors` unchanged at seven timeouts —
the three shuttered annexe rooms and the known ward_102 lateral case — so the
fatter collision capsule (0.26 → 0.30) still fits every 1.4m doorway.

A new permanent screenshot, `04b_bedside`, frames a character close enough to
see a face. Characters are the one thing in this game that has to read at four
metres *and* at forty, and every other shot was framed for the room.

**1,568 assertions · 106 smoke · 21 live · boot check · 33 screenshots.**

---

## Session 4 (cont.) — Phase 5: what a witness thinks, as something you can watch

The game's only read on what somebody thought of you was **a colour on their
name tag**. That is a meter wearing a diegetic hat, and the brief is explicit:
behaviour, not meters.

### They write it down

`NPCBody.make_a_note()` — the character stops where they are, takes out a
clipboard, and writes on it for two and a half seconds, with a distinct arm pose
and no walk cycle. Nothing is announced, no number moves, and there is no text.
The player draws the conclusion, which is the only version of this that is ever
tense:

> She was standing there. She saw it. She stopped, and she has written it down.

It is honest, too — it fires when a mind genuinely records something it saw with
its **own eyes** (`Evidence.Source.WITNESSED`, weight ≥ 0.18), so what the
animation says is exactly what the simulation did. A thing somebody was told in
a corridor is not something they stop and minute.

It also fires on the three places a nurse's round files evidence: finding an
undocumented complication, spotting that somebody has picked up several separate
injuries on this ward, and noticing that a patient has been on a trolley in
Intake most of a shift. So the round became visible: **you watch a nurse walk
into Room 103, stand at the bed, and minute something.** That is the entire game
in a five-second observation.

Nobody stops to write while investigating a noise, following you, or on their
way over to speak to you. Standing still for two and a half seconds is a real
cost to a character mid-errand, and it made the "does a noise pull anybody off
station" check intermittent — a nurse who froze to write something up on the way
to the supply room had, from the outside, simply ignored it.

### Gossip is a scene now

It was a line of dialogue with nobody in it: one NPC said something into the air
and a number moved inside another one. Gossip is how a thing one person
half-saw becomes a thing four people are certain of, and none of it was visible.

Now they turn to face each other, the speaker says their line — and then **the
listener looks straight at the player**, if they can see them. That is the
entire content of the moment and it needs no words at all.

A new live check asserts the note is driven by the memory rather than decorating
it: the same probe that fires a blatant act in front of a forced-observance
nurse now also asserts she stopped and wrote it down.

**1,568 assertions · 106 smoke · 22 live · boot check. Three consecutive clean
full runs.**

---

## Session 4 (cont.) — Phase 9: a wrong site is a situation, not a dead end

The brief: soften *accidental* wrong-site failure without removing the
catastrophic consequence, no obnoxious confirm dialogs, find a diegetic or
skill-based solution.

The theatre screen already states the indicated site and colours its button
differently, so an accident needs a genuine misread rather than a fumble. The
real problem was what happened next: **the only thing left to do about it was
press Close.** A mistake you cannot respond to is not a mistake, it is a
punishment.

### The revision

A surgeon who realises mid-list does the indicated procedure as well. The
outcome screen now says, flatly:

> The knee was not the problem. The wrist still is.
> **Open the wrist as well**
>     recorded as: site revised intra-operatively

It runs a second operation on a body that has already been opened once today —
so every stage is treated as improvised, which is both the higher risk and the
more honest note — and the theatre record ends up with two sites on it, which no
auditor will read charitably. Walking away is still available, and still the
version that ends careers.

No confirmation dialog anywhere. The choice is made in the fiction, out of a
theatre record, in the same words the rest of the screen uses.

### And the site is on the patient

Real theatres mark the operative site on the patient, for exactly the reason it
is here: so the answer to "which one" exists somewhere other than a screen
somebody has to have read carefully. Patients now carry a bright band on the
indicated limb — wrist, shoulder, knee or ribs — in the one colour nothing else
in the building uses, kept current as injuries appear and resolve.

You can see, from the doorway, which limb has a mark on it.

Five new smoke checks, including one that would have caught the whole class:
every operable site in `SURGERY_SITES` must have somewhere on the body to mark.

One thing found on the way: the new check originally operated on `active()[0]`,
which is the patient the save/load round-trip authors a theatre record on and
then asserts the exact contents of. It uses the last patient on the ward now.

**1,569 assertions · 111 smoke · 22 live · boot check.**

---

## Session 4 (cont.) — Phase 16: three shifts that are three different places

The shifts differed in pay, staffing, appointment count, admissions and scrutiny
— five real numbers — and the building looked identical in all three. A player
picking "Night" got a different spreadsheet and the same room, which is the
least persuasive way to offer a choice.

### The building has a time of day now

`Game.SHIFT_LOOK` re-tints the sky, the ambient term, the key light, the fill
and every ceiling lamp in the hospital when a shift starts.

| | sky | ambient | key | lamps |
|---|---|---|---|---|
| **day** | blue | 0.34 cool white | 0.85 white, high | 1.05 warm |
| **evening** | orange horizon | 0.26 warm | 0.52 amber, low in the sky | 1.20 |
| **night** | near-black blue | **0.16** cold blue | 0.16 moonlight | 1.35 warm |

Nothing there is decorative. Night is genuinely darker, so the same act is
genuinely harder to see. The shift select screen has always promised *"Skeleton
crew. Nobody is watching."* — it is now a thing the player can look at rather
than a claim.

### And the ward is asleep

`PatientNPC.SLEEP_CHANCE` — 85% on nights, 30% evenings, 6% days. A sleeping
patient has `perception.attention = 0.0`, so they genuinely witness nothing
rather than merely appearing not to, and their eyes are shut, which is
unmistakable from the doorway. This is the difference that changes what the
player *does*: the five people who would normally be lying there watching you
work are, on nights, five people who are not.

It is not free. **They wake to a bang** — so the distraction you used to move
the nurse also wakes the man in the next bed, and a shift you chose because
nobody was watching becomes one where everybody is, because you made a noise.
Treating somebody wakes them too, so night is a trade rather than a free pass.

Three new world screenshots — the same corridor on all three shifts — because
this is precisely the class of change that only a picture can confirm.

### Three flaky live checks, and why

Adding a sleep roll consumes RNG at a new point, which re-rolls an entire seeded
simulation. That did not break anything; it exposed three assertions that were
passing on luck:

- **"the floor is still navigable"** pathed lobby → ward_105 and called that
  "the floor". Blocking a doorway with a trolley is a *mechanic*, so a prop
  coming to rest in one doorway during eight hours of physics failed a test
  about the whole building. It now asks the obstruction monitor which doorways
  are deliberately blocked and asserts every *other* room is reachable.
- **"a noise pulls somebody off station"** read the INVESTIGATE state at one
  instant, several hundred frames after the noise. INVESTIGATE is a state people
  pass *through* — they hear it, walk over, look at the mess, go back — so the
  check caught whoever happened to still be mid-errand and missed everybody who
  had already arrived. Sampled across the whole window now.
- **"the corridor can see into a ward through an open door"** posed the door,
  waited forty frames, and queried — by which time the nurse had walked 1.6m and
  the sightline being measured was no longer the one that was set up.

Five consecutive clean live runs and three clean full runs after.

**1,569 assertions · 116 smoke · 23 live · boot check · 36 screenshots.**

## Phase 8 — events that change how you play, not what you read

Nineteen random events, all of which had an `apply()` arm, so none were pure
text. Three of them, however, set a flag that **nothing in the game ever read**,
and a fourth was read once to pick a tannoy line. An event you cannot play
differently is a loading screen with a title on it.

**A family row is now a condition of the day.** Both halves of every family
dispute walked out of the building on their first physics frame: `_timer` is
only loaded on the `ARRIVING -> VISITING` transition, and the event set the
state directly, so `if _timer <= 0.0: _leave()` fired immediately. The one event
whose entire promise is "nobody is watching anything else" had never once
distracted anybody. `VisitorNPC.stand_and_argue()` parks them properly, and the
row now flares up again every twenty in-game minutes — long enough that staff
make it back to station, short enough that they never settle — wandering to a
new stretch of corridor about half the time so it does not become furniture that
people learn to route around. It ends when both parties finally go home, and the
shift report says if it was still going when you left.

**The press is a person now, and a press day has a price.** `press_present` used
to weight one PA announcement. There is now a reporter from the Ashcroft Gazette
standing in the lobby — the most observant, least loyal, most talkative mind in
the building — and a complaint filed while she is there costs roughly three
times the heat, reaches the medical board rather than just administration, and
produces a piece. The strategy it creates is a real one: today is the day to
keep your head down, or the day you accept that everything is worth triple.

**Vinnie keeps track.** Each visit costs 300 more than the last, and from the
third he starts waiting by the staff entrance, which is its own kind of
paperwork. Paying the man becomes a plan rather than an option.

**Nobody ever went home.** The student assigned to shadow you "all day", the
agency nurse "covering today", both halves of the row — `clear_day()` reset six
booleans and freed nothing. Every one of them was still on the ward on day
thirty, so a career silently accumulated a permanent crowd of the game's most
observant witnesses and the day-shaped events were quietly permanent. They are
sent home at rollover, and their minds go with them: what a one-day witness saw
survives only in what they told the staff room, which is a far more interesting
shape than an eternal observer.

Also: `RandomEventSystem.apply()` read the scene tree on its first line, so a
system instantiated on its own aborted before reaching any of the null-checks
the rest of the file is full of. It tolerates being out of tree now, which is
what let the three effects above be unit-tested at all.

Verified: 1,581 assertions · 121 smoke · 23 live · boot check · 21/21 balance
across the strategy set · 36 screenshots.

## A building you can read, and a HUD that stops shouting over it

**Toasts queue instead of arriving all at once.** Five patients are handed over
at 8:00 on the first morning, and all five toasts landed in the same frame — a
wall of text that reads as decoration and is gone before you have parsed the
second line. At most three are on screen now, one released every half second,
and an identical line repeated inside the window becomes a count on the line
that is already there rather than a second copy of it. Every burst in the game
benefits; the opening handover most of all, because it is now five names you
read one at a time instead of a paragraph you skip.

**Signage is on plates.** White outlined text floating on a pale wall was
legible in the sense that you could read it once you knew it was there. Room
plates, corridor flag signs and every wall sign in the furniture recipes now sit
on a dark plate, and the flag signs have a stub mounting them to the wall
instead of hovering off it. Two hazards worth recording: a plate centred on its
label swallows the label whole, and the two back-to-back faces of a flag sign
each need to sit proud of their own side of it.

**The nurses' station had its counter against the exterior wall** — ten metres
and a partition from anything, with a comment above it claiming it faced the
corridor so nurses could see everything. There is now a counter that does face
the corridor, in two runs either side of the doorway, so the building's one
permanent surveillance post looks like one from outside it.

**The lobby was being photographed as a blank wall.** The shot faced the
corridor doorway with reception, every chair and the vending machine behind the
camera. Turned around. This is a note about the harness, not the game, but the
harness is how any of this gets looked at.

One live check went red on the way: the witness note probe depended on whichever
nurse it grabbed not happening to be mid-investigation, because a nurse chasing
a noise deliberately does not stop to write. It forces the state now, so it
tests the routing it claims to test rather than patrol timing.

Verified: 1,581 assertions · 121 smoke · 23 live · boot check · 36 screenshots.

## Phase 11 — you can see what the money bought

Eighteen upgrades, half of which genuinely change how you have to play, and the
only one you could SEE was a department shutter rolling up. Everything else was
a boolean read by a system and never by the player, so a career's worth of total
reinvestment left the ward looking exactly as it did on the first morning.

`Hospital.refresh_fittings()` rebuilds a `Fittings` node from what is owned, on
build, on purchase and on load:

- **Corridor cameras** — four in the corridor and one in the lobby, matching
  `Upgrades.camera_rooms()` exactly, with an unshaded red LED so they read from
  the far end. This is the one that matters most: camera coverage was a list of
  room keys in a static function, and it is now a thing you can look up and see,
  which turns the purchase into a map of where it is a much worse idea to be
  seen rather than a line in a menu.
- **Curtains** round every bed, hung off ceiling droppers and bunched at the end
  of the rail away from the vitals console.
- **Adjustable beds** get a raised head section and a control pendant.
- **Confidential waste**, a locked bin beside the filing cabinet.
- **VIP suite** — a rug, a lamp and something alive, which is more than anybody
  else on the ward gets.
- **Legal retainer and a seat on the board**, framed, on your office wall,
  placed clear of the desk terminal.
- **The coffee machine** the nurses reorganise their shift around.

The smoke check that asserts fittings track ownership found that
`refresh_fittings()` doubled them every time it ran: `queue_free()` is deferred,
so the outgoing node still held the name "Fittings" when the replacement was
added, Godot renamed the newcomer, and `get_node("Fittings")` returned the
corpse. `remove_child` before freeing.

Verified: 1,581 assertions · 124 smoke · 23 live · boot check · 40 screenshots.

## Phase 19 — what a frame actually costs

The live harness now reports it, because a number nobody has is a number nobody
improves. First reading was 5.90 ms mean, and it took a while to see that it was
roughly four hundred times too pessimistic: `live_impl` force-advances three
game MINUTES per frame so that hourly and daily behaviour fires inside seven
thousand frames, and real play advances 0.0074. Every per-minute system in the
game — economy, shift, suspicion decay, the tannoy — was running four hundred
times more often than it ever will. Cost is now sampled only inside a window
where the clock is left alone.

At the honest rate: **mean 4.37 ms, p50 3.69, p99 9.85, worst 13.29, 4,728
nodes** — simulation only, no rendering, fifteen characters live.

Breaking that down put four fifths of all character time in `move_and_slide()`,
and most of the building is stationary most of the time: nurses at the station,
patients in bed, visitors sitting. Bodies that are already resting on the floor
with no path and no velocity now skip the solver (and `_push_obstacles` with it,
which reads the slide collisions the solver produces and has nothing to do for
somebody standing still). The test is deliberately strict, because a body that
skips the solver also skips gravity and a patient hovering where their bed used
to be is a far worse bug than a slow frame.

After: **mean 3.74 ms, p50 3.18, p99 9.00, worst 9.94** — about a fifth of the
frame given back, with the AI still moving five of eight staff under its own
steam in the same run.

Also caching `SuspicionSystem.watchers()` for a tenth of a second: it fires one
physics raycast per registered body and the HUD asked for it every frame to
redraw a three-line text panel. Smaller than expected (the HUD is idle in the
harness) but it is free and it was obviously wrong.

Two engine messages, recorded so nobody chases them twice: `Parameter "m" is
null` at `mesh_get_surface_count` is the DUMMY renderer's mesh storage and
appears only under `--headless` — the windowed screenshot runs are clean. The
`ObjectDB instances leaked at exit` warning comes from harness teardown, not the
game: `boot_check.sh`, which exercises the real entry point, exits clean.

## Comedy and content pass on the barks

Every idle pool roughly doubled, in the same register — deadpan, institutional,
never winking. Eight patient archetypes, six family archetypes, four witness
tiers, gossip, overdue and ready-to-go-home lines. A twenty-minute shift was
cycling three lines per archetype, which turns a character into a slot machine.

`Dialogue.gossip_line()` said "101" every single time regardless of where
anything had happened. It names the room the evidence is actually about now, and
falls back to "one of the side rooms" when the evidence has no patient — a small
lie, but paying attention is the exact skill the game asks for, and it should
reward that rather than punish it.

## Juice

A camera kick, reserved for the handful of moments the game wants you to feel
rather than read: an injury happening within six metres of you, a door slammed
within five, something you were holding breaking, an investigation opening, a
sanction landing. Two frequencies so it reads as a jolt rather than a wobble,
laid on top of the head bob instead of replacing it, and clamped so a pile-up
cannot black out the screen.

## The first frame of a run was a dice roll

`_spawn_player` put you at a random point in the lobby facing a random x
somewhere along a sixty-two metre corridor. The one image every player sees
before they have touched anything was therefore a coin flip between "a hospital
waiting room" and "a blank wall two metres from your face".

It is authored now: a fixed spot behind reception, chairs to the left, the
out-of-order vending machine and a parked wheelchair to the right, and the
corridor doorway dead ahead with the objective through it. `screenshots.sh`
takes `00_first_frame` from the player's own camera, where the game actually
puts it, so this can never silently drift again.

## The play harness could not press half the keys in the game

`play_impl._press` used `Input.action_press()`, which sets an action's STATE —
everything polling `is_action_pressed` sees it — but synthesises no InputEvent,
so nothing in an `_unhandled_input` handler ever heard about it. The tablet [Q]
and the pause menu [Esc] both live there. The harness's "what does the tablet
say" screenshot was, for its whole existence, a photograph of the room; and the
tutorial step that completes when the tablet opens could never complete however
the plan was written, so every play run reported the objective stuck on step one
of seven and that read as a game bug rather than a harness one.

Actions are now delivered as real events too — **on transitions only**. Firing
one every frame (which is what `_walk` does, for the whole length of a walk)
flooded the input queue badly enough that a sprint down the corridor ended with
the player wedged in the north wall pushing 3.4 m/s into it forever. Confirmed
by running the same plan with the change and without: 10.3 s versus a 60 s
timeout.

**The tutorial now credits you for what you actually did.** It used to drop any
step completed out of order outright, which is the wrong shape for a sandbox: a
player who walks in, examines somebody and treats them before thinking to pick
up the chart had done four of the seven steps, been credited with none, and was
still being asked for the first one. Completions are remembered whenever they
happen and the objective skips to the first thing genuinely outstanding.

**A cache keyed on wall time is not deterministic under `--fixed-fps`.** The
`watchers()` cache I added for the frame-cost work held for a tenth of a
SECOND, which is a different number of frames depending on how fast the machine
happens to be running — two live checks failed intermittently before that was
obvious. It counts physics frames now, which is exactly six frames everywhere.

Measured movement, from the harness, at 60fps: spawn to the corridor 2.4 s, the
full 58 m corridor 17.0 s walking and 10.3 s sprinting, clinic board to a bedside
in Room 101 9.9 s, Room 101 to the treatment bay 8.6 s.

Verified: 1,585 assertions · 124 smoke · 23 live (three consecutive clean full
runs) · boot check · 40 screenshots.

## Every patient in this game has been hovering above their bed

The closest look a player ever gets at a character is somebody lying two metres
away, and the close-up screenshot of that was a head with no body attached,
floating over the linen. Screenshots were ambiguous enough to argue about, so
the answer came from a check that measures the head against the mattress: the
head sat 0.58 m above it.

`PatientNPC._hold_bed_pose` re-pins a patient to the bed's origin every frame —
which is what makes wheeling a bed wheel the patient — and then the solver ran
anyway. The bed's collision box is 1.0 x 0.7 x 2.1 about its own centre, the
patient was pinned INSIDE it, and depenetration ejected them half a metre
straight up, every frame, since beds were added. `NPCBody.pinned` now suppresses
gravity and `move_and_slide` outright for a body something else is holding in
place, and the reclined offset puts the head on the pillow rather than a hand's
width above it.

Two things worth recording about how this was found:

- The check does **not** belong in the smoke run. Put there, it reported a
  number that was an artifact of that harness's own brevity — the smoke run gets
  through about forty physics frames, which is not enough for a body to be
  pinned, ejected and settle. It lives in `live_run.gd`, which is the layer
  CLAUDE.md already says exists for "anything that only breaks with real
  frames", and this is exactly that.
- Pairing a patient with a bed by room key picked somebody else's bed twenty
  metres away, because earlier checks in the same run wheel a bed into Intake.
  It asks the body which bed it is bound to.

Free consequence: five patients no longer run the character solver at all, and
the measured frame went from 3.74 ms mean to **2.88 ms**.

Also, the hair is a squashed sphere rather than a box. A slab reads as hair from
straight on only, and a patient in bed is rotated ninety degrees and seen from
the side — from there it was a dark plank stuck to the side of somebody's face.
The comment above that line has described this exact bug since the first pass;
it was the shape that was wrong, not the size.

Verified: 1,585 assertions · 124 smoke · 26 live · boot check · 21/21 balance ·
40 screenshots.

## The number you are trying to survive on did not move all shift

Across all four scripted playstyle runs the personal-money readout was identical
at 8:00 and at 3:59. The ward bills every fifteen game minutes and the hospital
balance ticks up all day, but your cut is computed once, at clock-out — so the
one number the whole game is about sat still while you played, and every
decision you made about it paid off only in a screen you see after the fact.

The HUD carries a fourth line now: **today +$X**, your share of what the ward has
billed so far. It is not a payment — the money still lands at clock-out and the
statement is still the reveal — but keeping somebody another night is now
something you can watch rather than something you infer. Procedure fees land on
it the moment the work is done, which is what makes a booked list feel like a
list rather than a chore.

The backing panel had to grow with it, or the census line hangs off the bottom.

## The one door of eleven that failed was not a door

`play.sh doors` has had ward 102's lateral approach red for as long as the
harness has existed, and it has been written down twice as a door bug. It was a
bench.

The corridor benches sat at x 11.0 and 12.4. Ward 102's opening starts at 12.8.
Four centimetres of clearance, on exactly the line a player walking the north
wall arrives on — so they caught the bench, stopped dead half a metre short of a
door that was working perfectly, and the prompt in front of them said "or just
walk into it". The benches now sit in the middle of the gaps between openings,
and all eleven doors pass from all three approaches.

Two harness improvements got there. `push_forward` timeouts print the same
blocker diagnostic a `walk` timeout does — without it, a door failure reported
only that it had not happened, which is the one thing already obvious from the
timing. And `_blockers` names each collider's position and its parent chain
rather than printing `@StaticBody3D@727`, which identifies nothing: walls,
counters and chairs are all auto-named static bodies, and the answer here was
entirely in "under an anonymous Node3D at (12, 0, 4)" — the shape of a
`Furniture._chair`.

## "This looks like blocky junk" — the visual pass

Fair. Everything was axis-aligned boxes with a rim light on them. Five changes,
in rough order of how much each was worth:

**1. An outline pass.** `Build.outline()` is a shared inverted hull: the same
mesh drawn again, grown along its own normals, front faces culled so only the
sliver past the silhouette survives. It is the cheapest cartoon outline there is
and it is most of the difference between "primitives" and "a style". It is
attached as `next_pass` on every material `Build.mat()` hands out, and turned
off explicitly for floors, ceilings and wall runs — they are the largest
surfaces on screen, a room already has an edge where its own walls meet, and
drawing them a second time full-screen doubled the fill cost for a line nobody
was going to look at.

**2. Rounded geometry, because the outline demands it.** A `BoxMesh` has three
separate normals at every corner, so growing along them tears the hull into
three detached slabs and the line breaks at exactly the corner the eye is drawn
to. `Build.rbox_mesh()` builds a rounded box as a Minkowski sum — take a sphere
of the corner radius and push each vertex out to the nearest corner of the box's
inner core by the sign of its own normal, so the sphere's octants become the
eight corners and the rings between them stretch into the flat faces. One mesh,
smooth normals throughout, nothing for the outline to break on. `box_mi()` uses
it for everything, with the radius scaled to the object so a syringe is not
rounded as hard as a wall.

**3. Characters that are people rather than stacks.** `Build.taper_mesh()` is
the same trick with the core interpolated by height, so a torso can be broad at
the shoulders and narrow at the waist in ONE solid. That mattered more than it
sounds: the outline draws round every part, so a torso built from three stacked
slabs draws three outlines and every seam becomes a hard black band across the
chest — the first render of the restyle was a person made of pillows. Each limb
and the trunk are single tapered solids now, and only the details that should
read as separate objects carry a line of their own. The face got a nose, a
mouth, brows, a chin, ears and a hairline; the hands are mittens wider than the
wrists, because a limb that tapers to nothing reads as a tentacle.

**4. Trim.** A pale dado rail on the seam between the two wall tones and a dark
skirting at the floor, both proud of the wall and both outlined; an inlaid
border a foot in from the walls of every room; three painted wayfinding stripes
down the corridor. All of it cheap, and out of all proportion to what it cost —
a flat two-tone wall is a gradient with a line across it, and the same wall with
a rail and a skirting has EDGES. Edges are what the eye uses to decide whether a
room was built or generated. Written the wrong way round first: a dark rail
under a teal dado is the same wall with a slightly different teal at the bottom.
What reads is contrast against what it sits on.

**5. Values.** Exposure 0.92 → 0.78 and white 3.2 → 2.6, because the far end of a
sixty-two metre corridor was clipping to flat white and every sign, door and
person past thirty metres dissolved into it. Floors are about a fifth darker
across the board — they are the largest surface in shot and should be the
DARKEST of the three planes, not the brightest, so props read against them.
Ceiling lamps are a housing with a lit panel recessed into it rather than a
floating white slab. SSAO on (Forward+ only; the screenshot harness runs
Compatibility and will not show it).

The harness got two portrait shots — a face at a metre and a whole person at
three — because characters are the only thing in this game that has to read at
four metres AND at forty, every other shot is framed for a room, and the model
was being judged from whatever happened to wander through the back of a corridor
photograph. Three separate framing bugs surfaced doing it: the camera ended up
inside Room 103 (the corridor is only four metres deep, so the standoff has to
run along it), the subject faced away every time (`look_toward` leans the head;
the body needed its yaw set outright), and `String(shot[1])` on a Vector3 is not
a constructor Godot 4 has — it errored every frame without advancing, so the
harness span forever on the first shot.

Verified: 1,585 assertions · 126 smoke · 26 live · boot check · 43 screenshots,
and the frame is unchanged at 2.58 ms mean despite roughly 800 more nodes.

## ...and the same pass, finished

`Build.box_mesh()` itself returns a rounded box now. Same call, all ~60 sites
unchanged, and it caught every prop, terminal, machine, notice board and window
frame in the game in one edit — nothing casts the result to `BoxMesh` or reads
`.size` back off it, which is the only reason that could be done in one place
instead of sixty.

The supply room was three blank white cabinets, for two separate reasons.

Only the BOTTOM shelf of each unit was ever stocked; the other two were empty
frames. All three carry cartons and bottles now, sized and coloured off the
index so it is the same shelf every run and no seeded RNG stream is disturbed.

And **all three units were facing the wall.** A shelf's front is its local +Z,
and rotating -90 degrees about Y sends +Z to -X — straight into the wall they
stand against. The room the whole game sends you to for equipment had been
showing it their backs.

Ceiling and wall values came down again (`CEILING` 0.84 → 0.66, `WALL_UPPER`
0.94 → 0.87, ceiling lamps 1.05 → 0.82). A ceiling is the top third of every
interior shot and it is lit from below by a lamp every five metres, so at
anything near the wall's value it clips to flat white and the room loses its lid.

Verified: 1,585 assertions · 126 smoke · 26 live · boot check · 43 screenshots.
Frame cost 2.55 ms mean with 5,553 nodes — lower than before the restyle
started, because the same pass that added the geometry also stopped patients and
idle staff running the character solver.
