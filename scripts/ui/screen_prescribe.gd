extends ScreenBase
## What they take home.
##
## The list is the whole pharmacy, in alphabetical order, with no marking of
## which one is right. Working that out is the job — and the one thing the
## screen does tell you is that the pharmacy is writing this down.

var _patient = null
var _result: Dictionary = {}

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return

	var v := shell(720, 680, "Discharge", "%s · %s" % [_patient.display_name,
		_patient.presenting_complaint])

	if not _result.is_empty():
		v.add_child(UIKit.label("Signed off. The pharmacy has it.", 16, UIKit.INK))
		if int(_result.get("fee", 0)) > 0:
			v.add_child(UIKit.row("Discharge billed",
				UIKit.money_str(int(_result["fee"])), UIKit.MONEY))
		v.add_child(UIKit.spacer())
		v.add_child(UIKit.button("Close", close))
		return

	# The arithmetic, stated flatly, at the exact moment it matters. Nothing here
	# is advice and nothing here is labelled — it is two numbers and the player
	# can do what they like with them. This is the moment the whole game is
	# waiting for a stranger to notice.
	var money_box := UIKit.panel(UIKit.NOTE, 6, 1, UIKit.MONEY)
	var bx := UIKit.vbox(3)
	bx.add_child(UIKit.row("Send them home today", "your bonus is settled at %s"
		% UIKit.money_str(0), UIKit.INK_DIM))
	bx.add_child(UIKit.row("Every further night", "hospital %s   ·   you %s" % [
		UIKit.money_str(_patient.daily_revenue()),
		UIKit.money_str(_patient.your_cut_per_day())], UIKit.MONEY))
	bx.add_child(UIKit.label("Day %d of a projected %d." % [
		int(ceil(_patient.days_admitted)), int(ceil(_patient.expected_stay_days))],
		13, UIKit.INK_DIM))
	money_box.add_child(bx)
	v.add_child(money_box)

	v.add_child(UIKit.row("Condition on file", _patient.condition_name()))
	for c in _patient.active_complications():
		v.add_child(UIKit.row("  " + c.display_name,
			DB.cause_name(c.documented_cause) if c.documented_cause != "" else "NO CAUSE FILED",
			UIKit.GOOD if c.documented_cause != "" else UIKit.BAD, 13))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("PHARMACY", 13, UIKit.INK_DIM))

	var box := UIKit.vbox(4)
	for id in DB.PRESCRIPTIONS:
		var mid := String(id)
		var spec: Dictionary = DB.PRESCRIPTIONS[mid]
		var b := UIKit.button(String(spec["name"]), func(): _give(mid))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		box.add_child(b)
		box.add_child(UIKit.label("    %s" % String(spec["blurb"]), 12, UIKit.INK_DIM))
	v.add_child(UIKit.scroll(box))
	v.add_child(UIKit.label("The pharmacy keeps its own record of this.", 12, UIKit.INK_DIM))
	v.add_child(UIKit.button("Not yet", close))

func _give(med_id: String) -> void:
	var ts = get_tree().get_first_node_in_group("treatment_system")
	if ts == null:
		close()
		return
	_result = ts.prescribe(_patient, med_id)
	var ps = patient_system()
	if ps:
		ps.discharge(_patient, "recovered" if _patient.recovery >= 0.85 else "discharged")
	AudioMgr.play("pills", -13.0)
	rebuild()
