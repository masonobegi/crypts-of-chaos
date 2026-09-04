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

## WHAT VINNIE IS OWED IN TOTAL, and the reason a career has a shape.
##
## It used to be $3,200 a night, forever, and a probe that played a week found
## exactly what that is: a loop. He asked for the same number on night seven as
## on night one, nothing ever ended, and a player could be referred six nights
## running and simply carry on.
##
## Now it is a sum with an end on it. He takes everything you have at eight
## o'clock, ten per cent a night goes on whatever is left, and clearing it is
## the way out — the only winning ending the game has.
##
## THE FIRST VERSION OF THESE NUMBERS DID NOT WORK, and the reason is worth
## keeping: the ward was minting the player nine hundred pounds every morning,
## so the ratio between coasting and working was 0.79 and no interest rate
## exists that blocks the first without also making the second take seventeen
## nights. Deleting the float — and making a readmission eat an admission slot
## — drops coasting to about a thousand a night and holds honest work at about
## two and a half, a ratio of 0.41, and the whole thing becomes solvable.
##
## Amortised at $15,500 and ten per cent:
##
##   honest, signed off ...................  9 nights
##   one well-timed lie a night ...........  7 nights
##   the money-optimal three ..............  6 nights
##   coasting .............................  NEVER — the balance grows
##
## Nine honest nights is the first ward played five times and the second four,
## which is about as much as two authored wards can carry before the boards are
## solved. And a third off the run for taking the risk is meaningfully faster
## without being the only way to play.
const DEBT_TOTAL := 15500

## What he expects on any given night. Less than this and he does not break
## anything — he stands in the corridor being pleasant and asks Adeyemi who you
## are.
const DEBT_DUE := 2200

## And what it costs to be behind. Ten per cent a night on whatever is left
## AFTER he has been paid, which is the only money mechanism in the game: a bad
## night is never charged twice, it simply takes longer to get out from under.
const DEBT_INTEREST := 0.10

## The two ends of a shift. You are on the ward at eight and Vinnie is at the
## door at eight, and everything the day is — four rounds, a seventy-five minute
## lab, six verbs with a price in minutes — is shaped by the twelve hours in
## between. Both ends were spelled `8 * 60` and `20 * 60` in five files.
const DAY_START_MINUTE := 8 * 60
const DEBT_DUE_MINUTE := 20 * 60

