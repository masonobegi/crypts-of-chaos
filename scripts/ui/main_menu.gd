extends Control
## Title screen. Also where a run's seed gets chosen, so a good shift can be
## shared with a number.

var _seed_field: LineEdit = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The title screen had no sound at all, which is the first thing anybody
	# hears of this game and it was nothing.
	AudioMgr.play_music("evening")
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := UIKit.center_panel(660, 780)
	add_child(panel)
	var v := UIKit.vbox(10)
	panel.add_child(v)

	v.add_child(UIKit.title("CHRONIC CARE", 44, UIKit.ACCENT))
	v.add_child(UIKit.label("A broke doctor. A struggling hospital.\nPatients who really should have gone home by now.",
		16, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.rule())

	v.add_child(UIKit.button("New Career", _new_career, Color(0.16, 0.32, 0.30)))
	if SaveSystem.has_save(SaveSystem.AUTOSAVE):
		var info := SaveSystem.list_saves()
		var label := "Continue"
		for s in info:
			if String(s["slot"]) == SaveSystem.AUTOSAVE:
				label = "Continue — Day %d, %s" % [int(s["day"]), UIKit.money_str(int(s["money"]))]
		v.add_child(UIKit.button(label, _continue))

	if Meta.runs_completed > 0:
		v.add_child(UIKit.rule())
		v.add_child(UIKit.row("Careers finished", str(Meta.runs_completed)))
		v.add_child(UIKit.row("Endings found", "%d of %d" % [
			Meta.endings_found(), Endings.ENDINGS.size()], UIKit.ACCENT))
		v.add_child(UIKit.row("Best earnings", UIKit.money_str(Meta.best_earnings), UIKit.MONEY))
		var unlocked := Meta.unlocked_perks()
		if not unlocked.is_empty():
			v.add_child(UIKit.label("STARTING PERK", 13, UIKit.INK_DIM))
			var none_btn := UIKit.button("None", func(): _pick_perk(""),
				UIKit.PANEL_LIGHT if Meta.selected_perk != "" else Color(0.20, 0.35, 0.38))
			v.add_child(none_btn)
			for id in unlocked:
				var perk_id := id
				var b := UIKit.button(Meta.perk_name(perk_id), func(): _pick_perk(perk_id),
					UIKit.PANEL_LIGHT if Meta.selected_perk != perk_id else Color(0.20, 0.35, 0.38))
				b.tooltip_text = Meta.perk_desc(perk_id)
				v.add_child(b)
			if Meta.selected_perk != "":
				v.add_child(UIKit.label(Meta.perk_desc(Meta.selected_perk), 12, UIKit.INK_DIM,
					HORIZONTAL_ALIGNMENT_LEFT, true))

	v.add_child(UIKit.button("Settings", func(): _open_settings()))
	v.add_child(UIKit.spacer(10))
	v.add_child(UIKit.label("Run seed (optional)", 13, UIKit.INK_DIM))
	_seed_field = LineEdit.new()
	_seed_field.placeholder_text = "leave blank for random"
	_seed_field.add_theme_font_size_override("font_size", 15)
	v.add_child(_seed_field)

	v.add_child(UIKit.spacer(10))
	v.add_child(UIKit.rule())
	v.add_child(UIKit.label(
		"WASD move · E use · LMB grab · RMB throw · Q tablet · Esc pause",
		13, UIKit.INK_DIM, HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.label(
		"Everything in this game is fictional and extremely stupid on purpose.",
		12, Color(1, 1, 1, 0.28), HORIZONTAL_ALIGNMENT_CENTER))
	v.add_child(UIKit.button("Quit", func(): get_tree().quit()))

func _new_career() -> void:
	var s := 0
	if _seed_field and _seed_field.text.strip_edges() != "":
		var txt := _seed_field.text.strip_edges()
		s = int(txt) if txt.is_valid_int() else hash(txt)
	GameState.start_new_career(s)
	Meta.apply_perk()
	SaveSystem.delete_save(SaveSystem.AUTOSAVE)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _pick_perk(id: String) -> void:
	Meta.select_perk(id)
	for c in get_children():
		c.queue_free()
	call_deferred("_ready")

func _continue() -> void:
	GameState.set_flag("continue_save", true)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

## The options screen, from the title. UIRoot lives inside the game scene, so
## the menu builds its own instance of it rather than reaching for one that
## does not exist yet — a player should not have to start a career to turn the
## volume down.
func _open_settings() -> void:
	var ui: Node = load("res://scripts/ui/ui_root.gd").new()
	ui.name = "MenuUI"
	add_child(ui)
	ui.open("settings", {})
