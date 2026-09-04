extends Node
## Player-facing options, and the one place they are stored.
##
## There were none. No volume, no mouse sensitivity, no fullscreen, no way to
## turn the camera shake off — in a first-person game that is the difference
## between "a demo" and "software somebody can use", and it is the single
## cheapest thing on the list of what this needs before anyone plays it.
##
## Deliberately NOT part of the save file. Settings belong to the machine, not
## to the career: loading somebody else's save should not change your mouse
## sensitivity, and starting a new run should not reset your volume.

const PATH := "user://settings.cfg"

## Defaults are the values the game shipped with before there was a screen for
## any of it, so an existing player who never opens this sees no change.
const DEFAULTS := {
	"master_volume": 0.7,
	"sfx_volume": 1.0,
	"music_volume": 0.75,
	"mouse_sensitivity": 1.0,     ## multiplier on Player.MOUSE_SENS
	"invert_y": false,
	"fov": 78.0,
	"fullscreen": false,
	"vsync": true,
	"camera_shake": 1.0,          ## 0 turns it off entirely — accessibility
	"head_bob": 1.0,
	"subtitles": true,
	## `show_damage_flash` lived here and was read by nothing at all: it was a
	## setting for a health bar, in a game that has never had one. Gone rather
	## than wired up — there is no damage to flash.
	## HOW BIG THE WRITING IS. This game is a chart, a board and a conversation
	## about a document, so the text IS the game — and the cards were built at
	## one fixed size for one fixed viewport. `content_scale_factor` scales the
	## whole canvas layer and leaves the 3D viewport alone, which is exactly the
	## right knob: the ward stays the size it is and the paperwork gets bigger.
	"ui_scale": 1.0,
	"pad_look_sensitivity": 1.0,
	"pad_vibration": true,
}

var values: Dictionary = {}

signal changed(key: String)

# ------------------------------------------------------------------ bindings
## The actions a player is allowed to rebind, in the order a controls screen
## should list them. Kept apart from the option values because a binding is a
## list of events rather than a number, and because it has to be applied to the
## InputMap rather than to a bus or a camera.
const BINDABLE := [
	["move_forward", "Walk forward"],
	["move_back", "Walk back"],
	["move_left", "Step left"],
	["move_right", "Step right"],
	["sprint", "Hurry"],
	["crouch", "Crouch"],
	["jump", "Jump"],
	["interact", "Use / examine"],
	["grab", "Pick up"],
	["throw", "Throw"],
	["pause", "Pause"],
]

## A pad, out of the box.
##
## Not rebindable and deliberately so: the point of shipping gamepad support is
## that somebody can pick up a controller and play, and a controller layout that
## has to be configured first is a controller layout nobody uses.
##
## RIGHT stick only is handled in Player, and for a long time that sentence was
## the whole of "the sticks are handled in Player" — see PAD_AXES.
const PAD_DEFAULTS := {
	"jump": JOY_BUTTON_A,
	"sprint": JOY_BUTTON_LEFT_STICK,
	"crouch": JOY_BUTTON_B,
	"interact": JOY_BUTTON_X,
	"grab": JOY_BUTTON_RIGHT_SHOULDER,
	"throw": JOY_BUTTON_LEFT_SHOULDER,
	"pause": JOY_BUTTON_START,
}

## THE LEFT STICK, which is the half of "a pad works" that did not.
##
## The Controls screen has always said "left stick walks, right stick looks".
## Looking is read straight off the axis in `Player._handle_pad_look`, so that
## half was true. Walking is `Input.get_vector` over four ACTIONS, and those
## four actions had a keyboard event each and nothing else — so a player with a
## pad in their hands could look around the ward in every direction and not
## take a single step. CLAUDE.md 15: a promise the game makes in copy and does
## not keep in code, and the copy had been on the screen for months.
##
## Axis events rather than a `get_joy_axis` read in Player, so that rebinding,
## the deadzone and `Input.get_vector`'s own circular clamp all work on the
## stick exactly as they do on the keys.
const PAD_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
}

