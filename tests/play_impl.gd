extends RefCounted
## A scripted player. Presses the same input actions a person would, through the
## real controller, and writes down how long everything took.
##
## This exists because "the systems are green" and "the game is nice to play" are
## different claims and only one of them was ever being checked. Everything here
## is measured in FRAMES at a fixed 60fps, so every duration it reports is a real
## number of seconds a human would sit through.

const FPS := 60.0

var tree: SceneTree = null
var plan_name := "first_shift"
var game: Node = null

var frames := 0
var _beats: Array = []
var _beat := 0
var _beat_frames := 0
var _shots := 0
var _log: Array[String] = []
var _marks: Dictionary = {}
var _held: Array[String] = []
var _last_beat_frames := 0
var out_dir := "user://play"

# ------------------------------------------------------------------ lifecycle
func start() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.start_new_career(20260820)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	_say("=== PLAY: %s ===" % plan_name)

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 30:
		return false                      # let the scene settle
	if game == null or game.player == null:
		return frames > 300
	# The plan is built here rather than in start(): several beats ask the
	# hospital where a bed or a corridor point is, and the hospital does not
	# exist until the game has had a frame to build it.
	if _beats.is_empty():
		_beats = _plan(plan_name)

	if _beat >= _beats.size():
		_finish()
		return true
	var b: Dictionary = _beats[_beat]
	_beat_frames += 1
	var done: bool = _run_beat(b)
	if done or _beat_frames > int(float(b.get("timeout", 20.0)) * FPS):
		if not done:
			_say("  ! TIMED OUT after %.1fs: %s" % [_beat_frames / FPS, _describe(b)])
			if String(b["do"]) == "push_forward":
				# Same diagnostic a walk gets. Without it a door failure reports
				# only that it did not happen, which is the one thing already
				# obvious from the timing.
				_say("      stopped at %s facing %s, against %s" % [
					str(game.player.global_position.round()), str(b["at"].round()),
					_blockers(game.player)])
			if String(b["do"]) == "walk":
				_say("      stopped at %s, leg %d of %d%s, against %s" % [
					str(game.player.global_position.round()), _leg, _route.size(),
					("" if _leg >= _route.size() else " (heading for %s)" %
						str(_route[_leg].round())), _blockers(game.player)])
		_last_beat_frames = _beat_frames
		_release_all()
		_beat += 1
		_beat_frames = 0
	return false

func _finish() -> void:
	_say("\n--- TIMINGS ---")
	for k in _marks:
		_say("  %-42s %6.1f s" % [k, float(_marks[k])])
	_say("\n%d frames = %.1f real seconds, %d screenshots -> %s" % [
		frames, frames / FPS, _shots, ProjectSettings.globalize_path(out_dir)])
	var f := FileAccess.open("%s/%s.log" % [out_dir, plan_name], FileAccess.WRITE)
	if f:
		f.store_string("\n".join(_log))
		f.close()

