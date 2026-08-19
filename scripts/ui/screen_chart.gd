extends ScreenBase
## The patient chart. Read-only truth about the record — everything you can
## CHANGE lives on a terminal, because getting to a terminal is part of the cost.

func _build() -> void:
	var p = patient_system().get_patient(String(ctx.get("patient_id", ""))) if patient_system() else null
	if p == null:
		close()
		return
	var v := shell(760, 660, p.display_name,
		"%d · %s · %s" % [p.age, DB.archetype_name(p.archetype), DB.insurance_name(p.insurance)])

	v.add_child(UIKit.row("Recorded condition", DB.condition_name(p.chart.recorded_condition), UIKit.ACCENT))
	v.add_child(UIKit.row("Presenting sign", String(DB.condition(p.condition_id).get("tell", "—"))))
	# Somebody inherited from a previous shift was admitted before day one, so
	# "day -2" is both true and useless. Days-ago is what a chart is read for.
	var ago: int = GameState.day - p.admitted_on_day
	v.add_child(UIKit.row("Admitted", "today" if ago <= 0 else
		("yesterday" if ago == 1 else "%d days ago" % ago)))
	v.add_child(UIKit.row("Promised discharge", "day %d" % p.chart.promised_discharge_day,
		UIKit.WARN if p.chart.promised_discharge_day > p.admitted_on_day + int(ceil(p.expected_stay_days)) else UIKit.INK))
	v.add_child(UIKit.row("Day of stay", "%d of %d projected" % [
		int(ceil(p.days_admitted)), int(ceil(p.expected_stay_days))],
		UIKit.WARN if p.is_overdue() else UIKit.INK))
	v.add_child(UIKit.row("Daily billing", UIKit.money_str(p.daily_revenue()), UIKit.MONEY))

	var vit: Dictionary = p.vitals()
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("OBSERVATIONS", 13, UIKit.INK_DIM))
	v.add_child(UIKit.row("Humour balance", "%0.0f" % vit["humour_balance"]))
	v.add_child(UIKit.row("Spleen torque", "%0.1f" % vit["spleen_torque"]))
	v.add_child(UIKit.row("Ambient dread", "%0.0f" % vit["ambient_dread"]))
	v.add_child(UIKit.row("Impression", p.apparent_state()))

	var scroll_box := UIKit.vbox(6)
	scroll_box.add_child(UIKit.rule())
	scroll_box.add_child(UIKit.label("INDICATED TREATMENTS", 13, UIKit.INK_DIM))
	for tid in DB.correct_treatments(p.condition_id):
		var spec: Dictionary = DB.treatment(String(tid))
		scroll_box.add_child(UIKit.row(String(spec.get("name", tid)),
			String(spec.get("tool", "")) if String(spec.get("tool", "")) != "" else "no equipment"))

	scroll_box.add_child(UIKit.rule())
	scroll_box.add_child(UIKit.label("COMPLICATIONS", 13, UIKit.INK_DIM))
	if p.complications.is_empty():
		scroll_box.add_child(UIKit.label("None recorded.", 14, UIKit.INK_DIM))
	for c in p.complications:
		var status := "cause: %s" % DB.cause_name(c.documented_cause)
		var colour := UIKit.GOOD
		if c.documented_cause == "":
			status = "NO CAUSE FILED"
			colour = UIKit.BAD
		elif c.is_inconsistent():
			status = "cause: %s (does not fit)" % DB.cause_name(c.documented_cause)
			colour = UIKit.BAD
		scroll_box.add_child(UIKit.row("%s%s" % [c.display_name, "" if not c.resolved else " (resolved)"],
			status, colour))
		if c.symptom != "":
			scroll_box.add_child(UIKit.label("   " + c.symptom, 12, UIKit.INK_DIM))

	scroll_box.add_child(UIKit.rule())
	scroll_box.add_child(UIKit.label("TREATMENT LOG", 13, UIKit.INK_DIM))
	if p.chart.logged_treatments.is_empty():
		scroll_box.add_child(UIKit.label("Nothing logged.", 14, UIKit.INK_DIM))
	for t in p.chart.logged_treatments:
		scroll_box.add_child(UIKit.row(DB.treatment_name(String(t["id"])),
			"day %d" % (int(t["time"]) / GameState.MINUTES_PER_DAY + 1),
			UIKit.INK if bool(t.get("real", true)) else UIKit.SUS))

	if not p.chart.notes.is_empty():
		scroll_box.add_child(UIKit.rule())
		scroll_box.add_child(UIKit.label("NOTES", 13, UIKit.INK_DIM))
		for n in p.chart.notes:
			scroll_box.add_child(UIKit.label("· %s" % String(n["text"]), 13,
				UIKit.INK if bool(n.get("truthful", true)) else UIKit.SUS))

	v.add_child(UIKit.scroll(scroll_box))
	v.add_child(UIKit.label("Changes are made at a terminal.", 12, UIKit.INK_DIM))
	v.add_child(UIKit.button("Close", close))