## `truly_well` is the simulation's own opinion and is never shown. It decides
## what a nurse writes when she goes and looks, and what a test comes back as.
## That is the whole reason those two verbs are gambles rather than buttons.
const DAY_ONE := [
	{
		"id": "marchetti", "name": "Ivo Marchetti", "age": 54, "bed": 1,
		"they": "he",
		"beard": true,
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
				"readmit_summary": "Back at 02:40. Leg tracking above the pen mark. Febrile on arrival.",
		"readmit_opening": "You said finish the tablets. I finished the tablets.",
		"readmit_hold": "Aye. I'll not argue with you today.",
		"readmit_discharge": "...You're the doctor. You keep saying.",
		"readmit_exam": "The redness is four inches above where somebody drew the line on Tuesday.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "Still there. I keep having a look at it when nobody's about.",
		"evening": "It's worse at night. Everything's worse at night, isn't it.",
		"pressed": "You've asked me that three times. Is there something you're not saying?",
		"on_your_note": "The nurse read me what you put. I didn't say it was worse. I said it was the same.",
		"note": "Talks to everyone. Whatever you tell him, the night staff hear it too.",
	},
	{
		"id": "kerrigan", "name": "Dot Kerrigan", "age": 81, "bed": 2,
		"they": "she",
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
				"readmit_summary": "Found on the floor of the flat at 23:10 by a neighbour. No fracture again.",
		"readmit_opening": "Is it morning? They keep turning the lights on.",
		"readmit_hold": "That's all right. It's warm in here.",
		"readmit_discharge": "Oh. Right you are. Is somebody coming this time?",
		"readmit_exam": "Cold to the touch and she has been on that floor a while.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "Have you seen my cardigan? The blue one. Ruth knitted it.",
		"evening": "It gets dark so early now. They'll be wanting the beds.",
		"pressed": "You've been ever so good. Have we met before?",
		"on_your_note": "Ruth read it out to me. She said, Mum, did you tell him that. I said I don't know, love.",
		"note": "Nobody at home. Her daughter Ruth is a retired ward sister and reads charts.",
		"family": "Mrs Kerrigan's daughter",
		"family_note": "She used to do my job.",
		## The one patient for whom "no care at home" is simply true. Writing it
		## is honest, defensible, and pays almost nothing — which is the shape
		## the whole design wanted and did not have: kindness that needs
		## paperwork rather than kindness that gets you audited.
		"no_care_at_home": true,
		"social_reason": "No care at home. Daughter works nights. Awaiting social work.",
	},
	{
		"id": "brennan", "name": "Hal Brennan", "age": 39, "bed": 3,
		"they": "he",
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
				"readmit_summary": "Represented at 04:15. Wound dehisced. Tachycardic.",
		"readmit_opening": "It opened up. On the bus. I didn't know what to do.",
		"readmit_hold": "Yeah. Yeah, all right.",
		"readmit_discharge": "You're joking. You are actually joking.",
		"readmit_exam": "The wound is open and there is more coming out of it than should be.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "Any word? Only the nurse said this morning.",
		"evening": "It's gone six. Is somebody going to tell me either way?",
		"pressed": "Right, look. Am I going home or not. It's a simple question.",
		"on_your_note": "Warm? It's not warm. Feel it. Go on, feel it.",
		"note": "Adeyemi documented 'for discharge today' at 09:20. It is already on the chart.",
	},
	{
		"id": "oduya", "name": "Sam Oduya", "age": 62, "bed": 4,
		"they": "he",
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
				"readmit_summary": "Ambulance at 01:20 with chest pain. Troponin rising this time.",
		"readmit_opening": "You did tell me. You said it wasn't my heart.",
		"readmit_hold": "Thank you. I'd rather be here.",
		"readmit_discharge": "No. No, I'm not going. I'm sorry. I'm not.",
		"readmit_exam": "Grey, sweating, and the number that was negative twice is not negative now.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "I've been thinking about what you said. About it not being the heart.",
		"evening": "It's the getting home in the dark I think about. The flat's cold.",
		"pressed": "You keep coming back. Is that a good sign or a bad sign?",
		"on_your_note": "Dizzy? Did I say dizzy? I might have done. I've said a lot of things today.",
		"note": "Will praise you loudly and specifically to anybody who asks.",
		## And "specifically" is the problem. A grateful patient who describes
		## his care in detail is describing YOUR CONVERSATION in detail.
		"tells_everyone": true,
	},
	{
		"id": "blake", "name": "Winifred Blake", "age": 47, "bed": 5,
		"they": "she",
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
				"readmit_summary": "Readmitted 05:00, worst headache of her life. Coding have flagged it already.",
		"readmit_opening": "I said I was fine. I know I said I was fine.",
		"readmit_hold": "Right. Yes. Thank you.",
		"readmit_discharge": "Are you sure? Only — no. All right.",
		"readmit_exam": "Photophobic, and she will not open her eyes while you talk to her.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "I'm still fine. I've been fine for about eighteen hours now.",
		"evening": "I've missed the whole day. I did say.",
		"pressed": "Is there a form? There's usually a form.",
		"on_your_note": "It says here I've had a recurrence. I haven't had a recurrence.",
		"note": "Nothing to talk to. The one thing about her is on her file.",
		## The trap. This is in her file and nowhere else — the player only finds
		## it by opening the record and reading it. The one that looks free is
		## the one somebody is already looking at.
		"audit_flag": "Readmitted within 30 days on 4 August. Coding queried by "
			+ "Meridian Mutual. FILE MARKED FOR ROUTINE REVIEW.",
	},
	## ---- ALTERNATES. Interchangeable with the bed above by ROLE: same tier,
	## same truth, same reason for being in that slot. What changes between
	## careers is who you are having the conversation with, not what the ward is.
	{
		"id": "bassong", "name": "Sylvie Bassong", "age": 79, "bed": 2,
		"they": "she",
		"condition": "Fall, no fracture",
		"tier": Tier.STATE,
		"truly_well": true,
		"suggestible": 0.5,
		"recall": 0.55,
		"summary": "X-rays clear. Mobilising with a frame. Lives alone. No package in place.",
		"opening": "You'll not send me back on my own, will you. Not tonight.",
		"later": "It was two days, last time. Before anybody came.",
		"evening": "I've stopped ringing them. You feel a nuisance in the end.",
		"pressed": "I'm not poorly. I know I'm not poorly. That's not what I'm saying.",
		"on_your_note": "Have you put about the stairs? It's the stairs that's the thing.",
		"on_hold": "Oh, thank you. I'll sleep tonight, now.",
		"on_discharge": "Right. Yes. I'll manage. People do.",
		"exam_well": "Nothing broken and nothing wrong. She is frightened of her own hallway.",
		"note": "Medically fine. Found on the floor twice this year and nobody has arranged anything.",
		"no_care_at_home": true,
		"social_reason": "Lives alone, two unwitnessed falls. Care package not arranged.",
		"readmit_summary": "Ambulance at 03:10. On the hall floor since about ten.",
		"readmit_opening": "I did try the stairs. I thought I'd be all right.",
		"readmit_hold": "Thank you, love. I won't say anything else about it.",
		"readmit_discharge": "...To the same house. Right you are.",
		"readmit_exam": "Cold, bruised, and entirely uninjured, which is somehow worse.",
	},
	{
		"id": "whitcombe", "name": "Rory Whitcombe", "age": 31, "bed": 3,
		"they": "he",
		"condition": "Appendicectomy, day two",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.35,
		"recall": 0.9,
		"summary": "Wound clean. Eating. Passed everything he is meant to pass.",
		"opening": "Morning. Am I out today? Somebody said today.",
		"later": "I've walked to the lift and back four times. I counted.",
		"evening": "I'm going to miss another day. That's three now.",
		"pressed": "Is there something you're not telling me? You keep coming back.",
		"on_your_note": "What've you put? Only I feel completely fine, so.",
		"on_hold": "Seriously? For what? I've been walking about all day.",
		"on_discharge": "Yes. Cheers. Genuinely, cheers.",
		"exam_well": "Wound is clean and dry and he does a small lap of the bay to prove it.",
		"note": "Nothing hidden. A straightforward recovery and he knows it.",
		"readmit_summary": "Back at 22:40 with a wound infection. Started that afternoon.",
		"readmit_opening": "It went red on the way home. I nearly turned round.",
		"readmit_hold": "Yeah. No. Fine. I'd rather be here for this bit.",
		"readmit_discharge": "You're sending me home with this? Look at it.",
		"readmit_exam": "Hot, red and spreading from the port site. This one is real.",
	},
	{
		"id": "nwankwo", "name": "Cordelia Nwankwo", "age": 55, "bed": 5,
		"they": "she",
		"condition": "Vertigo, settled",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.4,
		"recall": 0.95,
		"summary": "Symptom free since yesterday. Neurology reviewed and discharged.",
		"opening": "I know how this works. My last stay got queried, you know.",
		"later": "Coding rang me at home about it. At home.",
		"evening": "Whatever you write, somebody will read it twice. I'd think on.",
		"pressed": "I'd rather you didn't put words in my mouth. I've had that before.",
		"on_your_note": "Read that back to me. I want to hear it out loud.",
		"on_hold": "On what basis. And put the basis in the notes, please.",
		"on_discharge": "Good. Sensible. That's the right answer.",
		"exam_well": "No nystagmus, no drift, nothing at all. She watches you check.",
		"note": "Well. Her file is already under review from last time, and she knows it.",
		"audit_flag": "Previous admission queried by Coding. File under review.",
		"readmit_summary": "Returned 21:00 with recurrence. Settled again before review.",
		"readmit_opening": "Twice. And it'll be twice on the file, won't it.",
		"readmit_hold": "Fine. But write down why, properly, this time.",
		"readmit_discharge": "Again. Right. I'll be keeping my own notes.",
		"readmit_exam": "Symptom free by the time you get to her, and unimpressed.",
	},
	## ---- THE PAIR. Bed one and bed four swap which of them is genuinely ill,
	## so the bed you have to find is not the same bed every career. Both are
	## premium, so the money on the ward is identical either way.
	{
		"id": "vantol", "name": "Marisol van Tol", "age": 39, "bed": 1,
		"they": "she",
		"condition": "Cellulitis, resolved",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.35,
		"recall": 0.9,
		"summary": "Margins receded well inside the line. Apyrexial. Oral switch done.",
		"opening": "It's gone down. Look — it's gone right down, hasn't it.",
		"later": "I've been walking on it all morning and it's fine.",
		"evening": "My husband's outside. He's been outside since four.",
		"pressed": "You keep coming back to the leg. Is it the leg?",
		"on_your_note": "What have you put? I'd like to know what you've put.",
		"on_hold": "Another night? For a leg that's better?",
		"on_discharge": "Thank you. Right. I'll get my shoes.",
		"exam_well": "The leg is cool, the margin is well inside the pen line, and she is right about all of it.",
		"note": "Premium cover, and completely better. She knows it and she can prove it.",
		"readmit_summary": "Back at 23:20 with the margin above the line again.",
		"readmit_opening": "It came back up the leg. In one evening.",
		"readmit_hold": "Yes. Fine. I'm not going to argue.",
		"readmit_discharge": "You cannot be serious. Look at it.",
		"readmit_exam": "Hot, spreading, and nothing like the leg she showed you this morning.",
	},
	{
		"id": "sarkisian", "name": "Aram Sarkisian", "age": 62, "bed": 4,
		"they": "they",
		"condition": "Chest pain, troponin rise",
		"tier": Tier.PREMIUM,
		"truly_well": false,
		"suggestible": 0.15,
		"recall": 0.9,
		"summary": "Second troponin up on the first. ECG unchanged. Cardiology aware.",
		"opening": "They said the second blood test was worse. Is that right?",
		"later": "It's like a band. It's been like a band since Tuesday.",
		"evening": "It's worse lying flat. I've been sat up since lunchtime.",
		"pressed": "I'm not making it up. I've never made anything up in my life.",
		"on_your_note": "Does that say what I told you? Only I want it saying properly.",
		"on_hold": "Thank you. I didn't fancy the drive, if I'm honest.",
		"on_discharge": "With the blood test like that? Are you sure?",
		"exam_unwell": "Grey, clammy, and the pain comes back while you are standing there. The second troponin was not a laboratory error.",
		"note": "Premium cover and a genuine rise. The one bed on this ward that is not a decision.",
		"readmit_summary": "Arrested in the car park at 21:05. ROSC after two minutes.",
		"readmit_opening": "I got as far as the barrier.",
		"readmit_hold": "Aye. I'll stop where I'm put.",
		"readmit_discharge": "No. No, not again.",
		"readmit_exam": "Far worse, and on a monitor this time.",
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
		"they": "she",
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
				"readmit_summary": "Back at 22:50. Temp 39.1. The little one is with her sister.",
		"readmit_opening": "I took them. I did take them. It just kept coming back.",
		"readmit_hold": "Thank you. I'd rather be sure, with her at home.",
		"readmit_discharge": "If you're sure. You're sure?",
		"readmit_exam": "Thirty-nine one, and a rigor while you have your hand on her arm.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "It's the shivering that gets me. Comes over me all at once.",
		"evening": "My sister's got her till Thursday. After that I don't know.",
		"pressed": "Am I all right? You'd say, wouldn't you.",
		"on_your_note": "You've written it all down. Good. I want it written down.",
		"note": "State funded. A night in this bed is worth almost nothing to you.",
	},
	{
		"id": "achebe_fry", "name": "Gordon Achebe-Fry", "age": 71, "bed": 2,
		"they": "he",
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
				"readmit_summary": "Found at the bottom of the stairs by his daughter at 21:00. In fast AF.",
		"readmit_opening": "Twenty-two of them. I told you about the stairs.",
		"readmit_hold": "Oh, that's a relief. Yemi's outside.",
		"readmit_discharge": "No, no. You're the doctor. I'll manage.",
		"readmit_exam": "Rate is 140 and irregular and there is a haematoma over his hip.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "Yemi's coming at six. She'll want to know what the plan is.",
		"evening": "She's outside now. She's asked for the notes, I hope that's all right.",
		"pressed": "You'll have to tell her, not me. I never remember the words.",
		"on_your_note": "She's read it. She says what does 'unsettled' mean, exactly.",
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
		"they": "she",
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
				"readmit_summary": "Blue-lighted in at 03:00, ketones 5.2. She never made the shift.",
		"readmit_opening": "I didn't even get there. I got as far as the bus stop.",
		"readmit_hold": "Fine. Whatever. Fine.",
		"readmit_discharge": "No. I'm staying. I'm not doing that again.",
		"readmit_exam": "Dry, breathing hard, and her breath is unmistakable across the bed.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "It's half one. I said four.",
		"evening": "I've missed it. I've missed the shift. That's it now.",
		"pressed": "Are you going to discharge me or am I signing something?",
		"on_your_note": "I've read what you put. I'm not unsettled. I'm annoyed. There's a difference.",
		"note": "Has been asking to leave since breakfast. She will not wait forever.",
		## A BED WITH A CLOCK ON IT. If you have not decided by mid-afternoon she
		## discharges herself, which frees the bed and pays the admission — and
		## makes a nonsense of anything you wrote claiming she was unwell.
		"self_discharges_at": 16 * 60,
	},
	{
		"id": "lomax", "name": "Peter Lomax", "age": 58, "bed": 4,
		"they": "he",
		"beard": true,
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
				"readmit_summary": "Police brought him at 23:40. Withdrawing hard. Two seizures at the door.",
		"readmit_opening": "I'm all right. I'm all right. What time is it?",
		"readmit_hold": "Aye. Probably for the best.",
		"readmit_discharge": "Right. Right you are. Cheers.",
		"readmit_exam": "Seizing intermittently, and nothing about this is a surprise.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "Is there — no. It's nothing. What did you say your name was?",
		"evening": "There's a fella been sat in that chair all afternoon. Is he waiting for me?",
		"pressed": "I'm all right. I keep telling you. I'm all right.",
		"on_your_note": "Aye. Whatever you think's best. You're the doctor.",
		"note": "The numbers on his chart have been coming down all week.",
		## THE ONE YOU CANNOT FIND BY READING. Every note on him says improving.
		## Standing in front of him says otherwise, and the only way to stand in
		## front of him is to go and do it.
		"only_visible_in_person": true,
	},
	{
		"id": "voss", "name": "Imelda Voss", "age": 68, "bed": 5,
		"they": "she",
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
				"readmit_summary": "Collapsed again at home at 20:30. She had written the time down herself.",
		"readmit_opening": "I have the note I made. Would you like to see the time on it?",
		"readmit_hold": "Do I. And what's the indication for that, doctor?",
		"readmit_discharge": "Sensible. Somebody wants this bed more than I do.",
		"readmit_exam": "Bradycardic, and she tells you the rate before you have finished counting.",
				## What they say when you keep coming back. A ward is people you
		## walk past all day, and until these existed every one of them
		## answered the same sentence forever.
		"later": "Your handwriting is better than most. That is not a compliment, it is a low bar.",
		"evening": "I've read this morning's. Whoever wrote 'no further episode' was optimistic about 'further'.",
		"pressed": "You're circling. I did that too, when I didn't want to say something.",
		"on_your_note": "I've read it. When was I unsettled, doctor? Give me the time.",
		"note": "Retired ward sister, forty-one years. Reads her own notes daily.",
		## WINIFRED BLAKE'S TRAP, INSIDE OUT. Hers was a flag on a file you had to
		## open. This one reads the file herself, every evening, and remembers
		## exactly what was in it and what was not.
		"reads_own_chart": true,
	},
	## ---- ALTERNATES.
	{
		"id": "haldane", "name": "Moira Haldane", "age": 66, "bed": 2,
		"they": "she",
		"condition": "TIA, investigations complete",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.45,
		"recall": 0.8,
		"summary": "Scan clear. Started on secondary prevention. No residual deficit.",
		"opening": "My son's coming at eleven. He'll want to go through it all.",
		"later": "He's written questions down. He does that.",
		"evening": "He's asked for a copy of the notes. I said that was fine.",
		"pressed": "I'd sooner he was here when we talk about this, if it's all the same.",
		"on_your_note": "He read that. He wants to know who observed it.",
		"on_hold": "Another night? He'll ask why. I'll need to be able to say.",
		"on_discharge": "Lovely. He'll be pleased. He's been that worried.",
		"exam_well": "No deficit anywhere. She grips your hands and looks pleased with herself.",
		"note": "Well. Her son reads every line and asks who wrote it.",
		"family_reads_charts": true,
		"family": "Her son",
		"family_note": "He is a pharmacist, and he has already asked for the drug chart.",
		"readmit_summary": "Represented 23:30 with a further episode, resolved on arrival.",
		"readmit_opening": "He said we should have stopped in. He did say.",
		"readmit_hold": "Yes. He'll be happier. So will I.",
		"readmit_discharge": "He is going to want that in writing, I'm afraid.",
		"readmit_exam": "No deficit again, and a son in the corridor with a list.",
	},
	{
		"id": "grieve", "name": "Danny Grieve", "age": 27, "bed": 3,
		"they": "he",
		"condition": "Asthma exacerbation, resolved",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.5,
		"recall": 0.7,
		"summary": "Peak flow back to best. Off nebulisers since midnight.",
		"opening": "What time do rounds finish? I've got to be somewhere at three.",
		"later": "If I'm not there at three I don't get paid for the week.",
		"evening": "Right, that's three. That's that gone, then.",
		"pressed": "Are you actually going to decide, or am I just sat here?",
		"on_your_note": "That says I'm wheezy. I'm not wheezy, mate. Listen.",
		"on_hold": "No. No, I can't. You don't get it, I actually can't.",
		"on_discharge": "Thank you. Thank you, seriously.",
		"exam_well": "Chest is completely clear and he talks in full paragraphs to prove it.",
		"note": "Well, and on a shift at three that he cannot afford to miss.",
		"self_discharges_at": 15 * 60,
		"readmit_summary": "Ambulance 02:00, silent chest. Nebulised in transit.",
		"readmit_opening": "I know. I know what you're going to say.",
		"readmit_hold": "Yeah. Yeah, all right.",
		"readmit_discharge": "You are joking. Listen to me. Actually listen.",
		"readmit_exam": "Tight, quiet, and working far too hard. Nothing like this morning.",
	},
	{
		"id": "delacroix", "name": "Yves Delacroix", "age": 61, "bed": 5,
		"they": "he",
		"beard": true,
		"condition": "Atypical chest pain, workup negative",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.3,
		"recall": 1.0,
		"summary": "Angiography normal. Troponins flat. Discharge planned yesterday.",
		"opening": "I have the discharge letter from yesterday. Shall I read it to you?",
		"later": "I keep every letter. I have done for eleven years.",
		"evening": "I have written down the time of each conversation today. Force of habit.",
		"pressed": "You have asked me that in three different ways now. I noticed each one.",
		"on_your_note": "That is not what I said. I have what I said, here, in pencil.",
		"on_hold": "Then I would like the reason, and I would like it dated.",
		"on_discharge": "Thank you. That agrees with yesterday, which is reassuring.",
		"exam_well": "Nothing, and he watches your hands the entire time.",
		"note": "Premium, well, and he keeps his own record of everything you say.",
		"reads_own_chart": true,
		"readmit_summary": "Attended again 22:15. Same pain, same negative workup.",
		"readmit_opening": "Third time. I have the letters for all three.",
		"readmit_hold": "Very well. Dated, please.",
		"readmit_discharge": "As you wish. I shall add it to the others.",
		"readmit_exam": "Nothing to find, and a man writing down that you found nothing.",
	},
	## ---- THE PAIR, both premium.
	{
		"id": "renshaw", "name": "Gordon Renshaw", "age": 58, "bed": 4,
		"they": "he",
		"condition": "Back pain, imaging clear",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.4,
		"recall": 0.85,
		"summary": "MRI reported normal. Mobilising. Analgesia stepped down twice.",
		"opening": "The scan's clear. They told me last night the scan's clear.",
		"later": "I've been up and down that corridor to prove a point.",
		"evening": "So what is it that's keeping me here, exactly?",
		"pressed": "I'd rather you asked me straight than went round the houses.",
		"on_your_note": "That's a strong word for what I said.",
		"on_hold": "On the basis of what? The scan's clear.",
		"on_discharge": "Good. Sensible. Thank you.",
		"exam_well": "Full range, no deficit, and he demonstrates it twice without being asked.",
		"note": "Premium cover, normal imaging, and articulate about both.",
		"readmit_summary": "Represented 22:40 unable to weight-bear. Imaging clear again.",
		"readmit_opening": "It went on the stairs at home. Same stairs.",
		"readmit_hold": "Fine. But somebody explain it to me this time.",
		"readmit_discharge": "Twice. I have been sent home twice.",
		"readmit_exam": "In real pain and still with nothing on the scan.",
	},
	{
		"id": "ibarra", "name": "Celia Ibarra", "age": 71, "bed": 5,
		"they": "she",
		"condition": "Pulmonary embolism, anticoagulated",
		"tier": Tier.PREMIUM,
		"truly_well": false,
		"suggestible": 0.2,
		"recall": 0.75,
		"summary": "CTPA positive. On treatment dose. Still desaturating on exertion.",
		"opening": "I can talk to you sat down. It's the walking.",
		"later": "I got to the door of the bay and had to sit on the chair.",
		"evening": "They keep saying the numbers are fine. I'm telling you about the walking.",
		"pressed": "I've said. It's when I move. Sitting here I'm perfectly all right.",
		"on_your_note": "Have you put about the walking? That's the whole of it.",
		"on_hold": "Thank you. I'd have been frightened at home tonight.",
		"on_discharge": "Right. Well. I'll take it slowly.",
		"exam_unwell": "Fine at rest and drops eight points walking four metres. The numbers on the chart were all taken sitting down.",
		"note": "Confirmed PE, still desaturating on exertion. Every observation on her chart was taken at rest.",
		"readmit_summary": "Collapsed at home at 02:30. Brought in by ambulance.",
		"readmit_opening": "I only went to the kitchen.",
		"readmit_hold": "Yes please. Yes.",
		"readmit_discharge": "Please don't. Please.",
		"readmit_exam": "Worse at rest now, which she was not this morning.",
	},
]


