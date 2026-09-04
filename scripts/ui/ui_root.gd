extends CanvasLayer
## Owns the HUD and routes every modal screen. Screens are built procedurally on
## demand and freed on close, so nothing is kept in memory or in a .tscn.

## Everything else that was in this table — the dialogue tree, the four
## dexterity games, the shift chooser, the night, the hearing, the shop, the
## tablet — went with the redesign, along with the screens themselves.
const SCREEN_SCRIPTS := {
	"morning": "res://scripts/ui/screen_morning.gd",
	"patient": "res://scripts/ui/screen_patient.gd",
	"chart": "res://scripts/ui/screen_chart.gd",
	"review": "res://scripts/ui/screen_review.gd",
	"day_over": "res://scripts/ui/screen_day_over.gd",
	"board": "res://scripts/ui/screen_board.gd",
	# Both public terminals emitted this and the router had no entry for it, so
	# they beeped and opened nothing — and with no route to a chart except a
	# patient's own card, writing anywhere private was impossible.
	"records": "res://scripts/ui/screen_records.gd",
}

var hud: HUD
var current: Control = null
var current_id := ""

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = HUD.new()
	hud.name = "HUD"
	add_child(hud)
	EventBus.request_ui.connect(open)

## The screen a phase could not be left without used to be put back here when
## Escape dismissed it. There are no phases left to strand: the day runs on one
## clock and the morning review is simply not dismissible.
## Screens that own the only route forward. Escape must not close these.
const UNDISMISSABLE := ["review", "day_over"]

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if current != null:
			# THE SCREENS YOU DO NOT GET TO DISMISS.
			#
			# `review` was guarded and the screen AFTER it was not, so Escape —
			# the universal close-this reflex — killed the End of Shift card and
			# stranded the player in a finished ward: dead clock, blank
			# objective, and "Work tomorrow" gone, which is the only thing that
			# advances the day. The two ending cards had the same hole, and
			# there is nothing behind those at all.
			if current_id in UNDISMISSABLE:
				return
			close()
		else:
			open("pause", {})
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ routing
func open(id: String, ctx: Dictionary = {}) -> void:
	if current != null:
		close()
	var screen: Control = null
	if SCREEN_SCRIPTS.has(id):
		var script: GDScript = load(SCREEN_SCRIPTS[id])
		if script == null or not script.can_instantiate():
			Log.e("screen '%s' failed to load" % id, "UI")
			return
		screen = script.new()
		screen.set("ctx", ctx)
		screen.set("ui", self)
	else:
		screen = _build_simple(id, ctx)
	if screen == null:
		return
	current = screen
	current_id = id
	add_child(screen)
	_set_modal(true, bool(screen.get("pauses_world") if screen.get("pauses_world") != null else true))
	# After it is genuinely up, and regardless of who asked. See EventBus.
	EventBus.ui_opened.emit(id)

func close() -> void:
	if current == null:
		return
	current.queue_free()
	current = null
	current_id = ""
	_set_modal(false)

## Some screens stop the world and some do not.
##
## A card you read while standing in front of somebody must not freeze them:
## the whole reason to walk up to a person is that they are a person, and a
## paused ward is a photograph. Those screens leave the tree running so the
## patient keeps breathing and reacting — but they stop the CLOCK, because time
## passing while you read is a cost nobody agreed to.
var _clock_was_running := false
var _froze_clock := false

func _set_modal(on: bool, pauses := true) -> void:
	# Only a screen that froze the clock may thaw it. Restoring it on every
	# close undid the clock-in the briefing had just performed, because the
	# state being restored was the one from before the button was pressed.
	if on:
		if not pauses:
			_clock_was_running = GameState.clock_running
			_froze_clock = true
			GameState.clock_running = false
	elif _froze_clock:
		GameState.clock_running = _clock_was_running
		_froze_clock = false
	get_tree().paused = on and pauses
	# Half a tannoy line behind the card is worse than no tannoy line — and the
	# world keeps talking for as long as the card is up, because most screens do
	# not pause it.
	var subs = get_tree().get_first_node_in_group("hud")
	if subs != null and subs.has_method("set_modal"):
		subs.call("set_modal", on)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if on else Input.MOUSE_MODE_CAPTURED
	var p = get_tree().get_first_node_in_group("player")
	if p:
		p.input_locked = on
	if hud:
		hud.set_crosshair_visible(not on)

# ------------------------------------------------------------------ simple screens
func _build_simple(id: String, _ctx: Dictionary) -> Control:
	match id:
		"pause": return _pause_screen()
		"settings": return _settings_screen()
		"controls": return _controls_screen()
		"credits": return _credits_screen()
	Log.w("unknown screen '%s'" % id, "UI")
	return null

