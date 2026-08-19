class_name RecordsSystem
extends Node
## Everything you can do to the paperwork. This is the Papers-Please half of the
## game and it is where most of the actual crime happens.
##
## Every action here takes a `private` flag from the terminal it was performed
## at. The same edit made at the nurses' station in front of three people and
## made in your office with the door shut are not the same act, and the game
## treats them differently.

var patient_system: PatientSystem = null

func _ready() -> void:
	add_to_group("records_system")
	patient_system = get_tree().get_first_node_in_group("patient_system")

func _visibility(private: bool, base: float) -> float:
	if private:
		return base * 0.15
	return base

func _emit(kind: String, p: Patient, visual: float, tags: Array, cover: String,
		summary: String, pos: Vector3, room: String) -> void:
	var e := WorldEvent.new(kind, "player").at(pos, room).seen(visual) \
		.cover(cover).says(summary)
	if p != null:
		e.about(p.id)
	for t in tags:
		e.tag(String(t))
	e.emit()

# ------------------------------------------------------------------ billing
## Bill for something you did. Honest, and the baseline.
func log_real_treatment(p: Patient, tid: String) -> void:
	if p == null:
		return
	p.chart.log_treatment(tid, GameState.career_minutes, true)

## Bill for something you did NOT do. Excellent money. Permanent record.
func log_phantom_treatment(p: Patient, tid: String, private: bool, pos: Vector3, room: String) -> void:
	if p == null:
		return
	p.chart.log_treatment(tid, GameState.career_minutes, false)
	GameState.stats.forged_entries += 1
	var value := int(float(DB.insurance_multiplier(p.insurance)) * 260.0)
	GameState.add_hospital(value, "billed %s" % DB.treatment_name(tid))
	_emit("phantom_billing", p, _visibility(private, 0.55),
		["records", "billing", "fraud"], "administrative",
		"billed %s for %s without doing it" % [DB.treatment_name(tid), p.display_name],
		pos, room)
	GameState.add_heat(0.015, "phantom billing")

# ------------------------------------------------------------------ complications
## The single most important action in the game. Filing a plausible cause BEFORE
## anyone notices turns a complication from an incident into revenue.
func document_complication(p: Patient, comp: Complication, cause: String,
		private: bool, pos: Vector3, room: String) -> Dictionary:
	if p == null or comp == null:
		return {}
	comp.documented_cause = cause
	comp.documented_at = GameState.career_minutes
	p.chart.times_edited += 1

	var plausible := comp.plausible_causes.has(cause)
	var clean := comp.is_clean()
	if clean:
		GameState.stats.complications_clean += 1
		var cdx = get_tree().get_first_node_in_group("codex")
		if cdx:
			cdx.note_clean_documentation()

	var visual := 0.0
	if not plausible:
		visual = 0.4          # writing down something that cannot be true
	elif comp.noticed_time >= 0:
		visual = 0.2          # filing it late, after someone already saw
	_emit("complication_documented", p, _visibility(private, visual),
		["records", "paperwork"], "administrative",
		"attributed %s to %s" % [comp.display_name, DB.cause_name(cause)],
		pos, room)

	if not plausible:
		var sus = get_tree().get_first_node_in_group("suspicion_system")
		if sus:
			sus.report_to_institution("admin", "impossible_cause", 0.35,
				"%s: %s attributed to %s" % [p.display_name, comp.display_name,
					DB.cause_name(cause)], p.id, ["records"])
	AudioMgr.play("stamp", -12.0)
	return {"clean": clean, "plausible": plausible}

## Causes the chart will offer for a given complication. Always includes some
## that do NOT fit, because the whole point is that filing the wrong one is easy.
func cause_options(comp: Complication) -> Array[String]:
	var out: Array[String] = []
	for c in comp.plausible_causes:
		out.append(String(c))
	for c in ["idiopathic", "patient_noncompliance", "dietary", "weather",
			"physician_error", "equipment_variance"]:
		if not out.has(c):
			out.append(c)
	return out

# ------------------------------------------------------------------ notes & dates
func add_note(p: Patient, text: String, truthful: bool, private: bool,
		pos: Vector3, room: String) -> void:
	if p == null:
		return
	p.chart.add_note(text, GameState.career_minutes, "You", truthful)
	if not truthful:
		GameState.stats.forged_entries += 1
		_emit("chart_falsified", p, _visibility(private, 0.5),
			["records", "forgery"], "administrative",
			"wrote a note that did not happen", pos, room)
	AudioMgr.play("paper", -14.0)

## Quietly moving the promised discharge date. Patients and families who were
## told the old date will notice; ones who weren't, won't.
func revise_discharge_date(p: Patient, new_day: int, private: bool,
		pos: Vector3, room: String) -> void:
	if p == null:
		return
	var old := p.chart.promised_discharge_day
	p.chart.promised_discharge_day = new_day
	p.chart.times_edited += 1
	if new_day <= old:
		return
	_emit("discharge_date_moved", p, _visibility(private, 0.3),
		["records"], "clinical_caution",
		"moved %s's discharge from day %d to day %d" % [p.display_name, old, new_day],
		pos, room)
	# The patient finds out one way or another, and being told later is worse
	# than being told now.
	if p.mind and RNG.chance("date_notice", 0.5 + p.mind.observance * 0.5):
		var ev := Evidence.new()
		ev.kind = "discharge_date_moved"
		ev.about_actor = "player"
		ev.patient_id = p.id
		ev.source = Evidence.Source.INFERRED
		ev.time = GameState.career_minutes
		ev.base_weight = 0.22 * float(new_day - old)
		ev.certainty = 0.75
		ev.cover_tag = "clinical_caution"
		ev.summary = "discharge date moved back %d day(s)" % (new_day - old)
		p.mind.add_evidence(ev)

# ------------------------------------------------------------------ facilities
## Report a fault BEFORE it causes a complication and the complication is the
## building's fault, not yours. This is the cleanest play in the game and it
## requires you to plan two steps ahead.
func file_facilities_ticket(r: Room, private: bool, pos: Vector3) -> void:
	if r == null:
		return
	r.facilities_ticket_filed = true
	GameState.add_cover("facilities", 600)
	GameState.add_hospital(-90, "facilities callout")
	_emit("facilities_ticket", null, _visibility(private, 0.0),
		["records", "facilities"], "facilities",
		"filed a facilities ticket for %s" % r.display, pos, r.key)
	EventBus.toast.emit("Facilities ticket filed for %s." % r.display, "info")
	AudioMgr.play("stamp", -14.0)

# ------------------------------------------------------------------ audit view
## What an auditor would currently find. Shown to the player at the end-of-shift
## chart review so the danger is legible before it becomes a verdict.
func pending_findings() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if patient_system == null:
		return out
	for p in patient_system.active():
		for f in p.chart.audit(p.actual_treatments, p.complications):
			var row: Dictionary = f.duplicate()
			row["patient"] = p.display_name
			row["patient_id"] = p.id
			out.append(row)
	out.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
	return out

func total_exposure() -> float:
	var total := 0.0
	for f in pending_findings():
		total += float(f["weight"])
	return total
