extends RefCounted
var tree: SceneTree = null
func mk() -> WardDay:
	var w := WardDay.new(); tree.root.add_child(w); return w
func dump(rv, w, label):
	var o = rv.outcome()
	print("   %s VERDICT=%s indef=%d solo=%d" % [label, o["verdict"],
		int(o["indefensible"]), int(o["solo"])])
	for b in o["beds"] if o.has("beds") else []: pass

func run() -> void:
	# ---- C: answering the ward-level "you never looked at anybody" question
	#         with POINT_AT_NURSE launders one specific CONTRADICTED bed.
	GameState.start_new_career(4242); GameState.reset_debt(); DoctorRecord.wipe()
	GameState.day = 1; GameState.set_flag(Cases.READMIT_FLAG, [])
	var w := mk(); w.start()
	w.advance_to(18 * 60)
	# a note about 08:30 typed at 18:00 -> backdated 570 min -> CONTRADICTED class
	w.write_entry("marchetti", ChartEntry.Claim.UNWELL, "Leg worse.", 8 * 60 + 30)
	w.set_disposition("marchetti", "hold")
	for c in Cases.DAY_ONE:
		var pid := String(c["id"])
		if pid != "marchetti": w.set_disposition(pid, "discharge")
	var t := w.review_truth(); var fs := w.review_findings()
	print("=== C ===")
	for f in fs: print("   %-32s pid=%-11s %.2f" % [f.kind, f.patient_id, f.severity])
	for b in Contradictions.audit_beds(w.records.entries, t, fs):
		print("   BEFORE %-11s billed=%s %s" % [b.patient_id, b.billed,
			Contradictions.Defence.keys()[b.state]])
	var rv := ReviewSystem.new(); rv.begin(fs, w.records.entries, t)
	while not rv.finished():
		var f = rv.current()
		var opts = rv.options(f, w.records)
		var names := []
		for o in opts: names.append(ReviewSystem.Answer.keys()[int(o["a"])])
		var pick: int = ReviewSystem.Answer.STAND_BY
		if f.kind == "never_laid_eyes_on_them":
			for o in opts:
				if int(o["a"]) == ReviewSystem.Answer.POINT_AT_NURSE:
					pick = ReviewSystem.Answer.POINT_AT_NURSE
		print("   Q %-32s pid=%-11s opts=%s pick=%s" % [f.kind, f.patient_id, names,
			ReviewSystem.Answer.keys()[pick]])
		rv.answer(pick, w.held_ids())
	var o := rv.outcome()
	print("   AFTER VERDICT=%s indef=%d solo=%d" % [o["verdict"],
		int(o["indefensible"]), int(o["solo"])])
	tree.root.remove_child(w); w.free()

	# ---- D: Ferreira signs herself out. What does the reviewer say about it?
	GameState.start_new_career(7); GameState.reset_debt(); DoctorRecord.wipe()
	GameState.day = 2; GameState.set_flag(Cases.READMIT_FLAG, [])
	var w2 := mk(); w2.start()
	for c in Cases.roster():
		var pid := String(c["id"])
		w2.read_chart(pid); w2.examine(pid)
	w2.advance_to(17 * 60)              ## she goes at 16:00
	for c in Cases.roster():
		var pid := String(c["id"])
		if String(w2.state[pid]["disposition"]) != "": continue
		w2.set_disposition(pid, "hold" if not bool(c.get("truly_well", true)) else "discharge")
	print("\n=== D: ferreira self-discharged? ", w2.state["ferreira"], " ===")
	var t2 := w2.review_truth(); var f2 := w2.review_findings()
	for f in f2: print("   %-32s pid=%-11s %.2f  | %s" % [f.kind, f.patient_id,
		f.severity, f.question])
	tree.root.remove_child(w2); w2.free()