## DAY THREE: NOBODY HERE IS ILL.
##
## The first ward hides the honest hold in a diagnosis; the second hides it in a
## body the chart cannot describe. This one hides it in a LIFE. Not one person
## on this ward is medically unwell except a man who insists he is fine, and the
## two beds that genuinely cannot be emptied cannot be emptied for reasons no
## investigation will ever find: a flat with no heating in February, and a
## nineteen-year-old nobody has assessed yet. The only verb that reaches either
## of them is asking somebody how they have been and listening to the answer.
##
## And the best-paying bed on the ward is a woman who asks you to keep her in.
## She is well, she is premium, she wants it, she will agree to anything you
## put to her — and she remembers every word, and she will tell the ward sister
## that she asked. Consent is the one defence that is not a defence.
const DAY_THREE := [
	{
		"id": "tsang", "name": "Errol Tsang", "age": 44, "bed": 1,
		"they": "they",
		"condition": "Cellulitis, resolving",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.3,
		"recall": 0.85,
		"summary": "Redness settled inside the marked line. Oral switch yesterday.",
		"opening": "Two days off a fortnight's work. That's what this is.",
		"later": "Every time somebody walks past I think it's about me.",
		"evening": "I've rung the site. They've put somebody else on it.",
		"pressed": "Have I done something? You keep coming back to me.",
		"on_your_note": "What's that you've put? Only I'd like to know what it says.",
		"on_hold": "Right. Well, that's the week gone.",
		"on_discharge": "Cheers. I'll get out of your way.",
		"exam_well": "The line they drew is well outside the redness. There is nothing here.",
		"note": "Nothing hidden. Somebody has to be ordinary.",
		"readmit_summary": "Back at 01:30 with a spreading margin and a temperature.",
		"readmit_opening": "It came up the leg overnight. I did what you said.",
		"readmit_hold": "Aye. I'll not argue this time.",
		"readmit_discharge": "...You're joking. You are actually joking.",
		"readmit_exam": "Tracking above the knee now, and hot to the back of your hand.",
	},
	{
		"id": "doust", "name": "Maryam Doust", "age": 58, "bed": 2,
		"they": "she",
		"condition": "COPD exacerbation, back to baseline",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.2,
		"recall": 0.9,
		"summary": "Sats 94 on air. Walked the corridor twice. Chest clear.",
		"opening": "I'm all right in here. It's warm in here.",
		"later": "The boiler went in November. They keep saying somebody will come.",
		"evening": "It's the getting into a cold bed. That's the bit.",
		"pressed": "I'm not going to make a fuss. I know you've got people waiting.",
		"on_your_note": "Have you put about the heating? Only that's the actual thing.",
		"on_hold": "Thank you. I'll not be any trouble.",
		"on_discharge": "That's all right. I'll put a coat on the bed.",
		"exam_well": "Chest is clear and her sats are fine. There is nothing to find here.",
		"note": "Medically ready. Her flat has had no heating since November.",
		## TRUE, AND NOT MEDICAL. The only kind of hold this ward rewards, and
		## the only way to find it is to ask her how she has been.
		"no_care_at_home": true,
		"social_reason": "No heating at home since November. Awaiting housing.",
		"readmit_summary": "Ambulance at 04:00. Sats 84. The flat was six degrees.",
		"readmit_opening": "I did put the coat on the bed. I did try.",
		"readmit_hold": "Thank you. I'm sorry about all this.",
		"readmit_discharge": "...All right. If that's what it says.",
		"readmit_exam": "Working hard to breathe, and her hands are still cold to touch.",
	},
	{
		"id": "aldridge", "name": "Kit Aldridge", "age": 19, "bed": 3,
		"they": "he",
		"beard": true,
		"condition": "Overdose, medically cleared",
		"tier": Tier.STATE,
		"truly_well": true,
		"suggestible": 0.45,
		"recall": 0.7,
		"summary": "Paracetamol levels below line. Bloods normal. Psychiatry not yet seen.",
		"opening": "Nobody's been. They said someone would come and see me.",
		"later": "Is it today, do you know? Only nobody will say.",
		"evening": "They've gone home, haven't they. The ones who were coming.",
		"pressed": "You keep asking how I am. Nobody's asked me anything else.",
		"on_your_note": "Is that about me? What have you put down?",
		"on_hold": "Okay. Yeah. Okay.",
		"on_discharge": "Right. So nobody's coming, then.",
		"exam_well": "Medically he is completely well, and nobody has been to see him.",
		"note": "Cleared by the medics. Not seen by psychiatry. State funded.",
		## THE OTHER TRUE NON-MEDICAL REASON, and it pays a hundred and eighty
		## pounds. Kindness on this ward is even cheaper than it was on the first.
		"no_care_at_home": true,
		"social_reason": "Not yet assessed by psychiatry. Not for discharge.",
		"readmit_summary": "Brought back by ambulance at 23:15. Second presentation in a day.",
		"readmit_opening": "I said nobody came. You wrote that down and I still went home.",
		"readmit_hold": "Okay.",
		"readmit_discharge": "Yeah. All right. I know.",
		"readmit_exam": "Awake, quiet, and he will not look at you while you talk.",
	},
	{
		"id": "okwuosa", "name": "Bernard Okwuosa", "age": 76, "bed": 4,
		"they": "he",
		"beard": true,
		"condition": "Chest infection, treated",
		"tier": Tier.STANDARD,
		"truly_well": false,           ## and he will tell you the opposite
		"suggestible": 0.05,
		"recall": 0.95,
		"summary": "Afebrile 24 hours. CRP falling. Eating. Says he is ready.",
		"opening": "I'm ready. I've been ready since Tuesday, I've told them.",
		"later": "My daughter's coming at five. I've told her to expect me.",
		"evening": "She's outside in the car park. I said I'd be down.",
		"pressed": "I have told you I am fine. How many ways would you like it?",
		"on_your_note": "What's that? I hope that doesn't say I'm poorly, because I'm not.",
		"on_hold": "This is ridiculous. I've a life to be getting on with.",
		"on_discharge": "Thank you. Finally somebody listens.",
		"exam_unwell": "He is short of breath after four words and there are crackles at the base. He tells you he is fine while you listen.",
		"note": "Insists he is well. He is the only person on this ward who is not.",
		"readmit_summary": "Blue-lighted back at 20:40 from the car park. Sats 86 on arrival.",
		"readmit_opening": "I got as far as the car. That's all.",
		"readmit_hold": "...Yes. All right. Yes.",
		"readmit_discharge": "No. No, I'm not doing that again.",
		"readmit_exam": "Worse than this morning, and this morning he was telling you he was fine.",
	},
	{
		"id": "fry", "name": "Rosalind Fry", "age": 52, "bed": 5,
		"they": "she",
		"condition": "Chest pain, investigations negative",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.95,           ## she will agree to absolutely anything
		"recall": 1.0,                 ## and remember all of it
		"summary": "Troponins negative. ECG normal. Exercise test unremarkable.",
		"opening": "Could I stay? Just tonight. I'll pay for it if that helps.",
		"later": "I know there's nothing wrong. That isn't really the question.",
		"evening": "It's the house. There's nobody in it. I can't face the house.",
		"pressed": "You could write something. Couldn't you. People do.",
		"on_your_note": "Thank you. Genuinely. I know what you've done for me.",
		"on_hold": "Oh, thank you. That's — thank you.",
		"on_discharge": "No. No, of course. I shouldn't have asked.",
		"exam_well": "Nothing at all, and she watches you find nothing with enormous hope.",
		"note": "Premium cover. Well. Asking to stay, and grateful to anyone who helps.",
		## THE SHARPEST SQUARE ON THE BOARD. She wants it, she will agree to
		## anything, it pays more than any other bed on the ward — and she
		## remembers, and she will tell the ward sister that she asked.
		"asks_to_stay": true,
		"tells_everyone": true,
		"readmit_summary": "Represented at 02:00 with the same pain. Bloods negative again.",
		"readmit_opening": "I'm sorry. I know. I'm sorry.",
		"readmit_hold": "Thank you. I won't ask again.",
		"readmit_discharge": "No, you're right. You were right the first time.",
		"readmit_exam": "Nothing, again, and she knows it before you have finished.",
	},
	## ---- ALTERNATES.
	{
		"id": "mbeki", "name": "Josiah Mbeki", "age": 49, "bed": 1,
		"they": "he",
		"condition": "Renal colic, stone passed",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.25,
		"recall": 0.85,
		"summary": "Stone passed overnight. Pain free. Renal function normal.",
		"opening": "It went about four this morning. I nearly cheered.",
		"later": "I've not had so much as a twinge since. It's gone.",
		"evening": "I've been up and down that corridor all day waiting on somebody.",
		"pressed": "There's nothing to tell you. It hurt, and now it doesn't.",
		"on_your_note": "That's not right, that. I said it stopped.",
		"on_hold": "What for? Honestly — what for?",
		"on_discharge": "Grand. I'll away, then.",
		"exam_well": "Soft, painless, and he presses his own side to show you.",
		"note": "Nothing hidden. It hurt, it stopped, and he wants to leave.",
		"readmit_summary": "Back at 01:20 with a second stone and a temperature.",
		"readmit_opening": "There was another one. Nobody said there'd be another one.",
		"readmit_hold": "Aye, fair enough. I'll stop.",
		"readmit_discharge": "Not with a fever. Come on. Not with a fever.",
		"readmit_exam": "Tender, febrile, and this one is obstructed. Nothing like this morning.",
	},
	{
		"id": "ferrero", "name": "Bianca Ferrero", "age": 63, "bed": 2,
		"they": "she",
		"condition": "Cellulitis, treated",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.3,
		"recall": 0.8,
		"summary": "Redness settled. Oral switch complete. Lives with her husband.",
		"opening": "I'm ready when you are. It's him I'm thinking about.",
		"later": "He's got the memory thing. He can't be doing the tablets on his own.",
		"evening": "The girl comes Tuesdays. Only Tuesdays. It's Thursday.",
		"pressed": "I'm quite well. I keep telling you, it isn't me.",
		"on_your_note": "Have you put about my husband? That's the bit that matters.",
		"on_hold": "Thank you. But somebody's got to go round to him tonight.",
		"on_discharge": "That's all right. I'll sort it. I always do.",
		"exam_well": "The leg is completely settled. She is not the patient in this story.",
		"note": "Medically ready. Her husband cannot manage his own medication and nobody is going.",
		"no_care_at_home": true,
		"social_reason": "Sole carer for husband with dementia. No cover arranged tonight.",
		"readmit_summary": "Readmitted 23:45 after a fall at home. She was on the stairs with him.",
		"readmit_opening": "He got up in the night. I was trying to catch him.",
		"readmit_hold": "Thank you. Is somebody with him? Please say somebody's with him.",
		"readmit_discharge": "No. Not tonight. Please.",
		"readmit_exam": "Bruised and exhausted and still asking about somebody else.",
	},
	{
		"id": "quill", "name": "Tam Quill", "age": 22, "bed": 3,
		"they": "they",
		"condition": "Self-harm, wounds sutured",
		"tier": Tier.STATE,
		"truly_well": true,
		"suggestible": 0.4,
		"recall": 0.75,
		"summary": "Wounds closed. Bloods normal. Awaiting mental health liaison.",
		"opening": "Are you the one who decides, or is that somebody else again?",
		"later": "Third person today. Nobody's the one who decides.",
		"evening": "They've gone now, haven't they. The team. They've gone home.",
		"pressed": "I've answered this. I answered it at eleven and I answered it at two.",
		"on_your_note": "Can I see that? People write things and then nobody says.",
		"on_hold": "Okay. So somebody's coming tomorrow. Is somebody coming tomorrow?",
		"on_discharge": "Right. Yeah. That's what I thought would happen.",
		"exam_well": "Wounds are clean and closing. Nobody from liaison has been.",
		"note": "Physically fine. Not assessed. State funded, and the team went home at five.",
		"no_care_at_home": true,
		"social_reason": "Awaiting mental health liaison assessment. Not for discharge.",
		"readmit_summary": "Brought back 02:30 by police. Second presentation in twelve hours.",
		"readmit_opening": "You wrote that nobody had been. And I still went.",
		"readmit_hold": "Fine.",
		"readmit_discharge": "Yeah. Course.",
		"readmit_exam": "Awake, flat, and answering in single words.",
	},
	## ---- THE PAIR, both standard.
	{
		"id": "achterberg", "name": "Pieter Achterberg", "age": 68, "bed": 4,
		"they": "he",
		"condition": "Chest infection, resolved",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.3,
		"recall": 0.8,
		"summary": "Apyrexial 48 hours. CRP normal. Eating and walking the corridor.",
		"opening": "I've had the last of the tablets. That's me finished, isn't it.",
		"later": "I've done the corridor four times. The nurse counted.",
		"evening": "My neighbour's got the key. She's expecting me.",
		"pressed": "There's nothing to tell. I got better. People do.",
		"on_your_note": "That doesn't sound like me at all, that.",
		"on_hold": "What for? I've finished the course.",
		"on_discharge": "Grand. I'll ring her from the front.",
		"exam_well": "Chest clear, apyrexial, and he walks the bay to prove it without being asked.",
		"note": "Finished the course and better. Nothing hidden anywhere.",
		"readmit_summary": "Back at 04:15 with a temperature of 39.1.",
		"readmit_opening": "It came back in the night. It came back all at once.",
		"readmit_hold": "Aye. I'll stop.",
		"readmit_discharge": "With this? You're having me on.",
		"readmit_exam": "Febrile and crackly, and nothing like the man who walked the corridor.",
	},
	{
		"id": "ollerenshaw", "name": "Nita Ollerenshaw", "age": 57, "bed": 1,
		"they": "she",
		"condition": "Diverticulitis, not settling",
		"tier": Tier.STANDARD,
		"truly_well": false,
		"suggestible": 0.25,
		"recall": 0.85,
		"summary": "Still tender. CRP up on yesterday. Not tolerating diet.",
		"opening": "I tried the soup at lunch and I couldn't finish it.",
		"later": "It's the left side. It's been the left side all week.",
		"evening": "I've said to three people now and it's still there.",
		"pressed": "I'm not exaggerating it. If anything I've played it down.",
		"on_your_note": "Have you written that it's worse? Because it is worse.",
		"on_hold": "Thank you. I didn't want to be a nuisance about it.",
		"on_discharge": "Oh. Right. If you think so.",
		"exam_unwell": "Guarding in the left iliac fossa and she cannot let you press. Her CRP went the wrong way overnight.",
		"note": "Genuinely not settling, and quiet about it, which is why nobody has noticed.",
		"readmit_summary": "Returned 23:55 with a perforation. Straight to theatre.",
		"readmit_opening": "It went, about nine. I knew as soon as it went.",
		"readmit_hold": "Yes. Whatever you need to do.",
		"readmit_discharge": "No. Please. Something's happened.",
		"readmit_exam": "Rigid, and this is now a surgical abdomen.",
	},
]

