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
| `mop_water` / `cold_coffee` | *nothing* | |

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
