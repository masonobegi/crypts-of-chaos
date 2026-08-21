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
## Each condition now names a PROCEDURE, and each procedure is a different job
## for your hands, performed on a drawing of the actual part of the actual
## person — a forearm with a bone in it, a laceration with lips that pull
## together, a syringe with graduations on the barrel.
##
## THE SHAPE OF EVERY PROCEDURE
##
##   1. You say what you are about to do. Treat them, or make it worse.
##   2. You do it, on the body part, with your hands.
##   3. You are graded on how WELL you did the thing you said you would do.
##
## That third step is the design. Both intents are skills. Doing either one
## well is rewarded and doing either one badly is punished, so there is no
## "safe" option to fall back on and no free crime:
##
##   treat, done well   -> they improve, they go home, you bill the procedure
##   treat, done badly  -> malpractice, plainly, in front of witnesses
##   worsen, done well  -> the bed keeps paying and it looks like bad luck
##   worsen, done badly -> everyone in the room watched you do it
##
## Intending harm and fumbling it is the worst square on the board, which is
## the correct amount of respect to have for the crime.

# ------------------------------------------------------------------ intents
## What you tell the game you are about to do, before you do it. Phrased
## plainly: this is the one place the player is allowed to be honest, because
## it is the only place nobody else can hear them.
const INTENTS := {
	"treat": {
		"label": "Treat them properly",
		"tone": "good",
		"verb": "treatment",
	},
	"worsen": {
		"label": "Make it worse",
		"tone": "bad",
		"verb": "manipulation",
	},
}

## Grade bands. Deliberately generous in the middle: most attempts land in
## `fair`, which is neither a payday nor a disaster, and the whole game is
## trying to get out of it in one direction or the other.
const BAND_GOOD := 0.74
const BAND_FAIR := 0.38

static func grade_band(grade: float) -> String:
	if grade >= BAND_GOOD:
		return "good"
	if grade >= BAND_FAIR:
		return "fair"
	return "poor"