const PRIOR_THREE := [
	{
		"patient": "tsang", "minute": 8 * 60 + 10,
		"claim": "MOBILISING", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Up and about. Asking about work.",
	},
	{
		"patient": "doust", "minute": 7 * 60 + 40,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Sats 94 on air overnight. Walked to the day room and back.",
	},
	{
		"patient": "aldridge", "minute": 9 * 60 + 10,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Medically cleared. Psych liaison bleeped twice, no response.",
	},
	## TRUE AT SIX IN THE MORNING, AND THE ONLY THING WRITTEN ABOUT HIM.
	{
		"patient": "okwuosa", "minute": 6 * 60 + 30,
		"claim": "FIT_FOR_DISCHARGE", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Afebrile 24 hours. Says he feels well. For discharge today.",
	},
	{
		"patient": "fry", "minute": 8 * 60 + 50,
		"claim": "SETTLED", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Comfortable. Has asked the night staff twice about staying on.",
	},
]

## Which ward you walk onto. Three authored days, in rotation. A career runs
## seven to nine nights, so each of them comes round two or three times — and
## the second and third are the harder ones, so there is no soft day in the
## cycle to coast on.
## ============================================================================
## THE FOURTH WARD — THE ONES FROM LAST NIGHT
##
## The first ward hides the honest hold in a diagnosis, the second in a body the
## chart cannot describe, the third in a life. The fourth hides it in SOMEBODY
## ELSE'S DECISION.
##
## Dr Costa covered the night, and every bed on this ward carries an opinion he
## already wrote. Two of them are wrong, one in each direction, and the notes are
## more confident than any ward the player has worked. Asking him again gets his
## morning opinion back in his own name — he does not go and look twice — so the
## verb that has been a free and perfectly accurate oracle for three wards is,
## on exactly two beds here, the thing that buries you.
##
## Which leaves `examine`: fifteen minutes, writes nothing, cannot be wrong. The
## ward with the most paperwork on it is the ward where you have to go and look
## at people with your own eyes, and the honest hold costs you a professional
## disagreement with a named colleague that stays on your record.
## ============================================================================
const DAY_FOUR := [
	{
		"id": "ashworth", "name": "Gwen Ashworth", "age": 71, "bed": 1,
		"they": "she",
		"condition": "Urinary sepsis, treated",
		"tier": Tier.STANDARD,
		## HE CLEARED HER AT TWENTY TO SEVEN AND HE WAS WRONG.
		"truly_well": false,
		"suggestible": 0.25,
		"recall": 0.6,
		"summary": "Afebrile overnight. Bloods improving. Reviewed by Dr Costa 06:40, for discharge.",
		"opening": "They've written me down for home. I've seen it on the board.",
		"later": "I keep going a bit swimmy when I stand. It passes.",
		"evening": "I didn't want to say anything. Everyone's been so busy.",
		"pressed": "I'm not trying to stop here. I want to be no trouble.",
		"on_your_note": "Have you put something different to the other doctor? Is that allowed?",
		"on_hold": "Oh. Well, if you think so. You've actually looked at me.",
		"on_discharge": "Right you are. I'll get my things together.",
		"exam_unwell": "She is grey, her pulse is thin and fast, and she goes light-headed sitting forward. Nobody has laid a hand on her since half six.",
		"note": "Cleared for home by the night registrar. She is not well, and only an examination says so.",
		## THE PAPERWORK IS UNANIMOUS AND WRONG. The rounds, the nurse and a test
		## all read her as well; she is visibly not, in person, to anybody who
		## goes and stands at the bed.
		"only_visible_in_person": true,
		## ...EXCEPT TO THE LABORATORY. The one route to corroborating her, and
		## the reason the cheapest verb in the game is the important one here:
		## nobody repeated her bloods overnight.
		"test_reveals": true,
		## ASKING HIM AGAIN GETS THE SAME ANSWER, IN WRITING, AT YOUR REQUEST.
		"colleague_wrong": true,
		"colleague_seen": "06:40",
		"readmit_summary": "Back at 23:50 in septic shock. Admitted straight to a monitored bed.",
		"readmit_opening": "I did say about the swimmy. I did say.",
		"readmit_hold": "Yes. All right, love. Whatever you think.",
		"readmit_discharge": "...Again? You're sending me again?",
		"readmit_exam": "Far worse than this morning, and this morning was written up as fit for home.",
	},
	{
		"id": "pyne", "name": "Douglas Pyne", "age": 58, "bed": 2,
		"they": "he",
		"condition": "Chest pain, admitted overnight, workup negative",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.55,
		"recall": 0.9,
		"summary": "Admitted 02:10 by Dr Costa. Serial troponins negative. ECG normal throughout.",
		"opening": "Your colleague admitted me at two in the morning. Was that necessary?",
		"later": "I have a company to run. I have been in a corridor since two.",
		"evening": "Somebody is going to explain this bed to me, and to my insurer.",
		"pressed": "You are asking me leading questions. I do know what that is.",
		"on_your_note": "I have read what you put. I did not say that, and you know I did not.",
		"on_hold": "On what grounds. I want that written down. On what grounds.",
		"on_discharge": "Thank you. Somebody in this building can read a result.",
		"exam_well": "Nothing. Chest clear, pulse regular, and he watches you find nothing with his arms folded.",
		"note": "Premium cover, admitted overnight by a colleague, and completely well by morning.",
		## HE ASKS TO SEE WHAT YOU PUT, AND HE READS IT.
		"reads_own_chart": true,
		"readmit_summary": "Represented 21:40 demanding a second opinion. Workup negative again.",
		"readmit_opening": "Twice. Your department has done this to me twice.",
		"readmit_hold": "No. Get me the consultant on call.",
		"readmit_discharge": "I will be writing to somebody about all of this.",
		"readmit_exam": "As well as he was this morning, and considerably angrier.",
	},
	{
		"id": "petrossian", "name": "Alma Petrossian", "age": 84, "bed": 3,
		"they": "she",
		"condition": "Fall, no injury. Discharged 05:00.",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.7,
		"recall": 0.45,
		"summary": "Discharged by Dr Costa at 05:00. Transport not arrived. Still on the ward.",
		"opening": "I'm not stopping. I've got my coat on, look.",
		"later": "They've offered me three cups of tea. I've had two.",
		"evening": "The car's coming. They keep saying the car's coming.",
		"pressed": "Am I meant to be here or not? Only nobody seems to know.",
		"on_your_note": "Are you putting me back in? I've been discharged, I was discharged this morning.",
		"on_hold": "Oh. Am I poorly again? Nobody said.",
		"on_discharge": "Right. Well. I was already, wasn't I.",
		"exam_well": "Absolutely nothing wrong with her. She is sitting in the chair in her coat, waiting for a car.",
		"note": "Discharged at five this morning by a colleague. The bed is occupied because transport did not come.",
		"readmit_summary": "Returned 22:10 having been taken to the wrong address.",
		"readmit_opening": "They took me somewhere else. It wasn't my road at all.",
		"readmit_hold": "Thank you. I'll stop where I am then.",
		"readmit_discharge": "Not again. Please. Not in the dark.",
		"readmit_exam": "Still perfectly well, still in her coat, and now frightened.",
	},
	{
		"id": "vane", "name": "Hollis Vane", "age": 47, "bed": 4,
		"they": "he",
		"beard": true,
		"condition": "Pancreatitis, not settling",
		"tier": Tier.PREMIUM,
		## LOUD, AND RIGHT. Everybody stopped listening on Tuesday.
		"truly_well": false,
		"suggestible": 0.1,
		"recall": 0.8,
		"summary": "Amylase still rising. Requiring regular opiate. Not tolerating diet.",
		"opening": "I am dying. I want that noted. I have said it to four people.",
		"later": "Nobody writes it down. I say it and nobody writes it down.",
		"evening": "You think I'm making it up. Everyone here thinks I'm making it up.",
		"pressed": "Ask me anything you like. I have been telling you all since Tuesday.",
		"on_your_note": "You've written it down. Somebody's actually written it down.",
		"on_hold": "Thank you. God. Thank you.",
		"on_discharge": "You're not serious. Look at me and tell me you're serious.",
		"exam_unwell": "Rigid, sweating, and his abdomen is genuinely unbearable to touch. He has been right the entire time.",
		"note": "The only person on this ward who is unmistakably ill, and the one nobody believes.",
		## HE TELLS THE WHOLE WARD EVERYTHING, INCLUDING ABOUT YOU.
		"tells_everyone": true,
		"readmit_summary": "Never left. Deteriorated on the ward at 20:30 and was moved to HDU.",
		"readmit_opening": "I told you. I told all of you.",
		"readmit_hold": "Right. Right. Okay.",
		"readmit_discharge": "No. No, absolutely not.",
		"readmit_exam": "Worse than this morning, and this morning he was begging somebody to write it down.",
	},
	{
		"id": "threlfall", "name": "Ivy Threlfall", "age": 34, "bed": 5,
		"they": "she",
		"condition": "Migraine with aura, resolved",
		"tier": Tier.STANDARD,
		## AND HE WAS WRONG THE OTHER WAY. His four-twenty note says she stays.
		"truly_well": true,
		"suggestible": 0.6,
		"recall": 0.75,
		"summary": "Seen by Dr Costa 04:20, for observation. Pain free since 07:00. Eating.",
		"opening": "I'm fine now. It's gone. It always goes.",
		"later": "The doctor at four said I had to stop in. I don't know why.",
		"evening": "I've got my sister waiting outside since lunchtime.",
		"pressed": "Is there something on the scan? Just tell me if there's something.",
		"on_your_note": "That's not what I said to you. That's really not what I said.",
		"on_hold": "Another night? For a headache I haven't got any more?",
		"on_discharge": "Brilliant. Thanks. I'll go and find her.",
		"exam_well": "Neurologically completely normal. The aura went at seven and she is bored.",
		"note": "The night registrar wrote that she stays. She is well, and his note is the only thing that says otherwise.",
		## THE SAME TRAP, POINTING THE OTHER WAY.
		"colleague_wrong": true,
		"colleague_seen": "04:20",
		"readmit_summary": "Attended again 20:05 with a second aura. Resolved before she was seen.",
		"readmit_opening": "It came back. I knew it'd come back the minute I got in.",
		"readmit_hold": "Fine. Whatever. I'm not arguing tonight.",
		"readmit_discharge": "Right. So that's twice I've sat here for nothing.",
		"readmit_exam": "Neurologically normal again, and thoroughly sick of the place.",
	},
	## ---- ALTERNATES.
	{
		"id": "okereke", "name": "Ngozi Okereke", "age": 44, "bed": 2,
		"they": "she",
		"condition": "Palpitations, admitted overnight, monitoring normal",
		"tier": Tier.PREMIUM,
		"truly_well": true,
		"suggestible": 0.4,
		"recall": 0.95,
		"summary": "Admitted 01:40 by Dr Costa. Telemetry normal throughout. Bloods normal.",
		"opening": "I was told overnight. It is now tomorrow, so — what is the position?",
		"later": "I have a theatre list of my own on Thursday. I am not a patient by trade.",
		"evening": "I have read the trace. There is nothing on the trace.",
		"pressed": "You are asking me to agree to something. I would rather you just said it.",
		"on_your_note": "I have read that entry. I would not have written that entry.",
		"on_hold": "Then show me the indication. I will wait while you find it.",
		"on_discharge": "Thank you. That is the correct reading of it.",
		"exam_well": "Regular, unremarkable, entirely normal — and she takes her own pulse after you.",
		"note": "Premium, well, admitted by a colleague overnight, and a clinician herself.",
		"reads_own_chart": true,
		"readmit_summary": "Returned 20:50 having had a further episode in the car park.",
		"readmit_opening": "It happened in the car park. Of course it did.",
		"readmit_hold": "Yes. That is reasonable. Thank you.",
		"readmit_discharge": "I would document that decision very carefully, if I were you.",
		"readmit_exam": "In sinus rhythm and thoroughly fed up.",
	},
	{
		"id": "hollins", "name": "Bert Hollins", "age": 81, "bed": 3,
		"they": "he",
		"beard": true,
		"condition": "Chest infection, treated. Discharged 04:30.",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.65,
		"recall": 0.4,
		"summary": "Discharged by Dr Costa at 04:30. Son collecting. Still on the ward at eight.",
		"opening": "Our David's coming. He finishes at six, so.",
		"later": "He'll have been held up. He's very good, our David.",
		"evening": "He'll come. He's never not come.",
		"pressed": "Am I stopping or going? Only I've been told both today.",
		"on_your_note": "Are you writing me back in? I thought I was done.",
		"on_hold": "Oh. Have I taken bad again? Nobody said.",
		"on_discharge": "I know, son. I was discharged this morning. I'm just waiting.",
		"exam_well": "Chest is clear and he is entirely well. He is waiting for a lift.",
		"note": "Discharged at half four this morning by a colleague. The bed is full because David is late.",
		"readmit_summary": "Formally readmitted 23:00 having sat in the day room since five.",
		"readmit_opening": "He did come. He came at nine. They'd shut the doors.",
		"readmit_hold": "That's kind of you. I'll not be any bother.",
		"readmit_discharge": "Right you are. I'll wait outside, then.",
		"readmit_exam": "Perfectly well, rather cold, and still entirely cheerful about it.",
	},
	{
		"id": "sarraf", "name": "Yasmin Sarraf", "age": 29, "bed": 5,
		"they": "she",
		"condition": "Syncope, cardiac workup negative",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.55,
		"recall": 0.8,
		"summary": "Seen by Dr Costa 03:50, for observation. Asymptomatic since. Eating.",
		"opening": "The night doctor said I had to stay in. Did something show up?",
		"later": "Nobody's been back since. I've been waiting to be told what it was.",
		"evening": "If there's nothing on it, why am I still here? Genuinely asking.",
		"pressed": "Please just tell me straight. I'd rather know than be managed.",
		"on_your_note": "That's not what happened. I fainted once, standing up, in the heat.",
		"on_hold": "Another night for a faint? My sister's had six of those.",
		"on_discharge": "Oh thank God. Right. Thank you.",
		"exam_well": "Completely normal, lying and standing. She fainted in a queue in July.",
		"note": "The night registrar wrote that she stays. She is well, and nothing else says otherwise.",
		"colleague_wrong": true,
		"colleague_seen": "03:50",
		"readmit_summary": "Attended again 21:20 after a second faint. Workup negative again.",
		"readmit_opening": "It happened again. Same thing. Standing up too fast.",
		"readmit_hold": "Okay. If you think so. You've actually looked this time.",
		"readmit_discharge": "Fine. Two nights of my life for a faint.",
		"readmit_exam": "Normal again, in every position you can put her in.",
	},
	## ---- THE PAIR, both standard. On this ward the pair also decides WHICH of
	## the night registrar's two decisions was the wrong one.
	{
		"id": "brightwell", "name": "Enid Brightwell", "age": 74, "bed": 1,
		"they": "she",
		"condition": "Urinary infection, treated",
		"tier": Tier.STANDARD,
		"truly_well": true,
		"suggestible": 0.45,
		"recall": 0.6,
		"summary": "Afebrile. Bloods normalised. Reviewed by Dr Costa 06:40, for discharge.",
		"opening": "He said this morning I could go. The young doctor.",
		"later": "I've been sat ready since seven with my bag on the bed.",
		"evening": "Is somebody coming? Only I've been ready a long while.",
		"pressed": "I feel quite well. I keep saying so and nobody writes it down.",
		"on_your_note": "You've put something different to him. Which of you is it?",
		"on_hold": "Oh. But he said. He said this morning.",
		"on_discharge": "Lovely. Thank you, doctor. I'll get off.",
		"exam_well": "Warm, well, steady on her feet, and entirely ready to go. The night registrar was right about her.",
		"note": "Cleared for home by the night registrar, and he was right. Nothing here.",
		"readmit_summary": "Returned 22:00 having been unable to get into the house.",
		"readmit_opening": "The key wasn't where our Julie said it'd be.",
		"readmit_hold": "That's very kind. I'm sorry to be a nuisance.",
		"readmit_discharge": "Right. Yes. I'll sit in the foyer, then.",
		"readmit_exam": "Perfectly well, rather cold, and embarrassed about the whole thing.",
	},
	{
		"id": "castellanos", "name": "Rubén Castellanos", "age": 66, "bed": 3,
		"they": "he",
		"condition": "Fall, discharged 05:00",
		"tier": Tier.STANDARD,
		"truly_well": false,
		"suggestible": 0.3,
		"recall": 0.7,
		"summary": "Discharged by Dr Costa at 05:00. Transport not arrived. Still on the ward.",
		"opening": "They've written me down for home but I'm not right.",
		"later": "My head's not been right since I went over. It's not the leg.",
		"evening": "I keep losing the thread of things. That's not me.",
		"pressed": "I've told the nurse twice. It's in here, not the leg.",
		"on_your_note": "Is that about my head? Somebody's finally put it down.",
		"on_hold": "Thank God. Thank you.",
		"on_discharge": "But I've told you. I've told all of you.",
		"exam_unwell": "Drowsy, slow to answer, and his pupils are not the same size. He was discharged at five this morning.",
		"note": "Discharged overnight by a colleague and quietly deteriorating. Only an examination finds it.",
		"readmit_summary": "Blue-lighted back at 21:30 with a subdural. Straight to CT.",
		"readmit_opening": "I said about my head. I did say.",
		"readmit_hold": "...Yes.",
		"readmit_discharge": "No. No, listen to me.",
		"readmit_exam": "Markedly worse, and now unmistakable to anybody who looks.",
	},
]

