# SPOILERS — what actually does what

> **Developer reference.** None of this is stated anywhere in the game. The player
> is meant to work it out by watching patients, and the in-game Codex only writes
> a note down after they have personally caused the same effect twice.
>
> If you are playing rather than building, close this file.

## Treatment machines

Machines expose a dial (0–11) and the value the chart prescribes. Everything below
is derived from `deviation = |dial − prescribed|` in `TreatmentMachine.run_cycle`.

| Deviation | Band | Effect scale | Complication chance | Seen weight |
|---|---|---|---|---|
| 0 | normal | ×1.00 | — | 0.00 |
| 1–2 | slight | ×0.72 / ×0.44 | 18% | 0.05 |
| 3–4 | high | ×0.16 / ×−0.12 | 62% | 0.30 |
| 5+ | extreme | negative | 100% | 0.55 |

Additional, and independent of the dial:

- Running a machine **not indicated** for the patient's condition adds a flat 0.40
  seen weight — as visible as picking up the wrong tool.
- Every cycle is written to the machine's own log with dial and prescribed value.
  Deviations of 3+ are what an investigator reads back to you.
- **Calibration** (maintenance panel) multiplies every cycle's effect permanently
  and is invisible to everyone except a technician. Below 0.9 it also adds a 30%
  complication chance. The service-contract upgrade fixes *and reports* it.

## Substitution

`Items.SUBSTANCES[*].effect_as` decides what actually happens; the prop's `label`
decides what everyone thinks happened.

| Substance | Acts as | Notes |
|---|---|---|
| `chalkinol` | chalkinol | genuinely works |
| `placebex` | placebex | works a bit |
| `saline` | fluids | works |
| `saline_plus` | *nothing* | identical in every respect including effect |
| `ambient_dread` | *nothing* | recovered from a patient; should stay in the canister |
| `mop_water` | *nothing* | but reliably causes Reactive Shivers |
| `cold_coffee` | *nothing* | but reliably causes Rebound Hiccups |

Some substances are therapeutically inert and still do something specific:
`Items.SUBSTANCES[*].complication`. Saline Plus genuinely does nothing at all;
recovered ambient dread puts back exactly what the extractor just took out.

**The dread loop.** Running the Ambient Dread Extractor refills the nearest
canister within 6m — the extraction has to put what it took somewhere. That
canister is a physical object with a lid and a label reading `EMPTY — SAFE TO
REFIT`. Decant it into a syringe, administer, and the patient has Ambient Dread
again. Every step is an ordinary, legitimate-looking action; the only visible
moment is the decant itself (0.55 seen weight).

Decanting (`Prop.interact` with another container held) moves contents and leaves
both labels alone. The act carries 0.55 seen weight; the *result* carries almost
none, which is the whole point — a substituted treatment looks correct from across
the room, and what catches you is being seen doing the swap or three days of a
chart insisting you treated someone who isn't improving.

## Complications

`paper_suspicion()` in `Complication`:

| State | Weight |
|---|---|
| documented with a plausible cause, **before** anyone noticed | 0.0 |
| undocumented | `severity` |
| documented with a cause the complication does not accept | `severity × 1.4` |

Filing a cause the chart doesn't accept also reports straight to Administration.

## Environment

`Room.comfort()` multiplies every occupant's recovery rate:

- temperature error × 0.035 per degree from 21 °C (floor 0.35)
- lights off: ×0.88
- cleanliness: lerp 0.8 → 1.02
- noise: down to ×0.7

An open window pulls the room toward 8 °C. Sustained discomfort rolls for an
environmental complication whose *true* cause is `facilities` — genuinely the
building's fault, provided a ticket was filed first (`RecordsSystem.file_facilities_ticket`,
which also grants a `facilities` cover story for 600 minutes).

## Thermostats

Quieter than a window — there is no physical tell in the room, so a nurse walking
in sees nothing out of place. The trade is that a thermostat has a *setting*, and
settings are records: anything 6° or more off 21 lands in the device log and an
inspector reads it back to you. Same bargain as the machine dial.

Rooms honour `Room.target_override` from the thermostat; an open window overrides
both and drags toward 8 °C, which is faster and far more obvious.

## The west annexe

The three departments are physical rooms behind roller shutters from day one.
Opening one changes more than what the shop says it changes:

**Emergency Intake.** The three trolleys are real `PatientBed` nodes in the
`bed` group, so when all five wards are full an admission physically lands on
one instead of vanishing into an invisible waiting list. A patient on a trolley
is admitted and billing — and losing satisfaction about four times as fast as
one merely kept too long (`0.24 × days × impatience`), in the busiest room in
the building, where every member of staff and every visitor walks past them.
Discharging a ward patient calls `_relieve_intake`, which moves the
longest-parked trolley patient into the freed bed.

