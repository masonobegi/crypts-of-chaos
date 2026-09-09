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

## Set by the TITLE SCREEN before this is added to the tree.
##
## `MainMenu._open_menu_screen` builds its own UIRoot, because UIRoot lives in
## the game scene and a player should not have to start a career to turn the
## volume down. But UIRoot assumes it is in a game: it builds a HUD, and
## `_set_modal(false)` puts the mouse back to CAPTURED because that is what
## closing a card in the ward should do.
##
## So clicking Settings on the title screen and then Back left the full in-game
## HUD — "Day 1", "8:00 AM", "$900", "[E] use [LMB] grab" — painted permanently
## over the main menu, and captured the cursor, so no button on the title screen
## could be clicked again. Settings is one of the first things anybody presses.
var menu_mode := false

## Which screen to return to when this one closes. One level is enough: the only
## nesting in the game is pause -> settings/controls/credits.
var _came_from := ""

## Rate-limited, because HSlider emits value_changed on every STEP of a drag and
## not on release. Range 0..1 at step 0.05 is twenty steps, so one sweep of the
## Effects slider fired twenty 880 Hz beeps inside a fraction of a second.
var _last_audition := 0

func _audition() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_audition < 140:
		return
	_last_audition = now
	AudioMgr.play("beep", -8.0)

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not menu_mode:
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
	# ...AND FULLSCREEN, WHICH WORKS WHEREVER YOU ARE. Deliberately above the
	# screen handling: it is not "get me out of this", it is a display setting,
	# and there is no state in which a player pressing it wants something else
	# to happen first.
	if event.is_action_pressed("toggle_fullscreen"):
		_fullscreen_pressed()
		get_viewport().set_input_as_handled()
		return
	# `ui_cancel` is B on a pad and Escape on a keyboard; `pause` is Escape and
	# Start. Only "get me out of this screen" is shared — B ALSO CROUCHES, so
	# `ui_cancel` deliberately does not open the pause menu when nothing is
	# open, or every crouch in the ward would stop the game.
	var closing := event.is_action_pressed("pause") \
		or (current != null and event.is_action_pressed("ui_cancel"))
	if closing:
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
			# Back to where you came from, not out to the world. Settings and
			# Controls are opened FROM the pause menu, and closing them dropped
			# the player straight into the ward with the game unpaused — so the
			# way out of a submenu was to quit the menu entirely.
			if _came_from != "":
				var back := _came_from
				_came_from = ""
				# One swap, one sound. Escape out of Settings is the same
				# gesture `_back()` performs from the button, and the guard
				# has to be in both places or the escape key gets a card put
				# away and another taken out in the same frame.
				_swapping = true
				close()
				_swapping = false
				open(back, {})
			else:
				close()
		elif not menu_mode:
			open("pause", {})
		# ...and on the TITLE screen there is nothing to pause. Escape opened the
		# in-game pause menu over the main menu and set `get_tree().paused`, which
		# freezes a title screen that has no way to unpause itself.
		get_viewport().set_input_as_handled()

# ------------------------------------------------------------------ routing
## EVERY SCREEN IN THE GAME OPENED AND CLOSED IN SILENCE.
##
## The patient card, the chart, records, the handover board, the pause menu,
## settings, controls, credits and the morning briefing — the first thing a
## stranger ever sees — all appeared and vanished with no sound at all, in a
## build where every BUTTON has a press sound and a hover sound. A game whose
## widgets are louder than the modals they live in reads as unfinished, and
## this is the most repeated interaction in the loop: a card opened five times
## a bed, five beds a night, nine nights.
##
## It goes HERE and not in the screens. Two screens already play their own and
## that is precisely why the other eight were silent — a per-screen sound is a
## thing eight people have to remember, and eight of them did not.
##
## The two that own theirs are listed rather than asked, because the screens
## are built from a path table by `script.new()` and a `owns_open_sound`
## property would have to be declared on each of them — which is the same
## per-screen bookkeeping this exists to remove. `review` opens on a folder
## being opened and `day_over` on a rubber stamp; both are the sound of the
## thing that just happened, not of a card arriving, and a rustle underneath
## either would only blur it.
const OWN_OPEN_SOUND := {"review": true, "day_over": true}
const CARD_UP_DB := -14.0
const CARD_DOWN_DB := -16.0
## True while `open()` is replacing one screen with another. Without it a swap
## fires the down and the up in the same frame, which is not two sounds — it is
## one muddy one.
var _swapping := false

