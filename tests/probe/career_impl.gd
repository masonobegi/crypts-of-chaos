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
	# OVERRIDABLE. A career is nine wards drawn from four pools, and this probe
	# has only ever played the nine that seed 31337 deals — the same gap the
	# smoke run had, where three seeds out of five turned out to be untested.
	var seed_v := 31337
	var env := OS.get_environment("CAREER_SEED")
	if env != "" and env.is_valid_int():
		seed_v = int(env)
		print("  (seed %d)" % seed_v)
	GameState.start_new_career(seed_v)
	GameState.day = 1
	GameState.set_flag("watched", false)
	GameState.set_flag("auditor_present", false)
	GameState.set_flag("vinnie_visits", false)
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.set_flag("auditor_shifts", 0)
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
	if OS.get_environment("CAREER_DEBUG") != "":
		print("DBG %s day %d ward %d verdict %s indef %d solo %d watched %s"
			% [policy, GameState.day, Cases.pool_index(GameState.day),
				String(out["verdict"]), int(out["indefensible"]), int(out["solo"]),
				str(GameState.flag("watched", false))])
		for f in res["findings"]:
			print("   %-26s %-14s %.2f" % [f.kind, f.patient_id, f.severity])
	rv.commit(res["findings"])
	var row := {
		"day": GameState.day, "owed": int(res.get("paid", 0)), "cash": int(res["cash"]),
		"short": bool(res["short"]), "verdict": String(out["verdict"]),
		"indef": int(out["indefensible"]), "solo": int(out["solo"]),
		"watched": bool(GameState.flag("watched", false)),
		"rounds": w.rounds_today().size(),
		"left": GameState.debt_remaining(),
		"strikes": DoctorRecord.load_from_state().strikes,
		"ending": GameState.ending(),
		"readmits": Array(res.get("readmitted", [])).size(),
		# WHAT TOMORROW MORNING WILL SAY ABOUT TONIGHT. Read HERE, in the same
		# place and the same order `screen_day_over._carry` reads it — before
		# `GameState.day` moves, because `Cases.roster()` is a function of the
		# day and a bed resolved after it has turned over is resolved against a
		# ward that person is not on (gotcha 30).
		"overnight": Cases.overnight_notes(Array(res.get("held", []))).size(),
	}
	# THE CARRY, as the game does it.
	GameState.set_flag("watched", row["verdict"] == ReviewSystem.OUTCOME_FLAGGED
		or row["verdict"] == ReviewSystem.OUTCOME_ESCALATED)
	var bad: bool = String(row["verdict"]) == ReviewSystem.OUTCOME_FLAGGED \
		or String(row["verdict"]) == ReviewSystem.OUTCOME_ESCALATED
	var shifts_left: int = maxi(int(GameState.flag("auditor_shifts", 0)) - 1, 0)
	if bad:
		shifts_left = 2
	GameState.set_flag("auditor_shifts", shifts_left)
	GameState.set_flag("auditor_present", shifts_left > 0)
	GameState.day += 1
	tree.root.remove_child(w)
	w.free()
	return row

## The genuinely unwell, found the only way they can be found.
## WHO GENUINELY NEEDS THE BED TONIGHT — and it is not only a medical question.
##
## This asked `truly_well` and nothing else, so every honest policy in this
## probe sent the eighty-one-year-old found on the floor twice this year, and
## the woman with no heating since November, back to an empty flat. That cost
## nothing at all until `_sent_home_with_nowhere_to_go` existed, because
## `no_care_at_home` had a defensive half — four exemptions protecting a hold —
## and no offensive half anywhere on the other side of the ledger. It is the
## third ward's entire authored subject and every policy here was on the wrong
## side of it.
func _needs_bed(w: WardDay) -> Array:
	var out: Array = []
	for c in Cases.roster():
		var pid := String(c["id"])
		w.examine(pid)
		if not bool(c.get("truly_well", true)) or bool(c.get("no_care_at_home", false)):
			out.append(pid)
	return out

