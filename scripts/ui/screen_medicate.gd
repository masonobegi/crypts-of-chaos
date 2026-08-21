extends ScreenBase
## Giving somebody a drug, in two parts: which bottle, and how much of it.
##
## The bottle is a KNOWLEDGE check. What is indicated for this condition is
## written on their chart, and the chart is a physical object in the room that
## you may or may not have bothered to pick up. What actively disagrees with it
## is on the same page, in the same small print, and is the other half of why
## reading is worth doing.
##
## The dose is a SKILL check, drawn up by hand against the graduations on the
## barrel with a needle going into a real arm. Hold to draw, release to give.
##
## The two multiply. A rock-steady hand on the wrong bottle still lands in the
## band that gets punished, and a perfect choice of drug administered by the
## litre is its own kind of incident. What is deliberately NOT here: any mark
## against any option on the shelf. Four boxes and their marketing copy, exactly
## as they would be on a shelf.

const FIELD := Vector2(820, 400)
const FILL_RATE := 0.42

var _patient = null
var _intent := ""
var _med := ""
var _read_the_chart := false
var _tone := Color(0.9, 0.7, 0.6)

var _canvas: Control = null
var _readout: Label = null
var _verdict: Label = null
var _coach: Label = null

var _level := 0.0
var _elapsed := 0.0
var _was_down := false
var _drawing := false
var _rate := 0.0
var _given := false
var _jab := 0.0
var _done := false

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return
	_read_the_chart = _patient.read_is_fresh()
	_tone = Anatomy.tone_for(_patient.display_name)
	if _intent == "":
		_build_intent()
	elif _med == "":
		_build_shelf()
	else:
		_build_field()

func _build_intent() -> void:
	var v := shell(760, 520, "Medication — %s" % _patient.display_name,
		_patient.condition_name())
	intent_gate(v,
		"The drug that treats what they have, drawn up to the line printed on "
		+ "the barrel. They improve and the round moves on.",
		"Something their condition will argue with, given at a dose nobody would "
		+ "call a mistake twice. Done well it is an unlucky reaction. Done badly "
		+ "it is a syringe emptied into a man in front of his wife.",
		func(intent: String): _begin(intent))

func _begin(intent: String) -> void:
	_intent = intent
	rebuild()

