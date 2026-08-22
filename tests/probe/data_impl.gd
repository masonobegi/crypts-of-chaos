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
		var roster: Array = Cases.roster(day + 1)
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
			if beds.has(int(c["bed"])):
				_fail("ward %d has two patients in bed %d" % [day + 1, int(c["bed"])])
			beds[int(c["bed"])] = true
			if not well:
				unwell += 1
			if int(c["tier"]) == Cases.Tier.PREMIUM:
				premium += 1
			# A family rule that fires needs somebody to name.
			if bool(c.get("family_reads_charts", false)) and not c.has("family"):
				_fail("ward %d / %s / family" % [day + 1, id])
			# ...and a social hold needs its own reason, or the note is generic.
			if bool(c.get("no_care_at_home", false)) and not c.has("social_reason"):
				_fail("ward %d / %s / social_reason" % [day + 1, id])
		if beds.size() != Cases.BEDS:
			_fail("ward %d has %d beds, not %d" % [day + 1, beds.size(), Cases.BEDS])
		if unwell < 1:
			_fail("ward %d has nobody who genuinely needs a bed" % (day + 1))
		print("  ward %d: %d people, %d genuinely unwell, %d premium, prior notes %d"
			% [day + 1, roster.size(), unwell, premium, Cases.prior_entries(day + 1).size()])

		# THE LOAD-BEARING INEQUALITY, on every ward: holding all five must earn
		# less than holding three, or "keep everybody" is the answer.
		var w := WardDay.new()
		tree.root.add_child(w)
		w.start()
		for c in roster:
			w.set_disposition(String(c["id"]), "hold")
		var five: int = int(w.projected()["earned"])
		for c in roster:
			w.set_disposition(String(c["id"]), "discharge")
		var best_three := 0
		for i in roster.size():
			for j in range(i + 1, roster.size()):
				for k in range(j + 1, roster.size()):
					for c in roster:
						w.set_disposition(String(c["id"]), "discharge")
					for x in [i, j, k]:
						w.set_disposition(String(roster[x]["id"]), "hold")
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
