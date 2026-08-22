extends RefCounted
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer

func _mk(day: int, readmits: Array) -> WardDay:
	GameState.start_new_career(1234)
	GameState.day = day
	GameState.set_flag(Cases.READMIT_FLAG, readmits)
	var w := WardDay.new(); tree.root.add_child(w); w.start(); return w

func _review(w: WardDay, res: Dictionary) -> Dictionary:
	var rv := ReviewSystem.new()
	rv.begin(res["findings"], w.records.entries, w.review_truth())
	while not rv.finished():
		var f = rv.current()
		rv.answer(A.STAND_BY, res["held"])
	return rv.outcome()

func run() -> void:
	# 1. WARD THREE, PLAYED HONESTLY: hold the man who is ill and the two who
	#    have nowhere to go, and document the social holds truthfully.
	var w := _mk(3, [])
	for c in Cases.roster():
		w.read_chart(String(c["id"]))
	w.advance_to(17 * 60 + 20)
	for pid in ["doust", "aldridge"]:
		w.write_entry(pid, C.SOCIAL, String(Cases.by_id(pid).get("social_reason", "No care at home.")), 17 * 60 + 18)
	for pid in ["okwuosa", "doust", "aldridge"]:
		w.set_disposition(pid, "hold")
	for pid in ["tsang", "fry"]:
		w.set_disposition(pid, "discharge")
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	var o := _review(w, res)
	print("\nWARD THREE, THE HONEST DAY")
	print("  earned %d  wanted %d  short=%s" % [int(res["earned"]), int(res["wanted"]), str(res["short"])])
	print("  verdict: %s   indefensible %d  solo %d" % [o["verdict"], o["indefensible"], o["solo"]])
	print("  because: %s" % o["because"])
	for b in Contradictions.audit_beds(w.records.entries, w.review_truth(), res["findings"]):
		print("    bed %-10s billed=%s state=%d  %s" % [b.patient_id, str(b.billed), int(b.state), b.why])
	tree.root.remove_child(w); w.free()

	# 2. WARD THREE, SEND THE TWO SOCIAL HOLDS HOME AND SEE WHAT IT COSTS.
	var q := _mk(3, [])
	for c in Cases.roster():
		q.read_chart(String(c["id"]))
	q.set_disposition("okwuosa", "hold")
	for pid in ["tsang", "doust", "aldridge", "fry"]:
		q.set_disposition(pid, "discharge")
	q.advance_to(Cases.DEBT_DUE_MINUTE)
	var res2 := q.end_day()
	var o2 := _review(q, res2)
	print("\nWARD THREE, SEND MARYAM AND KIT HOME")
	print("  earned %d  wanted %d  short=%s" % [int(res2["earned"]), int(res2["wanted"]), str(res2["short"])])
	print("  verdict: %s   indefensible %d  solo %d" % [o2["verdict"], o2["indefensible"], o2["solo"]])
	print("  readmitted tomorrow: %s" % str(res2["readmitted"]))
	print("  findings:")
	for f in res2["findings"]:
		print("    %-32s %s %.2f" % [f.kind, f.patient_id, f.severity])
	tree.root.remove_child(q); q.free()
