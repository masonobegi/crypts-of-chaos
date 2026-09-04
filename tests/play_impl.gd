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
## Backing out of the furniture: how long for, and which way to lean.
var _unstick_until := 0
var _unstick_side := 1.0
var _replans := 0
## How close this particular approach has to get. A person is 2.4m; the office
## terminal is 1.5m, because it sits BEHIND A DOOR — the doctor was stopping
## two and a bit metres away with the crosshair on "Open door", which is the
## right distance from the terminal and the wrong side of the room.
var _reach := REACH
var _office_tries := 0
var _day_was := 0

const REACH := 2.4
## How long a single approach gets. The office is at the far end of the
## building through two doors, and the day plan walks it after five beds.
const WALK_FRAMES := 900
const WALK_FRAMES_FAR := 2400

## The `day` plan: which bed we are on, how many got decided, and what button
## the selection is currently hunting for.
var _bed := 0
var _decided := 0
var _want: Array = []
var _tries := 0
var _last_focus := ""
var _dir := 0
const SEEK_DIRS := ["down", "up", "right", "left"]
## Either of the two decisions is a decision. The plan is not testing WHICH one
## a player makes — it is testing that a controller can make one.
const _DECIDE := ["Send them home", "Keep them in overnight"]

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
	if plan != "keys":
		match job:
			"accept": _press_pad(JOY_BUTTON_A, down)
			"back": _press_pad(JOY_BUTTON_B, down)
			"use": _press_pad(JOY_BUTTON_X, down)
			"down": _press_pad(JOY_BUTTON_DPAD_DOWN, down)
			"up": _press_pad(JOY_BUTTON_DPAD_UP, down)
			"left": _press_pad(JOY_BUTTON_DPAD_LEFT, down)
			"right": _press_pad(JOY_BUTTON_DPAD_RIGHT, down)
		return
	match job:
		"accept": _press_key(KEY_ENTER, down)
		"back": _press_key(KEY_ESCAPE, down)
		"use": _press_key(KEY_E, down)
		"down": _press_key(KEY_DOWN, down)
		"up": _press_key(KEY_UP, down)
		"left": _press_key(KEY_LEFT, down)
		"right": _press_key(KEY_RIGHT, down)

## Walk forward, with whatever this plan walks with.
func _walk(on: bool) -> void:
	if plan != "keys":
		_stick(JOY_AXIS_LEFT_Y, -1.0 if on else 0.0)
	else:
		_press_key(KEY_W, on)