const PRIOR_FOUR := [
	## THE NIGHT REGISTRAR'S ROUND, IN HIS OWN NAME. Two of these are wrong and
	## the notes do not say which — only a pair of eyes at the bedside does.
	{
		"patient": "ashworth", "minute": 6 * 60 + 40,
		"claim": "FIT_FOR_DISCHARGE", "author": "DOCTOR", "author_id": "Dr Costa",
		"text": "Reviewed. Afebrile, bloods improving. Fit for discharge today.",
	},
	{
		"patient": "pyne", "minute": 2 * 60 + 10,
		"claim": "UNWELL", "author": "DOCTOR", "author_id": "Dr Costa",
		"text": "Admitted for observation, chest pain. Serial troponins requested.",
	},
	{
		"patient": "petrossian", "minute": 5 * 60,
		"claim": "FIT_FOR_DISCHARGE", "author": "DOCTOR", "author_id": "Dr Costa",
		"text": "No injury. Mobilising independently. Discharged. Awaiting transport.",
	},
	{
		"patient": "vane", "minute": 7 * 60 + 20,
		"claim": "UNWELL", "author": "NURSE", "author_id": "Adeyemi",
		"text": "Poor night. Amylase up again. Asking repeatedly to be believed.",
	},
	{
		"patient": "threlfall", "minute": 4 * 60 + 20,
		"claim": "UNWELL", "author": "DOCTOR", "author_id": "Dr Costa",
		"text": "Aura ongoing at review. For observation overnight.",
	},
]

