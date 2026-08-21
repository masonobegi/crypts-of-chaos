extends ScreenBase
## Your tablet. Deliberately UNRELIABLE: the suspicion percentages are your
## character's estimate, and for people you have not spoken to recently they are
## systematically wrong. Confidently wrong information is more interesting than
## no information.

var _tab := "ward"

func _build() -> void:
	# Openable straight onto a tab, so the shift objective and the screenshot
	# harness can both point at the list rather than at the ward.
	if ctx.has("tab") and _tab == "ward":
		_tab = String(ctx["tab"])
	var v := shell(920, 800, "Tablet", "Day %d · %s" % [GameState.day, GameState.time_string()])
	var tabs := UIKit.hbox(6)
	for t in [["list", "List"], ["ward", "Ward"], ["people", "People"],
			["record", "Record"], ["money", "Money"], ["codex", "Notes"]]:
		var key := String(t[0])
		tabs.add_child(UIKit.button(String(t[1]), func(): _switch(key),
			UIKit.PANEL_LIGHT if _tab != key else Color(0.20, 0.35, 0.38)))
	v.add_child(tabs)
	v.add_child(UIKit.rule())

	var content := UIKit.vbox(8)
	match _tab:
		"list": _build_list(content)
		"ward": _build_ward(content)
		"people": _build_people(content)
		"record": _build_record(content)
		"money": _build_money(content)
		"codex": _build_codex(content)
	v.add_child(UIKit.scroll(content))
	v.add_child(UIKit.button("Close", close))

func _switch(t: String) -> void:
	_tab = t
	rebuild()

## Today's booked work. Without this the list existed only as a line in the
## morning briefing and a single objective string, which is not enough to plan a
## shift around — and planning the shift is the whole point of having one.
func _build_list(c: VBoxContainer) -> void:
	var appts = get_tree().get_first_node_in_group("appointment_system")
	if appts == null or appts.list.is_empty():
		c.add_child(UIKit.label("Nothing booked.", 15, UIKit.INK_DIM))
		return
	c.add_child(UIKit.label(
		"%s shift · %d still to see" % [DB.shift_name(GameState.shift_kind),
			appts.remaining()], 14, UIKit.INK_DIM))
	var ps = patient_system()
	for a in appts.list:
		var kind := String(a["kind"])
		var box := UIKit.panel(UIKit.NOTE, 6)
		var bv := UIKit.vbox(3)
		var status := "waiting"
		var tint := UIKit.INK
		if bool(a["done"]):
			status = "seen"
			tint = UIKit.GOOD
		elif bool(a["missed"]):
			status = "not seen"
			tint = UIKit.BAD
		else:
			var late: int = appts.hours_late(int(a["hour"]))
			if late >= 1:
				status = "%dh late" % late
				tint = UIKit.WARN
			elif late < 0:
				status = "in %dh" % -late
				tint = UIKit.INK_DIM
		bv.add_child(UIKit.row("%s  %s" % [GameState.hour_string(int(a["hour"])),
			String(AppointmentSystem.LABELS.get(kind, kind))], status, tint, 16))
		bv.add_child(UIKit.row("  " + String(a["name"]), String(a["complaint"]),
			UIKit.INK_DIM, 13))
		# Where they actually are, so the list is navigable rather than a
		# reminder that somebody exists.
		var p = ps.get_patient(String(a["patient_id"])) if ps else null
		if p != null and not p.discharged:
			bv.add_child(UIKit.row("  Where",
				"treatment bay" if not p.admitted else String(p.room).replace("ward_", "Room "),
				UIKit.INK_DIM, 13))
			if not p.acquired_injuries().is_empty():
				bv.add_child(UIKit.row("  Acquired here",
					"%d" % p.acquired_injuries().size(), UIKit.BAD, 13))
		box.add_child(bv)
		c.add_child(box)
	c.add_child(UIKit.rule())
	c.add_child(UIKit.row("Fees booked so far",
		UIKit.money_str(_fees_earned(appts)), UIKit.MONEY))

func _fees_earned(appts) -> int:
	var total := 0
	for a in appts.list:
		if bool(a["done"]):
			total += int(AppointmentSystem.FEES.get(String(a["kind"]), 0))
	return total