## kind -> intent -> band -> outcome.
##
## Fields: `recovery` added to truth, `stay` days added to the bed, `fee`
## billed, `visual` how obvious it looked to anybody in the doorway, `harm` a
## complication id, `sue` added lawsuit risk, `say` what the patient thinks of
## it, `tone` the colour of the toast.
const OUTCOMES := {
	"set_bone": {
		"treat": {
			"good": {
				"label": "Clean reduction", "recovery": 0.85, "stay": -1.0,
				"fee": 1600, "visual": 0.0, "harm": "", "sue": 0.0, "tone": "good",
				"say": ["Oh — oh, that's better.", "That's it. That's the one.",
					"I felt that go back in."],
			},
			"fair": {
				"label": "Reduced, roughly", "recovery": 0.32, "stay": 0.0,
				"fee": 800, "visual": 0.04, "harm": "", "sue": 0.02, "tone": "info",
				"say": ["Hnngh. Right. Fine.", "Is that meant to grind?",
					"You could have warned me."],
			},
			"poor": {
				"label": "Reduction failed", "recovery": -0.18, "stay": 1.5,
				"fee": 300, "visual": 0.52, "harm": "post_percussive_ringing",
				"sue": 0.30, "tone": "suspicion",
				"say": ["You have made that WORSE.", "Stop — stop, stop —",
					"Do you know what you're doing?"],
			},
		},
		"worsen": {
			"good": {
				"label": "Displaced — and it looks spontaneous", "recovery": -0.28,
				"stay": 3.0, "fee": 1500, "visual": 0.04,
				"harm": "post_percussive_ringing", "sue": 0.04, "tone": "info",
				"say": ["It just went. On its own.", "Did you hear that? That was IT.",
					"That wasn't you, was it? That was it."],
			},
			"fair": {
				"label": "Displaced, awkwardly", "recovery": -0.16, "stay": 1.5,
				"fee": 900, "visual": 0.30, "harm": "post_percussive_ringing",
				"sue": 0.18, "tone": "suspicion",
				"say": ["That felt like you.", "Hang on. Hang on.",
					"Was that supposed to happen?"],
			},
			"poor": {
				"label": "Everybody saw that", "recovery": -0.32, "stay": 2.0,
				"fee": 400, "visual": 0.80, "harm": "post_percussive_ringing",
				"sue": 0.48, "tone": "suspicion",
				"say": ["YOU DID THAT.", "He did that. He did that on purpose.",
					"I want somebody else. Now."],
			},
		},
	},
	"suture": {
		"treat": {
			"good": {
				"label": "Closed neatly", "recovery": 0.80, "stay": -0.5,
				"fee": 1200, "visual": 0.0, "harm": "", "sue": 0.0, "tone": "good",
				"say": ["Barely felt it.", "You've done that before.",
					"Oh, that's tidy."],
			},
			"fair": {
				"label": "Closed, raggedly", "recovery": 0.28, "stay": 0.5,
				"fee": 620, "visual": 0.04, "harm": "", "sue": 0.03, "tone": "info",
				"say": ["Is it meant to pucker?", "Hm. It'll do.",
					"That one stung."],
			},
			"poor": {
				"label": "Won't hold", "recovery": -0.14, "stay": 2.0,
				"fee": 300, "visual": 0.48, "harm": "wound_dehiscence", "sue": 0.26,
				"tone": "suspicion",
				"say": ["That's pulling. That is PULLING.",
					"It's opening. It's opening again.",
					"You've sewn it wrong, haven't you."],
			},
		},
		"worsen": {
			"good": {
				"label": "Closed loose — it will open on its own", "recovery": -0.22,
				"stay": 2.5, "fee": 1150, "visual": 0.03, "harm": "wound_dehiscence",
				"sue": 0.05, "tone": "info",
				"say": ["Feels fine, actually.", "That was quick.",
					"Thank you, doctor. Honestly."],
			},
			"fair": {
				"label": "Loose, and obviously so", "recovery": -0.12, "stay": 1.5,
				"fee": 700, "visual": 0.28, "harm": "wound_dehiscence", "sue": 0.16,
				"tone": "suspicion",
				"say": ["That's not tight.", "Are they meant to be that far apart?",
					"Hm. Hm."],
			},
			"poor": {
				"label": "Sewn shut at random", "recovery": -0.30, "stay": 2.0,
				"fee": 350, "visual": 0.76, "harm": "wound_dehiscence", "sue": 0.44,
				"tone": "suspicion",
				"say": ["What are you DOING?", "Get off. Get OFF.",
					"Somebody get somebody else."],
			},
		},
	},
	"manipulate": {
		"treat": {
			"good": {
				"label": "Reduced under control", "recovery": 0.82, "stay": -1.0,
				"fee": 1500, "visual": 0.0, "harm": "", "sue": 0.0, "tone": "good",
				"say": ["Oh — oh that's IT.", "It went back. I felt it go back.",
					"That's the first time it's been right in a week."],
			},
			"fair": {
				"label": "Reduced, eventually", "recovery": 0.30, "stay": 0.0,
				"fee": 760, "visual": 0.05, "harm": "", "sue": 0.03, "tone": "info",
				"say": ["Is it meant to take that long?", "Hnn. Hnnnn. Right.",
					"You could have warned me it'd click."],
			},
			"poor": {
				"label": "Forced through the arc", "recovery": -0.20, "stay": 1.5,
				"fee": 320, "visual": 0.54, "harm": "post_percussive_ringing",
				"sue": 0.32, "tone": "suspicion",
				"say": ["STOP. STOP.", "That is not the way it bends.",
					"Get off me. Get OFF."],
			},
		},
		"worsen": {
			"good": {
				"label": "Taken the wrong way, smoothly", "recovery": -0.26,
				"stay": 2.5, "fee": 1400, "visual": 0.04,
				"harm": "post_percussive_ringing", "sue": 0.05, "tone": "info",
				"say": ["It gave. It just gave.", "That's how it went the first time.",
					"Is that supposed to happen twice?"],
			},
			"fair": {
				"label": "Taken the wrong way, roughly", "recovery": -0.15,
				"stay": 1.5, "fee": 820, "visual": 0.30,
				"harm": "post_percussive_ringing", "sue": 0.18, "tone": "suspicion",
				"say": ["Hang on — which way are you going?",
					"That's not the direction.", "Ow. OW."],
			},
			"poor": {
				"label": "Wrenched, in front of everyone", "recovery": -0.32,
				"stay": 2.0, "fee": 360, "visual": 0.78,
				"harm": "post_percussive_ringing", "sue": 0.46, "tone": "suspicion",
				"say": ["HE WRENCHED IT.", "You did that on purpose.",
					"Somebody get a nurse. Get anybody."],
			},
		},
	},
	"dose": {
		"treat": {
			"good": {
				"label": "Dosed to the line", "recovery": 0.72, "stay": -0.5,
				"fee": 520, "visual": 0.0, "harm": "", "sue": 0.0, "tone": "good",
				"say": ["Oh, that's better already.", "Mm. Yes. That's the stuff.",
					"That went in nicely."],
			},
			"fair": {
				"label": "Given, approximately", "recovery": 0.16, "stay": 1.0,
				"fee": 300, "visual": 0.0, "harm": "", "sue": 0.01, "tone": "info",
				"say": ["Is it meant to taste of nothing?", "I'll give it a go.",
					"How long does it take to work?"],
			},
			"poor": {
				"label": "That was the wrong thing, wrongly", "recovery": -0.24,
				"stay": 1.5, "fee": 200, "visual": 0.42, "harm": "rebound_hiccups",
				"sue": 0.24, "tone": "suspicion",
				"say": ["That is NOT sitting right.", "Oh. Oh dear.",
					"Why is it fizzing?"],
			},
		},
		"worsen": {
			"good": {
				"label": "An unfortunate reaction", "recovery": -0.26, "stay": 2.5,
				"fee": 640, "visual": 0.03, "harm": "rebound_hiccups", "sue": 0.05,
				"tone": "info",
				"say": ["I've never reacted to anything before.",
					"Is that normal? That's not normal.",
					"It's not you. I have a funny system."],
			},
			"fair": {
				"label": "A reaction, and a raised eyebrow", "recovery": -0.14,
				"stay": 1.5, "fee": 380, "visual": 0.26, "harm": "rebound_hiccups",
				"sue": 0.15, "tone": "suspicion",
				"say": ["What was in that?", "Can I see the box?",
					"That's a lot, isn't it?"],
			},
			"poor": {
				"label": "Emptied into them in full view", "recovery": -0.34,
				"stay": 2.0, "fee": 220, "visual": 0.78, "harm": "rebound_hiccups",
				"sue": 0.46, "tone": "suspicion",
				"say": ["That was the whole thing!", "He gave me the WHOLE thing.",
					"Somebody write that down."],
			},
		},
	},
}

