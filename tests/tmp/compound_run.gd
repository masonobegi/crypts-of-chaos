extends SceneTree
func _initialize() -> void:
	load("res://tests/tmp/compound_impl.gd").new().run()
	quit()
