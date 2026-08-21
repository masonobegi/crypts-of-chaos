extends Node
## All game content lives here as plain data so conditions, treatments,
## complications, personalities, events and upgrades can be added without
## touching a single system. Everything medical is invented.

# =============================================================== PRESCRIPTIONS
## What somebody goes home with. Entirely invented, like everything else here.
##
## The indicated one keeps them at home. An inert one does nothing at all, so
## whatever was wrong with them is still wrong with them in a few days — and a
## readmission is a fresh admission, at a fresh daily rate, with a perfectly
## honest explanation. The third kind does something, and what it does turns up
## at the front desk about a week later looking like bad luck.
##
## The pharmacy keeps a record of all three. It is the only device log in the
## building the player cannot reach.
const PRESCRIPTIONS := {
	"chalkinol_takehome": {
		"name": "Chalkinol, 40mg", "kind": "indicated",
		"blurb": "Twice daily with food. Tastes like a library.",
		"treats": ["funny_bone", "spleen_torque", "percussive_sinus", "knuckle_weather",
			"recursive_sneeze", "borrowed_ache", "clerical_lung", "lactose_hostility",
			"premonitory_hangover", "acute_moustache_strain"],
	},
	"beigeostat": {
		"name": "Beigeostat", "kind": "indicated",
		"blurb": "Holds the colour. Does not restore it.",
		"treats": ["chronic_beige", "ossified_vibes", "gravitational_confusion",
			"reverse_shivers", "magnetic_indecision", "residual_monday",
			"spontaneous_tuesday", "opaque_torso", "latent_geometry"],
	},
	"bone_salts": {
		"name": "Compound Bone Salts", "kind": "indicated",
		"blurb": "For anything that has recently been the wrong shape.",
		"treats": ["fractured_wrist", "fractured_ankle", "cracked_ribs",
			"dislocated_shoulder", "torn_knee", "acute_shatter", "ghost_fracture",
			"percussive_collapse", "escalating_posture", "acute_deflation"],
	},
	"calmitol": {
		"name": "Calmitol", "kind": "indicated",
		"blurb": "Takes the edge off having had an opinion.",
		"treats": ["bilateral_opinions", "calcified_grudge", "recursive_worry",
			"borrowed_conviction", "chronic_certainty", "ambient_grievance",
			"concussion", "perforated_patience", "argumentative_reflex",
			"unfinished_yawn", "catastrophic_yawn"],
	},
	"placebex_takehome": {
		"name": "Placebex, 10mg", "kind": "inert",
		"blurb": "Well tolerated. Extremely well tolerated.",
		"treats": [],
	},
	"saline_caps": {
		"name": "Saline Capsules", "kind": "inert",
		"blurb": "Salt. In a capsule. Entirely above board.",
		"treats": [],
	},
	"dual_course": {
		"name": "Dual Course (Chalkinol + Calmitol)", "kind": "reactive",
		"blurb": "Both, together, at the full dose. Rarely indicated.",
		"treats": [], "reaction": "delayed_reaction",
	},
	"loading_dose": {
		"name": "Beigeostat Loading Dose", "kind": "reactive",
		"blurb": "The whole course, in the first three days.",
		"treats": [], "reaction": "escalating_politeness",
	},
}

static func prescription(id: String) -> Dictionary:
	return PRESCRIPTIONS.get(id, {})

static func prescription_name(id: String) -> String:
	return String(PRESCRIPTIONS.get(id, {}).get("name", id))

## Is this what you would actually send somebody home with?
static func prescription_indicated(med_id: String, condition_id: String) -> bool:
	return Array(PRESCRIPTIONS.get(med_id, {}).get("treats", [])).has(condition_id)

## Everything on the shelf that IS indicated for them. Empty means nothing in
## the pharmacy touches it, which is its own kind of answer.
static func prescriptions_for(condition_id: String) -> Array[String]:
	var out: Array[String] = []
	for id in PRESCRIPTIONS:
		if prescription_indicated(String(id), condition_id):
			out.append(String(id))
	return out

# =============================================================== SHIFTS
## Three shifts, and picking one is the first decision of every day.
##
## The trade is not "more or fewer witnesses" — it is WITNESSES against
## ATTRIBUTION. A night shift has almost nobody on the floor to see what you do,
## and exactly one person anybody can blame for it afterwards. A day shift is
## crowded, and a crowd is also an alibi. That is the whole reason there are
## three of these rather than one.
##
## pay         : multiplier on your salary for the shift
## appointments: how many booked encounters land on your list
## scrutiny    : how carefully the paperwork is read afterwards
## admissions  : morning arrivals multiplier
## night_penalty: how much of the evening out the shift has already cost you
##
## The note was "there is not as much of a trade-off for any shift — why am I
## getting paid more and there are fewer people in the morning?", and it was
## right: nights paid better AND had nobody watching, so the only thing it cost
## was volume, and volume is the thing a cheat cares least about.
##
## Each one gives up something the others keep:
##  * DAY is the money. Eight on the list and everybody billing — and five
##    members of staff on the floor who will see anything you try.
##  * EVENING is the compromise, and the one shift where you get an evening out
##    afterwards at full strength.
##  * NIGHT is the one where nobody is watching, and it costs you BOTH ends of
##    the day: two appointments, and you have been awake for eight hours when
##    the streets are the only place left to be. `night_penalty` is how much of
##    an evening out you have left in you.
const SHIFTS := {
	"night": {
		"name": "Night", "start_hour": 0, "hours": 8,
		"pay": 1.60, "appointments": 2, "scrutiny": 0.35, "admissions": 0.35,
		"night_penalty": 1.0,
		"blurb": "Two on the list and one nurse in the building.",
		"catch": "Nobody sees a thing — and you are too wrecked to go out after.",
	},
	"day": {
		"name": "Day", "start_hour": 8, "hours": 8,
		"pay": 1.0, "appointments": 8, "scrutiny": 1.15, "admissions": 1.0,
		"night_penalty": 0.0,
		"blurb": "Eight on the list, five staff on the floor, consultant rounds.",
		"catch": "All of the money, and an audience for everything you do.",
	},
	"evening": {
		"name": "Evening", "start_hour": 16, "hours": 8,
		"pay": 1.25, "appointments": 5, "scrutiny": 0.7, "admissions": 0.7,
		"night_penalty": 0.0,
		"blurb": "Visiting hours, then the building empties.",
		"catch": "Families see things staff have learned not to — and you finish "
			+ "with the whole night ahead of you.",
	},
}

## Who is actually rostered on. Indices into the spawned staff, so the same
## Nurse Sarah works the same shifts every day and "she's on nights" becomes a
## fact worth knowing rather than a dice roll.
const ROTA := {
	"night": {"nurses": [0], "doctors": []},
	"day": {"nurses": [0, 1, 3], "doctors": [0, 1]},
	"evening": {"nurses": [2, 4], "doctors": [2]},
}

const SHIFT_ORDER := ["night", "day", "evening"]

static func shift(kind: String) -> Dictionary:
	return SHIFTS.get(kind, SHIFTS["day"])

static func shift_name(kind: String) -> String:
	return String(shift(kind).get("name", kind))

static func rota(kind: String) -> Dictionary:
	return ROTA.get(kind, ROTA["day"])

## How many people are on the floor with you. Drives attribution: an injury
## discovered after a shift with one member of staff on it is not a mystery.
static func staff_on(kind: String) -> int:
	var r := rota(kind)
	return Array(r.get("nurses", [])).size() + Array(r.get("doctors", [])).size()