## Turn toward a point, with whatever this plan turns with. Proportional, so it
## settles instead of oscillating: a constant push overshoots by exactly as much
## as it took to get there.
## Turn toward a point in BOTH axES.
##
## Yaw only was enough for a patient, whose head is at eye height. It is not
## enough for a terminal on a desk: the ray leaves the camera horizontally at
## 1.6m, passes straight over the desk and hits whatever is behind it — which
## in the office is the door. The doctor stood a metre and a half from the
## thing that ends the shift, with the crosshair offering to open the door
## they had just walked through, for three attempts and two thousand frames.
func _aim_at(p: Player, at: Vector3) -> void:
	var eye: Vector3 = p.camera.global_position if p.camera != null \
		else p.global_position + Vector3.UP * 1.6
	var d: Vector3 = at - p.global_position
	var want_yaw := atan2(-d.x, -d.z)
	var err := wrapf(want_yaw - p.rotation.y, -PI, PI)
	var flat := Vector2(at.x - eye.x, at.z - eye.z).length()
	var want_pitch := atan2(at.y - eye.y, maxf(flat, 0.05))
	var perr := clampf(want_pitch, -1.4, 1.4) - p.head.rotation.x
	if plan != "keys":
		# `_yaw -= shaped.x * sens * delta`, so pushing the stick right turns
		# left. The shaping curve squares whatever is past the deadzone, so a
		# small error needs a push well clear of it to move at all.
		var push := clampf(-err * 1.6, -1.0, 1.0)
		if absf(push) < 0.35:
			push = 0.35 * signf(push) if absf(err) > 0.02 else 0.0
		_stick(JOY_AXIS_RIGHT_X, push)
		# `_pitch -= shaped.y * ...`, so pushing the stick DOWN looks down.
		var vpush := clampf(-perr * 1.6, -1.0, 1.0)
		if absf(vpush) < 0.35:
			vpush = 0.35 * signf(vpush) if absf(perr) > 0.02 else 0.0
		_stick(JOY_AXIS_RIGHT_Y, vpush)
	else:
		_mouse(Vector2(-err * 90.0, -perr * 90.0))

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
				if plan == "day":
					# NO SPECIAL FIRST BED. The pad and keys plans walk to
					# whoever is nearest and check the twelve things a first
					# approach can check; the day plan is a LOOP over the
					# roster, and starting it with a different bed from a
					# different code path left `_bed` pointing at somebody the
					# doctor was not standing in front of.
					_bed = 0
					_next_bed(p)
				else:
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
				if plan == "day":
					_bed += 1
					_next_bed(p)
				else:
					_to("done")
		# ------------------------------------------------------- the day plan
		"bed_walk":
			if _walk_toward(p):
				_to("bed_use")
		"bed_use":
			if _since() == 2:
				_tap("use", true)
			elif _since() == 8:
				_tap("use", false)
			elif _since() > 20:
				if String(game.ui.current_id) != "patient":
					_fail("the card would not open at bed %d — %s, %.1fm away, crosshair said '%s'"
						% [_bed + 1, _target.name if _target else "nobody",
							p.global_position.distance_to(_target.global_position)
								if _target else -1.0,
							String(_prompts[-1]) if not _prompts.is_empty() else ""])
					# ON TO THE NEXT ONE. Falling through to the office from
					# here walked nowhere, because the route was still the one
					# to this bed — and then opened this patient's card and
					# reported it as the office not working.
					_bed += 1
					_next_bed(p)
				else:
					_want = _DECIDE
					_tries = 0
					_dir = 0
					_last_focus = ""
					_to("bed_choose")
		"bed_choose":
			if _seek():
				_to("bed_settle")
		"bed_settle":
			# A PRESS IS NOT A RESULT UNTIL THE FRAME AFTER IT. Counting the
			# decision in the same tick that pressed the button read the state
			# from before the press, every time, on every bed: five decisions
			# made and "0 of 5" reported.
			if _since() > 8:
				if _held_or_sent():
					_decided += 1
				_to("bed_close")
		"bed_close":
			# The card rebuilds itself after a decision; one back closes it.
			if _since() == 2:
				_tap("back", true)
			elif _since() == 4:
				_tap("back", false)
			elif _since() > 12:
				_bed += 1
				_next_bed(p)
		"office_walk":
			# DOORS ON THE WAY. The office is a room with a door on it, and the
			# doctor was arriving at the desk's REACH radius with the door still
			# shut between them — 1.6m from the terminal, crosshair on "Open
			# door", pressing use at a door and calling it a broken terminal. A
			# person opens the door. So does this, whenever the crosshair offers
			# one, and then carries on walking.
			if _since() % 24 == 0 and not _prompts.is_empty() \
					and String(_prompts[-1]).begins_with("Open door"):
				_tap("use", true)
			elif _since() % 24 == 4:
				_tap("use", false)
			if _walk_toward(p):
				_to("office_use")
		"office_use":
			if _since() == 2:
				_tap("use", true)
			elif _since() == 6:
				_tap("use", false)
			elif _since() > 20:
				# THE DOOR FIRST, IF THERE IS ONE. The office is a room with a
				# door on it and the crosshair finds the door before it finds
				# the desk; one tap opens it, and then the walk finishes.
				if String(game.ui.current_id) != "records" and _office_tries < 3:
					_office_tries += 1
					_to("office_walk")
				else:
					_check_the_office_opens(p)
					# THE BUTTON, NOT THE CROSSHAIR. "Go home" is what the
					# terminal offers from across the room; the thing on the
					# records card is "Sign off for the night", and the seek
					# walked past it forty times looking for the wrong words.
					_want = ["Sign off for the night"]
					_tries = 0
					_dir = 0
					_last_focus = ""
					_to("office_choose")
		"office_choose":
			if _seek():
				_to("handover")
		"handover":
			# The review is a conversation: whatever she asks, answer it, and
			# keep answering until the card behind it is the end of the shift.
			if _since() > 6:
				if String(game.ui.current_id) == "day_over":
					_check_the_shift_can_be_finished()
					_want = ["Work tomorrow"]
					_tries = 0
					_dir = 0
					_last_focus = ""
					_day_was = GameState.day
					_to("tomorrow")
				elif _tries > 40:
					_fail("the handover would not finish (screen '%s')"
						% game.ui.current_id)
					_to("done")
				else:
					_tries += 1
					_tap("accept", true)
					_tap("accept", false)
					_to("handover")
		"tomorrow":
			# AND THE NEXT MORNING. The End of Shift card is not the end of
			# anything — "Work tomorrow" is the only thing that advances a
			# career, and the chain from one day to the next is the join that
			# has broken most often in this project.
			if _seek():
				_to("tomorrow_settle")
		"tomorrow_settle":
			if _since() > 20:
				_check_tomorrow_arrives()
				_to("done")
		"done":
			_report()
			return true
	if frames > (24000 if plan == "day" else 4000):
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
		"one press of %s starts the round" % ("Enter" if plan == "keys" else "A"))
	_ok(p != null and not p.input_locked,
		"and hands the ward back to the player")

