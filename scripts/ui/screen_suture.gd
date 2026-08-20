extends ScreenBase
## Closing a wound, on the wound.
##
## Six bites, in order, down an actual laceration on an actual part of an actual
## person, while they breathe and occasionally flinch. Each one lands where you
## put it: on the mark and the lips draw together and the red narrows, off the
## mark and the thread goes in crooked and stays crooked for everyone to see.
##
## The dishonest version is not "be slow" — being bad at your job is not a
## strategy this game respects. It is taking the bites shallow and wide, out at
## the marks in the skin either side of the cut, so that the closure holds for
## exactly as long as it takes you to leave the room. Done precisely, it is a
## wound that opened overnight and a bed that is still occupied on Thursday.
## Done sloppily, it is a man sewn up at random in front of his family.

const FIELD := Vector2(820, 400)
const FLINCH_EVERY := 4.4

var _patient = null
var _intent := ""
var _site := "forearm"
var _tone := Color(0.9, 0.7, 0.6)

var _canvas: Control = null
var _clock: Label = null
var _verdict: Label = null
var _coach: Label = null

var _line := PackedVector2Array()
var _open: Array[float] = []
var _targets: Array[Vector2] = []
var _tangents: Array[Vector2] = []
var _placed: Array[Dictionary] = []
var _scores: Array[float] = []
var _misses := 0
var _next := 0
var _left := Procedures.SUTURE_SECONDS
var _elapsed := 0.0
var _flinch_in := FLINCH_EVERY
var _flinch := 0.0
var _sway := Vector2.ZERO
var _was_down := false
var _done := false

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
	var v := shell(760, 520, "Closure — %s" % _patient.display_name,
		"%s · %s" % [_patient.condition_name(), Procedures.site_name(_patient.condition_id)])
	intent_gate(v,
		"Six bites down the middle of the cut, in order, through the marks. "
		+ "It holds, it heals, they go home and you bill the closure.",
		"Six shallow bites out at the wide marks instead. It looks closed. It is "
		+ "not closed. If your hands are good, it opens on its own tonight and "
		+ "nobody was anywhere near it.",
		func(intent: String): _begin(intent))

func _begin(intent: String) -> void:
	_intent = intent
	AudioMgr.play("swab", -14.0)
	rebuild()

func _build_field() -> void:
	var v := shell(900, 720, "Closure — %s" % _patient.display_name,
		"%s · %s" % [Procedures.site_name(_patient.condition_id),
			String(Procedures.INTENTS[_intent]["label"])])
	_coach = UIKit.label(
		"Click each mark in order. They are breathing; the cut moves with them.",
		15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_coach)

	_lay_out_wound()

	_canvas = Control.new()
	_canvas.custom_minimum_size = FIELD
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_field)
	v.add_child(_canvas)

	_clock = UIKit.label("", 16, UIKit.WARN, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_clock)
	_verdict = UIKit.label("", 20, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_verdict)
	set_process(true)

# ------------------------------------------------------------------ geometry
func _lay_out_wound() -> void:
	# Where a cut would actually run on this part — down the forearm, across the
	# brow, along the flank. The rig carries it, so the wound is a property of
	# the anatomy rather than of the screen.
	var rg := Anatomy.rig(_site)
	var ends: Array = rg["wound"]
	var wa: Vector2 = Vector2(ends[0]) * FIELD
	var wb: Vector2 = Vector2(ends[1]) * FIELD
	_line = Anatomy.wound_centreline(wa, wb, absi(hash(_patient.id)) | 1, 16, FIELD.y * 0.022)
	_open.clear()
	for i in _line.size():
		var t := float(i) / float(_line.size() - 1)
		_open.append(3.0 + 10.0 * sin(t * PI))

	_targets.clear()
	_tangents.clear()
	var loose: float = Procedures.SUTURE_LOOSE_OFFSET * FIELD.y * 0.070
	for k in Procedures.SUTURE_POINTS:
		var t: float = (float(k) + 0.5) / float(Procedures.SUTURE_POINTS)
		var idx: int = clampi(int(round(t * float(_line.size() - 1))), 1, _line.size() - 2)
		var tang: Vector2 = (_line[idx + 1] - _line[idx - 1]).normalized()
		var at: Vector2 = _line[idx]
		if _intent == "worsen":
			# Shallow bites, alternating sides, out in the skin rather than
			# through the wound. Still a mark; still has to be hit.
			at += tang.orthogonal().normalized() * loose * (1.0 if k % 2 == 0 else -1.0)
		_targets.append(at)
		_tangents.append(tang)

func _stitch_index_of(k: int) -> int:
	var t: float = (float(k) + 0.5) / float(Procedures.SUTURE_POINTS)
	return clampi(int(round(t * float(_line.size() - 1))), 1, _line.size() - 2)

