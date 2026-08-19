extends Node
## Entry point. Kept deliberately thin: it exists so the project always has a
## valid main scene while the rest of the game is under construction.

func _ready() -> void:
	Log.i("Chronic Care booting", "Boot")
	var main_menu := "res://scenes/MainMenu.tscn"
	if not ResourceLoader.exists(main_menu):
		Log.w("MainMenu not built yet — staying on Boot", "Boot")
		return
	# Deferred, because this runs inside the boot scene's own _ready(): the tree
	# is still in the middle of adding this node's children, and swapping the
	# scene from there makes the engine print
	#   "Parent node is busy adding/removing children, remove_child() can't be
	#    called at this time"
	# on every single launch of the game. Nothing in the test suite went through
	# the real entry point — every harness instantiates Game.tscn directly — so
	# the first line of output the shipped build produced was an engine error,
	# and no test had ever seen it.
	get_tree().change_scene_to_file.call_deferred(main_menu)
