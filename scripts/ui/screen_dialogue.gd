extends ScreenBase
## Conversation. Options show a confidence BAND, never a percentage — your
## character's read on the room is part of the fiction, and being confidently
## wrong is the point.

var _mind: Mind = null
var _patient = null
var _reply := ""
var _typer: Typewriter = null
## "speaking" is a beat that takes over the whole screen and waits for a click.
## "options" is the menu. A conversation alternates between them, which is what
## makes it a conversation rather than a form with a quote box on it.
var _stage := "speaking"
var _spoke_hint: Label = null
var _was_down := false

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
	if _reply == "":
		_reply = Dialogue.greeting(_mind, _patient)
	if _stage == "speaking":
		_build_speech()
		return
	_build_options()

# ------------------------------------------------------------------ speaking
## One line, one face, and nothing else on screen until you click.
##
## The note was "talking to people feels weird because the subtitles go so
## quick — it should lock you in a talking phase where you have to click for
## them to mumble words." This is that. The line types at the speed of speech
## with a blip per syllable pitched off their own id, the first click hurries
## it, and the second click is you deciding to answer.
func _build_speech() -> void:
	var sub := "%s · %s" % [_mind.role.capitalize(), DB.archetype_name(_mind.archetype)]
	var v := shell(760, 460, _mind.display_name, sub)
	v.add_child(UIKit.spacer(10))
	var rp := UIKit.panel(Color(0.12, 0.16, 0.18, 0.95), 8, 1, UIKit.ACCENT)
	var rl := UIKit.label("", 20, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true)
	rl.custom_minimum_size.y = 128
	rp.add_child(rl)
	v.add_child(rp)
	v.add_child(UIKit.spacer(8))
	_spoke_hint = UIKit.label("", 14, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_spoke_hint)
	_typer = Typewriter.new()
	add_child(_typer)
	_typer.speak(rl, "\"%s\"" % _reply, _mind.id)
	_was_down = true      # swallow the click that opened this screen
	set_process(true)

func _process(_delta: float) -> void:
	if _stage != "speaking":
		return
	if _spoke_hint != null:
		_spoke_hint.text = "" if (_typer != null and _typer.is_running()) \
			else "click to answer"
	var down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if down and not _was_down:
		_advance()
	_was_down = down

func _unhandled_input(event: InputEvent) -> void:
	if _stage != "speaking":
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_E]:
		get_viewport().set_input_as_handled()
		_advance()

func _advance() -> void:
	if _typer != null and _typer.hurry():
		AudioMgr.play("tick", -26.0, 1.2)
		return
	_stage = "options"
	set_process(false)
	rebuild()

