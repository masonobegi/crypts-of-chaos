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
      (Deleted in session 15: it described the pre-redesign game. `docs/REDESIGN.md`
      is the live design; git has the original.)
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

- Two authored wards, alternating. Day three comes round to the first one
  again with the carry making it harder. A third would be the next content
  worth having, and the shape to aim for is a ward where the honest hold is
  somebody's *social* circumstances rather than their medicine.
- Nothing is randomised. Same five people, same rounds, same traps — the
  replay comes from what you do, not what you are dealt.

---

## Session 13 — 2026-08-22 — the second ward, the second opinion, the second reason to be somewhere

Three things the last audit named as what stood between a proven design and a
game. All three are in.

### A second ward that is a different problem

Not the first one renamed. On ward one the man who genuinely needs the bed is
on premium cover, so the honest hold is also the one that pays — honesty is
tight but it is not a sacrifice. Ward two moves the money: the only person who
both needs the bed and pays for the night is **Peter Lomax**, whose chart says
he is improving. Every number on it has been coming down all week and he is not
fit to go. You cannot find him by reading.

Simulated before it was written: emptying the ward is short by 550, mercy alone
is short by 520, the two who are genuinely unwell clear by 180, the two who
merely *look* holdable clear by 450, and holding all five still earns less than
holding three. Four new traps, each a different shape from ward one's — a
daughter who is a solicitor and asked for the notes before you arrived; a woman
with a shift at four who signs herself out if you have not decided by then,
leaving a document you did not write; a retired ward sister who reads her own
chart every evening; and the man the record cannot describe.

### The two verbs

**Examine.** The only verb that tells you the truth and the only one that
cannot be done from a terminal. Fifteen minutes, writes nothing — it informs a
decision rather than justifying one, which is what stops it becoming a free
corroborating note you award yourself. Looking twice is free.

**Ask the registrar.** The strongest corroboration in the game and the most
dangerous request in it. A nurse looks at the patient; Dr Costa reads the whole
chart first and then writes down what he *thinks*. About somebody who needs the
bed that is `BACKED`, which nothing can take apart. About somebody who does
not, he writes a discharge **plan** — and reversing a named doctor's plan costs
0.78 against a nurse's 0.55. He is on this ward 11–13 and 15–17 and unreachable
otherwise, so asking him is something you schedule.

### And a reason to stand in a particular place

The ward already had one: the bay terminal in front of five people, against the
office with a door on it. That is a choice about where to be **seen**. The
**handover board** is a choice about where to **learn** — the rounds stated
rather than inferred, and nursing's plan for every bed, on a wall in the
station and nowhere else. Derived the way a nurse would derive it, from the last
thing anybody wrote, so it is wrong about exactly the patients the chart is
wrong about.

### The hole the audit did not find: half the decisions were unexamined

Every finding in the game asked about beds you **billed**. So it punished greed
and was completely indifferent to haste, and the fastest route to a clean
handover was to empty the ward — the one thing a doctor must not do. A
discharge is a decision and is audited as one now, in ascending order of how
badly it reads: the chart said otherwise, or a colleague you asked said
otherwise, or you examined them yourself and went ahead. *Discharge everybody*
has gone from **signed off** to **flagged**.

### What the instrumentation had been measuring

`remembered_beds` was cleared between playtest runs and `carried_debt` was not.
So from the first strategy that came up short, every strategy after it owed
Vinnie more than the last, and the number climbed again each time somebody else
fell behind — three successive audits reported a risk/reward frontier that
depended on the order of the list. One well-timed lie is worth **850** over an
honest day's 150, not 150 over 150.

The adversarial search now covers **2,200 plays**: both wards, every subset of
beds up to three, eleven ways of justifying a hold, and whether you *mix* them —
a peer behind the bed that deserves one and your own note on the bed that does
not, which is what somebody who has understood the game does and which a
single-verb search cannot see at all. Both frontiers are monotone and the risk
premium is the same on each:

```
ward one   signed off  150    noted  850    flagged 1150   referred 1150
ward two   signed off  180    noted  880    flagged 1150   referred 1150
can the top figure be reached signed off?   no, on either ward
```

### Every patient on the ward had their back to you

`rotation.y = bed.rotation.y + PI` for four iterations. The reasoning was that a
Godot model faces −Z so facing the bed's foot needs a half turn; these bodies
are built facing +Z, so the correction *was* the error. The harness that
photographs a patient from the front had been photographing the back of Sam
Oduya's head, and nothing that reads state could tell. Being looked at when you
walk in is most of what this game is about, and nobody had been.

Also found by looking: day two opened with Hal Brennan's name floating over a
bed belonging to Tallulah Ferreira, because `reset_day()` woke yesterday's
patients up rather than rebuilding the ward. And Ruth Kerrigan announced herself
at seven o'clock on a ward her mother has never been on.

---

## Session 14 — 2026-08-22 — the career

The fourth audit's finding was that the day was a game and the career was a
loop. This session made the career.

### An eight-lens panel attacked the plan before it was built

And found four things that would have made the game worse than the loop it
replaced. All four were real when checked against the code.

**Information had strictly negative expected value.** `_sent_home_unwell`
bailed unless the discharge was documented, examined, or overruled by a
colleague — and all three of those are things the *player* does. So the way to
make a wrongful discharge invisible was to never read a chart, never examine
anybody and never ask. Looking at a patient was the only way to manufacture
the evidence that convicted you of the decision you then made. Peter Lomax,
the man the second ward is built around, was **safest for a player who never
went near him**. It is a severity ladder now, not a gate, plus two findings
the player does not author: they came back, and you decided about three people
you never went near.

**The $900 was a daily stipend.** `cash = STARTING_CASH` sat in `start()`,
which runs every morning, so the player was minted a third of a night's
takings out of nowhere under every strategy in every measurement this project
has ever taken. It also made "he takes everything at eight" vacuous. Granted
once now; cash carries; every number re-derived.

**FLAGGED was a free verdict.** `struck_off()` read only referrals, and the
money-optimal play lands on FLAGGED on both wards and never on REFERRED — so
the optimal player accrued zero strikes forever and the auditor, gated on
REFERRED, never spawned at all.

**Readmission was upside-down.** Returners were seated at index 0, which is
each ward's only genuinely unwell hold. A held readmission earned nothing
while re-discharging one paid $150 and freed a $500 admission, so putting
right what you got wrong cost $650 against doing it again. And `is_flagged`
made every readmitted bed CONTRADICTED by construction, so the mechanic built
as the consequence of harming somebody took a third of your licence for
treating them.

### What the career is now

Vinnie is owed $15,500. He takes everything at eight, ten per cent goes on
what is left, and clearing it is the way out. Every night is scored — signed
off −1, noted 0, flagged +1, referred +3 — and at five the Board writes to
you. Measured over a whole career, eight policies:

```
never look at anybody ......... STRUCK OFF night 3, never pays off
hold three every night ........ STRUCK OFF night 3
one careless lie a night ...... STRUCK OFF night 4
lie every night, carefully .... STRUCK OFF night 7, $627 short
honest ........................ PAID night 9
honest + corroborated ......... PAID night 9
lie every OTHER night ......... PAID night 7
```

Crime pays if you can stop.

### And five smaller things the panel found

The last night of every career was a total amnesty (`ending()` checked
`paid_off` before `struck_off`). The honest social hold became indefensible
the moment anybody was in the room, because `_written_in_front_of_them` used
the body as a proxy for whether the note was a lie. The leading question used
one roll for both "will they stand behind it" and "do they remember whose idea
it was", so verb three of six was a trap in both branches. The doctor's record
scaled severity, which no bed state reads, so the whole escalation changed no
verdict, no money and no ending. And `backdated` was not in the contradicted
list and clamped at 0.45, so the headline two-timestamp mechanic could not
affect a verdict however far apart the two times were.

### A third ward, where nobody is ill

The first ward hides the honest hold in a diagnosis; the second in a body the
chart cannot describe. The third hides it in a **life**. Nobody on it is
medically unwell except a man who insists he is fine, and the two beds that
cannot be emptied cannot be emptied for reasons no investigation will ever
find — a boiler that went in November, and a nineteen-year-old psychiatry has
been bleeped about twice with no reply. The only verb that reaches either of
them is asking somebody how they have been and listening, which is the first
time that verb has been load-bearing.

And the best-paying bed on the ward is a woman who **asks you to keep her in**.
Rosalind Fry is well, premium, wants it, and will agree to any symptom you put
to her — and she remembers every word, and tells the ward sister in the morning
that she asked. Consent is the one defence that is not a defence. Saying no to
her costs nothing at all, which is what makes it a decision.

### The second career had no game in it

A career is nine nights and the cast was twenty people, so you already knew Ivo
Marchetti was the one who was genuinely ill. The whole investigation layer — the
twelve minutes a chart, the fifteen to go and look at somebody, the seventy-five
for bloods to come back — exists *only* to find that out, and on a second run
you skip all of it. The content was not too small. It was consumed in one run,
and every verb in the game turned into a formality on the way through.

So a ward is five **slots** now rather than five people, and `bed` is the slot
id: several authored patients share a bed number and exactly one of them is in
it tonight, drawn as a pure function of the career seed. Twelve new people, three
per ward, giving eight combinations a ward and 4,096 career shapes. Nothing else
changed — same four wards, same themes, same length of career, no new systems
and no new verbs. What changed is that you cannot memorise which bed is the
honest hold.

Candidates for a slot have to be **interchangeable by role**: same tier, so the
night is worth the same money, and same truth, so the honest hold is still where
the ward put it. The data check enforces both, which is what stops a draw
quietly dealing a ward with nothing genuinely wrong on it.

And because the game can now deal a board nobody has ever looked at,
`tests/probe/draws_run.gd` walks **every** combination on every ward — thirty-two
deals — plays each one the way somebody who understood the game would, and
asserts an honest day is never REFERRED and always covers the night.

### The draw was broken twice and looked perfect both times

First it was `hash("ward%d_bed%d") ^ seed`. With two candidates a slot the pick
is that value's bottom bit, and XOR only touches the bottom bit with the bottom
bit — so every slot on every ward flipped together on whether the seed was odd
or even. Four thousand careers on paper, two in practice.

Then it was a hash of the combined string, which should have worked: Godot's
String `hash()` does not reach the bottom bit well enough, and six seeds printed
side by side still showed two games.

Then splitmix64 — with the textbook constants, which do not fit in a signed
64-bit integer. GDScript mangles the literal instead of wrapping it, and the
mixer silently stopped mixing: wards one to three dealt identical fives for
every seed in existence while ward four varied, which looks exactly like a
content bug and is not one.

All three passed the tests, the data check and a play of the game. The only
thing that ever showed any of them was counting distinct wards across two
thousand seeds, so that is a permanent check now rather than something somebody
thought to do once.

### Where it stands

```
273 unit assertions · 70 smoke checks · 32 authored people · boot check
seven day-level criteria ................................ 7/7
every deal a career can make, played honestly ........... 32/32
distinct careers over 2,000 seeds ....................... 1,573
six career criteria ..................................... 6/6
adversarial frontier, 3,300 strategies over three wards . monotone on all three,
                                                          top figure unreachable
                                                          while signed off
```

### The measurement that was measuring nothing

The playtest has printed a risk/reward frontier for four iterations, ranked by
`res["cash"]`. Vinnie takes everything up to what he is owed, so against a
$15,500 debt that field is exactly 0 on every night of every career except the
last one. Thirty-one strategies were being ranked by a constant, in ties, and it
looked fine, because a sorted column of zeroes is a sorted column. The one check
that asks *does more money cost more exposure* had been comparing 0 to 0 since
the debt rework landed.

It reads what the day earned now, and it is a criterion rather than a printout —
the seventh. It fails if the spread goes flat, so a metric that dies again dies
loudly, and it fails if the biggest day in the table is also a clean one, which
is the moment honesty starts strictly dominating and the whole risk side of the
game goes decorative. Currently 1,750..3,450, best signed-off day 2,480, best day
of all 3,450 and flagged for audit.

Three smaller things, two of them found by looking at screenshots rather than at
tests: the ward connected to the clock twice whenever `start()` ran before the
node entered the tree (a red ERROR at the end of every headless run, there long
enough to read as furniture); a tannoy line that landed just before a modal
opened sat clipped in half behind the card for the rest of its timer, with the
HUD paused and unable to clear it; and the day label was only ever repainted by
`start_day()`, so any path that set `GameState.day` directly left the corner of
the screen a day behind — it now repaints on the clock.

And `test_all_scripts_compile` walked every `.gd` under `tests/`, including the
temp runner `check.sh` writes, so its assertion count wandered between runs —
271, 273, 275, 277, all green. A count that moves is a count nobody can read a
regression out of. What it checks is a naming rule now.

### NEXT UP

- A fourth ward would be the next content, and the shape not yet used is a
  ward where the honest hold is somebody ELSE's mistake — a patient another
  doctor should not have admitted, whom you cannot discharge without saying so.
- The registrar has hours and an opinion but no memory of being asked three
  times about people who turned out fine.
- Nothing is randomised, deliberately. If run-to-run variation is ever wanted,
  the honest place for it is which five of a larger written cast are in the
  beds — never generated conditions.


## Session 15 — 2026-09-04 — two adversarial audits, and looking at the game

Two things ran this session that had not been tried before: sixty-four and then
forty-seven agents reading the project adversarially against a brief of "find
what a player would hit", and — belatedly — a camera pointed at a person's face.

The audits produced ninety-odd claims, of which twenty-one survived
verification. What follows is the ones that changed the game rather than the
code.

### The two that were fatal

**A flagged night was a sentence.** Being watched doubles Adeyemi's rounds, and
the extra ones were placed at the MIDPOINT between two existing ones — which put
every round exactly ninety minutes from its neighbour. `ChartEntry.SAME_MOMENT`
is forty-five and the comparison is `<=`, so each round owns a ninety-one minute
window and those windows tiled the shift end to end. There was no minute in the
day at which a note could be written without reading as two people disagreeing
about the same half hour. Writing in the gap between rounds is the central
timing skill of this game; doubling the rounds was meant to make it harder and
instead deleted it, and since the findings that produces are what get you
flagged again, one bad night was a spiral with no floor. The career probe had it
in front of it the whole time — `skilled` and `one_lie` both went four rounds to
eight the night they were watched and were struck off on the next.

She writes up twice now, forty-five minutes after the first round rather than
splitting the gap. Three real windows survive and finding them is the point.

