extends RefCounted
## EVERY WARD A CAREER CAN DEAL YOU, PLAYED HONESTLY.
##
## A ward is a draw from a pool of authored people now, which is what stops the
## second career being a memory test — but it also means the game can deal a
## board nobody has ever looked at. The data check proves the CANDIDATES for a
## slot are interchangeable (same tier, same truth, so the money and the honest
## hold stay where the ward put them). That is necessary and it is not
## sufficient: it says nothing about whether the resulting five can be worked.
##
## So this walks all of them — every combination of every slot on every ward —
## and plays each one the way somebody who has understood the game would:
##
##   bloods on the beds you mean to keep, first thing, so the result is back
##   before you have to decide; go and look at the people who might be ill;
##   read everybody else so nothing is decided by somebody who never opened the
##   file; write up what you found, in your own name, in the morning.
##
## And then asserts the two things that have to be true of every board:
##
##   1. an honest day is not a disaster — no REFERRED, ever
##   2. an honest day pays what the night wants
##
## If a future alternate breaks either, this names the exact ward and slot
## combination rather than leaving it to be found by a player on seed 91195.
var tree: SceneTree = null
var bad := 0
var played := 0

func _fail(m: String) -> void:
	bad += 1
	print("  FAIL: " + m)

func _day(day: int, picks: Array) -> WardDay:
	GameState.day = day
	GameState.flags.clear()
	GameState.set_flag("debt_remaining", Cases.DEBT_TOTAL)
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.cash = 0
	GameState.minute_of_day = 8 * 60
	GameState.clock_running = false
	DoctorRecord.wipe()
	Cases.forced_picks = picks
	var w := WardDay.new()
	tree.root.add_child(w)
	w.start()
	return w

func _play(day: int, picks: Array) -> Dictionary:
	var w := _day(day, picks)
	var roster: Array = Cases.draw_five(day, picks)
	var keep: Array = []
	for c in roster:
		if not bool(c.get("truly_well", true)) or bool(c.get("no_care_at_home", false)):
			keep.append(String(c["id"]))
	# Bloods first, so they are back before anything has to be decided.
	for pid in keep:
		w.order_test(pid, "Repeat bloods")
	for c in roster:
		var pid := String(c["id"])
		if keep.has(pid):
			w.examine(pid)
		else:
			w.read_chart(pid)
	w.advance_to(maxi(w.minute, 11 * 60))
	for pid in keep:
		var c := Cases.by_id(pid)
		var claim: int = ChartEntry.Claim.SOCIAL if bool(c.get("no_care_at_home", false)) \
			else ChartEntry.Claim.UNWELL
		var text: String = String(c.get("social_reason", "Reviewed at the bedside. Not fit for discharge today."))
		w.write_entry(pid, claim, text, w.minute, WardDay.TERMINAL_OFFICE)
	# ...AND THEN SEND HER, WHICH IS THE ORDER THAT WORKS.
	#
	# A routine nurse review is a score and cannot find a body no document can
	# describe; a review of a finding you have already made and written down
	# can. So the sequence is look, write, and only then ask — and this probe
	# plays a person who has understood the game, so it plays it in that order.
	#
	# ONLY THE MEDICALLY UNWELL. Adeyemi reviews a patient, not a housing
	# situation: sending her to confirm a SOCIAL hold gets "settled, no
	# complaints" back about somebody who is medically settled and has nowhere
	# to go, which is a second opinion you asked for and were contradicted by,
	# on the bed you were right about. That is `invited_contradiction` and it is
	# correct — it is the wrong question, and the ward is where you learn so.
	for pid in keep:
		if bool(Cases.by_id(pid).get("truly_well", true)):
			continue
		w.nurse_check(pid)
	for c in roster:
		var pid := String(c["id"])
		w.set_disposition(pid, "hold" if keep.has(pid) else "discharge")
	var res := w.end_day()
	if OS.has_environment("DRAWS_DEBUG"):
		for fd in res["findings"]:
			print("    FINDING %-28s %-13s sev=%.2f  %s"
				% [fd.kind, fd.patient_id, fd.severity, fd.question])
	var rv := ReviewSystem.new()
	rv.begin(res["findings"], w.records.entries, w.review_truth())
	while not rv.finished():
		rv.answer(0, res["held"])
	var o := rv.outcome()
	var names: Array = []
	for c in roster:
		names.append(String(c["id"]))
	tree.root.remove_child(w)
	w.free()
	# PUT IT BACK. `forced_picks` is a static on Cases, so leaving it set meant
	# the distribution check below drew the same forced ward two thousand times
	# and reported one career — a harness bug that looks exactly like the real
	# bug it is there to catch.
	Cases.forced_picks = []
	return {"verdict": String(o["verdict"]), "paid": int(res["paid"]),
		"indef": int(o["indefensible"]), "who": names, "kept": keep.size()}

## Turn a roster back into per-slot candidate indices, which is what
## `Cases.forced_picks` speaks.
func _picks_for(day: int, deal: Array) -> Array:
	var by_bed := {}
	for c in Cases.pool_for(day):
		var b := int(c["bed"])
		if not by_bed.has(b):
			by_bed[b] = []
		by_bed[b].append(String(c["id"]))
	var beds: Array = by_bed.keys()
	beds.sort()
	var picks: Array = []
	for i in beds.size():
		picks.append(int(Array(by_bed[beds[i]]).find(String(deal[i]["id"]))))
	return picks