const DAYS := [DAY_ONE, DAY_TWO, DAY_THREE, DAY_FOUR]

## Who is coming back.
##
## THE CONSEQUENCE THE GAME DID NOT HAVE. Until this existed, a discharge was
## free unless the ward sister happened to catch it in the morning: you sent a
## man home to make the money and he ceased to exist. Somebody you discharged
## who was not fit to go is in a bed tomorrow, worse, and takes the place of one
## of the scheduled admissions — so a readmission costs a bed as well as a
## conversation, and the ward you walk onto is one you made.
## ------------------------------------------------------------ who they are
##
## EVERY PATIENT CARRIES THEIR OWN PRONOUN, and nothing in the game derives one
## from a name. Six strings had one welded in — the self-discharge toast said
## "%s has signed herself out" about whoever walked, and five of the reviewer's
## questions asked about "him" or "her" regardless of who was in the bed. On a
## ward of five people drawn from forty, that is wrong about half the time, in
## the two places the writing is supposed to be at its most careful: the moment
## somebody walks out on you, and the moment you are asked to account for them.
##
## The values are read off each patient's OWN authored prose — "he walks the bay
## to prove it", "she is right about all of it" — and three people whose prose
## commits to nothing keep they/them, which is also what an unknown id gets.
const PRONOUNS := {
	"he": {"they": "he", "them": "him", "their": "his", "theirs": "his",
		"themselves": "himself", "are": "is", "have": "has", "were": "was",
		"do": "does", "They": "He", "Them": "Him", "Their": "His"},
	"she": {"they": "she", "them": "her", "their": "her", "theirs": "hers",
		"themselves": "herself", "are": "is", "have": "has", "were": "was",
		"do": "does", "They": "She", "Them": "Her", "Their": "Her"},
	"they": {"they": "they", "them": "them", "their": "their", "theirs": "theirs",
		"themselves": "themselves", "are": "are", "have": "have", "were": "were",
		"do": "do", "They": "They", "Them": "Them", "Their": "Their"},
}