func _build_ward(c: VBoxContainer) -> void:
	var ps = patient_system()
	if ps == null:
		return
	var list: Array = ps.active()
	if list.is_empty():
		c.add_child(UIKit.label("No patients admitted.", 15, UIKit.INK_DIM))
		return
	for p in list:
		var box := UIKit.panel(UIKit.NOTE, 6)
		var bv := UIKit.vbox(3)
		bv.add_child(UIKit.row(p.display_name, p.condition_name(), UIKit.ACCENT, 17))
		bv.add_child(UIKit.row("Room", String(p.room).replace("ward_", "Room ")))
		bv.add_child(UIKit.row("Day of stay", "%d of %d projected" % [
			int(ceil(p.days_admitted)), int(ceil(p.expected_stay_days))],
			UIKit.WARN if p.is_overdue() else UIKit.INK))
		bv.add_child(UIKit.row("Impression", p.apparent_state()))
		bv.add_child(UIKit.row("Billing", "%s/day" % UIKit.money_str(p.daily_revenue()), UIKit.MONEY))
		bv.add_child(UIKit.row("  your share", "%s/day" % UIKit.money_str(p.your_cut_per_day()),
			UIKit.MONEY))
		bv.add_child(UIKit.row("Insurance", DB.insurance_name(p.insurance)))
		bv.add_child(UIKit.row("Personality", DB.archetype_name(p.archetype)))
		for note in p.read_notes():
			bv.add_child(UIKit.label("  · " + note, 12, UIKit.INK_DIM,
				HORIZONTAL_ALIGNMENT_LEFT, true))
		# A colleague's outstanding request. Deliberately stated as a request and
		# not as a warning: what happens if you ignore it is for the player to
		# find out at clock-out.
		if p.imaging_requested():
			bv.add_child(UIKit.row(
				"Ordered" if p.imaging_requested_by == Patient.YOU else "Requested",
				"imaging, day %d" % p.imaging_requested_day, UIKit.WARN))
		elif _radiology_is_open() and not p.chart.imaging_done:
			# ORDERING ONE YOURSELF, which was not possible at all.
			#
			# The bench worked the outstanding-request list and nothing else, so
			# Radiology — which the player pays for — could only ever be used to
			# answer somebody else's question. Imaging is the one act in the game
			# that produces TRUTH: it can clear you in court, and it can put the
			# thing you did into a document you cannot edit. "Do I want to know,
			# and do I want it written down?" is the decision, and until now the
			# player was not allowed to have it.
			var who: String = p.id
			bv.add_child(UIKit.button("Order a scan", func(): _order_a_scan(who),
				UIKit.INK_DIM))
		for comp in p.active_complications():
			bv.add_child(UIKit.row("  " + comp.display_name,
				DB.cause_name(comp.documented_cause) if comp.documented_cause != "" else "NO CAUSE FILED",
				UIKit.GOOD if comp.documented_cause != "" else UIKit.BAD, 13))
		box.add_child(bv)
		c.add_child(box)

