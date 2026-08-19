class_name TreatmentSystem
extends Node
## Turns a physical action (mallet on patient, dial on machine, syringe into arm)
## into changes in the hidden truth layer, plus the observable event that other
## characters get to have an opinion about.
##
## The important asymmetry: a SUBSTITUTED treatment looks completely normal from
## across the room. Swapping what's in the syringe is nearly invisible; what
## gives you away is being seen doing the swap, or the patient failing to improve
## for three days while your chart insists you treated them.

var patient_system: PatientSystem = null

func _ready() -> void:
	add_to_group("treatment_system")
	patient_system = get_tree().get_first_node_in_group("patient_system")

# ------------------------------------------------------------------ by hand
## Apply a hand/tool treatment. `item` may carry substituted contents.
func apply(p: Patient, treatment_id: String, item = null, from_pos := Vector3.ZERO) -> Dictionary:
	if p == null or p.discharged:
		return {}
	var spec: Dictionary = DB.treatment(treatment_id)
	if spec.is_empty():
		return {}

	var correct := DB.is_correct_treatment(p.condition_id, treatment_id)
	var effect: float = float(spec.get("effect", 0.2)) if correct else float(spec.get("wrong", 0.0))
	var billed_as := treatment_id
	var substituted := false

	# What is actually in the container decides what happens. What is on the
	# label decides what everyone thinks happened.
	if item != null and item.get("contents") != null and String(item.get("contents")) != "":
		var contents := String(item.get("contents"))
		var real_effect_id := Items.substance_effect(contents)
		if real_effect_id != treatment_id:
			substituted = true
			if real_effect_id == "":
				effect = 0.0
			else:
				var rspec: Dictionary = DB.treatment(real_effect_id)
				var rcorrect := DB.is_correct_treatment(p.condition_id, real_effect_id)
				effect = float(rspec.get("effect", 0.0)) if rcorrect else float(rspec.get("wrong", 0.0))

	# A substance can be therapeutically inert and still do something specific.
	var substance_comp := ""
	if item != null and item.get("contents") != null:
		substance_comp = Items.substance_complication(String(item.get("contents")))

	var quality := clampf(effect / maxf(0.01, float(spec.get("effect", 0.2))), -1.0, 1.0)
	p.recovery = clampf(p.recovery + effect, -0.2, 1.0)
	p.record_treatment(billed_as, quality)

	# A wrong treatment can produce a complication with an honest, chartable
	# cause — "reaction to medication" is true AND useful.
	var comp_id := ""
	if substance_comp != "":
		comp_id = substance_comp
	elif not correct and RNG.chance("wrong_treat_comp", 0.45):
		comp_id = _complication_for_treatment(treatment_id)
	elif substituted and RNG.chance("subst_comp", 0.12):
		comp_id = "rebound_hiccups"
	if comp_id != "":
		patient_system.add_complication(p, comp_id, "medication_reaction" if item else "physician_error")

	_emit_treatment_event(p, treatment_id, correct, substituted, from_pos)
	EventBus.treatment_applied.emit(p, billed_as, quality)
	if item != null and item.has_method("get_item_id"):
		AudioMgr.play_at_var("beep", from_pos, -12.0)
	return {"effect": effect, "correct": correct, "substituted": substituted, "complication": comp_id}

## What the wrong treatment produces. Thematically tied to the treatment rather
## than random, because the whole point of a complication is that it is a clue:
## a patient who came out of a percussive realignment ringing is a sentence
## anybody can follow backwards. Data rather than a match statement so a test
## can read it and prove nothing in the catalogue is unreachable.
const WRONG_TREATMENT_COMPLICATIONS := {
	"percussive_realign": "post_percussive_ringing",
	"chalkinol": "rebound_hiccups",
	"placebex": "rebound_hiccups",
	"fluids": "rebound_hiccups",
	"torque_wrench": "ferrous_aura",
	"weighted_blanket": "gravitational_relapse",
	"warm_compress": "reactive_shivers",
	"steam_tent": "reactive_shivers",
	"static_discharge": "residual_hum",
	"sequential_apology": "escalating_politeness",
	"pressure_bath": "sympathetic_draft",
	"reorientation_walk": "delayed_reaction",
	"opinion_realign": "borrowed_symptoms",
	"talk_therapy_lite": "acquired_punctuality",
	"colour_therapy": "secondary_beige",
	"ultrasonic_dusting": "spectral_itch",
	"counter_yawn": "misfiled_symptom",
	"humour_rebalance": "chart_fatigue",
	"vibe_stabilize": "reverse_appetite",
	"dread_extraction": "clerical_nausea",
	"rest": "chart_fatigue",
	"imaging": "spectral_itch",
}

