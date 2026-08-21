extends ScreenBase
## Setting a broken bone, on the broken bone.
##
## The first version of this was a needle sweeping a coloured bar. It tested a
## reflex, it was the same reflex for a wrist and a set of ribs, and the note
## that came back was "make the minigames show the body part you are treating,
## it should be med themed, not just some reaction test." Fair.
##
## So: the patient's actual limb, drawn from their actual condition, with the
## actual bone in it, in two pieces. The mouse is your grip on the distal
## fragment — left and right is the angle, up and down is traction. Your hands
## are not steady, and every few seconds the patient's muscle fights you.
##
## Where you are trying to put it depends on what you said you were doing. Back
## into line, or into the specific ugly position that a bone can plausibly find
## on its own overnight. Both are marked on the field as a ghost. Both need
## holding still. One of them is a fee and a discharge; the other is a fee and a
## bed that keeps paying, and the difference between getting away with it and
## not is entirely in your hands.

const FIELD := Vector2(820, 400)
const RESPONSE := 11.0            # how quickly the fragment follows your grip
const SPASM_EVERY := 3.1

var _patient = null
var _intent := ""
var _site := "forearm"
var _tone := Color(0.9, 0.7, 0.6)

var _canvas: Control = null
var _clock: Label = null
var _verdict: Label = null
var _coach: Label = null

var _angle := 0.0
var _gap := 0.0
var _want_angle := 0.0
var _want_gap := 0.0
var _kick := 0.0
var _hold := 0.0
var _elapsed := 0.0
var _spasm_in := SPASM_EVERY
var _qsum := 0.0
var _qtime := 0.0
var _peak := 0.0
var _done := false
var _grip := false
var _seat_flash := 0.0
var _grind := 0.0
var _angle_shown := 0.0
var _gap_shown := 0.0

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
	var v := shell(760, 520, "Reduction — %s" % _patient.display_name,
		"%s · %s" % [_patient.condition_name(), Procedures.site_name(_patient.condition_id)])
	intent_gate(v,
		"Bring the fragment back into line and hold it there until it seats. "
		+ "They improve, they need the bed for less time, and you bill a reduction.",
		"Put it somewhere a bone could plausibly have gone by itself, and hold it "
		+ "there just as steadily. Done well it reads as a bad night. Done badly it "
		+ "reads as you.",
		func(intent: String): _begin(intent))

func _begin(intent: String) -> void:
	_intent = intent
	# The fragment starts displaced, because it is broken. Which way is the
	# patient's business and not the same every time.
	var lean: float = -0.42 if absi(hash(_patient.id)) % 2 == 0 else 0.46
	_angle = lean
	_want_angle = lean
	_gap = 9.0
	_want_gap = 9.0
	AudioMgr.play("swab", -14.0)
	rebuild()

