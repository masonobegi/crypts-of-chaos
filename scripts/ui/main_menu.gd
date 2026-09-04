extends Control
## Title screen. Also where a run's seed gets chosen, so a good shift can be
## shared with a number.

var _seed_field: LineEdit = null
var _panel: PanelContainer = null
var _scrim: ColorRect = null
var _scene = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_backdrop()

	# Short on purpose. A PanelContainer grows to fit, so this is a floor and
	# not a ceiling — the panel is exactly as tall as what is in it, which is
	# different on a first run and a hundredth.
	var panel := UIKit.center_panel(660, 420)
	_panel = panel
	add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)

	v.add_child(UIKit.title("CHRONIC CARE", 44, UIKit.ACCENT))
	v.add_child(UIKit.label("A broke doctor. A struggling hospital.\nPatients who really should have gone home by now.",
		16, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.rule())

	# UIKit.button flips its text to paper-on-ink for a dark background, which
	# is what makes this the one emphatic control on a page of pale ones.
	var go := UIKit.button("New Career", _new_career, Color(0.11, 0.30, 0.29))
	go.add_theme_font_size_override("font_size", 20)
	v.add_child(go)
	if SaveSystem.has_save(SaveSystem.AUTOSAVE):
		var info := SaveSystem.list_saves()
		var label := "Continue"
		for s in info:
			if String(s["slot"]) == SaveSystem.AUTOSAVE:
				label = "Continue — Day %d, %s" % [int(s["day"]), UIKit.money_str(int(s["money"]))]
		v.add_child(UIKit.button(label, _continue))

	# A career tally, a list of endings found and a rack of unlockable starting
	# perks used to sit here. They were all reads over Meta, which was the save
	# file for a game made of many runs; this one is a ward, five people and a
	# day, and it does not keep score across them.

	var opts := UIKit.hbox(8)
	for entry in [["Settings", "settings"], ["Controls", "controls"],
			["Credits", "credits"]]:
		var screen_id := String(entry[1])
		var b2 := UIKit.button(String(entry[0]), func(): _open_menu_screen(screen_id))
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opts.add_child(b2)
	v.add_child(opts)
	v.add_child(UIKit.spacer(10))
	v.add_child(UIKit.label("Run seed (optional)", 13, UIKit.INK_DIM))
	_seed_field = LineEdit.new()
	_seed_field.placeholder_text = "leave blank for random"
	_seed_field.add_theme_font_size_override("font_size", 15)
	v.add_child(_seed_field)

	v.add_child(UIKit.spacer(10))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label(
		"WASD move · E use · LMB grab · RMB throw · Esc pause",
		13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label(
		"Everything in this game is fictional and extremely stupid on purpose.",
		12, Color(UIKit.INK.r, UIKit.INK.g, UIKit.INK.b, 0.45),
		HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.button("Quit", func(): get_tree().quit()))

	# The title screen had no sound at all, which is the first thing anybody
	# hears of this game and it was nothing. But building the score is about
	# eight tenths of a second of straight-line GDScript, and calling it from
	# the top of _ready() spent all of that BEFORE anything had been laid out:
	# roughly fifty frames of an empty black window as the first thing anybody
	# SEES of this game. Nothing in the project catches it — play_music returns
	# at once under headless, and --fixed-fps reports the stalled frame as a
	# sixtieth of a second however long it really took — so it survived every
	# harness we have. Two waits, because process_frame is emitted during the
	# idle step and the draw for that frame has not happened yet when the first
	# one comes back; after the second, the menu is genuinely on the screen and
	# the hitch happens behind something rather than instead of it.
	await get_tree().process_frame
	await get_tree().process_frame
	if is_inside_tree():
		AudioMgr.play_music()

## The title screen looks through a window into the building.
##
## A panel on a flat dark rectangle is a strange first thing to show somebody
## about a game whose whole look is a bright cartoon hospital, so this renders a
## corner of a ward into a SubViewport and puts the menu on top of it. Needs its
## own World3D — the menu scene is a Control tree with no 3D world of its own,
## and without this the room would have nowhere to exist.
func _backdrop() -> void:
	var holder := SubViewportContainer.new()
	holder.stretch = true
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	holder.add_child(vp)
	_scene = MenuScene.new()
	vp.add_child(_scene)
	# A scrim, because the panel has to be readable over whatever the camera
	# happens to be pointing at and the camera is deliberately not still.
	var scrim := ColorRect.new()
	scrim.color = Color(0.05, 0.08, 0.11, 0.18)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)
	_scrim = scrim

## Dress the title screen as a Steam capsule and hold still.
##
## The capsule is the single image that decides whether anybody ever clicks on
## this game, and a screenshot of a menu is not one: it is a picture of some
## buttons. This strips the chrome, re-frames the camera on the people rather
## than on the space behind a panel, and lays the title out to the left the way
## every capsule in the store does.
##
## Deliberately built out of the real menu rather than a separate mock, so the
## capsule is a promise the game keeps on its own first frame.
func set_capsule_mode(on: bool) -> void:
	if _panel != null:
		_panel.visible = not on
	if _scrim != null:
		_scrim.color = Color(0.05, 0.08, 0.11, 0.10 if on else 0.18)
	if _scene != null and _scene.has_method("pose_for_capsule"):
		_scene.pose_for_capsule(on)
	if not on:
		if _capsule_ui != null:
			_capsule_ui.queue_free()
			_capsule_ui = null
		return

	_capsule_ui = Control.new()
	_capsule_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_capsule_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_capsule_ui)
	# A slab behind the words. Type over a busy render is unreadable at the
	# 231x87 size Steam also renders this at.
	var slab := ColorRect.new()
	slab.color = Color(0.05, 0.09, 0.11, 0.62)
	UIKit.place(slab, Control.PRESET_CENTER_LEFT, 0, -240, 640, 480)
	_capsule_ui.add_child(slab)

	var v := UIKit.vbox(2)
	UIKit.place(v, Control.PRESET_CENTER_LEFT, 52, -186, 540, 372)
	var t := UIKit.title("CHRONIC", 92, Color(0.62, 0.96, 0.90))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(t)
	var t2 := UIKit.title("CARE", 92, Color(0.98, 0.99, 0.99))
	t2.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(t2)
	v.add_child(UIKit.spacer(14))
	var rule := ColorRect.new()
	rule.color = Color(0.62, 0.96, 0.90, 0.85)
	rule.custom_minimum_size.y = 3
	v.add_child(rule)
	v.add_child(UIKit.spacer(12))
	var tag := UIKit.label("You are paid by the night.\nNobody is getting better.",
		27, Color(0.93, 0.96, 0.97), HORIZONTAL_ALIGNMENT_LEFT, true)
	v.add_child(tag)
	_capsule_ui.add_child(v)

