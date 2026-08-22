extends SceneTree
func _initialize() -> void:
	var i = load("res://tests/probe/rx2_impl.gd").new(); i.tree = self; i.run(); quit()
