# SPOILERS — what actually does what

> **Developer reference.** None of this is stated anywhere in the game. The
> player is meant to work it out by watching people and by being asked about it
> at eight o'clock.
>
> If you are playing rather than building, close this file.

> **This file was rewritten from scratch.** The version before it described
> treatment machines with dials, complications with true causes, substances,
> upgrades, a service contract and a statistical review team — the game that
> `docs/REDESIGN.md` replaced. None of it had existed for several reworks, and
> `CLAUDE.md` pointed here as the developer-facing truth, so the project's own
> reference lied about the game to anybody who read it. That is not a
> hypothetical cost: this session lost real time to `VisitorNPC`, 115 lines of
> never-instantiated code that read like a feature.

---

## The shape of it

You owe **$15,500**. **$2,200** of it is due at eight o'clock tonight, and
whatever is still owed at the end of a night grows by **10%** before the next
one. You start with **$900**.

A ward is **5 beds**. A night in one pays by who is paying for it — **$850**
premium, **$450** standard, **$180** state. Sending somebody home pays **$150**
once, and frees the bed for one of the **2** admissions waiting downstairs at
**$500** each.

That last inequality is the whole economy and it is deliberate: an admission is
worth *less* than a premium night and *more* than a discharge. It is what makes
holding a state-funded patient cost you money, and it is what stops "hold
everybody" being the answer. Four and five held beds earn less than three.

---

## What the simulation knows and the chart does not

Every authored patient carries a `truly_well` the game never shows you. It
decides what an examination finds, what the nurse writes when she goes and
looks, and what a test comes back as. Nothing else reads it.

Four fields decide how hard the truth is to reach, and they are what make each
ward a different problem:

| Field | What it does |
|---|---|
| `only_visible_in_person` | The nurse goes, finds nothing, and writes that down. Only `examine` finds it. |
| `test_reveals` | The lab overrides `only_visible_in_person`. On those beds, bloods are the only corroboration available. |
| `colleague_wrong` | The registrar's opinion is already on the chart and it is wrong. Asking again gets the same answer in writing, **at your request**, which is worse than not asking. |
| `suggestible` / `recall` | How readily somebody agrees with a leading question, and whether they remember agreeing when the ward sister asks them in the morning. |

**The fourth ward is built on the first three.** Gwen Ashworth was cleared for
home by the night registrar and he was wrong; only an examination finds it; the
nurse cannot see it; asking him again makes it worse. The clean line is
examine → write it up → order bloods, and do not ask the two people who have
already told you. Every one of those traps is legible on the chart before you
touch anything, which is what makes it fair.

---

## The six verbs, in minutes

The day runs 08:00 to 20:00 and every verb spends it.

| Verb | Cost | What it actually buys |
|---|---|---|
| Read the chart | 12 | Everything written today, and *when* it was written |
| Ask how they have been | free | Nothing, unless you write it down |
| Ask a leading question | 10 | A symptom in the patient's mouth — if they go along with it, and if they remember doing so |
| Examine them | 15 | The truth. Goes in no notes. |
| Ask the nurse | 15 | She writes what she finds, in her own name |
| Ask the registrar | 25 | The strongest corroboration there is, and he keeps his own hours (11:00–13:00, 15:00–17:00) |
| Order bloods | 5 | + **75 minutes** before it lands |
| Write a note | 8 | Two timestamps: when you say it happened, and when you typed it |

---

## How a night is judged

Every held bed lands in one of four states, and the verdict is a count of them.

| State | Meaning |
|---|---|
| `BACKED` | Somebody other than you put a reason in the record |
| `SOLO` | Your word, and only your word |
| `CONTRADICTED` | The record actively disagrees with the reason you gave |
| `NONE` | There is no reason in the record at all |

```
2+ indefensible ................. REFERRED
1 indefensible, or 2 solo ....... FLAGGED FOR AUDIT
1 solo .......................... NOTED
otherwise ....................... SIGNED OFF
```

A **discharge** is audited the other way up: there is no reason to corroborate,
so the question is whether anything said they should have stayed, and whether
you can show you looked at them at all.

### The strike ladder

`CLEAR −1 · QUESTIONS 0 · FLAGGED +1 · ESCALATED +3`, floor of zero, and **5**
ends the career. A clean night pays a strike back, which is why one bad night is
survivable and four are not.

### The two rates

These are the part nobody can see and the part that ends most careers. Measured
across the whole career rather than tonight, because one bad night is a bad
night and a ward runs on those — it is the ratio that describes a person.

| Rate of beds only you ever saw a reason for | What changes |
|---|---|
| ≥ 0.5, after 4 nights | She stops accepting "only I saw it" as a defence of the **bed**: a SOLO bed becomes indefensible |
| ≥ 0.75, after 5 nights | She stops accepting it as a defence of **you**: one indefensible bed is a REFERRAL rather than a flag |

The gap between them is the entire game. **A bed on your word alone every other
night is survivable forever**, and that is the policy the design is trying to
make findable. Doing it every night is struck off on night six.

Both are written down for the player at the handover, under ON YOUR RECORD.

---

## The twenty-five things she can notice

`Contradictions` produces findings with a severity 0..1. The heaviest, roughly:

```
0.92  came back in the night and you sent them home AGAIN
0.85  sent home with a nurse note saying they should stay
0.80  readmitted within a day of a discharge you signed
0.78  overruled a colleague without going and looking
0.72  the patient asked you to keep them in and told her so
0.70  no reason recorded at all / the family read the notes
0.65  a note timed for a minute you were seen somewhere else
0.60  invited a contradiction — you asked, and they disagreed
0.55  a stay nobody but you ever saw a reason for
0.40  three notes explaining each other
0.10..0.90  backdated, by how far
```

Two multipliers sit on top and they compound with everything:

- A file already marked for review reads at **×1.6**.
- A kind she has raised before reads at **×(1 + 0.28n)**, capped at **×2.2**.

And a note is only "the same moment" as another within **45 minutes**, which is
what makes writing in the gap between her rounds the central timing skill. She
rounds at 10, 13, 16 and 19 — and after a flag she writes up **twice**, 45
minutes after each, which leaves three real windows instead of six.

---

## What the player is told, and when

Nothing is ever labelled "questionable". No suspicion number, no recovery delta,
no "+3 days". The three layers — what is true (`truly_well`), what is recorded
(the chart), and what people believe (`Mind`) — are allowed to disagree, and all
of the comedy is in the gaps.

The player finds out by being asked at eight o'clock, and every question names
the two documents that produced it.