**Removing it inverted the premise**, which is what the probe is for: with the
spiral gone, lying one bed every single night became the FASTEST route out of
the debt — six nights against honest's nine. The spiral had been doing the work
of punishing persistent dishonesty by a mechanism that punished everyone
equally. So the escalation went where `DoctorRecord.opening_line` had always
narrated it: above three-quarters of nights carrying an uncorroborated bed, one
bed is a referral rather than a flag. The gap between that and the half-rate
`habitual` rule is the whole game — a bed on your word alone every other night
stays survivable forever, and that is the policy the design is trying to make
findable.

```
honest      9 nights      skilled   struck off, night 6
restrained  8 nights      one_lie   struck off, night 6
adaptive    7 nights      greedy    struck off, night 5
```

### The free win, and the punishment for putting it right

"Adeyemi reviewed them and agreed with me" was offered against
`sent_home_unwell` — a finding built entirely out of a nurse note saying the
patient should STAY. The strongest wrongful-discharge question in the game was
cleared by citing the document that proves it. Top option on the menu, no verbs,
no chart, no examination; FLAGGED became NOTED. Empty the ward at five past
eight, press the first button, go home, every night, forever.

The other way up: `readmitted_after_your_discharge` was in the CONTRADICTED
list, and that branch only ever runs for a bed you are KEEPING. So holding the
man who bounced back at one in the morning because you got it wrong was
automatically indefensible — examining him, sending the nurse and documenting it
scored exactly the same as re-dumping him. The file had already found and
excluded this identical bug three hundred lines earlier for
`already_being_looked_at`, on the same bed.

### They came back before they had gone home

`Cases.roster()` reads `READMIT_FLAG` live and `GameState.day` is not
incremented until "Work tomorrow", so writing that flag inside `end_day()`
readmitted people onto the ward they were still lying on — in time for the
handover, which runs after. She asked why a man discharged at six was back
before the night staff went home, his file went "already under review" so every
other finding about him was multiplied by 1.6, and the very next screen promised
he would be back in the morning. Two climax screens disagreeing by a night about
the same bed. The list waits in `READMIT_PENDING` now and `_carry()` promotes it.

### The biggest number in the game had no noun and did not add up

The morning card says "In your account $900" and thirty seconds later the corner
of the screen said $1,900 in green with nothing attached to it. It was also
arithmetic no ward could produce: `free_beds()` counted an undecided bed as free
and charged its $500 admission, while `discharged_ids()` counted only explicitly
marked beds, so the same bed paid no discharge fee. Sign off on that exact state
and it pays $2,650. An undecided bed is now counted the way signing off counts
it, and the figure is captioned IF YOU SIGNED OFF NOW — VINNIE TOOK, after eight.

`WardDay.sign_off()` gives "ending the shift" one definition; the eight o'clock
close and the office terminal each spelled the loop out for themselves.

### Everybody in the ward was the same person

`PatientSystem._spawn` passed `p.skin_tone` and `p.shirt_color`, and nothing in
the game ever assigned either field. Forty authored people, one body: same skin,
same gown, same brown hair, same height, five at a time in a row. `PatientNPC._ready`
then overwrote the gown with a fourth hardcoded colour anyway.

`Appearance` derives a look from the id and the age — twelve skin tones, nine
hair colours greyed toward white by age, height and girth varying independently
so nobody is a scaled copy, hair that thins rather than vanishing. Forty distinct
people out of it. `age` had been in every record since the beginning and nothing
read it. Facial hair is authored rather than rolled: skin and build are
interchangeable at this fidelity and a hash is the right tool for them; a beard
is a fact about somebody.

The named staff were worse than uniform — `_random_skin()` drew from the
world-seeded RNG, so Adeyemi had a different face every playthrough and Ms
Ferrand turned up for her second booked shift looking like somebody else.

### And the reason nobody had noticed

The two screenshots meant to photograph a person asked for "oduya", and the shot
harness starts a career on a seed oduya is not on. `get_body` returned null, the
function returned, and the camera stayed where the previous shot left it. The
only two frames meant to show a PERSON had been silently photographing the wide
ward view for as long as they existed.

With a face on screen for the first time, two things were obvious immediately.
The eye whites were 0.056 scaled 0.92 by 1.18 — an egg on its end, pure unshaded
white, spanning the whole face with a small dot in the middle: everybody in the
building was wearing swimming goggles. And the floating nametag was a metre and
a half of text at the distance you stand from a bed.

The title screen had never been photographed at all, because the harness
instantiates Game.tscn directly. It had a man sitting INSIDE the bed (posed with
the waiting-room `set_seated` on a body standing at floor level on top of a
PatientBed) and the only unstyled control in the game.

### Everything else

- **Half the ward was misgendered.** Six strings had a pronoun welded in — the
  self-discharge toast said "signed herself out" about whoever walked, and five
  of the reviewer's questions said "him" or "her" regardless. A ward is five
  people drawn from forty. Every patient carries their own pronoun now, read off
  their OWN authored prose, and three whose prose commits to nothing keep
  they/them. `Cases.about()` fills the sentence and agrees the verbs.
- **The game taught you the first verb for six seconds, behind a card.** Toasts
  aged whether or not a modal was up, so the one line telling a new player what
  to do first expired before they pressed "Start the round". A lab result landing
  behind a chart died the same way.
- **Two hundred and fifty passes of the same eight bars.** The score is an A A B A
  form now, ninety-four seconds, with the lead tacet through the second pass and
  the brushes pulled back — length alone would have bought nothing.
- **An authored question no play could reach.** `ChartEntry.explains` had no
  writer anywhere, so `_addendum_cascade` could never fire. Writing the same
  claim about the same patient again is what an addendum is, so the chain builds
  itself.
- **Rooms were boxes with lids.** Two-metre vinyl seams on the floors, a 1.2m
  tile grid on the ceilings, and real joinery on the station counter.

### What the harnesses could not do

- `check.sh` could not fail. The last command in its pipeline was `head`, so it
  exited 0 on every parse error it has ever printed — including one of mine,
  which is how a duplicate function name reached a screenshot run.
- Three tests aborted mid-function without failing, all the same trap: reading a
  missing dictionary key, `String(null)`, `String(int)`. CLAUDE.md 11 is not
  only about freed objects — anything that throws inside a test silently ends it
  and the count barely moves.
- A test that compares `projected()` with `end_day()` compares a number with
  itself, because `end_day` computes its takings from `projected()`. It passed
  just as happily on the broken arithmetic.

### New guards

Everything above that could recur has one, and each was verified in both
directions:

```
a watched day still has a writable window .... contains one unbroken gap after
                                               her first round long enough to
                                               read a chart and write the note
nothing floats or sinks ..................... lowest point of every fixture that
                                               must rest on something is within
                                               2cm of the surface under it
nothing stands in a door's arc .............. against each door's real hinge and
                                               width; found four on first run
a readmission waits for the morning ......... no bounce finding on the night of
                                               the discharge; there in the morning
the HUD's money is the money you get ........ through sign_off(), not end_day()
nothing is said into a closed card .......... a toast raised behind a card is
                                               still there when it closes
nobody is misgendered ....................... data AND a grep over the strings
the score has a form ........................ four passes do not render alike
```

### Counts

```
unit + integration assertions ........................... 292
smoke checks ............................................ 125
seven day-level criteria ................................ 7/7
six career criteria ..................................... 6/6
authored people ......................................... 40 across four wards
screenshots ............................................. 22, including the
                                                          title screen and a
                                                          five-head lineup
```

### NEXT UP

- The registrar still has no memory of being asked three times about people who
  turned out fine.
- `VisitorNPC` exists and is never instantiated; the visitors are narrative-only
  toasts. Either give them bodies or delete the class.
- The overlap audit named in CLAUDE.md does not appear to exist under that name
  any more. The floating and door-swing audits cover part of what it did.


## Session 15, later — the harnesses, and the documentation

The audit findings ran out around here and what was left was to go looking. Most
of what follows was found by pointing an existing tool somewhere it had never
been pointed.

### Three of five seeds were untested

A ward is five people drawn from a pool of ten per day, so the first ward alone
can deal thirty-two boards. Every check in `smoke_impl.gd` named its patients —
"oduya", "marchetti", "kerrigan", "brennan", "blake" — so the whole file, 131
checks building a real world with a real UI, could only ever run against one of
them. Pointing it anywhere else produced eight failures and all eight were the
harness naming somebody who was not there.

Exactly the same defect as the shot harness asking for "oduya" on a seed oduya
is not on, and it hid the same way: a check that cannot run looks like a check
that passes. `SMOKE_SEED=n` points it anywhere now; nine seeds pass; the suite
runs three every time.

Two of the fixes are worth keeping the note for. The test-result check ordered
bloods on the first bed and asserted NORMAL — and on some wards the first bed is
the genuinely unwell one, whose bloods correctly come back abnormal. And
`_someone_unwell()` has to skip `only_visible_in_person` and `colleague_wrong`,
because Gwen Ashworth is the whole argument of the fourth ward: the nurse goes
and finds nothing and writes that down.

### A probe that asserted something false about a quarter of the content

The frontier search reported "signed off — never reached" on the fourth ward and
printed "no clean day exists on this ward" underneath it. That is a claim about
the ward, made from a fact about the search. The ward can be signed off.

Writing the honest day out by hand took four goes and each one was the ward
teaching me what it is for:

```
look at everybody, hold the two who are ill     FLAGGED  no reason recorded
...and write it up                              FLAGGED  invited_contradiction 0.95
...bloods for the kept, nurse for the sent home FLAGGED  invited_contradiction 0.60
...and don't ask a man who has already told you SIGNED OFF, 3,650 of a 4,350 top
```

Every one of those traps is legible on the chart, which is what makes the ward
fair — and none of them is legible to a search that applies every verb to every
bed. All four wards sign off on the honest day now, and that is a criterion.

### Two probes that printed FAILED and exited 0

`career_run.gd` and `frontier_run.gd` both end by printing PASSED or FAILED in
capital letters, and both called `quit()` with no argument. Same shape as
`check.sh` not failing on a parse error, and the reason neither was in
`run_tests.sh`: they could not be, because they could not fail. Both are in it
now. The career probe is under a second and is the only thing that catches a
balance inversion — it caught one this session, and it was not running with the
suite at the time.

### The documentation described a different game

`README.md` opened with "You are $435,000 in debt and you make $240 a shift",
explained that complications are the product, listed Ambient Dread and Ferrous
Aura, described a nine-rung sanction ladder and a shredder, and pointed at six
system files deleted several reworks ago.

`docs/SPOILERS.md` was worse, because `CLAUDE.md` points at it as the
developer-facing truth. It documented treatment-machine dials, complication
chances per deviation band, substances, upgrades, and a statistical review team
firing at 1.6x a 0.34-per-discharge baseline — which I had deleted from the code
earlier the same night, for the same reason.

`docs/REDESIGN.md` had drifted rather than rotted: $2,400 owed against a $2,200
debt, an $850 admission against a $500 one, and a worked example running to
23:10 on a day that ends at eight. Its "honest ceiling" was $2,650, which is
what emptying the ward pays — but the honest day KEEPS the people who are ill,
so the frontier probe measures it at $2,950 to $3,650. Honesty does not pay by
$100 and tightly. It pays by a thousand, and what it costs is that you send home
an 81-year-old who has nobody because she is well and you have nothing to write.

README and SPOILERS rewritten, DESIGN deleted, REDESIGN corrected. This is not
hypothetical: the session lost real time to `VisitorNPC`, and the docs are what
somebody reads before the code.

### And somebody is finally in the room

`VisitorNPC` was 115 lines never instantiated anywhere, and broken with it —
`_visit_bark` read `p.overdue_days`, which is not a property of `Patient`, so
reading it aborts the function and the half that produces evidence could not run
even if something had built one. Meanwhile "Ruth Kerrigan is here to see her
mother. She has brought a flask." has printed at seven o'clock since the line
was written.

Three patients have a family authored and every one names the hour out loud in
their own prose. That hour is a field now, the toast is built from the
`family_note` that was already written and only a review finding ever used, and
`_who_can_see_me` walks every registered mind — so standing her at the bedside
makes a note typed in front of her a note she saw, with no new machinery.

### The rest

- **Everything hovered.** Compatibility has no SSAO, so nothing had anything
  underneath it. Contact shadows, synthesised like the audio. Two wrong turns:
  multiply is the right blend and Compatibility ignores the albedo texture under
  it, which renders as a hard black rectangle and looks like a geometry bug.
- **Adeyemi wrote the same sentence four times.** The round line was picked from
  the patient id alone, deliberately — and produced four identical notes stacked
  on the chart screen. Eight lines of each now, because a flagged night has eight
  rounds on it.
- **Signing off dropped the whole ward out of their beds.** Patients are pinned
  half a metre up; standing them up unpinned them and let gravity do the rest.
  Normally half a second nobody sees — except at eight o'clock, when the handover
  card pauses the world and freezes five people mid-fall behind it.
- **A third of the patient screen's verbs were below the fold**, because every
  row was a panel wrapping a button that already had its own bordered panel.

### Counts

```
unit + integration assertions ........................... 292
smoke checks ............................................ 131, on three seeds
day-level criteria ...................................... 7/7
career-level criteria ................................... 6/6
wards that sign off on the honest day ................... 4/4
screenshots ............................................. 23
```


## Session 15, last stretch — telling the player things

Three of these are the same finding wearing different clothes: the game knew
something the player needed and did not say it.

**The day ended without a word of warning.** At eight o'clock every undecided
bed is sent home, the shift closes and the handover opens — and the first thing
the game had ever said about it was "Eight o'clock. He is in the corridor.",
after it had happened. The clock is in the corner so it was never hidden, but a
game whose whole pressure is a deadline should count down to it. An hour out,
twenty minutes, five, and the useful half is not the time: it is how many beds
are still undecided, which is the one thing the player cannot see without
opening something.

**The rounds were silent.** Writing in the gap between them is the central
timing skill of this game and they made no sound and put nothing on screen. The
board lists the times; this is the beat. It is also the only way a watched day
reads as what it is — the card says "she is writing her rounds up twice" in
words, and words on a card at the end of a night are not the same as noticing,
twice as often, that she has just been round again.

**Missing the registrar's window was silent.** He is the strongest corroboration
a bed can have and he is here for four hours of twelve. The patient screen says
when he is next about, which only helps if you happen to be looking at a
patient, and the window you want him in is usually the one you are busy in.

That last one had a bug the check caught, and it was the wrong one to have: the
"first evaluation of the day says nothing" guard sat AFTER the no-change test,
so the early return fired on every quiet minute and the guard was reached by
the first real TRANSITION instead. Eleven o'clock — when he actually arrives —
was the one arrival that went unannounced.

And a consequence: the day now has ten or more things to say, the queue holds
while a card is up, and half a second between toasts is wrong the moment there
is a backlog. Close a card on ten of them and the last arrives five seconds
later, by which point the first three have been pushed off the bottom of a
column that holds three. A backlog drains at 0.18; a trickle still at 0.5.