## THE TWO BUTTONS THE ENGINE LEAVES OUT.
##
## Godot's built-in UI actions ship with the D-pad and the left stick bound to
## `ui_up`/`ui_down`/`ui_left`/`ui_right` — but `ui_accept` is Enter, Kp Enter
## and Space, and `ui_cancel` is Escape, and neither has a pad button on it. So
## with a controller you could move the selection around a card perfectly well
## and had no way whatsoever to PRESS the thing you had selected, or to back out
## of the screen. That is the whole of menu navigation missing one button.
##
## A is also `jump` and B is also `crouch`; both of those are gated on
## `can_move`, which a screen turns off, so nothing double-fires.
const PAD_UI := {
	"ui_accept": JOY_BUTTON_A,
	"ui_cancel": JOY_BUTTON_B,
}

## The project file gives every action a deadzone of 0.5, which is the editor's
## default and is enormous: half the throw of the stick does nothing at all, and
## the other half goes from a standstill to a walk. It costs nothing on a key,
## which is 0 or 1, so it was invisible until the stick was wired up.
const PAD_DEADZONE := 0.2

## action -> keycode, for anything the player has changed. Only overrides are
## stored, so a new default in a later build reaches everybody who never touched
## that particular key.
var bindings: Dictionary = {}

func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	load_from_disk()
	apply_all()
	_add_pad_defaults()
	apply_bindings()

func _add_pad_defaults() -> void:
	for action in PAD_DEFAULTS.keys() + PAD_UI.keys():
		if not InputMap.has_action(String(action)):
			continue
		var ev := InputEventJoypadButton.new()
		ev.button_index = int(PAD_DEFAULTS[action] if PAD_DEFAULTS.has(action)
			else PAD_UI[action])
		var already := false
		for e in InputMap.action_get_events(String(action)):
			if e is InputEventJoypadButton and e.button_index == ev.button_index:
				already = true
		if not already:
			InputMap.action_add_event(String(action), ev)
	for action in PAD_AXES:
		var a := String(action)
		if not InputMap.has_action(a):
			continue
		var spec: Array = PAD_AXES[action]
		var m := InputEventJoypadMotion.new()
		m.axis = int(spec[0])
		m.axis_value = float(spec[1])
		var have := false
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadMotion and e.axis == m.axis \
					and signf(e.axis_value) == signf(m.axis_value):
				have = true
		if not have:
			InputMap.action_add_event(a, m)
		InputMap.action_set_deadzone(a, PAD_DEADZONE)

## WHAT TO TELL THE PLAYER TO PRESS, right now, on the thing in their hands.
##
## Different question from `binding_label`, which is what the rebind rows under
## "KEYBOARD AND MOUSE" show and must stay a key even with a pad plugged in.
## This one is for prompts in the world: it prefers the pad when there is one,
## because somebody holding a controller is not looking at the keyboard.
##
## It exists because two of these were hardcoded. The HUD's corner reminder was
## "[E] use [LMB] grab" in a build with a rebinding screen, so a player who
## moved "use" to F was told to press E for the rest of their career; that one
## was fixed and the carry prompt — "[RMB] throw [LMB] drop", the line you see
## while holding something — was not.
const PAD_LABELS := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
}

func prompt_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	if not Input.get_connected_joypads().is_empty():
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton and PAD_LABELS.has(ev.button_index):
				return String(PAD_LABELS[ev.button_index])
	return binding_label(action)

## What this action is currently bound to, as something a person can read.
func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "—"
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var code: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
			return OS.get_keycode_string(code)
		if e is InputEventMouseButton:
			match e.button_index:
				MOUSE_BUTTON_LEFT: return "Left mouse"
				MOUSE_BUTTON_RIGHT: return "Right mouse"
				MOUSE_BUTTON_MIDDLE: return "Middle mouse"
			return "Mouse %d" % e.button_index
	return "—"

## Replace the keyboard/mouse half of an action. Pad buttons are left alone, so
## rebinding a key never silently unbinds a controller.
func rebind(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action):
		return false
	if not (event is InputEventKey or event is InputEventMouseButton):
		return false
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		return false
	for e in InputMap.action_get_events(action):
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_erase_event(action, e)
	InputMap.action_add_event(action, event)
	if event is InputEventKey:
		bindings[action] = {"kind": "key",
			"code": event.physical_keycode if event.physical_keycode != 0 else event.keycode}
	else:
		bindings[action] = {"kind": "mouse", "code": event.button_index}
	save_to_disk()
	changed.emit("bindings")
	return true

