extends RefCounted
## PLAY A WEEK, NOT A DAY.
##
## Every harness in this repository measures ONE shift. The whole second half of
## the design — the carry, the remembered beds, the denser rounds after a flag,
## the debt that grows when Vinnie goes short — only exists across days, and
## nothing has ever run it. A game whose escalation is untested is a game whose
## escalation is a hypothesis.
##
## The two failure modes this exists to find:
##   DEATH SPIRAL — one bad night makes the next night unwinnable, so a player
##     who slips once is playing a formality until they restart.
##   FARM — a policy that clears every night forever with no rising cost, so
##     there is no reason to stop and nothing to be afraid of.
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer

const DAYS := 7

func _fresh_career() -> void:
	GameState.start_new_career(31337)
	GameState.day = 1
	for f in ["remembered_beds", "carried_debt", "watched", "auditor_present",
			"vinnie_visits"]:
		GameState.set_flag(f, PackedStringArray() if f == "remembered_beds" else 0)
	GameState.set_flag("watched", false)
	GameState.set_flag("auditor_present", false)
	GameState.set_flag("vinnie_visits", false)

## One day, played by `policy`, then the review, then the carry — exactly what
## screen_day_over._carry does, because that is the only place a verdict becomes
## state and a probe that reimplements it is measuring its own copy.
func _one_day(policy: String) -> Dictionary:
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	var owed: int = w.debt_tonight
	for c in Cases.roster():
		w.read_chart(String(c["id"]))
	_play(w, policy)
	w.advance_to(Cases.DEBT_DUE_MINUTE)
	var res := w.end_day()
	var rv := ReviewSystem.new()
	rv.begin(res["findings"], w.records.entries, w.review_truth())
	while not rv.finished():
		var f = rv.current()
		var pick: int = A.STAND_BY
		for o in rv.options(f, w.records):
			if int(o["a"]) == A.RECONCILE:
				pick = A.RECONCILE
		rv.answer(pick, res["held"])
	var out := rv.outcome()
	var row := {
		"day": GameState.day, "owed": owed, "cash": int(res["cash"]),
		"short": bool(res["short"]), "verdict": String(out["verdict"]),
		"indef": int(out["indefensible"]), "solo": int(out["solo"]),
		"watched": bool(GameState.flag("watched", false)),
		"rounds": w.rounds_today().size(),
	}
	# THE CARRY, as the game does it.
	GameState.set_flag("watched", row["verdict"] == ReviewSystem.OUTCOME_FLAGGED
		or row["verdict"] == ReviewSystem.OUTCOME_ESCALATED)
	GameState.set_flag("auditor_present", row["verdict"] == ReviewSystem.OUTCOME_ESCALATED)
	GameState.set_flag("remembered_beds", PackedStringArray(out.get("remembered", [])))
	GameState.set_flag("carried_debt", absi(int(res["cash"])) if bool(res["short"]) else 0)
	GameState.day += 1
	w.queue_free()
	return row

## The genuinely unwell, found the only way they can be found.
func _needs_bed(w: WardDay) -> Array:
	var out: Array = []
	for c in Cases.roster():
		var pid := String(c["id"])
		w.examine(pid)
		if not bool(c.get("truly_well", true)):
			out.append(pid)
	return out