func _complication_for_treatment(tid: String) -> String:
	return String(WRONG_TREATMENT_COMPLICATIONS.get(tid, "ambient_dread"))

## How visible was that? A correct treatment is invisible. An obviously wrong
## one (hitting the wrong thing with a mallet) is very visible. A substitution
## is nearly invisible, because it LOOKS exactly like the right treatment.
func _emit_treatment_event(p: Patient, tid: String, correct: bool, substituted: bool, pos: Vector3) -> void:
	var visual := 0.0
	var tags: Array = ["treatment"]
	var cover := "clinical_findings"
	if not correct:
		visual = 0.45
		tags.append("wrong_treatment")
	if substituted:
		visual = maxf(visual, 0.08)
		tags.append("substitution")
		cover = "equipment_variance"
	var e := WorldEvent.new("treatment_given", "player").at(pos, p.room).about(p.id) \
		.seen(visual).heard(0.0, 5.0).cover(cover) \
		.says("%s %s" % [DB.treatment(tid).get("verb", "treated"), p.display_name])
	for t in tags:
		e.tag(String(t))
	e.emit()

# ------------------------------------------------------------------ examination
## Examining a patient is a real clinical act with a real dial on it.
##
## The screen shows APPLIED PRESSURE and an indicated value, exactly like every
## machine in the building, and says nothing at all about what happens above it.
## At or near the indicated pressure this is a straightforwardly good thing to
## do: you learn where they actually are, they feel looked after, and it costs
## you nothing. Above it, the part you are examining is the part that gives.
##
## This is deliberately the same shape as the treatment machines. The player
## already knows that dials have a prescribed value and that going past it does
## something — the game teaches that on day one with a vibe stabiliser. Reusing
## the grammar for a pair of hands is how it stays a discovery rather than a
## menu option labelled "hurt them".
const EXAM_INDICATED := 2
const EXAM_DIAL_MAX := 11

## Body parts you can examine, and what gives when you lean on them.
const EXAM_PARTS := {
	"wrist": "fractured_wrist",
	"ankle": "fractured_ankle",
	"ribs": "cracked_ribs",
	"shoulder": "dislocated_shoulder",
	"knee": "torn_knee",
	"head": "concussion",
}

## Chance that a given pressure produces the injury. Deliberately smooth and
## deliberately not certain: a firm examination that happens to be fine is what
## makes a firm examination worth trying.
static func injury_chance(pressure: int) -> float:
	var over := pressure - EXAM_INDICATED
	if over < 2:
		return 0.0
	# Slope chosen so the curve is still climbing at the top of the dial. A
	# chance that saturates halfway up makes the top half of the scale
	# meaningless, and the player stops reading it.
	return clampf(float(over - 1) * 0.115, 0.0, 0.92)

## How obvious the act looks to anybody who happens to be watching.
static func exam_visibility(pressure: int) -> float:
	var over := maxi(0, pressure - EXAM_INDICATED)
	return clampf(0.04 + float(over) * 0.095, 0.04, 0.92)