func run() -> void:
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
	print("\n=== EVERY DEAL, PLAYED HONESTLY ===")
	for day in range(1, Cases.DAYS.size() + 1):
		# EVERY WARD THIS DAY CAN DEAL, not every product of its slots. Two beds
		# on each ward are paired — exactly one of them is ill — so half the
		# cartesian product is a board the game cannot produce, including boards
		# with nobody ill on them at all, which no honest play can survive.
		var deals: Array = Cases.enumerate_draws(day)
		var total := deals.size()
		var worst := ""
		var lowest := 999999
		var verdicts := {}
		for deal in deals:
			var picks: Array = _picks_for(day, deal)
			var r := _play(day, picks)
			played += 1
			verdicts[String(r["verdict"])] = int(verdicts.get(String(r["verdict"]), 0)) + 1
			# NOT MERELY "NOT A DISASTER". This asked only that an honest day
			# never reached REFERRED, which is two indefensible beds — a bar so
			# low that the third ward spent its whole existence FLAGGED for the
			# play its own content is written to reward, and the check said
			# nothing. A day spent looking at everybody, writing up what you
			# found in your own name and keeping the people who need the bed is
			# either signed off or, at worst, a note; anything below that is a
			# ward that punishes the play it teaches.
			if String(r["verdict"]) == ReviewSystem.OUTCOME_ESCALATED \
					or String(r["verdict"]) == ReviewSystem.OUTCOME_FLAGGED:
				_fail("ward %d %s -> %s for an honest day"
					% [day, str(r["who"]), String(r["verdict"])])
			if int(r["paid"]) < lowest:
				lowest = int(r["paid"])
				worst = "%s (%s, %d held)" % [str(r["who"]), r["verdict"], int(r["kept"])]
			if int(r["paid"]) < Cases.DEBT_DUE:
				_fail("ward %d %s -> honest day pays only %d, he wants %d"
					% [day, str(r["who"]), int(r["paid"]), Cases.DEBT_DUE])
		var tally: Array = []
		for v in verdicts:
			tally.append("%d %s" % [int(verdicts[v]), String(v)])
		print("  ward %d: %d deals, all worked (%s), thinnest %d — %s"
			% [Cases.pool_index(day) + 1, total, ", ".join(PackedStringArray(tally)),
				lowest, worst])
	_check_the_draw_is_actually_random()
	print("")
	if bad == 0:
		print("DRAW CHECK PASSED — %d deals, every one of them playable" % played)
	else:
		print("DRAW CHECK FAILED — %d problems over %d deals" % [bad, played])

## AND THAT THE DEAL IS ACTUALLY A DEAL.
##
## Every combination being PLAYABLE is worth nothing if the game only ever deals
## two of them, and that is twice what happened. First the pick was
## `hash(slot) ^ seed`, whose bottom bit — the only bit that matters when a slot
## has two candidates — is the seed's bottom bit, so every slot flipped together
## and there were two careers: odd seeds and even seeds. Then it was a hash of
## the combined string, and Godot's String hash does not reach the bottom bit
## well enough to fix it. Both looked completely fine in the game, in the tests,
## and in the data check. The only thing that showed either of them was counting
## distinct wards across a lot of seeds, so that is now a check rather than
## something somebody thought to do once.
func _check_the_draw_is_actually_random() -> void:
	Cases.forced_picks = []
	var was: int = GameState.seed_value
	var careers := {}
	var per_ward := {}
	for s in range(1, 2001):
		GameState.seed_value = s
		var key := ""
		for d in range(1, Cases.DAYS.size() + 1):
			var ids := []
			for c in Cases.draw_five(d):
				ids.append(String(c["id"]))
			var wk := ",".join(ids)
			key += wk + "|"
			# BY WARD, NOT BY NIGHT. The rotation is a per-career permutation,
			# so "night three" is four different wards across a seed sweep and
			# grouping by it counts each ward's deals against another ward's
			# total. This check exists because the draw has silently stopped
			# being a draw twice; a version of it that groups by the wrong key
			# is the third way for that to happen.
			var w: int = Cases.pool_index(d)
			if not per_ward.has(w):
				per_ward[w] = {}
			per_ward[w][wk] = true
		# ...and the ORDER is drawn too, so it belongs in the career key.
		var order: Array = []
		for d in range(1, Cases.DAYS.size() + 1):
			order.append(Cases.pool_index(d))
		key += str(order)
		careers[key] = true
	GameState.seed_value = was
	for w in range(Cases.DAYS.size()):
		var possible: int = Cases.enumerate_pool(w).size()
		var got: int = Dictionary(per_ward.get(w, {})).size()
		if got < possible:
			_fail("ward %d deals only %d of its %d possible wards in 2000 seeds"
				% [w + 1, got, possible])
	# AND THE ORDER ITSELF IS ACTUALLY DRAWN. A permutation that comes out the
	# same every career is the old constant with more code in front of it, and
	# it would look identical in the game, in the tests and in the deal counts
	# above — which is exactly how the slot draw failed twice.
	var orders := {}
	var first_cycle_complete := true
	for s2 in range(1, 2001):
		GameState.seed_value = s2
		var o: Array = []
		for d in range(1, Cases.DAYS.size() + 1):
			o.append(Cases.pool_index(d))
		orders[str(o)] = true
		var seen := {}
		for i in o:
			seen[i] = true
		if seen.size() != Cases.DAYS.size():
			first_cycle_complete = false
	GameState.seed_value = was
	var want_orders := 1
	for i in range(2, Cases.DAYS.size() + 1):
		want_orders *= i
	if orders.size() < want_orders:
		_fail("the ward order takes only %d of its %d permutations over 2000 seeds"
			% [orders.size(), want_orders])
	if not first_cycle_complete:
		_fail("a career's first %d nights do not visit every ward" % Cases.DAYS.size())
	print("  the ward order takes all %d permutations, every career visiting all %d wards"
		% [orders.size(), Cases.DAYS.size()])
	print("  %d distinct careers over 2000 seeds, every combination reachable"
		% careers.size())
