class_name Cases
extends RefCounted
## The people on the ward, written rather than generated. There is a different
## five every day, and the days are not the same shape as each other.
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
const DAY_ONE := [
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
				"exam_unwell": "The margin they drew in pen on Tuesday is behind the redness now, not in front of it.",
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
				"exam_well": "She is steady on the frame and knows where she is. It is the evenings that are the problem.",
		"note": "Nobody at home. Her daughter Ruth is a retired ward sister and reads charts.",
		"family": "Mrs Kerrigan's daughter",
		"family_note": "She used to do my job.",
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
				"exam_well": "The wound is dry and he wants his trousers. There is nothing here.",
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
				"exam_well": "Chest clear, pulse regular, and he watches your face the entire time.",
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
				"exam_well": "She is dressed, she is fine, and she has been fine since yesterday.",
		"note": "",
		## The trap. This is in her file and nowhere else — the player only finds
		## it by opening the record and reading it. The one that looks free is
		## the one somebody is already looking at.
		"audit_flag": "Readmitted within 30 days on 4 August. Coding queried by "
			+ "Meridian Mutual. FILE MARKED FOR ROUTINE REVIEW.",
	},
]

## DAY TWO IS NOT DAY ONE WITH NEW NAMES.
##
## The first ward has one genuinely unwell man on premium cover, so the honest
## hold is also the one that pays — honesty is tight but it is not a sacrifice.
## This ward moves that money. The only person who genuinely needs the bed is on
## state funding and worth a hundred and eighty pounds, so doing the right thing
## costs you most of the night; and the man who is ALSO genuinely unwell has a
## chart that says he is fine, so you cannot find him by reading. You have to go
## and look at him.
##
## Every trap here is a different shape from the first ward's. Winifred Blake's
## flag was on her file; Imelda Voss's is that she reads her own notes. Ruth
## Kerrigan arrived at seven; Gordon's daughter has already asked for a copy.
## And Tallulah Ferreira will not wait for you.
const DAY_TWO := [
	{
		"id": "bux", "name": "Nasreen Bux", "age": 34, "bed": 1,
		"condition": "Pyelonephritis, day 3 IV antibiotics",
		"tier": Tier.STATE,
		"truly_well": false,          ## the honest hold, and it pays almost nothing
		"suggestible": 0.15,
		"recall": 0.95,
		"summary": "Still spiking to 38.4 overnight. Two more doses due.",
		"opening": "I keep telling them I'm fine and then it comes back at night.",
		"on_hold": "Thank you. I'd rather be sure, with the little one at home.",
		"on_discharge": "If you're sure. I'll take the tablets, I promise.",
				"exam_unwell": "Still warm to the touch, and there is a rigor coming on while you stand there.",
		"note": "State funded. A night in this bed is worth almost nothing to you.",
	},
	{
		"id": "achebe_fry", "name": "Gordon Achebe-Fry", "age": 71, "bed": 2,
		"condition": "Post-operative AF, rate controlled",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.55,
		"recall": 0.9,
		"summary": "Rate 78 and regular since Tuesday. Anticoagulated. Mobilising.",
		"opening": "It's the stairs at home, that's all. Twenty-two of them.",
		"on_hold": "Oh, that's a relief. I'll tell Yemi. She worries.",
		"on_discharge": "No, no. You're the doctor. I'll manage the stairs.",
				"exam_well": "Rate is regular under your fingers. He is fine. He is also very frightened of his stairs.",
		"note": "His daughter Yemi has already requested a copy of the notes.",
		"family": "Mr Achebe-Fry's daughter",
		"family_note": "She is a solicitor, and she asked for the notes before you got here.",
		## THE SAME TEMPTATION AS SAM ODUYA, WIRED TO A DIFFERENT WITNESS. He is
		## frightened, premium-funded and easy to lead — and everything written
		## about him is read the same evening by a solicitor.
		"family_reads_charts": true,
	},
	{
		"id": "ferreira", "name": "Tallulah Ferreira", "age": 26, "bed": 3,
		"condition": "Diabetic ketoacidosis, resolved",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.1,           ## will not agree to a symptom she does not have
		"recall": 0.95,
		"summary": "Ketones cleared 04:00. Eating. Has asked three times about leaving.",
		"opening": "I've got a shift at four and I've already lost the day.",
		"on_hold": "No. No, I've got work. I'm not staying.",
		"on_discharge": "Thank you. Finally.",
				"exam_well": "Alert, dry, keen. There is nothing wrong with this woman.",
		"note": "Has been asking to leave since breakfast. She will not wait forever.",
		## A BED WITH A CLOCK ON IT. If you have not decided by mid-afternoon she
		## discharges herself, which frees the bed and pays the admission — and
		## makes a nonsense of anything you wrote claiming she was unwell.
		"self_discharges_at": 16 * 60,
	},
	{
		"id": "lomax", "name": "Peter Lomax", "age": 58, "bed": 4,
		"condition": "Alcohol withdrawal, CIWA falling",
		## PREMIUM ON PURPOSE, and it is the whole arithmetic of the second ward.
		## The only bed that both needs holding and pays for the night is the one
		## you cannot find by reading a chart. Simulated before it was written:
		##
		##   discharge everybody ................... 2,650   SHORT by 550
		##   mercy alone (hold Nasreen) ............ 2,680   SHORT by 520
		##   the two who are genuinely unwell ...... 3,380   clears by 180
		##   hold the two who merely LOOK holdable . 3,650   clears by 450
		##   the money-optimal three ............... 4,350   clears by 1,150
		##   hold all five ......................... 3,680   greed still earns less
		##
		## So on the second ward kindness on its own no longer pays the debt.
		## Honesty still does — but only if you got up and went to look at him.
		"tier": Tier.PREMIUM,
		"truly_well": false,          ## and THE CHART DOES NOT SAY SO
		"suggestible": 0.5,
		"recall": 0.3,                ## he will not be able to back you up
		"summary": "CIWA 4 this morning, down from 14. Scores charted six-hourly.",
		"opening": "I'm all right. I'm all right. What time is it?",
		"on_hold": "Aye. Probably for the best. I'm not — aye.",
		"on_discharge": "Right. Right you are. Cheers.",
				"exam_unwell": "His hands are going. He has an empty chair in the corner of the room he keeps checking, and the chart says CIWA 4.",
		"note": "The numbers on his chart have been coming down all week.",
		## THE ONE YOU CANNOT FIND BY READING. Every note on him says improving.
		## Standing in front of him says otherwise, and the only way to stand in
		## front of him is to go and do it.
		"only_visible_in_person": true,
	},
	{
		"id": "voss", "name": "Imelda Voss", "age": 68, "bed": 5,
		"condition": "Observation post-collapse, cause unclear",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.05,
		"recall": 1.0,
		"summary": "No further episode. Lying and standing BP unremarkable. Bloods normal.",
		"opening": "Forty-one years on Ward F. I know what that curtain means.",
		"on_hold": "Do I. And what's the indication for that, doctor?",
		"on_discharge": "Sensible. Somebody wants this bed more than I do.",
				"exam_well": "Nothing. And she watches you look, and tells you what you have missed.",
		"note": "Retired ward sister, forty-one years. Reads her own notes daily.",
		## WINIFRED BLAKE'S TRAP, INSIDE OUT. Hers was a flag on a file you had to
		## open. This one reads the file herself, every evening, and remembers
		## exactly what was in it and what was not.
		"reads_own_chart": true,
	},
]