Beds are rigid bodies on wheels and `_reconcile_room` reads a patient's room
from **where their bed currently stands**, so you can do this to somebody on
purpose. Wheel a ward patient out to Intake and they keep billing, recover
slower in a worse room, lose satisfaction four times as fast, and their ward
frees up for a better-insured admission. It is a two-part job — `free_wards()`
also requires a bed to physically be in the room, so you have to push a spare
trolley in behind you — which is about the right amount of effort for what it
buys. Their chart does not follow them, and a chart in the wrong room is its own
finding.

Ramping is not free. Moving an admitted patient from a ward to Intake emits
`patient_moved_to_corridor` with the player as its actor and visual weight 0.45,
so it goes through perception like anything else you do. Whether it is
defensible is decided by the floor, not by you: if there was another ward with a
bed and nobody in it, no cover is granted. If there genuinely was nowhere else,
`bed_shortage` is added for 420 minutes and any evidence tagged with it is worth
a quarter of its weight while it lasts. Doing this on a full ward is a
legitimate clinical decision. Doing it on a half-empty one is four witnesses.

And leaving them there keeps costing. `Patient.corridor_minutes` accumulates
while a patient is parked in Intake and resets the moment they get a real room.
Past four hours, any nurse whose round reaches them records
`patient_left_in_corridor` at `0.12 + hours × 0.05` (capped at 0.6) — so a busy
morning is nothing and most of a shift is a complaint. It carries the
`bed_shortage` cover tag, which means the same defence applies: worth a quarter
while the ward genuinely has no beds, worth all of it once it does. So a full ward plus an
arrival is a real decision: send a still-profitable overstayer home early, or
let the new one lie in Intake losing goodwill you will pay for in reputation.

Arrivals fire a 60 m hearing event positioned in Intake,
at the far west end of the floor. Every member of staff who hears a noise
investigates it, so an emergency admission reliably empties the east wards for
about a minute. Buying Emergency is, mechanically, a scheduled distraction that
also pays a day rate.

**The Psych Day Room.** Psychiatric admissions recover on `0.35 + satisfaction`
rather than on treatment, and `PatientSystem.tick()` scores every patient against
the comfort of the room their BODY is standing in, not the ward they are assigned
to. Psych patients have a 0.45 urge to sit in the day room for ~40 s at a time
once it is open. So the day room thermostat is a single control that slows every
psych admission on the floor simultaneously, and nothing on any individual chart
points at it. It is the highest-leverage thermostat in the building.

**Radiology.** The imaging bench used to appear in the treatment bay the instant
the upgrade was bought. It is now in Radiology, at the opposite end of the floor
from the wards, and the machine treats whoever is within 3.4 m of it — so using
it means physically wheeling a bed the length of the building and back.

Imaging is the only entry in the record the player does not write. It cannot be
edited, forged or shredded, and it names the cause the SIMULATION knows about,
not the one on the chart. `PatientChart.imaging_findings` records
`{id, name, true_cause, day}` for every active complication at the moment of the
scan, and `audit()` raises `contradicts_imaging` (weight 0.8) for any of them
whose filed cause disagrees. A perfectly clean, plausibly documented
complication passes every audit in the game until somebody points a scanner at
it.

Which is why the department cuts both ways: **colleagues can order imaging.**
`DoctorNPC._maybe_request_imaging` fires on any overdue patient once Radiology
is open — appetite 0.5, ×1.6 for an investigator, ×0.35 for a lazy one, so which
doctor is on shift genuinely matters. The request shows on the tablet. Ignore it
and at clock-out `ShiftSystem._settle_imaging_requests` gives the doctor who
asked an INFERRED memory at weight 0.34 and knocks insurer trust down 0.02 —
there is no way to explain this in the record, because none of it is in the
record.

The counterplay is the aperture. Like every device on the floor it has a
prescribed setting, and `_nearby_patient` now sets that from whoever has been
wheeled in. Run it two or more notches off and the scan degrades to artefact:
nothing enters the record, the request is satisfied on paper, and the only trace
is a line in the Radiology device log that somebody has to walk over there and
read. An alibi today against a document tomorrow.

The control booth screen is the one solid object in the department that breaks
line of sight to the couch.

Shutters block movement, block vision (layer 32) and remove their doorway from
the nav graph, so a sealed department is genuinely sealed — staff will not path
into it and `Hospital.open_room_keys()` will not offer it.

