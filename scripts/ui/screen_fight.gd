extends ScreenBase
## A physical disagreement with a patient.
##
## The one thing in this game where the punishment is your own time. Everything
## else you do badly costs standing, which you can still trade against; losing
## this costs the afternoon, the evening and a bill, and no paperwork makes that
## back.
##
## The manoeuvre is a side, not a reaction time. They wind up on your left or
## your right and you cover that side before it lands — the window is generous
## and the wind-up is what shortens, so the last two exchanges are tense because
## you have less time to READ, not because you have less time to twitch.
##
## Drawn on the person, like every other minigame here: their head, their
## shoulders and the arm that is about to arrive, in their own skin tone.

const FIELD := Vector2(760, 420)

var _patient = null
var _mind: Mind = null
var _tone := Color(0.88, 0.72, 0.60)

var _canvas: Control = null
var _status: Label = null
var _coach: Label = null

## The exchange in flight. `_side` is -1 for your left, +1 for your right.
var _side := 0
var _wind := 0.0            ## seconds the current wind-up lasts
var _t := 0.0               ## seconds into the current wind-up
var _recover := 0.0
var _exchange := 0
var _their_guard := Brawl.THEIR_GUARD
var _your_guard := Brawl.YOUR_GUARD
var _flash := 0.0
var _flash_good := false
var _blocked := false
var _resolved := false
var _last := ""

func _init() -> void:
	# You are standing in front of them. That is the entire point of it.
	pauses_world = false

func _build() -> void:
	_patient = patient_system().get_patient(String(ctx.get("patient_id", ""))) \
		if patient_system() else null
	if _patient == null or not Brawl.can_fight(_patient):
		close()
		return
	var sus = suspicion()
	_mind = sus.mind_of(_patient.id) if sus != null else null
	_tone = Anatomy.tone_for(_patient.display_name)
	if _resolved:
		_build_after()
	else:
		_build_ring()

