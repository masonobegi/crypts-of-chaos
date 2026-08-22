extends RefCounted
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer

func _new_ward() -> WardDay:
	for n in tree.root.get_children():
		if n is WardDay:
			tree.root.remove_child(n); n.free()
	var w := WardDay.new(); tree.root.add_child(w); w.start(); return w

func _review(w: WardDay) -> Dictionary:
	var res := w.end_day()
	var rv := ReviewSystem.new()
	rv.begin(res["findings"], w.records.entries, w.review_truth())
	while not rv.finished():
		var f = rv.current()
		var pick: int = A.STAND_BY
		for o in rv.options(f, w.records):
			if int(o["a"]) == A.RECONCILE: pick = A.RECONCILE
		rv.answer(pick, res["held"])
	var o := rv.outcome()
	print("   verdict=%s indef=%d solo=%d beds=%d because=%s"
		% [o["verdict"], o["indefensible"], o["solo"], o["beds"], o["because"]])
	for b in Contradictions.audit_beds(w.records.entries, w.review_truth(), res["findings"]):
		print("     bed %-12s billed=%s state=%d  %s"
			% [b.patient_id, str(b.billed), b.state, b.why])
	rv.commit(res["findings"])
	return {"res": res, "o": o}

func run() -> void:
	print("\n### DAY 1: discharge everybody blind, as 'coast' claims to")
	GameState.start_new_career(31337)
	var w := _new_ward()
	for c in Cases.roster():
		w.set_disposition(String(c["id"]), "discharge")
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var a := _review(w)
	print("   readmitted -> %s" % str(a["res"].get("readmitted", [])))
	print("   never_laid_eyes fired? %s"
		% str(_has(a["res"]["findings"], "never_laid_eyes_on_them")))

	# carry
	GameState.day += 1
	print("\n### DAY 2: they are back. DO THE RIGHT THING — examine, ask the")
	print("### registrar, get the nurse, hold them, document it.")
	var w2 := _new_ward()
	var backs: Array = []
	for c in Cases.roster():
		if bool(c.get("readmitted", false)): backs.append(String(c["id"]))
	print("   readmissions on the ward: %s" % str(backs))
	for pid in backs:
		w2.read_chart(pid)
		w2.examine(pid)
		w2.advance_to(11 * 60)
		w2.ask_colleague(pid)
		w2.nurse_check(pid)
		w2.write_entry(pid, C.UNWELL, "Not fit for discharge. Needs the bed.", w2.minute)
		w2.set_disposition(pid, "hold")
	for c in Cases.roster():
		var pid := String(c["id"])
		if String(w2.state[pid]["disposition"]) == "":
			w2.read_chart(pid); w2.examine(pid)
			w2.set_disposition(pid, "hold" if not bool(c.get("truly_well", true)) else "discharge")
	w2.advance_to(Cases.DEBT_DUE_MINUTE)
	var b := _review(w2)
	for f in b["res"]["findings"]:
		print("     finding %-32s %.2f  pid=%s" % [f.kind, f.severity, f.patient_id])

func _has(findings: Array, kind: String) -> bool:
	for f in findings:
		if String(f.kind) == kind: return true
	return false
