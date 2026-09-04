extends RefCounted
## CAN A PERSON ACTUALLY PLAY IT, WITH THE THING IN THEIR HANDS.
##
## Every other harness in tests/ reaches past the input layer: the smoke run
## calls `w.write_entry()`, the playtest calls `w.set_disposition()`, the
## screenshot run calls `ui.open()`. All of them would pass on a build where
## nothing was bound to anything.
##
## This one presses the buttons. It walks the doctor across the ward with the
## stick, aims with the other stick, taps use, navigates the card that opens,
## chooses something on it and backs out — and it found, on the first run, that
## a pad could look all the way round the room without taking a step (the four
## move actions had a key each and no axis), and that no screen in the game
## ever took focus, so the D-pad moved a selection that did not exist and A and
## B were not bound to `ui_accept` and `ui_cancel` at all. The Controls screen
## had promised the opposite of all of that for months.
##
## Two plans:
##   pad   — a controller, and nothing else. Runs anywhere, including headless.
##   keys  — WASD, the mouse and [E]. Mouse LOOK needs a captured cursor, which
##           the dummy display driver will not give, so this plan says so and
##           stops rather than passing by doing nothing; ./play.sh runs it under
##           Xvfb where the capture is real.

var tree: SceneTree = null
var plan := "pad"
var game: Node = null
var frames := 0
var stage := "boot"
var errors: Array[String] = []
var notes: Array[String] = []

## Who we are walking up to, and where we started from.
var _target: Node3D = null
var _from := Vector3.ZERO
var _stage_since := 0
## Everything the crosshair has said, and every screen the game has been asked
## to open, collected off the bus rather than read out of the UI — a prompt the
## player never sees is not a prompt.
var _prompts: Array[String] = []
var _opened: Array[String] = []
var _focus_at_open := ""
## The route to the bedside, and how far along it we are.
var _path: PackedVector3Array = PackedVector3Array()
var _wp := 0
var _last_seen := Vector3.ZERO
var _last_progress := 0

const REACH := 2.4
const WALK_FRAMES := 900

func start() -> void:
	# A FIXED WARD. `start_new_career(0)` means "seed off the clock", so this
	# played a different building every run and a failure could not be repeated.
	GameState.start_new_career(20260821)
	GameState.set_flag("tutorial_done", true)
	EventBus.interact_prompt.connect(func(t, _s): _prompts.append(String(t)))
	EventBus.ui_opened.connect(func(id): _opened.append(String(id)))
	var packed: PackedScene = load("res://scenes/Game.tscn")
	if packed == null:
		_fail("Game.tscn failed to load")
		return
	game = packed.instantiate()
	tree.root.add_child(game)

# ------------------------------------------------------------------ input
## Real events, not `Input.action_press`.
##
## `Input.action_press` sets the polled state of an action and dispatches
## NOTHING, so `_unhandled_input` never runs and every screen in the game is
## unreachable through it — which is exactly the layer this harness exists to
## test. The first version of this file used it and could not close the morning
## briefing.
func _press_pad(button: int, down: bool) -> void:
	var e := InputEventJoypadButton.new()
	e.device = 0
	e.button_index = button
	e.pressed = down
	Input.parse_input_event(e)

