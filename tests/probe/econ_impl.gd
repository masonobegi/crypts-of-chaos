extends RefCounted
## FOUR WAYS TO PLAY WITHOUT EVER LOOKING AT ANYBODY, AND NONE OF THEM MAY WIN.
##
## `career_impl` asserts that "never looking at anybody NEVER pays it off", and
## it asserts it about exactly ONE blind policy: discharge all five, every
## night. That is the laziest blind play there is, and the interesting ones are
## the blind play that READS THE HANDOVER — keep whoever the night staff already
## wrote up as unwell, look at nobody, write nothing — and its two greedier
## cousins. This file exists because one of those found the hole: `blind_prior`
## used to clear the entire debt in eleven nights and never be struck off, on a
## design whose whole subject is that information must be paid for.
##
## It was a scratch file. It printed four tables, asserted nothing, and was not
## in `run_tests.sh` — so the one probe that had found the largest design
## inversion in the game could not report it, which is the same shape of fault
## as a harness whose last pipeline stage is `head`. It fails now, and it is in
## the suite.
var tree: SceneTree = null
var bad := 0
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

func run() -> bool:
	# THE WARD IS NOT EMPTY WHILE YOU TYPE.
	#
	# No probe in this repo builds a world — a bare `WardDay` in the tree root
	# and no suspicion system, no player body, no hospital — so `seen_by` was
	# empty on every entry any of them ever wrote, and
	# `_written_in_front_of_them` (up to 0.62, and a bed-killer) could not fire
	# in a single one of the strategies searched. See `WardDay.witness_stub`.
	# Adeyemi has been on this ward since six and writes every round in it; the
	# office door is the thing that shuts.
	WardDay.witness_stub = PackedStringArray(["Adeyemi"])
	var endings := {}
	for policy in ["blind_dump", "blind_prior", "blind_prior_plus", "blind_rich"]:
		_fresh()
		print("\n--- %s" % policy)
		print("  %3s %7s %8s %-18s %4s %4s %4s %s" % ["day","paid","to go","verdict","ind","solo","re","state"])
		for i in DAYS:
			if GameState.ending() != "": break
			var r := _one_day(policy)
			print("  %3d %7d %8d %-18s %4d %4d %4d %s" % [r["day"], r["paid"], r["left"], r["verdict"],
				r["indef"], r["solo"], r["re"], ("SHORT " if r["short"] else "") + String(r["ending"]).to_upper()])
			endings[policy] = String(r["ending"])
			if String(r["ending"]) != "": break

	print("\n=== CAN A BLIND CAREER PAY IT OFF? ===")
	for policy in endings:
		var e := String(endings[policy])
		var ok: bool = e != GameState.ENDING_PAID
		if not ok:
			bad += 1
		print("  %-18s %-14s %s" % [policy,
			e if e != "" else "still going", "ok" if ok else "*** PAID OFF BLIND ***"])
	# ...AND A CAREER THAT NEVER ENDS IS NOT A PASS EITHER. `blind_prior` ran
	# twenty-five nights without being struck off and without clearing the debt
	# for two iterations of this file, which is the loop the whole debt rework
	# exists to stop: he asks for the same number forever and nothing happens.
	for policy in endings:
		if String(endings[policy]) == "":
			bad += 1
			print("  %-18s ran %d nights and neither paid nor was struck off"
				% [policy, DAYS])
	print("")
	if bad == 0:
		print("ECONOMICS PROBE PASSED — no blind career pays it off, and none of them loops")
	else:
		print("ECONOMICS PROBE FAILED — %d problems" % bad)
	return bad == 0