### The career probe had only ever played one career

Nine wards drawn from four pools of ten, and it had only ever played the nine
that seed 31337 deals. Twelve seeds pass by hand — all six criteria on every
one — and two run with the suite. Same gap the smoke run had, and that one hid
three untested seeds in five.

### Counts

```
unit + integration assertions ........................... 292
smoke checks ............................................ 136, on three seeds
day-level criteria ...................................... 7/7
career-level criteria ................................... 6/6, on three seeds
wards that sign off on the honest day ................... 4/4
the game says nothing it should not, while being played . asserted
```

## Session 15, the input layer — "a pad works without setting anything up"

The Controls screen has said that sentence for months. It was not true, and
nothing in the project could have told anybody, because every harness in
`tests/` reaches PAST the input layer: the smoke run calls `w.write_entry()`,
the playtest calls `w.set_disposition()`, the screenshot run calls `ui.open()`.
All of them pass on a build where nothing is bound to anything.

### What was actually wrong

Three things, and each of them is the whole feature for somebody:

1. **The left stick did nothing.** Walking is `Input.get_vector` over four
   ACTIONS, and those four actions had one keyboard event each and no axis.
   Looking is read straight off `JOY_AXIS_RIGHT_*` in `Player._handle_pad_look`,
   so that half worked — which means a player with a pad could turn all the way
   round the ward, in both axes, smoothly, and never take a step. The most
   convincing possible version of "the controller is supported".
2. **No screen in the game ever took focus.** Godot navigates a Control tree
   with `ui_up`/`ui_down`/`ui_accept` for free and every Button is focusable by
   default — but navigation starts from whatever holds focus, and nothing ever
   took it. So the D-pad moved a selection that did not exist.
3. **A and B were not bound to `ui_accept` and `ui_cancel`.** Godot's own
   defaults are not symmetrical: `ui_up`/`ui_down`/`ui_left`/`ui_right` ship
   with the D-pad AND the left stick on them, and `ui_accept` ships with Enter,
   Kp Enter and Space. So even with focus, there was no button that pressed the
   thing you had selected and none that backed out of the card.

Fixed in `Settings.PAD_AXES` (the left stick, as axis events rather than a
`get_joy_axis` read, so the deadzone and `get_vector`'s circular clamp work on
it exactly as on the keys), `Settings.PAD_UI` (A and B), `UIKit.focus_first`
(reading order, never steals from a control that already has focus) called from
`ScreenBase`, `UIRoot.open` and `MainMenu`, and a visible focus stylebox on
every button — Godot's default focus outline against paper-coloured card on a
paper-coloured screen is invisible, so the selection could have moved without
anybody being able to see that it had.

`ui_cancel` closes an open screen but deliberately does NOT open the pause menu
when nothing is open: B is also crouch, and every crouch in the ward would
otherwise stop the game.

Deadzone dropped from the editor default of 0.5 to 0.2 on the four move
actions. Half the throw of a stick doing nothing at all costs nothing on a key,
which is 0 or 1, so it was invisible until the stick was wired up.

### The harness that would have caught it, and had been dead for three sessions

`play.sh` and `playfast.sh` both ran `res://tests/play_run.gd`, which was
deleted with the world it tested. They printed an engine error and **exited 0**,
which is CLAUDE.md 21 in miniature: a harness that cannot fail.

Rebuilt as `tests/play_run.gd` + `tests/play_impl.gd`, with two plans:

- **`pad`** — a controller and nothing else. Closes the briefing with A, walks
  the doctor across the ward on the left stick, aims with the right, taps X to
  open the card, moves the selection with the D-pad, backs out with B. Runs
  headless, and is in `run_tests.sh`.
- **`keys`** — WASD, a real mouse and [E]. Mouse look needs a captured cursor,
  which the dummy display driver will not give, so this plan says so and stops
  rather than passing by doing nothing. `./play.sh` runs it under Xvfb, where
  the capture is real and it passes all twelve checks.

Two things it taught immediately. `Input.action_press()` dispatches NO
InputEvent — it sets the polled state an `is_action_pressed()` reads and
nothing else — so the first version could not close the morning briefing and
nothing in the UI could hear it at all. And `NavigationServer3D`'s map is empty
in this project: the building is procedural and headless and navigates on its
own A* grid, so asking the server for a route returns a zero-length path with
no error, which reads exactly like "there is no way into the ward". The doctor
walks the route `Hospital.nav` gives the nurses, and steers and walks it on
real input.

### Two settings that were read by nothing

`show_damage_flash` — a setting for a health bar, in a game that has never had
one. Deleted. `pad_vibration` — saved, restored, defaulted, read by nothing.
Now wired to `Player.shake()`, which is already reserved for the handful of
beats the game wants you to feel rather than read, so the rumble rides on the
same call instead of becoming a second thing to remember.

And a check, so the next one is found by the suite rather than by grep: every
key in `Settings.DEFAULTS` must be read by something in `scripts/`.

### And the focus code found its own bug on the way in

A card rebuilds itself after every action taken on it — and `rebuild()` freed
every control and DEFERRED the rebuild, so the deferred focus grab ran while the
old buttons were still children and put the selection on one that was already
queued for deletion. A pad player could open a card, press one thing, and find
the selection gone with no way back to it except a mouse.

Then the fix for that could not run, for the reason this project has written
down twice: `gui_get_focus_owner()` returns the freed control, and reading it
into a TYPED local raises "Trying to assign invalid previously freed instance"
and ABORTS the function (CLAUDE.md 11). `rebuild()` now removes children from
the tree before freeing them, and `UIKit.focus_first` reads the owner untyped
and tests it with `is_instance_valid`.

`smoke_impl.gd` grew the `_defer(n, callable)` helper CLAUDE.md has claimed it
had for two sessions — an assertion made in the same frame as its setup reads
last frame's value, and a rebuilt screen has not laid out yet. The run refuses
to report while one is outstanding, so a check that never comes due is a
failure rather than a quietly smaller number. Verified by inverting the
assertion and watching the suite go red.

### The quiet check was only watching half the game

It greps what the SMOKE run prints, and stops there — so the unit run had been
printing `Cannot call method 'queue_free' on a previously freed instance` twice
on every single invocation, for as long as anybody has looked at it. Two tests
take a SECOND day, `_day()` calls `setup()`, and setup frees every WardDay in
the tree — so the tidy-up line at the bottom freed a ward that was already gone,
threw, and (CLAUDE.md 11) aborted the function before the line that freed the
ward it actually had. Both of them leaked the thing they were cleaning up.

Fixed with a guarded `_drop()`, and the quiet check now reads both runs. The
lesson is the one this project keeps relearning: a harness that watches one
surface reports on one surface, and everything green everywhere else is not
evidence about the surface it is not watching.

### The game was pillarboxed on every monitor that is not 16:9

`display/window/stretch/aspect` was never set, so Godot's default of `keep`
applied: the whole game pinned to 1600x900 and black bars down the sides of
anything wider. On a first-person 3D game that reads as a game that does not
know what monitor it is on, and ultrawide and 16:10 are most of a Steam
library's laptops. Set to `expand`, and checked by rendering the whole
screenshot set at 2560x1080: the camera sees more of the room, the HUD plates
stay in the corners they are anchored to, and the cards measure themselves
against the real viewport exactly as they did.

Which is how the next one turned up. The patient card is a sheet pinned to the
RIGHT of the screen and the controls reminder is anchored to the bottom-right
CORNER, so with a card open the only part of that line visible was the last
three letters of "pause" poking out past the card's left edge — on every
monitor, at every aspect, for as long as both have existed. It reads as a
rendering fault, not a hint, and it is the least useful moment for it: what
[E] does in the world is not the question while a form is up. The HUD hides it
with the subtitles, on the modal signal it already had.

`shot_impl.gd` now measures it: for every card it photographs, it intersects
the sheet's rect with every visible HUD label and panel and prints
`[UNDER THE CARD: ...]`. Only measurable there — under `--headless` the root
window is 64 pixels tall and every global rect is nonsense (CLAUDE.md 19).
Verified by putting the bug back and watching three screens report it.

### A group lookup for a group nothing has been in since the redesign

`get_first_node_in_group("codex")` in `StaffNPC`, guarded by `if cdx:` — the
Codex went with the rework and the two lines have read as a working feature to
everybody who has scrolled past them since. The same silent nothing as a call
to a method that is not there, and now found the same way: the smoke run greps
every group name the source looks up and asserts something is actually in it.
Eight groups, all live, and the check goes red if one empties out.

### Four places told the player to press a key that might not be that key

This game has a rebinding screen AND a controller layout, and the HUD's corner
reminder was the only thing that read the InputMap. The carry prompt you see
while holding something said "[RMB] throw   [LMB] drop"; the hold-to-use prompt
said "hold [E]"; the title screen said "WASD move · E use · LMB grab". A player
who moved "use" to F was told to press E for the rest of their career by three
different parts of the game, and somebody on a pad was told to press E by all
four.

`Settings.prompt_label(action)` is the one honest answer and it prefers the pad
when one is plugged in — deliberately a different function from
`binding_label`, which is what the rebind rows under "KEYBOARD AND MOUSE" show
and must stay a key even with a controller connected.

The smoke run greps for `[E]`, `[LMB]`, `[RMB]`, `[Escape]` and `WASD` in any
non-comment line of `scripts/` now. It found the fourth one — "hold [E]" — a
minute after it was written, which is the entire argument for writing it.

### Interface size

The text IS this game: a chart, a board and an argument about a document. Every
card was built at one size for one viewport and there was no way to make any of
it bigger. `content_scale_factor` scales the canvas layer and leaves the 3D
viewport alone, which is exactly the right knob — the ward stays the size it is
and the paperwork grows. 80% to 140%, under DISPLAY, checked by rendering the
patient card at both ends: at 140% the card stays on the screen and its list
scrolls, at 80% the whole list fits without scrolling at all.

### The crosshair kept talking from behind the card

The patient card deliberately does not pause the world, so the interactor keeps
raycasting while you read it — and kept emitting the bedside prompt for the
very person the card is about. A crosshair label with no crosshair under it
(the crosshair is hidden by the modal), saying at a glance what the form beside
it says at length. It goes down with the subtitles now, on the modal signal the
HUD already had, and a new smoke check emits a prompt by hand while a card is
up and asserts it stays down — "it was already hidden" is not the assertion.

And the screenshot harness measured its two layout numbers only when the shot's
NAME began with a 1, which happened to cover 10 through 19 and left
`20_struck_off` — one of the two endings, the last thing a career shows
anybody — unmeasured. It measures whenever there is a card up.

### Half the settings screen could not show you where the selection was

The focus box was written for Buttons. A slider takes the FIRST focus on the
settings screen and Godot draws nothing on an HSlider that can be seen against
a paper card, so a pad player opened Settings, pressed a direction, and had no
idea what they were about to change. The toggles were worse in a quieter way:
they DID override a focus stylebox, painted from the same colour as the normal
one, so a selected toggle looked exactly like an unselected one.

Both rows now sit in a panel that lights up with the margin rule down it —
the same mark a focused button carries. Which turned up an alignment bug at the
same time: the toggle rows had been sitting eleven pixels left of the slider
rows on the same card, because only one of the two was inside a panel with
content margins. Both boxes carry identical content margins so nothing moves
when the selection arrives.

### The selection walked off the bottom of the page, and "press a key…" had no way out

`ScrollContainer.follow_focus` defaults to FALSE, and every long card in this
game is a scroll region — the settings screen, the key bindings, the list of
verbs on a patient. So a pad or a keyboard walked the selection off the bottom
of the visible area and kept going with nothing moving on screen, which is
indistinguishable from navigation not working at all. Watched go from a scroll
offset of 0 to 143 under Xvfb once it was on, and asserted as a property in the
smoke run, because under `--headless` no layout is real.

And pad bindings are deliberately fixed, so `Settings.rebind` refuses a joypad
event: somebody who pressed A on a binding row got "press a key…" and, with no
keyboard in reach, nothing that would end it — B is not a key either, so the
row listened for ever. Any pad button backs out of it now. Closing the screen
also disarms it, which only `Back` and `Reset` had been doing by hand, so
Escape mid-rebind left the next visit already waiting for a key nobody had
asked it to want.

Fixing that introduced its own bug and the check caught it: `_start_listening`
rebuilds the screen by closing and reopening it, so clearing the flag on close
unset the thing that had just been set and no row listened at all. Close first,
then arm.

### A whole shift, with nothing but a controller

The `day` plan. Walk to all five beds, open each card, move the selection to a
decision and press it; then find the office through a shut door, open the
records, sign off, and answer the ward sister until the End of Shift card is on
the screen. Nine checks, three seconds, and it is the only thing in this repo
that asserts the game can be COMPLETED rather than merely started.

It plays it as a STRANGER would, too: every other harness in this repo sets
`tutorial_done` at boot and has therefore never once been through the three
lines a new player is actually shown. The day plan does not — and reads a chart
and writes a note on the way, on the pad, which nothing had ever done through a
keypress either (every other harness calls `w.write_entry()` directly). Two
verbs, four screens, and the tutorial keeping up behind it.

It goes one screen further than the shift: "Work tomorrow" is the only thing
that advances a career, and the join from one day to the next is what has
broken most often in this project — so the plan presses it and asserts the day
number moved and the next morning's briefing is on the screen. Eleven checks in
all.

Six things it found on the way to passing, all of them harness bugs and every
one of them the kind that would also have been a player's problem:

- **Aiming was yaw only.** Fine for a patient, whose head is at eye height.
  The office terminal sits on a desk, so the ray left the camera horizontally,
  passed over it and hit the door behind — the doctor stood 1.6m from the thing
  that ends the shift with the crosshair offering to open the door they had
  just walked through, for three attempts and two thousand frames.
- **A press is not a result until the frame after it.** Counting the decision
  in the same tick that pressed the button read the state from before the
  press, on every bed: five decisions made, "0 of 5" reported.
- **Stuck is something to get out of.** A person who catches the corner of a
  bedside table backs off and goes round it. The first version walked into it
  and stayed there, and reported the building as impassable. Three goes:
  reverse, lean to one side, re-plan.
- **Stuck at the end of a column is not the same as not there.** Godot works
  focus neighbours out geometrically, so `ui_down` from the last control on a
  card moves nothing — a seek that only presses down sits on "Close" pressing
  it forty times. It turns round now.
- **"Go home" is the crosshair; the button says "Sign off for the night".**
  Forty presses looking for the wrong words.
- **The office has a door on it**, and the walk ended at the desk's radius with
  the door still shut in between. It opens doors on the way now.

