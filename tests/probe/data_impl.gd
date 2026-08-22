extends RefCounted
## EVERY AUTHORED PERSON, CHECKED. Fifteen patients across three wards, each
## with a readmission of their own, and every one of them is read by half a
## dozen systems that will silently print an empty string or fall back to a
## default if a field is missing. The tests assert the properties; this asserts
## the DATA, which is where content bugs live.
var tree: SceneTree = null
var bad := 0

func _fail(m: String) -> void:
	bad += 1
	print("  MISSING: " + m)

func run() -> void:
	var required := ["id", "name", "age", "bed", "condition", "tier", "truly_well",
		"suggestible", "recall", "summary", "opening", "later", "evening",
		"pressed", "on_your_note", "on_hold", "on_discharge", "note",
		"readmit_summary", "readmit_opening", "readmit_hold", "readmit_discharge",
		"readmit_exam"]
	var seen_ids := {}
	print("\n=== AUTHORED DATA — %d wards ===" % Cases.DAYS.size())
	for day in Cases.DAYS.size():
		GameState.day = day + 1
		# EVERY AUTHORED PERSON ON THE WARD, not the five in the beds tonight. A
		# ward is a draw from a pool now, so checking the roster checks whichever
		# five the seed happened to pick and leaves the alternates unread — which
		# is exactly the shape of content bug this file exists to catch.
		var roster: Array = Cases.pool_for(day + 1)
		var beds := {}
		var unwell := 0
		var premium := 0
		for c in roster:
			var id := String(c.get("id", "?"))
			for k in required:
				if not c.has(k) or (typeof(c[k]) == TYPE_STRING and String(c[k]).strip_edges() == ""):
					_fail("ward %d / %s / %s" % [day + 1, id, k])
			# The examination has to say SOMETHING, and which one depends on them.
			var well: bool = bool(c.get("truly_well", true))
			if well and not c.has("exam_well"):
				_fail("ward %d / %s / exam_well" % [day + 1, id])
			if not well and not c.has("exam_unwell"):
				_fail("ward %d / %s / exam_unwell" % [day + 1, id])
			if seen_ids.has(id):
				_fail("id %s appears on two wards" % id)
			seen_ids[id] = true
			# `bed` is the SLOT id, and several authored people can share one —
			# exactly one of them is in it on any given night. What has to be
			# true is that every slot has a candidate, not that every candidate
			# has a slot to itself.
			if not beds.has(int(c["bed"])):
				beds[int(c["bed"])] = []
			beds[int(c["bed"])].append(c)

			# A family rule that fires needs somebody to name.
			if bool(c.get("family_reads_charts", false)) and not c.has("family"):
				_fail("ward %d / %s / family" % [day + 1, id])
			# ...and a social hold needs its own reason, or the note is generic.
			if bool(c.get("no_care_at_home", false)) and not c.has("social_reason"):
				_fail("ward %d / %s / social_reason" % [day + 1, id])
		if beds.size() != Cases.BEDS:
			_fail("ward %d has %d slots, not %d" % [day + 1, beds.size(), Cases.BEDS])

		# INTERCHANGEABLE MEANS INTERCHANGEABLE. Two people can share a slot only
		# if swapping one for the other leaves the ward the same shape: same
		# tier, so the night is worth the same money, and same truth, so the
		# honest hold is still where the ward says it is. Without this a draw
		# could quietly produce a ward with no genuinely ill patient on it, or
		# turn a premium temptation into a state bed, and the careful economy
		# every other check defends would depend on a hash.
		for b in beds:
			var cands: Array = beds[b]
			var t0: int = int(cands[0]["tier"])
			var w0: bool = bool(cands[0].get("truly_well", true))
			for alt in cands:
				if int(alt["tier"]) != t0:
					_fail("ward %d slot %d: %s is a different tier from %s"
						% [day + 1, int(b), String(alt["id"]), String(cands[0]["id"])])
				if bool(alt.get("truly_well", true)) != w0:
					_fail("ward %d slot %d: %s is not as ill as %s"
						% [day + 1, int(b), String(alt["id"]), String(cands[0]["id"])])
			if not w0:
				unwell += 1
			if t0 == Cases.Tier.PREMIUM:
				premium += 1
		if unwell < 1:
			_fail("ward %d has nobody who genuinely needs a bed" % (day + 1))
		var combos := 1
		for b in beds:
			combos *= Array(beds[b]).size()
		print("  ward %d: %d authored, %d slots, %d combinations, %d genuinely unwell, %d premium"
			% [day + 1, roster.size(), beds.size(), combos, unwell, premium])

		# THE LOAD-BEARING INEQUALITY, on every ward: holding all five must earn
		# less than holding three, or "keep everybody" is the answer.
		var w := WardDay.new()
		tree.root.add_child(w)
		w.start()
		var tonight: Array = Cases.roster(day + 1)
		for c in tonight:
			w.set_disposition(String(c["id"]), "hold")
		var five: int = int(w.projected()["earned"])
		for c in tonight:
			w.set_disposition(String(c["id"]), "discharge")
		var best_three := 0
		for i in tonight.size():
			for j in range(i + 1, tonight.size()):
				for k in range(j + 1, tonight.size()):
					for c in tonight:
						w.set_disposition(String(c["id"]), "discharge")
					for x in [i, j, k]:
						w.set_disposition(String(tonight[x]["id"]), "hold")
					best_three = maxi(best_three, int(w.projected()["earned"]))
		if five >= best_three:
			_fail("ward %d: holding five earns %d, three earns %d" % [day + 1, five, best_three])
		else:
			print("      five beds %d < best three %d" % [five, best_three])
		tree.root.remove_child(w)
		w.free()
	GameState.day = 1
	print("")
	if bad == 0:
		print("DATA CHECK PASSED — %d authored people, all complete" % seen_ids.size())
	else:
		print("DATA CHECK FAILED — %d problems" % bad)