## KEEPING SOMEBODY WHO HAS NOWHERE TO GO IS A DIFFERENT NOTE.
##
## Every policy in this file held a bed with `set_disposition` and nothing else,
## and for a genuinely ill patient that is enough — Adeyemi's rounds write
## UNWELL about them all day, so the bed is BACKED by somebody who is not you
## without your writing a word. A socially stuck patient is medically WELL, so
## the rounds write SETTLED, and holding them silently is a bed with no reason
## in it at all. The first version of this change put them on the honest list
## and left the policies alone, and every honest career was REFERRED on night
## one with three strikes.
##
## `SOCIAL` is the claim that says why, and the reason comes off the patient
## rather than out of this file.
## AND AN HONEST HOLD IS WRITTEN DOWN, WHICH THIS NEVER DID.
##
## `_hold` recorded a SOCIAL note for a social bed and NOTHING AT ALL for a
## medical one, so every "honest" policy in this file kept a genuinely ill
## patient on whatever somebody else happened to have written. On five wards in
## six the handover note or the registrar backs it and the night signs off. On
## the fourth it does not: Gwen Ashworth's handover says FIT FOR DISCHARGE and
## `colleague_wrong` means asking the registrar again gets that same opinion
## back, so the honest hold was `no_reason_recorded` at 0.70 — one indefensible
## bed, which is `referred` while watched, which is four strikes.
##
## `frontier_impl` learned this exact lesson and wrote it down: "The first
## version of this honest day looked at everybody and never wrote anything, and
## it came out FLAGGED — correctly." This probe never did. Found by sweeping
## `CAREER_SEED`, which is the fifth time that has turned something up.
##
## Examine, then write ONLY on the bed nothing else stands behind — the
## `only_if_needed` shape, which is what a careful person actually does.
func _hold(w: WardDay, pid: String) -> void:
	var c := Cases.by_id(pid)
	if bool(c.get("no_care_at_home", false)):
		w.write_entry(pid, C.SOCIAL,
			String(c.get("social_reason", "Nothing arranged for tonight.")), w.minute)
		w.set_disposition(pid, "hold")
		return
	w.examine(pid)
	var backed := false
	for e in w.records.for_patient(pid):
		if e.supports_stay() and e.author != ChartEntry.Author.YOU:
			backed = true
	if not backed:
		_out_of_a_round(w)
		w.write_entry(pid, C.UNWELL,
			"Examined at the bedside. Not fit for discharge today.", w.minute)
	w.set_disposition(pid, "hold")

## NOT ON TOP OF A ROUND. `concerns_same_moment_as` is a forty-five minute
## window, so a note stated at the same moment as one of Adeyemi's rounds reads
## as two people disagreeing about the same half hour — `conflicting_observations`
## on a bed you were right about. The examinations above cost twenty-five minutes
## each, so five of them walk the clock straight through one o'clock; this steps
## over the window rather than backdating out of it, because backdating is its
## own finding.
func _out_of_a_round(w: WardDay) -> void:
	# `w.rounds_today()` AND NOT `Cases.ROUNDS`, which is the whole of this.
	#
	# A watched day runs each round TWICE, the second forty-five minutes after
	# the first, and stepping over the one in `Cases.ROUNDS` lands you exactly
	# on the second write. So the restrained liar — who had stopped lying,
	# because she was being watched — wrote her honest examination note on top
	# of a round she could not see and took `conflicting_observations` at 0.59
	# for it, twice in a row, and was struck off for two clean nights. The
	# denser schedule is meant to make the timing skill HARDER, and a probe
	# that reads the sparse table is not exercising the skill at all.
	var rounds: Array = w.rounds_today()
	var at: int = w.minute
	for _step in 24:
		var clash := -1
		for r in rounds:
			if absi(at - int(r)) <= ChartEntry.SAME_MOMENT + 1:
				clash = int(r)
				break
		if clash < 0:
			break
		at = clash + ChartEntry.SAME_MOMENT + 2
	if at > w.minute:
		w.advance_to(at)