And one real one, in the game: the door's own prompt read "[Shift+E] slam it"
— the fifth hardcoded key in a build with a rebinding screen, and the only
place in the game that mentions the sprint modifier at all. The grep missed it
because it was looking for "[E]" and this is "[Shift+E]". Both shapes now.

### Two flaky checks, found by sweeping seeds rather than repeating one

A green suite on three seeds is not evidence about the fourteenth. Fourteen
smoke seeds and seven career seeds later, two checks were wrong rather than the
game:

**"Writing in your own office is not observed"** compared the TOTAL evidence in
the building either side of eight office writes and demanded it not move. But
the half of the check above it has just put eight observations into somebody's
head, and `_gossip_pass` retells those to everybody else for the rest of the
shift — so on a seed where the gossip happened to land between the two
readings, the total grew with nobody having seen anything, and the check
reported the office as public. It counts WITNESSED evidence on both sides now,
which is what "nobody sees you in there" actually claims; hearsay about
something else is not a counterexample.

**"A card opens with a selection on it"** passed and failed on the same seed,
run to run. The patient card offers no verbs once the shift has ended —
correctly; there is nothing left to do about anybody — and by the time that
check runs the day may or may not be over, depending on where the clock got to.
It was reporting "no selection" about a card that genuinely had nothing to
select. It asks the records terminal, which always has a Close on it, when the
ward has closed.

Fourteen smoke seeds and seven career seeds pass now, repeatedly.

### Two ways to press [E] on somebody and have nothing happen

Both found by sweeping the day plan across twenty wards it had never played.
`PLAY_SEED` now points it at any of them.

**A person standing in a doorway could not be spoken to.** Patients get up and
wander, and one of the places they stop is the ward doorway — where the
crosshair finds the door instead. `_prefer_person` already overrules a loose
prop for exactly this reason (an IV stand beside every bed was stealing the
most important interaction in the game), and it deliberately did NOT overrule a
door, on the grounds that a door is a thing you aim at on purpose. That
reasoning is right for an empty doorway and wrong for one with somebody in it,
and the tie-break is in the door's own prompt: "or just walk into it". A door
can always be opened by walking into it, so nothing is lost by letting a person
in front of it win.

**A tap on somebody who takes a step did nothing.** A patient has
`interact_held`, so the tap only fires on the way UP — and `_handle_use` reads
what is under the crosshair on the release frame. Somebody who moves during the
0.42s of the tap takes the crosshair with them, `_cancel_use()` runs, and the
release goes nowhere: no sound, no card, no message. Exactly the "I pressed it
and nothing happened" that makes a game feel broken, and it is most likely with
the people who are most interesting to talk to. It acts on the thing you
PRESSED on now, while the press is in flight and while they are still within
arm's reach — walking away yourself still cancels, which is what walking away
means.

The harness learned two things too: keep aiming at somebody while you close the
last few frames on them, and take another step and try again rather than
reporting a bed as unreachable because a chair was in the way.

### The settings card was 720 tall in a 900-tall window

Twelve rows, and three of them plus the entire DISPLAY heading — where the new
Interface size slider lives — were under the fold. The viewport is a fixed
1600x900 in canvas units whatever the monitor is, so 830 is safe on every
machine and leaves thirty-five pixels top and bottom. Same for the key
bindings, which is ten rows and a paragraph about the pad.

### CLAUDE.md

Corrected against the code: the counts, forty people across four wards rather
than thirty-two, the testing table (eleven layers, and the "overlap audit" row
described a check that does not exist under that name — what is actually there
is a fixture audit that catches anything standing on nothing). The two numbered
lists that both started at 14 are now one sequence, and the second has its own
heading. Five new gotchas, four of them from tonight.

### Counts

```
unit + integration assertions ........................... 294
smoke checks ............................................ 161, on three seeds
input-layer checks ...................................... 12 on a pad, 12 on keys
day-level criteria ...................................... 7/7
career-level criteria ................................... 6/6, on three seeds
wards that sign off on the honest day ................... 4/4
the game says nothing it should not, while being played . asserted
```

## Session 16 — 2026-09-04 — "it just looks like low quality"

One note, and it is about the picture rather than about the game: *make the
graphics higher quality*. Everything below was found by rendering the real ward
at 1600x900 under Xvfb on the renderer this project ships, looking at the
result, and measuring it when looking was not enough. Nothing here is a guess
about what a renderer does; six of these were the opposite of what the code's
own comments claimed.

### Every flat surface in the building was shaded with sphere normals

`rbox_mesh` and `taper_mesh` build a Minkowski sum — take a sphere, push its
vertices out to the corners of a box — and handed the result to the renderer
WITH THE SPHERE'S NORMALS STILL ON IT. So every flat face of every object in
the game, from a twenty-metre ceiling to a bedside cabinet, was shaded as
though it were curved: the normal across one flat wall wandered by up to 22
degrees and the wall rendered as a soft radial blob, brightest somewhere near
its middle, with no light source that explained it.

That is the single largest reason the picture read as a smudge. Nothing in the
frame was a plane, so nothing in the frame could be crisply lit, and every
attempt at lighting landed on geometry whose shading was already wandering.
`Build._reface` recomputes them: area-weighted, accumulated onto SHARED
vertices — sharing matters twice, because the cel outline is an inverted hull
grown along these same normals and only stays closed if the vertices it grows
from are shared.

### The ambient was an order of magnitude out, and the wall paid for it

With the normals honest the ward went honest too, and showed what it had: a
wall gets what actually lands on it, and in a room lit by downward-facing
ceiling fittings that is almost nothing but ambient. There is no global
illumination on the Compatibility renderer. Measured, not guessed: a cream wall
in the ward reads (113, 124, 129) at ambient 0.62 and (195, 197, 194) at 3.0.
0.62 was tuned against the sphere-normal build, where every surface picked up
light from directions it did not face and hid how little of the room the lights
were reaching. It is 1.15 now, which is where the grade sweep below left it.

Two rounds were wasted first on `ambient_light_color`, which is not the knob:
warming it changed nothing visible, because the blue cast on the ward's
left-hand wall is a cool DirectionalLight3D fill and not the ambient at all.
`ambient_light_sky_contribution` is set to 0.0 as a statement of intent and was
measured to be a no-op with AMBIENT_SOURCE_COLOR on this backend.

### `ShaderMaterial.duplicate()` silently loses every parameter

The lighter-lined variant of a material was made by duplicating it and
replacing the outline pass. The copy renders with the shader's DEFAULTS: every
steel bed leg and the orange visitor chair came out cream-white, in a build
that otherwise looked like an improvement. Nothing errored. `_fit_line`
REBUILDS from a recipe recorded on the original instead, and `Surfaces` grew a
`shared` flag so `Build.mat` gets a material it is allowed to write to — two
call sites asking for the same grey with different line weights used to be
handed the SAME material and the second one's next_pass silently replaced the
first's, so a 4cm rail and a 40cm cabinet could never have had different lines.

### The cel line: measured, not argued about

A sweep that re-tinted every outline material in the live ward and photographed
the same bed under each showed that pure black and a per-object ink are
indistinguishable — the line was not too PALE, it was too THIN. `LINE_GAIN` is
0.66 rather than 0.22 and the ink is a deep version of the object's own hue,
pulled a third of the way to one shared cool near-black so the drawing still
looks inked by one hand.

The gain and the per-object cap have to be chosen together, and were not the
first time: trimming the cap from a fifth of the thinnest dimension to 0.14
"so the two move together" cancelled the gain EXACTLY on every panel under
about eleven centimetres, which is most of what a bed, a cabinet and a chair
are made of. The frame came back looking like the one before it and it took a
render at ten metres to see that nothing had changed. The cap is back at a
fifth and the gain went to 0.66, which is three times where it started.

The line is also fitted to the object now. It grows outward in every direction,
so on a thin object it eats the object: a 5cm handrail with the standard weight
is about a third ink at three metres, which is why the corridors were full of
black bars and the drip stands were black sticks. `_fit_line` trims it using
the mesh's own recorded thinness — recorded at build time, because
`Mesh.get_aabb()` queries the RenderingServer and returns nothing useful under
the headless driver every test in this project runs on.

### `Hospital.set_lamp_look` worked, and had no caller anywhere

Nor did the daylight move: `apply_shift_look` reads `GameState.minute_of_day`
and was called only when a shift STARTED, which is always eight in the morning
— so `warmth` was always zero, the sun never moved, the sky never changed, and
a function that lerps five things across twelve hours was a constant. In a game
whose entire pressure is the evening arriving, the ward sister's eight o'clock
and the last hour of a shift were lit by identical bulbs.

It runs off `minute_passed` now and drives the fittings too: they go warmer and
a little stronger as the daylight goes, which is what actually happens in a
building — the interior lighting does not change, the balance does. The fitting
re-tint also handed the lit panel `Build.unshaded`, which is not emissive, so
re-lighting the ward at any point would have quietly taken the one object in an
interior that is supposed to bloom out of the glow pass.

### Six things that were not what the file said they were

- **The ceiling fittings were not lights.** One OmniLight with shadows off per
  five metres, and a slab of geometry that was not attached to it. They are a
  shadowed SpotLight (frustum points away from the ceiling, so the ceiling
  cannot acne, and one shadow map instead of a cube) plus an unshadowed omni
  fill, because a cone has an edge and a room does not.
- **The fitting hung 14cm below the ceiling** it is recessed into.
- **The whiteboard's writing surface stood 17mm proud of its own frame.**
- **The bedside cabinet had two handles and no drawers** for them to be on.
- **The bed stood on four bare sticks.** Hospital beds have castors.
- **The doorways were holes where two wall boxes stopped.** They have linings.

### Surfaces, and the things that had none

`Surfaces` is procedural fragment shaders keyed off world position: no
textures, no UVs (which matters — `rbox_mesh` is a Minkowski-summed sphere and
its UVs tile like nothing on earth), continuous across separate meshes that
meet. Floor, wall, ceiling, fabric and prop. The fabric one had been written
and called by nothing at all, so the curtains, the bedding, the gowns and the
upholstery were every one of them a flat colour on a ward that had just been
given a speckled floor.

The floor now takes the room's own rect and darkens as it approaches each wall,
which is the other half of the contact shading the wall already did on its own
side. Without it the wall darkened toward the floor and the floor stopped dead
at the skirting, so the two planes still met in one hard ambiguous line.

### The wall shader had never compiled

`Redefinition of 'drift'`. The shared preamble declares `varying float drift;`
for every surface in the file, and the wall's fragment stage declared a local
of the same name — which is a shader compile error, which Godot reports by
dumping the whole shader to stdout ONCE and then rendering every surface that
uses it with a fallback material.

So every wall in the building was that fallback: a flat mid-grey plane with no
tooth, no emulsion drift, no contact darkening at the floor and no dado, in a
file whose comments described all four in detail. It is the reason two separate
rounds went into raising and warming the ambient to fix a wall that was not
being drawn by the shader anybody was editing, and it is the reason the ward
kept reading as "bare" however much else was fixed.

The suite would have caught it — the quiet check greps everything the game
prints for `ERROR` and both `SHADER ERROR: Redefinition of 'drift'.` and
`ERROR: Shader compilation failed.` are in that output. It was found by reading
the log rather than by the check reaching the end of a run, which is the same
thing arriving a few minutes earlier.

### And the diagonal streaks in every screenshot this project has ever taken

Two causes, both fixed. `grid_line` WIDENED rather than faded when the
screen-space derivative exceeded the line width, so a ceiling seen at a grazing
angle turned into a white wireframe; and the sun's shadow map was landing on
the underside of a ceiling nothing can be above, in broad soft bands in the
sun's direction. The ceiling shader is `shadows_disabled` and the sun casts
nothing — it was four full-scene depth passes producing nothing but leak.

### Counts

```
unit + integration assertions ........................... 297
smoke checks ............................................ 161, on three seeds
input-layer checks ...................................... 12 on a pad, 13 on a whole day
day-level criteria ...................................... 7/7
career-level criteria ................................... 6/6, on three seeds
wards that sign off on the honest day ................... 4/4
the game says nothing it should not, while being played . asserted
shaders that compile .................................... all of them, and it is checked
```

### A negative result: light wrap does not fix a flat face

The one audit finding left standing after all of the above was "characters have
no key light and no form", and the standard fix is `BACKLIGHT` — Godot's wrap
term, which puts light on the side of a surface facing AWAY from the source and
is what gives skin its subsurface roll. It was worth knowing whether the
Compatibility renderer even supports it.

It does, and it does not help. A wrap of 0.28 on skin alone moved 6,100 pixels
of a 1600x900 frame by at most 27 levels; 0.70, which is well past subtle,
moved 6,300 by at most 52 — and the two faces are indistinguishable side by
side. Reverted rather than shipped, because a term nobody can see is the same
failure as a constant nothing reads.

The reason it does nothing is worth more than the change would have been: the
faces are not short of light. The sun is a directional key with its shadow off,
so it lights the whole interior from upper-left, and there is 1.15 of ambient
on top of that — a head is already lit from two directions. What reads as flat
is an egg with decal eyes, which is a geometry problem.

`look.sh` is what made this cheap: two renders and a pixel diff, and the answer
was a measurement rather than an opinion.

### A second negative result: glass is not the hard part of a window

The hospital has no windows. That is two dead things at once — the procedural
sky, whose own comment says it is "only ever seen through the windows", and
`Room.window_open`, a saved state a complaint line reads out loud about a
window that does not exist — so glazing the four exterior wall runs looked like
one change that would pay three ways.

It is safe to do there and nowhere else: nobody is ever OUTSIDE the building,
so a pane that collides on layer 1 but not on 32 stops a thrown bedpan leaving
the ward while NPC sight passes straight through it, and not one sight line in
the stealth model can change. That part worked.

What did not work is the view. With no terrain outside, a window at eye level
fills with the sky's GROUND hemisphere — a flat murky green — so the ward ended
up with what look like windows painted over in sage. Worse than a blank wall,
because a blank wall is not promising anything. The dado made it worse again:
running teal up to a sill at 1.15 swallows the lower two thirds of every wall
and the cream/teal balance goes with it.

Reverted. The order is: build something to look at, rebalance the dado, then
glaze. Recorded here because the geometry, the safety argument and the material
are all worked out and only the view is missing.

One thing measured along the way, which is worth having: a LIT PBR material on
a twenty-metre alpha-blended surface defeats early-Z and takes a three-vantage
render past twenty minutes on this box. Unshaded is both cheaper and the right
choice for this project's style — every other bright thing in the game is
unshaded already.

### The gown was gingham

Two sines of the same pitch averaged together is a square lattice, and a square
lattice on a hospital gown is a printed check. It was on the closest object in
the game and it only became visible once the weave was on anything at all,
which was this session.