func _build_field() -> void:
	var v := shell(900, 720, "Reduction — %s" % _patient.display_name,
		"%s · %s" % [Procedures.site_name(_patient.condition_id),
			String(Procedures.INTENTS[_intent]["label"])])
	_coach = UIKit.label(
		"Hold the fragment in the marked position until it seats. "
		+ "Left-right is angle, up-down is traction.",
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
func _rig() -> Dictionary:
	return Anatomy.rig(_site)

func _fracture() -> Vector2:
	return Vector2(_rig()["pivot"]) * FIELD

## p′ = R(angle)·(p − fracture) + fracture + slide along the limb.
func _fragment_xf(angle: float, gap: float) -> Transform2D:
	var f := _fracture()
	var dir := Vector2(_rig()["axis"])
	return Transform2D(angle, f + dir * gap) * Transform2D(0.0, -f)

# ------------------------------------------------------------------ loop
func _process(delta: float) -> void:
	if _done or _canvas == null:
		return
	_elapsed += delta
	_seat_flash = maxf(0.0, _seat_flash - delta * 2.0)

	# Your grip. Held only while the button is down, so letting go is a way to
	# stop making it worse — and letting go does not stop the clock.
	_grip = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _grip:
		var m := _canvas.get_local_mouse_position()
		var c := FIELD * 0.5
		_want_angle = clampf((m.x - c.x) / (FIELD.x * 0.34) * Procedures.BONE_MAX_ANGLE,
			-Procedures.BONE_MAX_ANGLE, Procedures.BONE_MAX_ANGLE)
		_want_gap = clampf((m.y - c.y) / (FIELD.y * 0.36) * Procedures.BONE_MAX_GAP,
			-Procedures.BONE_MAX_GAP, Procedures.BONE_MAX_GAP)

	# Muscle. Every few seconds it pulls, and it pulls harder the longer you
	# have been standing there with your hands inside somebody.
	_spasm_in -= delta
	if _spasm_in <= 0.0:
		_spasm_in = SPASM_EVERY
		var away: float = -1.0 if _angle > 0.0 else 1.0
		_kick += away * (0.11 + _elapsed * 0.012)
		AudioMgr.play("grunt", -17.0, 0.9 + randf() * 0.2)
	_kick = lerpf(_kick, 0.0, 1.0 - exp(-delta * 2.4))

	var follow: float = 1.0 - exp(-delta * RESPONSE)
	_angle = lerpf(_angle, _want_angle, follow) + _kick * delta * 6.0
	_gap = lerpf(_gap, _want_gap, follow)
	_angle = clampf(_angle, -Procedures.BONE_MAX_ANGLE, Procedures.BONE_MAX_ANGLE)

	# Tremor: small, always there, and the reason a hold is a hold.
	var t := _elapsed
	var shake: float = sin(t * 11.3) * 0.55 + sin(t * 17.9 + 1.3) * 0.45
	var shown_angle: float = _angle + shake * 0.022
	var shown_gap: float = _gap + shake * 1.5

	var close: float = Procedures.bone_closeness(_intent, shown_angle, shown_gap)
	_peak = maxf(_peak, close)
	if Procedures.bone_in_tolerance(_intent, shown_angle, shown_gap):
		_hold += delta
		_qsum += close * delta
		_qtime += delta
		_grind = minf(1.0, _grind + delta * 2.0)
		if fmod(_hold, 0.16) < delta:
			AudioMgr.play("tick", -20.0, 1.1 + _hold * 0.5)
	else:
		_hold = maxf(0.0, _hold - delta * 0.9)
		_grind = maxf(0.0, _grind - delta * 1.5)

	_angle_shown = shown_angle
	_gap_shown = shown_gap
	_canvas.queue_redraw()

	if _clock != null:
		var left: float = maxf(0.0, Procedures.BONE_SECONDS - _elapsed)
		_clock.text = "%0.1fs   ·   seating %d%%" % [left,
			int(clampf(_hold / Procedures.BONE_HOLD_SECONDS, 0.0, 1.0) * 100.0)]
		_clock.add_theme_color_override("font_color",
			UIKit.GOOD if _hold > 0.0 else (UIKit.BAD if left < 4.0 else UIKit.WARN))

	if _hold >= Procedures.BONE_HOLD_SECONDS:
		_resolve(false)
	elif _elapsed >= Procedures.BONE_SECONDS:
		_resolve(true)


# ------------------------------------------------------------------ drawing
func _draw_field() -> void:
	var ci := _canvas
	Anatomy.draw_drape(ci, Rect2(Vector2.ZERO, FIELD))
	var rg := _rig()
	var f := _fracture()
	var dir := Vector2(rg["axis"])
	var bone_r: float = float(rg["bone_r"]) * FIELD.y

	# Where it is meant to end up, drawn as the bones alone in ghost colour and
	# under everything else. It is the same drawing the fragment will make when
	# it gets there, which is the only honest way to show a target.
	var target: Dictionary = Procedures.bone_target(_intent)
	var gxf := _fragment_xf(float(target["angle"]), float(target["gap"]))
	var gcol: Color = Anatomy.BONE_GHOST if _intent == "treat" else Color(0.95, 0.55, 0.45, 0.55)
	for c in rg["dbone"]:
		var poly := Anatomy.capsule_poly(
			gxf * (Vector2(c["a"]) * FIELD), gxf * (Vector2(c["b"]) * FIELD),
			float(c["ra"]) * FIELD.y, float(c["rb"]) * FIELD.y)
		ci.draw_colored_polygon(poly, Color(gcol.r, gcol.g, gcol.b, 0.14))
		Anatomy.outline_poly(ci, poly, 2.0, gcol)

	# The limb. Proximal half is fixed; the distal half is in your hands, and
	# whatever is on the end of it — a hand, a foot — comes along with it.
	var xf := _fragment_xf(_angle_shown, _gap_shown)
	Anatomy.draw_part_split(ci, _site, FIELD, _tone, xf)
	Anatomy.draw_fracture_end(ci, f, dir, bone_r)
	Anatomy.draw_fracture_end(ci, f, -dir, bone_r, xf)

	# Seating ring at the fracture, filling as it holds.
	var frac := clampf(_hold / Procedures.BONE_HOLD_SECONDS, 0.0, 1.0)
	var ring: float = bone_r + FIELD.y * 0.075
	if frac > 0.0:
		ci.draw_arc(f, ring, -PI * 0.5, -PI * 0.5 + TAU * frac, 40,
			UIKit.GOOD if _intent == "treat" else UIKit.WARN, 4.0, true)
	if _seat_flash > 0.0:
		ci.draw_circle(f, ring + 26.0 * (1.0 - _seat_flash), Color(1, 1, 1, _seat_flash * 0.4))

	# Your hands, so the fragment is something being held rather than floating.
	if _grip:
		var grip_at: Vector2 = xf * (f + dir * FIELD.y * 0.30)
		ci.draw_circle(grip_at, 15.0, Color(0.20, 0.55, 0.52, 0.55))
		ci.draw_arc(grip_at, 15.0, 0.0, TAU, 20, UIKit.ACCENT, 2.0, true)
	else:
		ci.draw_string(ThemeDB.fallback_font, Vector2(24, FIELD.y - 22),
			"hold the left mouse button to take the limb",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.82, 0.84, 0.8))

	Anatomy.draw_trace(ci, Rect2(Vector2(24, FIELD.y - 74), Vector2(FIELD.x - 48, 46)),
		_elapsed * 0.9, Color(0.45, 0.90, 0.70, 0.55), _grind)
	ci.draw_string(ThemeDB.fallback_font, Vector2(24, 34),
		Procedures.site_name(_patient.condition_id).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.55, 0.80, 0.78, 0.75))

