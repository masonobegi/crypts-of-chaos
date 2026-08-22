# Where this is, mid-surgery

Written because a session was interrupted. Everything below is committed and
pushed on `claude/github-repo-deletion-3hf0gq`.

## The suite is green and safe to build on

```
GODOT=/tmp/Godot_v4.3-stable_linux.x86_64 ./run_tests.sh
271 unit assertions · 70 smoke checks · 7/7 playtest criteria
20 authored people across 4 wards · boot check · exit 0
```

`/tmp/Godot_v4.3-stable_linux.x86_64` is the engine. Nothing in the game is
broken; the unfinished work is a MEASUREMENT that disagrees with a hand-played
result, described below.

## What landed this session

**The fourth ward — "the ones from last night".** Five new people
(`Cases.DAY_FOUR`, `PRIOR_FOUR`), wired into `DAYS` / `PRIOR_BY_DAY`. The theme
is that Dr Costa covered the night and every bed carries an opinion he already
wrote; two of them are wrong, one in each direction.

Three new mechanics support it:

- **`colleague_wrong`** (`WardDay.ask_colleague`). The registrar was an
  infallible oracle — 25 minutes bought certainty AND the strongest defence in
  the game. On a patient carrying this flag he restates his morning opinion
  instead of looking again, in his own name, at your request. Which leaves
  `examine` as the only verb that cannot be wrong, and it is the one that
  writes nothing.
- **`test_reveals`** (`WardDay.resolve_test`). `only_visible_in_person` hid a
  patient from the rounds, the nurse AND the laboratory. Gwen Ashworth needed
  exactly one corroboration route or the correct hold on the ward was
  uncorroboratable by construction. Repeat bloods are it: 5 minutes to order,
  75 to come back.
- **`_leaned_on_last_night`** (`contradictions.gd`). A bed whose only support
  was written before your shift, by somebody who has gone home. Gated on
  `looked_at`, because the question it asks out loud is "did you see this
  patient at all".

And **a justified reversal is no longer a contradiction**. Holding somebody the
night registrar wrongly cleared used to make the bed indefensible, so the
correct play on ward four was punished exactly as hard as a lie. If you
examined them AND they are genuinely unwell, severity drops to 0.12 — she still
asks, the bed still stands. Graded like `backdated` rather than listed.

## The one thing that is NOT finished

**The frontier probe cannot find a signed-off day on ward four, but one
exists.** Played by hand, this is SIGNED OFF, 0 indefensible, 0 solo, $2,750:

```
order_test("ashworth", "Repeat bloods")   # 08:00, lands ~09:20
examine("ashworth"); examine("vane")
read_chart on pyne, petrossian, threlfall  # so nothing is decided blind
advance to 11:00
write_entry("ashworth", UNWELL, "...", now)
hold ashworth + vane, discharge the other three
```

The probe reports "never reached" because its search space does not contain
that combination. I widened it twice this session — added `diligent` runs
(bloods on every held bed at 08:05, then look at everybody) and an `own_note`
verb (examine, then write it up promptly in your own name, which the list
genuinely lacked — every write-it-yourself strategy in there wrote at 17:20 or
19:00, which is the CRIME shape). Ward four still reports no clean day.

**Next step: find out which of the two it is.** Either the probe still lacks
the combination, or something in the game makes the hand-played day
unreachable under the probe's exact ordering. The way to tell is to make the
probe replay the hand-played sequence verbatim as one extra strategy and see
what verdict comes back. A scratch harness under `tests/scratch/` (gitignored,
and skipped by `test_all_scripts_compile`) is the place for it.

Do not "fix" ward four's content until that question is answered — the ward
itself measured correctly by hand.

## A probe bug fixed on the way out

`frontier_impl._day()` cleared `remembered_beds` and `carried_debt` but not
`Cases.READMIT_FLAG`, which was reset once per WARD and written by any run in
which somebody bounced. So every strategy after the first wrongful discharge
searched a different roster from the ones before it. The ward-four numbers
changed shape twice between identical runs while nothing about the ward
changed, which is what gave this away. Same lesson as CLAUDE.md 16.

**The last full frontier run predates that fix**, so its numbers are not
trustworthy. Re-run it before drawing any conclusion:

```
godot --headless --path . --script res://tests/probe/frontier_run.gd   # ~25 min
```

## Also outstanding

- A background workflow (`chronic-care-perfection-hunt`) was auditing the code
  for dead constants, unreachable findings and broken UI promises. Its findings
  had not come back. Re-run it or audit by hand.
- The career probe has not been run since ward four landed. It plays eight
  policies over twenty nights and asserts six properties; a fourth ward changes
  the rotation, so it needs re-measuring.