## Shifts

Three, and picking one is the first decision of every day. The trade is not more
or fewer witnesses — it is **witnesses against attribution**.

| | hours | pay | staff on | appointments | scrutiny |
|---|---|---|---|---|---|
| Night | 00:00–08:00 | ×1.45 | 1 | 3 | 0.4 |
| Day | 08:00–16:00 | ×1.00 | 5 | 7 | 1.0 |
| Evening | 16:00–24:00 | ×1.20 | 3 | 5 | 0.7 |

Staffing is a fixed rota (`DB.ROTA`), so which individuals are on is a fact
worth learning rather than a nightly dice roll. Off-duty staff leave the
building and cannot witness anything — but they keep every memory they already
had, and they come back tomorrow.

Every acquired injury records `caused_on_shift` and `staff_present`. When a
nurse later works out the pattern, their certainty is `1.15 − 0.13 ×
staff_present`, clamped to [0.4, 1.0]. A wrist that went during a night shift
with one other person in the building is near-certain; the same wrist on a day
shift is one of six possibilities. **The quiet shift is not the safe shift.**

## Examination

Same grammar as every machine: a site, a dial marked APPLIED PRESSURE, an
indicated value of 2, and nothing said about what is above it.

- `injury_chance(p) = clamp((p − 3) × 0.115, 0, 0.92)` — zero at 2 and 3, still
  climbing at 11.
- `exam_visibility(p) = clamp(0.04 + (p − 2) × 0.095, 0.04, 0.92)`.

At the indicated pressure it is genuinely worth doing: it sharpens your read on
where the patient actually is for a while, adds satisfaction, and satisfies a
booked physical or review. If the honest setting were useless the dial would be
a button that only exists for crime and would read that way immediately.

Above it, the part you are examining is the part that gives, with `true_cause`
of `examination` — a mechanism no chart will accept. The patient is always a
witness to their own examination, at certainty `0.35 + observance × 0.6`.

## Injuries, and the arrival-versus-discharge gap

Six injuries exist **twice**: in `CONDITIONS` as what somebody walks in with, and
in `COMPLICATIONS` as what they leave with. They read identically on purpose —
if they did not, "which kind is this" would be answerable from the name.

`PatientChart.audit()` reads the gap:

| finding | weight | when |
|---|---|---|
| `unexplained_injury` | 0.35 + sev × 0.45 | acquired here, no mechanism filed |
| `injury_predated` | 0.75 | filed as "present on admission", dates disagree |
| `injury_pattern` | 0.55 + 0.3 × (n − 1) | **two or more** acquired in one admission |

Filing a mechanism closes the individual gaps and does nothing about the
pattern. That asymmetry is the design: being a careful liar beats being a
careless one, and neither beats not doing it three times to the same person.

Nurses do the arithmetic on rounds from two injuries upward
(`StaffNPC._note_injury_pattern`) and there is no cover tag on it, because there
is no cover story for arithmetic.

## Surgery

Three stages, each done `careful` / `quick` / `improvise`, recorded in theatre
language: "as per protocol", "expedited", "approach modified intra-operatively".

| approach | risk | quality | visible |
|---|---|---|---|
| careful | 0.02 | 1.0 | 0.0 |
| quick | 0.14 | 0.75 | 0.12 |
| improvise | 0.60 | 0.30 | 0.45 |

What goes wrong goes wrong at the operative site, and every site's injury lists
`known_risk` among its plausible causes — so a botched operation is the most
deniable way in the game to hurt somebody. The catch is the theatre record,
which is not yours: two or more improvised stages on one patient raises
`improvised_procedure` at 0.4 + 0.25 per operation.

A by-the-book operation genuinely helps (+0.34 recovery at full quality), which
is what makes the approach a choice rather than a lever.

**The site.** Every operation has an indicated site — the injury they have, or
the body part their condition is about — stated on the theatre screen and then
not enforced, exactly like a machine's prescribed value. Operating somewhere
else sets recovery to −0.05, forces the complication risk to at least 0.8,
raises the act's visibility to 0.35 regardless of approach, and writes both the
site you opened and the site you were meant to into the theatre record. The
audit raises `wrong_site` at **0.95**, the heaviest single finding in the game.
There is no cover story for it and there never will be.

## What you make of them

Every patient carries a short read in your character's words, derived from
`mind.observance` and the archetype's `escalation`. It is never advice — there
is a test that walks every archetype and asserts no line contains "safe",
"risky", "witness" or "avoid" — and it is a GUESS until you have examined them.