# =============================================================== CONDITIONS
## base_days   : honest expected stay
## rate        : recovery per day under correct care
## revenue     : base daily billing before insurance multiplier
## treats      : treatment ids that actually help
## dept        : which department unlocks it
## tell        : the visible/absurd symptom described on the chart
const CONDITIONS := {
	"funny_bone": {
		"name": "Inflamed Funny Bone",
		"procedure": "prescribe",
		"desc": "The bone is not funny. It is furious.",
		"base_days": 2.0, "rate": 0.55, "revenue": 1200,
		"treats": ["percussive_realign", "chalkinol", "rest"],
		"dept": "ward", "tell": "Elbow emits a low comedic hum.",
		"color": Color(0.95, 0.62, 0.3),
	},
	"chronic_beige": {
		"name": "Chronic Beige",
		"procedure": "prescribe",
		"desc": "Patient is beiging. Prognosis: taupe.",
		"base_days": 3.0, "rate": 0.4, "revenue": 900,
		"treats": ["vibe_stabilize", "colour_therapy", "rest"],
		"dept": "ward", "tell": "Noticeably beige around the edges.",
		"color": Color(0.82, 0.75, 0.6),
	},
	"spleen_torque": {
		"name": "Excessive Spleen Torque",
		"procedure": "prescribe",
		"desc": "Spleen is over-tightened. Do not overtighten the spleen.",
		"base_days": 2.5, "rate": 0.48, "revenue": 1500,
		"treats": ["torque_wrench", "humour_rebalance", "fluids"],
		"dept": "ward", "tell": "Faint ratcheting sound when they laugh.",
		"color": Color(0.6, 0.35, 0.7),
	},
	"percussive_sinus": {
		"name": "Percussive Sinus Syndrome",
		"procedure": "suture",
		"desc": "Sinuses keep time. Badly.",
		"base_days": 1.5, "rate": 0.7, "revenue": 700,
		"treats": ["steam_tent", "chalkinol", "rest"],
		"dept": "ward", "tell": "Audibly maintains a 4/4 rhythm.",
		"color": Color(0.4, 0.7, 0.9),
	},
	"gravitational_confusion": {
		"name": "Mild Gravitational Confusion",
		"procedure": "prescribe",
		"desc": "Patient is unsure which way is down. Down is unsure too.",
		"base_days": 4.0, "rate": 0.32, "revenue": 1800,
		"treats": ["vibe_stabilize", "weighted_blanket", "fluids"],
		"dept": "ward", "tell": "Hair floats slightly. Only slightly.",
		"color": Color(0.55, 0.85, 0.8),
	},
	"calcified_grudge": {
		"name": "Calcified Grudge",
		"procedure": "suture",
		"desc": "An old resentment has hardened into a physical object.",
		"base_days": 5.0, "rate": 0.26, "revenue": 2200,
		"treats": ["dread_extraction", "talk_therapy_lite", "rest"],
		"dept": "ward", "tell": "Won't say who it's about.",
		"color": Color(0.5, 0.5, 0.55),
	},
	"knuckle_weather": {
		"name": "Localised Knuckle Weather",
		"procedure": "suture",
		"desc": "It is raining in one hand.",
		"base_days": 2.0, "rate": 0.52, "revenue": 1000,
		"treats": ["steam_tent", "warm_compress", "chalkinol"],
		"dept": "ward", "tell": "Small cloud, left fist.",
		"color": Color(0.45, 0.6, 0.85),
	},
	"lactose_hostility": {
		"name": "Lactose Hostility",
		"procedure": "prescribe",
		"desc": "Beyond intolerance. The dairy started it, allegedly.",
		"base_days": 1.0, "rate": 0.85, "revenue": 600,
		"treats": ["placebex", "fluids", "rest"],
		"dept": "ward", "tell": "Glares at the dessert cart.",
		"color": Color(0.9, 0.9, 0.75),
	},
	"reverse_shivers": {
		"name": "Reverse Shivers",
		"procedure": "prescribe",
		"desc": "Shivering outward. The room gets cold instead.",
		"base_days": 3.0, "rate": 0.38, "revenue": 1400,
		"treats": ["warm_compress", "weighted_blanket", "vibe_stabilize"],
		"dept": "ward", "tell": "Ambient temperature drops two degrees.",
		"color": Color(0.6, 0.8, 1.0),
	},
	"ossified_vibes": {
		"name": "Ossified Vibes",
		"procedure": "prescribe",
		"desc": "The vibes have gone to bone. Rare. Expensive.",
		"base_days": 6.0, "rate": 0.22, "revenue": 2600,
		"treats": ["dread_extraction", "vibe_stabilize", "humour_rebalance"],
		"dept": "ward", "tell": "Emits an unmistakable clacking serenity.",
		"color": Color(0.75, 0.7, 0.5),
	},
	"spontaneous_tuesday": {
		"name": "Spontaneous Tuesday",
		"procedure": "prescribe",
		"desc": "It is Tuesday inside this patient regardless of external evidence.",
		"base_days": 2.0, "rate": 0.5, "revenue": 1100,
		"treats": ["talk_therapy_lite", "placebex", "rest"],
		"dept": "ward", "tell": "Keeps referring to 'the meeting'.",
		"color": Color(0.7, 0.65, 0.85),
	},
	"acute_moustache_strain": {
		"name": "Acute Moustache Strain",
		"procedure": "suture",
		"desc": "Overexertion of facial hair. Often competitive.",
		"base_days": 1.5, "rate": 0.66, "revenue": 800,
		"treats": ["warm_compress", "rest", "chalkinol"],
		"dept": "ward", "tell": "Moustache is visibly exhausted.",
		"color": Color(0.5, 0.35, 0.25),
	},
	"bilateral_opinions": {
		"name": "Bilateral Wrist Opinions",
		"procedure": "prescribe",
		"desc": "Both wrists have views. The views differ.",
		"base_days": 2.5, "rate": 0.46, "revenue": 1300,
		"treats": ["opinion_realign", "torque_wrench", "rest"],
		"dept": "ward", "tell": "Left wrist disagrees with right wrist, audibly.",
		"color": Color(0.72, 0.45, 0.55),
	},
	"recursive_sneeze": {
		"name": "Recursive Sneeze",
		"procedure": "prescribe",
		"desc": "Each sneeze causes the previous sneeze. Do not think about it.",
		"base_days": 2.0, "rate": 0.54, "revenue": 1150,
		"treats": ["steam_tent", "ultrasonic_dusting", "placebex"],
		"dept": "ward", "tell": "Sneezing in a pattern that has no beginning.",
		"color": Color(0.85, 0.82, 0.60),
	},
	"unfinished_yawn": {
		"name": "Chronic Unfinished Yawn",
		"procedure": "prescribe",
		"desc": "It has been going since Thursday. It is not going well.",
		"base_days": 3.5, "rate": 0.34, "revenue": 1600,
		"treats": ["counter_yawn", "dread_extraction", "rest"],
		"dept": "ward", "tell": "Mid-yawn. Has been for some time.",
		"color": Color(0.62, 0.68, 0.75),
	},
	"borrowed_ache": {
		"name": "Borrowed Ache",
		"procedure": "prescribe",
		"desc": "The ache belongs to somebody else. Nobody has come forward.",
		"base_days": 3.0, "rate": 0.4, "revenue": 1450,
		"treats": ["talk_therapy_lite", "vibe_stabilize", "warm_compress"],
		"dept": "ward", "tell": "Winces on someone else's behalf.",
		"color": Color(0.68, 0.55, 0.62),
	},
	"magnetic_indecision": {
		"name": "Magnetic Indecision",
		"procedure": "prescribe",
		"desc": "Cannot choose. Attracts cutlery while failing to.",
		"base_days": 4.0, "rate": 0.3, "revenue": 1900,
		"treats": ["vibe_stabilize", "opinion_realign", "weighted_blanket"],
		"dept": "ward", "tell": "Surrounded by teaspoons. Undecided about it.",
		"color": Color(0.55, 0.60, 0.70),
	},
	"premonitory_hangover": {
		"name": "Premonitory Hangover",
		"procedure": "prescribe",
		"desc": "The hangover has arrived early. The event has not been scheduled.",
		"base_days": 1.5, "rate": 0.7, "revenue": 750,
		"treats": ["fluids", "chalkinol", "rest"],
		"dept": "ward", "tell": "Regretful about something that has not occurred.",
		"color": Color(0.78, 0.70, 0.45),
	},
	# ---------------------------------------------------------- emergency dept
	"acute_shatter": {
		"name": "Acute Vibe Shatter",
		"procedure": "set_bone",
		"desc": "Something broke. Loudly. Internally.",
		"base_days": 1.0, "rate": 0.95, "revenue": 3200,
		"treats": ["vibe_stabilize", "fluids", "chalkinol"],
		"dept": "emergency", "tell": "Making a noise like a dropped tray.",
		"color": Color(0.90, 0.45, 0.35),
	},
	"percussive_collapse": {
		"name": "Percussive Collapse",
		"procedure": "set_bone",
		"desc": "The rhythm section has given out entirely.",
		"base_days": 1.5, "rate": 0.8, "revenue": 2800,
		"treats": ["percussive_realign", "fluids", "humour_rebalance"],
		"dept": "emergency", "tell": "Arrhythmic. Aggressively so.",
		"color": Color(0.88, 0.55, 0.30),
	},
	"catastrophic_yawn": {
		"name": "Catastrophic Yawn",
		"procedure": "prescribe",
		"desc": "It got away from them.",
		"base_days": 1.0, "rate": 0.9, "revenue": 2600,
		"treats": ["counter_yawn", "dread_extraction", "fluids"],
		"dept": "emergency", "tell": "Cannot currently close.",
		"color": Color(0.75, 0.60, 0.85),
	},
	# ---------------------------------------------------------- radiology
	"opaque_torso": {
		"name": "Radiologically Opaque Torso",
		"procedure": "set_bone",
		"desc": "Nothing gets through. Nobody knows what is in there.",
		"base_days": 4.0, "rate": 0.3, "revenue": 2100,
		"treats": ["imaging", "ultrasonic_dusting", "vibe_stabilize"],
		"dept": "radiology", "tell": "Casts a shadow indoors.",
		"color": Color(0.45, 0.50, 0.58),
	},
	"ghost_fracture": {
		"name": "Ghost Fracture",
		"procedure": "set_bone",
		"desc": "A break that is not there yet.",
		"base_days": 3.0, "rate": 0.38, "revenue": 1900,
		"treats": ["imaging", "weighted_blanket", "warm_compress"],
		"dept": "radiology", "tell": "Winces pre-emptively.",
		"color": Color(0.68, 0.72, 0.80),
	},
	# ---------------------------------------------------------- psychiatry
	"recursive_worry": {
		"name": "Recursive Worry",
		"procedure": "prescribe",
		"desc": "Worried about the worrying. And about that.",
		"base_days": 4.0, "rate": 0.28, "revenue": 1700,
		"treats": ["talk_therapy_lite", "dread_extraction", "colour_therapy"],
		"dept": "psych", "tell": "Has started worrying about your expression.",
		"color": Color(0.60, 0.55, 0.75),
	},
	"borrowed_conviction": {
		"name": "Borrowed Conviction",
		"procedure": "prescribe",
		"desc": "Absolutely certain about something that belongs to somebody else.",
		"base_days": 5.0, "rate": 0.24, "revenue": 2000,
		"treats": ["talk_therapy_lite", "vibe_stabilize", "rest"],
		"dept": "psych", "tell": "Will explain it to you. At length.",
		"color": Color(0.72, 0.62, 0.55),
	},
	"clerical_lung": {
		"name": "Clerical Lung",
		"procedure": "prescribe",
		"desc": "Breathing has become administrative.",
		"base_days": 5.0, "rate": 0.25, "revenue": 2400,
		"treats": ["dread_extraction", "ultrasonic_dusting", "steam_tent"],
		"dept": "ward", "tell": "Each breath appears to require sign-off.",
		"color": Color(0.70, 0.72, 0.66),
	},
	# ---- second wave. Everything here is invented, and deliberately absurd.
	"escalating_posture": {
		"name": "Escalating Posture",
		"procedure": "manipulate",
		"desc": "Patient is becoming imperceptibly taller. Perceptibly.",
		"base_days": 2.5, "rate": 0.5, "revenue": 1300,
		"treats": ["reorientation_walk", "percussive_realign", "rest"],
		"dept": "ward", "tell": "Keeps not quite fitting the bed.",
		"color": Color(0.72, 0.84, 0.66),
	},
	"residual_monday": {
		"name": "Residual Monday",
		"procedure": "prescribe",
		"desc": "It is not Monday. They are still in one.",
		"base_days": 3.5, "rate": 0.35, "revenue": 1050,
		"treats": ["rest", "colour_therapy", "sequential_apology"],
		"dept": "ward", "tell": "Faint smell of a staff meeting.",
		"color": Color(0.58, 0.60, 0.68),
	},
	"argumentative_reflex": {
		"name": "Argumentative Reflex",
		"procedure": "suture",
		"desc": "The reflex does not respond. It replies.",
		"base_days": 2.0, "rate": 0.6, "revenue": 1150,
		"treats": ["opinion_realign", "sequential_apology", "rest"],
		"dept": "ward", "tell": "Knee disagrees with the hammer.",
		"color": Color(0.88, 0.55, 0.48),
	},
	"perforated_patience": {
		"name": "Perforated Patience",
		"procedure": "prescribe",
		"desc": "Structurally sound. Emotionally draughty.",
		"base_days": 4.0, "rate": 0.3, "revenue": 1600,
		"treats": ["pressure_bath", "talk_therapy_lite", "steam_tent"],
		"dept": "ward", "tell": "Sighs to a professional standard.",
		"color": Color(0.66, 0.70, 0.78),
	},
	"chronic_certainty": {
		"name": "Chronic Certainty",
		"procedure": "prescribe",
		"desc": "Has never said 'maybe' and is not about to start.",
		"base_days": 5.0, "rate": 0.26, "revenue": 1700,
		"treats": ["talk_therapy_lite", "opinion_realign", "sequential_apology"],
		"dept": "psych", "tell": "Answers questions before they finish.",
		"color": Color(0.80, 0.72, 0.42),
	},
	"ambient_grievance": {
		"name": "Ambient Grievance",
		"procedure": "prescribe",
		"desc": "The grievance predates the admission by some years.",
		"base_days": 4.5, "rate": 0.28, "revenue": 1550,
		"treats": ["talk_therapy_lite", "colour_therapy", "weighted_blanket"],
		"dept": "psych", "tell": "Brings it up. Whatever it is.",
		"color": Color(0.62, 0.52, 0.62),
	},
	"acute_deflation": {
		"name": "Acute Deflation",
		"procedure": "prescribe",
		"desc": "Visibly less than they were this morning.",
		"base_days": 1.2, "rate": 0.9, "revenue": 3100,
		"treats": ["steam_tent", "fluids", "pressure_bath"],
		"dept": "emergency", "tell": "Slightly smaller each time you look.",
		"color": Color(0.85, 0.66, 0.58),
	},
	"latent_geometry": {
		"name": "Latent Geometry",
		"procedure": "manipulate",
		"desc": "The angles do not add up. They have been checked twice.",
		"base_days": 3.0, "rate": 0.42, "revenue": 2100,
		"treats": ["imaging", "static_discharge", "ultrasonic_dusting"],
		"dept": "radiology", "tell": "Casts a shadow with one corner too many.",
		"color": Color(0.55, 0.66, 0.80),
	},
	# ---- injuries, as the thing somebody walks in WITH. The same six ids exist
	# in COMPLICATIONS as the thing somebody leaves with, which is the entire
	# point: a fractured wrist reads identically on the chart whether they
	# arrived with it or acquired it here. What differs is when it was written.
	"fractured_wrist": {
		"name": "Fractured Wrist",
		"procedure": "set_bone", "injury": true, "part": "wrist",
		"desc": "Fell off something. Says it was a kerb.",
		"base_days": 3.0, "rate": 0.4, "revenue": 1500,
		"treats": ["splinting", "pressure_bath", "rest"],
		"dept": "ward", "tell": "Wrist held very carefully still.",
		"color": Color(0.86, 0.72, 0.66),
	},
	"fractured_ankle": {
		"name": "Fractured Ankle",
		"procedure": "set_bone", "injury": true, "part": "ankle",
		"desc": "Stairs. It is always stairs.",
		"base_days": 4.0, "rate": 0.34, "revenue": 1650,
		"treats": ["splinting", "rest", "pressure_bath"],
		"dept": "ward", "tell": "Foot at an opinionated angle.",
		"color": Color(0.80, 0.66, 0.60),
	},
	"cracked_ribs": {
		"name": "Cracked Ribs",
		"procedure": "set_bone", "injury": true, "part": "ribs",
		"desc": "Breathing has become a considered decision.",
		"base_days": 4.5, "rate": 0.3, "revenue": 1750,
		"treats": ["rest", "pressure_bath", "sling_support"],
		"dept": "ward", "tell": "Laughs once, regrets it.",
		"color": Color(0.78, 0.62, 0.62),
	},
	"dislocated_shoulder": {
		"name": "Dislocated Shoulder",
		"procedure": "manipulate", "injury": true, "part": "shoulder",
		"desc": "Out. Was in this morning.",
		"base_days": 2.5, "rate": 0.5, "revenue": 1450,
		"treats": ["reduction", "sling_support", "rest"],
		"dept": "ward", "tell": "One shoulder noticeably further away.",
		"color": Color(0.84, 0.70, 0.64),
	},
	"torn_knee": {
		"name": "Torn Knee",
		"procedure": "manipulate", "injury": true, "part": "knee",
		"desc": "Went one way. Knee went the other.",
		"base_days": 5.0, "rate": 0.26, "revenue": 1800,
		"treats": ["splinting", "rest", "pressure_bath"],
		"dept": "ward", "tell": "Will not put weight on it.",
		"color": Color(0.76, 0.68, 0.62),
	},
	"concussion": {
		"name": "Concussion",
		"procedure": "prescribe", "injury": true, "part": "head",
		"desc": "Present, mostly. Asks the same question twice.",
		"base_days": 1.6, "rate": 0.62, "revenue": 2400,
		"treats": ["rest", "reorientation_walk", "imaging"],
		"dept": "emergency", "tell": "Asks what day it is. Then asks again.",
		"color": Color(0.72, 0.74, 0.80),
	},
}

