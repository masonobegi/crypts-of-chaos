extends RefCounted
## EVERY AUTHORED PERSON, CHECKED. Fifteen patients across three wards, each
## with a readmission of their own, and every one of them is read by half a
## dozen systems that will silently print an empty string or fall back to a
## default if a field is missing. The tests assert the properties; this asserts
## the DATA, which is where content bugs live.
var tree: SceneTree = null
var bad := 0

## THE THREE FLAGS THAT DECIDE HOW A TRUTH IS REACHED, and therefore what a ward
## IS. `only_visible_in_person` takes the patient away from the rounds, the
## nurse and the lab; `test_reveals` hands the lab back; `colleague_wrong` makes
## the registrar repeat his morning opinion in his own name instead of going to
## look. A ward's thesis is which of these its ill patient carries, so the two
## ends of a ward's ill-pair must carry the same ones or the thesis is a coin
## flip the player cannot see.
const DISCOVERY := ["only_visible_in_person", "test_reveals", "colleague_wrong"]

func _fail(m: String) -> void:
	bad += 1
	print("  MISSING: " + m)

func run() -> void:
	var required := ["id", "name", "age", "bed", "condition", "tier", "truly_well",
		"suggestible", "recall", "summary", "opening", "later", "evening",
		"pressed", "on_your_note", "on_hold", "on_discharge", "note",
		"readmit_summary", "readmit_opening", "readmit_hold", "readmit_discharge",
		"readmit_exam",
		# WHAT THE NIGHT WAS, if you kept them in it. Read by
		# `Cases.overnight_notes` onto the next morning's card. A patient without
		# one is a bed that goes silent the morning after — which is the whole
		# fault this field exists to fix, so it is required rather than defaulted.
		"overnight",
		# THE REST OF THE CONVERSATION, THE SECOND TIME ROUND. `readmission_of`
		# swaps these four in under the keys `WardDay.what_they_say` reads. It
		# used to ERASE them and restore `pressed` alone from `readmit_pressed`,
		# which was authored on nobody at all — so every readmitted patient in
		# the game, on every ward, had two things to say all day and shared one
		# of them with thirty-nine other people.
		"readmit_later", "readmit_evening", "readmit_pressed",
		"readmit_on_your_note"]
	var seen_ids := {}
	# SEED 0 IS THE CANONICAL GAME, and this file walks WARDS rather than
	# nights. The ward rotation is a per-career permutation now, so on any other
	# seed `pool_for(day + 1)` is not the ward whose prior-entry list and
	# ill-pair entry are indexed by `day` — and every check below pairs those
	# three together. Pinned rather than assumed, because nothing else in this
	# process sets it and a default is not a decision.
	GameState.seed_value = 0
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
		var pair_discovery: Array = []
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

			# AND THE READMISSION HAS TO BE A DIFFERENT CONVERSATION.
			#
			# Requiring the four keys above only proves they were typed. What
			# makes a readmission the strongest reversal in the game is that the
			# person in front of you has been through this once already, so a
			# `readmit_later` identical to `later` is the same silence with an
			# extra field in front of it. Checked through `readmission_of`
			# itself rather than against the raw dictionary, because that is the
			# function that decides which key wins and it is the one that used
			# to erase all four.
			var back := Cases.readmission_of(c)
			for k in ["later", "evening", "pressed", "on_your_note"]:
				if String(back.get(k, "")).strip_edges() == "":
					_fail("ward %d / %s / readmission says nothing when %s"
						% [day + 1, id, k])
				elif String(back.get(k, "")) == String(c.get(k, "")):
					_fail("ward %d / %s / readmitted %s is word for word the "
						% [day + 1, id, k] + "same as the first admission's")

			# A family rule that fires needs somebody to name.
			if bool(c.get("family_reads_charts", false)) and not c.has("family"):
				_fail("ward %d / %s / family" % [day + 1, id])
			# ...and a social hold needs its own reason, or the note is generic.
			if bool(c.get("no_care_at_home", false)) and not c.has("social_reason"):
				_fail("ward %d / %s / social_reason" % [day + 1, id])
		# EVERY AUTHORED PERSON WALKS IN WITH A NOTE ALREADY ON THEM.
		#
		# The prior-entry lists used to cover only the FIRST candidate in each
		# slot, so on any seed but zero up to four of the five beds opened with a
		# blank chart — nothing to write against, nothing for the audit to read,
		# and the whole record-versus-truth layer switched off for that bed. It
		# looked like nothing: the ward populated, the game played, every test
		# passed. Checked here rather than in the game because a missing note is
		# an absence, and an absence never throws.
		var noted := {}
		for pe in Cases.PRIOR_BY_DAY[day]:
			var who := String(pe["patient"])
			if noted.has(who):
				_fail("ward %d / %s has two handover notes" % [day + 1, who])
			noted[who] = true
			# `ChartEntry.Claim[...]` and `Author[...]` are looked up by NAME at
			# ward start, so a typo here is a runtime error inside a loop that
			# builds the chart — which, per gotcha 11, aborts the function and
			# leaves the ward silently half-charted.
			if not ChartEntry.Claim.has(String(pe.get("claim", ""))):
				_fail("ward %d / %s / claim %s is not a Claim"
					% [day + 1, who, String(pe.get("claim", ""))])
			if not ChartEntry.Author.has(String(pe.get("author", ""))):
				_fail("ward %d / %s / author %s is not an Author"
					% [day + 1, who, String(pe.get("author", ""))])
			if String(pe.get("author_id", "")).strip_edges() == "":
				_fail("ward %d / %s / handover note is unsigned" % [day + 1, who])
			if String(pe.get("text", "")).strip_edges() == "":
				_fail("ward %d / %s / handover note says nothing" % [day + 1, who])
			var mins := int(pe.get("minute", -1))
			if mins < 0 or mins >= Cases.DAY_START_MINUTE:
				_fail("ward %d / %s / handover note written at %d, not overnight"
					% [day + 1, who, mins])
		for c in roster:
			if not noted.has(String(c["id"])):
				_fail("ward %d / %s has no handover note" % [day + 1, String(c["id"])])
		for who in noted:
			var found := false
			for c in roster:
				if String(c["id"]) == String(who):
					found = true
			if not found:
				_fail("ward %d: handover note about %s, who is not on this ward"
					% [day + 1, String(who)])

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
			# TIER IS ALWAYS SHARED — that is what keeps the night worth the same
			# money whoever is in the bed. TRUTH is shared too, EXCEPT on the two
			# beds a ward declares as its pair: those two swap which of them is
			# ill, decided by one coin flip for the pair, so each of them must
			# offer both a well and an ill candidate. Bed one was the ill one on
			# three of the four wards and bed four on three, every career; a
			# second career still had you reading five charts to find something
			# you already knew.
			var pair = Cases.ILL_PAIR_BY_DAY.get(day + 1, [])
			var is_paired: bool = Array(pair).has(int(b))
			for alt in cands:
				if int(alt["tier"]) != t0:
					_fail("ward %d slot %d: %s is a different tier from %s"
						% [day + 1, int(b), String(alt["id"]), String(cands[0]["id"])])
				if not is_paired and bool(alt.get("truly_well", true)) != w0:
					_fail("ward %d slot %d: %s is not as ill as %s"
						% [day + 1, int(b), String(alt["id"]), String(cands[0]["id"])])
			if is_paired:
				# A paired bed has to be able to go either way, or the flip has
				# nothing to choose between and the pair silently does nothing.
				var has_ill := false
				var has_well := false
				for alt in cands:
					if bool(alt.get("truly_well", true)):
						has_well = true
					else:
						has_ill = true
				if not (has_ill and has_well):
					_fail("ward %d slot %d is paired but cannot go both ways"
						% [day + 1, int(b)])
				# AND BOTH ENDS OF THE PAIR MUST BE FOUND THE SAME WAY.
				#
				# Tier keeps the money the same and truth keeps the honest hold where
				# the ward says it is; neither says anything about HOW that truth is
				# reached, and that is the whole thesis of a ward. The second ward is
				# "a body the chart cannot describe" and the fourth is "somebody
				# else's decision", and each of them had its mechanic on exactly ONE
				# end of its pair: Lomax was `only_visible_in_person` and Ibarra was
				# not; Ashworth carried all three discovery flags and Castellanos
				# carried none. So on half of every career's nights on those two
				# wards — decided by a coin flip nobody can see — the ward played as
				# an ordinary read-the-chart ward with its premise switched off, and
				# `test_reveals` was authored on ONE person in the whole game who
				# appears on one side of one coin. Nothing could catch it: both ends
				# were the same tier, both could go both ways, and every authored
				# measurement in this repo plays seed 0.
				var ill_flags: Array = []
				for alt in cands:
					if bool(alt.get("truly_well", true)):
						continue
					var found: Array = []
					for k in DISCOVERY:
						if bool(alt.get(k, false)):
							found.append(k)
					ill_flags.append([String(alt["id"]), found])
				pair_discovery.append(ill_flags)
				# Exactly one of the pair is ill on any draw, so the ward's count
				# of genuinely ill people is unchanged by the flip. Counted once,
				# on the lower-numbered bed of the pair.
				if int(b) == mini(int(pair[0]), int(pair[1])):
					unwell += 1
			elif not w0:
				unwell += 1
			if t0 == Cases.Tier.PREMIUM:
				premium += 1
		# ...compared across the two beds, now that both have been walked.
		for i in pair_discovery.size():
			for j in range(i + 1, pair_discovery.size()):
				for a in pair_discovery[i]:
					for b2 in pair_discovery[j]:
						if Array(a[1]) == Array(b2[1]):
							continue
						_fail("ward %d: %s is found by [%s] and %s by [%s] — the two "
							% [day + 1, String(a[0]), ", ".join(PackedStringArray(a[1])),
								String(b2[0]), ", ".join(PackedStringArray(b2[1]))]
							+ "ends of a ward's pair must be found the same way")
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
		# AND EVERY BED CAN ACCOUNT FOR ITS OWN NIGHT. `overnight_notes` is what
		# the next morning's card renders, and it SKIPS anybody whose line is
		# missing or blank — so a patient with no `overnight` produces no error,
		# no warning and no row, and the bed you kept simply is not mentioned.
		# That silence is exactly the fault the field exists to end, which is why
		# it is counted here rather than trusted.
		var everyone_tonight := PackedStringArray()
		for c in tonight:
			everyone_tonight.append(String(c["id"]))
		var notes: Array = Cases.overnight_notes(Array(everyone_tonight))
		if notes.size() != everyone_tonight.size():
			_fail("ward %d: five beds held, %d overnight lines"
				% [day + 1, notes.size()])
		for line in notes:
			if not String(line).contains(" — "):
				_fail("ward %d: overnight line is unattributed: %s"
					% [day + 1, String(line)])

		tree.root.remove_child(w)
		w.free()
	GameState.day = 1

	# ---- WHO IS ALLOWED TO SOUND LIKE A NURSE.
	#
	# `Game._spawn_vinnie` and `_spawn_auditor` both build a `NurseNPC`, which
	# sets `role = "nurse"`, and every bark and behaviour in `StaffNPC` gated on
	# that string alone — so a loan shark walked to a bedside and said "Doing
	# nicely, this one." and Ms Ferrand from Coding said "I'll write that up."
	# Checked through the static predicate the three gates actually read, so it
	# needs no CharacterBody3D and no tree; and checked as CONTENT, because what
	# was wrong was never the code path, it was whose words came out of it.
	var speaks := {"nurse_0": true, "vinnie": false, "auditor": false}
	for who in speaks:
		var walks: bool = StaffNPC.rounds_for("nurse", String(who))
		if walks and not bool(speaks[who]):
			_fail("%s does bedside rounds and should not" % String(who))
		elif not walks and bool(speaks[who]):
			_fail("%s does no bedside rounds and should" % String(who))
	var wards_own: Array = []
	wards_own.append_array(StaffNPC.ROUND_OK)
	wards_own.append_array(StaffNPC.NOISE_BARK)
	for who in ["vinnie", "auditor"]:
		var bank: Dictionary = StaffNPC.VISITOR_BARKS.get(who, {})
		if bank.is_empty():
			_fail("%s has no voice of their own" % who)
			continue
		for kind in ["remark", "noise", "found"]:
			var lines: Array = Array(bank.get(kind, []))
			if lines.is_empty():
				_fail("%s has nothing to say when it is time to %s" % [who, kind])
			for l in lines:
				if String(l).strip_edges() == "":
					_fail("%s / %s / an empty line" % [who, kind])
				if wards_own.has(String(l)):
					_fail("%s says the ward's own line: %s" % [who, String(l)])
	# ...AND NOBODY NAMES A ROOM THAT DOES NOT EXIST. There are four rooms in
	# this building and none of them is numbered; `NurseNPC._ready` documents
	# that six were demolished. "Was that in 103?" sent players looking for a
	# wall.
	for l in wards_own:
		if String(l).contains("103"):
			_fail("a ward bark still names Room 103: %s" % String(l))
	print("  voices: Adeyemi does rounds, Vinnie and Ms Ferrand do not")

	# ...AND THE FRONT PAGE HAS TO SAY WHAT IS ACTUALLY IN THE BOX.
	#
	# The README is the store page. It said "forty authored patients across four
	# wards" when there are forty-three, "52 deals" when a career can reach 88,
	# "341 assertions" and "210 smoke checks" against 358 and 254, and "putting a
	# reader on the Credits screen is the one shipping item still open" about a
	# Licences screen that had been in the game for a day. Every one of those is
	# gotcha 15 in the file a buyer reads first, and the only one that could
	# possibly have been caught by a test is the one nobody would think to test.
	#
	# The three that are computable are checked. Digits, not words, in the
	# README, for exactly this reason.
	var readme := FileAccess.get_file_as_string("res://README.md")
	if readme == "":
		_fail("there is no README to check")
	else:
		var deals := 0
		for i in Cases.DAYS.size():
			deals += Cases.enumerate_pool(i).size()
		for claim in [["%d authored patients" % seen_ids.size(), "the head count"],
				["%d wards" % Cases.DAYS.size(), "the ward count"],
				["%d boards" % deals, "the board count"],
				["%d deals" % deals, "the board count again, in the test block"]]:
			if not readme.contains(String(claim[0])):
				_fail("the README does not say \"%s\" — %s has moved"
					% [String(claim[0]), String(claim[1])])
		print("  README: %d people, %d wards, %d boards — as advertised"
			% [seen_ids.size(), Cases.DAYS.size(), deals])

	print("")
	if bad == 0:
		print("DATA CHECK PASSED — %d authored people, all complete" % seen_ids.size())
	else:
		print("DATA CHECK FAILED — %d problems" % bad)