func open(id: String, ctx: Dictionary = {}) -> void:
	if current != null:
		_swapping = true
		close()
		_swapping = false
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
	# Before `add_child`, so the card and its sound arrive together. A sheet
	# lifted off the pile: the same material as the one that goes down on
	# `close()`, a fifth higher, because up and down is the one thing a player
	# needs to be able to tell without looking.
	if not OWN_OPEN_SOUND.has(id):
		AudioMgr.play("paper", CARD_UP_DB, 1.25)
	add_child(screen)
	# The pause menu, settings, controls and credits are plain Controls built by
	# `_build_simple`, not ScreenBases, so they have no `_focus_first` of their
	# own — and they are the screens a pad player reaches first. Deferred: the
	# buttons do not exist until the frame after `_ready` has built them.
	call_deferred("_focus_into", screen)
	_set_modal(true, bool(screen.get("pauses_world") if screen.get("pauses_world") != null else true))
	# After it is genuinely up, and regardless of who asked. See EventBus.
	EventBus.ui_opened.emit(id)

## Focus the first control on a screen, whatever kind of screen it is.
func _focus_into(screen: Control) -> void:
	if is_instance_valid(screen) and screen.is_inside_tree():
		UIKit.focus_first(screen)

## Out of a submenu, back to the menu that opened it — or out to the world if
## nothing did. "Back" from Settings used to call `close()`, which dropped the
## player into the unpaused ward rather than back to the pause menu they came
## from, so the only way out of a submenu was to leave the menu entirely.
func _back() -> void:
	if _came_from == "":
		close()
		return
	var to := _came_from
	_came_from = ""
	# One gesture, one sound. Backing out of Settings into the pause menu is a
	# card being replaced, not a card being put away and a different one taken
	# out a frame later; the sound the player wants is the one that arrives.
	_swapping = true
	close()
	_swapping = false
	open(to, {})

func close() -> void:
	if current == null:
		return
	# LEAVING THE CONTROLS SCREEN STOPS IT LISTENING. `Back` and `Reset` both
	# cleared this by hand and every other way out of the screen did not — so
	# closing it with Escape mid-rebind left `_listening_for` set, and the next
	# visit opened already waiting for a key nobody had asked it to want.
	if current_id == "controls":
		_listening_for = ""
	# The card going back down — but not when it is being swapped for another
	# one, which is a single gesture and gets a single sound. See `_swapping`.
	if not _swapping:
		AudioMgr.play("paper", CARD_DOWN_DB, 0.85)
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
	# GUARDED. `get_tree()` is null for a node that has left the tree, and this
	# runs from `close()` — which is exactly what happens on the way out of a
	# scene: the screenshot harness swapping the title screen for the ward threw
	# "Invalid assignment of property 'paused' on a null instance" twice, and
	# quitting to the menu takes the same path.
	var t := get_tree()
	if t == null:
		return
	t.paused = on and pauses
	# Half a tannoy line behind the card is worse than no tannoy line — and the
	# world keeps talking for as long as the card is up, because most screens do
	# not pause it.
	var subs = get_tree().get_first_node_in_group("hud")
	if subs != null and subs.has_method("set_modal"):
		subs.call("set_modal", on)
	# On the title screen there is no first-person view to go back to, so the
	# cursor stays.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if (on or menu_mode) \
		else Input.MOUSE_MODE_CAPTURED
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
		"licences": return _licences_screen()
	Log.w("unknown screen '%s'" % id, "UI")
	return null

