extends ScreenBase
## Taking a joint through an arc.
##
## The third verb, and a different SKILL from the other two on purpose. Setting
## a bone is holding a position steady; suturing is a sequence of precise
## clicks. This is tracking: a guide travels the path the joint has to follow
## and your job is to be on it, the whole way, at its speed.
##
## Which is what a reduction actually is. Not force — a particular curve at a
## particular pace, with a person attached to the end of it. It is the one
## manoeuvre here where going too fast and going too slow are both wrong, and
## the reason the dishonest version is harder is that the path a joint takes
## coming OUT is longer than the path it takes going in.

const FIELD := Vector2(820, 400)

var _patient = null
var _intent := ""
var _site := "shoulder"
var _tone := Color(0.9, 0.7, 0.6)

var _canvas: Control = null
var _clock: Label = null
var _verdict: Label = null
var _coach: Label = null

var _t := 0.0                 ## how far along the arc the guide is, 0..1
var _angle := Procedures.MANIP_START
var _elapsed := 0.0
var _quality_time := 0.0
var _tracked_time := 0.0
var _grip := false
var _done := false
var _flash := 0.0

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return
	_site = Procedures.site_for(_patient.condition_id)
	_tone = Anatomy.tone_for(_patient.display_name)
	if _intent == "":
		_build_intent()
	else:
		_build_field()

func _build_intent() -> void:
	var v := shell(760, 520, "Manipulation — %s" % _patient.display_name,
		"%s · %s" % [_patient.condition_name(), Procedures.site_name(_patient.condition_id)])
	intent_gate(v,
		"Take the joint back the way it came, following the guide the whole way. "
		+ "It goes in, they improve, and you bill the reduction.",
		"Take it the other way instead — out, over, and down the far side, along "
		+ "the curve it would have taken in a fall. It is a longer path and a "
		+ "harder one, and done properly it is a thing that happened to them.",
		func(intent: String): _begin(intent))

func _begin(intent: String) -> void:
	_intent = intent
	_angle = Procedures.MANIP_START
	AudioMgr.play("swab", -14.0)
	rebuild()