static func outcome(kind: String, intent: String, grade: float) -> Dictionary:
	var by_intent: Dictionary = OUTCOMES.get(kind, OUTCOMES["set_bone"])
	var by_band: Dictionary = by_intent.get(intent, by_intent["treat"])
	var band := grade_band(grade)
	var spec: Dictionary = by_band[band].duplicate(true)
	spec["band"] = band
	spec["intent"] = intent
	spec["kind"] = kind
	spec["grade"] = grade
	return spec

## What the player is told about the grade itself, separately from what
## happened to the patient. Reward and punishment both need to be legible or
## the skill is invisible.
static func band_note(intent: String, band: String) -> String:
	match band:
		"good":
			return "Textbook." if intent == "treat" else "Nobody could tell that was you."
		"fair":
			return "Adequate." if intent == "treat" else "It'll pass. Probably."
	return "That was a mess." if intent == "treat" else "That was not subtle."

# ------------------------------------------------------------------ anatomy
## Which bit of which person a procedure happens to. Conditions that name a
## body part use it; the invented ones get one assigned here, because a
## fracture has to be a fracture OF something before you can draw it.
const SITES := {
	"acute_shatter": "forearm",
	"ghost_fracture": "forearm",
	"latent_geometry": "forearm",
	"percussive_collapse": "ribs",
	"opaque_torso": "ribs",
	"percussive_sinus": "brow",
	"acute_moustache_strain": "brow",
	"escalating_posture": "flank",
	"argumentative_reflex": "forearm",
	"knuckle_weather": "hand",
	"calcified_grudge": "flank",
}