func _press_key(code: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = down
	Input.parse_input_event(e)

func _stick(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = 0
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)

func _mouse(rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	Input.parse_input_event(e)

## Whichever button this plan uses for a given job.
func _tap(job: String, down: bool) -> void:
	if plan == "pad":
		match job:
			"accept": _press_pad(JOY_BUTTON_A, down)
			"back": _press_pad(JOY_BUTTON_B, down)
			"use": _press_pad(JOY_BUTTON_X, down)
			"down": _press_pad(JOY_BUTTON_DPAD_DOWN, down)
		return
	match job:
		"accept": _press_key(KEY_ENTER, down)
		"back": _press_key(KEY_ESCAPE, down)
		"use": _press_key(KEY_E, down)
		"down": _press_key(KEY_DOWN, down)

## Walk forward, with whatever this plan walks with.
func _walk(on: bool) -> void:
	if plan == "pad":
		_stick(JOY_AXIS_LEFT_Y, -1.0 if on else 0.0)
	else:
		_press_key(KEY_W, on)

## Turn toward a point, with whatever this plan turns with. Proportional, so it
## settles instead of oscillating: a constant push overshoots by exactly as much
## as it took to get there.
func _aim_at(p: Player, at: Vector3) -> void:
	var d: Vector3 = at - p.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var err := wrapf(want_yaw - p.rotation.y, -PI, PI)
	if plan == "pad":
		# `_yaw -= shaped.x * sens * delta`, so pushing the stick right turns
		# left. The shaping curve squares whatever is past the deadzone, so a
		# small error needs a push well clear of it to move at all.
		var push := clampf(-err * 1.6, -1.0, 1.0)
		if absf(push) < 0.35:
			push = 0.35 * signf(push) if absf(err) > 0.02 else 0.0
		_stick(JOY_AXIS_RIGHT_X, push)
	else:
		_mouse(Vector2(-err * 90.0, 0.0))

# ------------------------------------------------------------------ the run
func tick() -> bool:
	frames += 1
	tree.paused = false
	var p := tree.get_first_node_in_group("player") as Player
	match stage:
		"boot":
			if frames > 20:
				_check_the_way_in()
				_to("briefing")
		"briefing":
			# One tap of accept on the card that owns the way into the shift.
			if _since() == 2:
				_tap("accept", true)
			elif _since() == 4:
				_tap("accept", false)
			elif _since() > 12:
				_check_the_briefing_can_be_dismissed(p)
				if plan == "keys" and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					_note("mouse look needs a captured cursor; this plan needs "
						+ "a display. ./play.sh runs it under Xvfb.")
					_report()
					return true
				_pick_somebody(p)
				_to("walk")
		"walk":
			if _walk_toward(p):
				_check_the_walk(p)
				_to("use")
		"use":
			# Tap, and release inside LONG_PRESS: a patient has both `interact`
			# and `interact_held`, so the tap only fires on the way UP.
			if _since() == 2:
				_tap("use", true)
			elif _since() == 8:
				_tap("use", false)
			elif _since() > 20:
				_check_the_card_opened()
				_to("navigate")
		"navigate":
			if _since() == 2:
				_focus_at_open = _focused()
				_tap("down", true)
			elif _since() == 4:
				_tap("down", false)
			elif _since() > 14:
				_check_the_card_can_be_used()
				_to("leave")
		"leave":
			if _since() == 2:
				_tap("back", true)
			elif _since() == 4:
				_tap("back", false)
			elif _since() > 14:
				_check_the_way_out()
				_to("done")
		"done":
			_report()
			return true
	if frames > 4000:
		_fail("stuck in '%s'" % stage)
		_report()
		return true
	return false

func _to(s: String) -> void:
	stage = s
	_stage_since = frames

func _since() -> int:
	return frames - _stage_since

# ------------------------------------------------------------------ checks
func _check_the_way_in() -> void:
	_ok(tree.get_first_node_in_group("player") != null, "the doctor exists")
	_ok(game != null and game.ui != null and game.ui.current_id == "morning",
		"and the morning briefing is up in front of them")
	# THE PROMISE THE CONTROLS SCREEN MAKES. Every action it names, bound.
	var missing: Array = []
	for action in Settings.PAD_DEFAULTS.keys() + Settings.PAD_UI.keys() \
			+ Settings.PAD_AXES.keys():
		var a := String(action)
		var found := false
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				found = true
		if not found:
			missing.append(a)
	_ok(missing.is_empty(), "every action a pad needs is bound to one%s"
		% ("" if missing.is_empty() else " — missing " + ", ".join(PackedStringArray(missing))))

func _check_the_briefing_can_be_dismissed(p) -> void:
	_ok(game.ui.current_id == "",
		"one press of %s starts the round" % ("A" if plan == "pad" else "Enter"))
	_ok(p != null and not p.input_locked,
		"and hands the ward back to the player")

func _check_the_walk(p) -> void:
	var moved: float = p.global_position.distance_to(_from)
	var to_them: float = p.global_position.distance_to(_target.global_position)
	_ok(moved > 1.0, "the %s walks the doctor across the ward (%.1fm)"
		% ["left stick" if plan == "pad" else "W key", moved])
	_ok(to_them <= REACH + 0.6,
		"and up to somebody (%.1fm from %s)" % [to_them, _target.name])
	var named := false
	for t in _prompts:
		if t.begins_with("Talk to"):
			named = true
	_ok(named, "and the crosshair offers them by name")

func _check_the_card_opened() -> void:
	_ok(_opened.has("patient"),
		"one tap of %s opens their card" % ("X" if plan == "pad" else "E"))
	_ok(_focused() != "", "and something on it is selected, so a pad has "
		+ "somewhere to start")

func _check_the_card_can_be_used() -> void:
	var now := _focused()
	_ok(now != "" and now != _focus_at_open,
		"the selection moves down the card ('%s' -> '%s')" % [_focus_at_open, now])

func _check_the_way_out() -> void:
	_ok(game.ui.current_id == "",
		"%s closes it again" % ("B" if plan == "pad" else "Escape"))

# ------------------------------------------------------------------ walking
func _pick_somebody(p) -> void:
	var ps = tree.get_first_node_in_group("patient_system")
	var best = null
	var best_d := 1e9
	for pat in ps.active():
		var b = ps.get_body(pat.id)
		if b == null or not b.is_inside_tree():
			continue
		var d: float = p.global_position.distance_to(b.global_position)
		if d < best_d:
			best_d = d
			best = b
	_target = best
	_from = p.global_position if p else Vector3.ZERO
	_last_seen = _from
	_last_progress = frames
	if _target == null:
		_fail("nobody on the ward to walk up to")
		return
	# THE SAME ROUTE A NURSE WOULD TAKE. Not `NavigationServer3D`: this hospital
	# is procedural and headless, so it navigates on its own deterministic A*
	# grid (`NavGrid`) and the engine's navigation map has no regions in it at
	# all — asking the server returns an empty path and no error, which read as
	# "there is no way into the ward".
	var h = tree.get_first_node_in_group("hospital")
	_path = h.nav.find_path(_from, _target.global_position) if h and h.nav else PackedVector3Array()
	_wp = 0
	if _path.size() < 2:
		_fail("no route from the corridor to a bed — the nav grid has a hole in it")

## Steer along the route and walk it, then stop pushing anything.
##
## A ROUTE, not a bearing. The doctor spawns in the corridor and the beds are
## down the far wall of the ward, through a doorway at x=10 — so walking at the
## patient in a straight line walks into the ward wall and stays there, which is
## exactly what the first version of this did for nine hundred frames before
## announcing that the ward was 8.6m wide. The waypoints come off the same
## navigation map the nurses use; the STEERING and the walking are still real
## input, which is the part being tested.
func _walk_toward(p) -> bool:
	if p == null or _target == null:
		return true
	var here: Vector3 = p.global_position
	var at: Vector3 = _target.head_position() if _target.has_method("head_position") \
		else _target.global_position
	var flat := Vector3(at.x, here.y, at.z)
	var to_them: float = here.distance_to(flat)
	# Close enough to speak to: stop, and look at them rather than at the floor
	# in front of them.
	if to_them <= REACH:
		_walk(false)
		if plan == "pad":
			_stick(JOY_AXIS_LEFT_Y, 0.0)
		_aim_at(p, at)
		return _aimed_at_them(p)
	# Otherwise: the next corner of the route.
	while _wp < _path.size() - 1 and here.distance_to(
			Vector3(_path[_wp].x, here.y, _path[_wp].z)) < 0.75:
		_wp += 1
	var goal := flat
	if _wp < _path.size():
		goal = Vector3(_path[_wp].x, here.y, _path[_wp].z)
	_aim_at(p, goal)
	# Only walk once we are pointing more or less at it, or the doctor spends
	# the whole corridor walking sideways into the wall.
	var err: float = absf(wrapf(atan2(-(goal - here).x, -(goal - here).z)
		- p.rotation.y, -PI, PI))
	_walk(err < 0.5)
	# STUCK IS A RESULT, NOT A TIMEOUT. If the doctor stops making ground for
	# four seconds, something in the building is in the way and that is worth
	# saying out loud rather than waiting out.
	if here.distance_to(_last_seen) > 0.25:
		_last_seen = here
		_last_progress = frames
	elif frames - _last_progress > 240:
		_fail("the doctor is wedged %.1fm from the bedside at %s"
			% [to_them, _round(here)])
		return true
	return _since() > WALK_FRAMES

## Pointing at them closely enough for the crosshair to be on them, or out of
## patience. The interactor's ray is 2.9m long and thin.
func _aimed_at_them(p) -> bool:
	if _since() > WALK_FRAMES:
		return true
	var at: Vector3 = _target.head_position() if _target.has_method("head_position") \
		else _target.global_position
	var d: Vector3 = at - p.global_position
	return absf(wrapf(atan2(-d.x, -d.z) - p.rotation.y, -PI, PI)) < 0.06

func _round(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [v.x, v.z]

func _focused() -> String:
	var vp := tree.root.get_viewport()
	var o := vp.gui_get_focus_owner() if vp else null
	if o == null:
		return ""
	return String(o.text) if "text" in o else o.get_class()

# ------------------------------------------------------------------ reporting
func _fail(msg: String) -> void:
	errors.append(msg)

func _note(msg: String) -> void:
	notes.append("  -- " + msg)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		notes.append("  ok: " + msg)
	else:
		errors.append(msg)

func _report() -> void:
	for n in notes:
		print(n)
	print("\n--------------------------------------")
	if errors.is_empty():
		print("PLAY RUN PASSED — %s, %d checks" % [plan, notes.size()])
	else:
		print("PLAY RUN FAILED — %s, %d problem(s):" % [plan, errors.size()])
		for e in errors:
			print("  " + e)
	print("--------------------------------------\n")