func _check_the_walk(p) -> void:
	var moved: float = p.global_position.distance_to(_from)
	var to_them: float = p.global_position.distance_to(_target.global_position)
	_ok(moved > 1.0, "the %s walks the doctor across the ward (%.1fm)"
		% ["W key" if plan == "keys" else "left stick", moved])
	_ok(to_them <= REACH + 0.6,
		"and up to somebody (%.1fm from %s)" % [to_them, _target.name])
	var named := false
	for t in _prompts:
		if t.begins_with("Talk to"):
			named = true
	_ok(named, "and the crosshair offers them by name")

func _check_the_card_opened() -> void:
	_ok(_opened.has("patient"),
		"one tap of %s opens their card" % ("E" if plan == "keys" else "X"))
	_ok(_focused() != "", "and something on it is selected, so a pad has "
		+ "somewhere to start")

func _check_the_card_can_be_used() -> void:
	var now := _focused()
	_ok(now != "" and now != _focus_at_open,
		"the selection moves down the card ('%s' -> '%s')" % [_focus_at_open, now])

func _check_the_way_out() -> void:
	_ok(game.ui.current_id == "",
		"%s closes it again" % ("Escape" if plan == "keys" else "B"))

func _check_every_bed_was_decided() -> void:
	_ok(_decided >= _roster_ids().size(),
		"every bed on the ward was decided with the pad (%d of %d)"
			% [_decided, _roster_ids().size()])

func _check_the_office_opens(p) -> void:
	var away: float = p.global_position.distance_to(_target.global_position) \
		if (p != null and _target != null) else -1.0
	_ok(String(game.ui.current_id) == "records",
		"the office terminal opens the records (screen '%s', %.1fm away, crosshair said '%s'; doctor at %s in '%s', desk at %s, route %d/%d)"
			% [game.ui.current_id, away,
				String(_prompts[-1]) if not _prompts.is_empty() else "",
				_round(p.global_position) if p else "?",
				p.current_room() if p != null and p.has_method("current_room") else "?",
				_round(_target.global_position) if _target else "?",
				_wp, _path.size()])