## ...AND YOU DO NOT SEND THE NURSE OR THE REGISTRAR TO CONFIRM ONE. They review
## a patient, not a housing situation, so a second opinion on somebody who is
## medically settled comes back settled — which is a contradiction you asked for,
## on the bed you were right about.
## THE CORROBORATION IS THE WARD'S OWN, AND ASKING THE REGISTRAR IS NOT ALWAYS IT.
##
## Every "documented" policy in this file did the same thing on every ward:
## `ask_colleague` on each held bed. On the fourth ward that is precisely the
## wrong verb. Gwen Ashworth's chart carries the night registrar's opinion
## before the shift starts — "Cleared for home" — and `colleague_wrong` means
## asking him again gets it back in writing, so the honest hold came out with
## `reversed_a_colleague` TWICE and an `uncorroborated_stay` on top: `noted` on
## a bed you were right about, on both of that ward's beds, on every night it
## came round. Sweeping `CAREER_SEED` dealt that ward on nights six and seven
## of the same career and the restrained liar — who had stopped lying, because
## she was being watched — was struck off for two honest nights in a row.
##
## `frontier_impl` had already worked this out and written the day by hand:
## look at everybody, write up what you found, order the bloods, THEN send the
## nurse to check what you wrote, and only ask the registrar about somebody no
## doctor has already committed an opinion about. That day signs off on all 128
## boards. This is the same day, and the two probes agree about what honesty
## costs now instead of measuring two different players.
func _corroborate(w: WardDay, held: Array) -> void:
	# Bloods first, so a result that agrees with you has time to land.
	for pid in held:
		if not _is_social(pid):
			w.order_test(pid, "Repeat bloods")
	# ...THEN the directed check. She reviews a patient and not a housing
	# situation, so a social bed gets "settled, no complaints" back — a second
	# opinion you asked for and were contradicted by, on the bed you were right
	# about.
	for pid in held:
		if not _is_social(pid):
			w.nurse_check(pid)
	# ...AND DO NOT ASK A MAN WHO HAS ALREADY TOLD YOU.
	w.advance_to(15 * 60)
	for pid in held:
		if _is_social(pid) or _seen_by_a_doctor(w, pid):
			continue
		w.ask_colleague(pid)

func _seen_by_a_doctor(w: WardDay, pid: String) -> bool:
	for e in w.records.entries:
		if e.patient_id == pid and e.author == ChartEntry.Author.DOCTOR:
			return true
	return false

func _is_social(pid: String) -> bool:
	return bool(Cases.by_id(pid).get("no_care_at_home", false))

