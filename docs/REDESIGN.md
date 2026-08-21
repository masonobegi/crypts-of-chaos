# CHRONIC CARE — REDESIGN
## One ward. Five patients. One night. One question.

> **Is manipulating records, people and beliefs inherently fun and tense?**
> If one day with five patients is not compelling, forty illnesses and thirty days will not save it.

---

## 1. PITCH

> **You are a doctor who needs $1,500 by eight o'clock. Every patient you keep in
> a bed tonight is money — and every reason you invent for keeping them is a
> document somebody can read tomorrow.**

## 2. PLAYER FANTASY

Not "be evil." **Be plausible.**

You are constructing a version of tonight that is *defensible*. You are not
poisoning anyone. You are noticing a symptom slightly harder than it deserves,
at a convenient hour, in front of the right person — and then living inside that
claim for the rest of the shift.

The feeling to hit: *"Technically I can justify this."*
The feeling that follows: *"...as long as nobody checks the medication log."*

## 3. CORE LOOP

**Minute to minute**
1. Read the ward — charts, people, what the nurses have already written.
2. Pick who stays and who goes. Money vs. exposure.
3. **Manufacture a reason** for each stay: create a finding, at a time, with an author.
4. Maintain it — every later action must not contradict it.
5. Watch what other people write, say and remember. React.

**Day to day**
Morning handover → ward round → the squeeze (money due) → the night → **the
review**, where somebody reads the day back to you.

## 4. CENTRAL VERBS

| Verb | Cost | Evidence it creates |
|---|---|---|
| **Write** a chart entry yourself | seconds at a terminal | Your name. Entry-time metadata. Anyone who sees you at that terminal. |
| **Ask** a leading question | a conversation | Patient-reported finding. The patient remembers being asked. |
| **Have a nurse check** | her time, her goodwill | Independently authored — the strongest record. She remembers why she went. |
| **Order a test** | money, time | Machine-authored truth. May support you. **May contradict you permanently.** |
| **Discharge** | the bed empties | Nothing. Safe. Pays almost nothing. |

Four ways to produce the same sentence in a chart, with completely different
evidence profiles. **That is the game.**

## 5. THE MECHANIC THAT MAKES IT WORK — TWO TIMESTAMPS

Every chart entry records **the time it describes** and **the time it was
written**. The player controls the first. The system records the second.

- Write it **early**, before the event exists → clean metadata, but you commit blind.
- Write it **late**, once you know what you need → informed, but it is backdated
  and the gap is on the record.

That single asymmetry generates most of the tension in the game.

## 6. FIVE PATIENTS — DAY ONE

Five situations, not five stat blocks. Nothing below is shown as a number.

### Bed 1 — **Ivo Marchetti**, 54. Cellulitis, improving.
Premium insurance (**$850/night to you**). Genuinely borderline: the redness has
receded but not resolved. **You can hold him honestly.** This patient exists to
teach the verb without a crime.
*Complication:* he is a talker. He tells the next nurse everything you said.

### Bed 2 — **Dot Kerrigan**, 81. Post-fall, confused in the evenings.
State insurance (**$180/night** — nearly worthless). Cannot reliably remember
today. The easiest person in the building to keep and the least profitable.
*Complication:* her daughter **Ruth visits at 19:00 and is a retired ward sister.**
She reads charts. She notices handwriting that isn't the nurse's.
*The real decision:* Dot has nobody at home. Discharging her is the *honest* act
and it is the one that will bother you.

### Bed 3 — **Hal Brennan**, 39. Post-op day 2, doing well.
Standard insurance (**$450/night**). **Nurse Adeyemi has already written "for
discharge today" in his notes at 09:20.**
*To hold him you must contradict an existing entry by a named colleague.* Either
she is wrong, or you are. That is a permanent, dated disagreement in a document.

### Bed 4 — **Sam Oduya**, 62. Chest pain, all tests negative.
Premium (**$850/night**). Wants to stay — he is frightened and his flat is cold.
He will corroborate anything, gratefully.
*Complication:* he is the only patient who will **volunteer** how well you looked
after him. Enthusiastic testimony is still testimony, and it is specific.

### Bed 5 — **Winifred Blake**, 47. Migraine, resolved.
Standard (**$450/night**). Agreeable, no family, no complaints. Looks free.
*Complication:* **her file already carries an audit flag** from a readmission
three weeks ago, before you started. The reviewer is coming to her chart with
her eyes already open. **The player can only learn this by opening the file and
reading it.** The one that looks free is the one under a light you cannot see
unless you go and look.

### The sixth bed
**A&E has a patient waiting** — premium, a clean one-off **$850 admission** —
who can only come up **if a bed is free.** Holding a $180 patient costs you an
$850 admission. Scarcity does the work that a morality meter can't.

## 7. TRUTH / RECORD / BELIEF

- **TRUTH** — what the simulation knows. Never shown to the player as a number.
- **RECORD** — the chart. Entries with content, stated time, entry time, author, location.
- **BELIEF** — each NPC's own `Mind`: what they personally saw, heard, read or were told.

