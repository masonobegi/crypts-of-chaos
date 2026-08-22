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

const DAYS := 20

func _fresh_career() -> void:
	GameState.start_new_career(31337)
	GameState.day = 1
	GameState.set_flag("watched", false)
	GameState.set_flag("auditor_present", false)
	GameState.set_flag("vinnie_visits", false)
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.reset_debt()
	DoctorRecord.wipe()

## One day, played by `policy`, then the review, then the carry — exactly what
## screen_day_over._carry does, because that is the only place a verdict becomes
## state and a probe that reimplements it is measuring its own copy.
func _one_day(policy: String) -> Dictionary:
	# One ward at a time: a finished day disconnects from the clock, but a day
	# that never ended would still be force-closing itself and paying Vinnie out
	# of the same career debt the moment anything else advanced the clock.
	for n in tree.root.get_children():
		if n is WardDay:
			tree.root.remove_child(n)
			n.free()
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
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
	rv.commit(res["findings"])
	var row := {
		"day": GameState.day, "owed": int(res.get("paid", 0)), "cash": int(res["cash"]),
		"short": bool(res["short"]), "verdict": String(out["verdict"]),
		"indef": int(out["indefensible"]), "solo": int(out["solo"]),
		"watched": bool(GameState.flag("watched", false)),
		"rounds": w.rounds_today().size(),
		"left": GameState.debt_remaining(),
		"ending": GameState.ending(),
		"readmits": Array(res.get("readmitted", [])).size(),
	}
	# THE CARRY, as the game does it.
	GameState.set_flag("watched", row["verdict"] == ReviewSystem.OUTCOME_FLAGGED
		or row["verdict"] == ReviewSystem.OUTCOME_ESCALATED)
	GameState.set_flag("auditor_present", row["verdict"] == ReviewSystem.OUTCOME_ESCALATED)
	GameState.day += 1
	tree.root.remove_child(w)
	w.free()
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
		"skilled":
			# What a good dishonest player does: spend the registrar on the bed
			# that deserves it, so it is BACKED and only ONE bed is on your word
			# alone — the difference between "noted" and "referred".
			w.advance_to(11 * 60 + 10)
			for pid in honest:
				w.ask_colleague(pid)
				w.set_disposition(pid, "hold")
			var mark := _safest_well(w, honest)
			if mark != "":
				w.advance_to(17 * 60 + 20)
				w.write_entry(mark, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
				w.set_disposition(mark, "hold")
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

## The best-paying well patient who is NOT a trap: nobody who reads their own
## notes, nobody whose family reads them, nobody already under review. Choosing
## the target is most of the skill and the naive policy above does it by price.
func _safest_well(w: WardDay, skip: Array) -> String:
	var best := ""
	var best_fee := -1
	for c in Cases.roster():
		var pid := String(c["id"])
		if skip.has(pid) or not bool(c.get("truly_well", true)):
			continue
		# ONLY THE TRAPS THAT ARE ACTUALLY FATAL. A patient who reads her own
		# notes, or whose file is already under review, produces a finding in
		# the CONTRADICTED class — the bed is gone whatever you say about it.
		# A family who reads the chart and a man who praises you loudly are
		# severity, not contradiction, and a good player takes that trade. The
		# first version of this excluded all of them and concluded the second
		# ward has no survivable lie on it, which was the probe being timid
		# rather than the game being binary.
		if w.is_flagged(pid) or bool(c.get("reads_own_chart", false)):
			continue
		var fee: int = Cases.night_fee(int(c["tier"]))
		if fee > best_fee:
			best_fee = fee
			best = pid
	return best

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
	var policies := ["honest", "honest_corroborated", "skilled", "one_lie",
		"greedy", "adaptive"]
	print("\n=== A WEEK ON WARD C — %d days per policy ===" % DAYS)
	var verdicts := {}
	for policy in policies:
		_fresh_career()
		print("\n--- %s" % policy)
		print("  %3s %7s %8s %-18s %5s %4s %s"
			% ["day", "paid", "to go", "verdict", "rnds", "re", "state"])
		var survived := 0
		var shorts := 0
		var nights_played := 0
		var seen: Array = []
		for i in DAYS:
			if GameState.ending() != "":
				break
			var r := _one_day(policy)
			nights_played += 1
			seen.append(String(r["verdict"]))
			if not bool(r["short"]):
				survived += 1
			else:
				shorts += 1
			print("  %3d %7d %8d %-18s %5d %4d %s" % [r["day"], int(r["owed"]) - 0,
				int(r["left"]), r["verdict"], r["rounds"], int(r["readmits"]),
				(String(r["ending"]).to_upper() if String(r["ending"]) != ""
					else ("watched" if bool(r["watched"]) else ""))])
			if String(r["ending"]) != "":
				break
		verdicts[policy] = {"survived": survived, "shorts": shorts, "seen": seen,
			"ending": GameState.ending(), "nights": nights_played}

	print("\n=== does a career hold together? ===")
	var ok := true
	for policy in policies:
		var v: Dictionary = verdicts[policy]
		print("  %-22s %-12s after %d night(s)"
			% [policy, String(v["ending"]) if String(v["ending"]) != "" else "unfinished",
				int(v["nights"])])

	# 1. HONESTY FINISHES. If the clean route cannot pay the debt, it is a stunt.
	var h: Dictionary = verdicts["honest_corroborated"]
	var honest_ok: bool = String(h["ending"]) == GameState.ENDING_PAID
	print("\n  documented honest play pays it off ................ %s (%d nights)"
		% ["PASS" if honest_ok else "FAIL", int(h["nights"])])
	ok = ok and honest_ok

	# 2. AND SO CAN A GOOD DISHONEST PLAYER — faster, at real risk. If crime
	#    cannot finish at all it is not a choice, it is a trap.
	var sk: Dictionary = verdicts["skilled"]
	var skilled_ok: bool = String(sk["ending"]) == GameState.ENDING_PAID \
		and int(sk["nights"]) < int(h["nights"])
	print("  a careful liar pays it off FASTER ................. %s (%d against %d)"
		% ["PASS" if skilled_ok else "FAIL", int(sk["nights"]), int(h["nights"])])
	ok = ok and skilled_ok

	# 3. GREED DOES NOT. A policy that farms the ward has no tension in it.
	var g: Dictionary = verdicts["greedy"]
	var greed_ok: bool = String(g["ending"]) == GameState.ENDING_STRUCK_OFF
	print("  greed is struck off before it finishes ............ %s (night %d)"
		% ["PASS" if greed_ok else "FAIL", int(g["nights"])])
	ok = ok and greed_ok

	# 4. NO DEATH SPIRAL. One bad night must be recoverable.
	_fresh_career()
	_one_day("greedy")
	var recovered := 0
	var n := 0
	while GameState.ending() == "" and n < 20:
		n += 1
		var r := _one_day("honest_corroborated")
		if not bool(r["short"]):
			recovered += 1
	var recover_ok: bool = GameState.ending() == GameState.ENDING_PAID
	print("  a bad first night is still recoverable ............ %s (%s after %d)"
		% ["PASS" if recover_ok else "FAIL", GameState.ending(), n + 1])
	ok = ok and recover_ok

	print("\n%s" % ("CAREER PROBE PASSED" if ok else "CAREER PROBE FAILED"))
