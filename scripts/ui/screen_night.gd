extends ScreenBase
## The evening.
##
## A street from above: you, a person walking home, some number of people who
## are not looking at anything in particular but could be, and a lamp or two
## that make the difference between a shape and a description.
##
## It is the ward's stealth game with the furniture taken out. Cones of vision,
## a thing you want to be next to, and the knowledge that being SEEN is a
## separate and much worse problem than what you actually came here to do. There
## is no combat, no aiming and nothing graphic: the act is one beat and a sound,
## and everything before it is where you stand.
##
## What you take home is an admission for the morning. What you risk is a
## patient who spends the week in your ward trying to remember where he has seen
## you before.

const FIELD := Vector2(820, 420)
const SECONDS := 22.0
const REACH := 30.0
const SPEED := 168.0

var _stage := "choose"
var _place: Dictionary = {}
var _mark_name := ""

var _canvas: Control = null
var _clock: Label = null
var _coach: Label = null

var _me := Vector2(60, 360)
var _mark := Vector2(600, 90)
var _mark_t := 0.0
var _route: Array[Vector2] = []
var _watchers: Array[Dictionary] = []
var _lamps: Array[Vector2] = []
var _exposure := 0.0
var _lit := 0.0
var _elapsed := 0.0
var _done := false
var _result: Dictionary = {}

func night():
	return get_tree().get_first_node_in_group("night_system")

func _build() -> void:
	match _stage:
		"choose": _build_choose()
		"street": _build_street()
		_: _build_after()

