class_name DoctorNPC
extends StaffNPC
## A colleague. Doctors witness less than nurses (they are rarely on the ward)
## but they read charts, which means their evidence is the kind that does not
## fade and the kind that ends up in front of a board.

func _ready() -> void:
	role = "doctor"
	outfit = Color(0.90, 0.91, 0.93)     # white coat
	home_room = "office"
	if patrol_rooms.is_empty():
		patrol_rooms = ["corridor", "station", "treatment", "office",
			"radiology", "intake"]
	super._ready()

## Colleagues periodically read your charts. An investigator-type does it every
## chance they get, and finds things nobody witnessed.
func review_charts(patients: Array) -> void:
	if mind == null:
		return
	var thoroughness: float = mind.observance * (1.6 if archetype == "investigator" else 0.8)
	for p in patients:
		if not RNG.chance("chart_review", thoroughness * 0.35):
			continue
		var findings: Array = p.chart.audit(p.actual_treatments, p.complications)
		for f in findings:
			var ev := Evidence.new()
			ev.kind = String(f["kind"])
			ev.about_actor = "player"
			ev.patient_id = p.id
			ev.source = Evidence.Source.RECORD
			ev.time = GameState.career_minutes
			ev.base_weight = float(f["weight"]) * 0.8
			ev.certainty = 0.85
			ev.summary = String(f["text"])
			mind.add_evidence(ev)
			if RNG.chance("doc_bark", 0.4):
				say(String(RNG.pick("doc_review", [
					"This chart doesn't add up.", "Who wrote this?",
					"That's not a cause of that.", "Hm. Interesting.",
				])), 3.0)
		_maybe_request_imaging(p)

## Once Radiology exists, a colleague reading a chart that has run long will ask
## for a scan. This is the hidden cost of the department: it is a machine that
## reports the truth, and you are not the only person who can point it at your
## patients. Declining is free today and costs you at clock-out.
func _maybe_request_imaging(p) -> void:
	var h = get_tree().get_first_node_in_group("hospital")
	if h == null or not h.is_room_open("radiology"):
		return
	if p.imaging_requested() or p.chart.imaging_done:
		return
	if not p.is_overdue():
		return
	# An investigator-type asks nearly every time. A lazy colleague mostly does
	# not, which is why WHICH doctor is on today is worth knowing.
	var appetite := 0.5 * (1.6 if archetype == "investigator" else 1.0)
	if archetype == "lazy":
		appetite *= 0.35
	if not RNG.chance("imaging_request", appetite):
		return
	p.imaging_requested_by = mind.id
	p.imaging_requested_day = GameState.day
	say(String(RNG.pick("imaging_ask", [
		"Get %s scanned, would you? It's been a while." % p.display_name,
		"I'd like imaging on %s before they go home." % p.display_name,
		"Can we put %s through the scanner today?" % p.display_name,
	])), 4.0)
	EventBus.toast.emit("%s wants %s imaged today." % [display, p.display_name], "suspicion")
