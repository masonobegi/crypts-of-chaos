extends RefCounted
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer

func run() -> void:
	GameState.start_new_career(31337)
	GameState.day = 1
	var w := WardDay.new(); tree.root.add_child(w); w.start()
	# Hold the one genuinely unwell man, with the nurse behind it. Never go near
	# the other four at all: no chart, no exam, no nurse, no registrar.
	w.advance_to(17 * 60)
	w.nurse_check("marchetti")
	w.set_disposition("marchetti", "hold")
	for c in Cases.roster():
		var pid := String(c["id"])
		if pid != "marchetti": w.set_disposition(pid, "discharge")
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	for f in res["findings"]:
		print("  finding %-28s sev %.2f  pid=%s" % [f.kind, f.severity, f.patient_id])
	var rv := ReviewSystem.new()
	rv.begin(res["findings"], w.records.entries, w.review_truth())
	while not rv.finished():
		rv.answer(A.STAND_BY, res["held"])
	var o := rv.outcome()
	print("  VERDICT: %s   beds=%d indef=%d solo=%d" % [o["verdict"], o["beds"],
		o["indefensible"], o["solo"]])
	print("  because: %s" % o["because"])