They are updated by *different events*, which is why they drift:

| Event | Truth | Record | Belief |
|---|---|---|---|
| Patient is actually fine | ✔ | — | patient knows; nurse may notice |
| You write "dizzy 20:30" | — | ✔ | only people who read it |
| Nurse rounds at 20:45 | — | ✔ (hers) | hers, first-hand |
| You tell Ruth he's "not quite right" | — | — | Ruth's only |

A **contradiction** is two of these that cannot both be true. Contradictions are
not detected by a die roll — they are found by a person who looks along an axis.

## 8. EVIDENCE — WHAT CREATES IT

Every profitable act leaves at least one:

| Act | Leaves behind |
|---|---|
| Writing an entry | author, entry-time, terminal location, anyone in sightline |
| Backdating | the gap between stated and entry time |
| Leading question | the patient's memory of being asked |
| Asking a nurse to check | her memory of *why she went* |
| Ordering a test | a result that is true whatever you wanted |
| Contradicting a colleague | a dated disagreement, and her opinion of you |
| Being in a room | anybody who saw you enter, and when |

**Contradiction types the reviewer can find:**
1. Two entries about the same window that disagree.
2. An entry stated at 20:30 and written at 23:10.
3. You authored an entry while a witness places you elsewhere.
4. A patient-reported symptom the patient does not remember reporting.
5. An order with no matching dispensation.
6. A finding no routine observation supports.

## 9. NPC BELIEF