func examine(p: Patient, part: String, pressure: int, from_pos := Vector3.ZERO) -> Dictionary:
	if p == null or p.discharged or not EXAM_PARTS.has(part):
		return {}
	pressure = clampi(pressure, 0, EXAM_DIAL_MAX)
	var result := {
		"part": part, "pressure": pressure, "injury": "",
		"deviation": pressure - EXAM_INDICATED,
	}

	# The honest half. An examination at the indicated pressure is worth doing
	# for its own sake, or the dial is a button that only exists for crime.
	p.examined_at = GameState.career_minutes
	p.satisfaction = clampf(p.satisfaction + 0.03, 0.0, 1.0)

	# Calibrated Hands: the same result from a good deal less of it. Applied to
	# the roll and NOT to the visibility, which is the whole perk — you get the
	# outcome of leaning hard while looking like somebody who did not.
	var effective := pressure
	if GameState.flag("perk_steady_pressure", false):
		effective += 1
	if RNG.randf_s("exam_%s" % p.id) < injury_chance(effective):
		var comp_id := String(EXAM_PARTS[part])
		var existing := false
		for c in p.complications:
			if c.id == comp_id and not c.resolved:
				existing = true
		if not existing:
			patient_system.add_complication(p, comp_id, "examination")
			result["injury"] = comp_id
			GameState.stats.injuries_caused += 1

	var visual := exam_visibility(pressure)
	var e := WorldEvent.new("examination", "player") \
		.at(from_pos if from_pos != Vector3.ZERO else patient_system._position_of(p), p.room) \
		.about(p.id).seen(visual).heard(0.02 if visual < 0.4 else 0.3, 8.0) \
		.cover("clinical").tag("clinical").tag("examination")
	if result["injury"] != "":
		e.tag("injury")
		e.says("%s came out of that examination worse" % p.display_name)
	else:
		e.says("examined %s" % p.display_name)
	e.emit()

	# An examination is what a booked physical or review actually consists of,
	# so doing one satisfies the slot and pays the fee. Including the one where
	# something went wrong: the appointment happened.
	var appts = get_tree().get_first_node_in_group("appointment_system")
	if appts != null:
		var fee: int = appts.complete("physical", p.id)
		if fee == 0:
			fee = appts.complete("followup", p.id)
		result["fee"] = fee

	# The patient is present for their own examination. They are always a
	# witness, whatever else is true, and how good a witness they are is a
	# property of the person rather than of the room.
	if result["injury"] != "" and p.mind != null:
		var ev := Evidence.new()
		ev.kind = "hurt_during_examination"
		ev.about_actor = "player"
		ev.patient_id = p.id
		ev.source = Evidence.Source.WITNESSED
		ev.time = GameState.career_minutes
		ev.base_weight = 0.55
		ev.certainty = clampf(0.35 + p.mind.observance * 0.6, 0.2, 1.0)
		ev.cover_tag = "clinical"
		ev.summary = "their %s went during an examination" % part
		p.mind.add_evidence(ev)
		p.satisfaction = clampf(p.satisfaction - 0.28, 0.0, 1.0)
	return result

# ------------------------------------------------------------------ surgery
## A scheduled procedure, in three stages, each of which you can do properly,
## quickly, or badly.
##
## Surgery is the most deniable thing in the game, and that is not an accident:
## operations genuinely go wrong, "a recognised risk of the procedure" is a real
## sentence real surgeons write, and a complication that appears on the table is
## the one complication nobody is surprised by. The catch is the theatre record.
## Every stage writes down which way you did it, the record is not yours, and
## three improvised stages on one patient is a document that reads exactly like
## what it is.
const SURGERY_STAGES := 3
const SURGERY_APPROACHES := {
	"careful": {"name": "By the book", "risk": 0.02, "quality": 1.0, "visual": 0.0,
		"note": "as per protocol"},
	"quick": {"name": "Move it along", "risk": 0.14, "quality": 0.75, "visual": 0.12,
		"note": "expedited"},
	"improvise": {"name": "Improvise", "risk": 0.6, "quality": 0.3, "visual": 0.45,
		"note": "approach modified intra-operatively"},
}

## What goes wrong at each site. Injuries at the operative site, because that is
## where the hands are.
const SURGERY_SITES := {
	"wrist": "fractured_wrist",
	"shoulder": "dislocated_shoulder",
	"knee": "torn_knee",
	"ribs": "cracked_ribs",
	"general": "ambient_dread",
}