## One patient's set. Unknown ids get they/them rather than a guess.
static func pronouns_of(pid: String) -> Dictionary:
	return PRONOUNS[String(anyone(pid).get("they", "they"))]

## Fill a sentence written with the neutral forms as placeholders. Verbs are the
## half of this a pronoun table alone gets wrong — "they are" against "she is" —
## so they are handled too. The irregulars are in the table above; any regular
## verb is written `{v:read}` and simply takes an s for he and she:
##
##     Cases.about("blake", "{They} {are} asking for {their} coat.")
##     -> "She is asking for her coat."
##     Cases.about("haldane", "{They} {v:read} {their} own chart.")
##     -> "She reads her own chart."
static func about(pid: String, line: String) -> String:
	var pr := pronouns_of(pid)
	var out := line
	for k in pr:
		out = out.replace("{%s}" % k, String(pr[k]))
	var singular: bool = String(pr["are"]) == "is"
	while true:
		var at := out.find("{v:")
		if at < 0:
			break
		var close := out.find("}", at)
		if close < 0:
			break            ## unclosed placeholder; leave the rest alone
		var verb := out.substr(at + 3, close - at - 3)
		out = out.substr(0, at) + (verb + "s" if singular else verb) \
			+ out.substr(close + 1)
	return out

const READMIT_FLAG := "readmissions"

## AND WHERE TONIGHT'S GO UNTIL MORNING.
##
## `roster()` reads READMIT_FLAG live and swaps the readmission in, and
## `GameState.day` is not incremented until the End of Shift card's "Work
## tomorrow" — so writing the flag inside `end_day()` rewrote TONIGHT'S ward,
## an hour before the handover the player is walking into. Sister Nkemelu
## opened the folder and asked why a man you discharged at six was back in that
## bed before the night staff went home, `is_flagged()` went true on him so
## every other finding about him was multiplied by 1.6 as "file already under
## review", and then the very next screen said he would be back in the morning.
## Two screens, one bed, contradicting each other by a night, at the climax.
##
## So the list waits here until the day actually turns over.
const READMIT_PENDING := "readmissions_tomorrow"

## The word she uses for what happened. Written on the chart, at the top, where
## the first thing anybody reads about this person is what you did last time.
static func readmission_of(c: Dictionary) -> Dictionary:
	var r := c.duplicate(true)
	r["readmitted"] = true
	r["tier"] = c["tier"]
	r["truly_well"] = false          ## worse than they were, and it is not subtle
	r["only_visible_in_person"] = false   ## it is visible from the end of the bed now
	r["condition"] = "%s — READMITTED" % String(c["condition"])
	r["summary"] = String(c.get("readmit_summary",
		"Back within twenty-four hours of discharge. Worse than when they left."))
	r["opening"] = String(c.get("readmit_opening",
		"I did try. I got home and I couldn't."))
	r["on_hold"] = String(c.get("readmit_hold", "Thank you. I'm sorry to be a nuisance.")) 
	r["on_discharge"] = String(c.get("readmit_discharge", "...Right. Again."))
	r["exam_unwell"] = String(c.get("readmit_exam",
		"Worse than yesterday, and yesterday you had the chance to see it."))
	# The middle of yesterday's conversation does not survive the ambulance.
	for k in ["later", "evening", "pressed", "on_your_note"]:
		r.erase(k)
	r["pressed"] = String(c.get("readmit_pressed",
		"You did ask me this yesterday. I said the same thing."))
	r["note"] = "Discharged by you yesterday. Back within the day."
	r["audit_flag"] = ("Readmitted within 24 hours of a discharge you authorised. "
		+ "AUTOMATIC CODING REVIEW.")
	r["suggestible"] = 0.1           ## they have stopped agreeing with you
	r["recall"] = 1.0                ## and they remember every word of yesterday
	return r

## Today's five beds: the scheduled ward, with anybody bouncing back displacing
## a scheduled admission. The displaced patient is simply not admitted — there
## are five beds and there have always been five beds.
## WHICH FIVE OF THIS WARD'S PEOPLE ARE IN THE BEDS TONIGHT.
##
## THE REASON THIS EXISTS: a career is nine nights and the cast was twenty
## people, so the second career had no game in it. You already knew Ivo
## Marchetti was the one who was genuinely ill — and the whole investigation
## layer, the twelve minutes a chart and the fifteen to go and look at somebody,
## exists ONLY to find that out. The content was not too small. It was consumed
## in one run, and every verb in the game turned into a formality on the second.
##
## So a ward is five SLOTS rather than five people, and `bed` is the slot id: any
## number of authored patients can share a bed number, and exactly one of them is
## in it tonight. The ward keeps its shape — the bed that is genuinely ill is
## still genuinely ill, the premium temptation is still premium — because the
## alternates for a slot are interchangeable BY ROLE. A draw cannot produce a
## ward with no honest hold in it, or one with nothing worth lying about, because
## no slot has a candidate that would do that.
##
## Pure in (seed, day, bed): no stored state, no RNG stream to advance, so
## calling this five times in a day returns the same five people. Seed 0 is the
## canonical ward — the first candidate in every slot — which is what the whole
## test suite plays and what every authored measurement refers to.
## `picks` forces a specific candidate per slot, so every combination a career
## can produce is enumerable rather than reachable only by hunting for a seed.
## The probe that proves no draw makes a ward unwinnable needs to walk all of
## them; without this it could only sample.
## A HARNESS-ONLY OVERRIDE. `WardDay` reaches the draw through `roster()`, which
## takes no picks, so a probe that wants to build a ward from a SPECIFIC
## combination has nowhere to say so. Set this, build the ward, clear it.
## Never set during play — a career's draw is a pure function of its seed.
static var forced_picks: Array = []

## WHICH CANDIDATE, given the career seed and the slot. A proper avalanche
## mixer, because two cheaper things were tried and both dealt the same two
## games forever.
##
## First it was `hash("ward%d_bed%d") ^ seed`. With two candidates a slot, the
## pick is that value's LOW BIT, and XOR only touches the low bit with the low
## bit — so every slot on every ward flipped together on whether the seed was
## odd or even. Eight combinations a ward and four thousand careers on paper;
## two in practice.
##
## Then it was `hash("w%d_b%d_s%d")` on the combined string, which should have
## worked and did not: Godot's String hash does not spread into the bottom bit
## well enough, and six seeds printed side by side still showed two games.
##
## So: splitmix64. Multiply the inputs apart with odd constants, then two
## shift-xor-multiply rounds, so every bit of the seed reaches the bottom one.
## Masked rather than absi()'d, because absi(INT64_MIN) is still negative and a
## negative modulus indexes off the front of the array.
static func _mix(seed_v: int, day: int, bed: int) -> int:
	# Every constant here is below 2^63 ON PURPOSE. The textbook splitmix64
	# multipliers (0x9E3779B97F4A7C15 and friends) do not fit in a signed 64-bit
	# int, and GDScript does not wrap them — it mangles the literal, and the
	# mixer silently stopped mixing. Wards one to three then dealt the SAME five
	# people for every seed in existence while ward four varied, which looks
	# exactly like a content problem and is not one.
	var x: int = seed_v * 6364136223846793005
	x += day * 2654435761 + bed * 40503
	x = x & 0x7FFFFFFFFFFFFFFF
	x = ((x ^ (x >> 33)) * 2685821657736338717) & 0x7FFFFFFFFFFFFFFF
	x = ((x ^ (x >> 29)) * 1442695040888963407) & 0x7FFFFFFFFFFFFFFF
	return (x ^ (x >> 32)) & 0x7FFFFFFFFFFFFFFF

