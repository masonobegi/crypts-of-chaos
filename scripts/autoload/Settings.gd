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
	## THE ROOM TONE HAD NO SLIDER OF ITS OWN AND WAS ON THE SCORE'S.
	##
	## The third slider was renamed from "Ambience" to "Music" deliberately —
	## a player who wants the score turned down does not go looking under
	## "Ambience" and concludes there is no way to do it — but the rename left
	## the ward's own air handling, and now the world outside the windows,
	## levelled by a control labelled after something else. So the one slider
	## somebody reaches for to quieten a hospital turned down the vibraphone,
	## and "Effects" — the other thing they would try — did not touch it
	## either.
	##
	## 0.75 and not 0.8 or 1.0: it is exactly what `music_volume` defaults to,
	## which is what the hum was levelled by until this key existed, so the
	## gain staging measured in `AudioMgr.start_ambience` (-15 dB source, about
	## -46 dBFS at the speaker, sixteen under the score) is the same number
	## after this change as before it. A new slider that moves the default mix
	## is a new mix, not a new control.
	"ambience_volume": 0.75,
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
	## GRAPHICS OPTIONS, WHICH THERE WERE NONE OF. 4x MSAA and an uncapped
	## frame rate were both compulsory: the first is the single most expensive
	## thing this renderer does on an integrated GPU, and the second means a
	## menu with three buttons on it runs a laptop's fan at full speed. 0/1/2 →
	## disabled/2x/4x, and 0 fps means uncapped.
	"msaa": 2,
	"fps_cap": 0,
	## AND HOW BRIGHT IT IS. The game shipped with no brightness control on a
	## picture that is dark type over a pale ward, which on a laptop in a lit
	## room is a refund rather than an adjustment. Applied through
	## `Grade.apply`, not through a branch of its own, because the title screen
	## and the ward have to agree about the look and they only do if there is
	## one place that says what it is.
	"brightness": 1.0,
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
	["toggle_fullscreen", "Fullscreen"],
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
	_apply_typeface()
	_fit_to_the_screen()

## THE WINDOW OPENS AT 1600x900 WHATEVER IT IS OPENING ONTO.
##
## `project.godot` asks for 1600x900 windowed, and nothing ever looked at the
## display. On a 1366x768 laptop — which is still a large slice of what Steam
## runs on — the game opens larger than the screen, with its title bar off the
## top and its footer buttons off the bottom, and the first thing the buyer does
## is not find the Continue button. The arithmetic is separated out and pure so
## it can be asserted headless, because the branch that matters is the one no
## machine in this repo has.
func _fit_to_the_screen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	var want := DisplayServer.window_get_size()
	var fitted := fitted_window_size(want, usable.size)
	if fitted == want:
		return
	DisplayServer.window_set_size(fitted)
	DisplayServer.window_set_position(
		usable.position + (usable.size - fitted) / 2)

## Pure, so it is testable without a monitor. Eighty pixels of margin because a
## window that exactly fills the usable rect still has a title bar on most
## desktops, and the aspect is kept because this game's layout is pinned to it.
static func fitted_window_size(want: Vector2i, usable: Vector2i) -> Vector2i:
	var maxw: int = usable.x - 80
	var maxh: int = usable.y - 80
	if want.x <= maxw and want.y <= maxh:
		return want
	var scale: float = minf(float(maxw) / float(maxi(1, want.x)),
		float(maxh) / float(maxi(1, want.y)))
	return Vector2i(maxi(640, int(want.x * scale)), maxi(360, int(want.y * scale)))

