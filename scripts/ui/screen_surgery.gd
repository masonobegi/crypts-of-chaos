extends ScreenBase
## A scheduled procedure, in three stages.
##
## Every stage names its approach in the language a theatre record would use —
## "as per protocol", "expedited", "approach modified intra-operatively" — and
## says nothing about consequences. Which is exactly how those words work in
## real notes: all three are things a surgeon writes, and only one of them is
## what you actually did.

var _patient = null
var _site := "general"
var _stage := 0
var _choices: Array[String] = []
var _result: Dictionary = {}

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return
	if not _result.is_empty():
		_build_outcome()
		return
	if _stage == 0 and _choices.is_empty():
		_build_site()
		return
	_build_stage()

func _build_site() -> void:
	var v := shell(680, 600, "Theatre", "%s · %s" % [_patient.display_name,
		_patient.presenting_complaint])
	# Stated flatly and then not enforced, exactly like a machine's prescribed
	# value. Nothing stops you opening a different part of somebody.
	var indicated := TreatmentSystem.indicated_site_for(_patient)
	v.add_child(UIKit.row("Indicated site", indicated.capitalize(), UIKit.ACCENT))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("OPERATIVE SITE", 13, UIKit.INK_DIM))
	for site in TreatmentSystem.SURGERY_SITES:
		var s := String(site)
		v.add_child(UIKit.button(s.capitalize(), func(): _pick_site(s),
			Color(0.20, 0.34, 0.32) if s == indicated else UIKit.PANEL_LIGHT))
	v.add_child(UIKit.spacer())
	v.add_child(UIKit.button("Not today", close))

func _build_stage() -> void:
	var v := shell(700, 560, "Theatre", "%s · %s · stage %d of %d" % [
		_patient.display_name, _site.capitalize(), _stage + 1,
		TreatmentSystem.SURGERY_STAGES])
	if not _choices.is_empty():
		v.add_child(UIKit.label("SO FAR", 13, UIKit.INK_DIM))
		for i in _choices.size():
			v.add_child(UIKit.row("Stage %d" % (i + 1),
				String(TreatmentSystem.SURGERY_APPROACHES[_choices[i]]["note"])))
		v.add_child(UIKit.rule())
	v.add_child(UIKit.label("APPROACH", 13, UIKit.INK_DIM))
	for key in TreatmentSystem.SURGERY_APPROACHES:
		var k := String(key)
		var spec: Dictionary = TreatmentSystem.SURGERY_APPROACHES[k]
		var b := UIKit.button(String(spec["name"]), func(): _choose(k))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
		v.add_child(UIKit.label("    recorded as: %s" % String(spec["note"]),
			12, UIKit.INK_DIM))

func _build_outcome() -> void:
	var v := shell(700, 560, "Theatre", "%s · %s" % [_patient.display_name, _site.capitalize()])
	v.add_child(UIKit.label("THEATRE RECORD", 13, UIKit.INK_DIM))
	v.add_child(UIKit.row("Site", _site.capitalize(),
		UIKit.BAD if bool(_result.get("wrong_site", false)) else UIKit.INK))
	if bool(_result.get("wrong_site", false)):
		v.add_child(UIKit.row("Indicated",
			String(_result.get("indicated", "")).capitalize(), UIKit.WARN))
	for i in _choices.size():
		v.add_child(UIKit.row("Stage %d" % (i + 1),
			String(TreatmentSystem.SURGERY_APPROACHES[_choices[i]]["note"])))
	v.add_child(UIKit.rule())
	var comp := String(_result.get("complication", ""))
	if comp == "":
		v.add_child(UIKit.label("Uneventful. They are noticeably better for it.",
			16, UIKit.GOOD, HORIZONTAL_ALIGNMENT_LEFT, true))
	else:
		v.add_child(UIKit.label(String(DB.COMPLICATIONS[comp]["symptom"]),
			16, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(UIKit.label(
			"Recorded against the procedure. Nothing has been filed as a cause.",
			13, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
	if int(_result.get("fee", 0)) > 0:
		v.add_child(UIKit.row("Procedure billed", UIKit.money_str(int(_result["fee"])),
			UIKit.MONEY))
	v.add_child(UIKit.spacer())
	v.add_child(UIKit.button("Close", close))

func _pick_site(site: String) -> void:
	_site = site
	rebuild()

func _choose(approach: String) -> void:
	_choices.append(approach)
	_stage += 1
	if _stage >= TreatmentSystem.SURGERY_STAGES:
		var ts = get_tree().get_first_node_in_group("treatment_system")
		if ts:
			_result = ts.perform_surgery(_patient, _site, _choices)
		AudioMgr.play("machine_on", -12.0)
	rebuild()