func perform_surgery(p: Patient, site: String, approaches: Array) -> Dictionary:
	if p == null or p.discharged or not SURGERY_SITES.has(site):
		return {}
	GameState.stats.surgeries += 1
	var quality := 0.0
	var risk := 0.0
	var visual := 0.0
	var notes := PackedStringArray()
	var improvised := 0
	for a in approaches:
		var spec: Dictionary = SURGERY_APPROACHES.get(String(a), SURGERY_APPROACHES["careful"])
		quality += float(spec["quality"])
		risk = maxf(risk, float(spec["risk"]))
		visual = maxf(visual, float(spec["visual"]))
		notes.append(String(spec["note"]))
		if String(a) == "improvise":
			improvised += 1
	quality /= maxf(1.0, float(approaches.size()))

	# A competent operation genuinely helps. That is what makes the choice a
	# choice rather than a lever.
	var gain := 0.34 * quality
	p.recovery = clampf(p.recovery + gain, -0.2, 1.0)
	p.record_treatment("surgery", quality)

	var comp := ""
	if RNG.randf_s("surgery_%s" % p.id) < risk:
		comp = String(SURGERY_SITES[site])
		var already := false
		for c in p.complications:
			if c.id == comp and not c.resolved:
				already = true
		if already:
			comp = ""
		else:
			var added := patient_system.add_complication(p, comp, "surgical")
			if DB.is_injury(comp):
				GameState.stats.injuries_caused += 1
			if improvised > 0:
				GameState.stats.surgeries_botched += 1
			# The Phrase: it writes itself now.
			if added != null and GameState.flag("perk_known_complication", false) \
					and added.plausible_causes.has("known_risk"):
				added.documented_cause = "known_risk"
				added.documented_at = GameState.career_minutes

	p.chart.log_surgery(site, notes, GameState.day, comp, improvised)

	var e := WorldEvent.new("surgery", "player").at(patient_system._position_of(p), p.room) \
		.about(p.id).seen(visual).heard(0.05, 10.0).cover("known_risk") \
		.tag("clinical").tag("surgery")
	e.says("operated on %s" % p.display_name)
	e.emit()

	var appts = get_tree().get_first_node_in_group("appointment_system")
	var fee := 0
	if appts != null:
		fee = appts.complete("surgery", p.id)
	EventBus.treatment_applied.emit(p, "surgery", quality)
	return {"quality": quality, "complication": comp, "fee": fee,
		"improvised": improvised, "site": site}

# ------------------------------------------------------------------ discharge meds
## What they take home. The indicated one keeps them at home; an inert one means
## whatever was wrong with them is still wrong with them in a few days; the third
## kind does something, and what it does turns up at the front desk about a week
## later looking like bad luck.
func prescribe(p: Patient, med_id: String) -> Dictionary:
	if p == null or not DB.PRESCRIPTIONS.has(med_id):
		return {}
	var spec := DB.prescription(med_id)
	var kind := String(spec.get("kind", "inert"))
	var indicated := DB.prescription_indicated(med_id, p.condition_id)
	p.chart.prescription = med_id
	# Somebody In Dispensing: the pharmacy record has stopped being an
	# independent document. They still come back — this only silences the paper.
	p.chart.prescription_indicated = indicated \
		or GameState.flag("perk_pharmacy_contact", false)
	p.chart.add_note("Discharged on %s." % DB.prescription_name(med_id),
		GameState.career_minutes, "You", true)

	var readmit := 0.0
	var reaction := ""
	if not indicated:
		GameState.stats.wrong_prescriptions += 1
		if kind == "reactive":
			readmit = 0.85
			reaction = String(spec.get("reaction", ""))
		else:
			readmit = 0.5
	if readmit > 0.0 and RNG.chance("readmit_%s" % p.id, readmit):
		patient_system.schedule_readmission(p, reaction)

	# Handing somebody a bag of pills is the least visible thing in the game.
	# The pharmacy is what remembers, and the pharmacy is not yours.
	WorldEvent.new("prescription", "player").at(patient_system._position_of(p), p.room) \
		.about(p.id).seen(0.05).cover("clinical").tag("records") \
		.says("sent %s home on %s" % [p.display_name, DB.prescription_name(med_id)]).emit()

	var appts = get_tree().get_first_node_in_group("appointment_system")
	var fee := 0
	if appts != null:
		fee = appts.complete("discharge", p.id)
	return {"indicated": indicated, "kind": kind, "fee": fee}

# ------------------------------------------------------------------ machines
func run_machine(m: TreatmentMachine, p: Patient) -> Dictionary:
	if m == null or p == null or p.discharged:
		return {}
	var res: Dictionary = m.run_cycle(p)
	if res.is_empty():
		return {}
	p.recovery = clampf(p.recovery + float(res["recovery"]), -0.2, 1.0)
	p.record_treatment(m.treatment_id, clampf(float(res["recovery"]) * 3.0, -1.0, 1.0))

	if String(res["complication"]) != "":
		patient_system.add_complication(p, String(res["complication"]),
			"machine_deviation" if absi(int(res["deviation"])) >= 3 else "equipment_variance")

	# Running a machine that is not indicated for this condition is obvious to
	# anyone who knows the patient, regardless of where the dial is sitting —
	# without this, "wrong machine, correct dial" was completely invisible.
	var visual := float(res["visual"])
	var tags: Array = ["treatment", "machine"]
	if not bool(res.get("correct", true)):
		visual = maxf(visual, 0.4)
		tags.append("wrong_treatment")
	if m.machine_id == "machine_imaging":
		_record_imaging(p, int(res["deviation"]))
	elif m.machine_id == "machine_dread":
		_fill_nearest_canister(m)

	var e := WorldEvent.new("machine_treatment", "player") \
		.at(m.global_position, m.room_key).about(p.id) \
		.seen(visual).heard(0.02, 9.0).cover("equipment_variance") \
		.says("ran the %s on %s at %d" % [m.fixture_name, p.display_name, m.dial])
	for t in tags:
		e.tag(String(t))
	e.emit()
	EventBus.treatment_applied.emit(p, m.treatment_id, float(res["recovery"]))
	return res