# ------------------------------------------------------------------ beats
func _run_beat(b: Dictionary) -> bool:
	match String(b["do"]):
		"wait":
			return _beat_frames >= int(float(b.get("s", 1.0)) * FPS)
		"say":
			_say(String(b["text"]))
			return true
		"mark":
			# The duration of the beat BEFORE this one — a mark is its own beat,
			# so its own frame count is always 1 and always meaningless.
			_marks[String(b["text"])] = _last_beat_frames / FPS
			return true
		"shot":
			return _shot(String(b["name"]))
		"report":
			_report()
			return true
		"walk":
			return _walk(b)
		"face":
			_face(b["at"])
			return true
		"face_patient":
			# Look at the person, not at the middle of the bed. Where their head
			# actually is depends on the bed mesh and the reclined pose, and a
			# player can see it; the harness has to ask.
			var body = _patient_body_in(String(b["room"]))
			if body == null:
				_say("  ! nobody in %s to look at" % String(b["room"]))
				return true
			_face(body.global_position + Vector3(0, 0.65, 0))
			return true
		"press":
			_press(String(b["action"]))
			return true
		"tap":
			if _beat_frames == 1:
				_press(String(b["action"]))
			if _beat_frames >= 6:
				_release(String(b["action"]))
				return true
			return false
		"hold":
			if _beat_frames == 1:
				_press(String(b["action"]))
			return _beat_frames >= int(float(b.get("s", 1.0)) * FPS)
		"close_ui":
			if game.ui != null and game.ui.current != null:
				_say("  (closing %s)" % String(game.ui.current_id))
				game.ui.close()
			return true
		"clock_in":
			game.shift.clock_in()
			_say("  clocked in at %s" % GameState.time_string())
			return true
		"prompt":
			_say("  prompt: %s" % _current_prompt())
			return true
		"face_fixture":
			var f = _fixture_in(String(b["room"]), String(b.get("type", "machine")))
			if f == null:
				_say("  ! no %s in %s" % [String(b.get("type", "machine")), String(b["room"])])
				return true
			_face(f.global_position + Vector3(0, float(b.get("aim", 0.0)), 0))
			return true
		"taps":
			# One press-and-release per 8 frames. Real key repeats, through the
			# real interactor, because the point is to exercise what the player
			# does — a dial is turned by pressing E over and over.
			var period := 8
			var n := int(b.get("n", 1))
			var i := int((_beat_frames - 1) / period)
			if i >= n:
				return true
			if (_beat_frames - 1) % period == 0:
				_press(String(b["action"]))
			elif (_beat_frames - 1) % period == 3:
				_release(String(b["action"]))
			return false
		"dial_to":
			# Turn the machine to a setting the way a player does: press E over
			# and over, or hold shift and press E to come back down. Setting
			# m.dial directly would skip interact() entirely — and interact() is
			# where the witness roll lives, so a harness that assigns the value
			# is testing the machine and quietly not testing the crime.
			var m = _fixture_in(String(b["room"]), "machine")
			if m == null:
				_say("  ! no machine in %s" % String(b["room"]))
				return true
			var want := int(b["to"])
			if _beat_frames == 1:
				_dial_from = int(m.dial)
				_dial_seen = int(m.dial)
				_dial_stall = 0
			if int(m.dial) == want:
				_release("sprint")
				_say("  dial in %s: %d -> %d (prescribed %d), %d presses" % [
					String(b["room"]), _dial_from, int(m.dial), int(m.prescribed),
					int((_beat_frames - 1) / 8)])
				return true
			# Direction is stated by the beat rather than worked out, because
			# "which way round is shorter" is a decision the PLAYER makes and a
			# harness that quietly optimises it is not reproducing anybody.
			if bool(b.get("down", false)):
				_press("sprint")
			else:
				_release("sprint")
			if int(m.dial) != _dial_seen:
				_dial_seen = int(m.dial)
				_dial_stall = 0
			else:
				_dial_stall += 1
				if _dial_stall == 240:
					_say("    ! dial stuck at %d after %d presses — looking at %s" % [
						int(m.dial), int((_beat_frames - 1) / 8), _current_prompt()])
			if (_beat_frames - 1) % 8 == 0:
				_press("interact")
			elif (_beat_frames - 1) % 8 == 3:
				_release("interact")
			return false
		"note":
			_note(String(b.get("text", "")))
			return true
		"teleport":
			game.player.global_position = b["at"]
			game.player.velocity = Vector3.ZERO
			return true
		"push_forward":
			# No pathfinding, no waypoints: point at a spot and walk. This is
			# what a person does at a door, and it is the only way to test a
			# door without the answer being about the navigation grid.
			if _beat_frames == 1:
				_walk_from = game.player.global_position
			_face(Vector3(b["at"].x, game.player.global_position.y, b["at"].z))
			_press("move_forward")
			return game.player.global_position.distance_to(b["at"]) < float(b.get("within", 1.2))
	return true

func _fixture_in(room_key: String, kind: String):
	for f in tree.get_nodes_in_group("fixture"):
		if String(f.get("room_key")) != room_key:
			continue
		match kind:
			"machine":
				if f is TreatmentMachine:
					return f
			"run_button":
				if f.get_script() != null and \
						f.get_script().resource_path.ends_with("run_button.gd"):
					return f
			"console":
				if f is VitalsConsole:
					return f
			_:
				return f
	return null