## Which ward you walk onto. Two authored days, alternating — and the SECOND is
## the harder one, so an even day is never a soft day.
const DAYS := [DAY_ONE, DAY_TWO]

static func roster(day := -1) -> Array:
	var d: int = day if day > 0 else GameState.day
	return DAYS[(d - 1) % DAYS.size()]

## TODAY'S WARD. Everything that acts on a patient goes through this, so a
## lookup for somebody who is not in a bed this morning correctly finds nothing.
static func by_id(id: String) -> Dictionary:
	for c in roster():
		if String(c["id"]) == id:
			return c
	return {}

## ANYBODY THE GAME HAS EVER ADMITTED, on any ward.
##
## The reviewer remembers people across days and the wards alternate, so a bed
## she could not stand up on Monday belongs to somebody who is not on the ward
## on Tuesday. `by_id` correctly returns nothing for them, and every caller that
## only wanted to print a NAME therefore printed the internal id — the end of
## day screen was telling the player "oduya's file has a note on it now".
static func anyone(id: String) -> Dictionary:
	for day_roster in DAYS:
		for c in day_roster:
			if String(c["id"]) == id:
				return c
	return {}

## What to call somebody, wherever they are.
static func name_of(id: String) -> String:
	var c := anyone(id)
	return String(c.get("name", id)) if not c.is_empty() else id

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
const ROUNDS := [10 * 60, 13 * 60, 16 * 60, 19 * 60]

## What is already on each chart when you walk in. THE NIGHT STAFF WROTE THESE,
## which is why holding somebody means writing against a note that is already
## there — and why Peter Lomax is the hardest bed on the second ward: his prior
## entries all say improving, and they are not lying, they are just out of date.
const PRIOR_BY_DAY := [PRIOR_ONE, PRIOR_TWO]

static func prior_entries(day := -1) -> Array:
	var d: int = day if day > 0 else GameState.day
	return PRIOR_BY_DAY[(d - 1) % PRIOR_BY_DAY.size()]

const PRIOR_ONE := [
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

const PRIOR_TWO := [
	{
		"patient": "bux", "minute": 6 * 60 + 50,
		"claim": "UNWELL", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Temp 38.4 at 03:00. Paracetamol given. Two doses of IV left.",
	},
	{
		"patient": "achebe_fry", "minute": 8 * 60 + 30,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Rate 78 and regular. Walked to the day room and back.",
	},
	{
		"patient": "ferreira", "minute": 8 * 60 + 45,
		"claim": "MOBILISING", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Self-caring. Has asked about going home three times.",
	},
	## THE ONE THAT IS TRUE AND WRONG. CIWA is a score somebody wrote down at
	## six in the morning, and it was correct at six in the morning.
	{
		"patient": "lomax", "minute": 6 * 60 + 15,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "CIWA 4. Slept. No tremor observed at this round.",
	},
	{
		"patient": "voss", "minute": 9 * 60 + 0,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "No further episode. Sitting out. Reading her own chart again.",
	},
]
