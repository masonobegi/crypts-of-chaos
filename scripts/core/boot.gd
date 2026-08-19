extends Node
## Entry point. Kept deliberately thin: it exists so the project always has a
## valid main scene while the rest of the game is under construction.

func _ready() -> void:
	Log.i("Chronic Care booting", "Boot")
	var main_menu := "res://scenes/MainMenu.tscn"
	if ResourceLoader.exists(main_menu):
		get_tree().change_scene_to_file(main_menu)
	else:
		Log.w("MainMenu not built yet — staying on Boot", "Boot")
