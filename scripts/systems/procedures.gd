class_name Procedures
extends RefCounted
## What actually happens when you treat somebody, per KIND of ailment.
##
## The first playtest verdict was "it's confusing to know what to do with the
## patients, I'm just tuning up their prescriptions and that's it" — which was
## exactly right. Every one of forty conditions was the same verb: turn a dial,
## read a toast. One interaction, no skill, and the choice to do harm was a
## number being slightly different rather than an act.
##
## Each condition now names a PROCEDURE, and each procedure is a different thing
## to do with your hands, with its own honest option and its own dishonest one.
## The dishonest option is never a button labelled "do the bad thing": it is the
## same interaction, performed differently, and usually performed BETTER — it
## takes more skill to injure somebody plausibly than to help them.
##
## The tradeoff is the same shape everywhere, because it is the game's thesis:
##   treat them well   -> a fee now, they go home, the bed frees up
##   treat them badly  -> the bed keeps paying, and somebody might sue you

## Zones on the bone-setting bar, outermost first. `stay` is days added.
const BONE_ZONES := {
	"clean": {
		"label": "Clean reduction",
		"recovery": 0.85, "stay": -1.0, "fee": 1400, "visual": 0.0,
		"harm": "", "sue": 0.0,
		"say": ["Oh — oh, that's better.", "That's it. That's the one.",
			"I felt that go back in."],
	},
	"rough": {
		"label": "Reduced, roughly",
		"recovery": 0.35, "stay": 0.0, "fee": 700, "visual": 0.05,
		"harm": "", "sue": 0.02,
		"say": ["Hnngh. Right. Fine.", "Is that meant to grind?",
			"You could have warned me."],
	},
	"worse": {
		"label": "Displaced further",
		"recovery": -0.25, "stay": 2.0, "fee": 300, "visual": 0.55,
		"harm": "post_percussive_ringing", "sue": 0.22,
		"say": ["THAT IS THE WRONG WAY.", "No no no no —",
			"Something just moved that shouldn't."],
	},
}

## Where each zone sits on a 0..1 bar. The clean window is narrow and central;
## the ruinous ones are wide and at the ends — which means doing harm is EASIER
## than doing good, and doing harm on purpose is a thing you have to aim for.
const BONE_BAR := [
	{"zone": "worse", "from": 0.00, "to": 0.17},
	{"zone": "rough", "from": 0.17, "to": 0.42},
	{"zone": "clean", "from": 0.42, "to": 0.58},
	{"zone": "rough", "from": 0.58, "to": 0.83},
	{"zone": "worse", "from": 0.83, "to": 1.00},
]

static func zone_at(x: float) -> String:
	for band in BONE_BAR:
		if x >= float(band["from"]) and x < float(band["to"]):
			return String(band["zone"])
	return "worse"

# ------------------------------------------------------------------ medicines
## Prescribing is a different kind of decision: not skill, KNOWLEDGE. The right
## drug is written on the chart — if you have read it. Guessing is playable and
## occasionally ruinous, which is the entire joke.
##
## `effect`:
##   cure    - works. They improve and go home.
##   inert   - does nothing at all. No harm done, and they are still here
##             tomorrow, still billing. The most profitable honest-looking act
##             in the game.
##   adverse - actively wrong for this condition.
const MEDICINES := {
	"chalkinol": {"name": "Chalkinol", "blurb": "Chalky. Reliable. Tastes of school."},
	"placebex": {"name": "Placebex", "blurb": "Sugar, mostly. Licensed anyway."},
	"vibrizone": {"name": "Vibrizone", "blurb": "For anything that hums."},
	"lactaway": {"name": "Lactaway", "blurb": "Settles a hostile dairy response."},
	"beigeolol": {"name": "Beigeolol", "blurb": "Restores colour. Slowly."},
	"mondazepam": {"name": "Mondazepam", "blurb": "For residual weekdays."},
	"sneezantol": {"name": "Sneezantol", "blurb": "Interrupts a recursive sneeze."},
	"yawnase": {"name": "Yawnase", "blurb": "Completes an unfinished yawn."},
	"grievadone": {"name": "Grievadone", "blurb": "Takes the edge off a grievance."},
	"pneumoclear": {"name": "Pneumoclear", "blurb": "Clears clerical lung."},
}

## condition -> the one that cures it. Everything else is inert, except the
## explicit clashes below.
const CURES := {
	"chronic_beige": "beigeolol",
	"lactose_hostility": "lactaway",
	"reverse_shivers": "vibrizone",
	"recursive_sneeze": "sneezantol",
	"clerical_lung": "pneumoclear",
	"residual_monday": "mondazepam",
	"premonitory_hangover": "mondazepam",
	"acute_deflation": "vibrizone",
	"ambient_grievance": "grievadone",
	"perforated_patience": "grievadone",
	"borrowed_ache": "chalkinol",
	"unfinished_yawn": "yawnase",
	"spontaneous_tuesday": "mondazepam",
	"catastrophic_yawn": "yawnase",
}

## Pairs that do something worse than nothing. Deliberately few: the common bad
## outcome should be "you gave them a sugar pill and kept the bed", not poison.
const CLASHES := {
	"lactose_hostility": ["chalkinol"],
	"clerical_lung": ["yawnase"],
	"recursive_sneeze": ["vibrizone"],
	"acute_deflation": ["sneezantol"],
}

static func medicine_effect(condition_id: String, med_id: String) -> String:
	if String(CURES.get(condition_id, "")) == med_id:
		return "cure"
	var clash: Array = CLASHES.get(condition_id, [])
	if clash.has(med_id):
		return "adverse"
	return "inert"

## The four or five options a prescription screen offers: the cure, any clash,
## and enough plausible others to make reading the chart worth doing.
static func options_for(condition_id: String) -> Array[String]:
	var out: Array[String] = []
	var cure := String(CURES.get(condition_id, "placebex"))
	out.append(cure)
	for c in CLASHES.get(condition_id, []):
		out.append(String(c))
	if not out.has("placebex"):
		out.append("placebex")
	for id in MEDICINES:
		if out.size() >= 5:
			break
		if not out.has(id):
			out.append(id)
	out.sort()
	return out

static func procedure_for(condition_id: String) -> String:
	return String(DB.condition(condition_id).get("procedure", "dial"))

static func procedure_name(kind: String) -> String:
	match kind:
		"set_bone": return "Set the bone"
		"prescribe": return "Prescribe something"
		"suture": return "Close it up"
	return "Run a cycle"
