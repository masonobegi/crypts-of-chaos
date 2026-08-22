extends RefCounted
var tree: SceneTree = null

func _fresh() -> void:
	GameState.start_new_career(31337)
	GameState.day = 1
	GameState.set_flag("watched", false)
	GameState.set_flag("auditor_present", false)
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.reset_debt()
	DoctorRecord.wipe()

func _ward() -> WardDay:
	for n in tree.root.get_children():
		if n is WardDay:
			tree.root.remove_child(n); n.free()
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	return w

## Exactly what screen_review._build does: recompute findings AND truth from the
## ward AFTER end_day() has run.
func _review(w: WardDay, res: Dictionary) -> Dictionary:
	var truth := w.review_truth()
	var finds := w.review_findings()
	print("   -- truth as the reviewer sees it")
	for pid in truth:
		print("      %-12s name=%-18s well=%s held=%s disc=%s bounced=%s flagged=%s" % [
			pid, String(truth[pid]["name"]), str(truth[pid]["well"]), str(truth[pid]["held"]),
			str(truth[pid]["discharged"]), str(truth[pid]["bounced_back"]), str(truth[pid]["flagged"])])
	for f in finds:
		print("      FINDING %-34s %.2f %s" % [f.kind, f.severity, f.patient_id])
	var rv := ReviewSystem.new()
	rv.begin(finds, w.records.entries, truth)
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.STAND_BY, res["held"])
	var o := rv.outcome()
	for b in Contradictions.audit_beds(w.records.entries, truth, finds):
		print("      BED %-12s billed=%s state=%d %s" % [b.patient_id, str(b.billed), int(b.state), b.why])
	print("   -- VERDICT %s (indef=%d solo=%d)" % [o["verdict"], o["indefensible"], o["solo"]])
	rv.commit(finds)
	return o

func run() -> void:
	_fresh()
	print("=== DAY 1: discharge everyone ===")
	var w := _ward()
	for c in Cases.roster():
		w.set_disposition(String(c["id"]), "discharge")
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var r1 := w.end_day()
	print("  earned=%d paid=%d readmits=%s" % [r1["earned"], r1["paid"], str(r1["readmitted"])])
	_review(w, r1)
	GameState.day += 1
	tree.root.remove_child(w); w.free()

	print("")
	print("=== DAY 2: RE-DISCHARGE the man who bounced back ===")
	var w2 := _ward()
	var back := ""
	for c in Cases.roster():
		if bool(c.get("readmitted", false)):
			back = String(c["id"])
	print("  bouncer on the ward = %s (well=%s)" % [back, str(Cases.by_id(back).get("truly_well", true))])
	for c in Cases.roster():
		var pid := String(c["id"])
		w2.read_chart(pid)
		w2.examine(pid)
		w2.set_disposition(pid, "discharge")
	w2.advance_to(Cases.DEBT_DUE_MINUTE)
	var r2 := w2.end_day()
	print("  earned=%d paid=%d readmits=%s" % [r2["earned"], r2["paid"], str(r2["readmitted"])])
	print("  findings CACHED by end_day: %d" % Array(r2["findings"]).size())
	for f in r2["findings"]:
		print("      CACHED %-34s %.2f %s" % [f.kind, f.severity, f.patient_id])
	_review(w2, r2)