## A labelled snapshot of everything a person would be judging the game by.
func _note(label: String) -> void:
	var sus = game.suspicion
	var worst := 0.0
	var worst_who := "nobody"
	for row in sus.ranked_suspicions():
		if float(row.get("value", 0.0)) > worst:
			worst = float(row["value"])
			worst_who = String(row.get("name", "?"))
	_say("  ** %s" % label)
	_say("     money   you $%d   hospital $%d   heat %.0f%%" % [
		GameState.personal_money, GameState.hospital_money, GameState.heat * 100.0])
	_say("     watched by %d   most suspicious: %s at %.0f%%" % [
		game.suspicion.watchers().size(), worst_who, worst * 100.0])
	var ps = game.patient_system
	for q in ps.active():
		var comps: Array[String] = []
		for c in q.active_complications():
			comps.append("%s%s" % [c.id, "" if c.documented_cause == "" else "*"])
		_say("     %-20s rec %.2f  day %.1f/%.1f  %s" % [
			q.display_name, q.recovery, q.days_admitted, q.expected_stay_days,
			"clean" if comps.is_empty() else ", ".join(comps)])

func _describe(b: Dictionary) -> String:
	return "%s %s" % [String(b["do"]), str(b.get("at", b.get("name", b.get("action", ""))))]

# ------------------------------------------------------------------ acting
## Walk to a world point the way a person would: work out a route round the
## walls, then follow it with the real movement code. Everything about
## acceleration, friction, door shoving and collision is genuinely exercised —
## only the wayfinding is scripted, because a player has eyes and this does not.
##
## The first version walked in a straight line and spent six minutes standing
## against the lobby wall. Worth remembering before trusting any harness that
## reports zeroes.
var _route: PackedVector3Array = PackedVector3Array()
var _leg := 0
var _walk_from := Vector3.ZERO
var _stuck := 0
var _dial_from := 0
var _dial_seen := -1
var _dial_stall := 0

func _walk(b: Dictionary) -> bool:
	var p = game.player
	if _beat_frames == 1:
		_walk_from = p.global_position
		_stuck = 0
		_leg = 0
		_route = game.hospital.nav.find_path(p.global_position, b["at"])
		if _route.is_empty():
			_say("    ! no route to %s" % str(b["at"]))
			return true
	if _leg >= _route.size():
		_release_all()
		return true

	var target: Vector3 = _route[_leg]
	var flat := Vector3(target.x, p.global_position.y, target.z)
	var d: float = p.global_position.distance_to(flat)
	var last: bool = _leg == _route.size() - 1
	# Tight, because doorways are 1.4m wide: advancing to the next waypoint while
	# still half a metre off line walks you into the door frame instead of
	# through the gap.
	if d < (float(b.get("within", 1.0)) if last else 0.45):
		_leg += 1
		if _leg >= _route.size():
			_release_all()
			return true
		return false

	_face(flat)
	_press("move_forward")
	if bool(b.get("run", false)):
		_press("sprint")

	# Doors and furniture genuinely stop you. If the real controller is wedged,
	# that is a finding about the game, so say so rather than hiding it.
	if Vector2(p.velocity.x, p.velocity.z).length() < 0.35:
		_stuck += 1
		if _stuck == 90:
			_say("    ! wedged for 1.5s at %s heading for %s — against %s" % [
				str(p.global_position.round()), str(flat.round()), _blockers(p)])
		# What a person does when they clip a door frame: step off the line and
		# come at it again. Without this the harness reports a wedge for
		# something a player would not even notice themselves doing.
		if _stuck > 40:
			_release("move_forward")
			_press("move_right" if (_stuck / 40) % 2 == 0 else "move_left")
		# Re-plan, exactly as NPCBody._check_stuck does. The grid is walkable
		# cell to cell but a capsule has a radius, so a route that hugs a wall
		# or takes a doorway on the diagonal can put the body into the frame. A
		# person sees the gap and adjusts; a scripted walker has to be told to.
		if _stuck > 130:
			_stuck = 0
			_release_all()
			_route = game.hospital.nav.find_path(p.global_position, b["at"])
			_leg = 0
			if _route.is_empty():
				_say("    ! no route from %s to %s" % [
					str(p.global_position.round()), str(b["at"])])
				return true
	else:
		_stuck = 0
	return false

## Doors are not in a group, so walk the hospital for them.
func _all_doors() -> Array:
	var out: Array = []
	for n in game.hospital.get_children():
		if n is SwingDoor:
			out.append(n)
	return out