# =============================================================== TREATMENTS
## effect  : recovery delta if CORRECT for the condition
## wrong   : recovery delta if applied to a condition it doesn't treat
## verb    : what the log says
## tool    : item/machine id required (empty = hands)
## time    : seconds of interaction
const TREATMENTS := {
	"percussive_realign": {
		"name": "Percussive Realignment", "verb": "realigned percussively",
		"effect": 0.35, "wrong": -0.04, "tool": "mallet", "time": 2.0,
		"desc": "Strike the affected area with the small approved mallet.",
	},
	"chalkinol": {
		"name": "Chalkinol", "verb": "administered Chalkinol",
		"effect": 0.25, "wrong": 0.0, "tool": "syringe", "time": 1.5,
		"desc": "Broad-spectrum. Tastes like a library.",
	},
	"placebex": {
		"name": "Placebex", "verb": "administered Placebex",
		"effect": 0.12, "wrong": 0.02, "tool": "syringe", "time": 1.5,
		"desc": "Works about as well as you'd expect, which is: sometimes.",
	},
	"fluids": {
		"name": "Fluid Top-Up", "verb": "topped up fluids",
		"effect": 0.2, "wrong": 0.02, "tool": "iv_bag", "time": 2.5,
		"desc": "Hang a bag. Any bag. Ideally the right bag.",
	},
	"rest": {
		"name": "Prescribed Rest", "verb": "prescribed rest",
		"effect": 0.15, "wrong": 0.05, "tool": "", "time": 1.0,
		"desc": "Tell them to lie down. Bill for it.",
	},
	"vibe_stabilize": {
		"name": "Vibe Stabilisation", "verb": "stabilised the vibes",
		"effect": 0.4, "wrong": -0.06, "tool": "machine_vibe", "time": 3.0,
		"desc": "Run the patient through the Vibe Stabiliser at a sensible setting.",
	},
	"humour_rebalance": {
		"name": "Humour Rebalancing", "verb": "rebalanced humours",
		"effect": 0.38, "wrong": -0.05, "tool": "machine_humour", "time": 3.0,
		"desc": "Four humours. One dial. Go.",
	},
	"dread_extraction": {
		"name": "Ambient Dread Extraction", "verb": "extracted ambient dread",
		"effect": 0.45, "wrong": -0.1, "tool": "machine_dread", "time": 4.0,
		"desc": "Suction, but for the soul. Emptying the canister is your job.",
	},
	"torque_wrench": {
		"name": "Spleen Detorquing", "verb": "detorqued the spleen",
		"effect": 0.42, "wrong": -0.08, "tool": "wrench", "time": 3.0,
		"desc": "Loosen by quarter turns. Quarter. Turns.",
	},
	"steam_tent": {
		"name": "Steam Tent", "verb": "applied a steam tent",
		"effect": 0.3, "wrong": 0.01, "tool": "steam_kit", "time": 2.5,
		"desc": "A tent. Of steam. Revolutionary in 1911.",
	},
	"warm_compress": {
		"name": "Warm Compress", "verb": "applied a warm compress",
		"effect": 0.22, "wrong": 0.02, "tool": "compress", "time": 2.0,
		"desc": "Warm. Compress. Not complicated.",
	},
	"colour_therapy": {
		"name": "Colour Therapy", "verb": "administered colour therapy",
		"effect": 0.34, "wrong": 0.0, "tool": "colour_lamp", "time": 3.0,
		"desc": "Shine aggressive colours at the beige.",
	},
	"weighted_blanket": {
		"name": "Gravitational Blanket", "verb": "applied a gravitational blanket",
		"effect": 0.3, "wrong": 0.03, "tool": "blanket", "time": 2.0,
		"desc": "Reminds the patient which way down is.",
	},
	"opinion_realign": {
		"name": "Opinion Realignment", "verb": "realigned the opinions",
		"effect": 0.36, "wrong": -0.05, "tool": "wrench", "time": 3.0,
		"desc": "Bring both sides of the patient into agreement. Mechanically.",
	},
	"ultrasonic_dusting": {
		"name": "Ultrasonic Dusting", "verb": "performed ultrasonic dusting",
		"effect": 0.33, "wrong": -0.03, "tool": "duster", "time": 3.0,
		"desc": "Shake the dust out at a frequency nobody enjoys.",
	},
	"counter_yawn": {
		"name": "Counter-Yawn", "verb": "administered a counter-yawn",
		"effect": 0.4, "wrong": 0.0, "tool": "", "time": 3.5,
		"desc": "Yawn back at the patient. Firmly. Maintain eye contact.",
	},
	"imaging": {
		"name": "Diagnostic Imaging", "verb": "imaged the patient",
		"effect": 0.28, "wrong": 0.04, "tool": "machine_imaging", "time": 4.0,
		"desc": "Look inside. Properly. For once.",
	},
	"talk_therapy_lite": {
		"name": "Brief Supportive Chat", "verb": "had a brief supportive chat",
		"effect": 0.26, "wrong": 0.04, "tool": "", "time": 4.0,
		"desc": "Listen. Nod. Bill generously.",
	},
	"static_discharge": {
		"name": "Static Discharge", "verb": "discharged static",
		"effect": 0.26, "wrong": -0.02, "tool": "duster", "time": 2.0,
		"desc": "Earth the patient. Gently. With the approved duster.",
	},
	"sequential_apology": {
		"name": "Sequential Apology", "verb": "worked through a sequential apology",
		"effect": 0.2, "wrong": 0.0, "tool": "", "time": 3.0,
		"desc": "Apologise, in order, for everything. It is on the pathway.",
	},
	"pressure_bath": {
		"name": "Pressure Bath", "verb": "gave a pressure bath",
		"effect": 0.28, "wrong": 0.01, "tool": "compress", "time": 2.4,
		"desc": "Warm, firm, and over faster than anybody would like.",
	},
	"reorientation_walk": {
		"name": "Reorientation Walk", "verb": "walked them round the ward",
		"effect": 0.22, "wrong": 0.02, "tool": "", "time": 3.5,
		"desc": "Twice round the corridor. Point out the windows.",
	},
	"splinting": {
		"name": "Splinting", "verb": "splinted it",
		"effect": 0.34, "wrong": -0.03, "tool": "splint", "time": 3.0,
		"desc": "Immobilise the part. It will be furious about it either way.",
	},
	"sling_support": {
		"name": "Sling Support", "verb": "put it in a sling",
		"effect": 0.3, "wrong": -0.02, "tool": "sling", "time": 2.2,
		"desc": "Take the weight off it and let it get on with things.",
	},
	"reduction": {
		"name": "Reduction", "verb": "put it back in",
		"effect": 0.42, "wrong": -0.08, "tool": "", "time": 3.4,
		"desc": "Put it back where it was. There is a knack and you have it.",
	},
}