func _check_tomorrow_arrives() -> void:
	_ok(GameState.day == _day_was + 1,
		"and one press starts the next day (day %d)" % GameState.day)
	_ok(String(game.ui.current_id) == "morning",
		"with the morning briefing in front of you (screen '%s')"
			% game.ui.current_id)

func _check_the_shift_can_be_finished() -> void:
	var w = tree.get_first_node_in_group("ward_day")
	_ok(w != null and w.ended, "and the shift signs off")
	_ok(String(game.ui.current_id) == "day_over",
		"and the end of the shift is on the screen")

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
	if to_them <= _reach:
		_walk(false)
		if plan != "keys":
			_stick(JOY_AXIS_LEFT_Y, 0.0)
		_aim_at(p, at)
		return _aimed_at_them(p)
	# BACKING OFF, if the last few frames went nowhere. Reverse and lean to one
	# side; the re-plan happens at the same moment, so what comes out of this is
	# a fresh route from a spot that is not against the furniture.
	if frames < _unstick_until:
		_walk(false)
		if plan != "keys":
			_stick(JOY_AXIS_LEFT_Y, 0.85)
			_stick(JOY_AXIS_LEFT_X, _unstick_side)
		else:
			_press_key(KEY_S, true)
			_press_key(KEY_A if _unstick_side < 0.0 else KEY_D, true)
		return false
	if frames == _unstick_until:
		if plan != "keys":
			_stick(JOY_AXIS_LEFT_Y, 0.0)
			_stick(JOY_AXIS_LEFT_X, 0.0)
		else:
			_press_key(KEY_S, false)
			_press_key(KEY_A, false)
			_press_key(KEY_D, false)

	# Otherwise: the next corner of the route. The LAST waypoint is dropped at
	# 1.2m rather than 0.75 — the route ends at a navigable cell beside the bed
	# and the doctor cannot stand on it, so insisting on it is how a walk runs
	# out of frames three quarters of a metre from somebody.
	while _wp < _path.size() - 1 and here.distance_to(
			Vector3(_path[_wp].x, here.y, _path[_wp].z)) < 0.75:
		_wp += 1
	if _wp == _path.size() - 1 and _path.size() > 0 and here.distance_to(
			Vector3(_path[_wp].x, here.y, _path[_wp].z)) < 1.2:
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
	# STUCK IS SOMETHING TO GET OUT OF, and then a result.
	#
	# A person who catches the corner of a bedside table backs off and goes
	# round it; this harness walked into it and stayed there, and reported the
	# building as impassable. Three goes: reverse and sidestep for half a
	# second, re-plan from wherever that left us, try again. Only if that fails
	# three times is the building genuinely in the way.
	if here.distance_to(_last_seen) > 0.25:
		_last_seen = here
		_last_progress = frames
		_replans = 0
	elif frames - _last_progress > 150:
		_replans += 1
		if _replans > 3:
			_fail("the doctor is wedged %.1fm from %s at %s"
				% [to_them, _target.name if _target else "the bedside", _round(here)])
			return true
		_unstick_until = frames + 34
		_unstick_side = 1.0 if (_replans % 2) == 0 else -1.0
		_last_progress = frames
		_route_to_current(p)
	return _since() > (WALK_FRAMES_FAR if stage == "office_walk" else WALK_FRAMES)

## Pointing at them closely enough for the crosshair to be on them, or out of
## patience. The interactor's ray is 2.9m long and thin.
func _aimed_at_them(p) -> bool:
	if _since() > WALK_FRAMES:
		return true
	var at: Vector3 = _target.head_position() if _target.has_method("head_position") \
		else _target.global_position
	var d: Vector3 = at - p.global_position
	if absf(wrapf(atan2(-d.x, -d.z) - p.rotation.y, -PI, PI)) >= 0.06:
		return false
	# ...and looking at the right HEIGHT, which is the half that was missing.
	var eye: Vector3 = p.camera.global_position if p.camera != null \
		else p.global_position + Vector3.UP * 1.6
	var flat := Vector2(at.x - eye.x, at.z - eye.z).length()
	return absf(clampf(atan2(at.y - eye.y, maxf(flat, 0.05)), -1.4, 1.4)
		- p.head.rotation.x) < 0.06