var _capsule_ui: Control = null

func _new_career() -> void:
	var s := 0
	if _seed_field and _seed_field.text.strip_edges() != "":
		var txt := _seed_field.text.strip_edges()
		s = int(txt) if txt.is_valid_int() else hash(txt)
	# ASK FIRST IF THERE IS SOMETHING TO DESTROY.
	#
	# There is one save slot. "New Career" is the big dark-filled button and
	# "Continue — Day 9" sits directly under it, so the misclick is one row and
	# it silently erases eight or nine completed shifts with no way back.
	if SaveSystem.has_save(SaveSystem.AUTOSAVE) and not _confirming:
		_confirming = true
		_ask_before_erasing(s)
		return
	_confirming = false
	GameState.start_new_career(s)
	SaveSystem.delete_save(SaveSystem.AUTOSAVE)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

var _confirming := false

func _ask_before_erasing(s: int) -> void:
	# AUTOSAVE is a String slot name, not an index.
	var what := "your current career"
	for row in SaveSystem.list_saves():
		if String(row.get("slot", "")) == SaveSystem.AUTOSAVE:
			what = "Day %d" % int(row.get("day", 1))
			break
	var ui: Node = get_node_or_null("MenuUI")
	if ui == null:
		ui = load("res://scripts/ui/ui_root.gd").new()
		ui.name = "MenuUI"
		ui.set("menu_mode", true)
		add_child(ui)
	var card := Control.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_child(UIKit.dim_background())
	var panel := UIKit.center_panel(560, 260)
	card.add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)
	v.add_child(UIKit.title("START AGAIN?", 26, UIKit.BAD))
	v.add_child(UIKit.label(
		"This erases %s. There is only one save and it does not come back."
			% what, 15, UIKit.INK, HORIZONTAL_ALIGNMENT_LEFT, true))
	v.add_child(UIKit.spacer(6))
	v.add_child(UIKit.button("Erase it and start again", func():
		card.queue_free()
		_new_career(), Color(0.30, 0.16, 0.16)))
	v.add_child(UIKit.button("Keep my career", func():
		_confirming = false
		card.queue_free()))
	ui.add_child(card)

func _continue() -> void:
	GameState.set_flag("continue_save", true)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

## The options screen, from the title. UIRoot lives inside the game scene, so
## the menu builds its own instance of it rather than reaching for one that
## does not exist yet — a player should not have to start a career to turn the
## volume down.
func _open_menu_screen(id: String) -> void:
	# ONE menu UI, reused. A fresh UIRoot per visit stacked another CanvasLayer
	# on the title screen every time somebody opened Settings and came back.
	var ui: Node = get_node_or_null("MenuUI")
	if ui == null:
		ui = load("res://scripts/ui/ui_root.gd").new()
		ui.name = "MenuUI"
		# Set before add_child, so `_ready` sees it and never builds a HUD.
		ui.set("menu_mode", true)
		add_child(ui)
	ui.open(id, {})
