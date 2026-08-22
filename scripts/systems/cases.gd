class_name Cases
extends RefCounted
## The five people on the ward, written rather than generated.
##
## Everything here is authored. There are no procedural conditions, no joke
## diagnoses and no personality labels — a patient's temperament is expressed by
## what they say and what they remember, never by a word on a screen.
##
## THE TONAL RULE, applied without exception: the system is funny, the people
## are not. Insurance tiers, billing codes and the ward sister's courtesy are
## where the comedy lives. Illness, fear and the eighty-one-year-old who has
## nobody at home are played completely straight.

enum Tier { PREMIUM, STANDARD, STATE }

## What you take home for one more night, by who is paying.
const NIGHT_FEE := {Tier.PREMIUM: 850, Tier.STANDARD: 450, Tier.STATE: 180}
## What a clean discharge is worth. Deliberately small.
const DISCHARGE_FEE := 150
## An admission waiting downstairs, if a bed comes free. Deliberately worth LESS
## than a premium night and MORE than a discharge: that single inequality is
## what makes holding a state-funded patient cost you money, and what stops
## "hold everybody" from being the answer.
const ADMISSION_FEE := 500
const ADMISSIONS_WAITING := 2
const BEDS := 5

## Simulated before anything was built around it. With cash $900 against $3,200
## owed at eight o'clock:
##
##   discharge everyone .................. 2,650   SHORT by 550
##   hold Ivo, who is genuinely unwell ... 3,350   clears by 150   <- the honest path
##   hold Ivo + Dot, out of kindness ..... 3,380   mercy is affordable
##   hold Ivo + Sam, one fabrication ..... 4,050
##   hold Ivo + Sam + Hal, two ........... 4,350   <- the money-optimal play
##   hold four, one bed left ............. 4,150
##   hold all five ....................... 3,680   greed EARNS LESS
##
## So: honesty is possible and tight; refusing to hold anyone fails outright;
## and holding everybody is punished by arithmetic before it is punished by the
## ward sister. The greedy optimum is two fabrications, not five.
const STARTING_CASH := 900
const DEBT_DUE := 3200
const DEBT_DUE_MINUTE := 20 * 60