func apply_bindings() -> void:
	for action in bindings:
		var a := String(action)
		if not InputMap.has_action(a):
			continue
		var spec: Dictionary = bindings[action]
		var ev: InputEvent = null
		if String(spec.get("kind", "key")) == "key":
			var k := InputEventKey.new()
			k.physical_keycode = int(spec.get("code", 0))
			ev = k
		else:
			var m := InputEventMouseButton.new()
			m.button_index = int(spec.get("code", 1))
			ev = m
		for e in InputMap.action_get_events(a):
			if e is InputEventKey or e is InputEventMouseButton:
				InputMap.action_erase_event(a, e)
		InputMap.action_add_event(a, ev)

func reset_bindings() -> void:
	bindings.clear()
	InputMap.load_from_project_settings()
	_add_pad_defaults()
	save_to_disk()
	changed.emit("bindings")

func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))

func set_value(key: String, v: Variant, persist := true) -> void:
	if not DEFAULTS.has(key):
		Log.w("unknown setting '%s'" % key, "Settings")
		return
	values[key] = v
	_apply(key)
	changed.emit(key)
	if persist:
		save_to_disk()

func reset_to_defaults() -> void:
	values = DEFAULTS.duplicate(true)
	apply_all()
	save_to_disk()
	changed.emit("")

# ------------------------------------------------------------------ applying
func apply_all() -> void:
	for k in DEFAULTS:
		_apply(k)

func _apply(key: String) -> void:
	match key:
		"master_volume", "sfx_volume", "music_volume":
			if Engine.has_singleton("AudioMgr") or AudioMgr != null:
				AudioMgr.master_volume = float(get_value("master_volume"))
				AudioMgr.sfx_volume = float(get_value("sfx_volume"))
				AudioMgr.music_volume = float(get_value("music_volume"))
				AudioMgr.refresh_music_volume()
		"fullscreen":
			# Guarded: a headless run has no window to resize, and every test
			# harness in this project is headless.
			if DisplayServer.get_name() == "headless":
				return
			DisplayServer.window_set_mode(
				DisplayServer.WINDOW_MODE_FULLSCREEN if bool(get_value("fullscreen"))
				else DisplayServer.WINDOW_MODE_WINDOWED)
		"vsync":
			if DisplayServer.get_name() == "headless":
				return
			DisplayServer.window_set_vsync_mode(
				DisplayServer.VSYNC_ENABLED if bool(get_value("vsync"))
				else DisplayServer.VSYNC_DISABLED)
		"fov":
			var p = _player()
			if p != null and p.camera != null:
				p.camera.fov = float(get_value("fov"))
		"ui_scale":
			if DisplayServer.get_name() == "headless":
				return
			var loop := Engine.get_main_loop()
			if loop is SceneTree and (loop as SceneTree).root != null:
				(loop as SceneTree).root.content_scale_factor = \
					clampf(float(get_value("ui_scale")), 0.75, 1.5)

func _player():
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).get_first_node_in_group("player")

# ------------------------------------------------------------------ disk
func save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for k in values:
		cfg.set_value("options", k, values[k])
	for a in bindings:
		cfg.set_value("bindings", String(a), bindings[a])
	cfg.save(PATH)

func load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for k in DEFAULTS:
		if cfg.has_section_key("options", k):
			# Typed against the default, so a hand-edited file that says
			# "loud" for a float cannot take the audio bus with it.
			var raw: Variant = cfg.get_value("options", k)
			if typeof(raw) == typeof(DEFAULTS[k]):
				values[k] = raw
	bindings.clear()
	if cfg.has_section("bindings"):
		for a in cfg.get_section_keys("bindings"):
			var spec: Variant = cfg.get_value("bindings", a)
			if typeof(spec) == TYPE_DICTIONARY:
				bindings[String(a)] = spec
