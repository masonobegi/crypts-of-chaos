extends ScreenBase
## The morning. Debts come out, events land, patients arrive. This is where the
## pressure is set for the day before you have done anything.

func _build() -> void:
	var v := shift_brief()
	v.add_child(UIKit.button("Clock in", func():
		var ss = shift_system()
		if ss:
			ss.clock_in()
		close(), Color(0.16, 0.32, 0.30)))

func shift_brief() -> VBoxContainer:
	var v := shell(920, 800, "Day %d" % int(ctx.get("day", 1)),
		"%s · %s" % [String(ctx.get("sanction", "Clean")),
			"%d admitted" % int(ctx.get("census", 0))])

	var content := UIKit.vbox(10)

	# ---- the part that actually motivates the whole game
	var wallet := UIKit.panel(UIKit.NOTE_BAD, 6, 1, Color(0.5, 0.3, 0.3))
	var wv := UIKit.vbox(4)
	wv.add_child(UIKit.label("PERSONAL FINANCES", 13, UIKit.INK_DIM))
	wv.add_child(UIKit.row("In your account", UIKit.money_str(GameState.personal_money),
		UIKit.MONEY if GameState.personal_money >= 0 else UIKit.BAD, 18))
	wv.add_child(UIKit.row("Total owed", UIKit.money_str(GameState.total_debt()), UIKit.BAD))
	wv.add_child(UIKit.row("Going out daily", UIKit.money_str(GameState.daily_debt_payment()), UIKit.WARN))
	for d in ctx.get("debts_paid", []):
		wv.add_child(UIKit.row("  paid — %s" % String(d["name"]),
			UIKit.money_str(-int(d["amount"])), UIKit.INK_DIM, 13))
	for d in ctx.get("debts_missed", []):
		wv.add_child(UIKit.row("  MISSED — %s" % String(d["name"]),
			"%s (%dx)" % [UIKit.money_str(int(d["amount"])), int(d["missed"])], UIKit.BAD, 13))
	for line in ctx.get("pressure", []):
		wv.add_child(UIKit.label("· " + String(line), 13, UIKit.WARN))
	wallet.add_child(wv)
	content.add_child(wallet)

	# ---- events
	var events: Array = ctx.get("events", [])
	if not events.is_empty():
		content.add_child(UIKit.rule())
		content.add_child(UIKit.label("TODAY", 13, UIKit.INK_DIM))
		for e in events:
			var box := UIKit.panel(UIKit.NOTE, 6)
			var bv := UIKit.vbox(3)
			bv.add_child(UIKit.label(String(e["title"]), 17, UIKit.WARN))
			bv.add_child(UIKit.label(String(e["body"]), 14, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
			box.add_child(bv)
			content.add_child(box)

	# ---- the handover. Who was already here when you arrived, and — stated
	# plainly, once, in the only place a new player is definitely reading —
	# which of them is finished. Nothing here suggests what to do about it.
	var handover: Array = ctx.get("handover", [])
	if not handover.is_empty():
		content.add_child(UIKit.rule())
		content.add_child(UIKit.label("HANDOVER FROM THE NIGHT DOCTOR", 13, UIKit.INK_DIM))
		for h in handover:
			var hb := UIKit.panel(UIKit.NOTE, 6)
			var hv := UIKit.vbox(2)
			hv.add_child(UIKit.row("%s — %s" % [String(h["name"]), String(h["room"]).capitalize()],
				String(h["condition"]), UIKit.INK, 16))
			var night_word := "night" if int(h["nights"]) == 1 else "nights"
			hv.add_child(UIKit.row("  %d %s so far" % [int(h["nights"]), night_word],
				"%s/night · your share %s" % [UIKit.money_str(int(h["revenue"])),
					UIKit.money_str(int(h["cut"]))], UIKit.MONEY, 13))
			if bool(h["ready"]):
				hv.add_child(UIKit.label("  Medically fit for discharge.", 14,
					UIKit.WARN if bool(h["overdue"]) else UIKit.ACCENT))
			if bool(h["overdue"]):
				hv.add_child(UIKit.label("  Past their expected date%s." %
					(" — and counting" if bool(h["knows"]) else ""), 13, UIKit.BAD))
			hb.add_child(hv)
			content.add_child(hb)

	# ---- the list. What the shift actually is.
	var appts: Array = ctx.get("appointments", [])
	if not appts.is_empty():
		content.add_child(UIKit.rule())
		content.add_child(UIKit.label("YOUR LIST — %s SHIFT" %
			String(ctx.get("shift_name", "Day")).to_upper(), 13, UIKit.INK_DIM))
		for a in appts:
			var row := UIKit.row("%s  %s" % [GameState.hour_string(int(a["hour"])),
				String(AppointmentSystem.LABELS.get(String(a["kind"]), ""))],
				String(a["name"]))
			content.add_child(row)
		# "with you", not "tonight": the same line is printed under a heading
		# that has just named the shift from ctx, and on a day shift it read
		# "5 other staff on the floor tonight" directly beneath "YOUR LIST —
		# DAY SHIFT". The number is the whole trade the shift-select screen is
		# built on, and this is the one place it is restated in the morning, so
		# it cannot be the line that contradicts the shift it describes.
		content.add_child(UIKit.label(
			"%d other staff on the floor with you." % int(ctx.get("staff_on", 0)),
			13, UIKit.INK_DIM))

	var open_inv: Array = ctx.get("open_investigations", [])
	if not open_inv.is_empty():
		content.add_child(UIKit.rule())
		content.add_child(UIKit.label("OPEN AGAINST YOU", 13, UIKit.INK_DIM))
		for t in open_inv:
			content.add_child(UIKit.label("· %s" % String(t), 15, UIKit.BAD))

	# ---- arrivals
	var arrivals: Array = ctx.get("arrivals", [])
	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("ADMISSIONS", 13, UIKit.INK_DIM))
	if arrivals.is_empty():
		content.add_child(UIKit.label("No beds free. Nobody new today.", 14, UIKit.INK_DIM))
	for a in arrivals:
		var box := UIKit.panel(UIKit.NOTE, 6)
		var bv := UIKit.vbox(2)
		bv.add_child(UIKit.row(String(a["name"]), String(a["condition"]), UIKit.ACCENT, 17))
		bv.add_child(UIKit.row("Expected stay", "%.1f days" % float(a["stay"])))
		bv.add_child(UIKit.row("Insurance", String(a["insurance"]),
			UIKit.MONEY if String(a["insurance"]) in ["Good", "Excellent", "Platinum Concierge"] else UIKit.INK))
		bv.add_child(UIKit.row("Daily billing", UIKit.money_str(int(a["revenue"])), UIKit.MONEY))
		bv.add_child(UIKit.row("Room", String(a["room"]).replace("ward_", "Room ")))
		bv.add_child(UIKit.label(DB.archetype_blurb(_arch_key(String(a["archetype"]))), 12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(bv)
		content.add_child(box)

	content.add_child(UIKit.rule())
	content.add_child(UIKit.row("Projected billing today",
		UIKit.money_str(int(ctx.get("projected_revenue", 0))), UIKit.MONEY, 17))
	v.add_child(UIKit.scroll(content))
	return v

## The briefing shows friendly archetype names; look the key back up for the blurb.
func _arch_key(display: String) -> String:
	for tbl in [DB.PATIENT_ARCHETYPES, DB.NURSE_ARCHETYPES, DB.DOCTOR_ARCHETYPES, DB.FAMILY_ARCHETYPES]:
		for k in tbl:
			if String(tbl[k].get("name", "")) == display:
				return String(k)
	return ""
