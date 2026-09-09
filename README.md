# Chronic Care

**A doctor in debt. Five beds. You are paid by the night, and nobody is getting better.**

A first-person dark-comedy hospital sim about paperwork. You owe $15,500. Vinnie
wants $2,200 of it at eight o'clock tonight, and everything still owed at the end
of a night grows by ten per cent before the next one. You have five beds and a
day, and every night somebody spends in one of them is money.

Everything medical here is fictional and the comedy is bureaucracy. Nothing in
this game describes a real way to harm a person.

---

## The idea

Most "be a bad guy" games give you a `DO CRIME` button. This one doesn't. There
is no setting labelled *questionable*, no tooltip that says *+3 days, +8%
suspicion*. There is a person in a bed, a chart, and twelve hours.

You are not poisoning anybody. You are **noticing a symptom slightly harder than
it deserves, at a convenient hour, in front of the right person** — and then
living inside that claim for the rest of the shift.

Three layers of state, allowed to disagree:

| Layer | What it is | Where it lives |
|---|---|---|
| **Truth** | Whether they are actually well | `truly_well`, which the game never shows you |
| **Record** | What the hospital believes | `Records`, and the two timestamps on every entry |
| **Belief** | What each person thinks | `Mind` + `Evidence`, per character |

All of the comedy, and all of the tension, is in the gaps.

## The loop

Eight in the morning. Five beds, five people, all five to decide. **Read a
chart. Look at somebody. Ask the nurse. Ask the registrar. Order bloods. Write a
note.** Every one of those costs minutes off a twelve-hour day, and the day is
the only resource that never comes back.

At eight o'clock Sister Nkemelu has the folder, and she asks about what you
wrote. Then Vinnie is at the door.

### Every note carries two times

When you say it happened, and when you typed it. A note stated for 18:35 and
written at 19:05 says so, on the chart, in red, forever. She rounds at ten, one,
four and seven, and anything inside forty-five minutes of a round she wrote is
two people disagreeing about the same half hour.

Writing in the gap between her rounds is the central skill of the game. After a
flag she writes up twice as often, which halves the gaps — but never closes
them.

### Suspicion is not a meter

Nobody has a suspicion stat you can edit. Characters hold **evidence**:
timestamped records of things they personally saw. Suspicion is *derived* from
that evidence, weighted by their personality and how much they trust you — so
typing a fabrication at the bedside with the patient watching is a different act
from typing it in your office with the door shut, and the building is what says
so.

### Nobody is trying to catch you

Adeyemi writes what she finds, in her own name, because that is her job. The
registrar has an opinion and two hours a day in which to give it. A daughter who
used to be a ward sister arrives at seven and reads her mother's notes. None of
them is investigating you. They are just there, and they write things down.

### The morning after

Every bed you kept gets a line on the next morning's card saying what its night
was — the second line that went in at three, the neighbour who rang at seven to
say she still had the key, the woman who was dressed by six and asked which form
she needed. Not only the beds that needed keeping: prose for the right decisions
and silence for the rest would be a score, and this game does not keep one.

Somebody you sent home who should not have gone is in a bed the next morning
instead, worse, taking an admission's place — with a new note on the chart, an
audit flag, and a different thing to say to you every time you go back.

### What it costs

A night in a bed pays $850, $450 or $180, depending on who is paying. A
discharge pays $150 once and frees the bed for an admission worth $500. That
single inequality — an admission worth *less* than a premium night and *more*
than a discharge — is what stops "hold everybody" being the answer.

Getting it wrong is not a game over. `CLEAR −1 · QUESTIONS 0 · FLAGGED +1 ·
REFERRED +3`, and five ends the career. A clean night pays a strike back, which
is why one bad night is survivable and four are not.

## Running it

Requires **Godot 4.3+**.

```bash
godot --path .                                   # or open project.godot and hit F5
GODOT=/path/to/godot ./run_tests.sh              # the whole suite
GODOT=/path/to/godot ./check.sh scripts/foo.gd   # parse errors for specific files
GODOT=/path/to/godot ./screenshots.sh            # render offscreen, photograph every screen
GODOT=/path/to/godot ./faces.sh try1             # six faces close up, for character work
GODOT=/path/to/godot ./export.sh all             # Windows, Linux, macOS
GODOT=/path/to/godot STRICT=1 ./export.sh all    # ...and what a RELEASE has to pass
```

`export.sh` builds all three targets and then *runs* the Linux one, because an
export that produces a file and an export that produces a game are different
claims. `STRICT=1` additionally fails the build on the things that are only
cosmetic to a developer and are the first thing a buyer sees: a placeholder
bundle id or company name, a preset version that has drifted from
`project.godot`, and a Windows exe with no icon or version block because rcedit
was not installed.

