extends ScreenBase
## The EHR terminal — where the paperwork crime happens.
##
## Every action here is stamped with whether this terminal is PRIVATE. The same
## edit made at the nurses' station and made in your office with the door shut
## are not the same act.

var _selected := ""
var _private := false
var _pos := Vector3.ZERO
var _room := ""

func _build() -> void:
	_private = bool(ctx.get("private", false))
	_pos = ctx.get("position", Vector3.ZERO)
	_room = String(ctx.get("room", ""))
	var ps = patient_system()
	if ps == null:
		close()
		return

	var privacy := "OFFICE TERMINAL · door's shut" if _private else "WARD TERMINAL · anyone can see this screen"
	var v := shell(880, 700, "Records", privacy)
	if GameState.flag("ehr_down", false):
		v.add_child(UIKit.label("SYSTEM DEGRADED — entries today are not timestamped.", 14, UIKit.WARN))

	var list: Array = ps.active()
	if list.is_empty():
		v.add_child(UIKit.label("No patients admitted.", 15, UIKit.INK_DIM))
		v.add_child(UIKit.button("Close", close))
		return
	if _selected == "":
		_selected = list[0].id

	var tabs := UIKit.hbox(6)
	for p in list:
		var b := UIKit.button(p.display_name.split(" ")[0], func(): _select(p.id),
			UIKit.PANEL_LIGHT if p.id != _selected else Color(0.20, 0.35, 0.38))
		tabs.add_child(b)
	v.add_child(UIKit.scroll_horizontal(tabs))

	var pat = ps.get_patient(_selected)
	if pat == null:
		return
	v.add_child(UIKit.rule())
	v.add_child(UIKit.row(pat.display_name, "%s · %s" % [pat.condition_name(),
		DB.insurance_name(pat.insurance)], UIKit.ACCENT))
	v.add_child(UIKit.row("Billing", "%s/day" % UIKit.money_str(pat.daily_revenue()), UIKit.MONEY))

	var content := UIKit.vbox(8)

	# ---- complications needing a cause. The core money action.
	var undocumented := 0
	for c in pat.active_complications():
		if c.documented_cause == "":
			undocumented += 1
	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("COMPLICATIONS", 13, UIKit.INK_DIM))
	if pat.active_complications().is_empty():
		content.add_child(UIKit.label("None active.", 14, UIKit.INK_DIM))
	for c in pat.active_complications():
		var box := UIKit.panel(Color(0.16, 0.18, 0.21, 0.9), 6)
		var bv := UIKit.vbox(5)
		bv.add_child(UIKit.row(c.display_name,
			DB.cause_name(c.documented_cause) if c.documented_cause != "" else "no cause filed",
			UIKit.GOOD if c.documented_cause != "" and not c.is_inconsistent() else UIKit.BAD))
		if c.symptom != "":
			bv.add_child(UIKit.label(c.symptom, 12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		if c.documented_cause == "":
			var causes := UIKit.vbox(4)
			var rs = records()
			for cause in (rs.cause_options(c) if rs else []):
				var cb := UIKit.button("Attribute to: %s" % DB.cause_name(String(cause)),
					func(): _document(pat, c, String(cause)))
				cb.alignment = HORIZONTAL_ALIGNMENT_LEFT
				causes.add_child(cb)
			bv.add_child(causes)
		box.add_child(bv)
		content.add_child(box)

	# ---- billing
	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("BILLING", 13, UIKit.INK_DIM))
	var bill_row := UIKit.vbox(4)
	for tid in DB.correct_treatments(pat.condition_id):
		var t := String(tid)
		bill_row.add_child(UIKit.button("Add line item: %s" % DB.treatment_name(t),
			func(): _bill(pat, t)))
	content.add_child(bill_row)

	# ---- dates and notes
	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("ADMINISTRATIVE", 13, UIKit.INK_DIM))
	content.add_child(UIKit.row("Promised discharge", "day %d" % pat.chart.promised_discharge_day))
	content.add_child(UIKit.button("Push discharge back one day",
		func(): _push_date(pat)))
	content.add_child(UIKit.button("Note: \"patient reports ongoing symptoms\"",
		func(): _note(pat, "Patient reports ongoing symptoms.", false)))
	content.add_child(UIKit.button("Note: \"reviewed, progressing as expected\"",
		func(): _note(pat, "Reviewed. Progressing as expected.", true)))
	if pat.recovery >= 0.98:
		content.add_child(UIKit.button("Begin discharge paperwork", func(): _discharge(pat),
			Color(0.16, 0.32, 0.20)))
	else:
		content.add_child(UIKit.button("Discharge anyway", func(): _discharge(pat),
			Color(0.32, 0.18, 0.16)))

	# ---- facilities
	content.add_child(UIKit.rule())
	content.add_child(UIKit.label("FACILITIES", 13, UIKit.INK_DIM))
	var hosp = get_tree().get_first_node_in_group("hospital")
	if hosp:
		for r in hosp.room_list():
			if r.kind != "ward":
				continue
			var gripes: Array = r.complaints()
			if gripes.is_empty() and not r.has_plausible_fault():
				continue
			var rr: Room = r
			content.add_child(UIKit.button("Report fault in %s%s" % [rr.display,
				"  (already filed)" if rr.facilities_ticket_filed else ""],
				func(): _ticket(rr)))

	# The exit nobody signposts. Only from a private terminal, because doing this
	# in front of the ward is a different act entirely.
	if _private:
		content.add_child(UIKit.rule())
		content.add_child(UIKit.label("MEDICAL BOARD", 13, UIKit.INK_DIM))
		content.add_child(UIKit.label(
			"There is a form here for reporting concerns about clinical practice. "
			+ "It does not ask whose practice.", 13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
		content.add_child(UIKit.button("Submit a report on this ward — including yourself",
			_whistleblow, Color(0.30, 0.24, 0.14)))

	v.add_child(UIKit.scroll(content))
	v.add_child(UIKit.button("Close", close))

func _select(id: String) -> void:
	_selected = id
	rebuild()

func _document(p, c, cause: String) -> void:
	var rs = records()
	if rs == null:
		return
	var res: Dictionary = rs.document_complication(p, c, cause, _private, _pos, _room)
	if bool(res.get("clean", false)):
		EventBus.toast.emit("Filed cleanly. %s extends the stay." % c.display_name, "money")
	elif not bool(res.get("plausible", true)):
		EventBus.toast.emit("Filed. That cause does not fit this complication.", "suspicion")
	else:
		EventBus.toast.emit("Filed late — it had already been noticed.", "suspicion")
	rebuild()

func _bill(p, tid: String) -> void:
	var rs = records()
	if rs == null:
		return
	# Was it actually performed and not yet billed? Then it's an honest line.
	var actual := 0
	for t in p.actual_treatments:
		if String(t["id"]) == tid:
			actual += 1
	var logged := 0
	for t in p.chart.logged_treatments:
		if String(t["id"]) == tid:
			logged += 1
	if logged < actual:
		rs.log_real_treatment(p, tid)
		EventBus.toast.emit("Line item added.", "info")
	else:
		rs.log_phantom_treatment(p, tid, _private, _pos, _room)
		EventBus.toast.emit("Line item added. It did not happen.", "money")
	rebuild()

func _push_date(p) -> void:
	var rs = records()
	if rs:
		rs.revise_discharge_date(p, p.chart.promised_discharge_day + 1, _private, _pos, _room)
	rebuild()

func _note(p, text: String, truthful: bool) -> void:
	var rs = records()
	if rs:
		rs.add_note(p, text, truthful, _private, _pos, _room)
	EventBus.toast.emit("Note added.", "info")
	rebuild()

func _discharge(p) -> void:
	var ts = get_tree().get_first_node_in_group("treatment_system")
	if ts == null:
		return
	var res: Dictionary = ts.attempt_discharge(p)
	if bool(res.get("premature", false)):
		EventBus.toast.emit("%s discharged early. That will be on the record." % p.display_name, "suspicion")
	_selected = ""
	rebuild()

## Ends the career on your own terms. Everything comes out, including your part
## in it, which is the whole point of it being an ending rather than an escape.
func _whistleblow() -> void:
	GameState.set_flag("whistleblew", true)
	EventBus.toast.emit("Report submitted. All of it.", "info")
	AudioMgr.play("stamp", -6.0)
	close()
	EventBus.game_over.emit("whistleblower")

func _ticket(r) -> void:
	var rs = records()
	if rs:
		rs.file_facilities_ticket(r, _private, _pos)
	rebuild()