# =============================================================== COMPLICATIONS
## The billable secondary conditions. `causes` lists cause tags a chart accepts.
const COMPLICATIONS := {
	## What a patient leaves a disagreement with. "Fell" is on the list of
	## plausible causes and is the single most-used word in this game.
	"disputed_contusion": {
		"name": "Disputed Contusion", "days": 2.5, "rec": -0.14, "sev": 0.6,
		"symptom": "Bruising in the shape of a professional disagreement.",
		"color": Color(0.55, 0.35, 0.62),
		"causes": ["fall", "known_risk", "patient_noncompliance", "idiopathic"],
	},
	"ambient_dread": {
		"name": "Ambient Dread", "days": 1.5, "rec": -0.08, "sev": 0.35,
		"symptom": "Room feels wrong. Nobody can say why.",
		"color": Color(0.45, 0.4, 0.55),
		"causes": ["underlying", "idiopathic", "visitor_stress", "weather"],
	},
	"rebound_hiccups": {
		"name": "Rebound Hiccups", "days": 1.0, "rec": -0.05, "sev": 0.25,
		"symptom": "Hiccups that arrive in retaliation.",
		"color": Color(0.9, 0.8, 0.4),
		"causes": ["medication_reaction", "underlying", "dietary", "idiopathic"],
	},
	"ferrous_aura": {
		"name": "Ferrous Aura", "days": 2.0, "rec": -0.12, "sev": 0.5,
		"symptom": "Cutlery leans toward the patient.",
		"color": Color(0.55, 0.55, 0.62),
		"causes": ["equipment_variance", "idiopathic", "underlying"],
	},
	"draft_exposure": {
		"name": "Draft Exposure", "days": 1.0, "rec": -0.06, "sev": 0.2,
		"symptom": "Chilled. Faintly indignant about it.",
		"color": Color(0.65, 0.8, 0.95),
		"causes": ["facilities", "weather", "patient_noncompliance"],
	},
	"nocturnal_confusion": {
		"name": "Nocturnal Confusion", "days": 1.5, "rec": -0.07, "sev": 0.3,
		"symptom": "Convinced it is a different, worse night.",
		"color": Color(0.4, 0.45, 0.7),
		"causes": ["noise", "underlying", "medication_reaction", "idiopathic"],
	},
	"post_percussive_ringing": {
		"name": "Post-Percussive Ringing", "days": 1.0, "rec": -0.05, "sev": 0.4,
		"symptom": "Rings gently when nudged.",
		"color": Color(0.85, 0.7, 0.35),
		"causes": ["equipment_variance", "underlying"],
	},
	"wound_dehiscence": {
		"name": "Wound Dehiscence", "days": 2.0, "rec": -0.08, "sev": 0.5,
		"symptom": "The closure has opened again, quietly, overnight.",
		"color": Color(0.85, 0.42, 0.40),
		"causes": ["known_risk", "underlying", "patient_noncompliance"],
	},
	"secondary_beige": {
		"name": "Secondary Beige", "days": 2.0, "rec": -0.1, "sev": 0.35,
		"symptom": "A second, worse beige.",
		"color": Color(0.8, 0.74, 0.62),
		"causes": ["underlying", "idiopathic", "dietary"],
	},
	"chart_fatigue": {
		"name": "Chart Fatigue", "days": 1.0, "rec": -0.03, "sev": 0.15,
		"symptom": "Tired of being written about.",
		"color": Color(0.75, 0.75, 0.7),
		"causes": ["administrative", "idiopathic"],
	},
	"reactive_shivers": {
		"name": "Reactive Shivers", "days": 1.5, "rec": -0.09, "sev": 0.45,
		"symptom": "Shivering, but argumentatively.",
		"color": Color(0.6, 0.85, 0.95),
		"causes": ["medication_reaction", "facilities", "underlying"],
	},
	"spectral_itch": {
		"name": "Spectral Itch", "days": 1.5, "rec": -0.07, "sev": 0.3,
		"symptom": "Scratching an area that is not present.",
		"color": Color(0.72, 0.65, 0.80),
		"causes": ["idiopathic", "underlying", "medication_reaction"],
	},
	"clerical_nausea": {
		"name": "Clerical Nausea", "days": 1.0, "rec": -0.04, "sev": 0.2,
		"symptom": "Made unwell by the amount of paperwork about them.",
		"color": Color(0.80, 0.82, 0.70),
		"causes": ["administrative", "idiopathic"],
	},
	"borrowed_symptoms": {
		"name": "Borrowed Symptoms", "days": 2.0, "rec": -0.1, "sev": 0.4,
		"symptom": "Has developed the condition of the patient next door.",
		"color": Color(0.65, 0.55, 0.70),
		"causes": ["underlying", "idiopathic", "visitor_stress"],
	},
	"reverse_appetite": {
		"name": "Reverse Appetite", "days": 1.5, "rec": -0.06, "sev": 0.25,
		"symptom": "Hungrier after eating. Considerably.",
		"color": Color(0.88, 0.72, 0.50),
		"causes": ["dietary", "medication_reaction", "idiopathic"],
	},
	"gravitational_relapse": {
		"name": "Gravitational Relapse", "days": 2.5, "rec": -0.15, "sev": 0.55,
		"symptom": "Down has moved again.",
		"color": Color(0.5, 0.85, 0.75),
		"causes": ["underlying", "equipment_variance", "idiopathic"],
	},
	"sympathetic_draft": {
		"name": "Sympathetic Draft", "days": 1.2, "rec": -0.06, "sev": 0.22,
		"symptom": "Shivers in time with the window, which is shut.",
		"color": Color(0.70, 0.84, 0.92),
		"causes": ["facilities", "weather", "underlying", "idiopathic"],
	},
	"acquired_punctuality": {
		"name": "Acquired Punctuality", "days": 1.0, "rec": -0.04, "sev": 0.18,
		"symptom": "Announces the time. Correctly. Constantly.",
		"color": Color(0.86, 0.86, 0.72),
		"causes": ["idiopathic", "administrative", "underlying"],
	},
	"residual_hum": {
		"name": "Residual Hum", "days": 1.6, "rec": -0.09, "sev": 0.4,
		"symptom": "Hums at exactly the frequency of the corridor lights.",
		"color": Color(0.62, 0.72, 0.66),
		"causes": ["equipment_variance", "noise", "idiopathic"],
	},
	"misfiled_symptom": {
		"name": "Misfiled Symptom", "days": 1.4, "rec": -0.07, "sev": 0.3,
		"symptom": "Has somebody else's rash. Nobody else is missing one.",
		"color": Color(0.88, 0.70, 0.66),
		"causes": ["administrative", "physician_error", "idiopathic"],
	},
	"escalating_politeness": {
		"name": "Escalating Politeness", "days": 2.0, "rec": -0.10, "sev": 0.45,
		"symptom": "Thanks the ceiling. Twice.",
		"color": Color(0.78, 0.66, 0.86),
		"causes": ["medication_reaction", "underlying", "idiopathic"],
	},
	"delayed_reaction": {
		"name": "Delayed Reaction", "days": 1.3, "rec": -0.06, "sev": 0.28,
		"symptom": "Responds, accurately, to yesterday.",
		"color": Color(0.70, 0.66, 0.58),
		"causes": ["medication_reaction", "dietary", "idiopathic"],
	},
	# ---- the same six, as the thing that happened to somebody under your care.
	# Far more severe than the ward's ordinary absurdities, because a fractured
	# wrist is not something anybody has to be observant to notice.
	"fractured_wrist": {
		"name": "Fractured Wrist", "injury": true, "part": "wrist",
		"days": 3.0, "rec": -0.26, "sev": 0.7,
		"symptom": "Wrist held very carefully still.",
		"color": Color(0.86, 0.72, 0.66),
		"causes": ["fall", "pre_existing", "transfer", "patient_noncompliance"],
	},
	"fractured_ankle": {
		"name": "Fractured Ankle", "injury": true, "part": "ankle",
		"days": 4.0, "rec": -0.3, "sev": 0.72,
		"symptom": "Foot at an opinionated angle.",
		"color": Color(0.80, 0.66, 0.60),
		"causes": ["fall", "pre_existing", "transfer", "patient_noncompliance"],
	},
	"cracked_ribs": {
		"name": "Cracked Ribs", "injury": true, "part": "ribs",
		"days": 4.5, "rec": -0.32, "sev": 0.75,
		"symptom": "Breathing has become a considered decision.",
		"color": Color(0.78, 0.62, 0.62),
		"causes": ["fall", "pre_existing", "known_risk", "transfer"],
	},
	"dislocated_shoulder": {
		"name": "Dislocated Shoulder", "injury": true, "part": "shoulder",
		"days": 2.5, "rec": -0.22, "sev": 0.68,
		"symptom": "One shoulder noticeably further away than the other.",
		"color": Color(0.84, 0.70, 0.64),
		"causes": ["fall", "transfer", "known_risk", "patient_noncompliance"],
	},
	"torn_knee": {
		"name": "Torn Knee", "injury": true, "part": "knee",
		"days": 5.0, "rec": -0.34, "sev": 0.7,
		"symptom": "Will not put weight on it.",
		"color": Color(0.76, 0.68, 0.62),
		"causes": ["fall", "pre_existing", "transfer", "known_risk"],
	},
	"concussion": {
		"name": "Concussion", "injury": true, "part": "head",
		"days": 2.0, "rec": -0.28, "sev": 0.85,
		"symptom": "Asks what day it is. Then asks again.",
		"color": Color(0.72, 0.74, 0.80),
		"causes": ["fall", "pre_existing", "patient_noncompliance"],
	},
}

