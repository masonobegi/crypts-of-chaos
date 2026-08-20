extends ScreenBase
## Conversation. Options show a confidence BAND, never a percentage — your
## character's read on the room is part of the fiction, and being confidently
## wrong is the point.

var _mind: Mind = null
var _patient = null
var _reply := ""
var _typer: Typewriter = null

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
		# Typed out, in their voice, rather than appearing complete.
		#
		# A reply used to arrive as finished text in a box, which is why talking
		# to somebody "goes so quick": nothing to read AT, no pace, no sense that
		# a person is saying it. It arrives at the speed of speech now, with a
		# blip per syllable pitched off their own id, and a click hurries it.
		var rp := UIKit.panel(Color(0.12, 0.16, 0.18, 0.9), 6)
		var rl := UIKit.label("", 16, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true)
		rl.custom_minimum_size.y = 52
		rp.add_child(rl)
		v.add_child(rp)
		_typer = Typewriter.new()
		add_child(_typer)
		_typer.speak(rl, "\"%s\"" % _reply, _mind.id)

	v.add_child(UIKit.rule())
	# The clinical action, kept out of the conversation list because it is not a
	# thing you say to somebody.
	if _patient != null and not _patient.discharged:
		# The procedure this person's actual ailment calls for. Forty conditions
		# used to funnel into one dial; a broken wrist and a head cold are not
		# the same job and should not be the same verb.
		var kind := Procedures.procedure_for(_patient.condition_id)
		if kind == "set_bone" or kind == "prescribe":
			var screen := "setbone" if kind == "set_bone" else "medicate"
			var pb := UIKit.button(Procedures.procedure_name(kind), func():
				var pid: String = _patient.id
				close()
				EventBus.request_ui.emit(screen, {"patient_id": pid}),
				Color(0.20, 0.32, 0.30))
			pb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(pb)
		var ex := UIKit.button("Examine them", func():
			var pid: String = _patient.id
			close()
			EventBus.request_ui.emit("exam", {"patient_id": pid}),
			Color(0.18, 0.28, 0.34))
		ex.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(ex)
		if _patient.admitted:
			var op := UIKit.button("Take them to theatre", func():
				var pid: String = _patient.id
				close()
				EventBus.request_ui.emit("surgery", {"patient_id": pid}),
				Color(0.18, 0.28, 0.34))
			op.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(op)
			var rx := UIKit.button("Discharge and prescribe", func():
				var pid: String = _patient.id
				close()
				EventBus.request_ui.emit("prescribe", {"patient_id": pid}),
				Color(0.18, 0.28, 0.34))
			rx.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(rx)
		# The treatments that need no equipment. There is no way to hold "rest"
		# in your hands, so the item-in-hand grammar every other treatment uses
		# had no way to express them at all — and six treatments across the
		# condition table are exactly that, printed on the chart as INDICATED
		# with "no equipment" beside them. The chart instructed the player to do
		# something the game had no verb for.
		for tid in DB.correct_treatments(_patient.condition_id):
			if String(DB.treatment(String(tid)).get("tool", "")) != "":
				continue
			var this_tid := String(tid)
			var bt := UIKit.button(DB.treatment_name(this_tid), func():
				_perform(this_tid), Color(0.18, 0.30, 0.26))
			bt.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(bt)
	var opts := UIKit.vbox(6)
	for o in Dialogue.options_for(_mind, _patient):
		opts.add_child(_option_button(o))
	v.add_child(UIKit.scroll(opts))

## Do it, right there, with your hands in your pockets.
func _perform(tid: String) -> void:
	var ts = get_tree().get_first_node_in_group("treatment_system")
	if ts == null or _patient == null:
		close()
		return
	var pos: Vector3 = Vector3.ZERO
	var body = patient_system().get_body(_patient.id) if patient_system() else null
	if body != null:
		pos = body.global_position
	ts.apply(_patient, tid, null, pos)
	var rs = get_tree().get_first_node_in_group("records_system")
	if rs:
		rs.log_real_treatment(_patient, tid)
	close()

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

## Walk them to the far end of the ward and keep them there for a while.
func _send_away() -> void:
	var sus = suspicion()
	var body = sus.body_of(_mind.id) if sus else null
	var p = player()
	if body != null and body.has_method("send_to_room") and p != null:
		var target: String = body.farthest_ward_from(p.global_position)
		body.send_to_room(target, 26.0)
		EventBus.toast.emit("%s heads off to check the far end." % _mind.display_name, "good")
	AudioMgr.play("beep", -14.0)
	close()

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
	if bool(res.get("send_away", false)):
		_send_away()
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


## Click (or E) anywhere to hurry the line along.
##
## The screen is modal and the tree is paused, so this is the only input that
## reaches it — and "let me read that at my own pace" is the first thing anybody
## wants from dialogue.
func _unhandled_input(event: InputEvent) -> void:
	if _typer == null or not _typer.is_running():
		return
	var pressed: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if pressed:
		_typer.hurry()
		AudioMgr.play("page", -22.0)
		get_viewport().set_input_as_handled()
