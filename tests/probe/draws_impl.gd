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
	for c in roster:
		var pid := String(c["id"])
		w.set_disposition(pid, "hold" if keep.has(pid) else "discharge")
	var res := w.end_day()
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
		for deal in deals:
			var picks: Array = _picks_for(day, deal)
			var r := _play(day, picks)
			played += 1
			if String(r["verdict"]) == ReviewSystem.OUTCOME_ESCALATED:
				_fail("ward %d %s -> REFERRED for an honest day" % [day, str(r["who"])])
			if int(r["paid"]) < lowest:
				lowest = int(r["paid"])
				worst = "%s (%s, %d held)" % [str(r["who"]), r["verdict"], int(r["kept"])]
			if int(r["paid"]) < Cases.DEBT_DUE:
				_fail("ward %d %s -> honest day pays only %d, he wants %d"
					% [day, str(r["who"]), int(r["paid"]), Cases.DEBT_DUE])
		print("  ward %d: %d deals, all worked, thinnest %d — %s"
			% [day, total, lowest, worst])
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
			if not per_ward.has(d):
				per_ward[d] = {}
			per_ward[d][wk] = true
		careers[key] = true
	GameState.seed_value = was
	for d in range(1, Cases.DAYS.size() + 1):
		var possible: int = Cases.enumerate_draws(d).size()
		var got: int = Dictionary(per_ward[d]).size()
		if got < possible:
			_fail("ward %d deals only %d of its %d possible wards in 2000 seeds"
				% [d, got, possible])
	print("  %d distinct careers over 2000 seeds, every combination reachable"
		% careers.size())