NPCs learn by: **witnessing** (line of sight, in the room), **hearing**,
**reading** (they open charts — nurses read their own patients, Ruth reads her
mother's), and **being told**.

They forget: first-hand memory decays slowly, hearsay fast, **anything written
down never decays**.

They share: nurses talk at handover. Whatever Adeyemi believes at 20:00 becomes
what the night staff believe at 20:15.

They become suspicious not by a counter but by **holding two beliefs that
conflict**. That is what makes them start asking questions — and the player's
only warning is behavioural: a nurse re-reads a chart, a daughter goes quiet,
somebody checks a time.

## 10. MONEY — WITH THE PROOF

```
Cash on hand                       $900
Owed tonight, 20:00              $2,400
Shortfall                        $1,500

Your cut, per extra night:  premium $850 · standard $450 · state $180
Completion fee, honest discharge:            $150
A&E admission (needs a free bed):            $850  (one-off)
```

**Honest ceiling:** 5 discharges ($750) + the A&E admission ($850) + $900
= **$2,500 against $2,400.** 

**Honesty pays — by $100.** The honest path is not blocked; it is *tight*, and it
requires you to send home an 81-year-old who has nobody and a frightened man with
a cold flat. **The cost of the honest path is moral, not financial.** That is a
far better first day than "you must commit fraud."

**Minimum-crime path:** discharge Dot (frees the bed → $850 admission), hold Hal
($450), discharge the rest ($450) = **$1,750.** One manufactured hold.

**Greed path:** hold all five = $2,780. Comfortable, and five separate stories to
keep straight in front of one reviewer.

**Missing the payment is not game over.** Vinnie adds $600 and **visits the ward
tomorrow** — a new pair of eyes in your workplace, permanently.

## 11. THE REVIEW — THE MORNING HANDOVER

Not a courtroom. **08:10, the ward sister goes through the night with you.**

She arrives holding: the chart (with metadata), the nursing notes, and whatever
she has been told at handover. She asks about **each contradiction she found** —
specifically, by name and time.

> "You've got dizziness at half eight. Adeyemi has him settled and comfortable at
> quarter to nine. One of you was in the wrong room."

You answer. **Your answers become new statements**, which are themselves
checkable. Outcomes: signed off / flagged for audit / escalated — and the player
always knows *which line did it*.

## 12. WORKED EXAMPLE — HOW A SMALL LIE COMPOUNDS

**19:40.** You need $1,500. Sam Oduya is premium and grateful. You write
*"reports transient dizziness on standing, 19:30 — observe overnight."*
You write it at the ward terminal. Nurse Adeyemi is at the station, eight metres
away, and sees you there.

**19:55.** Adeyemi does her round and writes *"Comfortable. Mobilising
independently to the toilet without difficulty."* **Contradiction 1.**

**20:10.** You ask her to re-check him. She goes — and now she remembers *that
you asked her to go*, which is a memory about **you**, not about Sam.

**20:30.** Ruth Kerrigan, in the next bed, mentions to Adeyemi that "the doctor
was asking Mr Oduya a lot of questions about feeling faint." **Contradiction 2:**
patient-reported, or doctor-suggested?

**21:00.** You decide to shore it up with a lying-and-standing blood pressure.
The machine records **normal**. **Contradiction 3, and it is permanent.**

**23:10.** You go back and write an addendum: *"BP unremarkable — symptoms likely
positional and transient."* Entry time 23:10, stated 21:00. **Backdated by two
hours,** and the terminal you used is outside the ward.

**08:10.** The sister opens with the softest one and works inward. You have to
choose which of three stories to defend, and abandoning one means explaining why
you wrote it.

That is the game the user asked for. Nobody clicked "Make it worse."

## 13. INFORMATION DESIGN

**Shown directly (it is a document — documents are readable):**
chart contents, timestamps, authors, your own money and what is owed, insurance
tier, who is physically in the room.

**Never shown:**
suspicion values, "Personality: Trusting", who the reviewer will believe, what
the correct treatment is, what any NPC currently believes, what the auditor will
look at.

**Inferred from behaviour:**
a nurse re-reading a chart · a patient repeating your question back to you ·
Ruth stopping mid-sentence when you walk in · an entry appearing that you didn't
write · somebody using your first name who didn't before.

## 14. WHY FIRST PERSON

Because **place and time are the evidence.**

- Terminals exist somewhere. Writing an entry means being *there*, at a time, in
  someone's sightline.
- You can **overhear** the handover and learn what the night staff now believe.
- You can **intercept** a nurse before she files a note — or fail to.
- You can **close a door** before asking a leading question.
- Ruth arrives at 19:00 whether you are ready or not.

The physical layer is not decoration; it is where evidence is created and where
it is discovered. This is the one thing that justifies keeping the locomotion.

## 15. TONE

**Option A — Dark bureaucratic satire.** Funny institution, serious people.
**Option B — Straight medical noir.** No comedy. Grim, tight.
**Option C — Deadpan workplace comedy.** Mundane colleagues, monstrous acts.

**Chosen: A, delivered like C.** One rule, applied without exception:

> **The system is funny. The people are not.**

Insurance tiers, billing codes, the forms, the hospital's incentives, the sister's
withering courtesy — funny. Illness, fear, and the eighty-one-year-old with
nobody at home — played completely straight.

This deletes "Chronic Beige" and keeps "Rent (studio, mould feature)". It is the
line the current game crosses, and crossing it is why neither audience exists.

## 16. DELETE

Aggressively, without sentiment:

- **The night street phase** — premeditated assault on strangers. This is the
  tonal cancer. Delete entirely.
- **The fistfight.** Whole system.
- **All four dexterity minigames.** They are not this game.
- **All 40 joke conditions.** Replace with ~6 plausible ones.
- **The legal/court system** — out of the slice.
- **17 upgrades, 12 perks, 12 endings, achievements, the meta-progression.**
- **Random events, departments, unlocks, three shift types.**
- **Bribery. The Chronicle as built** (its *idea* returns as the review).
- **11 of 15 rooms.** Keep: one ward, the nurses' station, the office, the corridor.
- **The suspicion word in the HUD.** All of it.

That is roughly 70% of the content and perhaps 45% of the systems code.

## 17. REUSE

- **`Evidence` + `Mind`** — the reason to do any of this. Extend, don't rewrite.
- **`NPCPerception`** — who saw you, from where. Already correct.
- **Player locomotion + `Interactor`** — genuinely good, keep as-is.
- **`PatientChart`** — extend with author, stated-time, entry-time, terminal.
- **`Build` / `UIKit` / `Anatomy`-free rendering, `SaveSystem`, `RNG`, `EventBus`.**
- **Hospital/room construction**, trimmed to four rooms.
- **The writing voice.**

## 18. SUCCESS CRITERIA

Specific and falsifiable. The prototype passes only if:

1. **Decision density** — a logged day contains ≥ 8 choices where the player
   changed their mind (opened a screen, backed out, chose otherwise). Below 5, the
   day is a formality.
2. **Divergence** — two playthroughs with the *same seed and same five patients*
   produce different final chart states and different reviewer questions ≥ 80% of
   the time.
3. **Lies create debt** — instrumented: every manufactured finding produces ≥ 2
   follow-on contradictions within the same day, ≥ 70% of the time.
4. **Legibility of failure** — after a flagged review, the player can name the
   contradiction that did it. Test: show the review to five people; ≥ 4 identify
   the correct line unprompted.
5. **The honest path is real and uncomfortable** — a fully honest day clears the
   debt, and ≥ 3 of 5 testers report hesitating over Dot Kerrigan.
6. **They start a second day.** Unprompted, ≥ 3 of 5.

If 1, 3 and 6 fail, the concept is wrong and we stop.

## 19. BUILD ORDER

1. **Strip.** Delete §16. Get the build green with one ward and five beds.
2. **Chart with metadata.** Entry = {content, stated_time, entry_time, author, terminal}. Readable in-world.
3. **The four authoring verbs.** Write / ask / have-checked / order-test.
4. **Contradiction detector.** Pure function over records + beliefs → list of contradictions with an axis. This is the whole reviewer AI.
5. **Five authored patients.** Hand-written situations.
6. **Money.** The numbers in §10, one payment, 20:00.
7. **The handover review.** Sister asks about contradictions in ascending order of severity; answers become statements.
8. **Belief plumbing.** Nurses read charts, talk at handover, remember why they were asked.
9. **Instrument the six criteria and play it twenty times.**

Nothing else. No new content until §18 passes.