func _play(w: WardDay, policy: String) -> void:
	var honest := _needs_bed(w)
	match policy:
		"honest":
			for pid in honest:
				w.set_disposition(pid, "hold")
		"honest_corroborated":
			w.advance_to(11 * 60 + 10)
			for pid in honest:
				w.ask_colleague(pid)
				w.set_disposition(pid, "hold")
		"one_lie":
			for pid in honest:
				w.set_disposition(pid, "hold")
			var extra := _richest_well(w, honest)
			if extra != "":
				w.advance_to(17 * 60 + 20)
				w.write_entry(extra, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
				w.set_disposition(extra, "hold")
		"greedy":
			for pid in honest:
				w.set_disposition(pid, "hold")
			w.advance_to(17 * 60 + 20)
			for c in Cases.roster():
				var pid := String(c["id"])
				if honest.has(pid) or w.held_ids().size() >= 3:
					continue
				w.write_entry(pid, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
				w.set_disposition(pid, "hold")
		"adaptive":
			# Lie only on a ward nobody is already reading.
			for pid in honest:
				w.set_disposition(pid, "hold")
			if not GameState.flag("watched", false):
				var extra := _richest_well(w, honest)
				if extra != "":
					w.advance_to(17 * 60 + 20)
					w.write_entry(extra, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
					w.set_disposition(extra, "hold")
	for c in Cases.roster():
		var pid := String(c["id"])
		if String(w.state[pid]["disposition"]) == "":
			w.set_disposition(pid, "discharge")

## The best-paying well patient who is not already flagged on their file.
func _richest_well(w: WardDay, skip: Array) -> String:
	var best := ""
	var best_fee := -1
	for c in Cases.roster():
		var pid := String(c["id"])
		if skip.has(pid) or not bool(c.get("truly_well", true)):
			continue
		if w.is_flagged(pid):
			continue
		var fee: int = Cases.night_fee(int(c["tier"]))
		if fee > best_fee:
			best_fee = fee
			best = pid
	return best

func run() -> void:
	var policies := ["honest", "honest_corroborated", "one_lie", "greedy", "adaptive"]
	print("\n=== A WEEK ON WARD C — %d days per policy ===" % DAYS)
	var verdicts := {}
	for policy in policies:
		_fresh_career()
		print("\n--- %s" % policy)
		print("  %3s %6s %7s %-18s %6s %6s" % ["day", "owed", "left", "verdict", "rounds", "flags"])
		var survived := 0
		var shorts := 0
		var seen: Array = []
		for i in DAYS:
			var r := _one_day(policy)
			seen.append(String(r["verdict"]))
			if not bool(r["short"]):
				survived += 1
			else:
				shorts += 1
			print("  %3d %6d %7d %-18s %6d %6s" % [r["day"], r["owed"], r["cash"],
				r["verdict"], r["rounds"],
				"watched" if bool(r["watched"]) else ""])
		verdicts[policy] = {"survived": survived, "shorts": shorts, "seen": seen}

	print("\n=== does a career hold together? ===")
	var ok := true
	for policy in policies:
		var v: Dictionary = verdicts[policy]
		print("  %-22s cleared %d of %d nights" % [policy, v["survived"], DAYS])
	# 1. HONESTY SURVIVES A WEEK. If it does not, the honest path is a stunt.
	var h: Dictionary = verdicts["honest_corroborated"]
	var honest_ok: bool = int(h["survived"]) == DAYS
	print("\n  honest play clears every night for a week ......... %s"
		% ("PASS" if honest_ok else "FAIL"))
	ok = ok and honest_ok
	# 2. GREED DOES NOT. A policy that farms the ward forever has no tension.
	var g: Dictionary = verdicts["greedy"]
	var caught := 0
	for s in Array(g["seen"]):
		if String(s) == ReviewSystem.OUTCOME_ESCALATED \
				or String(s) == ReviewSystem.OUTCOME_FLAGGED:
			caught += 1
	var greed_ok: bool = caught >= DAYS - 1
	print("  greed is caught on %d of %d nights ................ %s"
		% [caught, DAYS, "PASS" if greed_ok else "FAIL"])
	ok = ok and greed_ok
	# 3. NO DEATH SPIRAL. One bad night must be recoverable.
	_fresh_career()
	_one_day("greedy")                      ## a disaster on night one
	var recovered := 0
	for i in DAYS - 1:
		var r := _one_day("honest_corroborated")
		if not bool(r["short"]):
			recovered += 1
	var recover_ok: bool = recovered >= DAYS - 2
	print("  a bad night is recoverable by honest play ......... %s (%d of %d)"
		% ["PASS" if recover_ok else "FAIL", recovered, DAYS - 1])
	ok = ok and recover_ok
	print("\n%s" % ("CAREER PROBE PASSED" if ok else "CAREER PROBE FAILED"))