func _build_ring() -> void:
	var v := shell(880, 700, "A difference of opinion",
		"%s · %s" % [_patient.display_name, _patient.condition_name()])
	v.add_child(UIKit.label(
		'"%s"' % Brawl.opener(_patient, _mind, hash(_patient.id)),
		16, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	_coach = UIKit.label(
		"Cover the side they wind up on. [A] or [←] for your left, [D] or [→] "
		+ "for your right — or click that half of the picture.",
		15, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(_coach)

	var frame := UIKit.panel(Color(0.13, 0.15, 0.19), 4, 2, Color(0.30, 0.36, 0.42))
	_canvas = Control.new()
	_canvas.custom_minimum_size = FIELD
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP
	_canvas.draw.connect(_draw_ring)
	_canvas.gui_input.connect(_on_click)
	frame.add_child(_canvas)
	v.add_child(frame)

	_status = UIKit.label("", 17, UIKit.INK, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(_status)
	v.add_child(UIKit.spacer(4))
	card_footer(UIKit.button("Back off", func():
		_resolve(false)))
	_next_exchange()
	set_process(true)

## ------------------------------------------------------------------ the fight
func _next_exchange() -> void:
	_side = -1 if RNG.chance("brawl", 0.5) else 1
	_wind = Brawl.telegraph_for(_exchange)
	_t = 0.0
	_blocked = false
	_exchange += 1

func _process(delta: float) -> void:
	if _resolved or _canvas == null or not is_instance_valid(_canvas):
		return
	_flash = maxf(0.0, _flash - delta * 2.2)
	if _recover > 0.0:
		_recover -= delta
		if _recover <= 0.0:
			_next_exchange()
		_canvas.queue_redraw()
		return
	_t += delta
	# Keyboard, polled: the same way every other procedure screen reads input,
	# so a key held down through a swing does not count twice.
	if not _blocked:
		if Input.is_action_just_pressed("move_left") or Input.is_key_pressed(KEY_LEFT):
			_try_block(-1)
		elif Input.is_action_just_pressed("move_right") or Input.is_key_pressed(KEY_RIGHT):
			_try_block(1)
	if _t >= _wind + Brawl.WINDOW:
		_land(false)
	_canvas.queue_redraw()

func _on_click(event: InputEvent) -> void:
	if _resolved or _recover > 0.0 or _blocked:
		return
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		_try_block(-1 if event.position.x < FIELD.x * 0.5 else 1)

## A block only counts if it is on the right side AND inside the window. Too
## early is a guess, and the game should not reward guessing at the exact moment
## it starts asking you to read.
func _try_block(side: int) -> void:
	_blocked = true
	var early: bool = _t < _wind - Brawl.WINDOW
	if side == _side and not early:
		_land(true)
	else:
		_last = "Too early." if early else "Wrong side."
		_land(false)

func _land(blocked: bool) -> void:
	_recover = Brawl.RECOVER
	_flash = 1.0
	_flash_good = blocked
	var says := ""
	if blocked:
		_their_guard -= 1
		says = "Blocked, and returned."
		AudioMgr.play("thud", -12.0, 1.25)
	else:
		_your_guard -= 1
		# `_last` carries WHY, when there is a why — a wrong side and a missed
		# swing are different mistakes and want different words.
		says = _last if _last != "" else "That one landed."
		AudioMgr.play("thud", -6.0, 0.85)
	_last = ""
	if _status != null:
		_status.text = says
	if _their_guard <= 0:
		_resolve(true)
	elif _your_guard <= 0:
		_resolve(false)

func _resolve(won: bool) -> void:
	if _resolved:
		return
	_resolved = true
	set_process(false)
	var ts = treatment_system()
	var where := Vector3.ZERO
	var body = patient_system().get_body(_patient.id) if patient_system() else null
	if body != null and body.is_inside_tree():
		where = body.global_position
	_result = ts.apply_brawl(_patient, won, where) if ts != null else {}
	_won = won
	rebuild()

var _result: Dictionary = {}
var _won := false

func _build_after() -> void:
	var tint: Color = UIKit.WARN if _won else UIKit.BAD
	var v := shell(760, 480, String(_result.get("label", "It is over")),
		_patient.display_name)
	v.add_child(UIKit.stamp("won" if _won else "lost", tint))
	var box := UIKit.panel(UIKit.NOTE, 4, 2, tint)
	var bv := UIKit.vbox(4)
	bv.add_child(UIKit.label(String(_result.get("line", "")), 16, UIKit.INK,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	if _won:
		bv.add_child(UIKit.field("Their stay", "+%d days" % int(
			ceil(float(_result.get("stay", 0.0)))), UIKit.MONEY))
	else:
		bv.add_child(UIKit.field("Billed to you",
			UIKit.money_str(int(_result.get("bill", 0))), UIKit.BAD))
		bv.add_child(UIKit.field("The rest of today", "gone", UIKit.BAD))
		bv.add_child(UIKit.field("Tonight", "you are in no state", UIKit.BAD))
	box.add_child(bv)
	v.add_child(box)
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.button("Right", close))

## ------------------------------------------------------------------ drawing
func _draw_ring() -> void:
	var ci: CanvasItem = _canvas
	ci.draw_rect(Rect2(Vector2.ZERO, FIELD), Color(0.11, 0.13, 0.17))
	var wind: float = clampf(_t / maxf(_wind, 0.01), 0.0, 1.0)
	var throwing: float = clampf((_t - _wind) / maxf(Brawl.WINDOW, 0.01), 0.0, 1.0)
	var live: bool = _recover <= 0.0 and not _resolved

	# The two halves. Which side is coming is a PLACE on the screen that fills
	# up, not a letter you have to remember and not a word you have to read.
	for s in [-1, 1]:
		var x: float = 0.0 if s < 0 else FIELD.x * 0.5
		var half := Rect2(Vector2(x, 0), Vector2(FIELD.x * 0.5, FIELD.y))
		ci.draw_rect(half, Color(0.16, 0.19, 0.24))
		if live and _side == s:
			# Light. A saturated wash over the whole half turned the picture
			# brown and buried the person in it; the moving bar below is what
			# actually carries the timing.
			ci.draw_rect(half, Color(0.98, 0.62, 0.20, 0.05 + 0.10 * wind))
			ci.draw_rect(half, Color(1.0, 0.78, 0.34, 0.55 + 0.4 * wind), false, 4.0)
			# A bar that closes from the outside in. When it reaches the middle,
			# it has arrived — so "how long have I got" is a distance.
			var w: float = FIELD.x * 0.5 * wind
			var bx: float = (FIELD.x * 0.5 - w) if s < 0 else FIELD.x * 0.5
			ci.draw_rect(Rect2(Vector2(bx, FIELD.y * 0.5 - 9), Vector2(w, 18)),
				Color(1.0, 0.74, 0.26, 0.9))
			# The head of it, so the eye has an edge to track.
			var hx: float = FIELD.x * 0.5 - float(s) * 3.0
			ci.draw_rect(Rect2(Vector2(hx - 3, FIELD.y * 0.5 - 13),
				Vector2(6, 26)), Color(1.0, 0.92, 0.70, 0.95))
	ci.draw_line(Vector2(FIELD.x * 0.5, 0), Vector2(FIELD.x * 0.5, FIELD.y),
		Color(1, 1, 1, 0.08), 2.0)

	# Them. Shirt first, then skin, then a face — three groups so each gets its
	# own dark silhouette and the whole thing reads as one person in clothes
	# rather than one continuous sausage.
	var shirt: Color = _patient.shirt_color if _patient != null else Color(0.4, 0.5, 0.7)
	# Anatomy scales RADII by the field's height and POSITIONS by both axes, so
	# a shoulder placed at "one torso radius out" has to be converted: 0.15 of
	# the height is only 0.083 of the width. Getting this wrong is what had the
	# first version's arms floating a hand's width clear of the body.
	var ax: float = FIELD.y / FIELD.x
	var body: Array = [
		Anatomy.cap(0.50, 0.44, 0.50, 0.80, 0.150, 0.170, "skin"),
	]
	var limbs: Array = []
	for s in [-1, 1]:
		var sx: float = 0.50 + float(s) * 0.135 * ax
		var reach := 0.30
		var ey := 0.70
		if live and s == _side:
			# Draws back over the wind-up, then comes across on the throw.
			reach = 0.34 + 0.22 * wind - 0.72 * throwing
			ey = 0.58 - 0.13 * wind + 0.12 * throwing
		var ex: float = sx + float(s) * reach * ax
		body.append(Anatomy.cap(sx, 0.47, (sx + ex) * 0.5, (0.47 + ey) * 0.5,
			0.062, 0.056, "skin"))
		limbs.append(Anatomy.cap((sx + ex) * 0.5, (0.47 + ey) * 0.5, ex, ey,
			0.054, 0.060, "skin"))
		limbs.append(Anatomy.dot(ex, ey, 0.062, "skin"))
	Anatomy.draw_caps(ci, body, FIELD, shirt)
	Anatomy.draw_caps(ci, limbs, FIELD, _tone)
	Anatomy.draw_caps(ci, [
		Anatomy.cap(0.50, 0.355, 0.50, 0.415, 0.058, 0.070, "skin"),
		Anatomy.dot(0.50, 0.275, 0.098, "skin"),
	], FIELD, _tone)
	_face(ci, throwing if live else 0.0)

	# Guard bars, named. "Them" runs down as you land them, "you" runs down as
	# they land on you, and the whole question is answered by looking.
	var them: String = _patient.display_name if _patient != null else "them"
	_bar(ci, Vector2(20, 22), FIELD.x - 40,
		float(_their_guard) / float(Brawl.THEIR_GUARD),
		Color(0.42, 0.86, 0.62), them)
	_bar(ci, Vector2(20, FIELD.y - 32), FIELD.x - 40,
		float(_your_guard) / float(Brawl.YOUR_GUARD),
		Color(0.98, 0.56, 0.32), "you")

	if _flash > 0.0:
		var f: Color = Color(0.40, 0.95, 0.65, 0.20 * _flash) if _flash_good \
			else Color(0.98, 0.28, 0.24, 0.32 * _flash)
		ci.draw_rect(Rect2(Vector2.ZERO, FIELD), f)

## Eyes and a mouth. A blank oval is a mannequin, and you are supposed to feel
## slightly bad about this.
func _face(ci: CanvasItem, throwing: float) -> void:
	var head := Vector2(0.50, 0.275) * FIELD
	var r: float = 0.098 * FIELD.y
	for sx in [-1.0, 1.0]:
		var eye := head + Vector2(sx * r * 0.38, -r * 0.12)
		ci.draw_circle(eye, r * 0.24, Color(0.97, 0.98, 0.99))
		ci.draw_circle(eye + Vector2(0, r * 0.03), r * 0.12, Color(0.10, 0.11, 0.14))
		# Brows, angled down toward the middle. This is the entire performance.
		ci.draw_line(eye + Vector2(-sx * r * 0.26, -r * 0.34),
			eye + Vector2(sx * r * 0.26, -r * 0.18),
			Color(0.16, 0.13, 0.12), 3.0)
	var mouth := head + Vector2(0, r * 0.44)
	var open: float = r * (0.10 + 0.22 * throwing)
	ci.draw_rect(Rect2(mouth - Vector2(r * 0.28, open * 0.5),
		Vector2(r * 0.56, open)), Color(0.28, 0.16, 0.16))

func _bar(ci: CanvasItem, at: Vector2, w: float, frac: float, col: Color,
		who: String) -> void:
	var f := ThemeDB.fallback_font
	ci.draw_string(f, at + Vector2(2, -5), who, HORIZONTAL_ALIGNMENT_LEFT, -1, 13,
		Color(0.84, 0.88, 0.91))
	ci.draw_rect(Rect2(at, Vector2(w, 9)), Color(0.05, 0.07, 0.09, 0.9))
	ci.draw_rect(Rect2(at, Vector2(w * clampf(frac, 0.0, 1.0), 9)), col)