## Cause tags you can write on a chart. Some are always available; filing one
## that the complication doesn't accept is an inconsistency an auditor will find.
const CAUSES := {
	"underlying": "underlying condition",
	"idiopathic": "idiopathic (no identified cause)",
	"medication_reaction": "reaction to medication",
	"patient_noncompliance": "patient non-compliance",
	"facilities": "facilities fault",
	"weather": "atmospheric conditions",
	"visitor_stress": "visitor-induced stress",
	"dietary": "dietary",
	"noise": "environmental noise",
	"equipment_variance": "equipment variance",
	"administrative": "administrative burden",
	"physician_error": "physician error",
	# ---- mechanisms. What you write down when somebody leaves with something
	# they did not arrive with. All three are things that genuinely happen on
	# wards, which is exactly what makes them worth writing down.
	"fall": "an unwitnessed fall on the ward",
	"pre_existing": "present on admission",
	"transfer": "occurred during transfer",
	"known_risk": "a recognised risk of the procedure",
	# Truth-side tags. These never appear in the file-a-cause menu — they are
	# what the simulation knows, and they only ever surface when something
	# outside the player's handwriting reports them.
	"machine_deviation": "a treatment device run well off its prescribed setting",
	"altercation": "a physical altercation with the treating physician",
	"examination": "the examination itself",
	"surgical": "the procedure itself",
	"prescription": "what they were sent home with",
}