**Controls** — `WASD` move · `E` use · `LMB` grab · `RMB` throw · `Shift` sprint ·
`Ctrl` crouch · `Esc` pause. All rebindable; the HUD reads the bindings rather
than printing them.

## What's in the box

One hospital floor built from a single layout table: a corridor, a five-bed
ward, a nurses' station and your office. Hinged doors that block line of sight.
Forty authored patients across four wards, of whom five are dealt each morning —
the same board is never guaranteed twice, and every one of them is written
rather than generated.

There are no art or audio assets. Every mesh is built from primitives at
runtime, every character's face and build is derived from who they are, and
every sound — including the ninety-four-second score — is synthesised into a
waveform on first play. The one exception is type: a letterform is not
something you can reason your way to from boxes and spheres, so the game sets
in four open-licensed families (see **Licence** below).

| System | File |
|---|---|
| The day, the six verbs, the clock | `scripts/systems/ward_day.gd` |
| What the ward sister notices | `scripts/systems/contradictions.gd` |
| The handover, and what she accepts | `scripts/systems/review_system.gd` |
| What she remembers about you | `scripts/systems/doctor_record.gd` |
| Every authored patient and the economy | `scripts/systems/cases.gd` |
| Truth/record/belief | `scripts/systems/mind.gd`, `evidence.gd` |
| Perception (FOV, LOS, hearing) | `scripts/npc/perception.gd` |
| Bodies, faces, builds | `scripts/npc/npc_body.gd`, `scripts/util/appearance.gd` |
| Procedural world | `scripts/world/` |

Design is in [`docs/REDESIGN.md`](docs/REDESIGN.md). What actually does what,
for developers only, is in [`docs/SPOILERS.md`](docs/SPOILERS.md). The build log
is [`PROGRESS_LOG.md`](PROGRESS_LOG.md).

## Saving

**One slot, written once a night, at the handover.** A shift is one sitting —
about ten minutes — and there is no mid-shift save: leaving the ward loses
today, and the pause menu says so in plain English before you do it. What that
buys is that a shift cannot be rewound one decision at a time, which is the
whole game.

The autosave is written to a temporary and renamed into place, keeping the
previous night beside it as a `.bak`. If the primary will not parse, the game
falls back to that and says it has. If neither will — a truncated write, a file
from a newer build, something that is not a save at all — the title screen
offers no `Continue` at all rather than a button that starts a career which
looks new and is not one.

A shipped build writes a rotating log to the platform user-data directory
(`%APPDATA%\Godot\app_userdata\Chronic Care\logs` on Windows), beside the save.
If it ever goes wrong, that is the file to send.

## Tests

```
341 assertions   — units, integration, save round-trips, floor connectivity
210 smoke checks — boots the real scene and plays a whole shift, on three seeds
 32 ship checks  — is it a BUILD: identity, corrupt saves, RNG across a load
  7 criteria     — day-level: does the risk actually cost anything
  8 criteria     — career-level: does honest play pay it off, does greed not,
                   and does a night you got right leave a trace in the morning
  4 wards        — every one signs off on the day a careful person plays
 52 deals        — every ward a career can deal, played honestly
  2 play runs    — the buttons actually pressed, pad and keyboard
 21 screenshots  — rendered offscreen, because five real bugs were only visible
```

Run them before committing. Run the screenshots after any UI or world change —
the count of bugs found only by looking is now in double figures.

## Licence

The code and the design are this project's own. The typefaces are not, and are
the only thing in the build somebody else made:

- **Instrument Sans** — © 2022 The Instrument Sans Project Authors
- **IBM Plex Mono** and **IBM Plex Serif** — © 2017 IBM Corp., reserved font
  name "Plex"
- **Nothing You Could Do** — © 2010 Kimberly Geswein

All four are under the [SIL Open Font License
1.1](https://openfontlicense.org/), whose text ships beside them in
`assets/fonts/` and inside every exported build — `export_presets.cfg` carries
an `include_filter` for them, because a `.txt` is not an imported resource and
`all_resources` does not carry one. They are named on the Credits screen too.

The engine is [Godot](https://godotengine.org/) under the MIT licence, which
bundles some eighty further third-party components with notices of their own.
All of them are compiled into the binary and readable at runtime through
`Engine.get_license_text()` and `Engine.get_copyright_info()` — the ship probe
asserts both are there and non-empty, so the material a licences screen needs is
in the build. **Putting a reader on the Credits screen is the one shipping item
still open**, and it is the only gap on this page that matters for a paid
release rather than for taste.