What fixed it: the warp and weft run at pitches that do not divide into each
other, the phase is dragged about by the same noise that carries the slub, and
the threads are multiplied rather than averaged — threads cross, so you see the
crossing point where both are at the top of their cycle and the gap everywhere
else. The weave was also nine per cent of the albedo, which is a pattern you
can name from two metres; it is five and a half now, with the irregular half
carrying as much as the regular half.

At half a metre the gown reads as fine cloth; at five metres the weave
dissolves and the curtain is smooth with its folds doing the work, which is
what real fabric does across a room.

**A correction.** The commit that landed this says the pitch went from 180
threads a metre to 300. It did not. `fabric_mat` took the pitch as a default
and `Build.cloth_mat` passed 180 explicitly, so raising the default reached
nothing: every piece of cloth kept the old pitch while the shader's own
comments described the new one. The three changes above are what did the work.

Rendered 300 properly afterwards to see what had been missed, and it is worse —
the weave dissolves almost completely by half a metre, so a gown at the
distance you actually read one is flat pink. 180 stays, as one constant
(`Surfaces.WEAVE`) rather than a default at one end and a literal at the other.
The pixels never changed; only the account of them did.

A default is only a default until somebody passes the old value explicitly, and
when they do, the code and the comment disagree and the picture sides with the
code.

## Session 16 — state of play, and what is left

Everything below was checked against HEAD (96fa1a0) rather than written from
memory, because twice this session what I believed had shipped and what the
code actually did were different things.

### What shipped, with the numbers that are actually in the file

```
Build.LINE_GAIN ......................... 0.66   (was 0.22)
Build.line_for cap ...................... thin * 0.21, floor 0.0015
Build.ink_for ........................... hue-derived, v * 0.14, clamp 0.022-0.15
Build.shadow_texture STRENGTH ........... 0.62   (was 0.52), flat core * 1.45
Surfaces.WEAVE .......................... 180.0  (one constant, one call site)
NPCBody.SKIN_ROUGH ...................... 0.52   (was 0.85)
ceiling self_lit ........................ 0.22   (was 0.55)
wall ao_depth ........................... 0.20
floor edge_depth ........................ 0.16
ambient_light_energy .................... 1.15   (was 0.30)
tonemap exposure / white ................ 0.70 / 3.2
adjustment saturation / contrast ........ 1.35 / 1.16
glow_hdr_threshold ...................... 1.05
sun.shadow_enabled ...................... false
```

Mechanisms confirmed present: `_reface` called from both Minkowski builders;
`taper_mesh` at 18 segments; `cyl_mesh` returning a rounded-rim ArrayMesh;
`_fit_line` rebuilding from a recipe and guarding every meta read with
`has_meta`; the wall shader's local renamed to `streak` so it stops shadowing
the shared varying; `apply_shift_look` on `minute_passed`; `set_lamp_look`
using `lit_panel`; door linings. No `duplicate()` survives in any material
path — the three remaining mentions are the comments warning against it, and
one legitimate `StandardMaterial3D` copy.

Reverted and confirmed gone: `BACKLIGHT`, `glass_mat`, `_glaze`, `skin_mat`,
`tests/_evening_*`.

### What is left, in the order I would take it

1. **A view outside, and then windows.** The two have to land together and
   that is the whole lesson of the reverted attempt. The sky is built and
   re-tinted every minute and nothing can see it; `Room.window_open` is a
   saved, loaded state that a complaint line reads out loud about a window
   that does not exist. Glazing alone makes it worse, because with no terrain
   an opening at eye level fills with the sky's murky green ground hemisphere.
   Build a horizon band, a massed building or a treeline FIRST. Rebalance the
   dado at the same time — teal to a 1.15 sill swallows the lower two thirds
   of every wall. The glazing code that was reverted is in `04c87ce` if it
   helps; it was sound, and only cull mode and shading mode needed care
   (unshaded, back-faces culled, or a software rasteriser crawls).

2. **Character form is a GEOMETRY problem, not a lighting one.** Measured:
   see gotcha 44. Faces are lit from two directions already. What reads flat
   is an egg with decal eyes, so the next attempt belongs in `npc_body.gd`'s
   head construction — a brow ridge, a cheekbone, eyes set into sockets rather
   than laid on the surface — not in the shader.

3. **Does tripling the outline weight cost real fill?** `LINE_GAIN` went from
   0.22 to 0.66, which triples the ink area, and 917 of 1315 meshes on a live
   ward already draw twice. This could not be isolated here: the only
   rasteriser available is llvmpipe, frame times on it are not trustworthy,
   and the box had rogue renders stealing cores for much of the session.
   Measure it on hardware before assuming it is free.

4. **Smaller, all previously audited and none of them done:** `cyl_mesh`'s
   segment count is a magic number at 25 call sites; `corner_for` uses one
   radius for all three axes so medium props are marshmallows; the bedside
   screenshot vantage frames its patient badly, which is a harness choice
   rather than a rendering fault.

### Two things about this machine, not the game

The working tree was being written by something other than this session: a
looping `perf.gd`, stray `screenshots.sh` runs, and a pair of
`tests/_evening_*` probes that PATCH SOURCE FILES AT RUNTIME to sample the
ward at different times of day. That is what silently reverted two `build.gd`
edits mid-session and cost two rounds of confused debugging. They are killed
and deleted, and `.gitignore` now covers `tests/_*.gd` rather than only
`tests/_check.gd` — the rule was enforcing the underscore convention while
naming one file, which is the failure its own comment warns about.

And: on a four-core box two rogue renders halve everything. If a render seems
impossibly slow, `ps aux | grep Godot` before concluding anything about the
change under test.

## Session 16, continued — the view, and the windows to see it through

The first item on the handover, done, and in the order the handover said it
had to be done in.

### The view first

`Hospital._build_outside` puts three rings at three depths outside the
footprint: a boundary you look over at twelve metres, a treeline at forty-odd,
and pale massing at ninety to a hundred and fifteen. All of it is scenery in
the strictest sense — no collision, no navigation footprint, no outline — and
aerial perspective is baked into the colours because fog is deliberately off in
this project.

Two things had to be measured rather than guessed, and both came off renders.
A window shows a narrow slice of the world: from an eye at 1.7m the aperture
spans about three degrees below the horizontal to nine above. The first
treeline was nine metres tall at forty-five, which fills that band completely
— a column sampled through the glass gave a hundred and fifty pixels of flat
(116,166,139) where the sky and the town should have been. And at the grass's
own lightness a treeline is not a treeline, it is more grass. Trees are three
to four metres now and each ring is darker and bluer than the one in front.

### Then the glass

`_glaze` replaces the wall build on the four exterior runs. Safe there and
nowhere else: the pane collides on layer 1 but not on 32, so a thrown bedpan
bounces off it while NPC sight passes straight through — which would matter
enormously on an interior wall and matters not at all when there is nobody
outside to see. `Build.glass_mat` is unshaded and back-face culled, and both
are performance decisions: a lit PBR material on a twenty-metre alpha surface
defeats early-Z and took the first attempt past twenty minutes to render. This
one renders in six.

### And a regression the windows exposed

The corridor came back with two hard black diagonals down the right-hand wall.
They were the cornice and the dado rail — cream trim on a cream wall, so the
only visible part of them was their own outline, and the outline was as thick
as the trim. That is fallout from tripling `LINE_GAIN` earlier in the session.

The fix is not another width cap, and understanding why is the useful part.
The hull grows by a constant number of PIXELS at every distance, which is the
whole point of the depth term — but the object shrinks, so the ink's share of a
thin object grows without limit. A cap on the WIDTH bounds that at one distance
and nowhere else, which is exactly why trimming the width earlier cancelled the
gain and fixed nothing. The ceiling is in METRES now and lives in the shader:
`min(weight * dist, max_grow)`, with `max_grow` a share of the object's own
thinnest dimension. Near objects keep the full pixel-constant line; a thin one
stops growing at the distance where the line would start to eat it. Ink on that
stretch of wall fell forty per cent and the lines read as edges again.

Verified: 297 assertions, 161 smoke checks on three seeds, seven day criteria,
every deal playable, the frontier probe, both play runs, the quiet check and
the boot check. All green.

## Session 17 — sound, type, and one artefact that was never there

Three things the handover asked for and one it could not have, because finding
it needed a camera at the right height.

### Sound: the ward has a room around it now

Every sound in the game was DRY. Positional audio existed — 24 voices on
`AudioStreamPlayer3D`, attenuated, placed — but there was no bus and no reverb
anywhere, so a footstep on vinyl, a door down the corridor and a monitor forty
feet away all arrived with nothing around them. A hospital is hard floors,
painted plaster and long straight runs; it is one of the more reverberant
places a person is ever in, and its absence is the loudest "made in a week"
tell an interior game has.

`AudioMgr` now builds a `World` bus with one `AudioEffectReverb` — a corridor,
not a cathedral: room 0.62, damping 0.46, 18ms pre-delay so the direct sound
still arrives first and the source still has a direction, hipass 0.18 so a
footstep does not boom, wet 0.20. The whole 3D pool routes through it. The
music and the UI clicks stay dry on Master, because a button that echoes is a
button in a cave.

Before that: bedside monitors that take it in turns across the occupied beds
(so five patients is a rhythm and one is a lonely one), a two-beat pulse under
the last forty minutes before Vinnie, three ambience sounds rescued out of the
dead pile, and thirteen recipes deleted that nothing had called since the
treatment system was cut. Every recipe in the file is now played by something
and the smoke run keeps it that way.

### Type: four hands, and the chart reads like a chart

`assets/fonts/` — Instrument Sans, IBM Plex Mono, IBM Plex Serif and Nothing
You Could Do, all OFL, licences beside them. This is the one place the
no-assets rule bends, and the reason is that a letterform is not something you
can derive from primitives.

The mapping is the point, not the fonts. `ChartEntry.Author` picks the face:
your own notes are HANDWRITTEN, a colleague's are the interface sans, a
patient's reported speech is italic, and a machine's result is mono. The chart
and the ward sister's review both go through one `UIKit.chart_line`, so the
note she reads back at you at eight o'clock is visibly the note you wrote at
half six. Form titles and the rubber stamp are serif — the institution's own
voice. The HUD clock, the day and the money are mono because they change while
you are looking at them and a proportional face made the corner of the screen
twitch once a minute.

Measured rather than assumed: a specimen rendered on the real manila at the
real body size says the handwriting's x-height is IDENTICAL to the sans's at
the same nominal size. What differs is ink — 573 dark pixels against 943 —
because it is a single-stroke script. So it does not read small, it reads
faint, and the first version of `HAND_SCALE` (1.34, sized for an x-height
problem it does not have) would have overrun the chart card by a third. 1.19
puts the two within 15% of each other on ink.

### The ceiling bands, which were not a bug

The handover did not mention these because nobody had named them; they are the
broad soft diagonals across the top third of every interior shot this project
has ever taken, and they have been blamed on the sun's shadow map, on the tile
runner, and on noise aliasing across three separate passes.

Isolated properly this time, one term at a time on the real ward: horizontal
standard deviation across the ceiling was 9.33 with the tile runner on and 5.92
with it off, and every diagonal went with it. Splitting the runner into its two
axes finished it — they are `line.y`, lines of constant world z, drawn
correctly, fanning out from the vanishing point on a plane 65cm above the
camera.

Sixty-five centimetres, because `look.sh`'s wide vantage sat at 2.6m under a
3.25m ceiling. The player's eye is at 1.7m and every other vantage in both
harnesses uses it. At 1.7m the bands do not exist. Three passes of graphics
work were judged from a frame no player can stand in; the tuning vantages are
eye height now and `screenshots.sh` keeps its establishing shot.

### Two real faults found on the way

`ceiling_mat` declared `uniform float self_lit = 0.22` under a paragraph
explaining why 0.55 was too bright, and then handed the material **0.85**.
CLAUDE.md quoted the 0.22. The measurement: ceiling at L=215 against an upper
wall at 200 and a floor at 150 — the largest surface in the top third of every
frame was the brightest thing in the room, and the light fittings did not read
as fittings because the tile was as bright as they were. It is `CEIL_SELF_LIT`
now, in one place, quoted by the shader's own default. Gotcha 48, alive.

And `detail_fade`, which is `grid_line`'s argument applied to everything else:
the floor, the wall, the ceiling and the prop shader all sampled noise at 24 to
60 cycles per metre with no guard, while the fabric shader — the only one that
had ever been looked at closely — did it properly.

### The HUD money plate was off the screen

Measured on a 1600-wide render: the owed line ran to x=1589 with the plate's
own right edge at 1603. A PanelContainer sizes to its child and the default
grow direction is END, so on a plate anchored to the right the overflow goes
straight off the edge. It grows towards BEGIN now.

Verified: 297 assertions, 168 smoke checks on three seeds, seven day criteria,
the data and draw checks, careers on three seeds, the frontier probe, both play
runs, the quiet check and the boot check.

### Still open

- **Character form is a geometry problem.** Measured last session and still
  true: BACKLIGHT at 0.28 moved 6,100 pixels by at most 27 levels and the face
  read identically. The heads are eggs with decal eyes and that is where the
  next attempt goes — `npc_body.gd`, not the lighting.
- Whether tripling the outline weight costs real fill on hardware. Unmeasurable
  on llvmpipe.

## Session 17, continued — five people instead of one man in five gowns

`Appearance` already varied skin, hair colour, gown, height and girth, and the
ward lineup still came back as the same person five times. The reason is in the
file's own comment one level up: height and girth scale a BODY, and a body is a
coat. At three metres down a bay you read a person by their HEAD, and every
head in the building was the same ellipsoid at the same size with the same cap
on it.

Four new fields, all from the same stable hash over the id, so adding somebody
cannot change anybody who already exists:

  `skull`     non-uniform and independent per axis, so the cast contains long
              faces, round faces and broad ones rather than five sizes of one
  `nose`      the most identifying thing on a face and the cheapest to vary
  `jaw`       reads from further away than the nose, being the bottom edge
  `hair_style` five cuts — cropped, swept, bobbed, tied back, full

The last one is the one that carries it. Hair COLOUR is close to invisible
across a lit ward — three dark-haired patients in a row are three identical
dark caps whatever the swatches say — and a SILHOUETTE is visible at any
distance the head is. Two spheres each.

All of it goes on the silhouette pieces (skull, ears, jaw, hair) and none of it
on the `_head` node, because the brows rotate for expressions and a rotated
child of a non-uniformly scaled parent shears. Heavy thinning takes the cropped
cap whatever the draw said: a receding bob is not a haircut anybody has.

### And a real leak, found by reading a warning nobody had read

`WARNING: 5 RIDs of type "CanvasItem" were leaked.` has printed after every
day play run for as long as that harness has existed, in the middle of a page
of PASSes. `--verbose` names them: five VBoxContainers with no parent.