## Mechanisms the simulation knows about but no chart will ever accept, because
## there is no box on the form for them. Filing one is not an option; the game
## only ever uses these as TRUTH.
const TRUTH_ONLY_CAUSES := ["machine_deviation", "examination", "surgical",
	"prescription", "altercation"]

## Cause tags that can be filed against an acquired injury and be believed.
const INJURY_MECHANISMS := ["fall", "pre_existing", "transfer", "known_risk",
	"patient_noncompliance"]

## Is this id an injury rather than one of the ward's ordinary absurdities?
## Injuries are the loud half of the catalogue: obvious to anybody, expensive,
## and impossible to describe as "one of those things".
static func is_injury(id: String) -> bool:
	if CONDITIONS.has(id):
		return bool(CONDITIONS[id].get("injury", false))
	return bool(COMPLICATIONS.get(id, {}).get("injury", false))

static func body_part(id: String) -> String:
	if CONDITIONS.has(id):
		return String(CONDITIONS[id].get("part", ""))
	return String(COMPLICATIONS.get(id, {}).get("part", ""))

static func injury_ids() -> Array[String]:
	var out: Array[String] = []
	for id in COMPLICATIONS:
		if bool(COMPLICATIONS[id].get("injury", false)):
			out.append(String(id))
	return out