# ------------------------------------------------------------------ outcome
func _resolve(ran_out: bool) -> void:
	_done = true
	set_process(false)
	var grade := 0.0
	if ran_out:
		# Never quite got it there. Some credit for how close you came, not much.
		grade = _peak * 0.40
	else:
		var mean: float = _qsum / maxf(0.001, _qtime)
		grade = clampf(mean * (1.0 - 0.22 * (_elapsed / Procedures.BONE_SECONDS)), 0.0, 1.0)
		_seat_flash = 1.0
		AudioMgr.play("seat", -8.0)
	var spec := Procedures.outcome("set_bone", _intent, grade)
	_verdict.text = "%s — %s" % [String(spec["label"]),
		Procedures.band_note(_intent, String(spec["band"]))]
	_verdict.add_theme_color_override("font_color", _band_colour(String(spec["band"])))
	if _coach != null:
		_coach.text = ""
	if _canvas != null:
		_canvas.queue_redraw()

	var ts = treatment_system()
	if ts != null:
		ts.apply_outcome(_patient, spec, "set_bone", player_position())
	var rs = records()
	if rs != null and rs.has_method("log_real_treatment"):
		rs.log_real_treatment(_patient, "set_bone")
	AudioMgr.play("crack" if String(spec["band"]) == "poor" else "bone_grind", -11.0)
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		close()

func _band_colour(band: String) -> Color:
	match band:
		"good": return UIKit.GOOD
		"fair": return UIKit.WARN
	return UIKit.BAD
