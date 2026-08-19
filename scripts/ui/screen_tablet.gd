extends ScreenBase
## Your tablet. Deliberately UNRELIABLE: the suspicion percentages are your
## character's estimate, and for people you have not spoken to recently they are
## systematically wrong. Confidently wrong information is more interesting than
## no information.

var _tab := "ward"

func _build() -> void:
	var v := shell(920, 800, "Tablet", "Day %d · %s" % [GameState.day, GameState.time_string()])
	var tabs := UIKit.hbox(6)
	for t in [["ward", "Ward"], ["people", "People"], ["money", "Money"], ["codex", "Notes"]]:
		var key := String(t[0])
		tabs.add_child(UIKit.button(String(t[1]), func(): _switch(key),
			UIKit.PANEL_LIGHT if _tab != key else Color(0.20, 0.35, 0.38)))
	v.add_child(tabs)
	v.add_child(UIKit.rule())

	var content := UIKit.vbox(8)
	match _tab:
		"ward": _build_ward(content)
		"people": _build_people(content)
		"money": _build_money(content)
		"codex": _build_codex(content)
	v.add_child(UIKit.scroll(content))
	v.add_child(UIKit.button("Close", close))

func _switch(t: String) -> void:
	_tab = t
	rebuild()

func _build_ward(c: VBoxContainer) -> void:
	var ps = patient_system()
	if ps == null:
		return
	var list: Array = ps.active()
	if list.is_empty():
		c.add_child(UIKit.label("No patients admitted.", 15, UIKit.INK_DIM))
		return
	for p in list:
		var box := UIKit.panel(Color(0.14, 0.17, 0.19, 0.93), 6)
		var bv := UIKit.vbox(3)
		bv.add_child(UIKit.row(p.display_name, p.condition_name(), UIKit.ACCENT, 17))
		bv.add_child(UIKit.row("Room", String(p.room).replace("ward_", "Room ")))
		bv.add_child(UIKit.row("Day of stay", "%d of %d projected" % [
			int(ceil(p.days_admitted)), int(ceil(p.expected_stay_days))],
			UIKit.WARN if p.is_overdue() else UIKit.INK))
		bv.add_child(UIKit.row("Impression", p.apparent_state()))
		bv.add_child(UIKit.row("Billing", "%s/day" % UIKit.money_str(p.daily_revenue()), UIKit.MONEY))
		bv.add_child(UIKit.row("Insurance", DB.insurance_name(p.insurance)))
		bv.add_child(UIKit.row("Personality", DB.archetype_name(p.archetype)))
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
		var box := UIKit.panel(Color(0.14, 0.16, 0.19, 0.93), 6)
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
			var shown := 0
			for ev in m.evidence:
				if shown >= 3:
					break
				var w := ev.current_weight(GameState.career_minutes)
				if w < 0.02:
					continue
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
			var box := UIKit.panel(Color(0.14, 0.16, 0.19, 0.93), 6)
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
