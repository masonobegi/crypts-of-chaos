extends SceneTree
func _initialize() -> void:
	var i = load("res://tests/probe/rx3_impl.gd").new(); i.tree = self; i.run(); quit()
