extends RefCounted
## ADVERSARIAL ECONOMICS PROBE (scratch, not part of the suite).
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer
const DAYS := 25

func _fresh() -> void:
	GameState.start_new_career(31337)
	GameState.day = 1
	GameState.set_flag("watched", false)
	GameState.set_flag("auditor_present", false)
	GameState.set_flag("vinnie_visits", false)
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.reset_debt()
	DoctorRecord.wipe()

func _one_day(policy: String) -> Dictionary:
	for n in tree.root.get_children():
		if n is WardDay:
			tree.root.remove_child(n); n.free()
	var w := WardDay.new(); tree.root.add_child(w); w.start()
	_play(w, policy)
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	var rv := ReviewSystem.new()
	rv.begin(res["findings"], w.records.entries, w.review_truth())
	while not rv.finished():
		var f = rv.current()
		var pick: int = A.STAND_BY
		for o in rv.options(f, w.records):
			if int(o["a"]) == A.RECONCILE: pick = A.RECONCILE
		rv.answer(pick, res["held"])
	var out := rv.outcome()
	rv.commit(res["findings"])
	var row := {"day": GameState.day, "paid": int(res.get("paid",0)), "short": bool(res["short"]),
		"verdict": String(out["verdict"]), "indef": int(out["indefensible"]), "solo": int(out["solo"]),
		"left": GameState.debt_remaining(), "ending": GameState.ending(),
		"re": Array(res.get("readmitted", [])).size(), "beds": int(out["beds"])}
	GameState.set_flag("watched", row["verdict"] == ReviewSystem.OUTCOME_FLAGGED or row["verdict"] == ReviewSystem.OUTCOME_ESCALATED)
	GameState.set_flag("auditor_present", row["verdict"] == ReviewSystem.OUTCOME_ESCALATED)
	GameState.day += 1
	tree.root.remove_child(w); w.free()
	return row

## Beds whose PRIOR chart (written by the night nurse, before you arrived)
## already supports a stay. Free corroboration, costing zero minutes.
func _prior_supports(w: WardDay, pid: String) -> bool:
	for e in w.records.for_patient(pid):
		if e.supports_stay() and e.author != ChartEntry.Author.YOU:
			return true
	return false

func _play(w: WardDay, policy: String) -> void:
	match policy:
		"blind_dump":
			pass
		"blind_prior":
			# Hold every bed the night staff already justified for you. No
			# reading, no examining, no registrar, no notes at all.
			for c in Cases.roster():
				var pid := String(c["id"])
				if _prior_supports(w, pid):
					w.set_disposition(pid, "hold")
		"blind_prior_plus":
			# ...and then a single evening note on the richest remaining bed.
			for c in Cases.roster():
				var pid := String(c["id"])
				if _prior_supports(w, pid):
					w.set_disposition(pid, "hold")
			var best := ""; var bf := -1
			for c in Cases.roster():
				var pid := String(c["id"])
				if String(w.state[pid]["disposition"]) == "hold": continue
				if w.is_flagged(pid) or bool(c.get("reads_own_chart", false)): continue
				var fee: int = Cases.night_fee(int(c["tier"]))
				if fee > bf: bf = fee; best = pid
			if best != "" and w.held_ids().size() < 3:
				w.advance_to(17*60+20)
				w.write_entry(best, C.UNWELL, "Unsettled this evening.", 17*60+18)
				w.set_disposition(best, "hold")
		"blind_rich":
			# Hold the three richest beds, one evening note each, look at nobody.
			var ids: Array = []
			for c in Cases.roster(): ids.append(c)
			ids.sort_custom(func(a,b): return Cases.night_fee(int(a["tier"])) > Cases.night_fee(int(b["tier"])))
			w.advance_to(17*60+20)
			for i in mini(3, ids.size()):
				var pid := String(ids[i]["id"])
				if not _prior_supports(w, pid):
					w.write_entry(pid, C.UNWELL, "Unsettled this evening.", 17*60+18)
				w.set_disposition(pid, "hold")
	for c in Cases.roster():
		var pid := String(c["id"])
		if String(w.state[pid]["disposition"]) == "":
			w.set_disposition(pid, "discharge")

func run() -> void:
	for policy in ["blind_dump", "blind_prior", "blind_prior_plus", "blind_rich"]:
		_fresh()
		print("\n--- %s" % policy)
		print("  %3s %7s %8s %-18s %4s %4s %4s %s" % ["day","paid","to go","verdict","ind","solo","re","state"])
		for i in DAYS:
			if GameState.ending() != "": break
			var r := _one_day(policy)
			print("  %3d %7d %8d %-18s %4d %4d %4d %s" % [r["day"], r["paid"], r["left"], r["verdict"],
				r["indef"], r["solo"], r["re"], ("SHORT " if r["short"] else "") + String(r["ending"]).to_upper()])
			if String(r["ending"]) != "": break
