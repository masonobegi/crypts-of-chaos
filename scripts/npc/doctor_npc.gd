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