## ALT-TAB STOPS THE SHIFT.
##
## The ward clock is the only currency in this game and it ran while the window
## was behind a browser: a player who looked something up lost minutes off a
## twelve-hour budget for it. Opening the pause screen rather than setting
## `GameState.clock_running = false` directly, because a bare clock stop leaves
## somebody walking round a ward with a frozen clock and no way to tell why —
## the pause screen already stops the tree, releases the cursor and offers a
## visible Resume.
##
## GUARDED ON `template`, WHICH IS THE BUILD AND NOT THE DISPLAY. The obvious
## guard is `DisplayServer.get_name() != "headless"` and it is wrong: `./play.sh
## keys` runs under Xvfb — it has to, because mouse capture is not real without
## a display (gotcha 23) — where the name is "x11" and focus notifications do
## arrive. That harness drives a whole shift through the input layer, and a
## pause screen appearing mid-run breaks it intermittently rather than
## reproducibly. `OS.has_feature("template")` is true only in an exported
## build, which is the only place this matters and the only place no harness
## runs.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and OS.has_feature("template"):
		pause_for_focus_loss()

## Split out so the smoke run can press it without an exported build and a
## window manager. A guard that cannot be tested is a guard nobody knows about.
## F11, AND IT IS A REAL ACTION RATHER THAN A KEYCODE IN A BRANCH.
##
## There is a Fullscreen toggle on the Settings screen and no way to reach it
## without stopping the game — which is the one thing a player wants to do in
## the first ten seconds, before they have found the settings screen at all.
## Bound as `toggle_fullscreen` so it appears on the Controls screen and can be
## rebound like everything else: an undiscoverable shortcut is only half a
## feature, and a game whose own design rule is that nothing tells you to press
## a key by name has to be able to tell you what this one is.
func _fullscreen_pressed() -> void:
	Settings.set_value("fullscreen", not bool(Settings.get_value("fullscreen")))

func pause_for_focus_loss() -> void:
	if current != null or menu_mode:
		return
	open("pause", {})