func _shell(width: float, height: float, heading: String) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(UIKit.dim_background())
	var panel := UIKit.center_panel(width, height)
	root.add_child(panel)
	var v := UIKit.vbox(12)
	panel.add_child(v)
	if heading != "":
		v.add_child(UIKit.title(heading, 26, UIKit.ACCENT))
		v.add_child(UIKit.rule())
	return [root, v]

# ---- settings
##
## Every one of these is a thing a player will look for in the first two
## minutes and, until now, not find. Mouse sensitivity in particular: a
## first-person game whose look speed cannot be changed is one somebody
## refunds rather than adjusts to.
func _settings_screen() -> Control:
	var parts := _shell(680, 720, "Settings")
	var outer: VBoxContainer = parts[1]
	# The options scroll and the buttons do not.
	#
	# Fifteen rows at a fixed height overflowed a fixed-height panel and pushed
	# "Back" off the bottom of the screen — a settings screen you cannot leave
	# is worse than no settings screen. A scroll region means this cannot break
	# again if a row is added, or on a shorter display.
	var v := UIKit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroller := UIKit.scroll(v)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroller)
	var pct := func(x: float) -> String: return "%d%%" % int(round(x * 100.0))

	v.add_child(UIKit.label("AUDIO", 13, UIKit.INK_DIM))
	v.add_child(UIKit.slider("Master volume", Settings.get_value("master_volume"),
		0.0, 1.0, 0.05, func(x): Settings.set_value("master_volume", x), pct))
	v.add_child(UIKit.slider("Effects", Settings.get_value("sfx_volume"),
		0.0, 1.0, 0.05, func(x):
			Settings.set_value("sfx_volume", x)
			# Play something at the new level, so the slider answers the
			# question it is actually being asked.
			AudioMgr.play("beep", -8.0), pct))
	v.add_child(UIKit.slider("Ambience", Settings.get_value("music_volume"),
		0.0, 1.0, 0.05, func(x): Settings.set_value("music_volume", x), pct))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("CONTROLS AND CAMERA", 13, UIKit.INK_DIM))
	v.add_child(UIKit.slider("Mouse sensitivity", Settings.get_value("mouse_sensitivity"),
		0.2, 3.0, 0.05, func(x): Settings.set_value("mouse_sensitivity", x),
		func(x: float) -> String: return "%.2fx" % x))
	v.add_child(UIKit.toggle("Invert look", Settings.get_value("invert_y"),
		func(b): Settings.set_value("invert_y", b)))
	v.add_child(UIKit.slider("Field of view", Settings.get_value("fov"),
		60.0, 110.0, 1.0, func(x): Settings.set_value("fov", x),
		func(x: float) -> String: return "%d" % int(x)))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("COMFORT", 13, UIKit.INK_DIM))
	v.add_child(UIKit.slider("Camera shake", Settings.get_value("camera_shake"),
		0.0, 1.0, 0.1, func(x): Settings.set_value("camera_shake", x), pct))
	v.add_child(UIKit.slider("Head bob", Settings.get_value("head_bob"),
		0.0, 1.0, 0.1, func(x): Settings.set_value("head_bob", x), pct))
	v.add_child(UIKit.toggle("Subtitles", Settings.get_value("subtitles"),
		func(b): Settings.set_value("subtitles", b)))

	v.add_child(UIKit.slider("Stick sensitivity", Settings.get_value("pad_look_sensitivity"),
		0.2, 3.0, 0.05, func(x): Settings.set_value("pad_look_sensitivity", x),
		func(x: float) -> String: return "%.2fx" % x))
	v.add_child(UIKit.button("Key bindings…", func(): open("controls", {})))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("DISPLAY", 13, UIKit.INK_DIM))
	v.add_child(UIKit.toggle("Fullscreen", Settings.get_value("fullscreen"),
		func(b): Settings.set_value("fullscreen", b)))
	v.add_child(UIKit.toggle("V-Sync", Settings.get_value("vsync"),
		func(b): Settings.set_value("vsync", b)))

	outer.add_child(UIKit.spacer(6))
	var row := UIKit.hbox(10)
	var reset := UIKit.button("Reset to defaults", func():
		Settings.reset_to_defaults()
		# Rebuilt rather than updated: fifteen widgets each holding their own
		# copy of a value is fifteen things to forget to refresh.
		close()
		open("settings", {}), Color(0.28, 0.20, 0.20))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset)
	var back := UIKit.button("Back", close)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	outer.add_child(row)
	return parts[0]

# ---- controls
##
## Rebindable keys, which is the single most-cited missing feature in reviews of
## first-person games that do not have them. Left-hand column is what the action
## is in the fiction — "read the chart", not "chart" — because an action id is a
## programmer's name for a thing and nobody else's.
##
## Listening is a MODE rather than a dialog: press the row, the row says "press
## a key", the next key press lands. Escape cancels, and is therefore the one
## key nobody can bind.
var _listening_for := ""