func _build_people(c: VBoxContainer) -> void:
	var sus = suspicion()
	if sus == null:
		return
	c.add_child(UIKit.label(
		"Your read on the room. You are not always right about this.", 13, UIKit.INK_DIM))
	var ranked: Array = sus.ranked_suspicions()
	if ranked.is_empty():
		c.add_child(UIKit.label("Nobody has anything on you.", 15, UIKit.GOOD))
		return
	for s in ranked:
		var m: Mind = sus.mind_of(String(s["id"]))
		var box := UIKit.panel(UIKit.NOTE, 6)
		var bv := UIKit.vbox(3)
		var r := UIKit.hbox(8)
		r.add_child(UIKit.label("%s" % String(s["name"]), 17, UIKit.INK))
		r.add_child(UIKit.spacer(0, false))
		r.add_child(UIKit.bar(float(s["value"]), UIKit.tier_color(int(s["tier"])), 170.0))
		r.add_child(UIKit.label("%d%%" % int(s["pct"]), 15, UIKit.tier_color(int(s["tier"]))))
		bv.add_child(r)
		bv.add_child(UIKit.label("%s · %s" % [String(s["role"]).capitalize(),
			DB.archetype_name(m.archetype) if m else ""], 13, UIKit.INK_DIM))
		if m:
			# The three WORST things they hold, not the three oldest.
			#
			# This iterated m.evidence in insertion order, and add_evidence()
			# appends. Institutional records decay at a hundredth of their
			# weight per day and are always listed, so the three oldest filings
			# an insurer ever made stayed above the display floor for a whole
			# career — and every statistic filed after them, including the ones
			# that were actually about to sink you, was unreachable on the only
			# screen that shows what anybody has on you.
			var by_weight: Array = []
			for ev in m.evidence:
				var wt := ev.current_weight(GameState.career_minutes)
				if wt < 0.02:
					continue
				by_weight.append({"ev": ev, "w": wt})
			by_weight.sort_custom(func(a, b): return float(a["w"]) > float(b["w"]))
			var shown := 0
			for row in by_weight:
				if shown >= 3:
					break
				var ev = row["ev"]
				shown += 1
				var txt := "· %s (%s)" % [ev.label(), ev.source_label()]
				if ev.neutralized:
					txt += " — explained away"
				if ev.corroborators.size() > 0:
					txt += " — corroborated"
				bv.add_child(UIKit.label(txt, 13,
					UIKit.INK_DIM if ev.neutralized else UIKit.WARN))
		box.add_child(bv)
		c.add_child(box)