## Everything on the field moves together: breathing, plus whatever the patient
## just did about being stitched.
func _offset() -> Vector2:
	return _sway

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if _done or _canvas == null:
		return
	_elapsed += delta
	_left -= delta
	_sway = Vector2(sin(_elapsed * 1.15) * 3.0, sin(_elapsed * 1.6 + 0.7) * 5.0)
	_flinch = maxf(0.0, _flinch - delta * 2.2)
	_sway += Vector2(sin(_elapsed * 31.0), cos(_elapsed * 27.0)) * _flinch * 11.0

	_flinch_in -= delta
	if _flinch_in <= 0.0:
		_flinch_in = FLINCH_EVERY
		_flinch = 1.0
		AudioMgr.play("gasp", -18.0, 0.95 + randf() * 0.15)

	var down: bool = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if down and not _was_down:
		_click(_canvas.get_local_mouse_position())
	_was_down = down

	if _clock != null:
		_clock.text = "%0.1fs   ·   %d of %d" % [maxf(_left, 0.0), _next,
			Procedures.SUTURE_POINTS]
		_clock.add_theme_color_override("font_color",
			UIKit.BAD if _left < 4.0 else UIKit.WARN)
	_canvas.queue_redraw()
	if _left <= 0.0:
		_resolve()

func _click(at: Vector2) -> void:
	if _next >= Procedures.SUTURE_POINTS:
		return
	var target: Vector2 = _targets[_next] + _offset()
	var d: float = at.distance_to(target)
	if d > Procedures.SUTURE_RADIUS * 1.9:
		# Nowhere near. A hole in somebody for no reason.
		_misses += 1
		AudioMgr.play("wet", -16.0)
		return
	var q: float = Procedures.suture_score(d)
	_scores.append(q)
	_placed.append({"at": _targets[_next], "tangent": _tangents[_next], "q": q})
	_close_around(_next, q)
	_next += 1
	AudioMgr.play("stitch", -12.0, 0.92 + float(_next) * 0.05)
	if q < 0.25:
		AudioMgr.play("squelch", -18.0)
	if _next >= Procedures.SUTURE_POINTS:
		_resolve()

## A bite through the middle of the cut pulls the lips together around it. A
## shallow one out in the skin barely does anything, which is exactly why it is
## the dishonest option and exactly what it looks like on the drawing.
func _close_around(k: int, q: float) -> void:
	var centre := _stitch_index_of(k)
	var pull: float = (0.86 if _intent == "treat" else 0.16) * q
	for i in _open.size():
		var falloff: float = clampf(1.0 - absf(float(i - centre)) / 3.0, 0.0, 1.0)
		_open[i] = maxf(0.6, _open[i] * (1.0 - pull * falloff))

# ------------------------------------------------------------------ drawing
func _draw_field() -> void:
	var ci := _canvas
	Anatomy.draw_drape(ci, Rect2(Vector2.ZERO, FIELD))
	var off := _offset()
	Anatomy.draw_part(ci, _site, FIELD, _tone, Transform2D(0.0, off))

	var line := PackedVector2Array()
	for p in _line:
		line.append(p + off)
	Anatomy.draw_wound(ci, line, _open, _tone)

	# Thread already in.
	for st in _placed:
		Anatomy.draw_stitch(ci, Vector2(st["at"]) + off, Vector2(st["tangent"]),
			14.0, float(st["q"]))

	# Where the next one goes, and a dimmer hint of the ones after it.
	for k in range(_next, Procedures.SUTURE_POINTS):
		var at: Vector2 = _targets[k] + off
		var live: bool = k == _next
		var col: Color = (UIKit.ACCENT if _intent == "treat" else UIKit.WARN) if live \
			else Color(0.75, 0.82, 0.84, 0.22)
		var pulse: float = 1.0 + (0.12 * sin(_elapsed * 6.0) if live else 0.0)
		Anatomy.draw_target(ci, at, Vector2(_tangents[k]), 17.0, col, pulse)

	if _misses > 0:
		ci.draw_string(ThemeDB.fallback_font, Vector2(FIELD.x - 190, 34),
			"%d stray %s" % [_misses, "puncture" if _misses == 1 else "punctures"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UIKit.BAD)
	Anatomy.draw_trace(ci, Rect2(Vector2(24, FIELD.y - 74), Vector2(FIELD.x - 48, 46)),
		_elapsed * 1.1, Color(0.45, 0.90, 0.70, 0.55), _flinch)
	ci.draw_string(ThemeDB.fallback_font, Vector2(24, 34),
		Procedures.site_name(_patient.condition_id).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.80, 0.78, 0.75))

# ------------------------------------------------------------------ outcome
func _resolve() -> void:
	_done = true
	set_process(false)
	var grade := Procedures.suture_grade(_scores, _misses)
	var spec := Procedures.outcome("suture", _intent, grade)
	_verdict.text = "%s — %s" % [String(spec["label"]),
		Procedures.band_note(_intent, String(spec["band"]))]
	_verdict.add_theme_color_override("font_color", _band_colour(String(spec["band"])))
	if _coach != null:
		_coach.text = ""
	if _canvas != null:
		_canvas.queue_redraw()

	var ts = treatment_system()
	if ts != null:
		ts.apply_outcome(_patient, spec, "suture", player_position())
	var rs = records()
	if rs != null and rs.has_method("log_real_treatment"):
		rs.log_real_treatment(_patient, "suture")
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		close()

func _band_colour(band: String) -> Color:
	match band:
		"good": return UIKit.GOOD
		"fair": return UIKit.WARN
	return UIKit.BAD