func _round(v: Vector3) -> String:
	return "(%.1f, %.1f)" % [v.x, v.z]

## Walk the selection until it is on a button this plan is looking for, then
## press it. One press of down per call, because a keypress does not take
## effect until the frame after it.
##
## This is exactly what a person with a pad does, and it is the only way to
## drive a card without reaching past the input layer — which is the whole
## point of this file.
func _seek() -> bool:
	var now := _focused()
	for want in _want:
		if now.begins_with(String(want)):
			_tap("accept", true)
			_tap("accept", false)
			return true
	# STUCK AT THE END OF A COLUMN IS NOT THE SAME AS NOT THERE. Godot works
	# focus neighbours out geometrically, so `ui_down` from the last control on
	# a card moves nothing at all — and a seek that only ever presses down sits
	# on "Close" pressing it forty times. Turn round, and try the other two
	# directions, before deciding a button does not exist.
	if now == _last_focus:
		_dir = (_dir + 1) % SEEK_DIRS.size()
	_last_focus = now
	_tries += 1
	if _tries > 40:
		_fail("could not find %s on the %s card (selection sat on '%s')"
			% [str(_want), game.ui.current_id, now])
		return true
	var d := String(SEEK_DIRS[_dir])
	_tap(d, true)
	_tap(d, false)
	return false

## Line the doctor up with the next bed, or with the office once the beds are
## done.
func _next_bed(p) -> void:
	var ids := _roster_ids()
	if _bed >= ids.size():
		_check_every_bed_was_decided()
		_head_for_the_office(p)
		return
	var ps = tree.get_first_node_in_group("patient_system")
	_target = ps.get_body(ids[_bed]) if ps else null
	if _target == null or not _target.is_inside_tree():
		# Somebody already sent home. Not a failure — walk on.
		_bed += 1
		_next_bed(p)
		return
	_replans = 0
	_reach = REACH
	_route_to(p, _target.global_position)
	_to("bed_walk")

func _head_for_the_office(p) -> void:
	var desk = _the_office_terminal()
	if desk == null:
		_fail("no office terminal to sign off at")
		_to("done")
		return
	_target = desk
	_replans = 0
	_reach = 1.5
	_route_to(p, desk.global_position)
	_to("office_walk")

## The one terminal that ends the shift: `mode == "admin"` behind a shut door.
func _the_office_terminal():
	for n in tree.get_nodes_in_group("fixture"):
		if n is RecordsTerminal and n._is_the_office():
			return n
	# Not in a group: walk the tree for it.
	return _find_office(tree.root)

func _find_office(n: Node):
	for c in n.get_children():
		if c is RecordsTerminal and (c as RecordsTerminal)._is_the_office():
			return c
		var f = _find_office(c)
		if f != null:
			return f
	return null

## Re-plan to whatever we are currently walking at.
func _route_to_current(p) -> void:
	if _target != null and is_instance_valid(_target):
		_route_to(p, _target.global_position)

func _route_to(p, to: Vector3) -> void:
	var h = tree.get_first_node_in_group("hospital")
	_from = p.global_position
	_last_seen = _from
	_last_progress = frames
	_unstick_until = mini(_unstick_until, frames + 34)
	_path = h.nav.find_path(_from, to) if h and h.nav else PackedVector3Array()
	_wp = 0

func _roster_ids() -> Array:
	var out: Array = []
	for c in Cases.roster():
		out.append(String(c["id"]))
	return out

## Did that press actually decide the bed, rather than open a submenu.
func _held_or_sent() -> bool:
	var w = tree.get_first_node_in_group("ward_day")
	if w == null:
		return false
	var ids := _roster_ids()
	if _bed >= ids.size():
		return false
	var st: Dictionary = w.state.get(ids[_bed], {})
	return String(st.get("disposition", "")) != ""

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