func _build_field() -> void:
	var v := shell(900, 720, "Manipulation — %s" % _patient.display_name,
		"%s · %s" % [Procedures.site_name(_patient.condition_id),
			String(Procedures.INTENTS[_intent]["label"])])
	_coach = UIKit.label(
		"Hold the left mouse button and keep the limb on the guide. It sets the "
		+ "pace; you cannot hurry it and you cannot wait it out.",
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

	_clock = UIKit.label("", 16, UIKit.WARN, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_clock)
	_verdict = UIKit.label("", 20, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_verdict)
	set_process(true)

# ------------------------------------------------------------------ geometry
## Drawn at three-quarter size and nudged left, because this is the one screen
## that swings a whole limb through an arc: at full size the top of the curve
## puts a forearm outside the field.
const BOX := Vector2(0.74, 0.74)
const NUDGE := Vector2(0.34, 0.10)

func _box() -> Vector2:
	return FIELD * BOX

func _origin() -> Vector2:
	return (FIELD - _box()) * NUDGE + Vector2(0.0, FIELD.y * 0.06)

func _rig() -> Dictionary:
	return Anatomy.rig(_site)

func _pivot() -> Vector2:
	return _origin() + Vector2(_rig()["pivot"]) * _box()

func _fragment_xf(angle: float) -> Transform2D:
	var f := _pivot()
	return Transform2D(angle, f) * Transform2D(0.0, -f)

## Where the guide is on screen: the far end of the limb, rotated to the angle
## the guide is currently asking for.
func _guide_point(angle: float) -> Vector2:
	var f := _pivot()
	var reach: float = _box().y * 0.40
	return _fragment_xf(angle) * (f + Vector2(_rig()["axis"]) * reach)

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if _done or _canvas == null:
		return
	_elapsed += delta
	_flash = maxf(0.0, _flash - delta * 2.0)
	# The arc runs on its own clock. This is the whole design: the joint has a
	# pace and you are following it, rather than dragging it wherever you like.
	_t = clampf(_elapsed / Procedures.MANIP_SECONDS, 0.0, 1.0)
	var want := Procedures.manip_angle_at(_intent, _t)

	_grip = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _grip:
		# Your hand is wherever the mouse is, expressed as an angle about the
		# joint — so this is a real manipulation of a real limb rather than a
		# slider with an arm drawn next to it.
		var f := _pivot()
		var to := _canvas.get_local_mouse_position() - f
		if to.length() > 12.0:
			var base := Vector2(_rig()["axis"]).angle()
			_angle = wrapf(to.angle() - base, -PI, PI)
			_angle = clampf(_angle, -1.4, 1.6)
		_tracked_time += delta
		_quality_time += Procedures.manip_closeness(_angle - want) * delta
		if absf(_angle - want) <= Procedures.MANIP_TOL:
			if fmod(_elapsed, 0.18) < delta:
				AudioMgr.play("tick", -22.0, 1.0 + _t * 0.6)
		elif fmod(_elapsed, 0.35) < delta:
			AudioMgr.play("bone_grind", -24.0, 0.9)
	else:
		# Letting go does not stop the joint; it stops YOU.
		_tracked_time += delta

	_canvas.queue_redraw()
	if _clock != null:
		var left: float = maxf(0.0, Procedures.MANIP_SECONDS - _elapsed)
		var on: bool = _grip and absf(_angle - want) <= Procedures.MANIP_TOL
		_clock.text = "%0.1fs   ·   %s" % [left,
			"on the guide" if on else ("off the guide" if _grip else "not holding")]
		_clock.add_theme_color_override("font_color",
			UIKit.GOOD if on else (UIKit.WARN if _grip else UIKit.BAD))
	if _t >= 1.0:
		_resolve()

# ------------------------------------------------------------------ drawing
func _draw_field() -> void:
	var ci := _canvas
	Anatomy.draw_drape(ci, Rect2(Vector2.ZERO, FIELD))
	var f := _pivot()
	var want := Procedures.manip_angle_at(_intent, _t)
	var tint: Color = UIKit.ACCENT if _intent == "treat" else UIKit.WARN

	# The whole path, faintly, so you can see where this is going before it
	# goes there — and the part of it already travelled, brighter.
	var path := Procedures.manip_path(_intent)
	var trail := PackedVector2Array()
	for i in path.size():
		trail.append(_guide_point(float(path[i])))
	ci.draw_polyline(trail, Color(tint.r, tint.g, tint.b, 0.34), 3.0, true)
	var walked := PackedVector2Array()
	var upto: int = clampi(int(_t * float(path.size() - 1)), 1, path.size() - 1)
	for i in range(upto + 1):
		walked.append(trail[i])
	if walked.size() > 1:
		ci.draw_polyline(walked, Color(tint.r, tint.g, tint.b, 0.85), 5.0, true)

	# The limb, at the angle YOUR hand is holding it.
	Anatomy.draw_part_split(ci, _site, _box(), _tone,
		_fragment_xf(_angle) * Transform2D(0.0, _origin()))

	# The guide: where the joint is supposed to be right now.
	var g := _guide_point(want)
	var on: bool = _grip and absf(_angle - want) <= Procedures.MANIP_TOL
	ci.draw_arc(g, 24.0, 0.0, TAU, 26, tint, 3.0, true)
	ci.draw_circle(g, 9.0, Color(tint.r, tint.g, tint.b, 0.65 if on else 0.30))
	# ...and where your hand is, so the gap between them is the readout.
	var mine := _guide_point(_angle)
	if _grip:
		ci.draw_line(mine, g, Color(1, 1, 1, 0.22 if on else 0.45), 2.0, true)
		ci.draw_circle(mine, 12.0, Color(0.92, 0.96, 0.96, 0.75))
		ci.draw_arc(mine, 12.0, 0.0, TAU, 20, Color(0.10, 0.12, 0.14), 2.0, true)
	else:
		ci.draw_string(ThemeDB.fallback_font, Vector2(24, FIELD.y - 22),
			"hold the left mouse button and follow the guide",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.82, 0.84, 0.85))
	if _flash > 0.0:
		ci.draw_circle(f, 30.0 * (1.0 - _flash), Color(1, 1, 1, _flash * 0.4))

	Anatomy.draw_trace(ci, Rect2(Vector2(24, FIELD.y - 74), Vector2(FIELD.x - 48, 46)),
		_elapsed * 1.0, Color(0.45, 0.90, 0.70, 0.55),
		0.0 if on else 0.5)
	ci.draw_string(ThemeDB.fallback_font, Vector2(24, 34),
		Procedures.site_name(_patient.condition_id).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.80, 0.78, 0.75))

# ------------------------------------------------------------------ outcome
func _resolve() -> void:
	_done = true
	set_process(false)
	_flash = 1.0
	var grade := Procedures.manip_grade(_quality_time, _tracked_time)
	var spec := Procedures.outcome("manipulate", _intent, grade)
	_verdict.text = "%s — %s" % [String(spec["label"]),
		Procedures.band_note(_intent, String(spec["band"]))]
	_verdict.add_theme_color_override("font_color", _band_colour(String(spec["band"])))
	if _coach != null:
		_coach.text = ""
	if _canvas != null:
		_canvas.queue_redraw()

	var ts = treatment_system()
	if ts != null:
		ts.apply_outcome(_patient, spec, "manipulate", player_position())
	var rs = records()
	if rs != null and rs.has_method("log_real_treatment"):
		rs.log_real_treatment(_patient, "manipulate")
	AudioMgr.play("seat" if String(spec["band"]) != "poor" else "crack", -8.0)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		close()

func _band_colour(band: String) -> Color:
	match band:
		"good": return UIKit.GOOD
		"fair": return UIKit.WARN
	return UIKit.BAD