It is `screen_review.gd`'s citation box, built before it is known whether the
finding cites anything and then not parented when it does not — once per
rebuild, and the review rebuilds on every answer you give the ward sister. A
Control that is built and never parented renders nothing, errors nothing, and
is leaked; a player accumulates them for the whole shift.

`free()` and not `queue_free()`, because an orphan has no frame boundary to
defer to. `run_tests.sh` fails the day run on any `RIDs of type` line now,
proven red by putting the leak back. `ObjectDB instances` stays filtered — that
one is the audio server being yanked out from under a looping stream by
`quit()`, which boot_check.sh documents and no player can reach.

One thing tried and reverted: tearing the game down over a few frames before
the harness quits. It did not remove the CanvasItem leak (that was never a
pending free) and it added an ObjectDB one.

## Session 17, continued — the title screen, which was lit like a different game

`MenuScene` carried its own copy of the grade: a sky-blue ambient at 1.05,
exposure 0.80, white 2.6, saturation 1.22. `Game` carried the swept one —
warm-neutral at 1.15, 0.70, 3.2, 1.35, chosen by photographing six settings and
scoring them. So the first screen of the game was cooler, flatter and half a
stop brighter than every screen after it, and nothing anywhere said why.

`Grade.apply(env)` is the one definition now, with the measurements and the
reasons that went with them. Only the background differs between the two
callers, and it has to: the ward has a procedural sky it sees through the
windows, and the title vignette is one room with no outside.

The room itself was built out of `Build.wall` and `box_mi`, which give every
square metre one flat albedo — so the screen whose entire job is "the first
frame of the game looks like the game" had a blank white ceiling, a plain green
floor and flat cream walls, with none of the tile, speckle, paint tooth or
contact shading of any room behind it. It goes through `Surfaces` now.

And it has two beds in it. The panel covers the middle two fifths, leaving two
thirds of the frame to compose in, and only the left one had anybody in it —
the right third was a cabinet, a plant and four square metres of wall. Two beds
with two different patients also make the point the game is about: this is a
ward, and there is more than one of them. The lens went from 62 to 52, because
a wide lens in a three-metre room spends the top of the frame on ceiling tile.

## Session 17, continued — heads that read, and one thing left open

### The first pass at head variation did not work, and the measurement said why

`Appearance` was handing out five hairstyles with an even spread — 626/591/619/
556/608 over three thousand ids, so the hash is sound — and the ward lineup
still came back as three identical dark caps. Two reasons, both found by
printing what the cast actually drew rather than by looking harder:

  * Style 3 was a low bun BEHIND the skull. You see a patient from the foot of
    a bed, so from the front it is indistinguishable from the cropped cap.
    Six of the forty authored patients draw style 3 and six draw style 0, so
    twelve of forty were reading as the same haircut for want of four
    centimetres of height. It is a topknot now — the knot clearing the crown,
    plus the sweep that gathers into it so it is not a ball balanced on a head.
  * The skull range was 0.93-1.07 on x. That is plus or minus four per cent on
    a head sixty pixels across, which is arithmetically a variation and
    visually nothing. 0.90-1.11 on x, 0.92-1.18 on y, 0.90-1.09 on z.

`look.sh` has a fourth vantage now: the lineup. Character work was being judged
off a twenty-minute `screenshots.sh` run, which is the wrong loop for it — one
render at the right vantage would have caught the invisible hairstyle
immediately. It resolves the camera from the ward's own heads at shoot time, so
it follows whichever board the seed dealt.

### Open: two figures that blow out to white

`17_review.png` and `20_struck_off.png` both show a pair of standing characters
rendered as flat white silhouettes — 36% of that region is pure 255 — with no
shading left in them at all. Every other frame in the set shades characters
correctly, including four with people much closer to the camera.

Four controlled probes failed to reproduce it: a body standing directly under a
ward fitting at eight in the morning and at eight at night, with the rim term
on and off, with the fill light off, with every point light halved, and at
three metres and at one. None of them clipped. The two shots that show it are
both UI-card frames where the 3D is background, and in both the camera is very
close to somebody.

So it is real, it is rare, and I could not corner it. Written down rather than
guessed at: the next attempt should reproduce the exact shot first (it is in
`shot_impl.gd`) instead of building a synthetic scene, which is where four
attempts went.

## Session 17, continued — the rim light was erasing the building

The previous entry left "two figures that blow out to white" open, and said the
next attempt should reproduce the actual frame instead of building a synthetic
one. That is what fixed it, in ninety seconds, on the first try.

`SHOT_ONLY=struck_off ./screenshots.sh` renders one frame out of twenty-one.
With that, the bisect is trivial: rim term to zero, re-render, measure. The
figure box goes from **28.8% pure 255 to 0.3%**.

Godot adds `RIM` PER LIGHT, scaled by that light's energy and attenuation. A
ward has a ceiling fitting every five metres, each carrying a spot at
`SPOT_GAIN` 4.4 and a fill at `FILL_GAIN` 3.1, and four of them reach any given
square metre — so the rim arrives four times over at about three units each.
The sweep is a cliff rather than a slope (0.22 → 26.8%, 0.10 → 17.5%, 0.05 →
1.7%), because the term saturates the moment several lights agree.

And it was never only the characters. Side by side at the nurses' station:

  with rim      Adeyemi's blue scrubs are a white blob, the counter is a white
                slab, the notice board is a blank yellow rectangle
  without       her scrubs are blue with visible weave, the counter is a grey
                counter, the board has coloured notes pinned to it

Same in the ward: every bed was a featureless white shape and is now a bed.
Same at the bedside: the blanket was a flat pink slab and now has a fold in it.

The comment being replaced said the rim was "most of what gives a body its form
in a room lit from straight above", and it was true when it was written. Then
`ceiling_light` was split into a shadowed spot plus an unshadowed fill and the
gains went up to compensate, and nothing went back to the rim. Third instance
this session of the same fault, after the ceiling's `self_lit` (0.22 in the
comment, 0.85 in the code) and the fabric's weave pitch: a number tuned against
a world that has since moved, still doing exactly what it was told.

`Surfaces.RIM_EDGE` is one constant, set from GDScript into both shaders as a
uniform, and it is 0 — kept rather than deleted, with the measurements, because
the next person to reach for an edge light needs those more than they need a
clean file. If it is ever turned back on, the lights have to give first.

## Session 17, continued — the last forty minutes get quieter

There is one piece of music and it plays the whole time, which is a decision
this project made on purpose after three shift moods produced the bug where the
menu's track was thrown away the moment a shift started. But a score at exactly
the same level at ten past eight in the morning as at five to eight at night —
in a game whose entire pressure is a man arriving at eight — is not a score in
the game, it is a score playing over it.

So it steps back rather than changing. `AmbienceSystem` already knows when the
last stretch begins, because that is where it starts the heartbeat; the same
window pulls the music down nine decibels on a ramp and lets the ward the
player has been standing in all day finally be audible, with the monitors and
the pulse in front of it. Nothing is composed and nothing is added.

The half that would have failed silently is the release. `_pulse_pass` returns
early outside the window, and without a `duck_music(0.0)` on that path the
score stays nine decibels down for the rest of a nine-night career, with
nothing on screen to say so. Both halves are in the smoke run.

## Session 17, continued — the face was a nose problem

The standing open item was "faces are geometry, not lighting", measured twice
and never acted on. Two pieces of geometry, and both were visible in the first
comparison:

  A BRIDGE. The nose was one ball between two eyes, which reads as a clown
  nose — and at the closest camera distance in the game, a doctor standing over
  a bed, it is the thing you look at. What makes a nose a nose is that it rises
  out of the brow. One tapered ridge running up between the eyes, unlined,
  because an ink line up the middle of a face reads as a scar.

  A SOCKET. The eye whites are unshaded ovals sitting proud of an ellipsoid,
  which is why they read as stickers: a real eye sits IN something. A slightly
  larger, slightly darker skin disc behind each one seats it. Darkened rather
  than tinted, so it works across the whole skin range.

Two spheres and a box per head. Side by side the face has structure it did not
have, and at ward distance the five still read as five people.

### And a defect that was not one

Every face in the game carries a small white square with a dark border below
the nose, and it turns up in the closest shot in the set. Three renders went
into it: not a Label3D (hiding every one of them left the mark), not the mouth,
not an eye. It is the CROSSHAIR, at 800,450 on a 1600x900 frame, which is the
exact centre of the screen and the exact centre of a face the harness has
deliberately framed. Written down because the next person to look at that
screenshot will see it too.

## Session 17, continued — the room tone was a three-second loop

The score was taken from a sixteen-second loop to ninety-four seconds earlier in
this project's life, and the reason is written down beside it: the loop point
has to be further apart than the longest thing anybody does in one place. The
ROOM TONE, which plays underneath the score for the entire twelve hours, was
left at three seconds — with a seeded noise floor, so it repeated identically
about fourteen thousand times a shift.

Eleven seconds now, plus one slow breath per loop, because a plant of that size
does not hold a perfectly steady note and without the modulation the tone is
audibly a synthesiser holding one.

The constraint that keeps it seamless with no cross-fade is that every partial
has to fit a whole number of cycles in the buffer: 50 Hz gives 550 cycles in
eleven seconds and 74 Hz gives 814. Pick a length that leaves either of them
mid-cycle and it clicks, once per loop, under everything, forever — and nothing
else in this repo would ever hear it. `HUM_PARTIALS` exists so the smoke run can
do the arithmetic, and the check was proven red with a length of 11.017.

## Session 17, continued — and a lip

With the nose given a bridge and the eyes given sockets, the mouth was the last
thing on the face reading as a sticker: one dark red bar and two corner blocks,
all flat, with nothing above or below them. A mouth is a LINE BETWEEN TWO LIPS,
and the lower one is the half that catches light.

So: the bar is thinner, and a small warm piece sits directly under it, tucked
inside its width. The colour is the person's OWN skin pushed toward a lip rather
than a fixed pink — across a cast whose skin runs from 0.29 to 0.96 that is the
only version of this that works at all. Behind the bar in z and below it in y by
a couple of millimetres, so it never fights for a pixel and never pokes through
when the bar scales open for a grimace.

## Session 18 — the faces, which is what stops somebody clicking on it

Asked for a rating of the game, I said the character art was the ceiling on
everything else and the thing most likely to stop it being clicked. Asked to fix
it, the first thing needed was a way to SEE it.

### `./faces.sh`

Six people drawn through `Appearance` — the same machinery the ward uses, so
what is photographed is what ships — stood in the corridor and photographed one
at a time from eighty centimetres, then all six together in the ward. Seven
frames. `screenshots.sh` is twenty-one frames and twenty minutes; `look.sh`'s
lineup renders a head sixty pixels tall. Neither is a loop anybody can do an art
pass in, and that is exactly how a hairstyle invisible from the front got
shipped last session.

**Two harness faults cost a render each and both looked precisely like modelling
faults.** Six subjects five metres apart from x=2.5 in a twenty-metre corridor
puts the last two at 22.5 and 27.5 — outside the building, with nothing under
them. They fell; by the time the camera reached them their heads were at y=0.43
and dropping, so the portraits framed the top of a skull with the head pitched
up at a lens above it, and I was one edit away from "fixing" a `_tick_look` that
was working perfectly. Then the cast camera, four and a half metres back in a
four-metre-deep corridor, photographed the far side of a wall. The harness
asserts nobody is falling now, and the cast shot happens in the ward.

Also a process fault worth writing down: an edit script whose `assert` threw was
followed by a render in the same command, separated by a newline instead of
`&&` — so eight minutes went into photographing the unmodified source, and the
render came back looking exactly like a change that had not worked. Chain the
edit to the render, or verify the edit landed first.

### What was actually wrong

THE SCLERA. Every character had a big white oval with a dark disc floating in
it. Three separate fixes are recorded in the comments above that code — the
whites came down a third for "swimming goggles", the pupil was flattened for
"walleyed", the pupil was grown for "permanently surprised" — and every one of
them was a real fix for a symptom of the white being there at all.

A solid dark almond with one catchlight is what a stylised eye is. Nothing is
lost by dropping the sclera, because **nothing in this game ever moved a
pupil**: gaze is carried entirely by `look_toward` turning the head, and it is
still legible at four and a half metres, which is what the suspicion system
needs. The catchlight is not mirrored between the two eyes — there is one sun —
and it is what keeps an eye visible on the darkest skin in `Appearance.SKIN`. A
closed eye is a dark LINE in the same colour now, rather than the skin-coloured
bar it was, which on a light face was nothing at all.

THE HAIRLINE. The forelock's bottom edge sat at y=-0.014 — below the brows at
0.052 and below the eyes at 0.008 — and the crown's front face reached z=0.194,
in front of the eyes at 0.184. So the crown WAS the hairline, the forelock was
decorating a helmet, and not one character in the game had a forehead. The
crown is pulled back to own the top and the back; the forelock is raised to own
the front edge and leaves about three centimetres of forehead. It is the single
change that stopped these reading as blocky.

And three smaller ones off the same photographs: the brows were
`hair.lightened(0.10)`, which on a seventy-three-year-old's white hair is a
white bar on a pale forehead — invisible, on the one part of the model that
carries every expression in the game. The mouth bar was 0.086 half-width
against an eye span of 0.105, so a mouth was 82% as wide as the face. The nose
ball was a shade large and a shade too round.

Verified: 298 assertions, 172 smoke checks on three seeds, seven day criteria,
the data and draw checks, careers on three seeds, the frontier probe, both play
runs, the quiet check and the boot check. All green, and the title, bedside,
lineup, station and visitor frames re-rendered and reviewed.

## Session 18, continued — the bodies

With the faces fixed, the body became the weak link: `faces.sh`'s cast shot
showed six people who all appeared to be wearing sandwich boards.

It was not a stray object. The torso is a taper 0.70 wide and 0.36 deep with a
corner radius of 0.13 — which leaves a FLAT FRONT 0.44 across bounded by a 0.13
curve, so the chest is a big evenly-lit panel with a darker border round it, and
the arms hang beside it rather than off it. Deeper and much rounder (0.40,
radius 0.17) leaves a small flat front and a wide soft turn, which is a chest.
The arithmetic generalises: for anything built from `taper_mesh` or `rbox_mesh`,
the ratio of corner radius to half-depth decides whether it reads as a solid or
as a board.

Two smaller ones from the same shot. The legs sat at sx*0.145 with a thigh 0.20
across, which is nine centimetres of daylight between the thighs — two poles at
four metres. 0.118 closed it completely and made hip-to-ankle one column with a
seam; 0.129 leaves about two centimetres. And every arm hung at exactly
vertical, which on six people at once is a rack of mannequins; `ARM_REST_X` and
`ARM_REST_Z` put a few degrees of forward and outward into the rest pose, and
`set_in_bed` restores to those rather than to zero.

