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
var out_dir := "user://play"

# ------------------------------------------------------------------ lifecycle
func start() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	GameState.start_new_career(20260820)
	game = load("res://scenes/Game.tscn").instantiate()
	tree.root.add_child(game)
	_beats = _plan(plan_name)
	_say("=== PLAY: %s ===" % plan_name)

func tick() -> bool:
	frames += 1
	tree.paused = false
	if frames < 30:
		return false                      # let the scene settle
	if game == null or game.player == null:
		return frames > 300

	if _beat >= _beats.size():
		_finish()
		return true
	var b: Dictionary = _beats[_beat]
	_beat_frames += 1
	var done: bool = _run_beat(b)
	if done or _beat_frames > int(float(b.get("timeout", 20.0)) * FPS):
		if not done:
			_say("  ! TIMED OUT after %.1fs: %s" % [_beat_frames / FPS, _describe(b)])
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
			_marks[String(b["text"])] = _beat_frames / FPS
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
	return true

func _describe(b: Dictionary) -> String:
	return "%s %s" % [String(b["do"]), str(b.get("at", b.get("name", b.get("action", ""))))]

# ------------------------------------------------------------------ acting
## Walk to a world point using the real movement code: face it, hold forward,
## stop when close. Everything about acceleration, friction, door shoving and
## collision is therefore genuinely exercised.
func _walk(b: Dictionary) -> bool:
	var target: Vector3 = b["at"]
	var p = game.player
	var flat := Vector3(target.x, p.global_position.y, target.z)
	var d: float = p.global_position.distance_to(flat)
	if d < float(b.get("within", 1.2)):
		_release_all()
		return true
	_face(flat)
	_press("move_forward")
	if bool(b.get("run", false)):
		_press("sprint")
	return false

func _face(at) -> void:
	var target: Vector3 = at
	var p = game.player
	var to: Vector3 = target - p.global_position
	p.rotation.y = atan2(-to.x, -to.z)
	p.set("_yaw", p.rotation.y)

func _press(action: String) -> void:
	if not _held.has(action):
		_held.append(action)
	Input.action_press(action)

func _release(action: String) -> void:
	_held.erase(action)
	Input.action_release(action)

func _release_all() -> void:
	for a in _held.duplicate():
		Input.action_release(a)
	_held.clear()

func _shot(name: String) -> bool:
	if _beat_frames < 3:
		return false
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
	var appts = tree.get_first_node_in_group("appointment_system")
	if appts:
		var nxt: Dictionary = appts.next_due()
		_say("    next appt: %s" % ("none" if nxt.is_empty() else
			"%02d:00 %s - %s" % [int(nxt["hour"]), String(nxt["kind"]), String(nxt["name"])]))
	var watching := 0
	for b in game.suspicion.watchers():
		watching += 1
	_say("    staff who can see you right now: %d" % watching)

func _say(s: String) -> void:
	print(s)
	_log.append(s)

# ------------------------------------------------------------------ plans
func _plan(name: String) -> Array:
	match name:
		"walk_test": return _plan_walk()
		"honest": return _plan_honest()
	return _plan_first_shift()

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
		{"do": "face", "at": h.bed_position("ward_101") + Vector3(0, 1.2, 0)},
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