## THE ROOT THEME, AND WHY IT LIVES IN AN AUTOLOAD RATHER THAN IN Boot.
##
## Every harness in this repo instantiates Game.tscn directly and never runs
## Boot at all (that is the gap boot_check.sh exists to close). A theme applied
## in Boot would therefore be applied in the shipped game and in NO screenshot,
## no smoke run and no play run — so the pictures the look is judged from would
## show a different game to the one that ships. An autoload runs on every path
## into the tree, which is what this needs.
##
## `root.theme` is a fallback, not an override: any control that sets its own
## font still wins, so UIKit's per-control faces are refinements on top of this
## rather than a fight with it.
func _apply_typeface() -> void:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	if not Typeface.have():
		# Not fatal and not silent. A missing import leaves the game looking
		# exactly as it did before the fonts existed, which is the one failure
		# a screenshot cannot tell you about.
		Log.w("typeface not imported — falling back to the engine default", "Settings")
		return
	tree.root.theme = Typeface.theme()

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

## AND THE SAME BUTTONS ON A PLAYSTATION PAD, WHICH DOES NOT HAVE THEM.
##
## Godot reports joypad buttons by INDEX, and index 0 is A on an Xbox pad and
## Cross on a DualSense. The whole prompt layer said "A" and "B" and "right
## bumper" to somebody holding a controller with none of those written on it —
## and this is a game whose own design rule is that nothing tells the player to
## press a key by name, precisely so that the prompt is always the truth.
##
## Same keys in both tables on purpose: `Settings.PAD_LABELS.size()` is asserted
## equal in the smoke run, so the two cannot drift the way two copies of a tuned
## number always eventually do.
const PAD_LABELS_PS := {
	JOY_BUTTON_A: "Cross", JOY_BUTTON_B: "Circle",
	JOY_BUTTON_X: "Square", JOY_BUTTON_Y: "Triangle",
	JOY_BUTTON_LEFT_SHOULDER: "L1", JOY_BUTTON_RIGHT_SHOULDER: "R1",
	JOY_BUTTON_START: "Options", JOY_BUTTON_BACK: "Share",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
}

## Which family of glyphs the pad in the port actually has written on it. Godot
## gives us the device name and nothing else, so it is a substring match — and
## "Wireless Controller" is in there because that is what a DualShock 4 reports
## itself as over Bluetooth on Linux.
static func pad_family() -> String:
	var n := Input.get_joy_name(0).to_lower()
	for k in ["dualsense", "dualshock", "ps3", "ps4", "ps5", "sony",
			"wireless controller", "playstation"]:
		if n.find(k) >= 0:
			return "ps"
	return "xbox"

static func pad_label(idx: int) -> String:
	var table: Dictionary = PAD_LABELS_PS if pad_family() == "ps" else PAD_LABELS
	return String(table.get(idx, ""))

func prompt_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "?"
	if not Input.get_connected_joypads().is_empty():
		for ev in InputMap.action_get_events(action):
			if ev is InputEventJoypadButton and PAD_LABELS.has(ev.button_index):
				return pad_label(ev.button_index)
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
	# ...AND NOT A KEY SOMETHING ELSE ALREADY HAS.
	#
	# Rebinding "use" to W silently left W on "walk forward" as well, so one
	# press did both — and the Controls screen went on showing W beside two
	# rows, which reads as a display bug rather than as the thing the player
	# just did. Refused rather than stolen: taking it off the other action is a
	# second surprise, and the player who wanted that can clear it themselves.
	if conflicting_action(action, event) != "":
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