# ------------------------------------------------------------------ choosing
func _build_choose() -> void:
	var ns = night()
	var free: int = ns.beds_free() if ns != null else 0
	var v := shell(840, 760, "The evening",
		"Day %d · %d bed%s free" % [GameState.day, free, "" if free == 1 else "s"])
	first_time_note(v, "night")
	v.add_child(UIKit.label(
		"You could go home. The ward fills up on its own eventually, and "
		+ "eventually is the problem.", 15, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	if free <= 0:
		v.add_child(UIKit.label(
			"Every bed is full. Anybody you meet tonight goes across town, "
			+ "and you will have taken the risk for nothing.",
			14, UIKit.WARN, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.rule())
	var list := UIKit.vbox(6)
	for spec in NightSystem.PLACES:
		list.add_child(_place_option(spec))
	v.add_child(UIKit.scroll(list))
	v.add_child(UIKit.button("Go home. It's been a day.", _go_home))

func _place_option(spec: Dictionary) -> Control:
	var p := UIKit.panel(UIKit.PANEL_LIGHT, 6)
	var bv := UIKit.vbox(2)
	bv.add_child(UIKit.label(String(spec["name"]), 17, UIKit.INK))
	bv.add_child(UIKit.label(String(spec["blurb"]), 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	var w := int(spec["watchers"])
	var l := int(spec["lamps"])
	bv.add_child(UIKit.label("%d other %s about · %s" % [
		w, "person" if w == 1 else "people",
		"unlit" if l == 0 else ("one lamp" if l == 1 else "%d lamps" % l)],
		12, UIKit.WARN if w + l >= 5 else UIKit.INK_DIM))
	bv.add_child(UIKit.button("Go there", func(): _begin(spec)))
	p.add_child(bv)
	return p

func _begin(spec: Dictionary) -> void:
	_place = spec
	_mark_name = NightSystem.mark_name(String(spec["id"]) + str(GameState.day))
	_stage = "street"
	AudioMgr.play("door", -14.0)
	rebuild()

# ------------------------------------------------------------------ the street
func _build_street() -> void:
	var v := shell(900, 740, String(_place["name"]),
		"%s, walking home" % _mark_name)
	_coach = UIKit.label(
		"Hold the left mouse button to walk. Get next to them without standing "
		+ "in anybody's eyeline, then press Space.",
		15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_coach)

	_lay_out()

	_canvas = Control.new()
	_canvas.custom_minimum_size = FIELD
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_street)
	v.add_child(_canvas)

	_clock = UIKit.label("", 16, UIKit.WARN, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_clock)
	set_process(true)
	set_process_unhandled_input(true)

func _lay_out() -> void:
	var key := String(_place["id"])
	_route = [
		Vector2(FIELD.x * 0.94, FIELD.y * 0.20),
		Vector2(FIELD.x * 0.52, FIELD.y * 0.28),
		Vector2(FIELD.x * 0.44, FIELD.y * 0.66),
		Vector2(FIELD.x * 0.08, FIELD.y * 0.74),
	]
	_mark = _route[0]
	_me = Vector2(FIELD.x * 0.06, FIELD.y * 0.14)
	_watchers.clear()
	var n := int(_place["watchers"])
	for i in n:
		var t: float = (float(i) + 0.5) / float(n)
		_watchers.append({
			"at": Vector2(FIELD.x * (0.16 + 0.68 * t),
				FIELD.y * (0.16 + 0.62 * fposmod(float(RNG.randf_s("%s_w%d" % [key, i])), 1.0))),
			"face": TAU * float(RNG.randf_s("%s_f%d" % [key, i])),
			"sweep": 0.28 + 0.42 * float(RNG.randf_s("%s_s%d" % [key, i])),
			"phase": TAU * float(RNG.randf_s("%s_p%d" % [key, i])),
		})
	_lamps.clear()
	var lamps := int(_place["lamps"])
	for i in lamps:
		var t2: float = (float(i) + 0.5) / float(maxi(1, lamps))
		_lamps.append(Vector2(FIELD.x * (0.22 + 0.60 * t2), FIELD.y * (0.30 + 0.36 * sin(t2 * 3.1))))

## Where a watcher is looking right now. They sweep rather than stare, so the
## street has a rhythm you can read and wait out.
func _watcher_facing(w: Dictionary) -> float:
	return float(w["face"]) + sin(_elapsed * 0.9 + float(w["phase"])) * float(w["sweep"])

const CONE_HALF := 0.46
const CONE_RANGE := 190.0

func _seen_by(w: Dictionary) -> float:
	var to: Vector2 = _me - Vector2(w["at"])
	var dist := to.length()
	if dist > CONE_RANGE:
		return 0.0
	var facing := _watcher_facing(w)
	var off: float = absf(wrapf(to.angle() - facing, -PI, PI))
	if off > CONE_HALF:
		return 0.0
	# Dead centre and close is the worst place to be; the edge of a cone at
	# range is survivable.
	return clampf((1.0 - off / CONE_HALF) * (1.0 - dist / CONE_RANGE), 0.0, 1.0)

func _lamplight() -> float:
	var best := 0.0
	for l in _lamps:
		best = maxf(best, clampf(1.0 - _me.distance_to(l) / 120.0, 0.0, 1.0))
	return best

func _process(delta: float) -> void:
	if _done or _canvas == null:
		return
	_elapsed += delta

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var to := _canvas.get_local_mouse_position() - _me
		if to.length() > 4.0:
			_me += to.normalized() * SPEED * delta
			_me = _me.clamp(Vector2(14, 14), FIELD - Vector2(14, 14))

	# They walk home whether you are ready or not.
	_mark_t += delta * float(_place["mark_speed"]) / _route_length()
	_mark = _point_on_route(clampf(_mark_t, 0.0, 1.0))

	_lit = _lamplight()
	var watched := 0.0
	for w in _watchers:
		watched = maxf(watched, _seen_by(w))
	# A lamp does not make people look at you. It makes what they see usable.
	var rate: float = watched * (0.55 + _lit * 0.85)
	if rate > 0.0:
		_exposure = clampf(_exposure + rate * delta * 0.62, 0.0, 1.0)
		if fmod(_elapsed, 0.5) < delta:
			AudioMgr.play("tick", -26.0, 1.4)
	else:
		# Standing in the dark doing nothing does not undo being seen, but it
		# does let a bad moment stop getting worse.
		_exposure = maxf(0.0, _exposure - delta * 0.05)

	if _clock != null:
		var left: float = maxf(0.0, SECONDS - _elapsed)
		_clock.text = "%0.1fs   ·   %s" % [left, _exposure_word()]
		_clock.add_theme_color_override("font_color", _exposure_colour())
	_canvas.queue_redraw()

	if _mark_t >= 1.0 or _elapsed >= SECONDS:
		_resolve(false)

func _route_length() -> float:
	var total := 0.0
	for i in range(_route.size() - 1):
		total += _route[i].distance_to(_route[i + 1])
	return maxf(total, 1.0)

func _point_on_route(t: float) -> Vector2:
	var want: float = t * _route_length()
	var run := 0.0
	for i in range(_route.size() - 1):
		var seg: float = _route[i].distance_to(_route[i + 1])
		if run + seg >= want:
			return _route[i].lerp(_route[i + 1], (want - run) / maxf(seg, 0.001))
		run += seg
	return _route[_route.size() - 1]

func _exposure_word() -> String:
	if _exposure < 0.12: return "nobody has looked at you"
	if _exposure < NightSystem.CLEAN: return "a glance, maybe"
	if _exposure < NightSystem.MESSY: return "somebody has definitely seen you"
	return "you are being watched"

func _exposure_colour() -> Color:
	if _exposure < NightSystem.CLEAN: return UIKit.GOOD
	if _exposure < NightSystem.MESSY: return UIKit.WARN
	return UIKit.BAD

func _unhandled_input(event: InputEvent) -> void:
	if _done or _stage != "street":
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		if _me.distance_to(_mark) <= REACH:
			_resolve(true)
		else:
			AudioMgr.play("error", -20.0)

# ------------------------------------------------------------------ drawing
func _draw_street() -> void:
	var ci := _canvas
	var font := ThemeDB.fallback_font
	ci.draw_rect(Rect2(Vector2.ZERO, FIELD), Color(0.06, 0.07, 0.10))

	# Buildings along both edges, with a few windows still on. Without them the
	# field is a dark rectangle with dots in it; with them it is a street, and
	# the road in the middle is somewhere you are exposed.
	_draw_terrace(ci, 0.0, FIELD.y * 0.30, true)
	_draw_terrace(ci, FIELD.y * 0.68, FIELD.y * 0.32, false)

	# Pavement, kerb, road.
	ci.draw_rect(Rect2(Vector2(0, FIELD.y * 0.30), Vector2(FIELD.x, FIELD.y * 0.38)),
		Color(0.11, 0.12, 0.16))
	for i in 13:
		var x: float = FIELD.x * (0.02 + 0.078 * float(i))
		ci.draw_line(Vector2(x, FIELD.y * 0.30), Vector2(x, FIELD.y * 0.375),
			Color(0.16, 0.17, 0.21), 1.5)
		ci.draw_line(Vector2(x, FIELD.y * 0.615), Vector2(x, FIELD.y * 0.68),
			Color(0.16, 0.17, 0.21), 1.5)
	ci.draw_rect(Rect2(Vector2(0, FIELD.y * 0.375), Vector2(FIELD.x, FIELD.y * 0.24)),
		Color(0.09, 0.09, 0.12))
	for i in 9:
		ci.draw_rect(Rect2(Vector2(FIELD.x * (0.04 + 0.11 * float(i)), FIELD.y * 0.487),
			Vector2(34, 4)), Color(0.34, 0.34, 0.29, 0.55))

	for l in _lamps:
		for i in range(6, 0, -1):
			ci.draw_circle(l, 22.0 * float(i), Color(1.0, 0.90, 0.62, 0.026))
		ci.draw_line(l, l + Vector2(0, -26), Color(0.30, 0.32, 0.36), 3.0)
		ci.draw_circle(l, 7.0, Color(1.0, 0.94, 0.72))

	for w in _watchers:
		_draw_cone(ci, w)
	for w2 in _watchers:
		_draw_person(ci, Vector2(w2["at"]), 13.0, Color(0.44, 0.47, 0.55),
			_watcher_facing(w2))

	# Them. Ringed and named, so there is never a question which shape matters.
	var near: bool = _me.distance_to(_mark) <= REACH
	ci.draw_arc(_mark, REACH, 0.0, TAU, 26,
		Color(0.55, 0.94, 0.84, 0.85 if near else 0.34), 2.5, true)
	_draw_person(ci, _mark, 14.0, Color(0.84, 0.70, 0.50), _mark_heading())
	ci.draw_string(font, _mark + Vector2(-46, 34), _mark_name,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.86, 0.82, 0.74, 0.85))

	# You. The dot stays yours; how visible you are is a halo around it, because
	# tinting the marker itself made it the same muddy colour as everybody else
	# at exactly the moment it mattered most.
	if _exposure > 0.02:
		ci.draw_arc(_me, 20.0 + _exposure * 12.0, 0.0, TAU, 26,
			Color(0.94, 0.34, 0.30, 0.30 + _exposure * 0.6), 2.0 + _exposure * 3.0, true)
	if _lit > 0.05:
		ci.draw_circle(_me, 24.0, Color(1.0, 0.92, 0.66, _lit * 0.10))
	_draw_person(ci, _me, 14.0, Color(0.36, 0.80, 0.72), (_mark - _me).angle(), true)

	ci.draw_string(font, Vector2(18, 26), String(_place["name"]).to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.62, 0.66, 0.74, 0.8))
	if near:
		ci.draw_string(font, _mark + Vector2(-34, -30), "[Space]",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.72, 0.98, 0.88))

## A person from above: shoulders, a head, and which way they are pointing.
static func _draw_person(ci: CanvasItem, at: Vector2, r: float, tint: Color,
		facing: float, is_you := false) -> void:
	ci.draw_circle(at, r + 2.5, Color(0.04, 0.05, 0.07))
	ci.draw_circle(at, r, tint)
	ci.draw_circle(at, r * 0.52, tint.lightened(0.30))
	var nose: Vector2 = at + Vector2.from_angle(facing) * (r * 0.72)
	ci.draw_circle(nose, r * 0.30, Color(0.96, 0.96, 0.94))
	if is_you:
		ci.draw_arc(at, r + 4.5, 0.0, TAU, 24, Color(0.86, 0.98, 0.94, 0.9), 2.0, true)

func _mark_heading() -> float:
	var ahead := _point_on_route(clampf(_mark_t + 0.02, 0.0, 1.0))
	var d := ahead - _mark
	return d.angle() if d.length() > 0.5 else 0.0

## Two rows of buildings with the odd window still lit. Cheap, and it is the
## difference between "a street at night" and "a dark rectangle".
func _draw_terrace(ci: CanvasItem, top: float, tall: float, upper: bool) -> void:
	var n := 9
	for i in n:
		var w: float = FIELD.x / float(n)
		var x: float = float(i) * w
		var h: float = tall * (0.72 + 0.28 * fposmod(sin(float(i) * 12.9898) * 43758.5, 1.0))
		var y: float = top if upper else top + (tall - h)
		ci.draw_rect(Rect2(Vector2(x + 2, y), Vector2(w - 4, h)), Color(0.10, 0.10, 0.14))
		ci.draw_rect(Rect2(Vector2(x + 2, y), Vector2(w - 4, h)),
			Color(0.16, 0.17, 0.22), false, 2.0)
		for row in 2:
			for col in 3:
				if (i + row * 3 + col) % 4 == 1:
					continue
				var lit: bool = (i * 7 + row * 3 + col) % 5 < 2
				ci.draw_rect(Rect2(
					Vector2(x + 10 + float(col) * (w - 22) / 3.0, y + 12 + float(row) * (h * 0.42)),
					Vector2(12, 14)),
					Color(0.98, 0.86, 0.52, 0.55) if lit else Color(0.13, 0.14, 0.18))

func _draw_cone(ci: CanvasItem, w: Dictionary) -> void:
	var at: Vector2 = Vector2(w["at"])
	var facing := _watcher_facing(w)
	var pts := PackedVector2Array([at])
	var steps := 14
	for i in range(steps + 1):
		var a: float = facing - CONE_HALF + 2.0 * CONE_HALF * float(i) / float(steps)
		pts.append(at + Vector2.from_angle(a) * CONE_RANGE)
	ci.draw_colored_polygon(pts, Color(0.95, 0.88, 0.55, 0.055))
	ci.draw_line(at, at + Vector2.from_angle(facing - CONE_HALF) * CONE_RANGE,
		Color(0.95, 0.88, 0.55, 0.16), 1.5)
	ci.draw_line(at, at + Vector2.from_angle(facing + CONE_HALF) * CONE_RANGE,
		Color(0.95, 0.88, 0.55, 0.16), 1.5)

# ------------------------------------------------------------------ afterwards
func _resolve(reached: bool) -> void:
	if _done:
		return
	_done = true
	set_process(false)
	var ns = night()
	if reached:
		AudioMgr.play("crack", -6.0)
		AudioMgr.play("gasp", -12.0)
	if ns != null:
		_result = ns.resolve(String(_place["id"]), _mark_name, _exposure, reached)
	_stage = "after"
	rebuild()

func _build_after() -> void:
	var outcome := String(_result.get("outcome", "missed"))
	var headings := {
		"clean": "Nobody saw a thing",
		"messy": "Somebody saw something",
		"caught": "Everybody saw everything",
		"missed": "You went home",
	}
	var heading := String(headings.get(outcome, "You went home"))
	var tints := {"clean": UIKit.GOOD, "messy": UIKit.WARN, "caught": UIKit.BAD}
	var tint: Color = tints.get(outcome, UIKit.INK_DIM)
	var v := shell(760, 520, heading, String(_place.get("name", "")))
	var box := UIKit.panel(UIKit.PANEL_LIGHT, 6, 2, tint)
	var bv := UIKit.vbox(4)
	bv.add_child(UIKit.label(String(_result.get("line", "")), 16, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	if bool(_result.get("admitted", false)):
		bv.add_child(UIKit.label("%s will be on your list in the morning." % _mark_name,
			15, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT, true))
		if outcome != "clean":
			bv.add_child(UIKit.label(
				"They will be in one of your beds for a week, trying to place your face.",
				14, UIKit.BAD, HORIZONTAL_ALIGNMENT_LEFT, true))
	box.add_child(bv)
	v.add_child(box)
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Home", _go_home))

func _go_home() -> void:
	close()
	var ss = shift_system()
	if ss != null:
		ss.call_deferred("next_day")