None of it is visible on somebody lying in a bed, which is why all three
survived every screenshot this project has taken.

`faces.sh` grew a full-body frame for this, taken BEFORE the cast closes ranks
— taken after, it photographed the middle of a crowd. That was the third
harness fault in a row that looked like a modelling fault, and the running
score for the session is three renders lost to the camera and none to the
model.

Verified: 298 assertions, 172 smoke checks on three seeds, seven day criteria,
the data and draw checks, careers on three seeds, the frontier probe, both play
runs, the quiet check and the boot check. All green.

### And a brow that was written in two places

Setting a rest angle on the brows at build time and then letting `set_mood`
write `sx * _mood * 0.42` over it means the first time anybody's mood is set to
neutral, their brows snap flat and stay there — a different face to the one that
was built, arrived at silently. The height had the same fault in the other
direction: built at 0.052, set_mood at 0.068. `BROW_REST_Y` and `BROW_REST_Z`
are the one definition and both places read them. Same class as the ceiling's
`self_lit` and the fabric's weave pitch, found by reading the diff rather than
by looking at a picture, because a face at neutral and a face at build are
rarely in the same frame.


---

## The audit pass

Eight readers went over the game against a "ship it and charge money for it"
bar — content, economy, sound, environment art, onboarding, writing, release
hygiene, replayability — and a ninth read all eight and asked what they had
missed. What came back was better than the sum of it, because the thing that
mattered most lived between two of the areas and none of them owned it.

### A day was never a budget

CLAUDE.md has stated it as a design rule since the redesign: "the day is not
long enough to do all six on all five beds, so a day is a budget rather than a
checklist." It was not true and had never been true. Six verbs at
12/8/10/15/5/15/25 is ninety minutes a bed and 450 on a five-bed ward against a
720-minute shift, so the correct play was to do everything to everybody and then
decide, with two hundred and seventy minutes spare. The frontier probe's own
honest day worked 333 minutes of the twelve hours. Forty-six per cent.

Nothing caught it because nothing was looking. Every probe in the repo drives
the ward with `advance_to(15 * 60)` and reads the money at the end, so the clock
was an output nobody asserted on — the same shape as the ceiling `self_lit` that
was 0.22 in a comment and 0.85 in the code, and as the shift `scrutiny` that was
printed at the player and read by nothing.

`WardDay._spend` accumulates `minutes_worked` now, which is deliberately not
`minute` — that also moves when a probe skips an hour, when a round walks
forward and when the shift is forced to close. The frontier probe reports it and
fails three ways: a checklist that fits in a shift, an honest day that does not,
and the top of the money curve being reachable clean. That last property is the
probe's headline and it had been PRINTED and never asserted for as long as the
probe had existed.

The shape mattered more than the scale, and a uniform multiplier could not have
produced it: the honest day was already 74% of the exhaustive one, so anything
that made the checklist impossible made honesty impossible with it. So finding
out stays cheap — reading is 15 and the lab is 10 — because the career rework
exists to stop information ever having negative expected value. Looking costs
25. Corroboration is the scarce thing, because a name that is not yours behind a
bed is what the audit is actually asking for: Adeyemi has four bays and the
registrar covers two wards, and between them they are two thirds of the
checklist. 160 a bed, 800 a ward, 720 in a shift. The honest day now works 510
and finishes at half past five.

### Twenty people with nothing written about them

The prior-entry lists covered only the FIRST candidate in each slot, and every
ward is a draw from a pool of ten — so on any career seed but zero, up to four
of the five beds opened with a completely blank chart. No handover, nothing to
write against, nothing for the audit to read.

Not a flavour problem. Four of the ten genuinely ill people in this game are
alternates, and with nothing written about them at all `_sent_home_unwell` had
nothing to point at and did not fire: coasting through the first ward on seed
31337 was SIGNED OFF because the man with the rising troponin could be
discharged blind and the record was silent about him.

Seventeen of the notes that did exist were stamped in the future. The chart
prints `stated_minute` verbatim, so the first record a player ever opens carried
a nurse's observation timed 09:20 while the clock in the corner said 08:00.

### The second ward has never had a clean day

Celia Ibarra's examination line reads "the numbers on the chart were all taken
sitting down" and the chart could see her perfectly. Rubén Castellanos's note
has said "only an examination finds it" since he was written, and he carried no
flags at all. Both are the ill end of their ward's PAIR, so on half of every
career's nights the two wards built on "a body the chart cannot describe" and
"somebody else's decision" played as ordinary read-the-chart wards.

The data check now asserts that both ends of a pair are found the SAME WAY, and
it went red on a third asymmetry nobody had noticed — which then exposed the
real hole. With its premise switched on, the second ward could not be signed off
on ANY of its twelve boards: nobody in the building is capable of corroborating
Peter Lomax, one bed on your word alone is `noted`, and a doctor who works that
ward honestly often enough crosses `uncorroborated_rate` and it becomes flagged.
Playing it correctly was a slow accumulating penalty with no way off it.

So a DIRECTED nurse check is a different request from an undirected one. A
routine review is a score and cannot find a man whose tremor is at four in the
afternoon; but if you have laid hands on him yourself and written down what you
found, Adeyemi reads it and goes and checks THAT. Seventy minutes on one bed out
of seven hundred and twenty, and it teaches a sequence rather than a verb.

Three audit rules were punishing the doctor for doing the right thing, and all
three only became visible once an honest day was played on every board rather
than on the one the seed dealt. A normal result no longer refutes a doctor who
examined the patient and found something — on those two wards the bloods come
back normal BECAUSE the bloods cannot see it. `patient_no_recall` no longer
fires on a woman for not remembering a note she wrote herself. And
`invited_contradiction` can now tell corroboration from contradiction, which it
could not: it fired on the pair and printed whichever half you had asked for.

`_honest_on_every_board` plays a straight day on all 52 reachable boards now. It
costs about a second and a half. There is no reason for the strongest property a
probe has to be sampled.

### Which ward you walk onto is drawn

`DAYS[(day - 1) % DAYS.size()]` was the largest single piece of transferable
knowledge in the game. The four wards are the four lessons, so a returning
player walked onto every one already knowing which verb it was about, on every
career, forever. `Cases.pool_index` draws the order from the career seed with a
fresh permutation every cycle; every ward is still visited exactly once per
cycle, so the pressure curve and the debt arithmetic are unchanged. All 24
permutations appear over 2,000 seeds, every career visits all four wards in its
first four nights, and distinct careers went to 1,992 of 2,000.

The interesting half is that "night three" stopped being a ward, so `draws_impl`
was counting each ward's distinct deals against another ward's possible total.

### The answer key

`truly_well` is the hidden boolean the whole investigation layer exists to
deduce, and the game had never once said what it was. Over a nine-night career a
player received fewer than nine pieces of evidence about a question they were
asked forty times, and never saw the answer — which is why a second career was
execution rather than deduction. The End of Shift card reads all five beds back
now: what you did, and what they were, flat, with no score attached.

And the third number the economy turns on was invisible. An empty bed does not
merely pay a $150 discharge, it takes the next admission at $500 — the
inequality `ADMISSION_FEE`'s own comment calls "what stops hold-everybody from
being the answer" — and the word "admission" appeared nowhere a player could
read it. The patient card offered $150 against $180 for a state bed and made
holding look like the better night by thirty pounds.

### The build, the noise and the rest

Two implementation passes ran in isolated worktrees. One found that props have
not broken since the stats dictionary was deleted, that a loaded career ran on
randomness that was not its own, that the `records` save provider had been bound
to a dead object since the first frame of every career, and that the button a
player presses first had never been executed by anything. The other found that
every one of thirty sounds ended on a hard cut above -40 dBFS, that eleven of
them were the same undifferentiated white noise because there was no filter
anywhere in the synthesiser, and that the music duck's release path had been
dead for the entire end of every night.

Then eight strategies on the two wards nobody had ever played, `FRONTIER_SEED`
to go with the other three overrides, and nine things a stranger would have hit
in the first ten minutes — including that the control a player reaches for when
the text is too small was the control that hid the button they needed next.

## The belief layer reaches the verdict, and the stub that was never read

Nine hundred and fifty lines model being SEEN — `Mind`, `Evidence`, the gossip
pass, four tiers of dialogue, `file_complaint` — and they reached the eight
o'clock audit through exactly one channel: `seen_by`, stamped on a chart entry
at the moment it was typed. Everything else the ward accumulated over twelve
hours was thrown away at handover. Somebody would tell you to your face that
they had seen enough, and then say nothing at all to the woman holding the
folder.

`SuspicionSystem.what_the_ward_saw` is what the room would say if anybody asked
it, and `Contradictions.she_was_standing_there` is the one question it is
allowed to become: a bed you held that nobody else saw a reason for, in front of
a room that has been watching. It is in the CONTRADICTED list, so it costs one
notch and no more — noted becomes flagged — and going somewhere private to write
is free.

The first version filtered on `role == "nurse"`, because "Adeyemi watched you
type that" is the sentence the design wanted. It returned nothing. Measured in
the real tree after a shift of bedside notes, the minds holding witnessed
evidence were marchetti 0.331, bassong 0.257, whitcombe 0.257, blake 0.257,
oduya 0.186 — five patients and no staff, because the nurse is at her station
and the people who can see the bay are the people lying in it.

Four gates keep it off a careful doctor: a pattern rather than one note, anybody
else having recorded a reason, nowhere-to-go, and having examined them. The
last is the design rule rather than a balance decision — a measure that fires on
"wrote a note where somebody could see" and not on "went and looked first" pays
you to decide blind.

**And the stub was never read.** `WardDay.witness_stub` was added so the probes,
which build no world, could search a game where somebody is standing there. It
was set in four probes with eight lines of comment each — and read *after*
`if not is_inside_tree(): return`, in files whose entire search runs inside
`_initialize()`, where a node added to the root is not in the tree. The fix for
"the probe searches with a detector switched off" was itself switched off, by
the gotcha its own comment cites. Turning it on puts 9,402
`written_in_front_of_them` and 724 `she_was_standing_there` into the four
searches; the frontier's headline numbers did not move, which is the answer you
want.

Two harness faults found by sweeping seeds while checking this: the End of Shift
readback asked `Cases.roster()` for names while the card in front of it was
built from a different ward (gotcha 30, in a new place — it only showed on
`SMOKE_SEED=0`), and the clatter check demanded that a twelve-metre noise wake a
patient more than twelve metres away.

358 assertions, 250 smoke checks on three seeds, every probe green.

## A third of the cast had no face

`./faces.sh` photographs six people close up, and the darkest-skinned of the six
had no eyes and no mouth — two brows, a nose, and one white dot where two
catchlights should have been. Counting pixels: 108 on the left eye, 0 on the
right.

Two causes, both invisible from the code.

`Appearance.skull` is independent per axis and its z runs 0.90 to 1.09, so the
front of a head moves nearly four centimetres across the cast — and the eyes,
catchlights, brows, sockets and mouth were all placed at literal depths tuned on
an average one. Above about skull.z = 1.05 the skull is in front of them.
Nothing errors, nothing is missing, the head renders exactly as it should, and
the face is behind it. Measured after the fix: 8 of 72 features across 24
generated faces had been buried, worst by a centimetre. `NPCBody._face_z` asks
the ellipsoid where its own surface is, and the smoke run measures the built
pieces against the skull MESH's scale rather than against `_face_z`, which would
only ever agree with itself. Proven red by putting two of the literals back.

And the eye was `unshaded(0.10, 0.09, 0.11)`, a fixed emissive value, against a
lit face: read off a real frame, the darkest skin renders at (56, 33, 16) and
that eye at (68, 45, 37). The eye was lighter than the face. Lit near-black now,
so the ratio to skin is constant under any light.

While the pictures were up: the shoulder sphere was a 21cm ball on a 20cm
sleeve — shoulder pads on everybody, the second time that piece has read as an
epaulette — and the forearm was 16.4cm coming out of a sleeve that ends at 15,
with a comment on the next line about the hand being wider than the wrist, about
a hand 1.4cm narrower than the arm it is on.

351 assertions... 358, and 251 smoke checks on three seeds. Everything green.

## Three constants, twenty-six functions, six signals — and the dark end of the
## palette

Two sweeps in one stretch.

The dead-code one: gotcha 15 has said since the shift-type table that a constant
nothing reads is a promise made in copy and not kept in code, and nobody had run
that question over the whole repo. Twenty constants, twenty-six functions and six
signals came out — including a whole `Dressing` piece modelled and placed in no
room, the only way a fixture had to emit a world event, and a colour for a
reputation system that was cut two reworks ago. Three new smoke checks, all
proven red. An emit with no listener is the worst of the three: it costs work
every time it fires and it reads in review as the place where the thing happens.

And the faces one, which came in from outside mid-stretch: "some of the black
characters\' faces look messed up compared to the white ones". Three separate
causes and all of them the same shape — an absolute value chosen for the middle
of a range that the end of the range cannot carry. Features pinned at a literal
depth on a skull whose front moves four centimetres across the cast. An unshaded
eye that measured LIGHTER than the darkest skin. And a lower lip lerped toward
one fixed pink, which is darker than a pale face and two thirds lighter than the
darkest, so the one bright thing on that face was a salmon block under the mouth
that read as an open mouth with the tongue showing.

Underneath all three: at an albedo of 0.29 a cheek renders at 34 of 255 while
the same person\'s gown renders at 179. The darkest face had 21 levels of
contrast for its features where the pale ones had 91. `./faces.sh` measures that
per subject now and exits non-zero under a floor, which is the harness that
should have existed before any of this was authored.

## The camera you play the whole game through

A full screenshot pass, looking at every frame rather than assuming.

The bedside view — the one the player spends twelve hours in — showed a man laid
on a slab in his shoes. Four blue-grey tubes with peach ankles and navy shoes on
two of them, and you could not tell the arms from the legs. `PatientBed` has had
a blanket since it was written and it is BEDDING: flat on the mattress, two
thirds of the way down, underneath the patient. Turning that one piece bright red
and re-rendering the frame put no red anywhere near the occupied bed.

Then measured rather than guessed. The smoke run builds real beds with real
patients, so printing the occupant's mesh boxes through the bed's own inverted
transform costs forty seconds: the patient occupies z -1.30 to -0.30 of a bed
that runs -1.02 to +1.02. They sit propped in the head quarter and the rest of
the mattress is empty — so a duvet two thirds of the way down is a duvet over
nobody. The one that shipped is over the lap, and only while somebody is in the
bed.

