extends RefCounted
## ADVERSARIAL SEARCH. The twenty-three hand-written strategies in
## playtest_impl.gd test the plays a designer thought of, which is exactly the
## set of plays that will not contain the exploit. This enumerates instead:
## every subset of beds worth holding, crossed with every way of justifying a
## hold, crossed with three ways of answering in the room, and reports the
## money/exposure frontier — so a dominant strategy has to hide from a search
## rather than from an author.
var tree: SceneTree = null
var C = ChartEntry.Claim
var A = ReviewSystem.Answer

## The justifications, and the minute each is performed at. 17:30 is ninety
## minutes clear of the 16:00 and 19:00 rounds; 19:00 is on top of one.
const JUSTIFY := ["nothing", "gap_note", "round_note", "backdate", "lead",
	"nurse", "test_late", "social"]

func _day() -> WardDay:
	GameState.set_flag("remembered_beds", PackedStringArray())
	GameState.set_flag("watched", false)
	GameState.minute_of_day = 8 * 60
	var w := WardDay.new(); tree.root.add_child(w); w.start(); return w

func _justify(w: WardDay, pid: String, how: String) -> void:
	match how:
		"nothing":
			pass
		"gap_note":
			w.advance_to(17 * 60 + 20)
			w.write_entry(pid, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)
		"round_note":
			w.advance_to(19 * 60)
			w.write_entry(pid, C.UNWELL, "Unsettled this evening.", 19 * 60)
		"backdate":
			w.advance_to(19 * 60 + 30)
			w.write_entry(pid, C.UNWELL, "Unsettled this evening.", 17 * 60)
		"lead":
			w.advance_to(17 * 60 + 20)
			w.ask_patient(pid, "feeling faint this evening")
		"nurse":
			w.advance_to(17 * 60)
			w.nurse_check(pid)
		"test_late":
			w.advance_to(15 * 60)
			w.write_entry(pid, C.UNWELL, "Unsettled.", 14 * 60 + 55)
			var o := w.order_test(pid, "lying and standing BP")
			w.advance_to(17 * 60 + 30)
			w.resolve_test(o)
		"social":
			w.advance_to(17 * 60 + 20)
			w.write_entry(pid, C.SOCIAL, "No care at home. Awaiting social work.", 17 * 60 + 18)

func _answer_policy(name: String) -> Callable:
	match name:
		"stand": return func(_f, _o): return A.STAND_BY
		"fold": return func(_f, _o): return A.DEFER
	# "best available": take the strongest thing she has left you.
	return func(_f, opts):
		for want in [A.RECONCILE, A.POINT_AT_NURSE, A.WROTE_IT_LATE]:
			for o in opts:
				if int(o["a"]) == want: return want
		return A.STAND_BY

func run() -> void:
	GameState.start_new_career(31337)
	var ids: Array = []
	for c in Cases.ROSTER: ids.append(String(c["id"]))
	var rows: Array = []
	# Every non-empty subset of the five beds, up to four held (holding all
	# five earns less than holding fewer — the admissions cover it).
	for mask in range(1, 32):
		var held: Array = []
		for i in ids.size():
			if mask & (1 << i): held.append(ids[i])
		# Four and five beds earn LESS than three: the empty beds admit, and an
		# admission pays more than a night. Searching them is 200 runs spent
		# proving a piece of arithmetic that has its own test.
		if held.size() > 3:
			continue
		# One justification style applied to every held bed, which is what a
		# player converging on a strategy actually does.
		for how in JUSTIFY:
			for pol in ["stand", "best"]:
				rows.append(_run(held, how, pol))
	rows.sort_custom(func(a, b): return int(a["cash"]) > int(b["cash"]))

	print("\n=== ADVERSARIAL FRONTIER — %d strategies ===" % rows.size())
	# The pareto front: for each verdict, the most money anybody made reaching it.
	var best := {}
	for r in rows:
		var v := String(r["verdict"])
		if not best.has(v) or int(r["cash"]) > int(best[v]["cash"]):
			best[v] = r
	print("\n--- the most money made at each verdict ---")
	for v in [ReviewSystem.OUTCOME_CLEAR, ReviewSystem.OUTCOME_QUESTIONS,
			ReviewSystem.OUTCOME_FLAGGED, ReviewSystem.OUTCOME_ESCALATED]:
		if not best.has(v):
			print("  %-18s never reached" % v)
			continue
		var r = best[v]
		print("  %-18s %6d   %-26s %-10s %s" % [v, r["cash"],
			",".join(PackedStringArray(r["held"])), r["how"], r["pol"]])

	# THE QUESTION THAT MATTERS: is there a strategy that makes more money than
	# the best clean day AND is not punished for it?
	var clean: int = int(best[ReviewSystem.OUTCOME_CLEAR]["cash"]) if best.has(ReviewSystem.OUTCOME_CLEAR) else -99999
	var noted: int = int(best[ReviewSystem.OUTCOME_QUESTIONS]["cash"]) if best.has(ReviewSystem.OUTCOME_QUESTIONS) else -99999
	print("\n--- is the frontier real? ---")
	print("  best signed-off day: %d" % clean)
	print("  best noted day:      %d  (+%d for a bed on the file)" % [noted, noted - clean])
	var top: Dictionary = rows[0]
	print("  most money anybody made: %d, and it was %s (%s / %s)"
		% [top["cash"], top["verdict"], top["how"], top["pol"]])
	var top_clean := true
	for r in rows:
		if int(r["cash"]) == int(top["cash"]) and String(r["verdict"]) == ReviewSystem.OUTCOME_CLEAR:
			top_clean = true
			break
		top_clean = false
	print("  can the top figure be reached signed off? %s" % ("YES — DOMINANT STRATEGY" if top_clean else "no"))

func _run(held: Array, how: String, pol: String) -> Dictionary:
	var w := _day()
	for c in Cases.ROSTER:
		var pid := String(c["id"])
		if held.has(pid):
			# Ivo Marchetti is genuinely unwell and the night round already says
			# so; justifying him further is a different act from justifying
			# somebody who is well, so the search does both.
			_justify(w, pid, how)
			w.set_disposition(pid, "hold")
		else:
			w.set_disposition(pid, "discharge")
	var res := w.end_day()
	var rv := ReviewSystem.new()
	rv.begin(res["findings"], w.records.entries, w.review_truth())
	var chooser := _answer_policy(pol)
	while not rv.finished():
		var f = rv.current()
		rv.answer(int(chooser.call(f, rv.options(f, w.records))), res["held"])
	var o := rv.outcome()
	var row := {
		"cash": int(res["cash"]), "verdict": String(o["verdict"]),
		"held": held, "how": how, "pol": pol,
		"indef": int(o["indefensible"]), "solo": int(o["solo"]),
	}
	# free(), not queue_free(): a --script main loop runs no frames, so a queued
	# node is never actually collected and six hundred wards stay in memory
	# with their signals still connected to GameState.
	tree.root.remove_child(w)
	w.free()
	return row