## Which drawing gets used. The condition names a body part where it has one,
## the table above covers the invented ones, and anything unaccounted for is an
## arm — every rig in Anatomy is a real drawing, so there is no fallback that
## looks like a placeholder.
static func site_for(condition_id: String) -> String:
	var part := String(DB.body_part(condition_id))
	if Anatomy.PART_NAMES.has(part):
		return part
	part = String(SITES.get(condition_id, ""))
	if Anatomy.PART_NAMES.has(part):
		return part
	return "forearm"

static func site_name(condition_id: String) -> String:
	return Anatomy.part_name(site_for(condition_id))

# ------------------------------------------------------------------ bone work
## How far out of line the bone starts, and what counts as "in line" at the
## end. The dishonest target is a real angle you have to hit rather than the
## absence of one, so that making somebody worse on purpose is a manoeuvre.
const BONE_MAX_ANGLE := 0.62      # radians the distal fragment can swing
const BONE_MAX_GAP := 26.0        # pixels of traction, either way
const BONE_TREAT_TARGET := {"angle": 0.0, "gap": 0.0, "tol_angle": 0.085, "tol_gap": 4.6}
const BONE_WORSEN_TARGET := {"angle": 0.40, "gap": 15.0, "tol_angle": 0.075, "tol_gap": 4.2}
const BONE_HOLD_SECONDS := 1.15   # how long it has to stay there
const BONE_SECONDS := 14.0        # before the anaesthetic gives up

static func bone_target(intent: String) -> Dictionary:
	return BONE_WORSEN_TARGET if intent == "worsen" else BONE_TREAT_TARGET

## 1.0 dead on, 0.0 nowhere near. Both axes matter; the worse of the two wins,
## so you cannot buy a good grade on angle alone.
static func bone_closeness(intent: String, angle: float, gap: float) -> float:
	var t := bone_target(intent)
	var da: float = absf(angle - float(t["angle"])) / (float(t["tol_angle"]) * 3.0)
	var dg: float = absf(gap - float(t["gap"])) / (float(t["tol_gap"]) * 3.0)
	return clampf(1.0 - maxf(da, dg), 0.0, 1.0)

static func bone_in_tolerance(intent: String, angle: float, gap: float) -> bool:
	var t := bone_target(intent)
	return absf(angle - float(t["angle"])) <= float(t["tol_angle"]) \
		and absf(gap - float(t["gap"])) <= float(t["tol_gap"])

# ------------------------------------------------------------------ manipulation
## Taking a joint through an arc.
##
## The third distinct verb, and deliberately a TRACKING skill rather than a
## holding one or a clicking one: a guide travels along the path the joint has
## to follow and your job is to stay on it. That is what a reduction of a
## dislocated shoulder actually is — not force, but taking the limb round a
## particular curve at a particular speed — and it is the one manoeuvre in the
## game where being too fast and being too slow are both wrong.
const MANIP_SECONDS := 7.0
const MANIP_TOL := 0.17           ## radians either side of the guide
const MANIP_START := 0.62         ## how far out the joint sits to begin with

## The path, as a list of angles the guide passes through. Treating them takes
## the joint back the way it came; making it worse takes it the other way,
## round the outside, along a curve a shoulder could plausibly have taken in a
## fall — longer, and therefore harder to stay on.
static func manip_path(intent: String) -> Array:
	var out: Array = []
	var steps := 48
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		if intent == "worsen":
			# Out, over the top, and down the far side.
			out.append(MANIP_START + sin(t * PI) * 0.75 - t * 1.34)
		else:
			# Back to neutral on an ease-out, which is how a joint goes in.
			out.append(MANIP_START * (1.0 - t * t * (3.0 - 2.0 * t)))
	return out

static func manip_angle_at(intent: String, t: float) -> float:
	var path := manip_path(intent)
	var idx: int = clampi(int(round(clampf(t, 0.0, 1.0) * float(path.size() - 1))),
		0, path.size() - 1)
	return float(path[idx])

## 1.0 dead on the guide, 0.0 a full tolerance-and-a-half away.
static func manip_closeness(err: float) -> float:
	return clampf(1.0 - absf(err) / (MANIP_TOL * 2.4), 0.0, 1.0)

