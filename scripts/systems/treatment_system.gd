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

func _complication_for_treatment(tid: String) -> String:
	match tid:
		"percussive_realign": return "post_percussive_ringing"
		"chalkinol", "placebex", "fluids": return "rebound_hiccups"
		"torque_wrench": return "ferrous_aura"
		"weighted_blanket": return "gravitational_relapse"
		"warm_compress", "steam_tent": return "reactive_shivers"
	return "ambient_dread"

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
		_record_imaging(p)
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

## Imaging is the only thing in the game that tells you the truth. It also puts
## that truth in the record permanently, so every claim you make afterwards has
## to agree with it.
func _record_imaging(p: Patient) -> void:
	p.imaged_at = GameState.career_minutes
	p.chart.imaging_done = true
	p.chart.imaging_day = GameState.day
	# "Clear" means nothing underlying was found — which is true whenever the
	# patient has no active complications at the time of the scan.
	p.chart.imaging_clear = p.active_complications().is_empty()
	p.chart.add_note("Imaging performed. %s" % (
		"No underlying cause identified." if p.chart.imaging_clear
		else "Findings consistent with recorded complications."),
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