## What the controller is actually pressed up against. "Wedged" on its own is
## a symptom; the game only gets fixed once the harness names the object.
func _blockers(p) -> String:
	var names: Array[String] = []
	for i in p.get_slide_collision_count():
		var c: KinematicCollision3D = p.get_slide_collision(i)
		var o = c.get_collider()
		if o == null:
			continue
		var label := String(o.name)
		if o.has_method("get_class"):
			label += " (%s)" % o.get_class()
		# Walls and counters are auto-named StaticBody3D@nnn, which identifies
		# nothing. Where it is, and what its parent is, does.
		if o is Node3D:
			label += " at %s" % str((o as Node3D).global_position.round())
		if o is Node and (o as Node).get_parent() != null:
			var par: Node = (o as Node).get_parent()
			label += " under %s" % String(par.name)
			if par.get_parent() != null:
				label += "/%s" % String(par.get_parent().name)
			if par is Node3D:
				label += " @%s" % str((par as Node3D).global_position.round())
		if o.get("display") != null and String(o.get("display")) != "":
			label = "%s [%s]" % [label, String(o.get("display"))]
		if not names.has(label):
			names.append(label)
	if names.is_empty():
		return "nothing (not touching anything)"
	# When a door is what is in the way, say what the door is actually doing.
	# "blocked by a leaf" and "blocked by a leaf that is not moving because
	# nobody asked it to" are different bugs.
	var extra := ""
	var nearest: SwingDoor = null
	var best := 3.0
	for d in _all_doors():
		var dist: float = d.opening_centre().distance_to(p.global_position)
		if dist < best:
			best = dist
			nearest = d
	if nearest != null:
		extra = "   [door %.1fm away: angle %.0f deg, av %.2f, open=%s; player v=%.2f intended=%.2f can_move=%s]" % [
			best, nearest.angle_deg(), nearest.angular_velocity, str(nearest.is_open()),
			Vector2(p.velocity.x, p.velocity.z).length(), float(p.get("_intended_speed")),
			str(p.can_move)]
	return ", ".join(names) + extra

## Look at something, the way a person does: turn AND tilt.
##
## Yaw alone kept the crosshair level with the doctor's own eyes, which is a
## metre above a patient lying in a bed — so every bedside beat in every play
## run was actually aimed over the patient's head at whatever tall object stood
## behind them, and reported "Pick up IV Stand" as though that were the game's
## idea rather than the harness's.
func _face(at) -> void:
	var target: Vector3 = at
	var p = game.player
	var eye: Vector3 = p.camera.global_position
	var to: Vector3 = target - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	p.set("_yaw", p.rotation.y)
	var flat: float = Vector2(target.x - eye.x, target.z - eye.z).length()
	var pitch: float = clampf(atan2(target.y - eye.y, maxf(flat, 0.001)), -1.45, 1.45)
	p.set("_pitch", pitch)
	p.head.rotation.x = pitch

## Press an action for real.
##
## `Input.action_press()` alone sets the action's STATE — everything that polls
## `is_action_pressed` / `is_action_just_pressed` sees it — but it synthesises no
## InputEvent, so nothing in an `_unhandled_input` handler ever hears about it.
## The tablet [Q] and the pause menu [Esc] both live there, which meant this
## harness could not open either of them: the "what does the tablet say"
## screenshot was a photograph of the room, and the tutorial step that completes
## when the tablet opens could never complete no matter how the plan was
## written. Both halves are needed, and they are cheap.
func _press(action: String) -> void:
	Input.action_press(action)
	if _held.has(action):
		return            # already down: do NOT re-fire the event, see below
	_held.append(action)
	_send(action, true)

func _release(action: String) -> void:
	Input.action_release(action)
	if not _held.has(action):
		return
	_held.erase(action)
	_send(action, false)