# ------------------------------------------------------------------ options
func _build_options() -> void:
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

	# The last thing they said, kept on screen while you decide what to say
	# back. Not typed here — it has already been read, in the speaking beat.
	if _reply != "":
		var rp := UIKit.panel(Color(0.12, 0.16, 0.18, 0.9), 6)
		rp.add_child(UIKit.label("\"%s\"" % _reply, 15, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(rp)

	v.add_child(UIKit.rule())
	# The clinical action, kept out of the conversation list because it is not a
	# thing you say to somebody.
	if _patient != null and not _patient.discharged:
		# The procedure this person's actual ailment calls for. Forty conditions
		# used to funnel into one dial; a broken wrist and a head cold are not
		# the same job and should not be the same verb.
		var kind := Procedures.procedure_for(_patient.condition_id)
		var screen := Procedures.screen_for(kind)
		if screen != "":
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
		if not _patient.admitted:
			# Somebody upright, in a chair, who has not cost anybody anything
			# yet. This is the decision the five-bed ward is built around and it
			# belongs in the conversation where it happens, not only on the
			# examination screen.
			var ps = patient_system()
			var free: int = ps.free_wards().size() if ps != null else 0
			var beds := UIKit.label(
				"%d of 5 rooms free. Admitting them starts the daily rate." % free,
				13, UIKit.WARN if free <= 1 else UIKit.INK_DIM,
				HORIZONTAL_ALIGNMENT_LEFT, true)
			v.add_child(beds)
			var ad := UIKit.button("Admit them — %s a day" % UIKit.money_str(
				_patient.daily_revenue()), _admit, Color(0.16, 0.32, 0.30))
			ad.alignment = HORIZONTAL_ALIGNMENT_LEFT
			ad.disabled = free <= 0
			v.add_child(ad)
			var sh := UIKit.button("Send them home", _send_home, Color(0.24, 0.26, 0.30))
			sh.alignment = HORIZONTAL_ALIGNMENT_LEFT
			v.add_child(sh)
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
	var quiet := _quiet_word()
	if quiet != null:
		opts.add_child(UIKit.spacer(6))
		opts.add_child(quiet)
	v.add_child(UIKit.scroll(opts))

## The envelope.
##
## Kept apart from the conversation list on purpose. Explaining yourself is
## something you do with words and it is what the rest of this screen is for;
## this is a different KIND of move, it has a price on it, and it should feel
## like reaching into your own pocket rather than picking a line.
##
## Only offered to somebody who actually holds something against you — you
## cannot pre-emptively buy a ward, and there is nothing to buy from a person
## who saw nothing.
func _quiet_word() -> Control:
	if _mind.deal_state != "none":
		return null
	var worst := _mind.strongest(GameState.career_minutes)
	if worst == null or worst.neutralized:
		return null
	var box := UIKit.panel(Color(0.20, 0.17, 0.10, 0.85), 6, 1, UIKit.WARN)
	var bv := UIKit.vbox(4)
	bv.add_child(UIKit.label("Have a quiet word.", 17, UIKit.WARN))
	bv.add_child(UIKit.label(
		"They have not written it down yet. If they say no, they will — and they "
		+ "will write down that you asked.", 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	for tier in Bribery.TIERS:
		var t: Dictionary = tier
		var cost := Bribery.price(_mind, float(t["mult"]))
		var odds := Bribery.chance(_mind, t)
		var row := UIKit.hbox(8)
		var b := UIKit.button("%s  (%s)" % [String(t["label"]), UIKit.money_str(cost)],
			func(): _bribe(t), Color(0.30, 0.26, 0.14))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if GameState.personal_money < cost:
			b.disabled = true
		row.add_child(b)
		var colour := UIKit.GOOD
		if odds < 0.2: colour = UIKit.BAD
		elif odds < 0.4: colour = UIKit.WARN
		elif odds < 0.6: colour = Color(0.85, 0.82, 0.5)
		var l := UIKit.label(Bribery.band(odds), 12, colour, HORIZONTAL_ALIGNMENT_RIGHT)
		l.custom_minimum_size.x = 190
		row.add_child(l)
		bv.add_child(row)
	box.add_child(bv)
	return box

func _bribe(tier: Dictionary) -> void:
	var sus = suspicion()
	var body = sus.body_of(_mind.id) if sus else null
	var at: Vector3 = body.global_position if body != null else player_position()
	var room := ""
	if _patient != null:
		room = _patient.room
	var res := Bribery.attempt(_mind, tier, at, room)
	_reply = String(res.get("reply", ""))
	_stage = "speaking"
	if bool(res.get("broke", false)):
		EventBus.toast.emit("You cannot afford to be discreet.", "bad")
	elif bool(res.get("ok", false)):
		EventBus.toast.emit("%s takes it." % _mind.display_name, "good")
	else:
		EventBus.toast.emit("%s does not take it — and now they have that, too."
			% _mind.display_name, "suspicion")
	rebuild()

func _admit() -> void:
	var ps = patient_system()
	if ps == null or _patient == null:
		close()
		return
	if not ps.admit(_patient):
		EventBus.toast.emit("There is nowhere to put them.", "bad")
		return
	AudioMgr.play("trolley", -12.0)
	close()

func _send_home() -> void:
	var ps = patient_system()
	if ps != null and _patient != null:
		ps.send_home(_patient, "cleared")
	AudioMgr.play("door", -14.0)
	close()

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
	if _reply != "":
		_stage = "speaking"
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