## Which OTHER bindable action already answers to this event, or "" if none.
static func conflicting_action(action: String, event: InputEvent) -> String:
	for other in BINDABLE:
		# BINDABLE is a list of PAIRS — [action, label] — so `String(other)`
		# stringifies the whole array and matches no action at all. The first
		# version of this check returned "" for every event and refused nothing,
		# which is exactly what it looked like before it existed.
		var a := String(other[0])
		if a == action or not InputMap.has_action(a):
			continue
		for e in InputMap.action_get_events(a):
			if event is InputEventKey and e is InputEventKey:
				var want: int = event.physical_keycode if event.physical_keycode != 0 \
					else event.keycode
				var have: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
				if want != 0 and want == have:
					return a
			elif event is InputEventMouseButton and e is InputEventMouseButton:
				if event.button_index == e.button_index:
					return a
	return ""

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
		_queue_save()

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
		# A KEY MISSING FROM THIS ARM IS A SLIDER THAT DOES NOTHING, which is
		# the silent no-op gotcha 15 is about and is worse here than elsewhere:
		# the control is on screen, it moves, and the number beside it changes.
		"master_volume", "sfx_volume", "music_volume", "ambience_volume":
			if Engine.has_singleton("AudioMgr") or AudioMgr != null:
				AudioMgr.master_volume = float(get_value("master_volume"))
				AudioMgr.sfx_volume = float(get_value("sfx_volume"))
				AudioMgr.music_volume = float(get_value("music_volume"))
				AudioMgr.ambience_volume = float(get_value("ambience_volume"))
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
		"msaa":
			if DisplayServer.get_name() == "headless":
				return
			var loop_m := Engine.get_main_loop()
			if loop_m is SceneTree and (loop_m as SceneTree).root != null:
				(loop_m as SceneTree).root.msaa_3d = \
					clampi(int(get_value("msaa")), 0, 2) as Viewport.MSAA
		"fps_cap":
			# Engine.max_fps is 0 for uncapped, which is also this setting's
			# "off", so the two happen to agree and the guard is only about not
			# pinning a headless run to sixty frames it is not drawing.
			if DisplayServer.get_name() == "headless":
				return
			Engine.max_fps = maxi(0, int(get_value("fps_cap")))
		"brightness":
			# Straight onto the live environment. `Grade.apply` is where the
			# value comes FROM, so re-applying the whole grade would work and
			# would also re-do a dozen writes for one number.
			var e := _environment()
			if e != null:
				e.adjustment_brightness = \
					clampf(float(get_value("brightness")), 0.7, 1.3)
		"ui_scale":
			if DisplayServer.get_name() == "headless":
				return
			var loop := Engine.get_main_loop()
			if loop is SceneTree and (loop as SceneTree).root != null:
				(loop as SceneTree).root.content_scale_factor = \
					clampf(float(get_value("ui_scale")), 0.75, 1.5)

## THE LIVE ENVIRONMENT, whichever scene is up. Found by walking rather than by
## a path or an exported field, because there are two scenes with one each — the
## ward and the title vignette — and the whole point of `Grade` is that they are
## the same look. Called once per notch of a slider a player moves twice a
## career, so a walk of a few dozen nodes is the cheap answer.
func _environment() -> Environment:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	var root: Node = (loop as SceneTree).root
	if root == null:
		return null
	var stack: Array = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is WorldEnvironment and (n as WorldEnvironment).environment != null:
			return (n as WorldEnvironment).environment
		for c in n.get_children():
			stack.append(c)
	return null

func _player():
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return null
	return (loop as SceneTree).get_first_node_in_group("player")

# ------------------------------------------------------------------ disk
## SAVING ON EVERY NOTCH OF EVERY SLIDER.
##
## `set_value` wrote the whole config file, synchronously, on each frame of a
## drag — so moving one slider from end to end was forty file writes, and moving
## it back was forty more. It is not a correctness problem and it is exactly the
## kind of thing that makes a settings screen feel cheap on a slow disk, which
## is the screen a buyer opens first.
##
## Half a second, `process_always` so it survives the paused tree a pause-menu
## settings screen sits in, and flushed unconditionally on the way out of the
## tree so nothing is lost if the game is closed mid-drag.
var _save_pending := false
## Counted so the smoke run can assert that five writes in a frame are one write.
var saves_written := 0

func _queue_save() -> void:
	if _save_pending:
		return
	_save_pending = true
	var tree := get_tree()
	if tree == null:
		_save_pending = false
		save_to_disk()
		return
	var t := tree.create_timer(0.5, true, false, true)
	t.timeout.connect(func():
		_save_pending = false
		save_to_disk())

func _exit_tree() -> void:
	if _save_pending:
		_save_pending = false
		save_to_disk()

func save_to_disk() -> void:
	saves_written += 1
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