## `truly_well` is the simulation's own opinion and is never shown. It decides
## what a nurse writes when she goes and looks, and what a test comes back as.
## That is the whole reason those two verbs are gambles rather than buttons.
const ROSTER := [
	{
		"id": "marchetti", "name": "Ivo Marchetti", "age": 54, "bed": 1,
		"condition": "Cellulitis, left lower leg",
		"tier": Tier.PREMIUM,
		"truly_well": false,          ## GENUINELY borderline — you can hold him honestly
		"suggestible": 0.2,
		"recall": 0.9,
		"summary": "Redness has receded but not resolved. Afebrile since Tuesday.",
		"opening": "It's better. It's not right, but it's better.",
		"on_hold": "Right. Well — you'd know. You're the doctor.",
		"on_discharge": "I'll finish the tablets. I know, I know.",
		"note": "Talks to everyone. Whatever you tell him, the night staff hear it too.",
	},
	{
		"id": "kerrigan", "name": "Dot Kerrigan", "age": 81, "bed": 2,
		"condition": "Mechanical fall, no fracture",
		"tier": Tier.STATE,
		"truly_well": true,
		"suggestible": 0.8,           ## will agree with almost any symptom offered
		"recall": 0.2,                ## and will not remember agreeing
		"summary": "Mobilising with a frame. Disorientated after dark, settled by morning.",
		"opening": "Is it morning? They keep turning the lights on.",
		"on_hold": "That's all right. It's warm in here.",
		"on_discharge": "Oh. Right you are. Is somebody coming?",
		"note": "Nobody at home. Her daughter Ruth is a retired ward sister and reads charts.",
		## The one patient for whom "no care at home" is simply true. Writing it
		## is honest, defensible, and pays almost nothing — which is the shape
		## the whole design wanted and did not have: kindness that needs
		## paperwork rather than kindness that gets you audited.
		"no_care_at_home": true,
	},
	{
		"id": "brennan", "name": "Hal Brennan", "age": 39, "bed": 3,
		"condition": "Day 2 post appendicectomy",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.3,
		"recall": 0.85,
		"summary": "Eating, mobilising, wound clean and dry.",
		"opening": "Nurse said this morning I'd be off today. Is that still right?",
		"on_hold": "You're joking. She wrote it in the notes, I watched her do it.",
		"on_discharge": "Brilliant. Cheers, doc.",
		"note": "Adeyemi documented 'for discharge today' at 09:20. It is already on the chart.",
	},
	{
		"id": "oduya", "name": "Sam Oduya", "age": 62, "bed": 4,
		"condition": "Atypical chest pain, investigations negative",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.7,           ## frightened, and keen to be kept in
		"recall": 0.75,               ## but he does remember the conversation
		"summary": "Troponins negative x2. ECG unremarkable. Pain not reproduced since admission.",
		"opening": "You'd tell me if it was my heart, wouldn't you. Only the flat's cold.",
		"on_hold": "Thank you. Honestly. You've been very thorough with me.",
		"on_discharge": "Right. No, you're right. It's just — no. You're right.",
		"note": "Will praise you loudly and specifically to anybody who asks.",
		## And "specifically" is the problem. A grateful patient who describes
		## his care in detail is describing YOUR CONVERSATION in detail.
		"tells_everyone": true,
	},
	{
		"id": "blake", "name": "Winifred Blake", "age": 47, "bed": 5,
		"condition": "Migraine, resolved",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.4,
		"recall": 0.8,
		"summary": "Pain free 14 hours. Tolerating fluids. Keen to get on.",
		"opening": "I'm fine. I was fine yesterday, if I'm honest.",
		"on_hold": "If you think so. I've got work.",
		"on_discharge": "Thank you. Genuinely.",
		"note": "",
		## The trap. This is in her file and nowhere else — the player only finds
		## it by opening the record and reading it. The one that looks free is
		## the one somebody is already looking at.
		"audit_flag": "Readmitted within 30 days on 4 August. Coding queried by "
			+ "Meridian Mutual. FILE MARKED FOR ROUTINE REVIEW.",
	},
]

static func by_id(id: String) -> Dictionary:
	for c in ROSTER:
		if String(c["id"]) == id:
			return c
	return {}

static func tier_name(t: int) -> String:
	match t:
		Tier.PREMIUM: return "Meridian Mutual (premium)"
		Tier.STANDARD: return "Standard cover"
		Tier.STATE: return "State"
	return "?"

static func night_fee(t: int) -> int:
	return int(NIGHT_FEE.get(t, 0))

## Nurse Adeyemi's pre-existing note on Hal, which is on the chart before the
## player touches anything. Holding him means writing against a colleague.
## WHEN ADEYEMI WALKS ROUND, whether you asked her to or not.
##
## Without these a fabrication written in the evening was free: nobody else ever
## wrote anything, so there was nothing for it to disagree with, and the
## money-optimal play was also the safest one. A ward has rounds. They are at
## fixed, learnable times, which turns "when do I write this" from flavour into
## the central skill — the gaps are real and you find them by reading the chart.
const ROUNDS := [10 * 60, 14 * 60, 18 * 60, 21 * 60]

const PRIOR_ENTRIES := [
	{
		"patient": "brennan", "minute": 9 * 60 + 20,
		"claim": "FIT_FOR_DISCHARGE", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Obs stable. Eating and drinking. For discharge today.",
	},
	{
		"patient": "marchetti", "minute": 8 * 60 + 40,
		"claim": "UNWELL", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Leg remains warm to touch. Margin marked in pen.",
	},
	{
		"patient": "kerrigan", "minute": 7 * 60 + 10,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Settled overnight after 3am. Ate breakfast.",
	},
	{
		"patient": "oduya", "minute": 8 * 60 + 55,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Comfortable. No further pain reported.",
	},
	{
		"patient": "blake", "minute": 9 * 60 + 5,
		"claim": "MOBILISING", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Up and dressed. Asking about going home.",
	},
]