## Deliver the action as a real InputEvent as well as setting its state.
##
## `Input.action_press()` alone sets the STATE — everything polling
## `is_action_pressed` / `is_action_just_pressed` sees it — but synthesises no
## InputEvent, so nothing in an `_unhandled_input` handler ever hears about it.
## The tablet [Q] and the pause menu [Esc] both live there, which meant this
## harness could not open either: the "what does the tablet say" screenshot was
## a photograph of the room, and the tutorial step that completes when the
## tablet opens could never complete however the plan was written.
##
## ONLY ON TRANSITIONS. `_walk` calls _press every single frame for the whole
## length of a walk, and queueing a press event 120 times a second flooded the
## input queue badly enough that a sprint down the corridor ended with the
## player wedged in the north wall and pushing at 3.4 m/s into it forever.
## Verified by running the same plan with and without.
func _send(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

func _release_all() -> void:
	for a in _held.duplicate():
		Input.action_release(a)
		_send(a, false)
	_held.clear()

func _shot(name: String) -> bool:
	if _beat_frames < 3:
		return false
	if DisplayServer.get_name() == "headless":
		return true
	var img := tree.root.get_texture().get_image()
	img.save_png("%s/%02d_%s.png" % [out_dir, _shots, name])
	_shots += 1
	return true

# ------------------------------------------------------------------ reading
func _current_prompt() -> String:
	var hud = _hud()
	if hud == null:
		return "<no hud>"
	var t: String = String(hud.get("_prompt").text) if hud.get("_prompt") else ""
	var s: String = String(hud.get("_prompt_sub").text) if hud.get("_prompt_sub") else ""
	if t == "":
		return "<nothing to interact with>"
	return "%s / %s" % [t, s]

func _hud():
	for n in tree.root.get_children():
		var found = _find_hud(n)
		if found != null:
			return found
	return null

func _find_hud(n: Node):
	if n is HUD:
		return n
	for c in n.get_children():
		var f = _find_hud(c)
		if f != null:
			return f
	return null

## Everything the player could currently know, in one block. This is the thing
## the harness exists for: it says what the SCREEN says, not what the simulation
## knows, so the gap between the two is visible.
func _report() -> void:
	var p = game.player
	_say("  [%s] at %s in '%s'" % [GameState.time_string(),
		str(p.global_position.round()), game.hospital.room_at(p.global_position)])
	_say("    money  personal $%d / hospital $%d" % [
		GameState.personal_money, GameState.hospital_money])
	var hud = _hud()
	if hud and hud.get("_objective"):
		_say("    objective: %s" % String(hud.get("_objective").text))
	_say("    prompt: %s" % _current_prompt())
	if hud and hud.get("_next_appt"):
		_say("    next up:   %s" % String(hud.get("_next_appt").text))
	if hud and hud.get("_left"):
		_say("    deadline:  %s" % String(hud.get("_left").text))
	var appts = tree.get_first_node_in_group("appointment_system")
	if appts:
		var nxt: Dictionary = appts.next_due()
		_say("    next appt: %s" % ("none" if nxt.is_empty() else
			"%02d:00 %s - %s" % [int(nxt["hour"]), String(nxt["kind"]), String(nxt["name"])]))
	# Who is actually in the beds, and which of them the game is hoping you
	# notice. The first ten minutes live or die on this line.
	var ps = tree.get_first_node_in_group("patient_system")
	if ps:
		for q in ps.active():
			_say("    ward: %-22s %-26s %s%s%s/night, yours %s" % [
				q.display_name, q.condition_name(),
				"READY TO GO HOME · " if q.ready_for_discharge() else "",
				"OVERDUE · " if q.is_overdue() else "",
				"$%d" % q.daily_revenue(), "$%d" % q.your_cut_per_day()])
	var watching := 0
	for b in game.suspicion.watchers():
		watching += 1
	_say("    staff who can see you right now: %d" % watching)

## printerr as well as print: Godot's stdout block-buffers when it is not a TTY,
## so a run that is still going shows nothing at all until it exits. Watching a
## slow play run is most of the value.
func _say(s: String) -> void:
	print(s)
	printerr(s)
	_log.append(s)

func _patient_body_in(room_key: String):
	var ps = tree.get_first_node_in_group("patient_system")
	if ps == null:
		return null
	for q in ps.active():
		if q.room == room_key:
			return ps.get_body(q.id)
	return null

# ------------------------------------------------------------------ plans
func _plan(name: String) -> Array:
	match name:
		"walk_test": return _plan_walk()
		"honest": return _plan_honest()
		"reckless": return _plan_reckless()
		"careful_criminal": return _plan_careful_criminal()
		"opportunist": return _plan_opportunist()
		"idiot_chaos": return _plan_idiot_chaos()
		"doors": return _plan_doors()
	return _plan_first_shift()

## Walk into the nearest room, crank the machine to its stop, and run it. No
## paperwork, no cover, no looking round first. The question is whether the game
## reacts LOUDLY enough — whether a player doing the most obvious bad thing
## available gets told what they did.
func _plan_reckless() -> Array:
	var h = game.hospital
	var beats: Array = [
		{"do": "close_ui"},
		{"do": "clock_in"},
		{"do": "note", "text": "before"},
	]
	for key in ["ward_101", "ward_102", "ward_103"]:
		beats.append({"do": "say", "text": "\n-- %s: crank it and run it --" % key})
		beats.append({"do": "walk", "at": h.bed_position(key) + Vector3(1.6, 0, -1.4),
			"timeout": 45.0})
		beats.append({"do": "face_fixture", "room": key, "type": "machine", "aim": 1.05})
		beats.append({"do": "wait", "s": 0.3})
		beats.append({"do": "prompt"})
		beats.append({"do": "dial_to", "room": key, "to": 11, "timeout": 30.0})
		beats.append({"do": "wait", "s": 1.2})
		beats.append({"do": "prompt"})
		beats.append({"do": "face_fixture", "room": key, "type": "run_button"})
		beats.append({"do": "wait", "s": 0.3})
		beats.append({"do": "prompt"})
		beats.append({"do": "hold", "action": "interact", "s": 4.5})
		beats.append({"do": "wait", "s": 1.5})
		beats.append({"do": "close_ui"})
		beats.append({"do": "shot", "name": "reckless_%s" % key})
		beats.append({"do": "note", "text": "after cranking %s" % key})
	beats.append({"do": "wait", "s": 6.0})
	beats.append({"do": "note", "text": "six seconds later"})
	return beats

## The line the game is designed around: one notch off, on somebody worth it,
## with the paperwork filed before anybody has a chance to ask.
func _plan_careful_criminal() -> Array:
	var h = game.hospital
	var beats: Array = [
		{"do": "close_ui"},
		{"do": "clock_in"},
		{"do": "note", "text": "before"},
		{"do": "say", "text": "\n-- read the ward from the corridor first --"},
	]
	for key in ["ward_101", "ward_102", "ward_103", "ward_104", "ward_105"]:
		beats.append({"do": "walk", "at": _outside_door(key), "timeout": 45.0})
		beats.append({"do": "face", "at": _card_pos(key)})
		beats.append({"do": "wait", "s": 0.4})
		beats.append({"do": "prompt"})
	beats.append({"do": "shot", "name": "careful_read_the_ward"})
	beats.append({"do": "say", "text": "\n-- one notch off, on the best-insured one --"})
	beats.append({"do": "walk", "at": h.bed_position("ward_102") + Vector3(1.6, 0, -1.4),
		"timeout": 45.0})
	beats.append({"do": "face_fixture", "room": "ward_102", "type": "machine", "aim": 1.05})
	beats.append({"do": "wait", "s": 0.3})
	beats.append({"do": "prompt"})
	beats.append({"do": "taps", "action": "interact", "n": 1})
	beats.append({"do": "wait", "s": 1.2})
	beats.append({"do": "prompt"})
	beats.append({"do": "face_fixture", "room": "ward_102", "type": "run_button"})
	beats.append({"do": "wait", "s": 0.3})
	beats.append({"do": "prompt"})
	beats.append({"do": "hold", "action": "interact", "s": 4.5})
	beats.append({"do": "wait", "s": 2.0})
	beats.append({"do": "close_ui"})
	beats.append({"do": "note", "text": "after one notch"})
	beats.append({"do": "say", "text": "\n-- and straight to the records terminal --"})
	beats.append({"do": "walk", "at": Vector3(43.0, 0, -5.0), "timeout": 60.0})
	beats.append({"do": "mark", "text": "ward 102 -> office (to file it)"})
	beats.append({"do": "shot", "name": "careful_office"})
	beats.append({"do": "prompt"})
	beats.append({"do": "note", "text": "at the terminal"})
	return beats

## Never plans anything, but takes whatever the building hands them. Walk the
## floor, see what is lying about, and find out whether the game ever offers an
## opportunity you did not have to construct.
func _plan_opportunist() -> Array:
	var h = game.hospital
	return [
		{"do": "close_ui"},
		{"do": "clock_in"},
		{"do": "note", "text": "before"},
		{"do": "walk", "at": Vector3(15.0, 0, -2.0), "timeout": 45.0},
		{"do": "face", "at": Vector3(15.0, 1.2, -6.0)},
		{"do": "wait", "s": 0.4},
		{"do": "prompt"},
		{"do": "shot", "name": "opportunist_station"},
		{"do": "walk", "at": Vector3(32.0, 0, -4.0), "timeout": 45.0},
		{"do": "face", "at": Vector3(32.0, 1.4, -8.0)},
		{"do": "wait", "s": 0.4},
		{"do": "prompt"},
		{"do": "shot", "name": "opportunist_supply"},
		{"do": "tap", "action": "interact"},
		{"do": "wait", "s": 0.6},
		{"do": "close_ui"},
		{"do": "prompt"},
		{"do": "walk", "at": h.bed_position("ward_104") + Vector3(1.6, 0, -1.4), "timeout": 45.0},
		{"do": "face_patient", "room": "ward_104"},
		{"do": "wait", "s": 0.4},
		{"do": "prompt"},
		{"do": "shot", "name": "opportunist_bedside_holding"},
		{"do": "note", "text": "carrying something, at a bedside"},
	]

## Pick everything up and throw it. The most common thing a new player does with
## a physics sandbox, and the fastest way to find out whether the world reacts.
func _plan_idiot_chaos() -> Array:
	return [
		{"do": "close_ui"},
		{"do": "clock_in"},
		{"do": "note", "text": "before"},
		{"do": "walk", "at": Vector3(15.0, 0, -1.5), "timeout": 45.0},
		{"do": "face", "at": Vector3(15.0, 1.1, -6.0)},
		{"do": "wait", "s": 0.4},
		{"do": "tap", "action": "grab"},
		{"do": "wait", "s": 0.5},
		{"do": "prompt"},
		{"do": "face", "at": Vector3(40.0, 2.4, 2.0)},
		{"do": "tap", "action": "throw"},
		{"do": "wait", "s": 3.0},
		{"do": "shot", "name": "chaos_thrown"},
		{"do": "note", "text": "after throwing something down the corridor"},
		{"do": "wait", "s": 6.0},
		{"do": "note", "text": "six seconds after the clatter"},
		{"do": "shot", "name": "chaos_aftermath"},
	]

## Can a person get through every door in the building?
##
## One at a time, from a standing start two metres away, walking straight at it.
## No pathfinding involved, so the answer is about the DOOR and not about the
## navigation grid — which matters, because those two failure modes look
## identical from inside a play run and had already been confused once.
func _plan_doors() -> Array:
	var beats: Array = [
		{"do": "close_ui"},
		{"do": "clock_in"},
	]
	for entry in Hospital.LAYOUT:
		if not entry.has("door"):
			continue
		var key := String(entry["key"])
		var rect: Rect2 = entry["rect"]
		var north: bool = rect.position.y > 0.0
		var z: float = 4.0 if north else 0.0
		var cx := float(entry["door"])
		var outside := Vector3(cx, 0.0, z + (-2.0 if north else 2.0))
		var inside := Vector3(cx, 0.0, z + (2.4 if north else -2.4))
		beats.append({"do": "say", "text": "\n-- %s --" % key})
		beats.append({"do": "teleport", "at": outside + Vector3(0, 0.1, 0)})
		beats.append({"do": "wait", "s": 0.4})
		beats.append({"do": "push_forward", "at": inside, "timeout": 8.0})
		beats.append({"do": "mark", "text": "%s: corridor -> inside" % key})
		# ...and straight back out again, because a door you can only go one way
		# through is a room you can get trapped in.
		beats.append({"do": "push_forward", "at": outside, "timeout": 8.0})
		beats.append({"do": "mark", "text": "%s: inside -> corridor" % key})
		# ...and from two metres off to the side, pressed against the wall,
		# which is where a route that grazes the corner leaves you and where
		# every failure in the play runs actually happened.
		beats.append({"do": "teleport",
			"at": Vector3(cx - 2.0, 0.1, z + (-0.5 if north else 0.5))})
		beats.append({"do": "wait", "s": 0.4})
		beats.append({"do": "push_forward", "at": inside, "timeout": 8.0})
		beats.append({"do": "mark", "text": "%s: from the wall beside it" % key})
	beats.append({"do": "report"})
	return beats

## A point in the corridor just outside a ward door, and the door card beside it.
func _outside_door(key: String) -> Vector3:
	for entry in Hospital.LAYOUT:
		if String(entry["key"]) == key and entry.has("door"):
			return Vector3(float(entry["door"]) - 0.6, 0.0, 2.6)
	return Vector3.ZERO

func _card_pos(key: String) -> Vector3:
	for entry in Hospital.LAYOUT:
		if String(entry["key"]) == key and entry.has("door"):
			return Vector3(float(entry["door"]) - 1.4, 1.52, 3.9)
	return Vector3.ZERO

## What a new player sees and does in their first two minutes.
func _plan_first_shift() -> Array:
	var h = game.hospital
	return [
		{"do": "say", "text": "\n-- BOOT: what is on screen before I touch anything --"},
		{"do": "shot", "name": "boot"},
		{"do": "report"},
		{"do": "close_ui"},
		{"do": "wait", "s": 0.3},
		{"do": "shot", "name": "world_first_look"},
		{"do": "report"},
		{"do": "clock_in"},
		{"do": "wait", "s": 0.5},
		{"do": "shot", "name": "clocked_in"},
		{"do": "report"},

		{"do": "say", "text": "\n-- Can I find the corridor from the spawn? --"},
		{"do": "walk", "at": h.point_in("corridor", "play_a"), "timeout": 30.0},
		{"do": "mark", "text": "spawn -> corridor"},
		{"do": "shot", "name": "corridor"},
		{"do": "report"},

		{"do": "say", "text": "\n-- Walking the building end to end (62m) --"},
		{"do": "walk", "at": Vector3(44.0, 0, 2.0), "timeout": 40.0},
		{"do": "mark", "text": "corridor east end (walk)"},
		{"do": "shot", "name": "east_end"},
		{"do": "walk", "at": Vector3(-14.0, 0, 2.0), "run": true, "timeout": 40.0},
		{"do": "mark", "text": "east -> west end (sprint, 58m)"},
		{"do": "shot", "name": "west_end"},
		{"do": "report"},

		{"do": "say", "text": "\n-- The clinic board: can I read my list off the wall? --"},
		{"do": "walk", "at": Vector3(27.0, 0, 1.6), "timeout": 40.0},
		{"do": "face", "at": Vector3(27.0, 1.5, 3.9)},
		{"do": "wait", "s": 0.4},
		{"do": "shot", "name": "clinic_board"},
		{"do": "prompt"},

		{"do": "say", "text": "\n-- Going to see a patient --"},
		{"do": "walk", "at": h.bed_position("ward_101") + Vector3(1.6, 0, -1.6), "timeout": 40.0},
		{"do": "mark", "text": "board -> Room 101 bedside"},
		{"do": "face_patient", "room": "ward_101"},
		{"do": "wait", "s": 0.5},
		{"do": "shot", "name": "bedside"},
		{"do": "prompt"},
		{"do": "report"},
		{"do": "tap", "action": "interact"},
		{"do": "wait", "s": 0.6},
		{"do": "shot", "name": "patient_interaction"},
		{"do": "report"},
		{"do": "close_ui"},

		{"do": "say", "text": "\n-- What does the tablet say --"},
		{"do": "tap", "action": "tablet"},
		{"do": "wait", "s": 0.5},
		{"do": "shot", "name": "tablet"},
		{"do": "close_ui"},
		{"do": "report"},
	]

## Pure movement feel: how long does the building take to cross, and how much of
## a shift is spent walking.
func _plan_walk() -> Array:
	return [
		{"do": "close_ui"},
		{"do": "clock_in"},
		{"do": "walk", "at": Vector3(-14.0, 0, 2.0), "timeout": 60.0},
		{"do": "mark", "text": "to west end"},
		{"do": "walk", "at": Vector3(44.0, 0, 2.0), "timeout": 60.0},
		{"do": "mark", "text": "west -> east, WALK (58m)"},
		{"do": "walk", "at": Vector3(-14.0, 0, 2.0), "run": true, "timeout": 60.0},
		{"do": "mark", "text": "east -> west, SPRINT (58m)"},
		{"do": "walk", "at": Vector3(4.5, 0, 8.0), "timeout": 60.0},
		{"do": "mark", "text": "corridor -> Room 101 bed (through a door)"},
		{"do": "walk", "at": Vector3(24.0, 0, -5.0), "timeout": 60.0},
		{"do": "mark", "text": "Room 101 -> treatment bay"},
		{"do": "walk", "at": Vector3(43.0, 0, -5.0), "timeout": 60.0},
		{"do": "mark", "text": "treatment bay -> your office"},
		{"do": "report"},
	]

## A shift's worth of honest work, to see whether there is enough to do.
func _plan_honest() -> Array:
	var h = game.hospital
	var beats: Array = [
		{"do": "close_ui"},
		{"do": "clock_in"},
		{"do": "report"},
	]
	for key in ["ward_101", "ward_102", "ward_103", "ward_104", "ward_105"]:
		beats.append({"do": "walk", "at": h.bed_position(key) + Vector3(1.5, 0, -1.5),
			"timeout": 45.0})
		beats.append({"do": "mark", "text": "reached %s" % key})
		beats.append({"do": "prompt"})
	beats.append({"do": "report"})
	beats.append({"do": "shot", "name": "after_round"})
	return beats
