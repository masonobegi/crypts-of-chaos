extends ScreenBase
## Prescribing.
##
## Not a skill check — a KNOWLEDGE check. The right drug for this condition is
## written on the chart, and the chart is a physical object in the room you may
## or may not have bothered to pick up. Read it and this screen is trivial.
## Guess and it is a coin flip with three sides.
##
## What is deliberately NOT here: any mark against any option. No red text, no
## "(not indicated)", no confirmation. Four boxes of pills and their marketing
## copy, exactly as they would be on a shelf.

var _patient = null
var _read_the_chart := false

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return
	var v := shell(760, 620, "Prescribe — %s" % _patient.display_name,
		_patient.condition_name())

	# Has anybody actually looked into this? The chart carries the indication
	# once it has been read; until then you are going on the name of the illness.
	_read_the_chart = _patient.read_is_fresh()
	if _read_the_chart:
		var ind := String(Procedures.CURES.get(_patient.condition_id, ""))
		var nm := String(Procedures.MEDICINES.get(ind, {}).get("name", "—"))
		var box := UIKit.panel(Color(0.12, 0.20, 0.18, 0.85), 6, 1, UIKit.ACCENT)
		box.add_child(UIKit.label("Chart, examined: indicated is %s." % nm,
			15, Color(0.80, 0.96, 0.90), HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(box)
	else:
		v.add_child(UIKit.label(
			"You have not examined them. The chart is wherever you left it.",
			14, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	for med_id in Procedures.options_for(_patient.condition_id):
		v.add_child(_option(med_id))

	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Not today", close))

func _option(med_id: String) -> Control:
	var med: Dictionary = Procedures.MEDICINES.get(med_id, {})
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 6)
	var bv := UIKit.vbox(2)
	bv.add_child(UIKit.label(String(med.get("name", med_id)), 17, UIKit.INK))
	bv.add_child(UIKit.label(String(med.get("blurb", "")), 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	var b := UIKit.button("Prescribe", func(): _give(med_id))
	bv.add_child(b)
	p.add_child(bv)
	return p

func _give(med_id: String) -> void:
	var ts = treatment_system()
	if ts != null:
		ts.apply_prescription(_patient, med_id, player_position())
	var rs = records()
	if rs != null and rs.has_method("log_real_treatment"):
		rs.log_real_treatment(_patient, med_id)
	AudioMgr.play("paper", -14.0)
	close()