## Time on the guide is what is graded, and letting go stops your hand rather
## than the arc — so a player who panics and releases watches the joint go on
## without them.
static func manip_grade(quality_time: float, total_time: float) -> float:
	if total_time <= 0.0:
		return 0.0
	return clampf(quality_time / total_time, 0.0, 1.0)

# ------------------------------------------------------------------ suturing
const SUTURE_POINTS := 6
const SUTURE_SECONDS := 16.0
const SUTURE_RADIUS := 34.0       # how far off a stitch can land and still take
## How far to the side of the wound the loose bites sit, as a fraction of the
## wound's own half-width. Wide enough to be a different manoeuvre, close
## enough that it reads on the drawing as a stitch rather than a stab.
const SUTURE_LOOSE_OFFSET := 0.62

## Accuracy of one stitch: 1.0 through the mark, 0.0 at the edge of taking.
static func suture_score(distance: float) -> float:
	return clampf(1.0 - distance / SUTURE_RADIUS, 0.0, 1.0)

## Misses cost, or the optimal play is to spray clicks at the wound.
static func suture_grade(scores: Array, misses: int) -> float:
	if scores.is_empty():
		return 0.0
	var total := 0.0
	for s in scores:
		total += float(s)
	var mean: float = total / float(SUTURE_POINTS)
	return clampf(mean - float(misses) * 0.09, 0.0, 1.0)

# ------------------------------------------------------------------ medicines
## Prescribing is a different kind of decision: not skill, KNOWLEDGE — and then
## skill on top of it. The right drug for the condition is written on the chart
## if you have read it; the dose is drawn up by hand against graduations.
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
	"chronic_beige": ["vibrizone"],
	"residual_monday": ["grievadone"],
	"borrowed_ache": ["mondazepam"],
	"unfinished_yawn": ["sneezantol"],
	"premonitory_hangover": ["chalkinol"],
	"ambient_grievance": ["beigeolol"],
	"perforated_patience": ["yawnase"],
	"spontaneous_tuesday": ["pneumoclear"],
	"catastrophic_yawn": ["lactaway"],
	"reverse_shivers": ["pneumoclear"],
}

static func medicine_effect(condition_id: String, med_id: String) -> String:
	if String(CURES.get(condition_id, "")) == med_id:
		return "cure"
	var clash: Array = CLASHES.get(condition_id, [])
	if clash.has(med_id):
		return "adverse"
	return "inert"

## How much of your dosing skill survives your choice of bottle. Picking the
## wrong one for what you said you were doing drags the whole attempt down into
## the punished band however steady your hands were — which is the knowledge
## check doing its job.
const DRUG_FACTOR := {
	"treat": {"cure": 1.0, "inert": 0.46, "adverse": 0.10},
	"worsen": {"adverse": 1.0, "inert": 0.50, "cure": 0.10},
}

static func dose_grade(intent: String, effect: String, precision: float) -> float:
	var factors: Dictionary = DRUG_FACTOR.get(intent, DRUG_FACTOR["treat"])
	return clampf(precision * float(factors.get(effect, 0.3)), 0.0, 1.0)

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

## Where the prescribed line sits on the barrel, and where the line you want
## sits if you are not prescribing in good faith. Both are printed on the
## syringe; only one of them is printed in ink.
const DOSE_TREAT_TARGET := 0.42
const DOSE_WORSEN_TARGET := 0.88
const DOSE_TOLERANCE := 0.075

static func dose_target(intent: String) -> float:
	return DOSE_WORSEN_TARGET if intent == "worsen" else DOSE_TREAT_TARGET

static func dose_precision(intent: String, level: float) -> float:
	return clampf(1.0 - absf(level - dose_target(intent)) / (DOSE_TOLERANCE * 3.0), 0.0, 1.0)

static func procedure_for(condition_id: String) -> String:
	return String(DB.condition(condition_id).get("procedure", "dial"))

static func procedure_name(kind: String) -> String:
	match kind:
		"set_bone": return "Set the bone"
		"prescribe": return "Prescribe something"
		"suture": return "Close it up"
		"manipulate": return "Take it through the arc"
	return "Run a cycle"

## Which screen does which job.
static func screen_for(kind: String) -> String:
	match kind:
		"set_bone": return "setbone"
		"prescribe": return "medicate"
		"suture": return "suture"
		"manipulate": return "manipulate"
	return ""
