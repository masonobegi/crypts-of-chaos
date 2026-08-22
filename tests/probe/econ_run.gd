extends SceneTree
func _initialize() -> void:
	var i = load("res://tests/probe/econ_impl.gd").new(); i.tree = self; i.run(); quit()
