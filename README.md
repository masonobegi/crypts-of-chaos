# Chronic Care

**A broke doctor. A struggling hospital. Patients who really should have gone home by now.**

A first-person, physics-driven dark-comedy hospital sim. You are $435,000 in debt and
you make $240 a shift. The hospital bills for every day a patient stays, and your bonus
is a share of that. Nobody will ever ask you to do anything unethical — they don't have to.

Everything medical here is **fictional and absurd**. Inflamed Funny Bone, Chronic Beige,
Excessive Spleen Torque. The comedy is bureaucracy and slapstick; nothing in this game
describes a real way to harm a person.

---

## The idea

Most "be a bad guy" games give you a `DO CRIME` button. This one doesn't. There is no
setting labelled *questionable*, no tooltip that says *+3 days, +8% suspicion*. There is a
dial, a prescribed value, and a patient. You work out the rest by watching what happens.

Three layers of state, which are allowed to disagree with each other:

| Layer | What it is | Where it lives |
|---|---|---|
| **Truth** | What actually happened to the patient | `Patient.recovery`, `Complication.true_cause` |
| **Record** | What the hospital officially believes | `PatientChart`, machine logs, billing |
| **Belief** | What each individual person thinks | `Mind` + `Evidence`, per character |

All of the comedy — and all of the tension — lives in the gaps between them.

## The loop

Clock in → patients arrive with ridiculous conditions → diagnose → treat them properly,
or don't → manage the people who noticed → get your paperwork in before anyone asks →
survive the chart review → clock out → pay your debts → buy something that makes it
worse → next day.

### Suspicion is not a meter

Nobody has a suspicion stat you can edit. Characters hold **evidence**: discrete,
timestamped records of things they personally saw, heard, were told, or worked out.
Suspicion is *derived* from that evidence, weighted by their personality and how much
they trust you.

Because evidence is an object rather than a number, you can fight it:

- **it fades** — but records and inferences barely do
- **it can be contradicted** — a cover story filed first discounts it heavily
- **it spreads** — gossip degrades with each retelling, but reaches more people
- **it corroborates** — two witnesses to the same act is far worse than twice one witness,
  which makes *isolating witnesses* a real tactic
- **it can be destroyed** — the shredder is right there, and a missing chart is its own
  kind of evidence

### Complications are the product

Patients leave when they're better. Stays are extended by **complications** — Ambient
Dread, Ferrous Aura, Rebound Hiccups — and every complication carries both what actually
caused it and what you wrote down.

A complication with a plausible cause, filed *before anyone noticed*, is just medicine.
The same complication with nothing on the chart is an incident report. The actual verb of
this game is not "sabotage" — it's ***manufacture a complication and get in front of it
with a story.***

### Things that will catch you

Nurses who stop what they're doing and watch you. Families who count the days. Machines
that log every setting you ever dialled. A colleague who reads charts for fun. An insurer's
analytics team that notices your length-of-stay average drifting. An undercover patient
you will never be told about.

Getting caught is a nine-rung ladder — complaint, warning, review, probation, malpractice,
board, police, struck off, arrested — and two clean shifts walks you back down it.

## Running it

Requires **Godot 4.3+**.

```bash
godot --path .              # or open project.godot and hit F5
GODOT=/path/to/godot ./run_tests.sh
```

**Controls** — `WASD` move · `E` use (hold for procedures) · `LMB` grab · `RMB` throw ·
`Shift` sprint · `Ctrl` crouch (also rotates held objects) · `Q` tablet · `Esc` pause.

## What's in the box

One complete hospital floor, generated procedurally from a single layout table: corridor,
five patient rooms, lobby, nurses' station, treatment bay, supply room, staff WC, and your
office. Hinged physics doors that block line of sight. Wheelable beds with patients still
in them. Twenty-five physics props, all of which make noise, and noise moves people.

There are no art or audio assets. Every mesh is built from primitives at runtime and every
sound is synthesised into a waveform on first play.

| System | File |
|---|---|
| Truth/record/belief model | `scripts/core/`, `scripts/systems/mind.gd`, `evidence.gd` |
| Perception (FOV, LOS, hearing, attention) | `scripts/npc/perception.gd` |
| Witnesses, corroboration, gossip, heat | `scripts/systems/suspicion_system.gd` |
| Dialogue with real odds | `scripts/systems/dialogue.gd` |
| Patients, treatment, recovery | `scripts/systems/patient_system.gd`, `treatment_system.gd` |
| Paperwork crime | `scripts/systems/records_system.gd` |
| Investigations & the sanction ladder | `scripts/systems/investigation_system.gd` |
| Economy, debts, upgrades | `scripts/systems/economy_system.gd`, `upgrades.gd` |
| Procedural world | `scripts/world/` |

Design rationale, including a critique of the original brief and the five things that
changed because of it, is in [`docs/DESIGN.md`](docs/DESIGN.md).

## Tests

```
327 assertions   — units, integration, save round-trips, floor connectivity
 37 smoke checks — boots the real scene and plays a whole shift headless
  8 balance checks — three full careers, asserting the design intent holds
```

The balance harness (`tests/balance_sim.gd`) plays sixteen-day careers with three
strategies and asserts things like *"careful cheating out-earns honest practice"*. It has
already caught one design inversion that no unit test could: with only five beds, curing
people quickly and refilling the bed originally out-earned prolonging a stay, which
inverted the entire premise. That's why admission is expensive and marginal days are cheap.

## Careers

One career runs to an ending — Saint, Tycoon, Medical Mafia, Fraud King, Whistleblower,
Legendary, Struck Off, Custodial, Repossessed — evaluated against the whole run rather
than picked from a menu. Each ending unlocks a starting perk for the next career, shaped
by how that one went: going bankrupt gets your loans consolidated, going to prison means
somebody outside owes you a favour, being struck off leaves you with thicker skin.

## Screenshots

```
GODOT=/path/to/godot ./screenshots.sh
```

Renders the game offscreen through Xvfb and photographs every room and every UI screen.
Worth running after any visual change — it has caught five layout and economy bugs that
no amount of simulation testing could see.

## Status

Milestone 1 (playable vertical slice) is complete and verified end to end. Next up:
departments beyond the ward, and a human playtest for feel.
