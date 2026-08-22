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
## `own_note` is the plainest honest act in the game — go and look, then write
## what you found, in the morning, in your own name — and it was not in this
## list. Every "write it yourself" strategy here wrote at twenty past five or
## seven in the evening, which is the CRIME shape: a note that appears hours
## after the round it claims to describe. A search with no honest note in it
## cannot find an honest day, and on the fourth ward it did not.
const JUSTIFY := ["nothing", "gap_note", "round_note", "backdate", "lead",
	"nurse", "test_late", "social", "examine", "colleague", "colleague_note",
	"own_note"]

func _day() -> WardDay:
	# Including the debt. A search whose later rows owe more than its earlier
	# ones is not searching one game, it is searching several.
	GameState.set_flag("remembered_beds", PackedStringArray())
	GameState.set_flag("carried_debt", 0)
	# ...AND THE READMISSIONS. This was cleared once per WARD and written by any
	# run in which somebody bounced, so every strategy after the first wrongful
	# discharge searched a DIFFERENT roster from the ones before it — the ward
	# it thought it was exploring had a readmitted patient in a bed, earning
	# nothing. The results moved between identical runs and the ward-four
	# numbers changed shape twice while nothing about the ward changed. Same
	# lesson as CLAUDE.md 16: a harness that reuses GameState clears ALL of the
	# carry or none of it.
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.reset_debt()
	DoctorRecord.wipe()
	GameState.set_flag(Cases.READMIT_FLAG, [])
	GameState.set_flag("watched", false)
	GameState.set_flag("auditor_present", false)
	GameState.minute_of_day = 8 * 60
	# NOT the day. `_search` owns which ward this is.
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
		## THE TWO NEW VERBS, and the obvious abuse of the second one: ask the
		## registrar and then write over him if you do not like the answer.
		"examine":
			w.examine(pid)
		"own_note":
			w.examine(pid)
			w.advance_to(maxi(w.minute, 10 * 60))
			w.write_entry(pid, C.UNWELL,
				"Reviewed at the bedside. Not fit for discharge today.", w.minute)
		"colleague":
			w.advance_to(11 * 60 + 10)
			w.ask_colleague(pid)
		"colleague_note":
			w.advance_to(11 * 60 + 10)
			w.ask_colleague(pid)
			w.advance_to(17 * 60 + 20)
			w.write_entry(pid, C.UNWELL, "Unsettled this evening.", 17 * 60 + 18)

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
	for day in range(1, Cases.DAYS.size() + 1):
		_search(day)

func _search(day: int) -> void:
	GameState.day = day
	# No readmissions from a previous search, or the roster this search thinks
	# it is exploring is not the roster it gets.
	GameState.set_flag(Cases.READMIT_FLAG, [])
	var ids: Array = []
	for c in Cases.roster(day): ids.append(String(c["id"]))
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
		# One justification style applied to every held bed — and then the same
		# again MIXED, which is what somebody who has understood the game does:
		# get a peer behind the bed that deserves one and write your own note on
		# the bed that does not. A search that only applies one verb to the
		# whole ward cannot see that strategy at all, and on the second ward it
		# is the entire middle of the risk curve.
		for how in JUSTIFY:
			for pol in ["stand", "best"]:
				rows.append(_run(held, how, pol, false))
				rows.append(_run(held, how, pol, true))
				# ...AND THE SAME AGAIN DONE DILIGENTLY.
				#
				# The search could not reach a signed-off day on the fourth ward
				# in eleven hundred strategies, and reported that as a property
				# of the ward. It is a property of the SEARCH: every strategy in
				# here decided three beds without opening a chart, so
				# `never_laid_eyes_on_them` was live in all of them, and none of
				# them ordered a test early enough for the result to land before
				# the decision. A day played properly was not in the space, so
				# the probe could not tell honest play apart from impossible.
				rows.append(_run(held, how, pol, true, true))
				# ...and diligently WITHOUT the mixed routing, because mixed
				# spends the registrar on every genuinely unwell bed, and on the
				# fourth ward the registrar is the trap. A search in which every
				# careful strategy walks into the same trap reports the ward as
				# unwinnable.
				rows.append(_run(held, how, pol, false, true))
	rows.sort_custom(func(a, b): return int(a["cash"]) > int(b["cash"]))

	print("\n=== ADVERSARIAL FRONTIER — WARD %d — %d strategies ===" % [day, rows.size()])
	# The pareto front: for each verdict, the most money anybody made reaching it.
	var best := {}
	for r in rows:
		var v := String(r["verdict"])
		if not best.has(v) or int(r["cash"]) > int(best[v]["cash"]):
			best[v] = r
	print("\n--- the biggest night at each verdict ---")
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
	print("  best signed-off night: %d" % clean)
	if clean <= -99999:
		print("  best noted night:      %d  (no clean day exists on this ward)" % noted)
	else:
		print("  best noted night:      %d  (+%d for a bed on the file)" % [noted, noted - clean])
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

func _run(held: Array, how: String, pol: String, mixed := false,
		diligent := false) -> Dictionary:
	var w := _day()
	# A DAY PLAYED PROPERLY. Bloods on every bed you intend to keep, ordered at
	# five past eight so the result is back by half nine; then a look at
	# everybody, so that nothing on the ward is decided by somebody who never
	# opened the file. Both cost minutes and both are ordinary play.
	if diligent:
		for pid in held:
			w.order_test(String(pid), "Repeat bloods")
		for c in Cases.roster():
			var pid := String(c["id"])
			if held.has(pid):
				w.examine(pid)
			else:
				w.read_chart(pid)
		w.advance_to(maxi(w.minute, 10 * 60))
	for c in Cases.roster():
		var pid := String(c["id"])
		if held.has(pid):
			# In MIXED mode the player has walked round and knows who is
			# genuinely unwell, and spends the registrar on those beds — which
			# is knowledge the examination verb genuinely buys, not cheating.
			var verb := how
			if mixed and not bool(c.get("truly_well", true)):
				w.examine(pid)
				verb = "colleague"
			_justify(w, pid, verb)
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
		# WHAT THE NIGHT WAS WORTH, which since the debt got a term is what he
		# took rather than what is left over — he takes everything, so the
		# leftover is zero on every night that does not finish the game and
		# ranking by it made all 2,200 strategies look identical.
		"cash": int(res["paid"]), "verdict": String(o["verdict"]),
		"held": held,
		"how": ("diligent+" if diligent else "") + (("mixed+" + how) if mixed else how),
		"pol": pol,
		"indef": int(o["indefensible"]), "solo": int(o["solo"]),
	}
	# free(), not queue_free(): a --script main loop runs no frames, so a queued
	# node is never actually collected and six hundred wards stay in memory
	# with their signals still connected to GameState.
	tree.root.remove_child(w)
	w.free()
	return row