# ------------------------------------------------------------------ the shelf
func _build_shelf() -> void:
	var v := shell(760, 660, "Medication — %s" % _patient.display_name,
		"%s · choose the bottle" % _patient.condition_name())

	# Has anybody actually looked into this? The chart carries the indication —
	# and the clash — once it has been read; until then you are going on the
	# name of the illness and your nerve.
	if _read_the_chart:
		var ind := String(Procedures.CURES.get(_patient.condition_id, ""))
		var clashes: Array = Procedures.CLASHES.get(_patient.condition_id, [])
		# A condition with no entry in CURES used to render "indicated is ."
		# — _med_name() falls back to the id it was handed, and the id of
		# nothing is nothing, so the one reward for having gone and read the
		# chart was a sentence with a hole in the middle of it. The chart is
		# allowed to say that nothing on this shelf is licensed for what they
		# have; it is not allowed to trail off mid-indication.
		var lines := ""
		if ind == "":
			lines = "Chart, examined: nothing on this shelf is licensed for it."
		else:
			lines = "Chart, examined: indicated is %s." % _med_name(ind)
		if not clashes.is_empty():
			lines += "\nNoted as disagreeing with it: %s." % _med_name(String(clashes[0]))
		var box := UIKit.panel(UIKit.NOTE_GOOD, 6, 1, UIKit.ACCENT)
		box.add_child(UIKit.label(lines, 15, UIKit.INK,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		v.add_child(box)
	else:
		v.add_child(UIKit.label(
			"You have not examined them. The chart is wherever you left it.",
			14, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())

	var scroll := UIKit.scroll(_shelf_list())
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	v.add_child(UIKit.button("Not today", close))

func _shelf_list() -> Control:
	var list := UIKit.vbox(6)
	for med_id in Procedures.options_for(_patient.condition_id):
		list.add_child(_option(med_id))
	return list

func _med_name(id: String) -> String:
	return String(Procedures.MEDICINES.get(id, {}).get("name", id))

func _option(med_id: String) -> Control:
	var med: Dictionary = Procedures.MEDICINES.get(med_id, {})
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 6)
	var bv := UIKit.vbox(2)
	bv.add_child(UIKit.label(String(med.get("name", med_id)), 17, UIKit.INK))
	bv.add_child(UIKit.label(String(med.get("blurb", "")), 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	bv.add_child(UIKit.button("Draw it up", func(): _pick(med_id)))
	p.add_child(bv)
	return p

func _pick(med_id: String) -> void:
	_med = med_id
	AudioMgr.play("glass", -16.0)
	rebuild()

# ------------------------------------------------------------------ the dose
func _build_field() -> void:
	var v := shell(900, 720, "%s — %s" % [_med_name(_med), _patient.display_name],
		"%s · %s" % [Procedures.site_name(_patient.condition_id),
			String(Procedures.INTENTS[_intent]["label"])])
	_coach = UIKit.label(
		"Hold the left mouse button to draw it up. Let go to give it.",
		15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_coach)

	_canvas = Control.new()
	_canvas.custom_minimum_size = FIELD
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Nothing may escape the field. A limb swung far enough draws over the
	# panel, the heading and the room behind it, and a Control does not clip
	# its own drawing unless it is told to.
	_canvas.clip_contents = true
	_canvas.draw.connect(_draw_field)
	v.add_child(_canvas)

	_readout = UIKit.label("", 16, UIKit.WARN, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_readout)
	_verdict = UIKit.label("", 20, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_verdict)
	set_process(true)

func _barrel() -> Rect2:
	return Rect2(Vector2(FIELD.x * 0.17, FIELD.y * 0.14),
		Vector2(FIELD.x * 0.09, FIELD.y * 0.58))

func _process(delta: float) -> void:
	if _done or _canvas == null:
		return
	_elapsed += delta
	_jab = maxf(0.0, _jab - delta * 1.4)
	var down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if not _given:
		if down:
			if not _drawing:
				_drawing = true
				AudioMgr.play("swab", -16.0)
			# The plunger does not come up evenly, and it does not come up the
			# same way twice: two beats against each other so there is no rhythm
			# to learn, only a line to watch.
			var rate: float = FILL_RATE * (1.0 + 0.52 * sin(_elapsed * 7.1)
				+ 0.22 * sin(_elapsed * 2.3 + 1.1))
			_rate = rate
			_level = clampf(_level + rate * delta, 0.0, 1.0)
			if fmod(_level, 0.1) < rate * delta:
				AudioMgr.play("tick", -24.0, 0.8 + _level * 0.8)
		elif _drawing and _was_down:
			# It carries. Letting go on the line puts you past it, so the skill
			# is knowing how early to stop — which is a skill, unlike watching a
			# bar and releasing.
			_level = Procedures.dose_settle(_level, _rate)
			_give()
	_was_down = down
	if _readout != null and not _given:
		_readout.text = "%d ml drawn" % int(round(_level * 20.0))
	_canvas.queue_redraw()

func _give() -> void:
	_given = true
	_jab = 1.0
	AudioMgr.play("inject", -10.0)
	AudioMgr.play("wet", -20.0)
	var precision := Procedures.dose_precision(_intent, _level)
	var ts = treatment_system()
	var spec := {}
	if ts != null:
		spec = ts.apply_dose(_patient, _med, _intent, precision, player_position())
	else:
		spec = Procedures.outcome("dose", _intent,
			Procedures.dose_grade(_intent,
				Procedures.medicine_effect(_patient.condition_id, _med), precision))
	var rs = records()
	if rs != null and rs.has_method("log_real_treatment"):
		rs.log_real_treatment(_patient, "dose")
	_finish(spec)

func _finish(spec: Dictionary) -> void:
	_done = true
	var band := String(spec.get("band", "fair"))
	_verdict.text = "%s — %s" % [String(spec.get("label", "Given")),
		Procedures.band_note(_intent, band)]
	_verdict.add_theme_color_override("font_color",
		UIKit.GOOD if band == "good" else (UIKit.WARN if band == "fair" else UIKit.BAD))
	if _coach != null:
		_coach.text = ""
	if _readout != null:
		_readout.text = "%d ml given" % int(round(_level * 20.0))
	if _canvas != null:
		_canvas.queue_redraw()
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		close()

# ------------------------------------------------------------------ drawing
func _draw_field() -> void:
	var ci := _canvas
	Anatomy.draw_drape(ci, Rect2(Vector2.ZERO, FIELD))
	var target := Procedures.dose_target(_intent)
	var tint: Color = UIKit.ACCENT if _intent == "treat" else UIKit.WARN
	var barrel := _barrel()
	Anatomy.draw_syringe(ci, barrel, _level, target, Procedures.DOSE_TOLERANCE, tint)

	# The line printed on the side by whoever makes these. Always visible, even
	# when it is not the line you are aiming at.
	var py: float = barrel.position.y + barrel.size.y * (1.0 - Procedures.DOSE_TREAT_TARGET)
	ci.draw_line(Vector2(barrel.position.x - 14, py), Vector2(barrel.end.x + 4, py),
		Color(0.92, 0.95, 0.96, 0.75), 1.5)
	ci.draw_string(ThemeDB.fallback_font, Vector2(barrel.end.x + 12, py - 4),
		"prescribed", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.90, 0.92, 0.8))
	if _intent == "worsen":
		var wy: float = barrel.position.y + barrel.size.y * (1.0 - Procedures.DOSE_WORSEN_TARGET)
		ci.draw_string(ThemeDB.fallback_font, Vector2(barrel.end.x + 12, wy - 4),
			"what you are giving", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UIKit.WARN)

	# The part it is going into. It is a person, not a form — and it is THEIR
	# part: a brow gets a brow, an ankle gets an ankle.
	var box := Vector2(FIELD.x * 0.60, FIELD.y * 0.86)
	var origin := Vector2(FIELD.x * 0.38, FIELD.y * 0.07)
	Anatomy.draw_part(ci, Procedures.site_for(_patient.condition_id), box, _tone,
		Transform2D(0.0, origin))
	# The site, swabbed, with the needle standing in it once it has gone in.
	var site := origin + box * Vector2(0.46, 0.52)
	ci.draw_circle(site, box.y * 0.13, Color(0.86, 0.94, 0.92, 0.30))
	ci.draw_arc(site, box.y * 0.13, 0.0, TAU, 22, Color(0.72, 0.88, 0.84, 0.75), 2.0, true)
	if _jab > 0.0:
		ci.draw_circle(site, box.y * 0.13 * (0.5 + _jab * 0.9),
			Color(0.88, 0.36, 0.34, _jab * 0.55))
		ci.draw_line(site, site - Vector2(0, 54.0), Color(0.78, 0.83, 0.86), 3.0)
	ci.draw_string(ThemeDB.fallback_font, Vector2(24, 34),
		"%s · %s" % [_med_name(_med).to_upper(),
			Procedures.site_name(_patient.condition_id).to_upper()],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.80, 0.78, 0.75))
	Anatomy.draw_trace(ci, Rect2(Vector2(24, FIELD.y - 74), Vector2(FIELD.x - 48, 46)),
		_elapsed * 1.0, Color(0.45, 0.90, 0.70, 0.55), _jab)
	if not _given and not _drawing:
		ci.draw_string(ThemeDB.fallback_font, Vector2(24, FIELD.y - 22),
			"hold the left mouse button to draw it up",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.82, 0.84, 0.8))