static func is_truth_only(cause: String) -> bool:
	return TRUTH_ONLY_CAUSES.has(cause)

# =============================================================== INSURANCE
const INSURANCE := {
	"none":       {"name": "Uninsured",       "mult": 0.25, "scrutiny": 0.1},
	"bad":        {"name": "Bare Minimum",    "mult": 0.6,  "scrutiny": 0.35},
	"standard":   {"name": "Standard",        "mult": 1.0,  "scrutiny": 0.5},
	"good":       {"name": "Good",            "mult": 1.6,  "scrutiny": 0.7},
	"excellent":  {"name": "Excellent",       "mult": 2.4,  "scrutiny": 0.9},
	"platinum":   {"name": "Platinum Concierge", "mult": 3.6, "scrutiny": 1.15},
}

# =============================================================== PERSONALITIES
## Traits are read by systems via trait_of(). Missing traits fall back to a
## default, so new archetypes only need to specify what makes them different.
const PATIENT_ARCHETYPES := {
	"trusting": {
		"name": "Trusting", "observance": 0.25, "skepticism": 0.3, "trust": 0.75,
		"talkativeness": 0.35, "escalation": 0.2, "impatience": 0.7, "vital_bias": 0.2,
		"blurb": "Believes you. Genuinely. It's almost upsetting.",
	},
	"paranoid": {
		"name": "Paranoid", "observance": 0.75, "skepticism": 0.9, "trust": 0.25,
		"talkativeness": 0.6, "escalation": 0.75, "impatience": 1.3, "vital_bias": -0.3,
		"blurb": "Has already written down your name. Twice.",
	},
	"hypochondriac": {
		"name": "Hypochondriac", "observance": 0.5, "skepticism": 0.35, "trust": 0.6,
		"talkativeness": 0.8, "escalation": 0.3, "impatience": 0.3, "vital_bias": -0.6,
		"blurb": "Wants to stay. Actively lobbies to stay. Free money.",
	},
	"confrontational": {
		"name": "Confrontational", "observance": 0.55, "skepticism": 0.7, "trust": 0.3,
		"talkativeness": 0.7, "escalation": 0.95, "impatience": 1.5, "vital_bias": 0.1,
		"blurb": "Will escalate. Loudly. In the corridor.",
	},
	"confused": {
		"name": "Confused", "observance": 0.15, "skepticism": 0.2, "trust": 0.6,
		"talkativeness": 0.5, "escalation": 0.15, "impatience": 0.3, "vital_bias": 0.3,
		"blurb": "Not entirely sure this is a hospital.",
	},
	"observant": {
		"name": "Extremely Observant", "observance": 0.95, "skepticism": 0.75, "trust": 0.45,
		"talkativeness": 0.5, "escalation": 0.6, "impatience": 1.0, "vital_bias": -0.1,
		"blurb": "Noticed the dial. Noticed you noticing them notice the dial.",
	},
	"stoic": {
		"name": "Stoic", "observance": 0.4, "skepticism": 0.5, "trust": 0.55,
		"talkativeness": 0.15, "escalation": 0.25, "impatience": 0.5, "vital_bias": 0.7,
		"blurb": "Reports feeling fine. Is not fine. Reports feeling fine.",
	},
	"litigious": {
		"name": "Litigious", "observance": 0.7, "skepticism": 0.8, "trust": 0.3,
		"talkativeness": 0.65, "escalation": 1.0, "impatience": 1.2, "vital_bias": -0.4,
		"blurb": "Knows a guy. The guy is a lawyer. The guy is very available.",
	},
}

const NURSE_ARCHETYPES := {
	"lazy": {
		"name": "Lazy", "observance": 0.2, "skepticism": 0.3, "trust": 0.6,
		"talkativeness": 0.3, "escalation": 0.15, "patrol_speed": 0.7, "idle_bias": 2.0,
		"blurb": "Will not walk to the far end of the ward. Ever.",
	},
	"suspicious": {
		"name": "Suspicious", "observance": 0.85, "skepticism": 0.9, "trust": 0.3,
		"talkativeness": 0.5, "escalation": 0.7, "patrol_speed": 1.1, "idle_bias": 0.4,
		"blurb": "Has a theory about you and is collecting supporting material.",
	},
	"loyal": {
		"name": "Loyal", "observance": 0.6, "skepticism": 0.35, "trust": 0.9,
		"talkativeness": 0.25, "escalation": 0.1, "patrol_speed": 1.0, "idle_bias": 0.8,
		"blurb": "Would cover for you. Would feel bad about it. Would still do it.",
	},
	"gossip": {
		"name": "Gossip", "observance": 0.55, "skepticism": 0.5, "trust": 0.5,
		"talkativeness": 1.0, "escalation": 0.35, "patrol_speed": 1.0, "idle_bias": 1.4,
		"blurb": "The fastest information network in the building.",
	},
	"rule_follower": {
		"name": "Rule Follower", "observance": 0.7, "skepticism": 0.6, "trust": 0.45,
		"talkativeness": 0.4, "escalation": 0.95, "patrol_speed": 1.05, "idle_bias": 0.5,
		"blurb": "Writes it down. Files it. Follows up on it.",
	},
	"corrupt": {
		"name": "Enterprising", "observance": 0.6, "skepticism": 0.4, "trust": 0.55,
		"talkativeness": 0.4, "escalation": 0.05, "patrol_speed": 0.95, "idle_bias": 1.0,
		"blurb": "Saw everything. Has a number in mind.",
	},
	"incompetent": {
		"name": "Incompetent", "observance": 0.3, "skepticism": 0.4, "trust": 0.6,
		"talkativeness": 0.5, "escalation": 0.4, "patrol_speed": 1.2, "idle_bias": 0.9,
		"blurb": "A danger to your plans purely by accident.",
	},
}

const DOCTOR_ARCHETYPES := {
	"competitive": {
		"name": "Competitive", "observance": 0.6, "skepticism": 0.7, "trust": 0.3,
		"talkativeness": 0.6, "escalation": 0.7,
		"blurb": "Wants your numbers to be worse than theirs.",
	},
	"oblivious": {
		"name": "Oblivious", "observance": 0.15, "skepticism": 0.2, "trust": 0.7,
		"talkativeness": 0.4, "escalation": 0.1,
		"blurb": "Has not noticed the ward in some time.",
	},
	"ethical": {
		"name": "Ethical", "observance": 0.7, "skepticism": 0.75, "trust": 0.5,
		"talkativeness": 0.45, "escalation": 0.9,
		"blurb": "Genuinely good. Enormously inconvenient.",
	},
	"corrupt_doc": {
		"name": "Likeminded", "observance": 0.65, "skepticism": 0.3, "trust": 0.6,
		"talkativeness": 0.3, "escalation": 0.05,
		"blurb": "Running the same play on the other ward.",
	},
	"arrogant": {
		"name": "Arrogant", "observance": 0.35, "skepticism": 0.55, "trust": 0.35,
		"talkativeness": 0.55, "escalation": 0.5,
		"blurb": "Too important to look at a chart, thankfully.",
	},
	"investigator": {
		"name": "Investigator-Type", "observance": 0.9, "skepticism": 0.95, "trust": 0.25,
		"talkativeness": 0.3, "escalation": 1.0,
		"blurb": "Reads records for fun. On weekends.",
	},
}