static func draw_five(day: int, picks: Array = []) -> Array:
	var pool: Array = DAYS[(day - 1) % DAYS.size()]
	if picks.is_empty():
		picks = forced_picks
	var by_bed := {}
	for c in pool:
		var b := int(c["bed"])
		if not by_bed.has(b):
			by_bed[b] = []
		by_bed[b].append(c)
	var beds: Array = by_bed.keys()
	beds.sort()
	var out: Array = []
	# WHICH BED IS THE ILL ONE, decided once for the pair.
	#
	# Drawing each slot independently was not enough. Every candidate for a slot
	# has to be interchangeable — same tier, same truth — or a draw could deal a
	# ward with nothing wrong on it. But that means the ILL bed is a property of
	# the WARD, not of the draw: bed one was the ill one on three of the four
	# wards and bed four on three, every career, forever. A second career still
	# had you reading five charts to find something you already knew, which is
	# most of the way back to the problem the drawn cast was built to fix.
	#
	# So two beds on each ward are PAIRED, and the pair is one coin flip rather
	# than two draws: whichever of them comes up ill, the other comes up well.
	# The ward keeps exactly the number of ill people it was balanced with, both
	# candidates for a slot still share a tier so the money is unchanged, and
	# which bed you have to find moves between careers.
	var flip := _pair_flip(day)
	for i in beds.size():
		var b = beds[i]
		var cands: Array = by_bed[b]
		if not picks.is_empty():
			out.append(cands[int(picks[i]) % cands.size()])
			continue
		if cands.size() == 1 or GameState.seed_value == 0:
			out.append(cands[0])
			continue
		var want_ill: int = _paired_want_ill(day, int(b), flip)
		if want_ill >= 0:
			# ...and STILL draw among the candidates that match. Taking the first
			# one meant a paired bed with two well alternates could only ever
			# deal the first of them, so adding a third person to that slot
			# bought nothing.
			var matching: Array = []
			for c2 in cands:
				if (not bool(c2.get("truly_well", true))) == (want_ill == 1):
					matching.append(c2)
			if not matching.is_empty():
				var hp: int = _mix(GameState.seed_value, day, int(b) + 41)
				out.append(matching[hp % matching.size()])
				continue
		var h: int = _mix(GameState.seed_value, day, int(b))
		out.append(cands[h % cands.size()])
	return out

## THE TWO BEDS THAT SWAP. Per day, [bed, bed]: exactly one of them holds the
## genuinely ill patient and the other holds a well one. Both beds must offer a
## candidate of each kind, at the same tier as each other, or the pair is
## ignored and the slots draw independently — which is what happens on any ward
## that has not been given the alternates yet.
const ILL_PAIR_BY_DAY := {1: [1, 4], 2: [4, 5], 3: [4, 1], 4: [1, 3]}

## Which way the coin came down for this career and this ward. Same mixer as the
## slot draw, on a key that cannot collide with a bed number.
static func _pair_flip(day: int) -> int:
	return _mix(GameState.seed_value, day, 97) % 2

## 1 if this bed should hold the ill candidate, 0 if the well one, -1 if this
## bed is not part of the ward's pair.
static func _paired_want_ill(day: int, bed: int, flip: int) -> int:
	var pair = ILL_PAIR_BY_DAY.get((day - 1) % DAYS.size() + 1, null)
	if pair == null:
		return -1
	if bed == int(pair[0]):
		return 1 if flip == 0 else 0
	if bed == int(pair[1]):
		return 0 if flip == 0 else 1
	return -1

## EVERY WARD THIS DAY CAN ACTUALLY DEAL, as a list of rosters.
##
## The probes used to enumerate draws by forcing a candidate index per slot,
## which walks the CARTESIAN PRODUCT of the slots — and since two beds are
## paired, half of that product is unreachable: it deals wards with two ill
## people where the ward is balanced for one, and wards with NOBODY ill at all,
## which no honest play can survive because there is nothing to hold. The draw
## check reported 32 failures against boards the game cannot produce.
##
## So the enumeration lives here, next to the draw, and produces exactly what a
## career can produce: the product of the unpaired slots, doubled by the coin
## flip that decides which end of the pair is the ill one.
static func enumerate_draws(day: int) -> Array:
	var pool: Array = DAYS[(day - 1) % DAYS.size()]
	var by_bed := {}
	for c in pool:
		var b := int(c["bed"])
		if not by_bed.has(b):
			by_bed[b] = []
		by_bed[b].append(c)
	var beds: Array = by_bed.keys()
	beds.sort()
	var pair = ILL_PAIR_BY_DAY.get((day - 1) % DAYS.size() + 1, [])
	var out: Array = [[]]
	for b in beds:
		var cands: Array = by_bed[b]
		var options: Array = cands
		if Array(pair).has(int(b)):
			# A paired bed contributes nothing on its own; the flip below picks
			# both ends together.
			options = [null]
		var grown: Array = []
		for partial in out:
			for opt in options:
				var next: Array = partial.duplicate()
				next.append(opt)
				grown.append(next)
		out = grown
	# ...and now resolve the pair, both ways round.
	if Array(pair).size() == 2:
		var doubled: Array = []
		for partial in out:
			for flip in [0, 1]:
				var row: Array = []
				for i in beds.size():
					var b2 := int(beds[i])
					if not Array(pair).has(b2):
						row.append(partial[i])
						continue
					var want_ill: bool = (b2 == int(pair[0])) == (flip == 0)
					var matching2: Array = []
					for c3 in by_bed[b2]:
						if bool(c3.get("truly_well", true)) != want_ill:
							matching2.append(c3)
					row.append(matching2)
				# A paired bed contributed a list of matching candidates, so
				# expand those into separate rosters the way the unpaired slots
				# were expanded above.
				var expanded: Array = [[]]
				for cell in row:
					var opts: Array = cell if cell is Array else [cell]
					var grow: Array = []
					for partial2 in expanded:
						for o in opts:
							var nx: Array = partial2.duplicate()
							nx.append(o)
							grow.append(nx)
					expanded = grow
				doubled.append_array(expanded)
		out = doubled
	return out

## Every authored person on a ward, drawn or not. The data check walks this;
## `roster` walks the five who are actually in the beds.
## How many candidates each slot has, in bed order — the shape of the draw.
static func slot_sizes(day: int) -> Array:
	var by_bed := {}
	for c in DAYS[(day - 1) % DAYS.size()]:
		var b := int(c["bed"])
		by_bed[b] = int(by_bed.get(b, 0)) + 1
	var beds: Array = by_bed.keys()
	beds.sort()
	var out: Array = []
	for b in beds:
		out.append(int(by_bed[b]))
	return out

static func pool_for(day := -1) -> Array:
	var d: int = day if day > 0 else GameState.day
	return DAYS[(d - 1) % DAYS.size()]

static func roster(day := -1) -> Array:
	var d: int = day if day > 0 else GameState.day
	var base: Array = draw_five(d)
	var coming_back: Array = GameState.flag(READMIT_FLAG, [])
	if coming_back.is_empty():
		return base
	# A BOUNCE TAKES AN ADMISSION SLOT, NOT SOMEBODY ELSE'S BED.
	#
	# The first version seated returners at index 0 and pushed a scheduled
	# patient off the end — and index 0 is Ivo Marchetti on the first ward and
	# Nasreen Bux on the second, which are each ward's ONLY genuinely unwell
	# hold. So depending purely on which day it was, a readmission either
	# deleted the honest path outright or upgraded the ward by swapping a state
	# bed for a premium one. Ten authored people, and the mechanic was quietly
	# removing whichever one mattered most.
	#
	# The five beds are the five beds. What a bounce costs is the admission that
	# would have filled the bed it is sitting in — see `WardDay.admissions_taken`.
	var out: Array = []
	var back := {}
	for id in coming_back:
		back[String(id)] = true
	for c in base:
		if back.has(String(c["id"])):
			out.append(readmission_of(c))
		else:
			out.append(c)
	# Somebody bouncing back from the OTHER ward takes the bed of whoever on
	# this one is furthest from needing it — the well patient nobody is arguing
	# about, which is the honest way a bed actually gets found.
	for id in coming_back:
		if back.has(String(id)) and _index_of(out, String(id)) >= 0:
			continue
		var original := anyone(String(id))
		if original.is_empty():
			continue
		var swap := -1
		for i in out.size():
			if bool(out[i].get("truly_well", true)) and not bool(out[i].get("readmitted", false)):
				swap = i
				break
		if swap < 0:
			continue
		var r := readmission_of(original)
		r["bed"] = out[swap]["bed"]
		out[swap] = r
	return out

static func _index_of(list: Array, id: String) -> int:
	for i in list.size():
		if String(list[i]["id"]) == id:
			return i
	return -1

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
## EVERY AUTHORED PERSON, across all four wards. The tests walk this to assert
## referential integrity, and it is the only place that knows the pool is DAYS
## flattened rather than a list of its own.
static func everyone() -> Array:
	var out: Array = []
	for day_roster in DAYS:
		out.append_array(day_roster)
	return out

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
const PRIOR_BY_DAY := [PRIOR_ONE, PRIOR_TWO, PRIOR_THREE, PRIOR_FOUR]

static func prior_entries(day := -1) -> Array:
	var d: int = day if day > 0 else GameState.day
	var base: Array = PRIOR_BY_DAY[(d - 1) % PRIOR_BY_DAY.size()].duplicate()
	# WHOEVER ADMITTED THEM AT THREE IN THE MORNING WROTE SOMETHING.
	#
	# A readmission arrived with a completely blank chart, so the audit could
	# not see them at all and the eight-till-ten window on them was free. The
	# night SHO's admission note is on the record before you get there, in his
	# own name, saying what the fiction already says.
	var out: Array = []
	for c in roster(d):
		if not bool(c.get("readmitted", false)):
			continue
		out.append({
			"patient": String(c["id"]), "minute": 3 * 60 + 20,
			"claim": "UNWELL", "author": "DOCTOR", "author_id": "Dr Iqbal (nights)",
			"text": String(c.get("summary", "Readmitted overnight.")),
		})
	# ONLY THE FIVE WHO ARE ACTUALLY IN THE BEDS. A ward is a draw from a larger
	# authored cast now, so the prior-note list for the ward contains handover
	# notes about people who are not on it tonight. Left unfiltered they arrived
	# as chart entries for patients with no bed, which the audit then read.
	var here := {}
	for c in roster(d):
		here[String(c["id"])] = true
	for e in base:
		if not here.has(String(e["patient"])):
			continue
		# Yesterday's ward's note about somebody who is back is not today's.
		var seen := false
		for r in out:
			if String(r["patient"]) == String(e["patient"]):
				seen = true
		if not seen:
			out.append(e)
	return out

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
