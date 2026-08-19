extends Control
## Title screen. Also where a run's seed gets chosen, so a good shift can be
## shared with a number.

var _seed_field: LineEdit = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.09, 0.11)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var panel := UIKit.center_panel(620, 560)
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
	SaveSystem.delete_save(SaveSystem.AUTOSAVE)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")

func _continue() -> void:
	GameState.set_flag("continue_save", true)
	get_tree().change_scene_to_file("res://scenes/Game.tscn")
