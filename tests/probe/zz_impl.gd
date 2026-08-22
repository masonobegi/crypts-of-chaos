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

func _review(w: WardDay, res: Dictionary, label: String) -> void:
	var truth := w.review_truth()
	var finds := w.review_findings()
	var rv := ReviewSystem.new()
	rv.begin(finds, w.records.entries, truth)
	while not rv.finished():
		rv.answer(ReviewSystem.Answer.STAND_BY, res["held"])
	var o := rv.outcome()
	rv.commit(finds)
	var names := ""
	for f in finds:
		names += "%s/%.2f " % [f.kind, f.severity]
	print("  %s earned=%d verdict=%s indef=%d solo=%d strikes=%d" % [label,
		res["earned"], o["verdict"], o["indefensible"], o["solo"],
		DoctorRecord.load_from_state().strikes])
	print("      findings: %s" % ("(none)" if names == "" else names))

func _day(policy: String) -> void:
	var w := _ward()
	var back := ""
	for c in Cases.roster():
		if bool(c.get("readmitted", false)):
			back = String(c["id"])
	for c in Cases.roster():
		var pid := String(c["id"])
		w.read_chart(pid)
		w.examine(pid)
	for c in Cases.roster():
		var pid := String(c["id"])
		match policy:
			"honest":
				w.set_disposition(pid, "hold" if not bool(c.get("truly_well", true)) else "discharge")
			"dump_the_bouncer":
				if pid == back:
					w.set_disposition(pid, "discharge")
				else:
					w.set_disposition(pid, "hold" if not bool(c.get("truly_well", true)) else "discharge")
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	_review(w, res, "day %d [%s] bouncer=%s" % [GameState.day, policy, back if back != "" else "-"])
	GameState.day += 1
	tree.root.remove_child(w); w.free()

func run() -> void:
	print("### A: honest every night")
	_fresh()
	for i in 4:
		_day("honest")
	print("")
	print("### B: honest, but the man who bounces back is sent home again")
	_fresh()
	# night 1: honest, except send the one unwell man home so he bounces.
	var w := _ward()
	for c in Cases.roster():
		var pid := String(c["id"])
		w.read_chart(pid); w.examine(pid)
		w.set_disposition(pid, "discharge")
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var r := w.end_day()
	_review(w, r, "day 1 [dump everyone]  bouncer=-")
	GameState.day += 1
	tree.root.remove_child(w); w.free()
	for i in 3:
		_day("dump_the_bouncer")
