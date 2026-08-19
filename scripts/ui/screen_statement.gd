extends ScreenBase
## The shift report. Deliberately shareable: one card, a headline, and the two
## numbers that describe how the day actually went.

func _build() -> void:
	var st: Dictionary = ctx.get("statement", {})
	var v := shell(880, 740, "Shift Report — Day %d" % int(ctx.get("day", 1)),
		String(ctx.get("sanction", "Clean")))

	var head := UIKit.panel(Color(0.16, 0.15, 0.12, 0.95), 6, 1, UIKit.WARN)
	head.add_child(UIKit.label(String(ctx.get("headline", "")), 17, UIKit.WARN,
		HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(head)

	var content := UIKit.vbox(8)

	content.add_child(UIKit.label("BILLING", 13, UIKit.INK_DIM))
	for line in st.get("lines", []):
		content.add_child(UIKit.row(String(line["label"]),
			UIKit.money_str(int(line["amount"])),
			UIKit.SUS if bool(line.get("overdue", false)) else UIKit.MONEY, 14))
	content.add_child(UIKit.rule())
	content.add_child(UIKit.row("Revenue", UIKit.money_str(int(st.get("revenue", 0))), UIKit.MONEY, 16))

	var costs: Dictionary = st.get("costs", {})
	content.add_child(UIKit.row("  staff", UIKit.money_str(-int(costs.get("staff", 0))), UIKit.INK_DIM, 14))
	content.add_child(UIKit.row("  utilities", UIKit.money_str(-int(costs.get("utilities", 0))), UIKit.INK_DIM, 14))
	content.add_child(UIKit.row("  supplies", UIKit.money_str(-int(costs.get("supplies", 0))), UIKit.INK_DIM, 14))
	var profit := int(st.get("profit", 0))
	content.add_child(UIKit.row("Hospital profit", UIKit.money_str(profit),
		UIKit.MONEY if profit >= 0 else UIKit.BAD, 16))

	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("YOU", 13, UIKit.INK_DIM))
	content.add_child(UIKit.row("Salary", UIKit.money_str(int(st.get("salary", 0))), UIKit.INK))
	content.add_child(UIKit.row("Profit share", UIKit.money_str(int(st.get("bonus", 0))), UIKit.MONEY))
	content.add_child(UIKit.row("Take home", UIKit.money_str(int(st.get("take_home", 0))), UIKit.MONEY, 18))
	content.add_child(UIKit.row("Tomorrow's debts",
		UIKit.money_str(-int(ctx.get("daily_debt", 0))), UIKit.BAD, 15))

	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("STANDING", 13, UIKit.INK_DIM))
	var heat := float(ctx.get("heat", 0.0))
	var hd := float(ctx.get("heat_delta", 0.0))
	var hrow := UIKit.hbox(8)
	hrow.add_child(UIKit.label("Institutional heat", 15, UIKit.INK_DIM))
	hrow.add_child(UIKit.spacer(0, false))
	hrow.add_child(UIKit.bar(heat, UIKit.BAD if heat > 0.5 else UIKit.WARN, 180.0))
	hrow.add_child(UIKit.label("%+0.0f%%" % (hd * 100.0), 14,
		UIKit.BAD if hd > 0.001 else UIKit.GOOD))
	content.add_child(hrow)
	for track in ["hospital", "doctor", "staff_trust", "patient_sat", "insurer_trust", "gov_scrutiny"]:
		var value := float(ctx.get("reputation", {}).get(track, 0.5))
		var r := UIKit.hbox(8)
		r.add_child(UIKit.label(track.replace("_", " ").capitalize(), 14, UIKit.INK_DIM))
		r.add_child(UIKit.spacer(0, false))
		r.add_child(UIKit.bar(value, UIKit.rep_color(track, value), 180.0))
		content.add_child(r)

	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("WHAT PEOPLE THINK", 13, UIKit.INK_DIM))
	var sus: Array = ctx.get("suspicions", [])
	if sus.is_empty():
		content.add_child(UIKit.label("Nobody has anything on you.", 14, UIKit.GOOD))
	for s in sus:
		var r := UIKit.hbox(8)
		r.add_child(UIKit.label("%s (%s)" % [String(s["name"]), String(s["role"])], 14, UIKit.INK))
		r.add_child(UIKit.spacer(0, false))
		r.add_child(UIKit.bar(float(s["value"]), UIKit.tier_color(int(s["tier"])), 150.0))
		r.add_child(UIKit.label("%d%%" % int(s["pct"]), 14, UIKit.tier_color(int(s["tier"]))))
		content.add_child(r)

	content.add_child(UIKit.rule())
	content.add_child(UIKit.row("Average overstay", "%.1f days" % float(ctx.get("overstay", 0.0)),
		UIKit.SUS if float(ctx.get("overstay", 0.0)) > 0.8 else UIKit.INK))
	content.add_child(UIKit.row("Shift conduct",
		"clean" if bool(ctx.get("clean", false)) else "noted",
		UIKit.GOOD if bool(ctx.get("clean", false)) else UIKit.WARN))

	v.add_child(UIKit.scroll(content))
	var buttons := UIKit.hbox(10)
	buttons.add_child(UIKit.button("Spend money", func():
		if ui:
			ui.open("upgrades", {})))
	buttons.add_child(UIKit.button("Go home", func():
		var ss = shift_system()
		close()
		if ss:
			ss.next_day(), Color(0.16, 0.30, 0.28)))
	v.add_child(buttons)
