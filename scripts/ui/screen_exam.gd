extends ScreenBase
## Hands-on examination.
##
## Same grammar as every machine in the building: a dial, an indicated value,
## fictional units, and not one word about what happens above the line. The
## player already knows from the ward machines that dials have a prescribed
## setting and that exceeding it does *something*. Reusing that shape for a pair
## of hands is what keeps this a discovery rather than a menu entry labelled
## "hurt them".

const PARTS := ["wrist", "ankle", "shoulder", "knee", "ribs", "head"]

var _patient = null
var _part := "wrist"
var _pressure := 2
var _result: Dictionary = {}

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return

	var v := shell(700, 640, "Examination", _patient.display_name)

	if _result.is_empty():
		v.add_child(UIKit.row("Presenting complaint", _patient.presenting_complaint))
		v.add_child(UIKit.row("Day of stay", "%d of %d projected" % [
			int(ceil(_patient.days_admitted)), int(ceil(_patient.expected_stay_days))]))
		v.add_child(UIKit.rule())
		v.add_child(UIKit.label("WHAT YOU MAKE OF THEM", 13, UIKit.INK_DIM))
		for note in _patient.read_notes():
			v.add_child(UIKit.label("· " + note, 14,
				UIKit.INK_DIM if note.begins_with("You have not") else UIKit.INK,
				HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(UIKit.rule())

		v.add_child(UIKit.label("SITE", 13, UIKit.INK_DIM))
		var parts := UIKit.hbox(6)
		for part in PARTS:
			var b := UIKit.button(part.capitalize(), func(): _pick(part),
				Color(0.20, 0.34, 0.32) if part == _part else UIKit.PANEL_LIGHT)
			parts.add_child(b)
		v.add_child(parts)

		v.add_child(UIKit.spacer(6))
		v.add_child(UIKit.label("APPLIED PRESSURE", 13, UIKit.INK_DIM))
		var dial := UIKit.hbox(10)
		dial.add_child(UIKit.button("−", func(): _nudge(-1)))
		dial.add_child(UIKit.label("%d" % _pressure, 34,
			UIKit.INK if absi(_pressure - TreatmentSystem.EXAM_INDICATED) < 2 else UIKit.WARN))
		dial.add_child(UIKit.button("+", func(): _nudge(1)))
		dial.add_child(UIKit.label("  indicated %d" % TreatmentSystem.EXAM_INDICATED,
			14, UIKit.INK_DIM))
		v.add_child(dial)
		v.add_child(UIKit.label(
			"Graduated scale. Firm enough to find something, no firmer.",
			13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))

		v.add_child(UIKit.spacer())
		v.add_child(UIKit.button("Examine", _run, Color(0.16, 0.32, 0.30)))
		v.add_child(UIKit.button("Leave them", close))
		return

	# ---- afterwards
	v.add_child(UIKit.row("Site", String(_result.get("part", "")).capitalize()))
	v.add_child(UIKit.row("Pressure applied", "%d" % int(_result.get("pressure", 0))))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label(_finding(), 16, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	if String(_result.get("injury", "")) != "":
		v.add_child(UIKit.spacer(6))
		v.add_child(UIKit.label(DB.COMPLICATIONS[String(_result["injury"])]["symptom"],
			15, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(UIKit.label("Nothing has been written down.", 13, UIKit.WARN))
	if int(_result.get("fee", 0)) > 0:
		v.add_child(UIKit.row("Consultation billed",
			UIKit.money_str(int(_result["fee"])), UIKit.MONEY))

	# A walk-in is not a patient yet. This is the decision the clinic exists for
	# and it is stated as flatly as any other clinical judgement, because that is
	# what it looks like from the inside.
	if not _patient.admitted and not _patient.discharged:
		v.add_child(UIKit.rule())
		v.add_child(UIKit.label("DISPOSITION", 13, UIKit.INK_DIM))
		v.add_child(UIKit.button("Admit them — %s/day" %
			UIKit.money_str(_patient.daily_revenue()), _admit, Color(0.16, 0.32, 0.30)))
		v.add_child(UIKit.button("Nothing to admit for — send them home", _send_home))
	v.add_child(UIKit.spacer())
	v.add_child(UIKit.button("Close", close))

func _admit() -> void:
	var ps = patient_system()
	if ps == null:
		close()
		return
	if not ps.admit(_patient):
		EventBus.toast.emit("No bed for %s." % _patient.display_name, "bad")
	close()

func _send_home() -> void:
	var ps = patient_system()
	if ps:
		ps.send_home(_patient, "cleared")
		EventBus.toast.emit("%s sent home." % _patient.display_name, "good")
	close()

## What your character actually gleaned. This is the honest half of the verb and
## the reason a careful examination is worth the two minutes.
func _finding() -> String:
	if String(_result.get("injury", "")) != "":
		return "Something gave."
	var state: String = _patient.apparent_state()
	return "They are %s. You are fairly sure of that now." % state

func _pick(part: String) -> void:
	_part = part
	rebuild()

func _nudge(d: int) -> void:
	_pressure = clampi(_pressure + d, 0, TreatmentSystem.EXAM_DIAL_MAX)
	rebuild()

func _run() -> void:
	var ts = get_tree().get_first_node_in_group("treatment_system")
	if ts == null:
		close()
		return
	var p = player()
	_result = ts.examine(_patient, _part, _pressure,
		p.global_position if p != null else Vector3.ZERO)
	AudioMgr.play("beep", -14.0)
	rebuild()