const FAMILY_ARCHETYPES := {
	"absent": {
		"name": "Rarely Visits", "observance": 0.3, "skepticism": 0.4, "trust": 0.6,
		"talkativeness": 0.3, "escalation": 0.3, "visit_rate": 0.15,
		"blurb": "Will call. Once. From a car.",
	},
	"constant": {
		"name": "Constantly Visits", "observance": 0.65, "skepticism": 0.6, "trust": 0.45,
		"talkativeness": 0.7, "escalation": 0.6, "visit_rate": 0.9,
		"blurb": "Has a favourite chair here now.",
	},
	"questioner": {
		"name": "Asks Lots Of Questions", "observance": 0.7, "skepticism": 0.7, "trust": 0.4,
		"talkativeness": 0.8, "escalation": 0.5, "visit_rate": 0.6,
		"blurb": "Follow-up questions. Always follow-up questions.",
	},
	"litigious_family": {
		"name": "Threatens Lawsuits", "observance": 0.6, "skepticism": 0.85, "trust": 0.2,
		"talkativeness": 0.6, "escalation": 1.0, "visit_rate": 0.5,
		"blurb": "Opens with the lawsuit. Closes with the lawsuit.",
	},
	"knows_medicine": {
		"name": "Knows Medicine", "observance": 0.9, "skepticism": 0.85, "trust": 0.35,
		"talkativeness": 0.5, "escalation": 0.75, "visit_rate": 0.55,
		"blurb": "Nurse for eleven years. Will spot it in four seconds.",
	},
	"clueless": {
		"name": "Completely Clueless", "observance": 0.1, "skepticism": 0.15, "trust": 0.8,
		"talkativeness": 0.6, "escalation": 0.2, "visit_rate": 0.5,
		"blurb": "Thinks the Vibe Stabiliser is a vending machine.",
	},
}

const TRAIT_DEFAULTS := {
	"observance": 0.5, "skepticism": 0.5, "trust": 0.5, "talkativeness": 0.4,
	"escalation": 0.4, "impatience": 1.0, "vital_bias": 0.0, "patrol_speed": 1.0,
	"idle_bias": 1.0, "visit_rate": 0.5,
}

# =============================================================== NAMES
const FIRST_NAMES := [
	"Greg", "Marlene", "Dougie", "Priya", "Constance", "Bev", "Yusuf", "Tam",
	"Delia", "Roland", "Fenwick", "Moira", "Cliff", "Ines", "Bartholomew",
	"Sandra", "Ogden", "Lurleen", "Vikram", "Trish", "Maurice", "Camille",
	"Herb", "Nadia", "Pontus", "Glenda", "Wes", "Oksana", "Rudy", "Bernadette",
	"Chip", "Femi", "Rosalind", "Duncan", "Marguerite", "Kip", "Astrid", "Lyle",
]
const LAST_NAMES := [
	"Pumbleton", "Vasquez", "Nokes", "Achterberg", "Dill", "Crumb", "Okafor",
	"Feathers", "Stankiewicz", "Bright", "Muldoon", "Han", "Pratchett-Adjacent",
	"Wollop", "Bream", "Oyelaran", "Gundersen", "Spleen", "Marchetti", "Blunt",
	"Kowalczyk", "Tremble", "Dupree", "Nkemdirim", "Fossey", "Ratchet", "Vane",
	"Pillsbury-Ng", "Ostrowski", "Bracket", "Quill", "Mbeki", "Sunderland",
]
const STAFF_FIRST := [
	"Sarah", "Deepa", "Marcus", "Nell", "Terrance", "Yolanda", "Joon", "Bridget",
	"Ola", "Craig", "Simone", "Hank", "Amara", "Vince", "Petra", "Desmond",
]

# =============================================================== HELPERS
func condition_name(id: String) -> String:
	return String(CONDITIONS.get(id, {}).get("name", id))

func condition(id: String) -> Dictionary:
	return CONDITIONS.get(id, {})

## The by-the-book dial setting for a condition.
##
## It lived inside TreatmentMachine.set_prescribed_for() as an expression, which
## meant the number existed only on the machine — so the chart could not print
## it, and the tutorial's line "the chart states the prescribed setting" was
## simply untrue. Deviating from prescription is the central act of the game;
## the player has to be able to look the number up somewhere other than by
## walking to the machine.
func prescribed_setting(cond_id: String) -> int:
	return 3 + (hash(cond_id) % 5)

func treatment_name(id: String) -> String:
	return String(TREATMENTS.get(id, {}).get("name", id))

func treatment(id: String) -> Dictionary:
	return TREATMENTS.get(id, {})

func complication_name(id: String) -> String:
	return String(COMPLICATIONS.get(id, {}).get("name", id))

func cause_name(id: String) -> String:
	if id == "":
		return "no stated cause"
	return String(CAUSES.get(id, id))

func insurance_multiplier(id: String) -> float:
	return float(INSURANCE.get(id, {}).get("mult", 1.0))

func insurance_name(id: String) -> String:
	return String(INSURANCE.get(id, {}).get("name", id))

func insurance_scrutiny(id: String) -> float:
	return float(INSURANCE.get(id, {}).get("scrutiny", 0.5))

## Look a trait up across every archetype table, so callers never need to know
## which role a given archetype belongs to.
func archetype_data(arch: String) -> Dictionary:
	for tbl in [PATIENT_ARCHETYPES, NURSE_ARCHETYPES, DOCTOR_ARCHETYPES, FAMILY_ARCHETYPES]:
		if tbl.has(arch):
			return tbl[arch]
	return {}

func trait_of(arch: String, key: String, fallback: float = -9999.0) -> float:
	var d := archetype_data(arch)
	if d.has(key):
		return float(d[key])
	if fallback != -9999.0:
		return fallback
	return float(TRAIT_DEFAULTS.get(key, 0.5))

func archetype_name(arch: String) -> String:
	return String(archetype_data(arch).get("name", arch.capitalize()))

func archetype_blurb(arch: String) -> String:
	return String(archetype_data(arch).get("blurb", ""))

## Build a Mind pre-configured from an archetype.
func make_mind(id: String, display: String, role: String, arch: String) -> Mind:
	var m := Mind.new(id, display, role)
	m.archetype = arch
	m.observance = trait_of(arch, "observance")
	m.skepticism = trait_of(arch, "skepticism")
	m.trust = trait_of(arch, "trust")
	m.talkativeness = trait_of(arch, "talkativeness")
	m.escalation = trait_of(arch, "escalation")
	return m

## Which treatments are correct for a condition.
func correct_treatments(cond_id: String) -> Array:
	return Array(CONDITIONS.get(cond_id, {}).get("treats", []))

func is_correct_treatment(cond_id: String, tid: String) -> bool:
	return correct_treatments(cond_id).has(tid)