func _controls_screen() -> Control:
	var parts := _shell(660, 720, "Controls")
	var outer: VBoxContainer = parts[1]
	var v := UIKit.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var scroller := UIKit.scroll(v)
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroller)

	v.add_child(UIKit.label("KEYBOARD AND MOUSE", 13, UIKit.INK_DIM))
	for entry in Settings.BINDABLE:
		v.add_child(_binding_row(String(entry[0]), String(entry[1])))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("CONTROLLER", 13, UIKit.INK_DIM))
	v.add_child(UIKit.label(
		"A pad works without setting anything up: left stick walks, right stick "
		+ "looks, A jumps, X uses, right bumper picks up, left bumper throws, "
		+ "Start pauses.", 13, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true))

	outer.add_child(UIKit.spacer(6))
	var row := UIKit.hbox(10)
	var reset := UIKit.button("Reset bindings", func():
		Settings.reset_bindings()
		_listening_for = ""
		close()
		open("controls", {}), Color(0.28, 0.20, 0.20))
	reset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(reset)
	var back := UIKit.button("Back", func():
		_listening_for = ""
		close())
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(back)
	outer.add_child(row)
	return parts[0]

func _binding_row(action: String, label: String) -> Control:
	var h := UIKit.hbox(8)
	h.add_child(UIKit.label(label, 15, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT))
	var listening: bool = _listening_for == action
	var b := UIKit.button(
		"press a key…" if listening else Settings.binding_label(action),
		func(): _start_listening(action),
		Color(0.32, 0.28, 0.14) if listening else UIKit.PANEL_LIGHT, 190)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	h.add_child(b)
	return h

func _start_listening(action: String) -> void:
	_listening_for = action
	set_process_input(true)
	close()
	open("controls", {})

func _input(event: InputEvent) -> void:
	if _listening_for == "" or current_id != "controls":
		return
	var usable: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if not usable:
		return
	get_viewport().set_input_as_handled()
	var action := _listening_for
	_listening_for = ""
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		AudioMgr.play("error", -16.0)
	elif Settings.rebind(action, event):
		AudioMgr.play("ding", -14.0)
	close()
	open("controls", {})

# ---- credits
func _credits_screen() -> Control:
	var parts := _shell(680, 660, "Chronic Care")
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.label(
		"A hospital management game about the gap between what happened, what "
		+ "you wrote down, and what everybody thinks.", 15, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_CENTER, true))
	v.add_child(UIKit.rule())
	var creds := [
		["Design and code", "Built as one long conversation."],
		["Art", "There isn't any. Every shape in this building is assembled from "
			+ "boxes and cylinders at load time."],
		["Audio", "There isn't any of that either. Every sound is a waveform "
			+ "synthesised the first time you hear it."],
		["Engine", "Godot 4.3, and a great deal of patience with its loader."],
		["Medicine", "Entirely invented. Chronic Beige is not a condition. "
			+ "Please do not attempt any procedure in this game."],
		["With thanks to", "Everybody who said \"this looks like blocky junk\" "
			+ "and meant it kindly."],
	]
	for c in creds:
		var box := UIKit.panel(UIKit.PANEL_LIGHT, 6)
		var bv := UIKit.vbox(2)
		bv.add_child(UIKit.label(String(c[0]), 15, UIKit.ACCENT))
		bv.add_child(UIKit.label(String(c[1]), 13, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true))
		box.add_child(bv)
		v.add_child(box)
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.button("Back", close))
	return parts[0]

# ---- pause
func _pause_screen() -> Control:
	var parts := _shell(400, 430, "Paused")
	var v: VBoxContainer = parts[1]
	v.add_child(UIKit.label("Day %d · %s" % [GameState.day, GameState.time_string()], 15, UIKit.INK_DIM))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Resume", close))
	# NO MID-SHIFT SAVE. The save carries GameState and the chart; it does not
	# carry the day — who you have decided about, who you asked, what you sent
	# for, which records you have read. A player who used this and pressed
	# Continue got their notes back and none of their decisions, silently, which
	# is worse than not offering it. The autosave happens at the handover, where
	# a day is genuinely over and the only thing that carries is the carry.
	v.add_child(UIKit.label("A shift is one sitting. It saves at the handover.",
		12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER, true))
	v.add_child(UIKit.button("Settings", func(): open("settings", {})))
	v.add_child(UIKit.button("Controls", func(): open("controls", {})))
	v.add_child(UIKit.spacer(8))
	v.add_child(UIKit.button("Quit to Menu", func():
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"), Color(0.3, 0.16, 0.16)))
	return parts[0]