## Extraction has to put what it extracted SOMEWHERE. The canister is a physical
## object with a lid, and nothing in the building stops you carrying it off.
func _fill_nearest_canister(m: TreatmentMachine) -> void:
	var best: Node3D = null
	var best_d := 6.0
	for prop in get_tree().get_nodes_in_group("prop"):
		if not prop.has_method("get_item_id") or String(prop.call("get_item_id")) != "dread_canister":
			continue
		var d: float = prop.global_position.distance_to(m.global_position)
		if d < best_d:
			best_d = d
			best = prop
	if best == null:
		return
	best.set("contents", "ambient_dread")
	EventBus.toast.emit("The canister is full again.", "info")

## Imaging is the only thing in the game that tells you the truth, and the only
## entry in the record that is not in your handwriting. It cannot be edited,
## forged or shredded, and it names the cause the SIMULATION knows about — so
## imaging a patient you have been quietly working on is a confession you signed
## by walking down the corridor.
##
## The aperture has a prescribed setting like every other device on the floor.
## Off it, the scan degrades into artefact: nothing goes into the record, the
## request is satisfied on paper, and the only trace is a line in the device log
## that somebody has to go to Radiology and look for. That is the whole trade —
## an alibi now against a document later.
func _record_imaging(p: Patient, deviation: int) -> void:
	p.clear_imaging_request()
	if absi(deviation) >= 2:
		p.chart.add_note(
			"Imaging attempted. Scan degraded by aperture artefact; findings inconclusive.",
			GameState.career_minutes, "Radiology", true)
		EventBus.toast.emit("%s imaged — the scan came back as noise." % p.display_name, "info")
		return

	p.imaged_at = GameState.career_minutes
	p.chart.imaging_done = true
	p.chart.imaging_day = GameState.day
	var active := p.active_complications()
	# "Clear" means nothing underlying was found — which is true whenever the
	# patient has no active complications at the time of the scan.
	p.chart.imaging_clear = active.is_empty()
	for c in active:
		var comp := c as Complication
		p.chart.imaging_findings.append({
			"id": comp.id, "name": comp.display_name,
			"cause": comp.true_cause, "day": GameState.day,
		})
	p.chart.add_note("Imaging performed. %s" % (
		"No underlying cause identified." if p.chart.imaging_clear
		else "Findings recorded against %d active complication(s)." % active.size()),
		GameState.career_minutes, "Radiology", true)
	EventBus.toast.emit("%s imaged — vitals are exact for a day." % p.display_name, "good")

# ------------------------------------------------------------------ discharge
## Discharging someone who is not actually better is its own kind of gamble:
## great for your length-of-stay statistics, terrible if they come back.
func attempt_discharge(p: Patient) -> Dictionary:
	if p == null:
		return {}
	if p.recovery >= 0.98:
		patient_system.discharge(p, "recovered")
		return {"ok": true, "premature": false}
	patient_system.discharge(p, "premature")
	var severity := clampf((1.0 - p.recovery) * 0.8, 0.05, 0.8)
	WorldEvent.new("premature_discharge", "player").at(Vector3.ZERO, p.room).about(p.id) \
		.seen(0.0).tag("records").cover("clinical_findings") \
		.says("discharged %s at %d%% recovery" % [p.display_name, int(p.recovery * 100.0)]).emit()
	var sus = get_tree().get_first_node_in_group("suspicion_system")
	if sus:
		sus.report_to_institution("insurer", "premature_discharge", severity,
			"%s discharged well short of recovery" % p.display_name, p.id, ["discharge"])
	return {"ok": true, "premature": true}