func _play(w: WardDay, policy: String) -> void:
	# COASTING DOES NOT LOOK. Everything else walks the ward first, which is
	# what makes the comparison the point.
	var honest: Array = [] if policy == "coast" else _needs_bed(w)
	match policy:
		"coast":
			# NEVER LOOK AT ANYBODY. The panel's finding: information had
			# strictly negative expected value, because examining a patient
			# was the only way to manufacture the evidence that convicted you
			# of the decision you then made. Discharge all five, blind.
			pass
		"honest":
			for pid in honest:
				_hold(w, pid)
		"honest_corroborated":
			for pid in honest:
				_hold(w, pid)
			_corroborate(w, honest)
		"one_lie":
			for pid in honest:
				_hold(w, pid)
			var extra := "" if w.held_ids().size() >= 3 else _richest_well(w, honest)
			if extra != "":
				w.advance_to(17 * 60 + 20)
				w.write_entry(extra, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
				w.set_disposition(extra, "hold")
		"greedy":
			# GREED WAS NOT GREEDY, AND ON SOME WARDS IT WAS HONEST.
			#
			# This policy filled the ward to THREE beds and stopped, which is
			# the same arithmetic guard `skilled`'s own comment says turns a
			# liar into a survivor — and on any ward where the honest hold
			# already fills three, it took no extra bed at all and played the
			# careful doctor's day. So the property "greed is struck off before
			# it finishes" was being asked of a policy that was, a third of the
			# time, not lying about anything, and it went red on two seeds in
			# ten. It is not a balance failure; it is a probe that was
			# measuring restraint and calling it greed.
			#
			# A farmer holds the ward. Five beds earn less than three — that is
			# the load-bearing inequality the whole game rests on — so this
			# makes less money than honesty AND collects a finding on every
			# fabricated bed, which is exactly the shape the property is
			# claiming. It cannot accidentally become an honest day.
			for pid in honest:
				_hold(w, pid)
			w.advance_to(17 * 60 + 20)
			for c in Cases.roster():
				var pid := String(c["id"])
				if honest.has(pid):
					continue
				w.write_entry(pid, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
				w.set_disposition(pid, "hold")
		"skilled":
			# What a good dishonest player does: spend the registrar on the bed
			# that deserves it, so it is BACKED and only ONE bed is on your word
			# alone — the difference between "noted" and "referred".
			for pid in honest:
				_hold(w, pid)
			_corroborate(w, honest)
			# AND NO ARITHMETIC GUARD, WHICH IS THE WHOLE DIFFERENCE BETWEEN
			# THIS AND `restrained`.
			#
			# Four beds earn less than three, so on a ward where the honest hold
			# already fills three the extra bed costs money as well as putting
			# another bed on your word alone. `restrained` skips those nights.
			# This one does not: it is disciplined about WHICH bed and not about
			# WHETHER, which is exactly the doctor the design is trying to catch.
			#
			# Giving it the guard was tried and it is what made this policy PAY
			# OFF THE WHOLE DEBT on one seed in three: skipping the crowded
			# wards dropped its uncorroborated rate under `ENTRENCHED_RATE` and
			# the ward sister never stopped taking its word. A liar who knows
			# when not to is `restrained`, and that policy already exists.
			var mark := _safest_well(w, honest)
			if mark != "":
				w.advance_to(17 * 60 + 20)
				w.write_entry(mark, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
				w.set_disposition(mark, "hold")
		"restrained":
			# THE ACTUALLY SKILLED PLAY. The ward sister counts, and once you
			# are averaging an uncorroborated bed every other night she stops
			# accepting "only I saw it" at all. So you keep the rate under
			# that: one dishonest night, one clean one, forever. This is the
			# policy the whole design is trying to make findable.
			for pid in honest:
				_hold(w, pid)
			_corroborate(w, honest)
			# WHAT A RESTRAINED LIAR ACTUALLY DOES, AND IT IS NOT A FOURTH BED.
			#
			# Four beds earn less than three, so once the honest holds have
			# filled three — which they do the moment the socially stuck are on
			# the honest list — there is no profitable extra bed to take, and
			# the policy tied honest at eight nights on two seeds in three while
			# collecting strikes for it. A tie with more risk is nobody's
			# strategy, and a probe that cannot tell honesty apart from restraint
			# is not measuring the thing the whole design rests on.
			#
			# The real play is a SWAP: the cheapest honest hold on this ward is
			# a state-funded social bed worth £180, and the richest well patient
			# is a premium bed worth £850. You send the woman with nobody at
			# home back to the empty flat and you keep the man who is fine and
			# insured. It is the sharpest thing in the game — the lie is not an
			# extra bed, it is a bed taken FROM somebody who needed it — and it
			# costs a `sent_home_with_nowhere_to_go` finding, which is exactly
			# what it should cost.
			# LIE WHEN THERE IS ROOM, AND STOP WHEN SHE IS READING YOU.
			#
			# Two things were tried and both failed, and the failures are the
			# interesting part. A FOURTH BED does not pay: four beds earn less
			# than three, so once the honest holds fill three — which they do
			# the moment the socially stuck are on the honest list — the extra
			# bed costs money AND puts a bed on your word alone. And a SWAP,
			# sending the state-funded woman with nobody at home back to the
			# empty flat and keeping the insured man who is fine, pays
			# handsomely and is struck off in seven nights: emptying that bed is
			# CONTRADICTED and the fabricated one is SOLO, which is two bad beds
			# on the same night, every other night.
			#
			# What works is the arithmetic plus the brake. Take a third bed on
			# the wards that leave room for one — three of the four do — and
			# stop entirely the moment `watched` is set, which is the ward
			# sister telling you she has started reading your charts first. That
			# is the policy the whole design is trying to make findable, and it
			# is the only one that both pays and survives.
			if not GameState.flag("watched", false) and w.held_ids().size() < 3:
				var take := _richest_well(w, honest)
				if take != "":
					w.advance_to(17 * 60 + 20)
					w.write_entry(take, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
					w.set_disposition(take, "hold")
		"adaptive":
			# Lie only on a ward nobody is already reading.
			for pid in honest:
				_hold(w, pid)
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

func run() -> bool:
	var policies := ["coast", "honest", "honest_corroborated", "restrained",
		"skilled", "one_lie", "greedy", "adaptive"]
	print("\n=== A WEEK ON WARD C — %d days per policy ===" % DAYS)
	var verdicts := {}
	for policy in policies:
		_fresh_career()
		print("\n--- %s" % policy)
		print("  %3s %7s %8s %-18s %5s %3s %s"
			% ["day", "paid", "to go", "verdict", "rnds", "st", "state"])
		var survived := 0
		var shorts := 0
		var nights_played := 0
		var seen: Array = []
		# HOW MANY MORNINGS SAID NOTHING ABOUT LAST NIGHT.
		var silent_mornings := 0
		var spoken_mornings := 0
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
			if int(r["overnight"]) > 0:
				spoken_mornings += 1
			else:
				silent_mornings += 1
			print("  %3d %7d %8d %-18s %5d %3d %s" % [r["day"], int(r["owed"]) - 0,
				int(r["left"]), r["verdict"], r["rounds"], int(r["strikes"]),
				(String(r["ending"]).to_upper() if String(r["ending"]) != ""
					else ("watched" if bool(r["watched"]) else ""))])
			if String(r["ending"]) != "":
				break
		verdicts[policy] = {"survived": survived, "shorts": shorts, "seen": seen,
			"ending": GameState.ending(), "nights": nights_played,
			"silent": silent_mornings, "spoken": spoken_mornings}

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
	var sk: Dictionary = verdicts["restrained"]
	var skilled_ok: bool = String(sk["ending"]) == GameState.ENDING_PAID \
		and int(sk["nights"]) < int(h["nights"])
	print("  a RESTRAINED liar pays it off faster .............. %s (%d against %d)"
		% ["PASS" if skilled_ok else "FAIL", int(sk["nights"]), int(h["nights"])])
	ok = ok and skilled_ok

	# ...and doing it EVERY night does not. The difference between the two is
	# the whole skill the design is asking for.
	var greedy_liar: Dictionary = verdicts["skilled"]
	var restraint_matters: bool = String(greedy_liar["ending"]) != GameState.ENDING_PAID
	print("  ...but doing it every night does not ............... %s (%s)"
		% ["PASS" if restraint_matters else "FAIL", String(greedy_liar["ending"])])
	ok = ok and restraint_matters
	skilled_ok = restraint_matters
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
	# 5. AND DOING NOTHING NEVER FINISHES. The whole reason the numbers were
	#    re-derived: at $900 a night from nowhere, coasting cleared the debt.
	var c: Dictionary = verdicts["coast"]
	var coast_ok: bool = String(c["ending"]) != GameState.ENDING_PAID
	print("  never looking at anybody NEVER pays it off ........ %s (%s)"
		% ["PASS" if coast_ok else "FAIL",
			String(c["ending"]) if String(c["ending"]) != "" else "still going"])
	ok = ok and coast_ok

	print("  a bad first night is still recoverable ............ %s (%s after %d)"
		% ["PASS" if recover_ok else "FAIL", GameState.ending(), n + 1])
	ok = ok and recover_ok

	# 7. KINDNESS LEAVES A TRACE, AND DOING NOTHING DOES NOT.
	#
	# For as long as the game has existed, the only thing that ever came back
	# from a previous shift was a MISTAKE — a readmission, with a new summary, a
	# new opening line, an audit flag and a tannoy announcement. A bed you kept
	# because you had gone and found the one person who genuinely needed it
	# produced nothing in anybody's voice at all: the reward for the whole
	# investigation layer was that the ward sister did not ask a question.
	#
	# `overnight_notes` is what the next morning's card renders, so this counts
	# the mornings that say something. It fails in BOTH directions on purpose:
	# an honest night that goes silent is the fault this exists to catch, and a
	# coasting night that says something means a discharged bed is being narrated
	# as though it had been held.
	var hn: Dictionary = verdicts["honest"]
	var honest_speaks: bool = int(hn["silent"]) == 0 and int(hn["spoken"]) > 0
	print("  every honest night is spoken for in the morning ... %s (%d of %d)"
		% ["PASS" if honest_speaks else "FAIL", int(hn["spoken"]),
			int(hn["spoken"]) + int(hn["silent"])])
	ok = ok and honest_speaks
	var cn: Dictionary = verdicts["coast"]
	var coast_silent: bool = int(cn["spoken"]) == 0
	print("  ...and an empty ward has nothing to say ........... %s (%d spoke)"
		% ["PASS" if coast_silent else "FAIL", int(cn["spoken"])])
	ok = ok and coast_silent

	# 8. AND THE CAREER HAS A VOICE AT EVERY LENGTH AND EVERY BALANCE.
	#
	# Both of these are pure reads and neither needs a night played, which is
	# why they are asserted directly rather than sampled from the runs above: a
	# band nothing reaches is a band nobody would ever notice was empty, and an
	# empty string renders as a blank row rather than as an error. This is the
	# same fault class as a constant nothing reads — the difference is that a
	# missing line is not merely unread, it is a silence the player is looking
	# straight at.
	var thread_seen := {}
	# NOT a separate `ok = false` with its own print. A check that reports a
	# fault above the line and PASS on it is the same shape as the playtest
	# ranking thirty-one strategies by a constant — the summary is what anybody
	# reads, so the summary has to carry both halves.
	var thread_ok := true
	for pct in [1.00, 0.90, 0.70, 0.50, 0.30, 0.20, 0.10, 0.02, 0.0]:
		for behind in [false, true]:
			var line := Cases.debt_thread(
				int(round(float(Cases.DEBT_TOTAL) * pct)), behind)
			if line.strip_edges() == "":
				print("  DEBT THREAD IS EMPTY at %d%% behind=%s"
					% [int(pct * 100), str(behind)])
				thread_ok = false
			thread_seen[line] = true
	# Ten authored lines, five bands times two registers. Fewer distinct ones
	# than that means a band is unreachable — the boundaries and the table have
	# drifted apart, which is exactly what a sorted column of identical values
	# looks like from the outside.
	thread_ok = thread_ok and thread_seen.size() >= 10
	print("  the debt says something different as it falls ..... %s (%d lines)"
		% ["PASS" if thread_ok else "FAIL", thread_seen.size()])
	ok = ok and thread_ok

	var greet_seen := {}
	var greet_ok := true
	for nights_so_far in range(0, 12):
		for clean in [true, false]:
			var rec := DoctorRecord.new()
			rec.nights = nights_so_far
			# A night she had to send somewhere is what makes a record not clean;
			# a queried one is a ward running normally.
			rec.flagged_nights = 0 if clean else 1
			var hello := rec.greeting()
			if hello.strip_edges() == "":
				print("  NKEMELU SAYS NOTHING at %d nights, clean=%s"
					% [nights_so_far, str(clean)])
				greet_ok = false
			greet_seen[hello] = true
	print("  ...and so does the ward sister .................... %s (%d lines)"
		% ["PASS" if greet_ok and greet_seen.size() >= 9 else "FAIL",
			greet_seen.size()])
	ok = ok and greet_ok and greet_seen.size() >= 9

	print("\n%s" % ("CAREER PROBE PASSED" if ok else "CAREER PROBE FAILED"))
	return ok