`Patient.read_bias` is a fixed per-person error in the range ±0.24, rolled at
admission and stored, so the read does not flicker while you look at it. It is
zeroed for four in-game hours after an examination (`read_is_fresh()`), and the
notes say so out loud while it is not. This is the quiet argument for the honest
examination: the dial at its indicated value is how you find out whose account
of the afternoon anybody would believe.

## The pharmacy

Three kinds of take-home. **Indicated** ends the story. **Inert** means whatever
was wrong with them is still wrong with them, 50% to book a readmission.
**Reactive** is 85% to book one, and they come back with a complication whose
true cause is `prescription`.

A readmission is a fresh admission at a fresh daily rate with a completely
honest explanation — the closest thing in the game to a renewable resource. They
are booked 2–5 days out so the patient genuinely goes home in between, and
somebody who has been round the loop once comes back with +0.2 observance and
−0.3 trust.

The chart raises `prescription_mismatch` at 0.45 for anything not indicated. The
pharmacy is the one device log in the building the player cannot reach.

## Money, and where it is not

Deliberately thin margins on everything except beds:

| | fee | cost | net |
|---|---|---|---|
| Physical (walk-in) | 300 | 265 clinic overhead | 35 |
| Review | 120 | — | 120 |
| Procedure | 4600 | 3850 theatre time | 750 |
| Discharge | 150 | — | 150 |

A clinic that paid for itself would invert the premise a second time. The reason
to want theatre on your list is not the fee — it is that an operation is the
most deniable place in the building for something to go wrong, and a
complication is a fortnight of bed days.

## Ward-acquired injury rate

The insurer watches **injuries per patient-shift**, measured against how many
people are ON the ward rather than how many left it (`ShiftSystem
.rolling_injury_rate`). Baseline 0.06, tuned against a five-bed ward; files
`injury_rate_outlier` above 2× at weight `(over − 1.9) × 0.11`, capped at 0.85.

The denominator is the point. The complication rate divides by discharges and
goes blind on a ward that never lets anybody leave, so "fill every bed with
people you hurt and discharge nobody" would otherwise have switched the
statistics off entirely.

## Charts in the wrong room

Charts are physical props you can carry. An investigator that reaches a bed and
finds the chart somewhere else records a `chart_misfiled` finding (0.4) — a
smaller penalty than a shredded chart (0.85), and unlike shredding it is
recoverable by putting it back before anyone gets there.

## Being seen

`NPCPerception.evaluate`: 112° FOV, 13 m range, LOS blocked by walls and **closed
doors**. Inside 3 m the FOV check is skipped. Perception rolls against
`observance × attention`; noise drops attention by 0.55 and takes ~2.5 s to recover.

`Evidence.current_weight`:

- source multiplier — witnessed 1.0, record 0.8, inferred 0.6, heard 0.45, gossip 0.35
- decay per day — witnessed 0.10, heard 0.22, gossip 0.28, inferred 0.04, record **0.01**
- corroboration — `× (1 + 0.55 × witnesses)`, which is why isolating people matters
- active matching cover story — ×0.25
- neutralised (talked your way out) — ×0.12, never zero

## Complaints that have nothing to do with suspicion

`Patient.satisfaction` starts between 0.55 and 0.85 and falls: 0.06/day ×
impatience once they are past their expected discharge date, 0.24/day × 
impatience while parked on a trolley in Intake, a little more each time they are
startled or ignored. Below **0.18** they file a formal complaint about their
CARE — `SuspicionSystem.file_complaint` at severity `0.35 + (0.18 − sat) × 2`,
capped at 0.8. That is heat, and heat is what brings people to look at you.

Nothing in this path requires anybody to suspect anything. A perfectly
documented, entirely deniable career that simply treats people badly still ends
up under investigation, which is the point: being bad at the job is a separate
failure state from being caught at the crime. One patient files one complaint.

## Statistics

Two independent end-of-shift signals, both landing on Administration and the insurer
as slow-decaying `INFERRED` evidence:

- **length of stay** — fires above 0.6 days over projection on average
- **complication rate** — fires above 1.6 × the 0.34/discharge ward baseline,
  computed over a rolling six-shift window

The second one is what stops immaculate paperwork from being a free win. The
counter-play is genuine volume: cure a lot of people quickly and a handful of
profitable outliers disappears into the denominator.

## Money

The load-bearing constant is `EconomySystem.ADMISSION_COST` (850). Without it,
turnover beats duration on a five-bed ward and the entire premise inverts —
see the note in that file. Complications add 26% each to the daily rate, and a
long complicated stay escalates a further 5%/day to a 45% cap.
