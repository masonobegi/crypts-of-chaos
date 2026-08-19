extends ScreenBase
## Conversation. Options show a confidence BAND, never a percentage — your
## character's read on the room is part of the fiction, and being confidently
## wrong is the point.

var _mind: Mind = null
var _patient = null
var _reply := ""

func _build() -> void:
	var sus = suspicion()
	if sus == null:
		close()
		return
	_mind = sus.mind_of(String(ctx.get("npc_id", "")))
	if _mind == null:
		close()
		return
	_patient = patient_system().get_patient(_mind.id) if patient_system() else null
	if _patient == null and _mind.patient_id != "":
		_patient = patient_system().get_patient(_mind.patient_id) if patient_system() else null

	var sub := "%s · %s" % [_mind.role.capitalize(), DB.archetype_name(_mind.archetype)]
	var v := shell(760, 640, _mind.display_name, sub)

	# What they are currently holding against you, in their words.
	var worst := _mind.strongest(GameState.career_minutes)
	if worst != null:
		var box := UIKit.panel(Color(0.22, 0.13, 0.13, 0.7), 6, 1, UIKit.BAD)
		var bv := UIKit.vbox(2)
		bv.add_child(UIKit.label("They %s: %s" % [worst.source_label(), worst.label()],
			15, Color(1, 0.86, 0.84), HORIZONTAL_ALIGNMENT_LEFT, true))
		if worst.corroborators.size() > 0:
			bv.add_child(UIKit.label("And they are not the only one.", 13, UIKit.WARN))
		box.add_child(bv)
		v.add_child(box)
	else:
		v.add_child(UIKit.label("Nothing on their mind. As far as you can tell.", 14, UIKit.INK_DIM))

	if _patient != null:
		v.add_child(UIKit.row("Condition", _patient.condition_name()))
		v.add_child(UIKit.row("Day of stay", "%d of %d projected" % [
			int(ceil(_patient.days_admitted)), int(ceil(_patient.expected_stay_days))],
			UIKit.WARN if _patient.is_overdue() else UIKit.INK))

	if _reply != "":
		var rp := UIKit.panel(Color(0.12, 0.16, 0.18, 0.9), 6)
		rp.add_child(UIKit.label("\"%s\"" % _reply, 16, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(rp)

	v.add_child(UIKit.rule())
	var opts := UIKit.vbox(6)
	for o in Dialogue.options_for(_mind, _patient):
		opts.add_child(_option_button(o))
	v.add_child(UIKit.scroll(opts))

func _option_button(o) -> Control:
	var h := UIKit.hbox(8)
	var chance := Dialogue.success_chance(_mind, o)
	# No band on lines that cannot fail — a confidence readout against "how are
	# you feeling?" makes the whole readout look untrustworthy.
	var band := "" if o.tone in ["none", "small_talk"] else Dialogue.success_band(chance)
	var label_text: String = o.text
	if o.cost > 0:
		label_text += "  (%s)" % UIKit.money_str(o.cost)
	var b := UIKit.button(label_text, func(): _choose(o))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	h.add_child(b)
	if band != "":
		var colour := UIKit.GOOD
		if chance < 0.2: colour = UIKit.BAD
		elif chance < 0.4: colour = UIKit.WARN
		elif chance < 0.6: colour = Color(0.85, 0.82, 0.5)
		var l := UIKit.label(band, 12, colour, HORIZONTAL_ALIGNMENT_RIGHT)
		l.custom_minimum_size.x = 190
		h.add_child(l)
	# Burned excuses are visibly burned. You should be able to see that you've
	# already used this one on this person.
	if o.cover != "" and _mind.cover_effectiveness(o.cover) < 0.99:
		b.add_theme_color_override("font_color", UIKit.INK_DIM)
		b.text = "%s  (used before)" % label_text
	return h

func _choose(o) -> void:
	if o.tone == "none":
		close()
		return
	var res := Dialogue.resolve(_mind, o, _patient)
	_reply = String(res.get("reply", ""))
	if bool(res.get("discharge_promise", false)) and _patient != null:
		var ts = get_tree().get_first_node_in_group("treatment_system")
		if ts:
			ts.attempt_discharge(_patient)
		EventBus.toast.emit("%s is being discharged." % _patient.display_name, "good")
		close()
		return
	AudioMgr.play("beep" if bool(res.get("success", false)) else "error", -14.0)
	if bool(res.get("small_talk", false)):
		rebuild()
		return
	if bool(res.get("success", false)):
		EventBus.toast.emit("%s seems to accept that." % _mind.display_name, "good")
	else:
		EventBus.toast.emit("%s did not buy it." % _mind.display_name, "bad")
	rebuild()
