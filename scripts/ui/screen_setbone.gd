extends ScreenBase
## Setting a broken bone.
##
## A sweeping marker over a five-band bar. Press to stop it. The clean window is
## narrow and central; the two ruinous bands are wide and at the ends.
##
## That asymmetry is the design. Helping somebody is a skill check you can fail
## by accident. Hurting somebody is a skill check you can pass ON PURPOSE — and
## nothing on this screen tells you that, or labels the red bands as anything
## other than what they are. The chart says what a clean reduction looks like;
## the bar just shows you where your hands are.

const BAR_W := 620.0
const BAR_H := 46.0

var _patient = null
var _pos := 0.0
var _dir := 1.0
var _speed := 0.85
var _stopped := false
var _bar: Control = null
var _needle: ColorRect = null
var _verdict: Label = null
var _hint: Label = null

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null:
		close()
		return
	var v := shell(720, 480, "Reduction — %s" % _patient.display_name,
		_patient.condition_name())

	v.add_child(UIKit.label(
		"Hold the limb, wait for the swing, and stop it where the bone wants to go.",
		15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.spacer(6))

	# The bar. Bands are drawn in the patient's own colours rather than a
	# traffic light, because a traffic light would be the game telling you which
	# end is the crime.
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(BAR_W, BAR_H)
	v.add_child(_bar)
	for band in Procedures.BONE_BAR:
		var r := ColorRect.new()
		r.position = Vector2(BAR_W * float(band["from"]), 0)
		r.size = Vector2(BAR_W * (float(band["to"]) - float(band["from"])), BAR_H)
		r.color = _band_colour(String(band["zone"]))
		_bar.add_child(r)
	_needle = ColorRect.new()
	_needle.color = Color(1, 1, 1, 0.95)
	_needle.size = Vector2(4, BAR_H + 12)
	_needle.position = Vector2(0, -6)
	_bar.add_child(_needle)

	v.add_child(UIKit.spacer(8))
	_hint = UIKit.label("[Space] or click to set it.", 15, UIKit.ACCENT,
		HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_hint)
	_verdict = UIKit.label("", 19, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER, true)
	v.add_child(_verdict)

	# Faster for a bigger bone: a wrist is fiddly, a shoulder fights you.
	_speed = 0.72 + clampf(float(_patient.base_daily_revenue) / 4000.0, 0.0, 0.5)
	set_process(true)

func _band_colour(zone: String) -> Color:
	match zone:
		"clean": return Color(0.30, 0.52, 0.46)
		"rough": return Color(0.34, 0.36, 0.40)
	return Color(0.42, 0.30, 0.30)

func _process(delta: float) -> void:
	if _stopped or _needle == null:
		return
	_pos += _dir * _speed * delta
	if _pos >= 1.0:
		_pos = 1.0
		_dir = -1.0
	elif _pos <= 0.0:
		_pos = 0.0
		_dir = 1.0
	_needle.position.x = BAR_W * _pos - 2.0

func _unhandled_input(event: InputEvent) -> void:
	if _stopped:
		return
	var go: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if not go:
		return
	get_viewport().set_input_as_handled()
	_resolve()

func _resolve() -> void:
	_stopped = true
	var zone := Procedures.zone_at(_pos)
	var spec: Dictionary = Procedures.BONE_ZONES[zone]
	_hint.text = ""
	_verdict.text = String(spec["label"])
	_verdict.add_theme_color_override("font_color",
		UIKit.GOOD if zone == "clean" else (UIKit.WARN if zone == "rough" else UIKit.BAD))

	var ts = treatment_system()
	if ts != null:
		ts.apply_reduction(_patient, zone, player_position())
	AudioMgr.play("snap" if zone == "worse" else "thud", -8.0)
	# Long enough to read the verdict and hear the patient's opinion of it.
	await get_tree().create_timer(1.6).timeout
	if is_instance_valid(self):
		close()