## What an auditor would find if they pulled your charts right now.
##
## The same view as the end-of-shift review, but available at any moment — the
## whole point of the paperwork half of the game is being able to get in front
## of things, and you cannot do that if you only find out on your way home.
func _build_record(c: VBoxContainer) -> void:
	var rs = records()
	if rs == null:
		return
	var findings: Array = rs.pending_findings()
	var exposure: float = rs.total_exposure()

	var band := "Nothing to find."
	var colour := UIKit.GOOD
	if exposure > 2.2:
		band = "This would not survive an audit."
		colour = UIKit.BAD
	elif exposure > 1.0:
		band = "There is enough here to start something."
		colour = UIKit.WARN
	elif exposure > 0.25:
		band = "Minor gaps. Probably fine."
		colour = Color(0.58, 0.48, 0.05)

	var head := UIKit.panel(UIKit.NOTE, 6, 1, colour)
	var hv := UIKit.vbox(5)
	hv.add_child(UIKit.label(band, 17, colour))
	hv.add_child(UIKit.bar(clampf(exposure / 3.0, 0.0, 1.0), colour, 460.0, 10.0))
	head.add_child(hv)
	c.add_child(head)

	# Undocumented complications first — they are the most findable thing in a
	# record and the easiest to fix while the terminals are still on.
	var ps = patient_system()
	var undocumented: Array = []
	if ps:
		for p in ps.active():
			for comp in p.active_complications():
				if comp.documented_cause == "":
					undocumented.append({"patient": p.display_name, "comp": comp.display_name})
	if not undocumented.is_empty():
		c.add_child(UIKit.rule())
		c.add_child(UIKit.label("NO CAUSE FILED", 13, UIKit.INK_DIM))
		for u in undocumented:
			c.add_child(UIKit.row(String(u["patient"]), String(u["comp"]), UIKit.BAD))

	c.add_child(UIKit.rule())
	c.add_child(UIKit.label("FINDINGS", 13, UIKit.INK_DIM))
	if findings.is_empty():
		c.add_child(UIKit.label("Your records are consistent. Genuinely.", 15, UIKit.GOOD))
	for f in findings:
		var w := float(f["weight"])
		var fc := UIKit.WARN if w < 0.5 else UIKit.BAD
		var box := UIKit.panel(UIKit.NOTE, 6)
		var bv := UIKit.vbox(2)
		bv.add_child(UIKit.row(String(f["patient"]), String(f["kind"]).replace("_", " "), fc))
		bv.add_child(UIKit.label(String(f["text"]), 13, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(bv)
		c.add_child(box)

	# Device logs are records too, and are the thing players most reliably forget.
	var machine_rows: Array = []
	for f in get_tree().get_nodes_in_group("fixture"):
		if f is TreatmentMachine and not f.suspicious_log_entries().is_empty():
			machine_rows.append("%s — %d flagged run(s)" % [
				f.fixture_name, f.suspicious_log_entries().size()])
		elif f is Thermostat and not f.suspicious_log_entries().is_empty():
			machine_rows.append("%s — %d extreme setting(s)" % [
				f.fixture_name, f.suspicious_log_entries().size()])
	if not machine_rows.is_empty():
		c.add_child(UIKit.rule())
		c.add_child(UIKit.label("DEVICE LOGS", 13, UIKit.INK_DIM))
		for row in machine_rows:
			c.add_child(UIKit.label("· %s" % String(row), 13, UIKit.WARN))

func _build_money(c: VBoxContainer) -> void:
	c.add_child(UIKit.row("In your account", UIKit.money_str(GameState.personal_money),
		UIKit.MONEY if GameState.personal_money >= 0 else UIKit.BAD, 18))
	c.add_child(UIKit.row("Hospital funds", UIKit.money_str(GameState.hospital_money), UIKit.INK, 16))
	c.add_child(UIKit.rule())
	c.add_child(UIKit.label("DEBTS", 13, UIKit.INK_DIM))
	for d in GameState.debts:
		c.add_child(UIKit.row(String(d.get("name", "")),
			"%s  (%s/day)" % [UIKit.money_str(int(d.get("amount", 0))),
				UIKit.money_str(int(d.get("daily", 0)))],
			UIKit.BAD if int(d.get("missed", 0)) > 0 else UIKit.INK, 14))
	c.add_child(UIKit.rule())
	c.add_child(UIKit.row("Total owed", UIKit.money_str(GameState.total_debt()), UIKit.BAD, 16))
	c.add_child(UIKit.row("Daily outflow", UIKit.money_str(GameState.daily_debt_payment()), UIKit.WARN))
	var ps = patient_system()
	if ps:
		c.add_child(UIKit.row("Ward billing today", UIKit.money_str(ps.total_daily_revenue()), UIKit.MONEY))

func _build_codex(c: VBoxContainer) -> void:
	c.add_child(UIKit.label("THINGS YOU HAVE WORKED OUT", 13, UIKit.INK_DIM))
	if GameState.codex_unlocked.is_empty():
		c.add_child(UIKit.label(
			"Nothing yet. The game will not explain its systems to you — "
			+ "notes appear here once you have seen something happen twice.",
			14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var cdx = get_tree().get_first_node_in_group("codex")
	if cdx:
		for e in cdx.entries():
			var box := UIKit.panel(UIKit.NOTE, 6)
			var bv := UIKit.vbox(3)
			bv.add_child(UIKit.label(String(e["title"]), 16, UIKit.ACCENT))
			bv.add_child(UIKit.label(String(e["text"]), 13, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
			box.add_child(bv)
			c.add_child(box)
	c.add_child(UIKit.rule())
	c.add_child(UIKit.label("STANDING", 13, UIKit.INK_DIM))
	for track in GameState.reputation:
		var value := float(GameState.reputation[track])
		var r := UIKit.hbox(8)
		r.add_child(UIKit.label(String(track).replace("_", " ").capitalize(), 14, UIKit.INK_DIM))
		r.add_child(UIKit.spacer(0, false))
		r.add_child(UIKit.bar(value, UIKit.rep_color(String(track), value), 180.0))
		c.add_child(r)
	c.add_child(UIKit.rule())
	c.add_child(UIKit.row("Standing", GameState.SANCTIONS[GameState.sanction_level],
		UIKit.GOOD if GameState.sanction_level == 0 else UIKit.BAD))

## Book yourself a scan. The bench in Radiology works the outstanding list, so
## this is the whole of it — no cost, no confirmation, and no warning about what
## imaging tends to find, because the game does not tell the player what a thing
## will do to them before they do it.
func _order_a_scan(patient_id: String) -> void:
	var ps = patient_system()
	if ps == null:
		return
	var p = ps.get_patient(patient_id)
	if p == null or p.imaging_requested():
		return
	p.imaging_requested_by = Patient.YOU
	p.imaging_requested_day = GameState.day
	EventBus.toast.emit("%s is on the list for Radiology." % p.display_name, "info")
	rebuild()

func _radiology_is_open() -> bool:
	var h = get_tree().get_first_node_in_group("hospital")
	return h != null and h.has_method("is_room_open") and h.is_room_open("radiology")
