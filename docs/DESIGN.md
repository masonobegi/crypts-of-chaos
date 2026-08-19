# CHRONIC CARE — Design Document

> *"I'm a broke doctor trying to keep patients in the hospital as long as possible
> without anyone realising I'm doing it."*

A first-person, physics-driven dark-comedy hospital immersive sim. Stylized low-poly.
Everything medical is **fictional and absurd**. No real conditions, no real drugs, no
real procedures — the humour comes from bureaucracy and slapstick, never from harm.

---

## 1. Critique of the original brief, and what changed

The brief is strong — the premise is instantly legible, which is the single most
important property for a streamable game. But five things in it would have made the
game boring or unshippable. Here is the critique and the fix that is actually
implemented in this codebase.

### 1.1 A suspicion *meter* turns an immersive sim into a spreadsheet
**Problem.** If suspicion is a number that goes up, the optimal play is arithmetic:
find the action with the best `stay_days / suspicion` ratio and spam it. All the
physics, NPCs and rooms become decoration.

**Fix — evidence-first suspicion.** Nobody has a suspicion stat that you edit
directly. Characters hold **Evidence** (`scripts/systems/evidence.gd`): discrete,
timestamped records of things they *personally observed or inferred*. Suspicion is a
**derived read** over the evidence a character holds, weighted by their personality
and how much they trust you.

Because evidence is an object rather than a number, it can be interacted with:
it decays, it can be contradicted, it can be transferred by gossip, it can be
destroyed (shred the chart), it can be *pre-empted* (document a cause before the
complication lands), and it can be corroborated — two witnesses to the same act are
far worse than one, because corroboration multiplies weight. That is a systems
sandbox. A meter is not.

### 1.2 "Questionable / Extremely Questionable" settings label the crime for you
The brief already flags this. Implemented consequence: **no UI anywhere states a
suspicion cost or a recovery delta.** Machines expose fictional physical
controls — a dial reading `PLASMA GRADIENT 0–11`, a coolant valve, a polarity
switch. What those do to a patient is learned by watching patients, not by reading
tooltips. The `docs/SPOILERS.md` table exists for developers; the player gets
`Codex` entries only after they personally observe an effect twice.

### 1.3 Nothing in the brief explains *why the patient stays longer*
This is the real design hole. "Bad treatment → longer stay" is one boring verb.

**Fix — the Complication economy.** A patient leaves when their (hidden) recovery
reaches 100%. Stays are extended by **Complications** — absurd fictional secondary
conditions (`Ambient Dread`, `Rebound Hiccups`, `Ferrous Aura`, `Chart Fatigue`).
Each complication is an *object* with:

- a **cause** — the actual sim event that produced it (truth), and
- a **documented cause** — whatever you wrote on the chart (claim).

A complication whose documented cause is plausible, is filed *before* anyone else
notices, and matches the physical state of the room, is **pure revenue and zero
suspicion.** The same complication with no paperwork is an incident report.

So the actual gameplay verb is not "sabotage". It is ***manufacture a complication
and get in front of it with a story.*** That is a much richer, much funnier verb, and
it is what makes the Papers-Please half of the game load-bearing rather than a theme.

### 1.4 The player would always know the optimal answer
**Fix — hidden true state.** Recovery is never shown as a number. You see **vitals**
(three fictional readouts) which are noisy, personality-distorted, and can be
misread by tired doctors. Your tablet's suspicion percentages are *your character's
estimate*, and they are systematically wrong for NPCs you have not talked to
recently. Confidently-wrong information is funnier and more tense than no
information.

### 1.5 Escalation with no early-warning is unfair, not tense
**Fix — tells.** Every NPC broadcasts its internal state physically before it
punishes you: a nurse who suspects you stops what she's doing and *watches* you; a
suspicious wife follows you down the corridor; a rule-follower writes on a clipboard
(that clipboard is a physical evidence object you can steal); gossip is audible if
you stand near two NPCs talking. You can always see it coming if you're paying
attention — which makes getting caught feel earned and makes the recovery scramble
the best part of a stream.

### 1.6 Additions not in the brief
- **The Debt Clock.** Rent, loans and a truly hostile car payment auto-deduct daily.
  A pure-saint run cannot service the debt at the starting wage. The game never tells
  you to cheat; the arithmetic does. This is the ethical joke and the difficulty curve
  in one system.
- **Shift Report card + headline generator.** Every shift ends on a shareable summary
  card with a generated local-news headline. Streamer bait, and a readable feedback loop.
- **Career meta / roguelite spine.** One career is 45–120 minutes and terminates in one
  of the endings. Endings unlock starting perks and new condition decks, so the sandbox
  is replayable rather than a single 8-hour campaign that dies at the first ending.
- **Corroboration + contradiction.** Two witnesses is exponentially worse than one.
  Conversely you can *plant* contradicting evidence.

---

## 2. Systems map

```
                       ┌──────────────┐
        physics/props  │  WorldEvent  │  everything observable emits one
        treatments ───►│   (fact)     │◄─── dialogue, paperwork, machines
                       └──────┬───────┘
                              │ perception (FOV + range + LOS + attention)
                              ▼
                       ┌──────────────┐   gossip    ┌──────────────┐
                       │   Evidence   │◄───────────►│ Social graph │
                       │ (per-NPC)    │             └──────────────┘
                       └──────┬───────┘
             personality      │  derive
             trust, decay     ▼
                       ┌──────────────┐            ┌──────────────┐
                       │  Suspicion   │──spill────►│  Heat (inst.)│
                       └──────┬───────┘            └──────┬───────┘
                              │                            │
                              ▼                            ▼
                       complaints, refusals        investigations, audits,
                       second opinions             escalation ladder → endings
```

- **Truth layer** — `Patient.recovery`, real complication causes, what physically happened.
- **Record layer** — charts, the EHR, billing codes. *Can disagree with truth.*
- **Belief layer** — what each NPC holds as evidence. *Can disagree with both.*

All the comedy lives in the gaps between those three layers.

## 3. Vertical slice scope (milestone 1)

One floor: lobby, 5 patient rooms, nurses' station, supply room, doctor's office,
bathrooms, treatment area. Full shift loop: clock in → intake → diagnose → treat or
prolong → manage staff/families → chart review → clock out → pay debts → upgrade → next day.

## 4. Content safety rule (hard constraint)

Every condition, drug, machine and procedure in `DB` is invented. Nothing in this
game describes a real technique for harming a person. Sabotage verbs are things like
"set the dial to 11", "swap the label", "file the wrong form", "leave the window
open" — bureaucratic and slapstick, not medical.