func _shell(width: float, height: float, heading: String) -> Array:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(UIKit.dim_background())
	# CAP IT AGAINST THE WINDOW, the way `ScreenBase.card_shell` has since a
	# patient card ran off the bottom of the screen and took its last button
	# with it. This one never did, and the reason it matters is the setting two
	# rows below it: "Interface size" sets `content_scale_factor`, which divides
	# the visible canvas rect — at 1.4 the 900-unit viewport is 643 units tall,
	# and a Settings screen asking for 830 put its own footer, and the Controls
	# screen's, off the bottom of the monitor. So the one control a player
	# reaches for when the text is too small was the control that hid the button
	# they needed to press next. `get_visible_rect()` is the scaled number,
	# which is why it is read from the root rather than from the window.
	height = minf(height, get_tree().root.get_visible_rect().size.y - 48.0)
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
	# TALLER. The viewport is a fixed 1600x900 in canvas units whatever the
	# monitor is, and 720 of it left three rows and the whole DISPLAY heading
	# under the fold on a card with twelve rows on it. 830 leaves a clear
	# thirty-five pixels top and bottom and shows three more of them; it still
	# scrolls, because it always did.
	var parts := _shell(680, 830, "Settings")
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
			_audition(), pct))
	# "Music", not "Ambience". It is the slider that turns the score down, and
	# a player who wants the score turned down does not go looking under
	# "Ambience" — they conclude there is no way to do it. The setting key stays
	# `music_volume`, which is what it has always actually been.
	v.add_child(UIKit.slider("Music", Settings.get_value("music_volume"),
		0.0, 1.0, 0.05, func(x): Settings.set_value("music_volume", x), pct))
	# ...AND THE ROW THE RENAME ABOVE LEFT WITHOUT ONE. Calling the score's
	# slider "Music" was right, and it left the room tone and the world outside
	# the windows — the two continuous beds, which are the sound of the
	# building itself — being turned down by a control named after the
	# vibraphone, with "Effects" not touching them either. A player wanting a
	# quieter hospital had nothing to drag.
	v.add_child(UIKit.slider("Ambience", Settings.get_value("ambience_volume"),
		0.0, 1.0, 0.05, func(x): Settings.set_value("ambience_volume", x), pct))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("CONTROLS AND CAMERA", 13, UIKit.INK_DIM))
	v.add_child(UIKit.slider("Mouse sensitivity", Settings.get_value("mouse_sensitivity"),
		0.2, 3.0, 0.05, func(x): Settings.set_value("mouse_sensitivity", x),
		func(x: float) -> String: return "%.2fx" % x))
	# NEXT TO THE MOUSE ONE, because it is the same question asked of the other
	# hand. It sat under "Subtitles" in the COMFORT block, which reads as a
	# grouping error in the shipped settings screenshot.
	v.add_child(UIKit.slider("Stick sensitivity", Settings.get_value("pad_look_sensitivity"),
		0.2, 3.0, 0.05, func(x): Settings.set_value("pad_look_sensitivity", x),
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
	# A SAVED, DEFAULTED, READ SETTING WITH NO ROW ON THE SCREEN is a setting
	# that does not exist. `pad_vibration` has a default, is persisted, and is
	# checked before every rumble — and the only way to turn it off was to edit
	# settings.cfg by hand. It is also the one comfort setting a player looks
	# for first if they have a reason to.
	v.add_child(UIKit.toggle("Controller vibration", Settings.get_value("pad_vibration"),
		func(b): Settings.set_value("pad_vibration", b)))
	v.add_child(UIKit.button("Key bindings…", func(): open("controls", {})))

	v.add_child(UIKit.rule())
	v.add_child(UIKit.label("DISPLAY", 13, UIKit.INK_DIM))
	# THE TEXT IS THE GAME. A chart, a board and an argument about a document —
	# and every card was built at one size for one viewport, with no way to make
	# any of it bigger. `content_scale_factor` scales the canvas layer and
	# leaves the 3D viewport alone, so the ward stays the size it is and the
	# paperwork grows; the cards already cap themselves against the viewport, so
	# they stay on the screen as it does.
	v.add_child(UIKit.slider("Interface size", Settings.get_value("ui_scale"),
		0.8, 1.4, 0.05, func(x): Settings.set_value("ui_scale", x), pct))
	# THE KNOB A PLAYER LOOKS FOR IN A DARK ROOM AND A BRIGHT ONE. Dark type on
	# a pale ward, on somebody's laptop, in the afternoon — and there was no way
	# to change it. It goes through `Grade`, so the ward and the title screen
	# stay one definition of the look.
	v.add_child(UIKit.slider("Brightness", Settings.get_value("brightness"),
		0.7, 1.3, 0.05, func(x): Settings.set_value("brightness", x), pct))
	v.add_child(UIKit.toggle("Fullscreen", Settings.get_value("fullscreen"),
		func(b): Settings.set_value("fullscreen", b)))
	v.add_child(UIKit.toggle("V-Sync", Settings.get_value("vsync"),
		func(b): Settings.set_value("vsync", b)))
	# NO GRAPHICS OPTIONS AT ALL, and both of the compulsory ones cost. 4x MSAA
	# is the single most expensive thing this renderer does on an integrated
	# GPU, and an uncapped frame rate means a menu with three buttons on it runs
	# a laptop's fan flat out. Sliders rather than toggles because there are
	# three settings and two, and a formatter says what the number means.
	v.add_child(UIKit.slider("Anti-aliasing", Settings.get_value("msaa"),
		0.0, 2.0, 1.0, func(x): Settings.set_value("msaa", int(x)),
		func(x: float) -> String:
			return ["off", "2x", "4x"][clampi(int(x), 0, 2)]))
	v.add_child(UIKit.slider("Frame rate cap", Settings.get_value("fps_cap"),
		0.0, 240.0, 30.0, func(x): Settings.set_value("fps_cap", int(x)),
		func(x: float) -> String:
			return "uncapped" if int(x) <= 0 else "%d fps" % int(x)))

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
	var back := UIKit.button("Back", _back)
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
	# Taller for the same reason as Settings: ten binding rows and a paragraph
	# about the pad do not fit in 720 of a 900-tall viewport.
	var parts := _shell(660, 830, "Controls")
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
	# EVERY LINE OF THIS IS NOW TRUE, WHICH IT WAS NOT. "Left stick walks" was
	# copy and not code for as long as this screen has existed: walking is
	# `Input.get_vector` over four actions that had a key each and no axis, so a
	# player holding a pad could look all the way round the ward without taking
	# a step. Menus were worse — the D-pad moved a selection nothing had taken,
	# and A and B were not bound to `ui_accept`/`ui_cancel` at all.
	v.add_child(UIKit.label(
		"A pad works without setting anything up: left stick walks, right stick "
		+ "looks, A jumps, B crouches, X uses, left stick click hurries, right "
		+ "bumper picks up, left bumper throws, Start pauses. In a menu the "
		+ "D-pad moves, A chooses and B goes back.", 13, UIKit.INK_DIM,
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
		_back())
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
	# CLOSE FIRST, THEN ARM. `close()` clears `_listening_for` on the way out of
	# the controls screen, and this rebuilds that screen by closing and
	# reopening it — so setting the field first meant closing it immediately
	# unset the thing that had just been set, and no row ever listened.
	close()
	_listening_for = action
	set_process_input(true)
	open("controls", {})

func _input(event: InputEvent) -> void:
	if _listening_for == "" or current_id != "controls":
		return
	# A PAD BUTTON CANCELS. Pad bindings are deliberately fixed, so `rebind`
	# refuses a joypad event — which meant somebody who pressed A on a binding
	# row got "press a key…" and, with no keyboard in reach, no way out of it at
	# all: B was not a key either, so the row listened forever. Any pad button
	# now backs out of it, which is what B would have done anywhere else.
	var cancelled: bool = event is InputEventJoypadButton and event.pressed
	var usable: bool = cancelled \
		or (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed)
	if not usable:
		return
	get_viewport().set_input_as_handled()
	var action := _listening_for
	_listening_for = ""
	if cancelled or (event is InputEventKey and event.keycode == KEY_ESCAPE):
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
		# THE ONE THING IN THE GAME SOMEBODY ELSE MADE, and the SIL Open Font
		# License asks for the notice to travel with the software. The licence
		# files themselves ship in `assets/fonts/` — `include_filter` in
		# export_presets.cfg puts them in the build, because a .txt is not an
		# imported resource and "all_resources" does not carry one.
		["Type", "Instrument Sans by the Instrument Sans Project Authors; IBM "
			+ "Plex Mono and IBM Plex Serif by IBM; Nothing You Could Do by "
			+ "Kimberly Geswein. All four under the SIL Open Font License 1.1, "
			+ "whose text ships beside them. They are the only thing here "
			+ "nobody in this conversation made."],
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
	v.add_child(UIKit.button("Licences", func(): open("licences", {})))
	v.add_child(UIKit.button("Back", _back))
	return parts[0]

## THE LICENCE TEXT, IN THE GAME, WHICH IS WHERE IT HAS TO BE.
##
## Three OFL families ship with their notices beside them and the SIL Open Font
## License asks for the notice to travel with the software — and "travel with"
## has always meant a .txt in the archive, which a player never opens and which
## a store page never shows. Godot's own MIT notice was not in the build at all,
## and it is required by the engine's licence.
##
## Nothing new ships for this: `Engine.get_license_text()` and
## `get_copyright_info()` are compiled in, and the three OFL files are already
## carried by `include_filter`. It is a screen that reads what is there.
func _licences_screen() -> Control:
	var parts := _shell(760, 700, "Licences")
	var v: VBoxContainer = parts[1]
	var body := UIKit.vbox(10)
	for f in ["OFL-InstrumentSans.txt", "OFL-IBMPlex.txt", "OFL-NothingYouCouldDo.txt"]:
		var txt := FileAccess.get_file_as_string("res://assets/fonts/" + f)
		if txt.strip_edges() == "":
			continue
		body.add_child(UIKit.label(f, 13, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
		body.add_child(UIKit.label(txt, 11, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true, Typeface.mono()))
	body.add_child(UIKit.label("Godot Engine", 13, UIKit.ACCENT, HORIZONTAL_ALIGNMENT_LEFT))
	body.add_child(UIKit.label(Engine.get_license_text(), 11, UIKit.INK_DIM,
		HORIZONTAL_ALIGNMENT_LEFT, true, Typeface.mono()))
	# ...AND EVERYTHING THE ENGINE ITSELF DEPENDS ON. Two hundred-odd entries,
	# every one of them a notice somebody is owed, and all of it already in the
	# binary.
	for entry in Engine.get_copyright_info():
		var name := String(entry.get("name", ""))
		var lines: Array = []
		for part in entry.get("parts", []):
			for c in Array(part.get("copyright", [])):
				lines.append(String(c))
		if name == "" or lines.is_empty():
			continue
		body.add_child(UIKit.label("%s — %s" % [name,
			", ".join(PackedStringArray(lines))], 10, UIKit.INK_DIM,
			HORIZONTAL_ALIGNMENT_LEFT, true, Typeface.mono()))
	v.add_child(UIKit.scroll(body))
	v.add_child(UIKit.button("Back", func(): open("credits", {})))
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
	v.add_child(UIKit.button("Settings", func():
		_came_from = "pause"
		open("settings", {})))
	v.add_child(UIKit.button("Controls", func():
		_came_from = "pause"
		open("controls", {})))
	v.add_child(UIKit.spacer(8))
	# A SHIFT IS ONE SITTING, AND THIS THROWS IT AWAY.
	#
	# The autosave is written once, by the End of Shift card, at the end of a
	# night. Quitting to the menu at four in the afternoon discards everything
	# since eight in the morning — every chart read, every note, every decision —
	# and the button said nothing about it. It sits two rows under "Resume" in a
	# menu people open to change the volume.
	v.add_child(UIKit.label(
		"The shift is only saved when it ends. Leaving now loses today.",
		12, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_LEFT, true))
	var confirm := {"armed": false}
	var quit_btn := UIKit.button("Quit to Menu", Callable(), Color(0.3, 0.16, 0.16))
	quit_btn.pressed.connect(func():
		if not confirm["armed"]:
			confirm["armed"] = true
			quit_btn.text = "Lose today's shift — press again"
			return
		get_tree().paused = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	v.add_child(quit_btn)
	# AND OUT OF THE GAME ENTIRELY, which was only possible from the title
	# screen — so a player who wanted to stop had to lose the shift to the menu
	# first and then quit from there, which is two confirmations for one
	# decision and looks like the game arguing with them. Same two-press arm as
	# its neighbour, because it throws away the same day.
	var bye := {"armed": false}
	var desk_btn := UIKit.button("Quit to Desktop", Callable(), Color(0.3, 0.16, 0.16))
	desk_btn.pressed.connect(func():
		if not bye["armed"]:
			bye["armed"] = true
			desk_btn.text = "Lose today's shift and quit — press again"
			return
		get_tree().quit())
	v.add_child(desk_btn)
	return parts[0]