A full re-pose was tried first and reverted, and the reason is the useful half:
derived honestly from the backrest's own 29-degree ramp, hips at the crease,
legs flat, it put the head seventy centimetres past the headboard and the
mattress through the man's elbows. Three coupled degrees of freedom do not fall
out of one measurement, and the pose was never the fault.

On the title screen — the first frame anybody sees — every character had a black
horseshoe on the gown at the shoulder. A seam filler tucked half inside the
trunk still has a silhouette against the trunk, so the outline pass drew it.

And a doormat at 0.22 of a value on a floor at 0.72 is not a mat, it is a
rectangular hole in the vinyl.

The README had drifted into the same fault as a constant nothing reads, in the
file a buyer reads first: forty patients where there are 43, 52 deals where a
career reaches 88, and one shipping item described as still open that had been
done for a day. The three computable numbers are asserted by the data probe now.

---

## Two more wards, and the three rules they broke

Sixty-four authored people across six wards now, 128 boards a career can reach.
The two new ones are prose rather than engineering — every field a system would
otherwise silently default, one handover note each, and a palette apiece — but
between them they broke three rules that four wards had never touched, and all
three had been wrong for a long time.

**Ward five, "the family reads the chart."** Tiers mirror ward one exactly, so
the money is a shape the frontier probe has already searched two and a half
thousand ways. What is new is who else is in the building: four of the ten have
somebody who reads the notes — a son who photographs the drug chart, a daughter
who is a nurse, a wife with a ring binder, a retired ward sister who ran a ward
like this one for twenty-two years. `family_read_it` is harsher when there was
nothing written down before they arrived, so the ward teaches writing the reason
BEFORE the visiting hour, which none of the first four is about.

**Ward six, "the patient is the witness."** The other five hide the truth in a
document, a body, a colleague or a household. This one puts it in the mouths of
people who are awake, articulate and comparing notes with each other across the
bay. Cyril Mott spikes a temperature between two sets of observations and tells
everybody except the person holding the pen. Ivy Driscoll was sick twice in the
night and is charted as settled. Aurelia Arbuthnot reads her own file the way
she read files for nineteen years on the bench. `reads_own_chart` and
`tells_everyone` are on both ends of the ward's pair and on both candidates at
bed four, so no draw of it deals with its premise switched off.

### The verb that wrote in somebody else's name

`ask_patient` is the one verb in the game that manufactures a reason out of
nothing, and it signs the entry `Author.PATIENT`. `_reads_own_chart` read
`Author.YOU` entries only — so the rule that exists to punish writing on the
chart of somebody who reads it could not see the one line on that chart the
patient had most reason to object to. On two dice going your way (they agree,
and they do not remember whose idea it was) leading a perfectly well premium
patient was eight hundred and fifty pounds with no trace at all.

It survived four shipped wards because on each of them the premium well bed
happened to carry something else: Sam Oduya tells everybody, Douglas Pyne was
admitted overnight by a colleague who wrote it down. Ward six's premium bed
carries neither, and the adversarial search went dominant on three seeds out of
four — the most profitable night on that ward was also a clean one, which is the
single property the whole economy stands on. The rule reads the attributed line
now, gated on both dice having gone your way so it cannot double up with
`_patient_no_recall` or `_symptom_was_suggested`. What it says is the thing
neither of those can: she agreed, she remembers agreeing, and she still read the
sentence you wrote it up as and wanted to know who had chosen the words.

### And the doctor who went and looked

The same rule then convicted the opposite person. Ward six has two patients who
are genuinely, expensively ill and read the microbiology every morning, and
against them `_reads_own_chart` fired at 0.66 on a doctor who had drawn the
curtains, examined them, found what was wrong and written it up in her own name
— on every one of the twenty-four boards that ward can deal. Its own question
says "nobody had been near {them}", about somebody who had been. It takes the
same carve-out `_objective_refutes` and `_justification_undermined` already had,
and the same design rule is underneath all three: nothing may fire on "wrote it
down" and not on "went and looked first", or the game pays you to decide blind.

### Three harnesses that were asserting a number rather than a property

- `draws_impl` swept a fixed two thousand seeds and demanded every ward ORDER
  appear. True of four wards — 24 permutations — and arithmetically impossible
  for six: 720 permutations over 2,000 uniform draws covers about 675, so a
  perfectly uniform rotation failed the moment a fifth ward existed. And the
  line reporting it printed "takes all %d permutations" with the count it had
  just failed on, two lines under its own failure.
- `test_ward.gd` asserted that "day five comes round to the first ward again",
  which was a claim about the number four rather than about the rotation.
- The crosshair check strips a patient's own condition words out of the bedside
  prompt before comparing what an ill patient's prompt says against a well one's
  — with a bare `replace(word, "")`. Ward six is the first to author a condition
  containing a standalone "a", so stripping that token removed every letter a in
  the string and left "ntibiotics," behind as a word no other patient has.

### Two findings that decided the patient's gender for them

`_grateful_witness` said "He was very complimentary about you" and
`_symptom_was_suggested` said "He says you asked him about it". Both are read
out loud at the review, and between them the people carrying those flags include
three women. The misgendering grep only inspects quoted strings that also
contain a `%s` — a name substituted into a sentence that has already decided who
the person is — and neither of these has a `%s` in it at all. A grep that
requires a second marker misses every line that simply hardcodes one person.

### A handover note that supports the stay

Ward five's social bed was handed over as a `SOCIAL` claim, which is what it is
in prose and the wrong thing on a chart. `_objective_refutes` fires when a
normal result post-dates an entry supporting the hold, and the night staff write
at seven — so ordering a blood test on that bed flagged eight of the ward's
sixteen boards. Every other social bed in the game is handed over as
`MOBILISING` or `SETTLED` and nobody had ever written down why: the night staff
record what they SAW, and the reason a bed is held for a broken stairlift is the
day doctor's to write, which is the verb the ward is about.

### And then the wards were photographed, which found five more

Ward five rendered with the right floor, the right dado, the right curtains and
"Beech Ward" over the beds — and "Ward C" on the flag projecting over the ward
door, three metres away. `Furniture.rename_ward` rebuilds the plate and the
corridor arrow every morning; the door flag is built out of `Hospital.LAYOUT` at
construction time and had said Ward C on every night of every career. So had the
End of Shift card, which prints "Day %d · Ward C" as a literal and is the most
read screen in the game; the objective waypoint over the door; the corridor's own
`Room.display`, which a witness quotes back at you; and two tannoy lines paging a
ward nobody was standing in. The smoke run walks every `Label3D` under the
hospital after each reskin now and fails if any of them names a different ward.
Proven red by putting the flag back.

Then the largest object in the frame — a folding screen a metre and a half wide,
two metres from the camera, in the shot a store page leads with — stayed teal on
all six wards. There are TWO screens in a ward and only the far one was ever
passed a bay colour. The probe written to find that reported the room as correct,
because both nodes are named "ScreenPartition", Godot discards the second name
and substitutes the class (gotcha 17), and a search by name found exactly one
screen in a room with two. `get_shader_parameter` cannot confirm a tint either
(gotcha 36); what settled it was the material's instance id, because
`Build.cloth_mat` caches by colour and a colour that did not change is the same
object.

Both screens take the ward's colour at about half strength now, mixed toward a
neutral — the same reasoning `floor_zone` already carried. A bay colour on a
6cm curtain is an accent; the same colour on the biggest flat surface in the
room after the floor is a swatch.

`screenshots.sh` also could not fail on a runtime error. It greps for shader
failures and for its own measured regressions and exited 0 on a `SCRIPT ERROR`
printed in the middle of a page of "shot:" lines — which is how a card built for
the wrong ward got rendered, noticed by eye, and would otherwise have shipped.

### The man in bed was still in his shoes

The bedside camera is the one the whole game is played through, and it showed a
head above a blue lump with two navy shoes sticking out of the near end. Turning
the duvet bright red and re-rendering that one frame — ninety seconds — showed
the cover was exactly where the last pass put it, over the lap, and that the
problem was elsewhere.

Measured: the occupant's mesh boxes through the bed's own inverted transform put
the body at z -1.32..0.20 and the shins and shoes at y 0.78..1.15, against a
20cm cover on a mattress at 0.62 that tops out at 1.01. Fourteen centimetres of
foot coming up through the bedding. Feet tent a blanket; the duvet is as deep as
they are now, and the ward from the door is five made beds rather than five
white trays with people on them.

The probe that measures that has to run PHYSICS frames with the tree unpaused.
The pose is applied in `_physics_process`, the morning briefing pauses the world,
and the first two versions waited on `process_frame` and measured a patient
standing to attention beside the bed — reporting nonsense to two decimal places.

And the bay strip on the floor, which the comment beside it has always described
as "mixed toward the floor's own colour", was mixed toward a literal sage green
chosen when there was one ward. On the slate-blue ward that is a green rug on
lino. It reads `Cases.ward_look()["floor"]` now.

### Fifteen hedges were standing inside the building

The office had two flat pale-green slabs behind the desk with no tooth, no
shading and no detail — they read as an unfinished piece of furniture, which is
why three sessions of looking at that frame never recognised them. They are the
boundary hedge.

The view through the windows is three rings of blocks drawn about the centre of
the floor plan, and the plan is a 20 x 21 rectangle, so a ring of radius 12.5 to
14 clears the long sides and passes straight through all four corners, which are
14.5 out. `_outside_radius(bearing)` returns the distance to the building's own
wall along a bearing now, so the boundary is a rounded rectangle at a fixed
standoff and every window sees it at the same height. The smoke run intersects
every `outside` mesh's footprint with the plan; proven red at fifteen blocks.

Two more signs were still saying Ward C: the station's own whiteboard, in marker,
and the sign hanging from the corridor ceiling — the one a player reads walking
in. The check written last commit could not see either. It matched anything
beginning with "Ward", case-sensitively, against the whole label, so a board that
SHOUTS and a sign with a tail both slipped through; widened, it then swept up
"WARD RECORDS", which is a door. The precise question is "does any sign name a
DIFFERENT ward", so it tests against `Cases.WARDS` itself.

And the red has to be proven on the right line. Breaking the board's build-time
literal proved nothing, because `rename_for_ward` runs on every reskin and put it
straight back.

### 1.0.0

Version bumped from 0.9.0 in `project.godot` and all four fields of
`export_presets.cfg`, which the ship probe cross-checks against each other.
All three platforms export and the Linux build boots and exits clean.

### The shadow trench down the middle of every ward frame

`Dressing._add` gives anything below 5cm a contact shadow sized to its own
footprint. That is right for a bin, a plant or a bedside cabinet and wrong for
the bay strip under the beds, which is an eighteen-metre painted rectangle and
got an eighteen-metre radial blob centred on itself — darkest in the middle,
which is exactly what a shadow trench looks like.

It had been blamed on three other things across two sessions: the zone's own
tint, the ceiling fittings falling off toward the far wall, and five bed shadows
merging into one band. Turning the zone bright red and re-rendering the doorway
frame settled it in ninety seconds — pure red came back at 190 along the strip's
front edge and 73 through the middle, which is not a lighting gradient. After the
fix the strip is uniform at (105, 124, 138) across its whole length, and the
beds' own contact shadows are visible on it again instead of being drowned.

The tint had been `darkened()` twice on top of that, compensating for the blob
from the other end. Both are gone: a bay marking is the ward's floor colour mixed
toward its bay tint, and it is paint rather than an object, so it casts nothing.

### A black hairline on every rounded box in the game

There was a short black dash lying across the bedding of every bed, visible in
the bedside frame — which is the camera the whole game is played through — and
in the visitor frame. It survived six renders of red tests: the bed's side
rails, its bracket posts, the IV stand's crossbar, and two rounds of tightening
the ink cap. None of them was it, because it is not a thin object and it is not
a magnitude problem. What found it was zeroing each cloth piece's own `line` in
turn: the dash belonged to the piece it was drawn on.

Every mesh in this building is a Godot `SphereMesh` Minkowski-summed with a box,
and a SphereMesh duplicates its seam meridian — two vertices at the same point
with different indices, because they need different UVs. `_reface` accumulated
area-weighted normals by INDEX, so each copy got only the faces on its own side
of the seam. Measured after the fix: 140 of 540 shared vertices carried
different normals, and the worst pair were exactly opposite. The outline pass
pushes every vertex along its own normal, so the two copies went different ways
and opened a crack down the meridian; drawn back-faces-only, that crack is a
hairline running from the middle of a face toward its edge.

Gotcha 37 has said since it was written that the hull "only stays closed if they
are shared". They were not. `_reface` accumulates by quantised POSITION now, the
smoke run asserts that a shared vertex has one normal, and it was proven red at
140 of 540.

The two wrong turns are worth keeping. Bounding the ink growth by the mesh's own
corner radius is sound reasoning — an offset surface folds through itself when
the offset exceeds the local radius of curvature — and it moved the number by a
fifth, removed nothing, and would have thinned every outline in the building. It
was reverted. So was a per-piece ink cap on the bedding, which fixed the symptom
on two pieces out of every rounded box in the game.

### The wayfinding was turned ninety degrees from the way people walk

`Dressing.ceiling_sign` faces its own +Z and takes a `rot_y` that both call sites
left at the default. The corridor runs in X. So the two hanging signs — which
carry the only "this way to the ward, that way to the station" the building has —
presented their six-centimetre edge to everybody who ever walked under them: a
blue vertical stripe in the middle of the ceiling, in the first frame a player
sees on leaving their office, with the text on the two faces nobody can see.

A quarter turn, and the board already carries the text on both faces so it reads
walking either way. The plate was also a fixed 1.5 metres while `_wall_sign` has
always sized its plate to its text, so the words hung off both ends into the air;
it takes the same advance-per-character estimate now.

### Two more Ward Cs, on the two biggest pieces of text in the game

The sign check written last commit walks `Label3D`s in the world. It cannot see
a UI screen, and the two remaining offenders were screens: the morning briefing,
whose header is the largest text in the game and the first card of every shift,
and the loading card between the main menu and the ward. Both said WARD C on all
six wards.

They had also survived a `grep "Ward C"` over the whole of `scripts/`, because
they shout — the same lesson as the sign check itself, a second time in the same
week. The static half of the check greps every quoted string in `scripts/`
against `Cases.WARDS` itself now, case-insensitively and on whole words: the
first version matched "Ward C" inside "the ward can see", which is a line on the
records screen.

It also caught `Hospital.LAYOUT`, which spelled both room names out as literals
that `reskin()` corrected a moment later — so between `build()` and the first
reskin, and in every harness that builds a hospital and never reskins, the
corridor a witness quotes was the wrong ward's.

The loading card names no ward at all now. Its own comment already says nothing
on it may read `GameState`, because on the Continue path the save has not been
read yet; a ward name there would have been last career's, printed with total
confidence, for a fifth of a second.
